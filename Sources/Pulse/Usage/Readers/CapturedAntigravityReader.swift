// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The Antigravity **IDE** cache: one JSON object per line, written by pulling
/// usage from a running Antigravity language server.
///
/// It is not a native local usage log. The cache is produced by an authenticated
/// sync against the language server, and Pulse reads that cache rather than
/// talking to the server itself. It must not be confused with `antigravity-cli`,
/// a different product that keeps its own conversation databases.
///
/// `session_meta` supplies a fallback model for the `usage` rows that follow it
/// in the same file; a row that names no model and has no fallback is skipped,
/// because a token count with no model cannot be priced or attributed and must
/// not be filed under an invented name.
///
/// **Reasoning is not silently folded into output.** This schema does not state
/// whether `reasoning` is already part of `output`; adding it would double-count
/// a subset and dropping it would undercount a separate bucket. So `output`
/// stays exactly as reported, `reasoning` is not placed in any bucket, and the
/// record is marked `isPartial` so the ambiguity is visible rather than guessed
/// away.
enum CapturedAntigravityReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["jsonl"])
        var records: [AgentUsageRecord] = []
        for file in files {
            records.append(contentsOf: Self.records(at: file))
        }
        return records
    }

    private static func records(at url: URL) -> [AgentUsageRecord] {
        var fallbackModel: String?
        var records: [AgentUsageRecord] = []

        for line in AgentLogIO.jsonLines(at: url) {
            guard let type = AgentLogIO.text(line["type"]) else { continue }

            if type == "session_meta" {
                fallbackModel = AgentLogIO.text(line["modelId"])
                continue
            }
            guard type == "usage" else { continue }

            guard
                let session = AgentLogIO.text(line["sessionId"]),
                let at = AgentLogIO.timestamp(line["timestamp"], milliseconds: true),
                at.timeIntervalSince1970 > 0
            else { continue }

            guard
                let model = AgentLogIO.text(line["modelId"]) ?? fallbackModel,
                !isPlaceholder(model)
            else { continue }

            // Negative counts clamp to zero. An all-zero row asserts no usage
            // and is dropped.
            let tally = TokenTally(
                input: clamp(line["input"]),
                cacheWrite: clamp(line["cacheWrite"]),
                cacheRead: clamp(line["cacheRead"]),
                output: clamp(line["output"])
            )
            guard tally.total > 0 else { continue }

            var record = AgentUsageRecord(timestamp: at, model: model, tally: tally)
            record.sessionID = session
            // A separate reasoning figure may or may not already be inside
            // `output`; it is neither added nor counted, and the record says it
            // may be incomplete.
            if clamp(line["reasoning"]) > 0 { record.isPartial = true }
            if let response = AgentLogIO.text(line["responseId"]) {
                // The response id is the cache's own identity for the call; a
                // re-sync of the same response folds here.
                record.deduplicationID = "antigravity:\(response)"
            }
            records.append(record)
        }
        return records
    }

    /// A count that cannot be read is zero, and a negative clamps to zero:
    /// this format states every bucket, so an absent one is a real zero rather
    /// than an unknown.
    private static func clamp(_ value: Any?) -> Int {
        max(0, AgentLogIO.count(value) ?? 0)
    }

    /// Placeholder ids name no model Pulse can resolve without the sync's own
    /// alias table, so they are skipped rather than passed on as a price key
    /// that could collide.
    private static func isPlaceholder(_ model: String) -> Bool {
        model.lowercased().hasPrefix("model_placeholder_")
    }
}
