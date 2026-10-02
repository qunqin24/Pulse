// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The Cline CLI's session store.
///
/// A root holds one directory per session with a `<session>.messages.json`
/// transcript and a sibling `<session>.json` manifest. Only assistant messages
/// that carry a `metrics` object count. The store's `inputTokens` is
/// **cache-inclusive**, so the fresh input is what is left after the two cache
/// counts are removed — clamped at zero rather than allowed to go negative.
///
/// Roots come from the environment first, in the order the CLI itself checks
/// them; blank or whitespace values are ignored rather than treated as a path.
/// A missing `ts` is not backfilled from a file's date: the message is simply
/// not a record, and the honest result is fewer records rather than a wrong
/// hour.
enum ClineCLIReader {
    static let supportedClients: Set<String> = ["cline"]

    static func inputs(home: URL, environment: [String: String]) -> [URL] {
        if let value = EditorLog.nonBlank(environment["CLINE_SESSION_DATA_DIR"]) {
            return [URL(fileURLWithPath: value)]
        }
        if let value = EditorLog.nonBlank(environment["CLINE_DATA_DIR"]) {
            return [URL(fileURLWithPath: value).appending(path: "sessions")]
        }
        if let value = EditorLog.nonBlank(environment["CLINE_DIR"]) {
            return [URL(fileURLWithPath: value).appending(path: "data/sessions")]
        }
        return [home.appending(path: ".cline/data/sessions")]
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["json"])
            .filter { $0.lastPathComponent.hasSuffix(".messages.json") }
        return files.sorted { $0.path < $1.path }.flatMap(parse)
    }

    // MARK: - One session

    private static func parse(_ file: URL) -> [AgentUsageRecord] {
        let stem = String(file.lastPathComponent.dropLast(".messages.json".count))
        guard let root = AgentLogIO.object(AgentLogIO.json(at: file)) else { return [] }

        let manifest = AgentLogIO.object(
            AgentLogIO.json(at: file.deletingLastPathComponent().appending(path: "\(stem).json"))
        )
        let messages = (root["messages"] as? [[String: Any]]) ?? []

        let session = EditorLog.nonBlank(AgentLogIO.text(root["sessionId"]))
            ?? EditorLog.nonBlank(AgentLogIO.text(manifest?["sessionId"]))
            ?? stem
        let project = EditorLog.project(
            AgentLogIO.text(manifest?["workspace_root"]) ?? AgentLogIO.text(manifest?["cwd"])
        )
        let title = AgentLogIO.object(manifest?["metadata"]).flatMap {
            EditorLog.nonBlank(AgentLogIO.text($0["title"]))
        }
        let manifestModel = EditorLog.nonBlank(AgentLogIO.text(manifest?["model"]))

        var records: [AgentUsageRecord] = []
        for (index, message) in messages.enumerated() {
            guard
                AgentLogIO.text(message["role"]) == "assistant",
                let metrics = AgentLogIO.object(message["metrics"]),
                let timestamp = AgentLogIO.timestamp(message["ts"], milliseconds: true)
            else { continue }

            let cacheRead = EditorLog.int(metrics["cacheReadTokens"])
            let cacheWrite = EditorLog.int(metrics["cacheWriteTokens"])
            let tally = TokenTally(
                input: max(0, EditorLog.int(metrics["inputTokens"]) - cacheRead - cacheWrite),
                cacheWrite: cacheWrite,
                cacheRead: cacheRead,
                output: EditorLog.int(metrics["outputTokens"])
            )
            guard tally.total > 0 else { continue }

            let modelInfo = AgentLogIO.object(message["modelInfo"])
            guard
                let model = EditorLog.nonBlank(
                    AgentLogIO.text(modelInfo?["id"]) ?? manifestModel
                )
            else { continue }

            // The message's own id is the store's identity; a metadata-less
            // message still has a stable line position to tell it from its
            // neighbours.
            let messageID = EditorLog.nonBlank(AgentLogIO.text(message["id"])) ?? "line\(index)"
            records.append(
                EditorLog.record(
                    timestamp: timestamp,
                    model: model,
                    tally: tally,
                    sessionID: session,
                    title: title,
                    project: project,
                    deduplicationID: "cline:\(session):\(messageID)"
                )
            )
        }
        return records
    }
}
