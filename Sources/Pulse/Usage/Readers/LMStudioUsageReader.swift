// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// LM Studio's server logs.
///
/// `~/.lmstudio/server-logs/**/*.log` is pretty-printed OpenAI-compatible
/// server output, so the usage is **not** one JSON object per line. Each
/// response ends with a balanced `"usage": { … }` block, and the response `id`,
/// `model` and a local log timestamp sit in the text just before it. This
/// reader finds those blocks, reads the facts around them, and keeps no part of
/// a prompt or a completion body.
///
/// **The timestamp is the log line's own and nothing else.** A block with no
/// local `YYYY-MM-DD HH:MM:SS` prefix is skipped; the file's modification time
/// or the current clock is never used to fill one in.
///
/// **The prompt is cache-inclusive and completion includes reasoning.** Cache
/// read and cache write are clamped to the prompt, the total is at least
/// prompt + completion, and fresh input is the total minus everything already
/// accounted for — including completion, which is kept whole because its
/// `reasoning_tokens` detail is a subset Pulse's output bucket already counts
/// once. Reasoning is not subtracted and not carried as unknown, so no output
/// is dropped and none is double counted. Local inference has no money behind
/// it, so no cost is read.
enum LMStudioUsageReader {
    private static let promptKeys = ["prompt_tokens", "promptTokens", "input_tokens", "inputTokens"]
    private static let completionKeys = [
        "completion_tokens", "completionTokens", "output_tokens", "outputTokens",
    ]
    private static let totalKeys = ["total_tokens", "totalTokens"]
    private static let promptDetailKeys = [
        "prompt_tokens_details", "input_tokens_details", "inputTokensDetails",
    ]
    private static let outputDetailKeys = [
        "output_tokens_details", "completion_tokens_details", "outputTokensDetails",
    ]

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []

        for file in AgentLogIO.files(in: roots, extensions: ["log"]) {
            guard !Task.isCancelled else { return [] }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let path = StructuredLogSupport.path(file)

            var cursor = text.startIndex
            while let marker = text.range(of: "\"usage\"", range: cursor..<text.endIndex) {
                guard !Task.isCancelled else { return [] }
                guard let block = usageBlock(in: text, after: marker.upperBound) else {
                    cursor = marker.upperBound
                    continue
                }
                cursor = block.end

                guard
                    let value = try? JSONSerialization.jsonObject(with: Data(block.json.utf8)),
                    let usage = value as? [String: Any]
                else { continue }

                let context = precedingContext(of: marker.lowerBound, in: text)
                guard let timestamp = logTimestamp(context) else { continue }
                guard let model = lastCapture("\"model\"\\s*:\\s*\"([^\"]*)\"", in: context) else { continue }

                let resolved = counts(usage)
                guard resolved.any else { continue }

                let offset = text.distance(from: text.startIndex, to: marker.lowerBound)
                let identity = lastCapture("\"id\"\\s*:\\s*\"([^\"]*)\"", in: context)
                    ?? StructuredLogSupport.hash(
                        "\(path):\(offset):\(model):\(resolved.tally.input):"
                            + "\(resolved.tally.cacheWrite):\(resolved.tally.cacheRead):\(resolved.tally.output)"
                    )

                guard
                    let record = StructuredLogSupport.record(
                        timestamp: timestamp,
                        model: model,
                        tally: resolved.tally,
                        unclassified: resolved.unclassified,
                        sessionID: "lmstudio:\(path)",
                        sessionName: file.lastPathComponent,
                        deduplicationID: "lmstudio:\(identity)"
                    )
                else { continue }
                records.append(record)
            }
        }

        return records
    }

    /// The usage counts, with the cache and reasoning clamps applied.
    private static func counts(
        _ usage: [String: Any]
    ) -> (tally: TokenTally, unclassified: Int, any: Bool) {
        let prompt = StructuredLogSupport.count(usage, promptKeys)
        let completion = StructuredLogSupport.count(usage, completionKeys)
        let reportedTotal = StructuredLogSupport.count(usage, totalKeys)

        let promptDetails = promptDetailKeys.compactMap { AgentLogIO.object(usage[$0]) }.first
        let outputDetails = outputDetailKeys.compactMap { AgentLogIO.object(usage[$0]) }.first

        let cached = StructuredLogSupport.count(promptDetails ?? [:], ["cached_tokens"])
            ?? StructuredLogSupport.count(usage, ["cached_tokens"])
        let cacheCreation = StructuredLogSupport.count(promptDetails ?? [:], ["cache_creation_input_tokens"])
            ?? StructuredLogSupport.count(usage, ["cache_creation_input_tokens"])
        let reasoning = StructuredLogSupport.count(outputDetails ?? [:], ["reasoning_tokens"])
            ?? StructuredLogSupport.count(usage, ["reasoning_tokens"])

        // A bare total with no prompt/completion is real but unclassifiable.
        if prompt == nil, completion == nil {
            guard let reportedTotal, reportedTotal > 0 else {
                return (TokenTally(), 0, false)
            }
            return (TokenTally(), reportedTotal, true)
        }

        let promptTokens = prompt ?? 0
        let completionTokens = completion ?? 0
        let cacheRead = min(cached ?? 0, promptTokens)
        let cacheWrite = min(cacheCreation ?? 0, max(0, promptTokens - cacheRead))
        // `reasoning_tokens` is a detail of completion, so it is already in the
        // output bucket; it is read only to keep the argument explicit.
        let reasoningTokens = min(reasoning ?? 0, completionTokens)
        let total = max(reportedTotal ?? 0, promptTokens + completionTokens)
        let input = max(0, total - completionTokens - cacheRead - cacheWrite)

        let tally = TokenTally(
            input: input,
            cacheWrite: cacheWrite,
            cacheRead: cacheRead,
            output: StructuredLogSupport.output(
                reported: completionTokens,
                reasoning: reasoningTokens,
                relationship: .includedInOutput
            )
        )
        return (tally, 0, true)
    }

    // MARK: - Text scanning

    /// The balanced `{ … }` after a `"usage"` key, and where it ends.
    private static func usageBlock(
        in text: String,
        after keyEnd: String.Index
    ) -> (json: String, end: String.Index)? {
        var index = keyEnd
        while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
        guard index < text.endIndex, text[index] == ":" else { return nil }
        index = text.index(after: index)
        while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
        guard index < text.endIndex, text[index] == "{" else { return nil }

        let start = index
        var depth = 0
        var inString = false
        var escaped = false

        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let end = text.index(after: index)
                    return (String(text[start..<end]), end)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Up to 4 KB of text before the block, where the response's facts sit.
    private static func precedingContext(of start: String.Index, in text: String) -> String {
        guard
            let contextStart = text.index(start, offsetBy: -4096, limitedBy: text.startIndex)
        else { return String(text[text.startIndex..<start]) }
        return String(text[contextStart..<start])
    }

    /// The last capture of `pattern` in `text`, so an id repeated in a listing
    /// resolves to the one nearest the block.
    private static func lastCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.matches(in: text, range: range).last,
            match.numberOfRanges > 1,
            let captured = Range(match.range(at: 1), in: text)
        else { return nil }
        return StructuredLogSupport.nonBlank(String(text[captured]))
    }

    /// The local `YYYY-MM-DD HH:MM:SS` prefix nearest the block, parsed in the
    /// machine's own time zone.
    private static func logTimestamp(_ text: String) -> Date? {
        guard
            let raw = lastCapture("(\\d{4}-\\d{2}-\\d{2}[ T]\\d{2}:\\d{2}:\\d{2})", in: text)
        else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: raw.replacingOccurrences(of: "T", with: " "))
    }
}
