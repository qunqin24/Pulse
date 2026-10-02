// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Mux's per-workspace usage snapshot.
///
/// `~/.mux/sessions/<workspaceId>/session-usage.json` holds one cumulative
/// session total per `"<provider>:<model>"` key:
///
/// ```json
/// { "version": 1,
///   "byModel": { "anthropic:claude": {
///     "input":       { "tokens": 10, "cost_usd": 0.01 },
///     "cached":      { "tokens": 20, "cost_usd": 0.00 },
///     "cacheCreate": { "tokens":  5, "cost_usd": 0.01 },
///     "output":      { "tokens": 30, "cost_usd": 0.10 },
///     "reasoning":   { "tokens":  7, "cost_usd": 0.01 } } },
///   "lastRequest": { "model": "claude", "timestamp": 1710000000000 } }
/// ```
///
/// **The snapshot is already one reading per model.** A single file read emits
/// one record per model whose key is the model, so the increment from nothing
/// is the whole snapshot; the builder's global dedup folds a workspace copied
/// into two roots.
///
/// **Reasoning is left out, not added and not carried as unknown.** The file
/// reports `output` and `reasoning` side by side and gives no token total, so
/// nothing on disk says whether reasoning is already inside `output`. Pulse's
/// output bucket counts reasoning once, so adding it would double it when it is
/// a subset, and putting it in `unclassifiedTokens` would add it to the grand
/// total just the same. With no total to check against, the reported output is
/// kept and the ambiguous reasoning figure is not counted at all — an
/// undercount the file cannot rule out, preferred to a guess in either
/// direction.
///
/// **One timestamp per session.** `lastRequest.timestamp` is when the session
/// last ran, shared by every model record, so the ledger must not draw an
/// hourly profile from it — every record is marked aggregate. A file with no
/// such timestamp is skipped rather than dated from its own modification time.
enum MuxUsageReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []

        for file in AgentLogIO.files(in: roots, names: ["session-usage.json"]) {
            guard let root = AgentLogIO.object(AgentLogIO.json(at: file)) else { continue }

            // The same timestamp is every model's; without a real one the
            // session has no date and is not guessed from the file.
            let lastRequest = AgentLogIO.object(root["lastRequest"])
            guard
                let timestamp = StructuredLogSupport.eventTime(
                    lastRequest?["timestamp"], milliseconds: true
                )
            else { continue }

            guard let byModel = AgentLogIO.object(root["byModel"]) else { continue }
            let sessionID = file.deletingLastPathComponent().lastPathComponent
            let fallbackModel = AgentLogIO.text(lastRequest?["model"])

            for key in byModel.keys.sorted() {
                guard let entry = AgentLogIO.object(byModel[key]) else { continue }
                let reasoning = bucket(entry, "reasoning") ?? 0
                let tally = TokenTally(
                    input: bucket(entry, "input") ?? 0,
                    cacheWrite: bucket(entry, "cacheCreate") ?? 0,
                    cacheRead: bucket(entry, "cached") ?? 0,
                    // No total exists to decide whether reasoning is inside
                    // output, so the reported output is kept and the separate
                    // reasoning count is not placed anywhere.
                    output: StructuredLogSupport.output(
                        reported: bucket(entry, "output") ?? 0,
                        reasoning: reasoning,
                        relationship: .unknown
                    )
                )
                let model = modelName(from: key) ?? fallbackModel
                // A reported reasoning count that could not be placed leaves
                // the record short of the session's real work; say so.
                let omittedReasoning = reasoning > 0

                guard
                    let record = StructuredLogSupport.record(
                        timestamp: timestamp,
                        model: model,
                        tally: tally,
                        isAggregate: true,
                        isPartial: omittedReasoning,
                        sessionID: sessionID,
                        sessionName: sessionID,
                        deduplicationID: "mux:\(sessionID):\(key)"
                    )
                else { continue }
                records.append(record)
            }
        }

        return records
    }

    /// `"<provider>:<model>"` → the model after the first colon. The provider
    /// is routing, not part of the model's name, and is dropped rather than
    /// folded into a key no price list could match.
    private static func modelName(from key: String) -> String? {
        guard let colon = key.firstIndex(of: ":") else {
            return StructuredLogSupport.nonBlank(key)
        }
        let model = key[key.index(after: colon)...]
        return StructuredLogSupport.nonBlank(String(model))
    }

    /// A named bucket's `tokens`, where the bucket is `{ tokens, cost_usd }`.
    private static func bucket(_ entry: [String: Any], _ key: String) -> Int? {
        guard let object = AgentLogIO.object(entry[key]) else { return nil }
        return AgentLogIO.count(object["tokens"])
    }
}
