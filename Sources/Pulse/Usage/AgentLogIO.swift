// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CryptoKit
import Foundation
import os

/// Read-only helpers for the files an agent leaves behind.
///
/// Every reader that parses a transcript, a capture or a dropped log needs the
/// same handful of things: walk a set of known roots without walking the whole
/// home, tolerate a half-written line, and only ever turn an actually-decoded
/// value into a number. This is that handful, so a new client does not
/// reimplement it — and, more to the point, so two readers cannot disagree
/// about what "malformed" or "missing" means.
///
/// **Nothing here invents a value.** A missing key is nil, not zero; a broken
/// line is skipped, not repaired; a timestamp is never guessed from a file's
/// modification date or the clock. A caller that cannot read its store says so
/// rather than showing a figure nobody measured.
enum AgentLogIO {
    // MARK: - Files

    /// Every regular file under `roots` that matches the filters.
    ///
    /// `roots` may name directories or files; callers pass the **specific,
    /// known** places their agent writes rather than a broad tree. A directory
    /// is walked recursively, hidden files and hidden subdirectories included,
    /// so a dot-directory store is not silently empty. SQLite's `-shm`
    /// sidecar is excluded everywhere: it is shared memory a read touches.
    ///
    /// With both `extensions` and `names` empty every regular file matches.
    /// When either is non-empty a file matches if it satisfies **either**
    /// filter, so `extensions: ["jsonl"], names: ["state.json"]` takes both.
    ///
    /// Roots and results are normalized and symlink-resolved for ordering and
    /// de-duplication, so a path reachable two ways is one file.
    static func files(
        in roots: [URL],
        extensions: Set<String> = [],
        names: Set<String> = [],
        excludingRootDirectories: Set<String> = []
    ) -> [URL] {
        let manager = FileManager.default
        let wantsExtension = !extensions.isEmpty
        let wantsName = !names.isEmpty

        var seenRoots: Set<String> = []
        let ordered = roots
            .map { $0.standardizedFileURL }
            .sorted { $0.path < $1.path }
            .filter { seenRoots.insert($0.path).inserted }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        var candidates: [URL] = []

        for root in ordered {
            guard !Task.isCancelled else { return [] }
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                guard let walker = manager.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsPackageDescendants]
                ) else { continue }

