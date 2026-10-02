// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Amp's threads, where the same calls are described twice.
///
/// A `T-*.json` thread holds assistant messages with their own usage and a
/// `usageLedger.events` series. The ledger is the primary record; an assistant
/// message is matched to a ledger event by `toMessageId` first and by equal
/// model plus equal tokens second, and a matched message is **not** emitted
/// again. Only when the ledger is empty (or a message has no event) does the
/// message stand alone. That reconciliation is the whole point: emitting both
/// sides would double every call.
///
/// A message's own time is a ledger event's RFC3339 stamp. Amp records no time
/// on a message, so a message without a matching stamped event can only be
/// placed at the thread's own report time, and is marked `isAggregate` rather
/// than given a fabricated per-message time. With no real time at all — neither
/// an event stamp nor the thread's own report time — the call is not emitted:
/// inventing a timestamp from the message id is not a reading.
enum AmpSessionReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var result: [AgentUsageRecord] = []
        var incomplete = false
        let files = AgentLogIO.files(in: roots, extensions: ["json"])
            .filter { $0.lastPathComponent.hasPrefix("T-") }
        for file in files {
            let parsed = thread(at: file)
            result.append(contentsOf: parsed.records)
            incomplete = incomplete || parsed.incomplete
        }
        return incomplete ? result.map(Self.markedPartial) : result
    }

    static func thread(at url: URL) -> (records: [AgentUsageRecord], incomplete: Bool) {
        guard let root = AgentLogIO.object(AgentLogIO.json(at: url)) else { return ([], false) }
        let threadID = AgentLogIO.text(root["id"]) ?? url.deletingPathExtension().lastPathComponent
        let created = AgentLogIO.timestamp(root["created"], milliseconds: true)

        let (messageCalls, droppedMessages) = messages(in: root)
        let (events, droppedEvents) = ledgerEvents(in: root)
        var incomplete = droppedMessages || droppedEvents
        var consumed = Array(repeating: false, count: events.count)
        var unmatched: [Call] = []

        for call in messageCalls {
            var matched = false
            if let id = call.messageID {
                if let index = events.indices.first(where: { !consumed[$0] && events[$0].toMessageID == id }) {
                    consumed[index] = true
                    matched = true
                }
            }
            if !matched, let index = events.indices.first(where: {
                !consumed[$0] && events[$0].model == call.model && events[$0].tally == call.tally
            }) {
                consumed[index] = true
                matched = true
            }
            if !matched { unmatched.append(call) }
        }

        var records: [AgentUsageRecord] = []
        for event in events {
            guard let timestamp = event.timestamp ?? created else {
                incomplete = true
                continue
            }
            let suffix = event.toMessageID.map { String($0) }
                ?? event.fromMessageID.map { String($0) }
                ?? String(event.index)
            records.append(
                AgentUsageRecord(
                    timestamp: timestamp, model: event.model, tally: event.tally,
                    sessionID: threadID,
                    deduplicationID: "amp:\(threadID):event:\(suffix)",
                    isAggregate: event.timestamp == nil
                )
            )
        }

        for call in unmatched {
            guard let created else {
                incomplete = true
                continue
            }
            let suffix = call.messageID.map { String($0) } ?? "0"
            records.append(
                AgentUsageRecord(
                    timestamp: created, model: call.model, tally: call.tally,
                    sessionID: threadID,
                    deduplicationID: "amp:\(threadID):message:\(suffix)",
                    isAggregate: true
                )
            )
        }
        return (records, incomplete)
    }

    private static func markedPartial(_ record: AgentUsageRecord) -> AgentUsageRecord {
        var copy = record
        copy.isPartial = true
        return copy
    }

    // MARK: - Shapes

    private struct Call {
        var model: String
        var tally: TokenTally
        var messageID: Int?
    }

    private struct Event {
        var timestamp: Date?
        var model: String
        var tally: TokenTally
        var toMessageID: Int?
        var fromMessageID: Int?
        var index: Int
    }

    private static func messages(in root: [String: Any]) -> (calls: [Call], droppedUsage: Bool) {
        let rows = root["messages"] as? [[String: Any]] ?? []
        var calls: [Call] = []
        var dropped = false
        for row in rows {
            guard row["role"] as? String == "assistant" else { continue }
            guard let usage = row["usage"] as? [String: Any] else { continue }
            let tally = TokenTally(
                input: AgentLogIO.count(usage["inputTokens"]) ?? 0,
                cacheWrite: AgentLogIO.count(usage["cacheCreationInputTokens"]) ?? 0,
                cacheRead: AgentLogIO.count(usage["cacheReadInputTokens"]) ?? 0,
                output: AgentLogIO.count(usage["outputTokens"]) ?? 0
            )
            guard tally.total > 0 else { continue }
            guard let model = AgentLogIO.text(usage["model"]) else {
                dropped = true
                continue
            }
            calls.append(Call(model: model, tally: tally, messageID: AgentLogIO.count(row["messageId"])))
        }
        return (calls, dropped)
    }

    private static func ledgerEvents(in root: [String: Any]) -> (events: [Event], droppedUsage: Bool) {
        let ledger = root["usageLedger"] as? [String: Any]
        let rows = ledger?["events"] as? [[String: Any]] ?? []
        var events: [Event] = []
        var dropped = false
        for (index, row) in rows.enumerated() {
            let tokens = row["tokens"] as? [String: Any] ?? [:]
            let tally = TokenTally(
                input: AgentLogIO.count(tokens["input"]) ?? 0,
                cacheWrite: AgentLogIO.count(tokens["cacheCreationInputTokens"]) ?? 0,
                cacheRead: AgentLogIO.count(tokens["cacheReadInputTokens"]) ?? 0,
                output: AgentLogIO.count(tokens["output"]) ?? 0
            )
            guard tally.total > 0 else { continue }
            guard let model = AgentLogIO.text(row["model"]) else {
                dropped = true
                continue
            }
            events.append(
                Event(
                    timestamp: AgentLogIO.timestamp(row["timestamp"]),
                    model: model,
                    tally: tally,
                    toMessageID: AgentLogIO.count(row["toMessageId"]),
                    fromMessageID: AgentLogIO.count(row["fromMessageId"]),
                    index: index
                )
            )
        }
        return (events, dropped)
    }
}
