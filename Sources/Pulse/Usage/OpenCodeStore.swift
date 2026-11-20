// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreFoundation
import Foundation
import SQLite3

/// OpenCode's store, and Kilo CLI's — the same schema, because Kilo is a fork
/// of it down to the migrations.
///
/// ```sql
/// session(id, project_id, slug, directory, title, …)
/// message(id, session_id, time_created, time_updated, data)
/// ```
///
/// `data` is the message as JSON, and an assistant's carries everything a
/// ledger needs:
///
/// ```json
/// { "role": "assistant", "modelID": "mimo-v2.5", "providerID": "…",
///   "cost": 0, "time": { "created": 1777654926954 },
///   "tokens": { "total": 10812, "input": 9705, "output": 11,
///               "reasoning": 72, "cache": { "write": 0, "read": 1024 } } }
/// ```
///
/// **OpenCode 2 moved both tables.** Messages go to
/// `session_message(id, session_id, type, seq, time_created, time_updated, data)`
/// and sessions to `session_v2`; the upgrade copied the history across under
/// the same ids and stopped writing `message` (on the Mac this was found on,
/// `message` ended 2026-09-19 and every request since was missing). A 2 row's
/// role is the `type` column, not a `role` in `data`, and its model is
/// `"model": { "id": "gpt-6.1-sol", "providerID": "openai" }` rather than
/// `modelID`. Both tables are read, and a message id is counted once from the
/// latest readable row by `time_updated`. Ties or incomparable timestamps
/// keep the new layout, including when its usage is zero. A store without the
/// new tables (OpenCode 1, Kilo CLI) reads exactly as before.
///
/// **Its own `cost` is ignored.** It is whatever OpenCode's own table said at
/// the time, is zero for a plan it has no rate for, and would put two
/// differently-sourced figures in one total. Everything here is priced from
/// `ModelPrices` like the rest of the page.
///
/// **Reasoning tokens are counted as output**, which is where every price list
/// bills them and where the two CLIs' own counts already put them.
enum OpenCodeStore {
    static func ledger(at file: URL, prices: [String: ModelPrice], vendor: String? = nil) -> UsageLedger {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return .empty
        }
        defer { sqlite3_close(handle) }

        let sessions = Self.sessions(handle)

        var buckets: [String: [String: TokenTally]] = [:]
        var perSession: [String: (tally: TokenTally, cost: Double, unpriced: Int, start: Date, end: Date)] = [:]
        // A session resumed across days is several quarter-hours, and the
        // project totals need to be able to count only the ones inside the
        // span on screen.
        var sessionSlots: [String: [String: (tokens: Int, cost: Double, unpriced: Int)]] = [:]
        let calendar = Calendar.current

        var messages: [String: Message] = [:]
        var anonymous: [Message] = []
        var lookup = ModelPriceLookup(prices)
        let rows: (OpaquePointer?) -> Void = { statement in
            guard
                let sessionText = sqlite3_column_text(statement, 1),
                let dataText = sqlite3_column_text(statement, 2)
            else { return }
            let session = String(cString: sessionText)
            let json = Data(String(cString: dataText).utf8)
            guard
                let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                // OpenCode 2 states the role in its own column, selected as
                // the fourth; OpenCode 1 in the message.
                (sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? root["role"] as? String) == "assistant",
                let model = root["modelID"] as? String ?? (root["model"] as? [String: Any])?["id"] as? String,
                let counts = root["tokens"] as? [String: Any],
                Self.readableCounts(counts),
                let at = Self.date(in: root)
            else { return }

            let cache = counts["cache"] as? [String: Any] ?? [:]
            let tally = TokenTally(
                input: Self.int(counts["input"]),
                cacheWrite: Self.int(cache["write"]),
                cacheRead: Self.int(cache["read"]),
                // OpenCode 2 states the role in its own column; OpenCode 1's
                // `message` rows are the ones old enough to have no total.
                output: Self.output(counts, int: Self.int, totallessFolded: sqlite3_column_text(statement, 3) == nil)
            )
            let message = Message(session: session, model: model, at: at, tally: tally,
                                  updated: Self.updated(statement))
            // Validate before deduplication, but keep a readable zero: it can
            // supersede an older positive count. Never select by token total.
            if let idText = sqlite3_column_text(statement, 0) {
                let id = String(cString: idText)
                if let previous = messages[id] {
                    guard let old = previous.updated, let new = message.updated, new > old else { return }
                }
                messages[id] = message
            } else {
                // Historical layouts without ids cannot be matched across tables.
                anonymous.append(message)
            }
        }
        for (table, role) in [("session_message", "type"), ("message", "NULL")] {
            let columns = Self.columns(handle, table)
            let id = columns.contains("id") ? "id" : "NULL"
            let updated = columns.contains("time_updated") ? "time_updated" : "NULL"
            let filter = table == "session_message" ? " WHERE type = 'assistant'" : ""
            Self.each(handle, "SELECT \(id), session_id, data, \(role), \(updated) FROM \(table)\(filter)", rows)
        }

