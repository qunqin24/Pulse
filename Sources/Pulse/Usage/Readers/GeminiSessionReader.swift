// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Gemini CLI's three on-disk shapes.
///
/// - a legacy whole-session JSON (`session-*.json`),
/// - the current chat recording (`tmp/<id>/chats/<file>.json`),
/// - a headless JSONL stream whose `init` line names the model and session and
///   whose `tokens`/`stats` lines carry usage.
///
/// The token keys are aliases — `prompt`/`input_tokens`/`promptTokenCount` and
/// so on — and the cache relation is **shape-specific**, so the two decoders
/// are kept apart rather than blended. Tool tokens are real counters; the
/// session shape folds them into fresh input while the headless usage object
/// does not carry them at all. Reasoning is additive on top of output, and
/// cache writes are always zero here.
enum GeminiSessionReader {
    enum Shape {
        case session
        case headless
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []
        var incomplete = false
        for file in AgentLogIO.files(in: roots, extensions: ["json", "jsonl"]) {
            let parsed: (records: [AgentUsageRecord], incomplete: Bool)
            if file.pathExtension == "jsonl" {
                parsed = headless(at: file)
            } else if file.lastPathComponent.hasPrefix("session-") || isChatPath(file) {
                parsed = session(at: file)
            } else {
                continue
            }
            records.append(contentsOf: parsed.records)
            incomplete = incomplete || parsed.incomplete
        }
        return incomplete ? records.map(Self.markedPartial) : records
    }

    private static func markedPartial(_ record: AgentUsageRecord) -> AgentUsageRecord {
        var copy = record
        copy.isPartial = true
        return copy
    }

    /// The current chat recording's exact `…/tmp/<id>/chats/<file>.json` shape.
    /// A JSON file anywhere else is not accepted: a different shape read as
    /// this one would attribute the wrong session.
    static func isChatPath(_ url: URL) -> Bool {
        let components = url.pathComponents
        guard
            let chats = components.lastIndex(of: "chats"),
            chats >= 2,
            components[chats - 2] == "tmp",
            !components[chats - 1].isEmpty
        else { return false }
        return true
    }

    // MARK: - Session JSON

    static func session(at url: URL) -> (records: [AgentUsageRecord], incomplete: Bool) {
        guard let root = AgentLogIO.object(AgentLogIO.json(at: url)) else { return ([], false) }
        let fallbackID = url.deletingPathExtension().lastPathComponent
        let sessionID = AgentLogIO.text(root["sessionId"])
            ?? AgentLogIO.text(root["session_id"])
            ?? fallbackID
        let messages = root["messages"] as? [[String: Any]] ?? []

        var records: [AgentUsageRecord] = []
        var incomplete = false
        for message in messages {
            guard message["type"] as? String == "gemini" else { continue }
            guard let tokens = message["tokens"] as? [String: Any] else { continue }

            let usage = decode(tokens, shape: .session, tokenWrapper: false)
            guard usage.tally.total > 0 || usage.unclassified > 0 else { continue }

            guard
                let model = AgentLogIO.text(message["model"]),
                let timestamp = AgentLogIO.timestamp(message["timestamp"])
                    ?? AgentLogIO.timestamp(message["created_at"])
            else {
                // Real usage with no model or no locatable time.
                incomplete = true
                continue
            }

            let id = AgentLogIO.text(message["id"])
            records.append(
                AgentUsageRecord(
                    timestamp: timestamp, model: model, tally: usage.tally,
                    sessionID: sessionID,
                    deduplicationID: id.map { "gemini:session:\(sessionID):\($0)" },
                    unclassifiedTokens: usage.unclassified
                )
            )
        }
        return (records, incomplete)
    }

    // MARK: - Headless JSONL

