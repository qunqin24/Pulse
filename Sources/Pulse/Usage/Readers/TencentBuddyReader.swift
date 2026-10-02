// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// CodeBuddy and WorkBuddy, Tencent's coding agents.
///
/// Three shapes meet here and each is dispatched by the file it is found in:
/// a JSONL transcript under `projects/`, an extension log with a
/// `[AgentReporter]` usage line, and WorkBuddy's aggregate SQLite database.
/// The JSONL and log carry real per-request counts; the database carries only
/// one aggregate quantity per session, which is reported as
/// `unclassifiedTokens` rather than being passed off as fresh input.
///
/// **Nothing here estimates.** A transcript without a usage object is not a
/// record, and a database row is one session-level total placed on its real
/// timestamp — never spread across hours nobody measured.
///
/// **Only the JSONL is the reconcilable channel.** Its `messageId`, `traceId`
/// or line id folds a replayed message. When a transcript is present it is the
/// only thing returned: the extension log and the aggregate database share no
/// identity with its message ids, so appending them would double count. If the
/// excluded fallback held records, the transcript records are marked
/// `isPartial` because only a subset of the product's work could be confirmed.
///
/// **With no transcript, the fallback stands alone.** The extension log's
/// lines are counted one by one — a mirrored sink may still be counted twice,
/// but folding two same-second, same-count lines by timestamp would silently
/// drop a real request, which is the worse error.
enum TencentBuddyReader {
    static let supportedClients: Set<String> = ["codebuddy", "workbuddy"]

    static func inputs(client: String, home: URL) -> [URL] {
        switch client {
        case "codebuddy":
            // The product tree holds `projects/` transcripts and any extension
            // logs beneath it.
            return [home.appending(path: ".codebuddy")]
        case "workbuddy":
            // `workbuddy` is the 5.0 tree, `workbuddy-ai` the 5.5 one; both can
            // exist on one machine.
            return [home.appending(path: ".workbuddy"), home.appending(path: ".workbuddy-ai")]
        default:
            return []
        }
    }

    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(
            in: roots, extensions: ["jsonl", "log"], names: ["workbuddy.db"],
            excludingRootDirectories: ["binaries"]
        )

        var transcript: [AgentUsageRecord] = []
        for file in files where file.pathExtension == "jsonl" {
            guard !Task.isCancelled else { return [] }
            transcript += autoreleasepool { jsonl(client: client, file: file) }
        }

