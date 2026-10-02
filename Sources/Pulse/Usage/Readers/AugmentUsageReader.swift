// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Augment's per-session chat history.
///
/// `~/.augment/sessions/<sessionId>.json` holds `sessionId`,
/// `agentState.modelId` and `chatHistory[]`. Each turn is
/// `{ "finishedAt", "completed", "sequenceId",
///    "exchange": { "model_id", "request_id",
///                  "response_nodes": [{ "token_usage": {...} }] } }`.
///
/// **Only completed turns count.** An aborted or in-progress turn can carry a
/// partial streamed total; emitting it would put a snapshot of work that never
/// finished into the ledger.
///
/// **The last non-empty `token_usage` wins, never the sum.** A turn's response
/// is streamed as several nodes whose usage is cumulative; adding them would
/// multiply the turn. The final node that reported anything is the turn's own
/// total.
///
/// Input and cache are independent here — the format does not fold one into the
/// other — so they are read straight across. Augment credits are a cost, not a
/// kind, and are left for Pulse's price table. `finishedAt` is the only time
/// the turn has, so timing is end-anchored and there is no duration.
enum AugmentUsageReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []

        for file in AgentLogIO.files(in: roots, extensions: ["json"]) {
            guard let session = AgentLogIO.object(AgentLogIO.json(at: file)) else { continue }

            let sessionID = AgentLogIO.text(session["sessionId"]) ?? file.deletingPathExtension().lastPathComponent
            let agentModel = AgentLogIO.object(session["agentState"]).flatMap { AgentLogIO.text($0["modelId"]) }

            guard let turns = session["chatHistory"] as? [[String: Any]] else { continue }

            for (index, turn) in turns.enumerated() {
                // `completed` must be exactly true; absent or false is not a
                // finished turn.
                guard (turn["completed"] as? Bool) == true else { continue }
                guard let exchange = AgentLogIO.object(turn["exchange"]) else { continue }
                guard
                    let usage = lastUsage(in: exchange),
                    let timestamp = StructuredLogSupport.eventTime(turn["finishedAt"])
                else { continue }

                let tally = TokenTally(
                    input: AgentLogIO.count(usage["input_tokens"]) ?? 0,
                    cacheWrite: AgentLogIO.count(usage["cache_creation_input_tokens"]) ?? 0,
                    cacheRead: AgentLogIO.count(usage["cache_read_input_tokens"]) ?? 0,
                    output: AgentLogIO.count(usage["output_tokens"]) ?? 0
                )

                let model = AgentLogIO.text(exchange["model_id"]) ?? agentModel
                let identity = AgentLogIO.text(exchange["request_id"])
                    ?? AgentLogIO.text(turn["sequenceId"])
                    ?? String(index)

                guard
                    let record = StructuredLogSupport.record(
                        timestamp: timestamp,
                        model: model,
                        tally: tally,
                        sessionID: sessionID,
                        sessionName: sessionID,
                        deduplicationID: "augment:\(sessionID):\(identity)"
                    )
                else { continue }
                records.append(record)
            }
        }

        return records
    }

    /// The last `response_nodes` entry whose `token_usage` reports anything.
    private static func lastUsage(in exchange: [String: Any]) -> [String: Any]? {
        guard let nodes = exchange["response_nodes"] as? [[String: Any]] else { return nil }
        for node in nodes.reversed() {
            guard let usage = AgentLogIO.object(node["token_usage"]) else { continue }
            let tally = TokenTally(
                input: AgentLogIO.count(usage["input_tokens"]) ?? 0,
                cacheWrite: AgentLogIO.count(usage["cache_creation_input_tokens"]) ?? 0,
                cacheRead: AgentLogIO.count(usage["cache_read_input_tokens"]) ?? 0,
                output: AgentLogIO.count(usage["output_tokens"]) ?? 0
            )
            if tally.total > 0 { return usage }
        }
        return nil
    }
}
