// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Cherry Studio's agent transcripts.
///
/// The store is a standard Claude Code-shaped JSONL tree under the app's
/// `.claude/projects`, once for the legacy V1 layout and once for V2. Cherry
/// appends the **same API call three or four times** as a response streams,
/// each copy with a fresh `uuid` but the same `requestId`, `message.id` and
/// usage — so counting lines would multiply every call by four.
///
/// **The identity is the call, and the counters are cumulative.** Records
/// sharing `requestId` (falling back to `message.id`, then `uuid`) are folded
/// into one, merging each bucket by field-wise maximum, which is what a stream
/// of growing snapshots needs. A record with no identity at all is kept on its
/// own: usage that merely looks alike is not the same call.
enum CherryStudioReader {
    static let supportedClients: Set<String> = ["cherrystudio"]

    static func inputs(home: URL) -> [URL] {
        let applicationSupport = "Library/Application Support/CherryStudio"
        let config = ".config/CherryStudio"
        // V2 is listed before V1 everywhere so a same-named session in both
        // trees resolves to the current one.
        return [
            home.appending(path: "\(applicationSupport)/Data/Agents/.claude/projects"),
            home.appending(path: "\(applicationSupport)/.claude/projects"),
            home.appending(path: "\(config)/Data/Agents/.claude/projects"),
            home.appending(path: "\(config)/.claude/projects"),
        ]
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var seenRelative: Set<String> = []
        var records: [AgentUsageRecord] = []

        for root in roots {
            for file in AgentLogIO.files(in: [root], extensions: ["jsonl"]) {
                // Both trees hold the same relative session path; the first
                // root listed (V2) wins it.
                let relative = Self.relativePath(of: file, under: root)
                guard seenRelative.insert(relative).inserted else { continue }
                records += parse(file, relative: relative)
            }
        }
        return records
    }

    // MARK: - One transcript

    private struct Snapshot {
        var input = 0
        var cacheWrite = 0
        var cacheRead = 0
        var output = 0
        var timestamp: Date?
        var model: String?
    }

    private static func parse(_ file: URL, relative: String) -> [AgentUsageRecord] {
        let session = file.deletingPathExtension().lastPathComponent
        let project = EditorLog.nonBlank(file.deletingLastPathComponent().lastPathComponent)

        var identified: [String: Snapshot] = [:]
        var order: [String] = []
        var unidentified: [AgentUsageRecord] = []

        for row in AgentLogIO.jsonLines(at: file) {
            guard
                AgentLogIO.text(row["type"]) == "assistant",
                let message = AgentLogIO.object(row["message"]),
                let usage = AgentLogIO.object(message["usage"])
            else { continue }

            let input = EditorLog.int(usage["input_tokens"])
            let cacheRead = EditorLog.int(usage["cache_read_input_tokens"])
            let cacheWrite = EditorLog.int(usage["cache_creation_input_tokens"])
            let output = EditorLog.int(usage["output_tokens"])
            guard input + cacheRead + cacheWrite + output > 0 else { continue }

            // The timestamp may sit on the record, on its message, or be
            // absent; absent is not newer evidence.
            let timestamp = AgentLogIO.timestamp(row["timestamp"])
                ?? AgentLogIO.timestamp(message["timestamp"])

            let identity = EditorLog.nonBlank(AgentLogIO.text(row["requestId"]))
                ?? EditorLog.nonBlank(AgentLogIO.text(message["requestId"]))
                ?? EditorLog.nonBlank(AgentLogIO.text(message["id"]))
                ?? EditorLog.nonBlank(AgentLogIO.text(row["uuid"]))

            guard
                let model = EditorLog.nonBlank(AgentLogIO.text(message["model"]))
            else { continue }

            guard let identity else {
                guard let timestamp else { continue }
                unidentified.append(
                    EditorLog.record(
                        timestamp: timestamp,
                        model: model,
                        tally: TokenTally(
                            input: input, cacheWrite: cacheWrite, cacheRead: cacheRead, output: output
                        ),
                        sessionID: session,
                        project: project
                    )
                )
                continue
            }

            var snapshot = identified[identity] ?? Snapshot()
            if identified[identity] == nil { order.append(identity) }
            snapshot.input = max(snapshot.input, input)
            snapshot.cacheWrite = max(snapshot.cacheWrite, cacheWrite)
            snapshot.cacheRead = max(snapshot.cacheRead, cacheRead)
            snapshot.output = max(snapshot.output, output)
            snapshot.model = snapshot.model ?? model
            if let timestamp, timestamp > (snapshot.timestamp ?? .distantPast) {
                snapshot.timestamp = timestamp
            }
            identified[identity] = snapshot
        }

        var records = unidentified
        for identity in order {
            guard
                let snapshot = identified[identity],
                let timestamp = snapshot.timestamp,
                let model = snapshot.model
            else { continue }
            records.append(
                EditorLog.record(
                    timestamp: timestamp,
                    model: model,
                    tally: TokenTally(
                        input: snapshot.input,
                        cacheWrite: snapshot.cacheWrite,
                        cacheRead: snapshot.cacheRead,
                        output: snapshot.output
                    ),
                    sessionID: session,
                    project: project,
                    deduplicationID: "cherrystudio:\(relative):\(identity)"
                )
            )
        }
        return records
    }

    private static func relativePath(of file: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return file.lastPathComponent }
        return String(filePath.dropFirst(prefix.count))
    }
}