                while let file = autoreleasepool(invoking: { walker.nextObject() as? URL }) {
                    guard !Task.isCancelled else { return [] }
                    if !excludingRootDirectories.isEmpty,
                       file.deletingLastPathComponent().standardizedFileURL == root,
                       excludingRootDirectories.contains(file.lastPathComponent),
                       (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        walker.skipDescendants()
                        continue
                    }
                    guard matches(
                        file, extensions: extensions, names: names,
                        wantsExtension: wantsExtension, wantsName: wantsName
                    ) else { continue }
                    guard
                        let values = try? file.resourceValues(forKeys: Set(keys)),
                        values.isRegularFile == true
                    else { continue }
                    candidates.append(file.standardizedFileURL)
                }
            } else {
                guard matches(
                    root, extensions: extensions, names: names,
                    wantsExtension: wantsExtension, wantsName: wantsName
                ) else { continue }
                guard
                    let values = try? root.resourceValues(forKeys: Set(keys)),
                    values.isRegularFile == true
                else { continue }
                candidates.append(root)
            }
        }

        var resolved: [(canonical: String, url: URL)] = []
        for file in candidates {
            guard !Task.isCancelled else { return [] }
            resolved.append(autoreleasepool {
                (canonical: file.resolvingSymlinksInPath().path, url: file)
            })
        }
        resolved.sort { lhs, rhs in
            if lhs.canonical == rhs.canonical { return lhs.url.path < rhs.url.path }
            return lhs.canonical < rhs.canonical
        }
        var seen: Set<String> = []
        var files: [URL] = []
        for file in resolved where seen.insert(file.canonical).inserted {
            guard !Task.isCancelled else { return [] }
            files.append(file.url)
        }
        return files
    }

    private static func matches(
        _ url: URL,
        extensions: Set<String>,
        names: Set<String>,
        wantsExtension: Bool,
        wantsName: Bool
    ) -> Bool {
        if url.lastPathComponent.hasSuffix("-shm") { return false }
        if !wantsExtension, !wantsName { return true }
        if wantsExtension, extensions.contains(url.pathExtension) { return true }
        if wantsName, names.contains(url.lastPathComponent) { return true }
        return false
    }

    // MARK: - JSON

    /// Exact whole-file identity without faulting an entire mapped transcript
    /// into memory. Cancellation stops between chunks, as it does for lines.
    static func digest(at url: URL) -> String? {
        guard !Task.isCancelled, let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var hash = SHA256()
        do {
            while !Task.isCancelled {
                let data = try autoreleasepool { try file.read(upToCount: 64 * 1024) }
                // Foundation may use nil rather than empty Data for EOF.
                guard let data, !data.isEmpty else {
                    return hash.finalize().map { String(format: "%02x", Int($0)) }.joined()
                }
                hash.update(data: data)
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Parses a whole file as JSON. Malformed content or unreadable bytes are
    /// nil, never a partial value.
    static func json(at url: URL) -> Any? {
        guard !Task.isCancelled else { return nil }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        guard !Task.isCancelled else { return nil }
        let value = autoreleasepool { try? JSONSerialization.jsonObject(with: data) }
        return Task.isCancelled ? nil : value
    }

    /// Lazily parses JSONL objects, skipping any line that is not one. Each
    /// iteration opens its own stream; conversation payloads are not retained
    /// in a whole-file array before the caller can extract usage counters.
    ///
    /// A log being appended to can end mid-line, and one corrupt row must not
    /// cost the rest. Non-object JSON (an array, a bare number) is skipped for
    /// the same reason the caller wants objects.
    static func jsonLines(at url: URL) -> AnySequence<[String: Any]> {
        AnySequence {
            let lines = LogLines(at: url).makeIterator()
            return AnyIterator {
                while let line = lines.next() {
                    let object: [String: Any]? = autoreleasepool {
                        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
                    }
                    if let object { return object }
                }
                return nil
            }
        }
    }

    /// A JSON object, or nil for anything that is not one.
    static func object(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    /// A non-blank string, trimmed. Whitespace-only is nil rather than a name.
    static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Numbers

    /// A token count, or nil.
    ///
    /// Only a finite, non-negative whole number that fits an `Int` is a count.
    /// A decimal, an overflowed value, a boolean and a missing key all come
    /// back nil — **and nil is not zero**: a figure that was never written is
    /// not a figure of nothing. Nothing here traps on a hostile value.
    static func count(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return int(from: number) }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Int(trimmed), parsed >= 0 else { return nil }
            return parsed
        }
        return nil
    }

    /// A whole number's `Int`, or nil for a boolean, a fraction or an overflow.
    ///
    /// `NSNumber.objCType` is what keeps this from trapping: `c` is how a
    /// boolean is stored and is refused outright, an integer type is read
    /// through its exact `Int64`/`UInt64`, and a floating type is accepted only
    /// when `Int(exactly:)` says it is a whole number in range.
    private static func int(from number: NSNumber) -> Int? {
        switch UInt8(bitPattern: number.objCType.pointee) {
        case UInt8(ascii: "c"):
            return nil
        case UInt8(ascii: "i"), UInt8(ascii: "s"), UInt8(ascii: "l"), UInt8(ascii: "q"):
            let value = number.int64Value
            guard value >= 0, let result = Int(exactly: value) else { return nil }
            return result
        case UInt8(ascii: "C"), UInt8(ascii: "I"), UInt8(ascii: "S"),
             UInt8(ascii: "L"), UInt8(ascii: "Q"):
            guard let result = Int(exactly: number.uint64Value) else { return nil }
            return result
        case UInt8(ascii: "f"), UInt8(ascii: "d"):
            let value = number.doubleValue
            guard value.isFinite, value >= 0, let result = Int(exactly: value) else { return nil }
            return result
        default:
            return nil
        }
    }

    // MARK: - Time

    /// A timestamp, or nil.
    ///
    /// An ISO 8601 string is read with or without fractional seconds and with
    /// or without a timezone offset. A number — or a string that is exactly a
    /// number — is read in the unit the caller states: **seconds by default,
    /// milliseconds only when asked**, never guessed from the magnitude. A
    /// non-finite number and a value a `Date` cannot hold are both nil. The
    /// clock and a file's modification date are never used to fill a gap.
    static func timestamp(_ value: Any?, milliseconds: Bool = false) -> Date? {
        guard !Task.isCancelled, let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let number = Double(trimmed) { return date(from: number, milliseconds: milliseconds) }
            return Self.iso(trimmed)
        }

        if let number = value as? NSNumber {
            // A boolean is not a timestamp; `c` is how it is stored.
            guard UInt8(bitPattern: number.objCType.pointee) != UInt8(ascii: "c") else { return nil }
            return date(from: number.doubleValue, milliseconds: milliseconds)
        }

        return nil
    }

    private static func date(from number: Double, milliseconds: Bool) -> Date? {
        guard number.isFinite else { return nil }
        let seconds = milliseconds ? number / 1000 : number
        guard seconds.isFinite else { return nil }
        let date = Date(timeIntervalSince1970: seconds)
        guard date.timeIntervalSince1970.isFinite else { return nil }
        return date
    }

    /// ISO8601DateFormatter is not Sendable. Keep the two parsers behind a lock
    /// rather than constructing them for every record in a large transcript.
    private struct ISOParsers {
        let fraction: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        let plain = ISO8601DateFormatter()
    }

    private static let isoParsers = OSAllocatedUnfairLock(uncheckedState: ISOParsers())

    private static func iso(_ text: String) -> Date? {
        isoParsers.withLock { $0.fraction.date(from: text) ?? $0.plain.date(from: text) }
    }
}
