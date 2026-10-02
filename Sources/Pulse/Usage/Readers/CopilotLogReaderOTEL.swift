// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Copilot's file-exported OpenTelemetry JSONL.
///
/// One line per span, log record or event, and a usage line does not always
/// carry its own model, session or agent — those often arrive on another line
/// that shares the `trace_id`, sometimes after the usage line. The file is
/// therefore read once into memory and the context resolved afterwards.
///
/// **Four record kinds, in priority order.** A chat span outranks an inference
/// log, which outranks an agent-turn log, which outranks an agent-summary span.
/// A higher lane suppresses a lower one when the two share a trace id or a
/// response id; the coarse conversation id is deliberately not used, because it
/// spans many turns. A record that names neither a trace nor a response id
/// cannot be correlated at all: it is counted as its own event — never folded
/// onto another by a shared instant, which would delete a different request —
/// and marked `isPartial`, since the schema cannot prove some other lane does
/// not already cover it.
///
/// **Tokens are made disjoint before they leave.** An OTel chat span counts the
/// cache read inside its input, so the cache read is removed from input once.
/// Reasoning is a subset of output in this convention, so it is not added on
/// top of output; it only stands in when output itself was not reported.
enum CopilotOTELReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var candidates: [Candidate] = []

        for file in AgentLogIO.files(in: roots, extensions: ["jsonl"]) {
            let rows = AgentLogIO.jsonLines(at: file)
            let context = traceContext(rows)
            for (index, row) in rows.enumerated() {
                // Each accepted candidate keeps its own ordinal, used only when
                // the record names no stable id. `candidates.count` is unique
                // per accepted record, so two identity-less rows can never be
                // folded together by a shared instant.
                guard let candidate = self.candidate(
                    row: row, index: index, context: context, ordinal: candidates.count
                ) else { continue }
                candidates.append(candidate)
            }
        }

        return resolve(candidates)
    }

    // MARK: - Kinds

    /// The four record kinds, ordered so a lower raw value outranks a higher.
    private enum Lane: Int, CaseIterable {
        case chatSpan = 0
        case inferenceLog = 1
        case agentTurnLog = 2
        case agentSummarySpan = 3
    }

    private static func lane(_ row: [String: Any]) -> Lane? {
        let attributes = self.attributes(row)
        let type = AgentLogIO.text(row["type"])
        let name = AgentLogIO.text(row["name"])
        let operation = AgentLogIO.text(attributes["gen_ai.operation.name"])

        let isSpan = type == "span" || (type == nil && name != nil && hasSpanShape(row))
        guard isSpan else {
            if AgentLogIO.text(attributes["event.name"]) == "gen_ai.client.inference.operation.details"
                || body(row, startsWith: "GenAI inference:") {
                return .inferenceLog
            }
            if AgentLogIO.text(attributes["event.name"]) == "copilot_chat.agent.turn"
                || body(row, startsWith: "copilot_chat.agent.turn") {
                return .agentTurnLog
            }
            return nil
        }

        if operation == "chat" || (name?.hasPrefix("chat ") ?? false) { return .chatSpan }
        if operation == "invoke_agent" || (name?.hasPrefix("invoke_agent ") ?? false) {
            return .agentSummarySpan
        }
        return nil
    }

    /// The shape a span has when its `type` is absent: a name plus any explicit
    /// span identity, timing or kind. Inference and turn logs never carry a
    /// top-level name.
    private static func hasSpanShape(_ row: [String: Any]) -> Bool {
        let identity = identification(row)
        if identity.trace != nil || identity.span != nil { return true }
        return row["startTime"] != nil || row["endTime"] != nil
            || row["duration"] != nil || row["kind"] != nil
    }

    private static func body(_ row: [String: Any], startsWith prefix: String) -> Bool {
        for key in ["body", "_body"] {
            if let text = AgentLogIO.text(row[key]), text.hasPrefix(prefix) { return true }
        }
        return false
    }

    // MARK: - Attributes

    private static func attributes(_ row: [String: Any]) -> [String: Any] {
        row["attributes"] as? [String: Any] ?? [:]
    }

    private static func identification(_ row: [String: Any]) -> (trace: String?, span: String?) {
        let nested = row["spanContext"] as? [String: Any]
        let trace = validID(AgentLogIO.text(row["traceId"]) ?? AgentLogIO.text(nested?["traceId"]))
        let span = validID(AgentLogIO.text(row["spanId"]) ?? AgentLogIO.text(nested?["spanId"]))
        return (trace, span)
    }

    /// The W3C non-recording sentinel — empty, or all zeroes — is absent.
    private static func validID(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.allSatisfy { $0 == "0" } ? nil : value
    }

    private static func model(_ attributes: [String: Any]) -> String? {
        AgentLogIO.text(attributes["gen_ai.response.model"])
            ?? AgentLogIO.text(attributes["gen_ai.request.model"])
    }

    private static func session(_ attributes: [String: Any]) -> String? {
        let keys = [
            "gen_ai.conversation.id",
            "copilot_chat.session_id",
            "copilot_chat.chat_session_id",
            "session.id",
            "github.copilot.interaction_id",
            "gen_ai.response.id",
        ]
        for key in keys {
            if let value = AgentLogIO.text(attributes[key]) { return value }
        }
        return nil
    }

    /// The context one trace shares: the first stated model, session, response
    /// and agent across every line that carries that trace id.
    private struct Context {
        var model: String?
        var session: String?
        var response: String?
        var agent: String?
    }

    private static func traceContext(_ rows: some Sequence<[String: Any]>) -> [String: Context] {
        var contexts: [String: Context] = [:]
        for row in rows {
            guard let trace = identification(row).trace else { continue }
            let attributes = self.attributes(row)
            var context = contexts[trace] ?? Context()
            if context.model == nil { context.model = model(attributes) }
            if context.session == nil { context.session = session(attributes) }
            if context.response == nil {
                context.response = AgentLogIO.text(attributes["gen_ai.response.id"])
            }
            if context.agent == nil { context.agent = AgentLogIO.text(attributes["gen_ai.agent.id"]) }
            contexts[trace] = context
        }
        return contexts
    }

    // MARK: - Candidates

    private struct Candidate {
        var lane: Lane
        var key: String
        var timestamp: Date
        var model: String
        var sessionID: String?
        var agent: String?
        var tally: TokenTally
        var unclassified: Int
        var trace: String?
        var response: String?
        /// True when the record names no trace or response id, so it cannot be
        /// correlated with another lane. It is still counted — deleting it or
        /// folding it by an instant would both lose or duplicate real work —
        /// but the record says so.
        var isPartial = false

        /// The same event seen twice is one event; a later copy can only add
        /// detail, so each bucket takes the larger of the two.
        func merged(with other: Candidate) -> Candidate {
            var result = self
            result.tally = TokenTally(
                input: max(tally.input, other.tally.input),
                cacheWrite: max(tally.cacheWrite, other.tally.cacheWrite),
                cacheRead: max(tally.cacheRead, other.tally.cacheRead),
                output: max(tally.output, other.tally.output)
            )
            result.unclassified = max(unclassified, other.unclassified)
            result.isPartial = isPartial || other.isPartial
            return result
        }
    }

    private static func candidate(
        row: [String: Any],
        index: Int,
        context: [String: Context],
        ordinal: Int
    ) -> Candidate? {
        guard let lane = lane(row) else { return nil }
        let attributes = self.attributes(row)
        let identity = identification(row)
        let shared = identity.trace.flatMap { context[$0] }

        // A record with no usable time is not dated at all: the clock is never
        // used to fill the gap.
        guard let timestamp = self.timestamp(row) else { return nil }

        let session = self.session(attributes) ?? shared?.session
        let response = AgentLogIO.text(attributes["gen_ai.response.id"]) ?? shared?.response
        guard let model = self.model(attributes) ?? shared?.model else { return nil }
        let agent = AgentLogIO.text(attributes["gen_ai.agent.id"]) ?? shared?.agent

        let tokens = counts(attributes)
        guard tokens.tally.total > 0 || tokens.unclassified > 0 else { return nil }
        let turn = textValue(attributes["turn.index"])
            ?? textValue(attributes["copilot_chat.turn.index"])

        let key = dedupKey(
            lane: lane, identity: identity, session: session, response: response,
            index: index, turn: turn, ordinal: ordinal
        )

        return Candidate(
            lane: lane, key: key, timestamp: timestamp, model: model, sessionID: session,
            agent: agent, tally: tokens.tally, unclassified: tokens.unclassified,
            trace: identity.trace, response: response,
            // Neither a trace nor a response id means the record cannot be
            // matched against another lane; the schema cannot prove it is
            // covered elsewhere, so it is carried as a possible subset.
            isPartial: identity.trace == nil && response == nil
        )
    }

    /// The product's own identity for a record, never a clock reading.
    ///
    /// A trace + span, a session + span or a turn index is what proves two
    /// lines are one event; a timestamp is **not** an identity, because two
    /// different requests can share one. A record that names none of those
    /// therefore keeps its own ordinal and is never folded with another —
    /// over-counting two copies of one unnamed event is preferred to deleting a
    /// different request that happened to land on the same instant.
    ///
    /// A response id is an identity only for an **inference log**, which is one
    /// record per response: a replay of it collapses. A chat span is not keyed
    /// by response id, because several spans can belong to one response and
    /// folding them would delete work; the response id is still used for
    /// cross-lane suppression below.
    private static func dedupKey(
        lane: Lane,
        identity: (trace: String?, span: String?),
        session: String?,
        response: String?,
        index: Int,
        turn: String?,
        ordinal: Int
    ) -> String {
        switch lane {
        case .chatSpan, .agentSummarySpan:
            if let trace = identity.trace, let span = identity.span { return "\(trace):\(span)" }
            if let session, let span = identity.span { return "span:\(session):\(span)" }
            return "span-unnamed:\(ordinal)"
        case .inferenceLog:
            if let trace = identity.trace, let span = identity.span { return "log:\(trace):\(span)" }
            if let response { return "log-response:\(response)" }
            return "log-unnamed:\(ordinal)"
        case .agentTurnLog:
            if let trace = identity.trace {
                return "agent-turn:\(trace):\(turn ?? "idx-\(index)")"
            }
            return "agent-turn-unnamed:\(ordinal)"
        }
    }

    // MARK: - Tokens

    /// The four disjoint kinds, plus a bare total that named no kind at all.
    private static func counts(_ attributes: [String: Any]) -> (tally: TokenTally, unclassified: Int) {
        let input = AgentLogIO.count(attributes["gen_ai.usage.input_tokens"]) ?? 0
        let output = AgentLogIO.count(attributes["gen_ai.usage.output_tokens"]) ?? 0
        let cacheRead = firstPositive(attributes, [
            "gen_ai.usage.cache_read.input_tokens",
            "gen_ai.usage.cache_read_input_tokens",
        ])
        let cacheWrite = firstPositive(attributes, [
            "gen_ai.usage.cache_write.input_tokens",
            "gen_ai.usage.cache_creation.input_tokens",
            "gen_ai.usage.cache_write_input_tokens",
            "gen_ai.usage.cache_creation_input_tokens",
        ])
        let reasoning = firstPositive(attributes, [
            "gen_ai.usage.reasoning.output_tokens",
            "gen_ai.usage.reasoning_tokens",
        ])

        let namesAKind = input > 0 || output > 0 || cacheRead > 0 || cacheWrite > 0 || reasoning > 0
        if !namesAKind {
            // A total with no split is real work Pulse cannot place; it is
            // counted as unclassified and never put into the input bucket.
            let total = AgentLogIO.count(attributes["gen_ai.usage.total_tokens"])
                ?? AgentLogIO.count(attributes["gen_ai.usage.total.tokens"])
                ?? AgentLogIO.count(attributes["total_tokens"])
            return (TokenTally(), total.map { max($0, 0) } ?? 0)
        }

        // Input includes the cache read; remove it once. Reasoning is a subset
        // of output, so it is left inside output and only stands in alone when
        // output was not reported.
        let freshInput = max(input - min(cacheRead, input), 0)
        let foldedOutput = output > 0 ? output : reasoning
        return (
            TokenTally(
                input: freshInput, cacheWrite: cacheWrite, cacheRead: cacheRead, output: foldedOutput
            ),
            0
        )
    }

    private static func firstPositive(_ attributes: [String: Any], _ keys: [String]) -> Int {
        for key in keys {
            if let value = AgentLogIO.count(attributes[key]), value > 0 { return value }
        }
        return 0
    }

    private static func textValue(_ value: Any?) -> String? {
        if let text = AgentLogIO.text(value) { return text }
        if let number = AgentLogIO.count(value) { return String(number) }
        return nil
    }

    // MARK: - Time

    /// The first usable timing key, in the format's own order.
    ///
    /// A numeric `duration` is taken as milliseconds, matching the scalar
    /// timings here, and is only consulted to back-calculate a start from an
    /// `endTime` when no start was written.
    private static func timestamp(_ row: [String: Any]) -> Date? {
        if let value = row["startTime"], let date = AgentLogIO.timestamp(value) { return date }

        if let value = row["endTime"], let end = AgentLogIO.timestamp(value) {
            if let duration = duration(row) { return end.addingTimeInterval(-duration) }
            return end
        }

        for key in ["hrTime", "_hrTime"] {
            if let pair = row[key] as? [Any], !pair.isEmpty,
               let seconds = AgentLogIO.count(pair[0]) {
                let nanos = pair.count > 1 ? (AgentLogIO.count(pair[1]) ?? 0) : 0
                return Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1_000_000_000)
            }
        }

        for key in ["time", "timestamp", "observedTimestamp"] {
            if let value = row[key], let date = AgentLogIO.timestamp(value) { return date }
        }

        if let value = row["timeUnixNano"], let nanos = AgentLogIO.count(value) {
            return Date(timeIntervalSince1970: Double(nanos) / 1_000_000_000)
        }
        return nil
    }

    private static func duration(_ row: [String: Any]) -> TimeInterval? {
        guard let value = row["duration"] else { return nil }
        if let milliseconds = AgentLogIO.count(value) { return Double(milliseconds) / 1000 }
        if let object = value as? [String: Any],
           let start = object["startTime"].flatMap({ AgentLogIO.timestamp($0) }),
           let end = object["endTime"].flatMap({ AgentLogIO.timestamp($0) }) {
            return end.timeIntervalSince(start)
        }
        return nil
    }

    // MARK: - Resolving

    private static func resolve(_ candidates: [Candidate]) -> [AgentUsageRecord] {
        // Same-key copies collapse first, then a higher lane drops a lower one
        // that shares a trace or response id.
        var byKey: [String: Candidate] = [:]
        for candidate in candidates {
            if let existing = byKey[candidate.key] {
                byKey[candidate.key] = existing.merged(with: candidate)
            } else {
                byKey[candidate.key] = candidate
            }
        }

        let deduped = byKey.values.sorted { lhs, rhs in
            lhs.key < rhs.key
        }

        var traces: [Lane: Set<String>] = [:]
        var responses: [Lane: Set<String>] = [:]
        for candidate in deduped {
            if let trace = candidate.trace { traces[candidate.lane, default: []].insert(trace) }
            if let response = candidate.response {
                responses[candidate.lane, default: []].insert(response)
            }
        }

        var kept: [Candidate] = []
        for candidate in deduped {
            let suppressed = Lane.allCases.contains { higher in
                guard higher.rawValue < candidate.lane.rawValue else { return false }
                if let trace = candidate.trace, traces[higher]?.contains(trace) == true { return true }
                if let response = candidate.response,
                   responses[higher]?.contains(response) == true { return true }
                return false
            }
            if !suppressed { kept.append(candidate) }
        }

        return kept.compactMap { candidate in
            StructuredLogSupport.record(
                timestamp: candidate.timestamp,
                model: candidate.model,
                tally: candidate.tally,
                unclassified: candidate.unclassified,
                isPartial: candidate.isPartial,
                sessionID: candidate.sessionID,
                sessionName: CopilotLogReader.agentLabel(candidate.agent),
                deduplicationID: "copilot-otel:\(candidate.key)"
            )
        }
    }
}
