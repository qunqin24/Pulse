// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import SQLite3

/// Paths, numbers, timestamps and record construction shared by the readers
/// in this directory.
///
/// These are the readers for agents Pulse did not previously understand: the
/// ones that keep a database or an event log rather than a Claude-shaped
/// transcript. They are kept here, one file per product, so none of them grows
/// into the whole layer — and every one of them is read-only, so a product
/// that is running while Pulse looks at its store is never written to.
///
/// **Nothing here invents a value.** A missing column is nil, a malformed blob
/// is skipped, and a timestamp is never filled in from the clock or a file's
/// modification date. A reader that cannot decode its store says so by
/// producing no records rather than a zero.
enum DatabaseReaderSupport {
    // MARK: - Paths

    /// A non-empty environment value, or nil.
    static func environment(_ key: String, _ environment: [String: String]) -> String? {
        guard let value = environment[key], !value.isEmpty else { return nil }
        return value
    }

    static func directory(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    /// `$XDG_DATA_HOME`, else `~/.local/share`.
    static func xdgDataHome(home: URL, environment: [String: String]) -> URL {
        if let value = Self.environment("XDG_DATA_HOME", environment) {
            return Self.directory(value)
        }
        return home.appending(path: ".local/share", directoryHint: .isDirectory)
    }

    static func applicationSupport(home: URL) -> URL {
        home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    /// `%LOCALAPPDATA%` when the environment names it. Absent on this platform,
    /// where it stays nil rather than becoming a fabricated path.
    static func localAppData(environment: [String: String]) -> URL? {
        Self.environment("LOCALAPPDATA", environment).map(Self.directory)
    }

    /// `%APPDATA%` when the environment names it.
    static func appData(environment: [String: String]) -> URL? {
        Self.environment("APPDATA", environment).map(Self.directory)
    }

    /// The first candidate that exists, in the order given. Nil when none do.
    static func firstExisting(_ candidates: [URL]) -> URL? {
        candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    /// The immediate subdirectories of a directory, ordered by name. Empty when
    /// the directory is missing or unreadable.
    static func subdirectories(of directory: URL) -> [URL] {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        else { return [] }
        return entries
            .filter(Self.isDirectory)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Numbers

    /// A finite number, from a JSON number or a numeric string. A boolean is
    /// not a number. Nil when absent.
    static func number(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            guard UInt8(bitPattern: number.objCType.pointee) != UInt8(ascii: "c") else { return nil }
            return number.doubleValue.isFinite ? number.doubleValue : nil
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Double(trimmed), parsed.isFinite else { return nil }
            return parsed
        }
        return nil
    }

    /// A token count from JSON, clamped at zero. A missing value is zero here
    /// **only for arithmetic that already knows it is adding a bucket** — the
    /// distinction between "absent" and "zero" is made by the caller looking at
    /// the key first. A negative value is clamped rather than subtracted.
    static func clampedCount(_ value: Any?) -> Int {
        guard let number = Self.number(value) else { return 0 }
        guard number > 0 else { return 0 }
        guard let count = Int(exactly: number.rounded(.towardZero)) else { return 0 }
        return count
    }

    /// An integer column, or nil for NULL or an out-of-range value.
    static func intColumn(_ statement: OpaquePointer, _ column: Int32) -> Int? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_int64(statement, column)
        guard value >= 0, let result = Int(exactly: value) else { return nil }
        return result
    }

    /// A numeric column, or nil for NULL.
    static func numberColumn(_ statement: OpaquePointer, _ column: Int32) -> Double? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_double(statement, column)
        return value.isFinite ? value : nil
    }

    /// The column names of a table. Empty when the table does not exist, which
    /// is how a reader built against one schema stays silent against another.
    static func columns(_ database: OpaquePointer, of table: String) -> Set<String> {
        var names: Set<String> = []
        AgentSQLite.each(database, sql: "PRAGMA table_info(\(table))") { statement in
            if let name = AgentSQLite.text(statement, column: 1) { names.insert(name) }
        }
        return names
    }

    // MARK: - Time

    /// A numeric epoch in **seconds or milliseconds**.
    ///
    /// Values below `1e12` are seconds, at or above are already milliseconds —
    /// the same threshold Hermes and Crush state. Zero and negatives are nil:
    /// an unset column is not 1970, and a record must not be bucketed on a
    /// date nobody wrote.
    static func epoch(_ raw: Double) -> Date? {
        guard raw.isFinite, raw > 0 else { return nil }
        let seconds = raw < 1e12 ? raw : raw / 1000
        guard seconds.isFinite else { return nil }
        let date = Date(timeIntervalSince1970: seconds)
        guard date.timeIntervalSince1970.isFinite else { return nil }
        return date
    }

    /// A timestamp from either an ISO 8601 string or a numeric epoch.
    ///
    /// Numeric strings are read as epochs **before** the ISO parser sees them,
    /// because `AgentLogIO.timestamp` would read `"1789372800000"` as seconds
    /// and land it in the year 58,000 rather than the millisecond it is.
    static func flexible(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let number = Double(trimmed), number.isFinite { return Self.epoch(number) }
            return AgentLogIO.timestamp(trimmed)
        }
        if let number = Self.number(value) { return Self.epoch(number) }
        return nil
    }

    /// A timestamp from a stated string format, in UTC, after ISO 8601.
    ///
    /// Used for the formats RFC 3339 does not cover — Goose writes
    /// `yyyy-MM-dd HH:mm:ss` and `yyyy-MM-dd`.
    static func utc(_ text: String, formats: [String]) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = AgentLogIO.timestamp(trimmed) { return date }
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// A filename stem, percent-decoded where it is a directory encoded as one.
    static func stem(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Records

    /// A record from a reader, carrying the pieces the native builders added
    /// to this boundary.
    ///
    /// `unclassifiedTokens` is **reported-but-unattributed** work: a bare
    /// session total, or the remainder of a total the explicit kinds do not
    /// explain. It is counted and never split into a kind or turned into
    /// money. `isAggregate` marks a record that is one product's cumulative
    /// session total rather than a per-request increment, so a consumer can
    /// tell the two apart.
    ///
    /// `isPartial` marks a record whose read is a **known subset** of what the
    /// product did — an ambiguous cache or reasoning figure left out rather
    /// than guessed — so a summary can say so instead of presenting the subset
    /// as a complete total. It is never used to add or guess a token; a client
    /// with no such doubt leaves it false.
    ///
    /// A method on this support type rather than an extension on
    /// `AgentUsageRecord`, so two independent reader families cannot collide
    /// on the same extension member.
    static func record(
        at timestamp: Date,
        model: String,
        tally: TokenTally = TokenTally(),
        unclassifiedTokens: Int = 0,
        sessionID: String? = nil,
        sessionName: String? = nil,
        title: String? = nil,
        project: String? = nil,
        deduplicationID: String? = nil,
        isAggregate: Bool = false,
        isPartial: Bool = false
    ) -> AgentUsageRecord {
        AgentUsageRecord(
            timestamp: timestamp,
            model: model,
            tally: tally,
            sessionID: sessionID,
            sessionName: sessionName,
            title: title,
            project: project,
            deduplicationID: deduplicationID,
            unclassifiedTokens: unclassifiedTokens,
            isAggregate: isAggregate,
            isPartial: isPartial
        )
    }
}
