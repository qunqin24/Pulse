// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Jcode's sessions and their append-only journals.
///
/// `~/.jcode/sessions/session_*.json` (or `$JCODE_HOME/sessions`) carries
/// `id`, `provider_key`, `model`, `working_dir` and `messages[]`; the sidecar
/// `session_*.journal.jsonl` carries lines of
/// `{ "meta": {...}, "append_messages": [...] }`. The journal is replayed into
/// the session before anything is emitted, so a message written once and
/// replayed once is one record.
///
/// **A message's cache shape is settled only by an explicit marker.** The
/// Anthropic-style `cache_creation_input_tokens` key means `input_tokens` is
/// already cache-exclusive; an OpenAI-native details object (`prompt_tokens_details`
/// and its spellings) means the cached tokens are a subset of input. A positive
/// `cache_read_input_tokens` with **neither** marker is ambiguous: the input is
/// carried in `unclassifiedTokens` — never priced as fresh — the cache is not
/// added, and the record is marked partial, because whether the cache is
/// separate work cannot be confirmed. Magnitude is never used to infer the
/// convention; a `cache_read` larger than `input` is not evidence of a schema.
///
/// **Reasoning is left out and marks the record partial.** Jcode reports
/// `reasoning_output_tokens` beside output and gives no token total, so nothing
/// says whether it is already inside output. Pulse's output bucket counts
/// reasoning once: adding it would double it when it is a subset, and carrying
/// it in `unclassifiedTokens` would add it to the grand total the same way. The
/// reported output is kept, the ambiguous reasoning figure is not counted, and
/// the record is marked `isPartial` so the shortfall is visible rather than
/// silent.
///
/// A message with no `token_usage` emits nothing, and a message whose timestamp
/// is missing is skipped rather than dated from the file.
enum JcodeUsageReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []

        let files = AgentLogIO.files(in: roots, extensions: ["json", "jsonl"])
            .filter { $0.lastPathComponent.hasPrefix("session_") }

        for file in files {
            guard file.pathExtension == "json" else { continue }
            guard let session = AgentLogIO.object(AgentLogIO.json(at: file)) else { continue }

            let sessionID = AgentLogIO.text(session["id"])
                ?? Self.stem(of: file)
            let workspace = AgentLogIO.text(session["working_dir"])
            let sessionModel = AgentLogIO.text(session["model"])
            let provider = AgentLogIO.text(session["provider_key"])

            var messages: [(message: [String: Any], model: String?)] = []
            if let rows = session["messages"] as? [[String: Any]] {
                messages.append(contentsOf: rows.map { ($0, sessionModel) })
            }

            // Journal lines update the session's model/provider/workspace as
            // they are replayed, so a message takes the meta that was current
            // when it was appended.
            var journalModel = sessionModel
            for line in AgentLogIO.jsonLines(at: Self.journal(beside: file)) {
                if let meta = AgentLogIO.object(line["meta"]) {
                    journalModel = AgentLogIO.text(meta["model"]) ?? journalModel
                }
                if let appended = line["append_messages"] as? [[String: Any]] {
                    messages.append(contentsOf: appended.map { ($0, journalModel) })
                }
            }

            for (message, model) in messages {
                guard let usage = AgentLogIO.object(message["token_usage"]) else { continue }
                guard let timestamp = StructuredLogSupport.eventTime(message["timestamp"]) else { continue }

                let reportedInput = AgentLogIO.count(usage["input_tokens"]) ?? 0
                let cacheRead = AgentLogIO.count(usage["cache_read_input_tokens"]) ?? 0
                let cacheWrite = AgentLogIO.count(usage["cache_creation_input_tokens"]) ?? 0
                let reportedOutput = AgentLogIO.count(usage["output_tokens"]) ?? 0
                let reasoning = AgentLogIO.count(usage["reasoning_output_tokens"]) ?? 0

                let output = StructuredLogSupport.output(
                    reported: reportedOutput,
                    reasoning: reasoning,
                    relationship: .unknown
                )

                let tally: TokenTally
                var unclassified = 0
                // Reasoning is relationally unknown, and an input whose cache
                // relationship is unproven is not priced as fresh.
                var isPartial = reasoning > 0

                switch cacheShape(usage) {
                case .anthropicDisjoint:
                    // The schema states input excludes the cache.
                    tally = TokenTally(
                        input: reportedInput, cacheWrite: cacheWrite,
                        cacheRead: cacheRead, output: output
                    )

                case .openAIContained:
                    // An explicit native details field states the cache is a
                    // subset of the input.
                    tally = TokenTally(
                        input: max(0, reportedInput - min(cacheRead, reportedInput)),
                        cacheWrite: cacheWrite, cacheRead: cacheRead, output: output
                    )

                case .ambiguous:
                    if cacheRead > 0 {
                        // A positive cache with no distinguishing marker and no
                        // total: the input may or may not already contain it, so
                        // it cannot be priced as fresh. The known output stands
                        // and the reported input is carried unclassified, with
                        // the record marked partial because the cache may still
                        // be separate work.
                        tally = TokenTally(output: output)
                        unclassified = reportedInput
                        isPartial = true
                    } else {
                        // No cache is in play, so the input is fresh.
                        tally = TokenTally(input: reportedInput, output: output)
                    }
                }

                let name = AgentLogIO.text(message["id"])
                    ?? "\(sessionID):\(timestamp.timeIntervalSince1970):\(model ?? ""):"
                        + "\(reportedInput):\(cacheWrite):\(cacheRead):\(reportedOutput)"

                guard
                    let record = StructuredLogSupport.record(
                        timestamp: timestamp,
                        model: model ?? sessionModel,
                        tally: tally,
                        unclassified: unclassified,
                        isPartial: isPartial,
                        sessionID: sessionID,
                        sessionName: provider,
                        project: StructuredLogSupport.project(workspace),
                        deduplicationID: "jcode:\(sessionID):\(name)"
                    )
                else { continue }
                records.append(record)
            }
        }

        return records
    }

    /// How a usage object says its cached tokens relate to its input.
    ///
    /// **Only an explicit marker settles it.** The Anthropic-style
    /// `cache_creation_input_tokens` key means input is cache-exclusive; an
    /// OpenAI-native details object means the cached tokens are a subset of
    /// input. Anything else — a positive `cache_read_input_tokens` with neither
    /// marker — is `ambiguous`, and its input is left unclassified rather than
    /// guessed into a fresh kind.
    enum CacheShape {
        case anthropicDisjoint
        case openAIContained
        case ambiguous
    }

    static func cacheShape(_ usage: [String: Any]) -> CacheShape {
        if usage.keys.contains("cache_creation_input_tokens") { return .anthropicDisjoint }
        let nativeDetails = [
            "prompt_tokens_details", "promptTokensDetails",
            "input_tokens_details", "inputTokensDetails",
        ]
        if nativeDetails.contains(where: { usage[$0] != nil }) { return .openAIContained }
        return .ambiguous
    }

    /// `session_abc.json` → `session_abc`.
    private static func stem(of file: URL) -> String {
        let name = file.lastPathComponent
        guard name.hasSuffix(".json") else { return name }
        return String(name.dropLast(".json".count))
    }

    /// The journal beside a session file, whether or not it exists.
    private static func journal(beside file: URL) -> URL {
        file.deletingLastPathComponent().appending(path: "\(stem(of: file)).journal.jsonl")
    }
}
