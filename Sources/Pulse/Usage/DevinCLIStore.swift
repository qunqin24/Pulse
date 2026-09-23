import Foundation
import SQLite3

/// Devin's CLI, which keeps its conversations in SQLite.
///
/// `message_nodes.chat_message` is the message as JSON, and an assistant's
/// carries its own metrics:
///
/// ```json
/// { "role": "assistant", "metadata": {
///     "generation_model": "…", "created_at": …,
///     "metrics": { "input_tokens": 11486, "output_tokens": 254,
///                  "cache_read_tokens": 6450, "cache_creation_tokens": null } } }
/// ```
///
/// **Not the same store as the quota route.** `DevinUsageService` reads the
/// desktop app's saved plan for the ring; this is the CLI's own transcript
/// database, and the two know nothing about each other.
enum DevinCLIStore {
    static func ledger(at file: URL, prices: [String: ModelPrice]) -> UsageLedger {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return .empty
        }
        defer { sqlite3_close(handle) }

        var directories: [String: (directory: String?, title: String?)] = [:]
        Self.each(handle, "SELECT id, working_directory, title FROM sessions") { statement in
            guard let id = sqlite3_column_text(statement, 0) else { return }
            directories[String(cString: id)] = (
                sqlite3_column_text(statement, 1).map { String(cString: $0) },
                sqlite3_column_text(statement, 2).map { String(cString: $0) }
            )
        }

        var buckets: [String: [String: TokenTally]] = [:]
        var perSession: [String: (tokens: Int, cost: Double, start: Date, end: Date)] = [:]
        var sessionSlots: [String: [String: (tokens: Int, cost: Double)]] = [:]

        Self.eachUsage(handle) { session, model, at, tally in
            let key = UsageLedgerReader.slotKey(for: at)
            buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally

            let cost = ModelPrices.price(for: model, in: prices).map { tally.cost(at: $0) } ?? 0

            var slot = sessionSlots[session, default: [:]][key] ?? (tokens: 0, cost: 0)
            slot.tokens += tally.total
            slot.cost += cost
            sessionSlots[session, default: [:]][key] = slot

            if var running = perSession[session] {
                running.tokens += tally.total
                running.cost += cost
                running.start = min(running.start, at)
                running.end = max(running.end, at)
                perSession[session] = running
            } else {
                perSession[session] = (tally.total, cost, at, at)
            }
        }

        guard !buckets.isEmpty else { return .empty }

        var ledger = UsageLedgerReader.price(buckets, with: prices)
        ledger.sessions = perSession.map { id, totals in
            let session = directories[id]
            return UsageLedger.Session(
                id: "\(file.path)#\(id)",
                name: id,
                title: session?.title,
                project: UsageProject(session?.directory),
                start: totals.start,
                end: totals.end,
                tokens: totals.tokens,
                cost: totals.cost,
                slots: UsageLedgerReader.sessionSlots(sessionSlots[id] ?? [:])
            )
        }
        .sorted { $0.end > $1.end }

        return ledger
    }

    /// Only sessions this reader can actually count suppress their Desktop
    /// mirror. A metadata row, an empty metrics object or an undated message
    /// is not usage. Share the exact parser so the two routes cannot disagree.
    static func countedSessionIDs(in database: OpaquePointer?) -> Set<String> {
        var ids: Set<String> = []
        eachUsage(database) { session, _, _, _ in ids.insert(session) }
        return ids
    }

    private static func eachUsage(
        _ database: OpaquePointer?,
        _ consume: (String, String, Date, TokenTally) -> Void
    ) {
        each(database, "SELECT session_id, chat_message, created_at FROM message_nodes") { statement in
            guard
                let sessionText = sqlite3_column_text(statement, 0),
                let messageText = sqlite3_column_text(statement, 1),
                let root = try? JSONSerialization.jsonObject(with: Data(String(cString: messageText).utf8)) as? [String: Any],
                let metadata = root["metadata"] as? [String: Any],
                let metrics = metadata["metrics"] as? [String: Any]
            else { return }

            let tally = TokenTally(
                input: int(metrics["input_tokens"]),
                cacheWrite: int(metrics["cache_creation_tokens"]),
                cacheRead: int(metrics["cache_read_tokens"]),
                output: int(metrics["output_tokens"])
            )
            guard tally.total > 0 else { return }
            let seconds = Double(sqlite3_column_int64(statement, 2))
            let at = Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
            guard at.timeIntervalSince1970 > 0 else { return }
            consume(String(cString: sessionText), metadata["generation_model"] as? String ?? "devin", at, tally)
        }
    }

    private static func each(
        _ handle: OpaquePointer?,
        _ sql: String,
        _ row: (OpaquePointer?) -> Void
    ) {
        guard let handle else { return }
        AgentSQLite.each(handle, sql: sql) { row($0) }
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}