        // **The transcript wins and the fallback is not appended.** The
        // extension log and the aggregate database share no identity with the
        // transcript's message ids, so adding them would double count whatever
        // both channels saw. When the excluded fallback held records the
        // returned set is only the confirmed subset, and is marked partial so
        // the doubt is shown rather than stated in a comment and counted.
        var fallback: [AgentUsageRecord] = []
        for file in files where file.pathExtension != "jsonl" {
            guard !Task.isCancelled else { return [] }
            let read = autoreleasepool {
                file.pathExtension == "log"
                    ? extensionLog(client: client, file: file, firstOnly: !transcript.isEmpty)
                    : sqlite(client: client, file: file)
            }
            if !transcript.isEmpty, !read.isEmpty {
                // Only existence matters for the partial flag. No need to
                // decode/store millions of fallback rows we will not count.
                return transcript.map { marking($0, partial: true) }.sorted { $0.timestamp < $1.timestamp }
            }
            fallback += read
        }
        if !transcript.isEmpty { return transcript.sorted { $0.timestamp < $1.timestamp } }
        return fallback.sorted { $0.timestamp < $1.timestamp }
    }

    /// A copy of the record with its completeness flag set.
    private static func marking(_ record: AgentUsageRecord, partial: Bool) -> AgentUsageRecord {
        guard partial else { return record }
        var copy = record
        copy.isPartial = true
        return copy
    }

    // MARK: - JSONL transcript

    private static func jsonl(client: String, file: URL) -> [AgentUsageRecord] {
        let stem = file.deletingPathExtension().lastPathComponent
        var identified: [String: AgentUsageRecord] = [:]
        var unidentified: [AgentUsageRecord] = []

        for row in AgentLogIO.jsonLines(at: file) {
            guard let timestamp = AgentLogIO.timestamp(row["timestamp"], milliseconds: true) else { continue }

            let type = AgentLogIO.text(row["type"])
            let role = AgentLogIO.text(row["role"])
            guard (type == "message" && role == "assistant") || type == "function_call" else { continue }
            // A record the product itself calls incomplete is not counted.
            if let status = AgentLogIO.text(row["status"]), status != "completed" { continue }

            let message = AgentLogIO.object(row["message"]) ?? [:]
            let provider = AgentLogIO.object(row["providerData"]) ?? [:]
            guard
                let usage = AgentLogIO.object(message["usage"])
                    ?? AgentLogIO.object(provider["usage"])
                    ?? AgentLogIO.object(provider["rawUsage"])
            else { continue }

            let parts = transcriptUsage(usage)
            guard parts.tally.total + parts.unclassified > 0 else { continue }

            let session = EditorLog.nonBlank(AgentLogIO.text(row["sessionId"])) ?? stem
            let model = EditorLog.modelID(
                AgentLogIO.text(provider["model"])
                    ?? AgentLogIO.text(provider["requestModelId"])
                    ?? AgentLogIO.text(message["model"])
            ) ?? client

            let identity = AgentLogIO.text(provider["messageId"])
                ?? AgentLogIO.text(provider["traceId"])
                ?? AgentLogIO.text(row["id"])

            let record = EditorLog.record(
                timestamp: timestamp,
                model: model,
                tally: parts.tally,
                sessionID: session,
                project: EditorLog.project(AgentLogIO.text(row["cwd"])),
                deduplicationID: identity.map { "\(client):\(session):\($0)" },
                unclassifiedTokens: parts.unclassified
            )

            // Mirrored writes of one message land on one identity; the more
            // complete snapshot wins rather than both being added.
            if let identity = record.deduplicationID {
                if let existing = identified[identity], total(existing) >= total(record) {
                    continue
                }
                identified[identity] = record
            } else {
                unidentified.append(record)
            }
        }

        return Array(identified.values) + unidentified
    }

    private static func transcriptUsage(_ usage: [String: Any]) -> EditorLog.UsageParts {
        EditorLog.combine(
            input: EditorLog.firstCount(usage, ["input_tokens", "inputTokens", "prompt_tokens"]),
            output: EditorLog.firstCount(usage, ["output_tokens", "outputTokens", "completion_tokens"]),
            cacheRead: EditorLog.firstCount(usage, [
                "cache_read_input_tokens", "cacheReadInputTokens", "cacheTokens",
                "prompt_cache_hit_tokens", "cached_tokens",
            ]),
            cacheWrite: EditorLog.firstCount(usage, [
                "cache_creation_input_tokens", "cacheCreationInputTokens",
                "cachedWriteTokens", "prompt_cache_write_tokens",
            ]),
            reasoning: EditorLog.firstCount(usage, [
                "completion_thinking_tokens", "completionThinkingTokens", "reasoningTokens",
            ]),
            total: EditorLog.firstCount(usage, ["total_tokens", "totalTokens"]),
            exclusiveInput: EditorLog.firstCount(usage, ["cachedMissTokens", "cacheMissTokens"]),
            inputMayIncludeCache: true
        )
    }

    // MARK: - Extension log

    private static func extensionLog(client: String, file: URL, firstOnly: Bool = false) -> [AgentUsageRecord] {
        let workspace = file.lastPathComponent
            .components(separatedBy: "__").first
            .flatMap { EditorLog.nonBlank($0) }

        var models: [String: String] = [:]
        var records: [AgentUsageRecord] = []

        for line in LogLines(at: file) {
            guard let raw = String(data: line, encoding: .utf8),
                  raw.contains("[CraftInvokableAgent]") || raw.contains("[AgentReporter]") else { continue }
            guard let timestamp = EditorLog.naiveTimestamp(raw) else { continue }

            if let prepared = prepared(raw) {
                models[prepared.agent] = prepared.model
                continue
            }
            guard let reported = reported(raw) else { continue }

            let parts = extensionUsage(reported.usage)
            guard parts.tally.total + parts.unclassified > 0 else { continue }

            let model = EditorLog.modelID(models[reported.agent]) ?? client
            // The line carries no message, request or trace id, so it has no
            // business identity. Two real requests in the same second with the
            // same counts are therefore two records; folding them by the
            // timestamp would silently drop one. A mirrored duplicate is the
            // price of never losing a real request, and is reported as a
            // limitation rather than guessed away.
            records.append(
                EditorLog.record(
                    timestamp: timestamp,
                    model: model,
                    tally: parts.tally,
                    sessionID: reported.agent,
                    project: workspace,
                    unclassifiedTokens: parts.unclassified
                )
            )
            if firstOnly { return records }
        }
        return records
    }

    private static func extensionUsage(_ usage: [String: Any]) -> EditorLog.UsageParts {
        EditorLog.combine(
            input: EditorLog.firstCount(usage, ["inputTokens", "prompt_tokens"]),
            output: EditorLog.firstCount(usage, ["outputTokens", "output_tokens"]),
            cacheRead: EditorLog.firstCount(usage, [
                "cacheTokens", "cachedReadTokens", "cache_read_input_tokens",
            ]),
            cacheWrite: EditorLog.firstCount(usage, [
                "cachedWriteTokens", "cacheCreationTokens", "cache_creation_input_tokens",
            ]),
            reasoning: EditorLog.firstCount(usage, [
                "reasoningTokens", "completionThinkingTokens",
            ]),
            total: EditorLog.firstCount(usage, ["totalTokens", "total_tokens"]),
            exclusiveInput: EditorLog.firstCount(usage, ["cachedMissTokens", "cacheMissTokens"]),
            inputMayIncludeCache: true
        )
    }

    private static func prepared(_ line: String) -> (agent: String, model: String)? {
        guard let marker = line.range(of: "[CraftInvokableAgent]") else { return nil }
        guard let agent = bracketed(line, from: marker.upperBound) else { return nil }
        guard let label = line.range(of: "Model prepared:", range: marker.upperBound..<line.endIndex) else {
            return nil
        }
        let rest = line[label.upperBound...]
        guard
            let open = rest.lastIndex(of: "("),
            let close = rest.lastIndex(of: ")"),
            open < close
        else { return nil }
        let model = String(rest[rest.index(after: open)..<close])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        return (agent, model)
    }

    private static func reported(_ line: String) -> (agent: String, usage: [String: Any])? {
        guard let marker = line.range(of: "[AgentReporter]") else { return nil }
        guard let agent = bracketed(line, from: marker.upperBound) else { return nil }
        guard
            let usageRange = line.range(of: "usage:", range: marker.upperBound..<line.endIndex),
            let usage = EditorLog.braceObject(in: String(line[usageRange.upperBound...]))
        else { return nil }
        return (agent, usage)
    }

    /// The first `[value]` after `index`, which is where the agent id sits.
    private static func bracketed(_ line: String, from index: String.Index) -> String? {
        guard
            let open = line.range(of: "[", range: index..<line.endIndex),
            let close = line.range(of: "]", range: open.upperBound..<line.endIndex)
        else { return nil }
        return EditorLog.nonBlank(String(line[open.upperBound..<close.lowerBound]))
    }

    // MARK: - WorkBuddy SQLite fallback

    private static func sqlite(client: String, file: URL) -> [AgentUsageRecord] {
        guard client == "workbuddy" else { return [] }

        let rows: [AgentUsageRecord]? = AgentSQLite.read(at: file) { database in
            var sessions: [String: (cwd: String?, model: String?)] = [:]
            AgentSQLite.each(database, sql: "SELECT id, cwd, model FROM sessions") { statement in
                guard let id = AgentSQLite.text(statement, column: 0) else { return }
                sessions[id] = (
                    AgentSQLite.text(statement, column: 1),
                    AgentSQLite.text(statement, column: 2)
                )
            }

            var found: [AgentUsageRecord] = []
            AgentSQLite.each(
                database,
                sql: "SELECT session_id, used, updated_at FROM session_usage"
            ) { statement in
                guard
                    let sessionID = AgentSQLite.text(statement, column: 0),
                    let used = AgentLogIO.count(AgentSQLite.text(statement, column: 1)),
                    used > 0,
                    let updated = AgentLogIO.count(AgentSQLite.text(statement, column: 2)),
                    updated > 0,
                    let timestamp = EditorLog.autoEpoch(updated)
                else { return }

                let session = sessions[sessionID]
                found.append(
                    EditorLog.record(
                        timestamp: timestamp,
                        model: EditorLog.modelID(session?.model) ?? "auto",
                        tally: TokenTally(),
                        sessionID: sessionID,
                        project: EditorLog.project(session?.cwd),
                        // One row is the session's whole aggregate, so the
                        // identity includes the write that produced it.
                        deduplicationID: "workbuddy:\(sessionID):\(updated)",
                        unclassifiedTokens: used,
                        isAggregate: true
                    )
                )
            }
            return found
        }

        return rows ?? []
    }

    private static func total(_ record: AgentUsageRecord) -> Int {
        record.tally.total + record.unclassifiedTokens
    }
}