        for message in Array(messages.values) + anonymous {
            let (session, model, at, tally) = (message.session, message.model, message.at, message.tally)
            guard tally.total > 0 else { continue }
            let price = lookup.price(for: model, vendor: vendor)
            let cost = price.map { tally.cost(at: $0) } ?? 0
            let unpriced = price == nil ? tally.total : 0
            let key = UsageLedgerReader.slotKey(for: at)
            buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally

            var slot = sessionSlots[session, default: [:]][key] ?? (tokens: 0, cost: 0, unpriced: 0)
            slot.tokens += tally.total
            slot.cost += cost
            slot.unpriced += unpriced
            sessionSlots[session, default: [:]][key] = slot

            if var running = perSession[session] {
                running.tally = running.tally + tally
                running.cost += cost
                running.unpriced += unpriced
                running.start = min(running.start, at)
                running.end = max(running.end, at)
                perSession[session] = running
            } else {
                perSession[session] = (tally, cost, unpriced, at, at)
            }
        }

        guard !buckets.isEmpty else { return .empty }

        var ledger = UsageLedgerReader.price(buckets, with: prices, calendar: calendar, vendor: vendor)
        ledger.sessions = perSession
            .compactMap { id, totals in
                let session = sessions[id]
                return UsageLedger.Session(
                    id: "\(file.path)#\(id)",
                    name: session?.slug ?? id,
                    title: session?.title,
                    project: UsageProject(session?.directory),
                    start: totals.start,
                    end: totals.end,
                    tokens: totals.tally.total,
                    cost: totals.cost,
                    unpricedTokens: totals.unpriced,
                    slots: UsageLedgerReader.sessionSlots(sessionSlots[id] ?? [:])
                )
            }
            .sorted { $0.end > $1.end }

