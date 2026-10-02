// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// JetBrains Junie's event stream.
///
/// `~/.junie/sessions/<session-id>/events.jsonl` carries one event per line.
/// A usage event is one whose `event.agentEvent.kind` is
/// `LlmResponseMetadataEvent` and which holds a `modelUsage[]`; every entry in
/// that array is one provider call. `UserPromptEvent` and the lifecycle events
/// (`AgentStateUpdatedEvent`, `AgentCurrentStatusUpdatedEvent`,
/// `AgentPatchCreatedEvent`) carry no usage and are skipped.
///
/// **The timestamp is anchored to the response's start.** `timestampMs` is the
/// response's end, and `usage.time` is its latency, so a row with a positive
/// latency is dated at `timestampMs − time`; the ledger's quarter-hour then
/// belongs to when the call began. A row with no latency keeps the end time.
///
/// **Reasoning is left out.** Junie lists `reasoningTokens`,
/// `reasoningOutputTokens` or `thinkingTokens` beside output without a token
/// total or a statement of containment. Pulse's output bucket counts reasoning
/// once: adding it would double it when it is already inside output, and
/// carrying it in `unclassifiedTokens` would add it to the grand total the same
/// way. The reported output is kept and the ambiguous reasoning figure is not
/// counted. Cost is the product's own dollars and is not read as tokens.
enum JunieUsageReader {
    static let inputAliases = ["inputTokens", "input"]
    static let outputAliases = ["outputTokens", "output"]
    static let cacheReadAliases = ["cacheInputTokens", "cacheReadInputTokens", "cacheRead"]
    static let cacheWriteAliases = ["cacheCreateTokens", "cacheCreationInputTokens", "cacheWrite"]
    static let reasoningAliases = ["reasoningTokens", "reasoningOutputTokens", "thinkingTokens"]

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []

        for file in AgentLogIO.files(in: roots, names: ["events.jsonl"]) {
            let sessionID = file.deletingLastPathComponent().lastPathComponent

            // The session id encodes its own start, which is the real fallback
            // when the event's `timestampMs` is unset (`0`).
            let sessionStart = Self.sessionIDTime(sessionID)

            for row in AgentLogIO.jsonLines(at: file) {
                guard let event = AgentLogIO.object(row["event"]) else { continue }
                guard let agentEvent = AgentLogIO.object(event["agentEvent"]) else { continue }
                guard AgentLogIO.text(agentEvent["kind"]) == "LlmResponseMetadataEvent" else { continue }
                guard let usages = agentEvent["modelUsage"] as? [[String: Any]] else { continue }

                // A zero millisecond time is "unset", not 1970, so the record
                // falls back to the session id's own date. Neither the clock
                // nor the file's date is used.
                let end = StructuredLogSupport.eventTime(row["timestampMs"], milliseconds: true)
                let agent = AgentLogIO.object(agentEvent["agent"])
                let agentName = AgentLogIO.text(agent?["name"]) ?? AgentLogIO.text(agent?["id"])

                for (index, entry) in usages.enumerated() {
                    guard let model = AgentLogIO.text(entry["model"]) else { continue }

                    let latency = AgentLogIO.count(entry["time"]) ?? 0
                    let timestamp = Self.eventTime(end: end, latency: latency, fallback: sessionStart)
                    guard let timestamp else { continue }

                    let reasoning = StructuredLogSupport.merged([entry], reasoningAliases)
                    let tally = TokenTally(
                        input: StructuredLogSupport.merged([entry], inputAliases),
                        cacheWrite: StructuredLogSupport.merged([entry], cacheWriteAliases),
                        cacheRead: StructuredLogSupport.merged([entry], cacheReadAliases),
                        output: StructuredLogSupport.output(
                            reported: StructuredLogSupport.merged([entry], outputAliases),
                            reasoning: reasoning,
                            relationship: .unknown
                        )
                    )

                    let identity = "\(sessionID):\(timestamp.timeIntervalSince1970):\(model):"
                        + "\(tally.input):\(tally.cacheWrite):\(tally.cacheRead):\(tally.output):"
                        + "\(AgentLogIO.count(entry["cost"]) ?? 0):\(index)"

                    guard
                        let record = StructuredLogSupport.record(
                            timestamp: timestamp,
                            model: model,
                            tally: tally,
                            isPartial: reasoning > 0,
                            sessionID: sessionID,
                            sessionName: agentName,
                            deduplicationID: "junie:\(identity)"
                        )
                    else { continue }
                    records.append(record)
                }
            }
        }

        return records
    }

    /// The call's start when the response end is known, else the session's own
    /// start. The result is always a real, positive time: a latency that would
    /// place the start at or before the epoch is not used.
    static func eventTime(end: Date?, latency: Int, fallback: Date?) -> Date? {
        guard let end else { return fallback }
        guard latency > 0 else { return end }
        let start = end.addingTimeInterval(-Double(latency) / 1000)
        return start.timeIntervalSince1970 > 0 ? start : end
    }

    /// `session-YYMMDD-HHMMSS` in local time → its start, or nil.
    static func sessionIDTime(_ id: String) -> Date? {
        guard let marker = id.range(of: "session-") else { return nil }
        let stamp = String(id[marker.upperBound...].prefix(13))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyMMdd-HHmmss"
        return formatter.date(from: stamp)
    }
}
