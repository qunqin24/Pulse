// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Unsloth Studio's database, `studio.db` under `$UNSLOTH_STUDIO_HOME` (else
/// `~/.unsloth/studio`). Two tables carry real counters.
///
/// **`chat_messages` is the measured chat path.** An assistant message's
/// `metadata_json` holds `$.contextUsage` (prompt, completion, total, cached,
/// cache-write and reasoning counters) and `$.responseDetails`. The counters
/// are normalized so the four emitted kinds add up to the reported total
/// exactly: a cache read is bounded by the prompt, a cache write by what the
/// read left, reasoning by the completion, and the total is raised to at least
/// `prompt + completion`. Reasoning is folded into output once, where every
/// price list bills it.
///
/// **`api_usage_events` is the measured API path**, with fewer buckets: no
/// cache and no reasoning columns exist, so those stay zero rather than being
/// guessed.
///
/// The server-supplied `providerType` route and the store's own cost are not
/// used: Pulse prices each model from `ModelPrices`, and a route name the
/// server can rename is not a price key. Rows with no readable timestamp or no
/// message identity are skipped, never dated 1970.
enum UnslothReader {
    static func inputs(home: URL, environment: [String: String]) -> [URL] {
        let root: URL
        if let value = DatabaseReaderSupport.environment("UNSLOTH_STUDIO_HOME", environment) {
            root = DatabaseReaderSupport.directory(value)
        } else {
            root = home.appending(path: ".unsloth/studio", directoryHint: .isDirectory)
        }
        return [root.appending(path: "studio.db")]
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        AgentLogIO.files(in: roots, names: ["studio.db"]).flatMap(read)
    }

    // MARK: - One database

    private static func read(_ file: URL) -> [AgentUsageRecord] {
        AgentSQLite.read(at: file) { database in
            chat(database) + api(database)
        } ?? []
    }

    /// The chat path. One record per assistant message.
    private static func chat(_ database: OpaquePointer) -> [AgentUsageRecord] {
        let messages = DatabaseReaderSupport.columns(database, of: "chat_messages")
        let threads = DatabaseReaderSupport.columns(database, of: "chat_threads")
        guard
            messages.contains("id"), messages.contains("thread_id"),
            messages.contains("role"), messages.contains("metadata_json"),
            messages.contains("created_at"),
            threads.contains("id"), threads.contains("model_id")
        else { return [] }

        var records: [AgentUsageRecord] = []
        let sql = """
        SELECT m.id, m.thread_id, m.metadata_json, m.created_at, t.model_id
        FROM chat_messages m JOIN chat_threads t ON m.thread_id = t.id
        WHERE m.role = 'assistant'
        """
        AgentSQLite.each(database, sql: sql) { statement in
            guard
                let messageID = AgentLogIO.text(AgentSQLite.text(statement, column: 0)),
                let createdAt = DatabaseReaderSupport.numberColumn(statement, 3),
                createdAt > 0,
                let timestamp = DatabaseReaderSupport.epoch(createdAt)
            else { return }

            let thread = AgentSQLite.text(statement, column: 1)
            let threadModel = AgentSQLite.text(statement, column: 4)
            guard
                let metadata = AgentSQLite.text(statement, column: 2),
                let root = try? JSONSerialization.jsonObject(with: Data(metadata.utf8)),
                let object = root as? [String: Any]
            else { return }

            let usage = object["contextUsage"] as? [String: Any] ?? [:]
            let details = object["responseDetails"] as? [String: Any] ?? [:]
            let model = AgentLogIO.text(details["responseModelId"])
                ?? AgentLogIO.text(usage["modelId"])
                ?? AgentLogIO.text(threadModel)
                ?? "unknown"

            let prompt = DatabaseReaderSupport.clampedCount(usage["promptTokens"])
            let completion = DatabaseReaderSupport.clampedCount(usage["completionTokens"])
            let cacheRead = min(DatabaseReaderSupport.clampedCount(usage["cachedTokens"]), prompt)
            let cacheWrite = min(
                DatabaseReaderSupport.clampedCount(usage["cacheWriteTokens"]), prompt - cacheRead
            )
            let total = max(DatabaseReaderSupport.clampedCount(usage["totalTokens"]), prompt + completion)
            guard total > 0 else { return }

            // Reasoning is part of the completion and is folded into output
            // once here, which is where every price list bills it.
            let fresh = total - completion - cacheRead - cacheWrite
            let tally = TokenTally(
                input: max(0, fresh),
                cacheWrite: cacheWrite,
                cacheRead: cacheRead,
                output: completion
            )

            records.append(
                DatabaseReaderSupport.record(
                    at: timestamp,
                    model: model,
                    tally: tally,
                    sessionID: thread ?? "unsloth:chat:\(messageID)",
                    deduplicationID: "unsloth:chat:\(messageID)"
                )
            )
        }
        return records
    }

    /// The external-API path. No cache and no reasoning columns exist here.
    private static func api(_ database: OpaquePointer) -> [AgentUsageRecord] {
        let columns = DatabaseReaderSupport.columns(database, of: "api_usage_events")
        guard
            columns.contains("id"), columns.contains("endpoint"),
            columns.contains("model"), columns.contains("prompt_tokens"),
            columns.contains("completion_tokens"), columns.contains("total_tokens"),
            columns.contains("created_at")
        else { return [] }

        var records: [AgentUsageRecord] = []
        let sql = """
        SELECT id, endpoint, model, prompt_tokens, completion_tokens, total_tokens, created_at
        FROM api_usage_events
        """
        AgentSQLite.each(database, sql: sql) { statement in
            guard
                let id = AgentLogIO.text(AgentSQLite.text(statement, column: 0)),
                let model = AgentLogIO.text(AgentSQLite.text(statement, column: 2)),
                let createdAt = DatabaseReaderSupport.numberColumn(statement, 6),
                createdAt > 0,
                let timestamp = DatabaseReaderSupport.epoch(createdAt)
            else { return }

            let prompt = DatabaseReaderSupport.intColumn(statement, 3) ?? 0
            let completion = DatabaseReaderSupport.intColumn(statement, 4) ?? 0
            let total = max(DatabaseReaderSupport.intColumn(statement, 5) ?? 0, prompt + completion)
            guard total > 0 else { return }

            let tally = TokenTally(
                input: max(0, total - completion),
                output: completion
            )
            records.append(
                DatabaseReaderSupport.record(
                    at: timestamp,
                    model: model,
                    tally: tally,
                    sessionID: "unsloth:api",
                    title: AgentLogIO.text(AgentSQLite.text(statement, column: 1)),
                    deduplicationID: "unsloth:api:\(id)"
                )
            )
        }
        return records
    }
}
