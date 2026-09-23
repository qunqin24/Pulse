import Foundation

/// Grok Build's transcripts.
///
/// `~/.grok/sessions/<directory>/<session id>/updates.jsonl`, where the
/// directory is the working directory **percent-encoded** — `%2FUsers%2Fme%2FCode`
/// — which is the one agent here that gives its project away in the path
/// without losing anything.
///
/// One line per event, and the one that counts is the end of a turn:
///
/// ```json
/// { "timestamp": 1786775595,
///   "params": { "update": { "sessionUpdate": "turn_completed",
///     "usage": { "inputTokens": 33379, "outputTokens": 91,
///                "cachedReadTokens": 22272, "cacheCreationTokens": 0,
///                "reasoningTokens": 42,
///                "modelUsage": { "grok-4.6-build": { … } } } } } }
/// ```
///
/// **`modelUsage` is what names the model**, and a turn can touch more than
/// one — so the per-model counts are read from it and the flat totals beside
/// it are used only when it is absent.
enum GrokStore {
    static func ledger(at root: URL, prices: [String: ModelPrice]) -> UsageLedger {
        var buckets: [String: [String: TokenTally]] = [:]
        var sessions: [UsageLedger.Session] = []

        let manager = FileManager.default
        let directories = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []

        for directory in directories {
            guard !Task.isCancelled else { return .empty }
            // The folder is the working directory, percent-encoded.
            let project = UsageProject(directory.lastPathComponent.removingPercentEncoding)

            let runs = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for run in runs {
                guard !Task.isCancelled else { return .empty }
                let file = run.appending(path: "updates.jsonl")

                var tokens = 0
                var cost = 0.0
                var first: Date?
                var last: Date?
                var title: String?
                var runSlots: [String: (tokens: Int, cost: Double)] = [:]

                for root in AgentLogIO.jsonLines(at: file) {
                    guard let params = root["params"] as? [String: Any],
                          let update = params["update"] as? [String: Any]
                    else { continue }

                    // The opening prompt, for a row that would otherwise be a
                    // uuid.
                    if title == nil, update["sessionUpdate"] as? String == "user_message_chunk",
                       let text = UsageLedgerReader.text(in: update["content"]),
                       let opening = UsageLedgerReader.title(from: text) {
                        title = opening
                    }

                    guard update["sessionUpdate"] as? String == "turn_completed",
                          let usage = update["usage"] as? [String: Any],
                          let seconds = root["timestamp"] as? Double ?? (root["timestamp"] as? Int).map(Double.init)
                    else { continue }

                    let at = Date(timeIntervalSince1970: seconds)
                    first = min(first ?? at, at)
                    last = max(last ?? at, at)
                    let key = UsageLedgerReader.slotKey(for: at)

                    let perModel = usage["modelUsage"] as? [String: [String: Any]]
                        ?? ["grok": usage]

                    for (model, counts) in perModel {
                        let tally = TokenTally(
                            input: int(counts["inputTokens"]),
                            cacheWrite: int(counts["cacheCreationTokens"]),
                            cacheRead: int(counts["cachedReadTokens"]),
                            output: int(counts["outputTokens"]) + int(counts["reasoningTokens"])
                        )
                        guard tally.total > 0 else { continue }

                        let money = ModelPrices.price(for: model, in: prices).map { tally.cost(at: $0) } ?? 0
                        buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally
                        tokens += tally.total
                        cost += money

                        var slot = runSlots[key] ?? (tokens: 0, cost: 0)
                        slot.tokens += tally.total
                        slot.cost += money
                        runSlots[key] = slot
                    }
                }

                guard tokens > 0, let first, let last else { continue }
                sessions.append(
                    UsageLedger.Session(
                        id: file.path, name: run.lastPathComponent, title: title,
                        project: project, start: first, end: last, tokens: tokens, cost: cost,
                        slots: UsageLedgerReader.sessionSlots(runSlots)
                    )
                )
            }
        }

        guard !buckets.isEmpty else { return .empty }
        var ledger = UsageLedgerReader.price(buckets, with: prices)
        ledger.sessions = sessions.sorted { $0.end > $1.end }
        return ledger
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}
