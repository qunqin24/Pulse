import Foundation

/// OpenCodeReview's session logs.
///
/// One JSONL per session under `sessions/<encoded-repo>/`. A `session_start`
/// line names the working directory and default model; each `llm_response`
/// carries the response's own usage.
///
/// **The cache relation is not assumed.** OpenCodeReview's own resolver
/// (`internal/llm/usage_resolver.go`) treats the cache counts as *included* in
/// `prompt_tokens` under OpenAI semantics and as *exclusive* under Anthropic
/// semantics, and the persisted `llm_response.usage` writes only
/// `prompt_tokens`, `completion_tokens`, `cache_read_tokens` and
/// `cache_write_tokens` — **no total and no record of which provider path the
/// cache came from**. A bare sum could therefore bill the same tokens twice.
/// The store's own total, where a variant carries one, is what settles it:
///
/// - `total == prompt + completion + cacheRead + cacheWrite` → the four kinds
///   are disjoint and are counted as reported.
/// - `total == prompt + completion` (and not the above) → prompt already
///   contains the cache, so the cache overlap is removed from the input.
/// - any other total → the relation cannot be established, so the record
///   carries the total in `unclassifiedTokens` with an empty tally rather than
///   a guessed split that would price a double count.
/// - **no total** and a positive cache count → the relation is unproven, so no
///   record is emitted at all. This is the ordinary persisted shape; when some
///   readable records remain they are marked `isPartial`, because the source
///   said more than Pulse can prove.
/// - **no total** and no cache count → nothing can overlap, so input and
///   completion are counted as reported.
///
/// A `llm_response` line carries a real `uuid`; a replayed `uuid` folds once
/// while two equal requests in one second stay two. A line with no `uuid`
/// falls back to the **file's own content digest plus its line position**, so
/// a whole-file mirror folds but two different files that happen to share a
/// session id and restart at line zero are both kept.
enum OpenCodeReviewReader {
    static let supportedClients: Set<String> = ["opencodereview"]

    static func inputs(home: URL) -> [URL] {
        [home.appending(path: ".opencodereview/sessions")]
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["jsonl"]).sorted { $0.path < $1.path }
        var seen: Set<String> = []
        var records: [AgentUsageRecord] = []
        var skippedUnprovable = false

        for file in files {
            let parsed = parse(file)
            skippedUnprovable = skippedUnprovable || parsed.skippedUnprovable
            for record in parsed.records {
                if let id = record.deduplicationID {
                    guard seen.insert(id).inserted else { continue }
                }
                records.append(record)
            }
        }

