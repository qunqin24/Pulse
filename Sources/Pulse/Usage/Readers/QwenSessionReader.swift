// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Qwen Code's chat transcripts.
///
/// `~/.qwen/projects/<projectPath>/chats/*.jsonl`, one line per event, and only
/// an `assistant` line with a `usageMetadata` object carries a count.
///
/// **The field set is Gemini's documented `usageMetadata`, and Qwen normalizes
/// every backend into it.** Google documents `promptTokenCount` as *including*
/// the cached content, and `totalTokenCount` as `prompt + candidates + tool +
/// thoughts`. So the fresh input is the prompt minus the cache read — the two
/// are not disjoint — and reasoning (`thoughtsTokenCount`) is billed as output,
/// added once.
///
/// The declared `totalTokenCount` is used as a check when present: it can prove
/// the cache read sits inside the prompt (subtract) or beside it (disjoint), and
/// when neither identity holds the total is carried as `unclassifiedTokens`
/// rather than split on a guess. With no total, the documented field semantics
/// above are what decide the relation; a line whose cache relation could not be
/// established is not turned into a complete-looking count.
///
/// Record identity prefers the line's own message id. Lines without one are
/// keyed by the **file fragment's content digest plus their emitted position**,
/// so two different fragments of one session never collide on a shared starting
/// index, while a byte-identical mirror of one file still folds.
enum QwenSessionReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []
        var incomplete = false

        for file in AgentLogIO.files(in: roots, extensions: ["jsonl"]) {
            guard let fragment = AgentLogIO.digest(at: file) else { continue }
            let project = projectSegment(file)
            let fileStem = file.deletingPathExtension().lastPathComponent
            let fallbackID = [project, fileStem].compactMap { $0 }.joined(separator: "-")

            var emitted = 0
            for row in AgentLogIO.jsonLines(at: file) {
                guard row["type"] as? String == "assistant" else { continue }
                guard let metadata = row["usageMetadata"] as? [String: Any] else { continue }
                guard let usage = decode(metadata) else { continue }
                guard usage.tally.total > 0 || usage.unclassified > 0 else { continue }
                guard
                    let model = AgentLogIO.text(row["model"]),
                    let timestamp = AgentLogIO.timestamp(row["timestamp"])
                else {
                    // Real usage with no model or no locatable time.
                    incomplete = true
                    continue
                }

                let sessionID = AgentLogIO.text(row["sessionId"]) ?? fallbackID
                let messageID = AgentLogIO.text(row["id"]) ?? AgentLogIO.text(row["messageId"])
                let identity = messageID.map { "\(sessionID):\($0)" }
                    ?? "\(sessionID):\(fragment):\(emitted)"

                records.append(
                    AgentUsageRecord(
                        timestamp: timestamp,
                        model: model,
                        tally: usage.tally,
                        sessionID: sessionID,
                        project: project,
                        deduplicationID: "qwen:\(identity)",
                        unclassifiedTokens: usage.unclassified
                    )
                )
                emitted += 1
            }
        }
        return incomplete ? records.map(Self.markedPartial) : records
    }

    private static func markedPartial(_ record: AgentUsageRecord) -> AgentUsageRecord {
        var copy = record
        copy.isPartial = true
        return copy
    }

    /// Decodes one Gemini-shaped `usageMetadata` object.
    ///
    /// Nil when nothing countable was reported or every field is zero. A
    /// reported total that cannot be reconciled to a split is carried as
    /// `unclassifiedTokens`, never distributed across kinds.
    static func decode(_ metadata: [String: Any]) -> (tally: TokenTally, unclassified: Int)? {
        let prompt = AgentLogIO.count(metadata["promptTokenCount"])
        let candidates = AgentLogIO.count(metadata["candidatesTokenCount"])
        let thoughts = AgentLogIO.count(metadata["thoughtsTokenCount"])
        let cached = AgentLogIO.count(metadata["cachedContentTokenCount"])
        let total = AgentLogIO.count(metadata["totalTokenCount"])
            ?? AgentLogIO.count(metadata["total"])
            ?? AgentLogIO.count(metadata["total_tokens"])

        let any = prompt != nil || candidates != nil || thoughts != nil
            || cached != nil || total != nil
        guard any else { return nil }

        let promptCount = prompt ?? 0
        let cachedCount = cached ?? 0
        // Gemini bills thinking as output; the normalized output bucket holds it
        // once.
        let output = (candidates ?? 0) + (thoughts ?? 0)

        if let total {
            let included = promptCount + output
            let disjoint = promptCount + cachedCount + output
            if cachedCount == 0 {
                guard total == included else { return (TokenTally(), total) }
                return (TokenTally(input: promptCount, cacheWrite: 0, cacheRead: 0, output: output), 0)
            }
            if total == included, total != disjoint {
                // Proven: the cache read is inside the prompt.
                return (
                    TokenTally(
                        input: max(0, promptCount - cachedCount),
                        cacheWrite: 0, cacheRead: cachedCount, output: output
                    ),
                    0
                )
            }
            if total == disjoint, total != included {
                // Proven: the cache read sits beside the prompt.
                return (
                    TokenTally(input: promptCount, cacheWrite: 0, cacheRead: cachedCount, output: output),
                    0
                )
            }
            // Reported total that matches neither identity: keep the total, name
            // no kind.
            return (TokenTally(), total)
        }

        // No total. The documented field semantics (prompt includes the cached
        // content) are what the four buckets are derived from.
        return (
            TokenTally(
                input: max(0, promptCount - cachedCount),
                cacheWrite: 0, cacheRead: cachedCount, output: output
            ),
            0
        )
    }

    /// The `<projectPath>` segment between `projects/` and `chats/`.
    static func projectSegment(_ url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.lastIndex(of: "projects"), index + 1 < components.count else {
            return nil
        }
        return components[index + 1].isEmpty ? nil : components[index + 1]
    }

}
