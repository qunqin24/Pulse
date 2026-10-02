// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Gajae Code's (`gjc`) JSONL session files.
///
/// A transcript opens with `{"type":"session","id","timestamp","cwd"}` and then
/// carries `{"type":"message","id","message":{"role","model","provider",
/// "timestamp","usage":{"input","output","cacheRead","cacheWrite","totalTokens"}}}`.
/// Service-tier and unknown event types are ignored.
///
/// **Only assistant rows with a model and usage emit.** A user row has no
/// usage; a message with no model names nothing to price.
///
/// **Identity is the entry id, and only that.** A row with an `id` folds
/// against the same id (`<session>:<entryId>`), so a replay of that row counts
/// once. A row **without** an id is its own request and is always counted —
/// even when another row carries the same second, model and token counts.
/// Identical figures are not evidence that two calls are one, and the store
/// wrote no id to say so; folding them by a value hash would silently drop a
/// real request. A byte-for-byte mirror file (the same session id and the same
/// file name at two depths) is recognised by that explicit session/file
/// identity and read once, while a session's genuinely separate parts, which
/// carry different names or different lines, all count.
///
/// `cost.total` is the product's own dollars and is not read as tokens; Pulse's
/// price table prices the counts. Reasoning is not exposed by this usage shape,
/// so output is taken as reported.
enum GJCUsageReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []
        // A session id and file name map to the digests already read; only a
        // byte-for-byte mirror of one of them is skipped.
        var seenFiles: [String: Set<String>] = [:]

        for file in AgentLogIO.files(in: roots, extensions: ["jsonl"]) {
            guard let digest = AgentLogIO.digest(at: file) else { continue }
            let lines = LogLines(at: file)

            // The header is read first so a mirror can be recognised before
            // any of its lines has been counted.
            var headerID: String?
            var workspace: String?
            for line in lines {
                guard
                    let event = object(line),
                    AgentLogIO.text(event["type"]) == "session"
                else { continue }
                if headerID == nil { headerID = AgentLogIO.text(event["id"]) }
                if workspace == nil { workspace = AgentLogIO.text(event["cwd"]) }
            }

            // One session written twice at two depths shares both its id and
            // its file name. That is read once **only when the bytes are
            // identical**; a same-named file with extra requests is a fuller
            // record, not a mirror, and is parsed in full. Real entry ids then
            // fold the overlap in the builder, and id-less rows stay separate.
            if let headerID {
                let mirror = "\(headerID)|\(file.lastPathComponent)"
                if seenFiles[mirror, default: []].contains(digest) { continue }
                seenFiles[mirror, default: []].insert(digest)
            }

            let session = headerID ?? file.deletingPathExtension().lastPathComponent

            for line in lines {
                guard
                    let event = object(line),
                    AgentLogIO.text(event["type"]) == "message",
                    let message = AgentLogIO.object(event["message"]),
                    AgentLogIO.text(message["role"])?.lowercased() == "assistant",
                    let usage = AgentLogIO.object(message["usage"]),
                    let model = AgentLogIO.text(message["model"]),
                    let timestamp = timestamp(of: message, event: event)
                else { continue }

                let tally = TokenTally(
                    input: AgentLogIO.count(usage["input"]) ?? 0,
                    cacheWrite: AgentLogIO.count(usage["cacheWrite"]) ?? 0,
                    cacheRead: AgentLogIO.count(usage["cacheRead"]) ?? 0,
                    output: AgentLogIO.count(usage["output"]) ?? 0
                )

                // Only a real entry id is an identity. Without one the record
                // carries none, so the builder keeps every occurrence.
                let identity = AgentLogIO.text(event["id"]).map { "gjc:\(session):\($0)" }

                guard
                    let record = StructuredLogSupport.record(
                        timestamp: timestamp,
                        model: model,
                        tally: tally,
                        sessionID: session,
                        sessionName: session,
                        project: StructuredLogSupport.project(workspace),
                        deduplicationID: identity
                    )
                else { continue }
                records.append(record)
            }
        }

        return records
    }

    /// The message's own unix-millisecond time, else the envelope's RFC 3339
    /// time. Absent is skipped.
    private static func timestamp(of message: [String: Any], event: [String: Any]) -> Date? {
        // A zero message time is unset, so the envelope's time is tried.
        if let value = StructuredLogSupport.eventTime(message["timestamp"], milliseconds: true) {
            return value
        }
        return StructuredLogSupport.eventTime(event["timestamp"])
    }

    /// One JSONL line as an object, or nil for a malformed or non-object line.
    private static func object(_ line: Data.SubSequence) -> [String: Any]? {
        guard let value = try? JSONSerialization.jsonObject(with: Data(line)) else { return nil }
        return value as? [String: Any]
    }
}