        // A recognized usage was dropped because its cache relation could not
        // be proven; what remains is a confirmed subset, not the whole.
        if skippedUnprovable {
            return records.map { marking($0, partial: true) }
        }
        return records
    }

    private static func marking(_ record: AgentUsageRecord, partial: Bool) -> AgentUsageRecord {
        guard partial else { return record }
        var copy = record
        copy.isPartial = true
        return copy
    }

    private static func parse(_ file: URL) -> (records: [AgentUsageRecord], skippedUnprovable: Bool) {
        guard let fragment = AgentLogIO.digest(at: file) else {
            return ([], false)
        }
        let rows = AgentLogIO.jsonLines(at: file)
        // The file's own digest is a deterministic fragment identity: a
        // byte-identical mirror shares it, two different files do not.
        let stem = file.deletingPathExtension().lastPathComponent

        var sessionFromStart: String?
        var cwd: String?
        var startModel: String?
        for row in rows where AgentLogIO.text(row["type"]) == "session_start" {
            sessionFromStart = EditorLog.nonBlank(AgentLogIO.text(row["sessionId"])) ?? sessionFromStart
            cwd = EditorLog.nonBlank(AgentLogIO.text(row["cwd"])) ?? cwd
            startModel = EditorLog.modelID(AgentLogIO.text(row["model"])) ?? startModel
        }

        var records: [AgentUsageRecord] = []
        var skippedUnprovable = false
        for (index, row) in rows.enumerated() where AgentLogIO.text(row["type"]) == "llm_response" {
            guard
                let end = AgentLogIO.timestamp(row["timestamp"], milliseconds: true),
                let usage = AgentLogIO.object(row["usage"])
            else { continue }

            let reduction = Self.parts(usage)
            if reduction.unprovable {
                skippedUnprovable = true
                continue
            }
            let parts = reduction.parts
            guard parts.tally.total + parts.unclassified > 0 else { continue }

            // A real end timestamp plus a positive duration puts the request's
            // start at the end minus the duration.
            let duration = AgentLogIO.count(row["duration_ms"]) ?? 0
            let start = duration > 0
                ? end.addingTimeInterval(-Double(duration) / 1000)
                : end

            let session = EditorLog.nonBlank(AgentLogIO.text(row["sessionId"]))
                ?? sessionFromStart
                ?? stem
            let model = EditorLog.modelID(AgentLogIO.text(row["model"])) ?? startModel
            guard let model else { continue }

            // The record's own `uuid` is a real per-request identity. Without
            // one, the file digest keeps two same-session fragments apart while
            // still folding a byte-identical mirror.
            let identity = EditorLog.nonBlank(AgentLogIO.text(row["uuid"]))
                .map { "opencodereview:\(session):uuid:\($0)" }
                ?? "opencodereview:\(session):fragment:\(fragment):line:\(index)"

            records.append(
                EditorLog.record(
                    timestamp: start,
                    model: model,
                    tally: parts.tally,
                    sessionID: session,
                    project: cwd,
                    deduplicationID: identity,
                    unclassifiedTokens: parts.unclassified
                )
            )
        }
        return (records, skippedUnprovable)
    }

    /// One usage object reduced, or a flag that it cannot be split.
    private struct Reduction {
        var parts: EditorLog.UsageParts
        /// The usage names a positive cache count but carries no total to say
        /// whether the cache is already inside `prompt_tokens`.
        var unprovable = false
    }

    private static func parts(_ usage: [String: Any]) -> Reduction {
        let prompt = EditorLog.firstCount(usage, ["prompt_tokens", "promptTokens"])
        let completion = EditorLog.firstCount(usage, ["completion_tokens", "completionTokens"])
        let cacheRead = EditorLog.firstCount(usage, ["cache_read_tokens", "cacheReadTokens"])
        let cacheWrite = EditorLog.firstCount(usage, ["cache_write_tokens", "cacheWriteTokens"])
        let total = EditorLog.firstCount(usage, ["total_tokens", "totalTokens", "total"])

        let namesAKind = prompt != nil || completion != nil || cacheRead != nil || cacheWrite != nil
        if !namesAKind, let total, total > 0 {
            return Reduction(parts: EditorLog.UsageParts(tally: TokenTally(), unclassified: total))
        }

        let promptValue = prompt ?? 0
        let completionValue = completion ?? 0
        let cacheReadValue = cacheRead ?? 0
        let cacheWriteValue = cacheWrite ?? 0
        let disjoint = promptValue + completionValue + cacheReadValue + cacheWriteValue

        // A total of zero is not a usable total; it is treated as absent.
        if let total, total > 0 {
            if total == disjoint {
                // The total names every kind, so the four are disjoint.
                return Reduction(
                    parts: EditorLog.UsageParts(
                        tally: TokenTally(
                            input: promptValue, cacheWrite: cacheWriteValue,
                            cacheRead: cacheReadValue, output: completionValue
                        )
                    )
                )
            }
            if total == promptValue + completionValue, total != disjoint {
                // The total is only prompt + completion, so prompt already
                // contains the cache counts.
                return Reduction(
                    parts: EditorLog.UsageParts(
                        tally: TokenTally(
                            input: max(0, promptValue - cacheReadValue - cacheWriteValue),
                            cacheWrite: cacheWriteValue, cacheRead: cacheReadValue,
                            output: completionValue
                        )
                    )
                )
            }
            // The total fits neither shape: keep it whole rather than price a
            // split that could double count.
            return Reduction(parts: EditorLog.UsageParts(tally: TokenTally(), unclassified: total))
        }

        // No total to settle the overlap. With no cache there is nothing that
        // could overlap; with a positive cache the split is unproven and no
        // complete-looking number may be produced.
        guard cacheReadValue == 0, cacheWriteValue == 0 else {
            return Reduction(parts: EditorLog.UsageParts(tally: TokenTally()), unprovable: true)
        }
        return Reduction(parts: EditorLog.UsageParts(tally: TokenTally(input: promptValue, output: completionValue)))
    }
}
