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
        var perSession: [String: (tally: TokenTally, cost: Double, start: Date, end: Date)] = [:]
        // A session resumed across days is several quarter-hours, and the
        // project totals need to be able to count only the ones inside the
        // span on screen.
        var sessionSlots: [String: [String: (tokens: Int, cost: Double)]] = [:]
        let calendar = Calendar.current

        Self.each(handle, "SELECT session_id, data FROM message") { statement in
            guard
                let sessionText = sqlite3_column_text(statement, 0),
                let dataText = sqlite3_column_text(statement, 1)
            else { return }

            let session = String(cString: sessionText)
            let json = Data(String(cString: dataText).utf8)
            guard
                let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                root["role"] as? String == "assistant",
                let model = root["modelID"] as? String,
                let counts = root["tokens"] as? [String: Any],
                let at = Self.date(in: root)
            else { return }

            let cache = counts["cache"] as? [String: Any] ?? [:]
            let tally = TokenTally(
                input: Self.int(counts["input"]),
                cacheWrite: Self.int(cache["write"]),
                cacheRead: Self.int(cache["read"]),
                output: Self.int(counts["output"]) + Self.int(counts["reasoning"])
            )
            guard tally.total > 0 else { return }

            let cost = ModelPrices.price(for: model, in: prices, vendor: vendor).map { tally.cost(at: $0) } ?? 0
            let key = UsageLedgerReader.slotKey(for: at)
            buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally

            var slot = sessionSlots[session, default: [:]][key] ?? (tokens: 0, cost: 0)
            slot.tokens += tally.total
            slot.cost += cost
            sessionSlots[session, default: [:]][key] = slot

            if var running = perSession[session] {
                running.tally = running.tally + tally
                running.cost += cost
                running.start = min(running.start, at)
                running.end = max(running.end, at)
                perSession[session] = running
            } else {
                perSession[session] = (tally, cost, at, at)
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
                    slots: UsageLedgerReader.sessionSlots(sessionSlots[id] ?? [:])
                )
            }
            .sorted { $0.end > $1.end }

        return ledger
    }

    // MARK: - The tables

    private struct Session {
        var slug: String?
        var title: String?
        var directory: String?
    }

    private static func sessions(_ handle: OpaquePointer?) -> [String: Session] {
        var rows: [String: Session] = [:]
        each(handle, "SELECT id, slug, title, directory FROM session") { statement in
            guard let id = sqlite3_column_text(statement, 0) else { return }
            rows[String(cString: id)] = Session(
                slug: sqlite3_column_text(statement, 1).map { String(cString: $0) },
                title: sqlite3_column_text(statement, 2).map { String(cString: $0) },
                directory: sqlite3_column_text(statement, 3).map { String(cString: $0) }
            )
        }
        return rows
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

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}