        return ledger
    }

    // MARK: - The tables

    private struct Message {
        var session: String
        var model: String
        var at: Date
        var tally: TokenTally
        var updated: Double?
    }

    /// Missing optional counters still mean zero, but malformed counters must
    /// not turn an unreadable copy into a zero that hides valid usage.
    private static func readableCounts(_ counts: [String: Any]) -> Bool {
        let cache = counts["cache"] as? [String: Any] ?? [:]
        if let value = counts["cache"], !(value is [String: Any]) { return false }
        let values = [counts["input"], counts["output"], counts["reasoning"], cache["read"], cache["write"]]
            .compactMap { $0 }
        return !values.isEmpty && values.allSatisfy { value in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
            let count = number.doubleValue
            return count.isFinite && count >= 0 && count < Double(Int.max) && count.rounded(.down) == count
        }
    }

    /// Both upstream layouts write epoch milliseconds here. Creation and
    /// completion times describe the request, not the last database update.
    /// Missing, nonnumeric and nonpositive values cannot establish recency.
    private static func updated(_ statement: OpaquePointer?) -> Double? {
        let type = sqlite3_column_type(statement, 4)
        guard type == SQLITE_INTEGER || type == SQLITE_FLOAT else { return nil }
        let value = sqlite3_column_double(statement, 4)
        return value.isFinite && value > 0 ? value : nil
    }

    private struct Session {
        var slug: String?
        var title: String?
        var directory: String?
    }

    /// OpenCode 2's `session_v2` first, then `session` for any it lacks.
    private static func sessions(_ handle: OpaquePointer?) -> [String: Session] {
        var rows: [String: Session] = [:]
        let read: (OpaquePointer?) -> Void = { statement in
            guard let id = sqlite3_column_text(statement, 0) else { return }
            let key = String(cString: id)
            guard rows[key] == nil else { return }
            rows[key] = Session(
                slug: sqlite3_column_text(statement, 1).map { String(cString: $0) },
                title: sqlite3_column_text(statement, 2).map { String(cString: $0) },
                directory: sqlite3_column_text(statement, 3).map { String(cString: $0) }
            )
        }
        each(handle, "SELECT id, slug, title, directory FROM session_v2", read)
        each(handle, "SELECT id, slug, title, directory FROM session", read)
        return rows
    }

    private static func columns(_ handle: OpaquePointer?, _ table: String) -> Set<String> {
        var names: Set<String> = []
        each(handle, "PRAGMA table_info(\(table))") { statement in
            if let name = sqlite3_column_text(statement, 1) { names.insert(String(cString: name)) }
        }
        return names
    }

    /// Read-only and in place, the same way Pulse reads every other
    /// application's store: the agent may be running and its journal belongs
    /// to that process.
    private static func each(
        _ handle: OpaquePointer?,
        _ sql: String,
        _ row: (OpaquePointer?) -> Void
    ) {
        guard let handle else { return }
        AgentSQLite.each(handle, sql: sql) { row($0) }
    }

    /// `time.created` in milliseconds, with the row's own column as the
    /// fallback for a message that carries no time of its own.
    private static func date(in root: [String: Any]) -> Date? {
        guard let time = root["time"] as? [String: Any] else { return nil }
        let created = int(time["created"])
        guard created > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(created) / 1000)
    }


    /// Output with its reasoning, counted once.
    ///
    /// **Two shapes under one name.** Current OpenCode (and Kilo, and MiMo
    /// Code, which share its store) reports reasoning **beside** output, and
    /// `total` is input, output, reasoning and cache together. Older rows
    /// folded reasoning **into** output and left it out of `total`; adding it
    /// again counted it twice (632 rows on the Mac this was found on). So:
    ///
    /// - reasoning larger than output cannot be inside it, and is added;
    /// - a `total` decides where there is one;
    /// - without one, `totallessFolded` does. OpenCode 1's `message` rows that
    ///   predate `total` all have output at least their reasoning — 78 of 78
    ///   here, where a fifth of later rows with reasoning beside output do
    ///   not — so they are the folded shape. OpenCode 2's `session_message`
    ///   carries no `total` at all and keeps reasoning beside output.
    static func output(_ counts: [String: Any], int: (Any?) -> Int, totallessFolded: Bool = false) -> Int {
        let output = int(counts["output"]), reasoning = int(counts["reasoning"])
        guard reasoning > 0, output >= reasoning else { return output + reasoning }
        let cache = counts["cache"] as? [String: Any] ?? [:]
        let total = int(counts["total"])
        guard total > 0 else {
            // Only a row with no total at all is OpenCode 1's old shape; a
            // total written as zero says nothing either way.
            let stated = counts["total"].map { !($0 is NSNull) } ?? false
            return totallessFolded && !stated ? output : output + reasoning
        }
        let folded = total == int(counts["input"]) + output + int(cache["read"]) + int(cache["write"])
        return folded ? output : output + reasoning
    }
    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}
