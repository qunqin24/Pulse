// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The Hindsight ledger: a JSONL mirror of a self-hosted memory service's
/// `llm-requests`, one record per line.
///
/// The service's own table is a rolling window — records are evicted as it runs
/// — so the durable copy is the JSONL an authenticated sync writes. Pulse reads
/// that ledger, never the service.
///
/// **A user-edited file is untrusted.** A line that will not decode, a row with
/// no `id` or `started_at`, a row whose stated total asserts no usage, or a row
/// with neither input nor output is skipped rather than guessed at.
enum CapturedHindsightReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["jsonl"])
        var records: [AgentUsageRecord] = []
        for file in files {
            records.append(contentsOf: Self.records(at: file))
        }
        return records
    }

    private static func records(at url: URL) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []
        for line in AgentLogIO.jsonLines(at: url) {
            // The id is the ledger's dedup identity; without it a re-synced
            // row cannot be folded, so it is required.
            guard
                let id = AgentLogIO.text(line["id"]),
                let model = AgentLogIO.text(line["model"]),
                let at = AgentLogIO.timestamp(line["started_at"])
            else { continue }

            // A stated total of zero or less asserts no usage.
            if let total = AgentLogIO.count(line["total_tokens"]), total <= 0 { continue }

            let input = AgentLogIO.count(line["input_tokens"]) ?? 0
            let output = AgentLogIO.count(line["output_tokens"]) ?? 0
            guard input > 0 || output > 0 else { continue }

            // `cached_tokens` is the cache-read bucket; it is null in practice
            // on the Ollama path, so it is usually zero. Cache write is not
            // reported. Reasoning is never split out on this path — the
            // completion count already includes it — so output stays as stated.
            let tally = TokenTally(
                input: input,
                cacheWrite: 0,
                cacheRead: AgentLogIO.count(line["cached_tokens"]) ?? 0,
                output: output
            )

            var record = AgentUsageRecord(timestamp: at, model: model, tally: tally)
            record.sessionID = AgentLogIO.text(line["trace_id"]) ?? id
            record.deduplicationID = "hindsight:\(id)"
            // The bank is the workspace the record ran against; operation and
            // scope describe the call.
            record.project = AgentLogIO.text(line["bank"])
            record.title = title(
                operation: AgentLogIO.text(line["operation"]),
                scope: AgentLogIO.text(line["scope"])
            )
            records.append(record)
        }
        return records
    }

    /// `operation / scope` where both are present and differ, otherwise
    /// whichever one the ledger stated.
    private static func title(operation: String?, scope: String?) -> String? {
        switch (operation, scope) {
        case let (operation?, scope?):
            return operation == scope ? operation : "\(operation) / \(scope)"
        case let (operation?, nil):
            return operation
        case let (nil, scope?):
            return scope
        default:
            return nil
        }
    }
}
