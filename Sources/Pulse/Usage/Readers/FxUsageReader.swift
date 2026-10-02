// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Fx's per-session usage snapshot.
///
/// `~/.fx/sessions/<sessionId>/usage-v2.json` holds a `snapshot` and a `models`
/// array; `session.json` in the same directory carries the session's timing and
/// workspace, and `~/.fx/sessions/index.json` carries its title.
///
/// **One record per model**, each a cumulative session total, so the whole
/// snapshot is the increment and the builder folds a session reached twice. A
/// snapshot whose `models` array is empty but whose aggregate has usage still
/// emits once under `fx-unknown`, so totals are not lost when the product
/// groups nothing.
///
/// **Reasoning is left out, not added and not counted as unknown.** Fx reports
/// a per-model `reasoning_tokens` beside `output_tokens` and states no token
/// total, so nothing says whether reasoning is already inside output. Pulse's
/// output bucket counts reasoning once: adding it would double it when it is a
/// subset, and carrying it in `unclassifiedTokens` would add it to the grand
/// total all the same. The reported output is kept and the ambiguous reasoning
/// figure is not counted — an undercount rather than a guess.
///
/// **One timestamp per session**, `updated_at_ms` else `created_at_ms`; a
/// snapshot with neither is skipped. Every model record is marked aggregate
/// because none has its own call time.
///
/// `total_cost` is Fx's own dollars and is not read as tokens. The global
/// `~/.fx/usage.jsonl` stream has no session id or workspace and is not scanned.
enum FxUsageReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []
        let titles = titles(roots)

        for file in AgentLogIO.files(in: roots, names: ["usage-v2.json"]) {
            guard let root = AgentLogIO.object(AgentLogIO.json(at: file)) else { continue }
            guard let snapshot = AgentLogIO.object(root["snapshot"]) else { continue }

            let directory = file.deletingLastPathComponent()
            let sessionID = AgentLogIO.text(root["session_id"]) ?? directory.lastPathComponent
            let sidecar = AgentLogIO.object(
                AgentLogIO.json(at: directory.appending(path: "session.json"))
            )

            // A zero `updated_at_ms` is "unset", so `created_at_ms` is tried.
            guard
                let timestamp = StructuredLogSupport.eventTime(
                    sidecar?["updated_at_ms"], milliseconds: true
                )
                    ?? StructuredLogSupport.eventTime(
                        sidecar?["created_at_ms"], milliseconds: true
                    )
            else { continue }

            let workspace = AgentLogIO.text(sidecar?["workspace_root"])
            let title = titles[sessionID]

            if let models = snapshot["models"] as? [[String: Any]], !models.isEmpty {
                for entry in models {
                    let reasoning = AgentLogIO.count(entry["reasoning_tokens"]) ?? 0
                    let tally = TokenTally(
                        input: AgentLogIO.count(entry["input_tokens"]) ?? 0,
                        cacheWrite: AgentLogIO.count(entry["cache_write_tokens"]) ?? 0,
                        cacheRead: AgentLogIO.count(entry["cache_read_tokens"]) ?? 0,
                        output: StructuredLogSupport.output(
                            reported: AgentLogIO.count(entry["output_tokens"]) ?? 0,
                            reasoning: reasoning,
                            relationship: .unknown
                        )
                    )
                    let model = AgentLogIO.text(entry["model"]) ?? "fx-unknown"
                    guard
                        let record = StructuredLogSupport.record(
                            timestamp: timestamp,
                            model: model,
                            tally: tally,
                            isAggregate: true,
                            isPartial: reasoning > 0,
                            sessionID: sessionID,
                            sessionName: sessionID,
                            title: title,
                            project: StructuredLogSupport.project(workspace),
                            deduplicationID: "fx:\(sessionID):\(model)"
                        )
                    else { continue }
                    records.append(record)
                }
            } else {
                let reasoning = AgentLogIO.count(snapshot["reasoning_tokens"]) ?? 0
                let tally = TokenTally(
                    input: AgentLogIO.count(snapshot["input_tokens"]) ?? 0,
                    cacheWrite: AgentLogIO.count(snapshot["cache_write_tokens"]) ?? 0,
                    cacheRead: AgentLogIO.count(snapshot["cache_read_tokens"]) ?? 0,
                    output: StructuredLogSupport.output(
                        reported: AgentLogIO.count(snapshot["output_tokens"]) ?? 0,
                        reasoning: reasoning,
                        relationship: .unknown
                    )
                )
                guard
                    let record = StructuredLogSupport.record(
                        timestamp: timestamp,
                        model: "fx-unknown",
                        tally: tally,
                        isAggregate: true,
                        isPartial: reasoning > 0,
                        sessionID: sessionID,
                        sessionName: sessionID,
                        title: title,
                        project: StructuredLogSupport.project(workspace),
                        deduplicationID: "fx:\(sessionID):fx-unknown"
                    )
                else { continue }
                records.append(record)
            }
        }

        return records
    }

    /// `index.json`'s `sessions[<id>].title`, where present.
    private static func titles(_ roots: [URL]) -> [String: String] {
        var titles: [String: String] = [:]
        for file in AgentLogIO.files(in: roots, names: ["index.json"]) {
            guard
                let root = AgentLogIO.object(AgentLogIO.json(at: file)),
                let sessions = AgentLogIO.object(root["sessions"])
            else { continue }
            for (id, value) in sessions {
                if let title = AgentLogIO.text(AgentLogIO.object(value)?["title"]) {
                    titles[id] = title
                }
            }
        }
        return titles
    }
}
