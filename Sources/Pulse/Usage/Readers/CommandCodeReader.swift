// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// CommandCode's transcripts.
///
/// One JSONL per session under `projects/<slug>/`. The modern format is a
/// **tree**: every entry names a `parentId`, and `/rewind` moves the leaf while
/// the abandoned replies keep their usage on disk. Replies on every branch
/// carry real work: rewinding context does not refund tokens already
/// consumed. Message identities fold replays; ancestry only resolves the model
/// a reply used, so a model change on another branch cannot reprice it.
///
/// The modern `usage` object names all four buckets and is cache-exclusive.
/// The legacy flat format has no tree and may carry no usage at all; where it
/// does not, there is **no estimate** — token counts from string lengths are
/// not reported tokens, so those lines contribute nothing.
enum CommandCodeReader {
    static let supportedClients: Set<String> = ["commandcode"]

    static func inputs(home: URL) -> [URL] {
        [
            home.appending(path: ".commandcode/projects"),
            // The legacy model fallback lives here and is read, so it is an
            // input too.
            home.appending(path: ".commandcode/config.json"),
        ]
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let configModel = configModel(in: roots)
        let files = AgentLogIO.files(in: roots, extensions: ["jsonl"])
            .filter { !$0.lastPathComponent.hasSuffix(".checkpoints.jsonl") }
        return files.sorted { $0.path < $1.path }.flatMap { parse($0, configModel: configModel) }
    }

    // MARK: - One session

    private struct Entry {
        let index: Int
        let id: String?
        let parent: String?
        let type: String?
        let model: String?
        let role: String?
        let timestamp: Date?
        let session: String?
        let tally: TokenTally?
    }

    private static func parse(_ file: URL, configModel: String?) -> [AgentUsageRecord] {
        let stem = file.deletingPathExtension().lastPathComponent
        var headerSession: String?
        var entries: [Entry] = []

        for (index, row) in AgentLogIO.jsonLines(at: file).enumerated() {
            let type = AgentLogIO.text(row["type"])
            if type == "session" {
                headerSession = EditorLog.nonBlank(AgentLogIO.text(row["id"])) ?? headerSession
                continue
            }
            let message = AgentLogIO.object(row["message"])
            let role = EditorLog.nonBlank(AgentLogIO.text(message?["role"]))
                ?? EditorLog.nonBlank(AgentLogIO.text(row["role"]))
            let tally = AgentLogIO.object(row["usage"]).map { usage in
                TokenTally(
                    input: EditorLog.int(usage["inputTokens"]),
                    cacheWrite: EditorLog.int(usage["cacheWriteTokens"]),
                    cacheRead: EditorLog.int(usage["cacheReadTokens"]),
                    output: EditorLog.int(usage["outputTokens"])
                )
            }
            entries.append(
                Entry(
                    index: index,
                    id: EditorLog.nonBlank(AgentLogIO.text(row["id"])),
                    parent: EditorLog.nonBlank(AgentLogIO.text(row["parentId"])),
                    type: type,
                    model: EditorLog.modelID(AgentLogIO.text(row["model"])),
                    role: role,
                    timestamp: role == "assistant" ? AgentLogIO.timestamp(row["timestamp"]) : nil,
                    session: EditorLog.nonBlank(AgentLogIO.text(row["sessionId"])),
                    tally: tally
                )
            )
        }

        let hasTree = entries.contains { $0.parent != nil }
        var byID: [String: Entry] = [:]
        for entry in entries {
            guard !Task.isCancelled else { return [] }
            if let id = entry.id { byID[id] = entry }
        }
        var inheritedModels: [String: String] = [:]

        var records: [AgentUsageRecord] = []
        var currentModel: String?

        for entry in entries {
            guard !Task.isCancelled else { return [] }
            if entry.type == "model_change" {
                if let model = entry.model {
                    currentModel = model
                }
                continue
            }

            guard entry.role == "assistant", let timestamp = entry.timestamp, let tally = entry.tally else { continue }
            guard tally.total > 0 else { continue }

            guard
                let model = entry.model
                    ?? (hasTree ? ancestorModel(of: entry, entries: byID, cache: &inheritedModels) : currentModel)
                    ?? configModel
            else { continue }

            let session = headerSession
                ?? entry.session
                ?? stem
            // An explicit message id names the call even if an export changes
            // its timestamp. The builder folds replays across files once.
            let identity = entry.id.map { "commandcode:\(session):\($0)" }
                ?? "commandcode:\(session):line\(entry.index):\(timestamp.timeIntervalSince1970)"

            records.append(
                EditorLog.record(
                    timestamp: timestamp,
                    model: model,
                    tally: tally,
                    sessionID: session,
                    deduplicationID: identity
                )
            )
        }
        return records
    }

    /// The nearest stated model on this reply's own ancestry, not the last
    /// model change in file order. Memoized so long branches stay linear;
    /// missing parents and cycles stop without borrowing a sibling's model.
    private static func ancestorModel(
        of entry: Entry,
        entries: [String: Entry],
        cache: inout [String: String]
    ) -> String? {
        var visited: Set<String> = []
        var cursor = entry.parent
        var model: String?
        while let id = cursor, visited.insert(id).inserted {
            guard !Task.isCancelled else { return nil }
            if let cached = cache[id] { model = cached; break }
            guard let ancestor = entries[id] else { break }
            if let stated = ancestor.model {
                model = stated
                break
            }
            cursor = ancestor.parent
        }
        if let model {
            for id in visited { cache[id] = model }
        }
        return model
    }

    private static func configModel(in roots: [URL]) -> String? {
        for root in roots where root.lastPathComponent == "config.json" {
            if let object = AgentLogIO.object(AgentLogIO.json(at: root)),
               let model = EditorLog.modelID(AgentLogIO.text(object["model"])) {
                return model
            }
        }
        return nil
    }
}
