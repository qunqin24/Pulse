// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Reasonix's daily stats files.
///
/// `~/.reasonix/stats/YYYY-MM-DD.jsonl` (`$REASONIX_STATE_HOME`, or
/// `$REASONIX_HOME/stats`) holds one aggregate per request group:
/// `{ "ts", "model", "prompt", "completion", "reasoning", "cache_hit",
///    "cache_miss", "total", "requests", "turn" }`. The session transcript is
/// deliberately not scanned: it has no authoritative counters and would
/// overlap these.
///
/// **Only real, non-empty rows count.** A `turn == true` marker, an empty
/// model, and a row whose `total` and `requests` are both non-positive are all
/// skipped — the first is not a call, the second names nothing, and the third
/// is a row that reported nothing.
///
/// **Cache hit is the read, cache miss the fresh input.** When `cache_miss` is
/// present and positive it is the fresh input; otherwise it is `prompt −
/// cache_hit`. **Reasoning is a subset of completion** — the format reports it
/// as a count within the completion — so the completion is kept whole as
/// output; subtracting reasoning and counting it a second time would drop real
/// output or double it. There is no cache-write figure in this format, so it
/// is zero.
///
/// `model` is written as `provider/model` and is kept exactly as reported; the
/// provider prefix is not stripped, because guessing which spelling a price
/// table wants is not this reader's job.
enum ReasonixUsageReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []

        for file in AgentLogIO.files(in: roots, extensions: ["jsonl"]) {
            guard !Task.isCancelled else { return [] }
            let path = StructuredLogSupport.path(file)

            var lineIndex = 0
            for raw in LogLines(at: file) {
                lineIndex += 1
                guard
                    let value = try? JSONSerialization.jsonObject(with: Data(raw)),
                    let row = value as? [String: Any]
                else { continue }

                // `turn` is a marker, not a call.
                if (row["turn"] as? Bool) == true { continue }
                guard let model = AgentLogIO.text(row["model"]) else { continue }

                let total = AgentLogIO.count(row["total"])
                let requests = AgentLogIO.count(row["requests"])
                guard (total ?? 0) > 0 || (requests ?? 0) > 0 else { continue }
                guard let timestamp = StructuredLogSupport.eventTime(row["ts"]) else { continue }

                let prompt = AgentLogIO.count(row["prompt"])
                let completion = AgentLogIO.count(row["completion"])
                let reasoning = AgentLogIO.count(row["reasoning"]) ?? 0
                let cacheRead = AgentLogIO.count(row["cache_hit"]) ?? 0

                let tally: TokenTally
                let unclassified: Int
                if prompt == nil, completion == nil {
                    // A bare total: real, but with no split to place it in.
                    tally = TokenTally()
                    unclassified = total ?? 0
                } else {
                    let miss = AgentLogIO.count(row["cache_miss"]) ?? 0
                    let input = miss > 0 ? miss : max(0, (prompt ?? 0) - cacheRead)
                    tally = TokenTally(
                        input: input, cacheWrite: 0, cacheRead: cacheRead,
                        output: StructuredLogSupport.output(
                            reported: completion ?? 0,
                            reasoning: min(reasoning, completion ?? 0),
                            relationship: .includedInOutput
                        )
                    )
                    unclassified = 0
                }

                guard
                    let record = StructuredLogSupport.record(
                        timestamp: timestamp,
                        model: model,
                        tally: tally,
                        unclassified: unclassified,
                        sessionID: "reasonix-stats:\(path)",
                        sessionName: "reasonix",
                        deduplicationID: "reasonix:\(path):\(lineIndex):\(requests ?? 0):\(total ?? 0)"
                    )
                else { continue }
                records.append(record)
            }
        }

        return records
    }
}