    static func headless(at url: URL) -> (records: [AgentUsageRecord], incomplete: Bool) {
        let rows = AgentLogIO.jsonLines(at: url)
        let fileStem = url.deletingPathExtension().lastPathComponent
        var currentModel: String?
        var currentSession: String?
        var records: [AgentUsageRecord] = []
        var indexByID: [String: Int] = [:]
        var incomplete = false

        func submit(_ record: AgentUsageRecord, id: String?) {
            if let id, let existing = indexByID[id] {
                // A re-export of the same call replaces its original in place
                // rather than adding a second copy.
                records[existing] = record
            } else {
                if let id { indexByID[id] = records.count }
                records.append(record)
            }
        }

        for (line, row) in rows.enumerated() {
            if row["type"] as? String == "init" {
                if let model = AgentLogIO.text(row["model"]) { currentModel = model }
                if let session = AgentLogIO.text(row["session_id"]) ?? AgentLogIO.text(row["sessionId"]) {
                    currentSession = session
                }
                continue
            }

            let sessionID = AgentLogIO.text(row["session_id"])
                ?? AgentLogIO.text(row["sessionId"])
                ?? currentSession
                ?? fileStem
            let lineID = AgentLogIO.text(row["id"])
            let lineTime = AgentLogIO.timestamp(row["timestamp"]) ?? AgentLogIO.timestamp(row["created_at"])

            if let tokens = row["tokens"] as? [String: Any] {
                let usage = decode(tokens, shape: .headless, tokenWrapper: true)
                guard usage.tally.total > 0 || usage.unclassified > 0 else { continue }
                guard
                    let model = AgentLogIO.text(row["model"]) ?? currentModel,
                    let timestamp = lineTime
                else {
                    incomplete = true
                    continue
                }
                submit(
                    AgentUsageRecord(
                        timestamp: timestamp, model: model, tally: usage.tally,
                        sessionID: sessionID,
                        deduplicationID: lineID.map { "gemini:line:\($0)" }
                            ?? "gemini:headless:\(fileStem):\(line)",
                        unclassifiedTokens: usage.unclassified
                    ),
                    id: lineID
                )
                continue
            }

            var stats = row["stats"] as? [String: Any]
            if stats == nil, let result = row["result"] as? [String: Any] {
                stats = result["stats"] as? [String: Any]
            }
            guard let stats else { continue }

            if let models = stats["models"] as? [String: [String: Any]] {
                for (model, counts) in models {
                    let usage = decode(counts, shape: .headless, tokenWrapper: false)
                    guard usage.tally.total > 0 || usage.unclassified > 0 else { continue }
                    guard let timestamp = AgentLogIO.timestamp(counts["timestamp"]) ?? lineTime else {
                        incomplete = true
                        continue
                    }
                    let id = lineID.map { "\($0):\(model)" }
                    submit(
                        AgentUsageRecord(
                            timestamp: timestamp, model: model, tally: usage.tally,
                            sessionID: sessionID,
                            deduplicationID: id.map { "gemini:line:\($0)" }
                                ?? "gemini:headless:\(fileStem):\(line):\(model)",
                            unclassifiedTokens: usage.unclassified
                        ),
                        id: id
                    )
                }
            } else {
                let usage = decode(stats, shape: .headless, tokenWrapper: false)
                guard usage.tally.total > 0 || usage.unclassified > 0 else { continue }
                guard
                    let model = AgentLogIO.text(stats["model"]) ?? currentModel,
                    let timestamp = AgentLogIO.timestamp(stats["timestamp"]) ?? lineTime
                else {
                    incomplete = true
                    continue
                }
                submit(
                    AgentUsageRecord(
                        timestamp: timestamp, model: model, tally: usage.tally,
                        sessionID: sessionID,
                        deduplicationID: lineID.map { "gemini:line:\($0)" }
                            ?? "gemini:headless:\(fileStem):\(line)",
                        unclassifiedTokens: usage.unclassified
                    ),
                    id: lineID
                )
            }
        }
        return (records, incomplete)
    }

    // MARK: - Tokens

    /// Decodes a Gemini usage object into disjoint buckets.
    ///
    /// The session shape's cache overlap is proven only by a total that equals
    /// the non-cache sum; the headless shape treats an input that arrived under
    /// a prompt-style key (or a `tokens` wrapper) as cache-inclusive and a bare
    /// `input` field as already net. A bare total with no named kind is carried
    /// as unclassified rather than guessed into input.
    static func decode(
        _ object: [String: Any],
        shape: Shape,
        tokenWrapper: Bool
    ) -> (tally: TokenTally, unclassified: Int) {
        let input = first(object, ["input", "prompt", "input_tokens", "prompt_tokens", "promptTokenCount"])
        let output = first(object, ["output", "candidates", "output_tokens", "completion_tokens", "candidatesTokenCount"])
        let cached = first(object, ["cached", "cached_tokens", "cachedContentTokenCount"])
        let reasoning = first(object, ["thoughts", "reasoning", "thoughts_tokens"])
        let tool = first(object, ["tool", "tool_tokens"])
        let total = first(object, ["total", "totalTokenCount", "total_tokens"])

        let inputCount = input.value.flatMap { AgentLogIO.count($0) } ?? 0
        let outputCount = output.value.flatMap { AgentLogIO.count($0) } ?? 0
        let cachedCount = cached.value.flatMap { AgentLogIO.count($0) } ?? 0
        let reasoningCount = reasoning.value.flatMap { AgentLogIO.count($0) } ?? 0
        let toolCount = tool.value.flatMap { AgentLogIO.count($0) } ?? 0
        let totalCount = total.value.flatMap { AgentLogIO.count($0) }

        let anyKind = input.value != nil || output.value != nil || cached.value != nil
            || reasoning.value != nil || tool.value != nil
        if !anyKind {
            return (TokenTally(), totalCount ?? 0)
        }

        let outputBucket = outputCount + reasoningCount
        switch shape {
        case .session:
            let raw = inputCount + toolCount
            // A reported total is the authority when present. Without one, the
            // documented Gemini semantics still apply to a prompt-style input
            // key (the prompt includes the cached content); a net `input` field
            // is already the fresh count and is left alone.
            if let totalCount {
                let cacheInclusive = totalCount == raw + outputCount + reasoningCount
                    && totalCount != raw + outputCount + reasoningCount + cachedCount
                let fresh = cacheInclusive ? max(0, raw - cachedCount) : raw
                return (TokenTally(input: fresh, cacheWrite: 0, cacheRead: cachedCount, output: outputBucket), 0)
            }
            let promptStyle = input.key != nil && input.key != "input"
            let fresh = promptStyle ? max(0, raw - cachedCount) : raw
            return (TokenTally(input: fresh, cacheWrite: 0, cacheRead: cachedCount, output: outputBucket), 0)
        case .headless:
            let cacheInclusive = tokenWrapper || (input.key != nil && input.key != "input")
            let fresh = cacheInclusive ? max(0, inputCount - cachedCount) : inputCount
            return (TokenTally(input: fresh, cacheWrite: 0, cacheRead: cachedCount, output: outputBucket), 0)
        }
    }

    private static func first(
        _ object: [String: Any],
        _ keys: [String]
    ) -> (value: Any?, key: String?) {
        for key in keys where object[key] != nil {
            return (object[key], key)
        }
        return (nil, nil)
    }
}
