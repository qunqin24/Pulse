// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A captured MiniMax Code headless stream: the JSONL `mcode exec
/// --output-format stream-json` writes.
///
/// There is no native local usage file. A user or a wrapper must run the CLI
/// with the stream-json format and capture the output here; driving the CLI is
/// out of scope, and Pulse only reads the capture.
///
/// **Usage is buffered per `turnId` and emitted only when a matching
/// `exec.result` supplies the model.** A stream that never names a model is
/// unusable, and Pulse refuses to guess one from response text or local
/// configuration. An `exec.result` names a model for a turn; it is **not**
/// evidence that the turn held only one request, so every buffered message in
/// the turn is emitted.
///
/// **A message is merged only by its own identity, never by its counts.** When
/// a message carries an id (`id`, `messageId` or `responseId`), a later line
/// with the same id is the streaming/terminal restatement of *that* message and
/// replaces it. When it carries no id, every line is its own message and is
/// kept — even when two have identical counts, and even when the second's
/// counts are larger. Counting alone never makes two messages one.
///
/// The file is read line by line and a **leading BOM or a bad byte on one line
/// does not lose the rest** — a capture that appended one malformed line must
/// still yield its other turns.
enum CapturedMcodeReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["jsonl"])
        var records: [AgentUsageRecord] = []
        for file in files {
            records.append(contentsOf: Self.records(at: file))
        }
        return records
    }

    /// One assistant message's usage, before a model is known.
    private struct Usage {
        var input: Int
        var output: Int
        var cacheRead: Int
        var cacheWrite: Int
        /// A stated total with no per-kind split: real tokens Pulse cannot
        /// place in a bucket, counted and never invented into `input`.
        var unclassified: Int
        var timestamp: Date?
        /// The message's own id where the stream states one; nil otherwise.
        var identity: String?
    }

    /// A model-bearing `exec.result`, which is what unlocks a turn's usage.
    private struct TurnResult {
        let session: String
        let model: String
    }

    private static func records(at url: URL) -> [AgentUsageRecord] {
        var buffered: [String: [Usage]] = [:]
        var positions: [String: [String: Int]] = [:]
        var results: [String: TurnResult] = [:]
        var order: [String] = []

        for object in objects(at: url) {
            guard let type = AgentLogIO.text(object["type"]) else { continue }

            if type == "message" {
                guard
                    let message = AgentLogIO.object(object["message"]),
                    AgentLogIO.text(message["role"]) == "assistant",
                    let turn = AgentLogIO.text(message["turnId"]),
                    let usage = AgentLogIO.object(message["usage"]),
                    let entry = self.usage(usage, at: date(message["timestamp"]),
                                           identity: identity(message))
                else { continue }
                if buffered[turn] == nil { order.append(turn) }
                merge(entry, turn: turn, into: &buffered, positions: &positions)
            } else if type == "exec.result" {
                guard
                    let session = AgentLogIO.text(object["sessionId"]),
                    let turn = AgentLogIO.text(object["turnId"]),
                    let model = AgentLogIO.object(object["model"]),
                    AgentLogIO.text(model["providerId"]) != nil,
                    let modelID = AgentLogIO.text(model["modelId"])
                else { continue }
                results[turn] = TurnResult(session: session, model: modelID)
            }
        }

        var records: [AgentUsageRecord] = []
        for turn in order {
            guard let result = results[turn], let entries = buffered[turn] else { continue }
            for (index, entry) in entries.enumerated() {
                guard let at = entry.timestamp else { continue }
                var record = AgentUsageRecord(
                    timestamp: at,
                    model: result.model,
                    tally: TokenTally(
                        input: entry.input,
                        cacheWrite: entry.cacheWrite,
                        cacheRead: entry.cacheRead,
                        output: entry.output
                    )
                )
                record.sessionID = result.session
                record.unclassifiedTokens = entry.unclassified
                record.deduplicationID = "mcode:\(result.session):\(turn):\(index):"
                    + "\(entry.input):\(entry.output):\(entry.cacheRead):\(entry.cacheWrite)"
                records.append(record)
            }
        }
        return records
    }

    /// Appends a message, or replaces the earlier restatement of the **same
    /// id**. Two different messages — with or without equal counts — are always
    /// both kept.
    private static func merge(
        _ entry: Usage,
        turn: String,
        into buffered: inout [String: [Usage]],
        positions: inout [String: [String: Int]]
    ) {
        if let identity = entry.identity,
           let index = positions[turn]?[identity],
           index < (buffered[turn]?.count ?? 0) {
            buffered[turn]?[index] = entry
            return
        }
        var entries = buffered[turn] ?? []
        let index = entries.count
        entries.append(entry)
        buffered[turn] = entries
        guard let identity = entry.identity else { return }
        var map = positions[turn] ?? [:]
        map[identity] = index
        positions[turn] = map
    }

    /// The message's own id, preferring the most specific field the stream
    /// offers. Nil means the line is an independent message.
    private static func identity(_ message: [String: Any]) -> String? {
        AgentLogIO.text(message["id"])
            ?? AgentLogIO.text(message["messageId"])
            ?? AgentLogIO.text(message["responseId"])
    }

    /// The message's usage, or nil when it asserts nothing usable.
    private static func usage(_ object: [String: Any], at timestamp: Date?, identity: String?) -> Usage? {
        let bucketKeys = ["inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens"]
        let hasBuckets = bucketKeys.contains { object[$0] != nil }
        let total = AgentLogIO.count(object["totalTokens"]) ?? 0

        if hasBuckets {
            let entry = Usage(
                input: AgentLogIO.count(object["inputTokens"]) ?? 0,
                output: AgentLogIO.count(object["outputTokens"]) ?? 0,
                cacheRead: AgentLogIO.count(object["cacheReadTokens"]) ?? 0,
                cacheWrite: AgentLogIO.count(object["cacheWriteTokens"]) ?? 0,
                unclassified: 0,
                timestamp: timestamp,
                identity: identity
            )
            if entry.input + entry.output + entry.cacheRead + entry.cacheWrite > 0 { return entry }
            // Buckets present but empty, with a stated total: the split is not
            // reported, so the tokens are unclassified rather than fake input.
            if total > 0 {
                return Usage(input: 0, output: 0, cacheRead: 0, cacheWrite: 0,
                             unclassified: total, timestamp: timestamp, identity: identity)
            }
            return nil
        }

        // No per-kind counter at all: only a stated total exists.
        if total > 0 {
            return Usage(input: 0, output: 0, cacheRead: 0, cacheWrite: 0,
                         unclassified: total, timestamp: timestamp, identity: identity)
        }
        return nil
    }

    /// Every JSON object line, tolerating a BOM and a single bad byte.
    private static func objects(at url: URL) -> AnySequence<[String: Any]> {
        AnySequence {
            let lines = LogLines(at: url).makeIterator()
            return AnyIterator {
                while var bytes = lines.next() {
                    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
                    let object: [String: Any]? = autoreleasepool {
                        (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
                    }
                    if let object { return object }
                }
                return nil
            }
        }
    }

    /// A stream timestamp in seconds or milliseconds, per the capture schema:
    /// values below the millisecond epoch threshold are seconds. Nothing is
    /// inferred from the clock or a file's modification date.
    private static func date(_ value: Any?) -> Date? {
        guard let raw = number(value), raw.isFinite, raw > 0 else { return nil }
        let seconds = raw < 10_000_000_000 ? raw : raw / 1000
        let date = Date(timeIntervalSince1970: seconds)
        guard date.timeIntervalSince1970.isFinite else { return nil }
        return date
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Double(trimmed)
        }
        return nil
    }
}
