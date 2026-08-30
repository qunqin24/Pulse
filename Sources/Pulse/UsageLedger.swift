import Foundation

/// Tokens of each kind, which is what a price list needs to become money.
struct TokenTally: Codable, Sendable, Equatable {
    /// Fresh input — what wasn't served from the prompt cache.
    var input = 0
    var cacheWrite = 0
    var cacheRead = 0
    var output = 0

    var total: Int { input + cacheWrite + cacheRead + output }

    static func + (lhs: TokenTally, rhs: TokenTally) -> TokenTally {
        TokenTally(
            input: lhs.input + rhs.input,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            output: lhs.output + rhs.output
        )
    }

    /// Rates are per million tokens. A missing cache rate falls back to the
    /// plain input rate — that is the provider's own arrangement for models
    /// that don't price the cache separately, not a guess.
    func cost(at price: ModelPrice) -> Double {
        (Double(input) * price.input
            + Double(cacheWrite) * (price.cacheWrite ?? price.input)
            + Double(cacheRead) * (price.cacheRead ?? price.input)
            + Double(output) * price.output) / 1_000_000
    }
}

/// One day's work, priced.
struct LedgerDay: Identifiable, Sendable, Equatable {
    let date: Date
    let tokens: Int
    let cost: Double
    /// Tokens spent on models with no published price. They count towards
    /// `tokens` but not `cost`, so the two can be read honestly side by side.
    let unpricedTokens: Int
    /// Tokens by model, so "which model is doing the work" can be answered
    /// over any span rather than only the one totalled at scan time.
    let models: [String: Int]

    var id: Date { date }
}

/// A provider's history, worked out from the logs its own CLI leaves on this
/// Mac.
///
/// Worth being clear about what this is and isn't. The providers report
/// *limits*, not spending, and neither publishes a per-day history — so the
/// only place the day-by-day story exists is the transcripts on disk. That
/// makes this local by nature: work done on another machine isn't here, and
/// neither is anything the CLI has since pruned.
///
/// The money is likewise a translation, not a bill. Both tools are used on a
/// subscription, so nothing here was charged per token; the figure is what the
/// same tokens would cost at the providers' published API rates, which is the
/// only defensible way to put a number on it.
struct UsageLedger: Sendable, Equatable {
    /// A quarter of an hour's work. Days are what the card shows, but a
    /// five-hour limit opens and closes inside one, so the totals are kept at
    /// a resolution fine enough to answer "since this window opened".
    struct Slot: Sendable, Equatable {
        let start: Date
        let tokens: Int
        let cost: Double
    }

    /// Ascending by date, gaps closed so the chart reads as a calendar.
    let days: [LedgerDay]
    let earliest: Date?
    /// Models seen in the logs that models.dev has no price for.
    let unpricedModels: [String]
    /// How each model id is written by its provider, where models.dev says.
    let modelNames: [String: String]
    /// Ascending by start time. Only slots with work in them.
    let slots: [Slot]

    static let empty = UsageLedger(
        days: [], earliest: nil, unpricedModels: [], modelNames: [:], slots: []
    )

    /// What has gone through since a moment — the figure a rate-limit window
    /// needs. A slot straddling the boundary counts in full, so this can run a
    /// few minutes' work high; at fifteen-minute steps that is well inside the
    /// rounding the providers' own percentages carry.
    func spend(since start: Date) -> (tokens: Int, cost: Double) {
        slots.reduce(into: (0, 0.0)) { running, slot in
            guard slot.start >= start else { return }
            running.0 += slot.tokens
            running.1 += slot.cost
        }
    }

    var today: LedgerDay? {
        days.last.flatMap { Calendar.current.isDateInToday($0.date) ? $0 : nil }
    }

    func total(overLast count: Int) -> (tokens: Int, cost: Double) {
        days.suffix(count).reduce(into: (0, 0.0)) {
            $0.0 += $1.tokens
            $0.1 += $1.cost
        }
    }

    var allTime: (tokens: Int, cost: Double) {
        days.reduce(into: (0, 0.0)) {
            $0.0 += $1.tokens
            $0.1 += $1.cost
        }
    }

    func recent(_ count: Int) -> [LedgerDay] { Array(days.suffix(count)) }

    /// The heaviest day in a span. Scoped rather than all-time so it sits
    /// beside the other figures on the card without quietly changing the
    /// window they all share.
    func busiestDay(overLast count: Int) -> LedgerDay? {
        days.suffix(count).max { $0.tokens < $1.tokens }
    }

    /// The model most of the work went through, and how much of it. Falls back
    /// to the whole history when the recent window is quiet, so the line
    /// doesn't vanish after a week off.
    func topModel(overLast count: Int) -> (name: String, share: Double)? {
        let window = days.suffix(count).contains { $0.tokens > 0 } ? Array(days.suffix(count)) : days

        var totals: [String: Int] = [:]
        for day in window {
            for (model, tokens) in day.models { totals[model, default: 0] += tokens }
        }

        guard
            let leader = totals.max(by: { $0.value < $1.value }),
            case let overall = totals.values.reduce(0, +),
            overall > 0
        else { return nil }

        return (modelNames[leader.key] ?? leader.key, Double(leader.value) / Double(overall))
    }
}

/// Reads the CLIs' own transcripts and adds them up.
///
/// Scanning is kept off the price list on purpose: the cache holds *tokens per
/// model per day*, and money is worked out afterwards. A price change then
/// costs nothing to apply, where caching the money would have meant rescanning
/// a few hundred megabytes to pick it up.
actor UsageLedgerReader {
    static let shared = UsageLedgerReader()

    /// Tokens by quarter-hour (`yyyy-MM-dd HH:mm`, local) and then by model.
    private typealias Buckets = [String: [String: TokenTally]]

    private var cached: [Provider: UsageLedger] = [:]

    func ledger(for provider: Provider, refresh: Bool = false) async -> UsageLedger {
        if !refresh, let cached = cached[provider] { return cached }

        let buckets = scan(provider)
        let prices = await ModelPrices.shared.prices()
        let ledger = price(buckets, with: prices)
        cached[provider] = ledger
        return ledger
    }

    // MARK: - Pricing

    private func price(_ buckets: Buckets, with prices: [String: ModelPrice]) -> UsageLedger {
        guard !buckets.isEmpty else { return .empty }

        var unpriced: Set<String> = []
        var names: [String: String] = [:]
        var slots: [UsageLedger.Slot] = []

        // Rolled up as we go: the card wants days, the window estimate wants
        // the raw quarter-hours, and both come out of the same pass.
        var dayTokens: [Date: Int] = [:]
        var dayCost: [Date: Double] = [:]
        var dayUnpriced: [Date: Int] = [:]
        var dayModels: [Date: [String: Int]] = [:]
        let calendar = Calendar.current

        for (key, models) in buckets {
            guard let start = slotFormatter.date(from: key) else { continue }

            var tokens = 0
            var cost = 0.0
            var unpricedTokens = 0

            for (model, tally) in models {
                tokens += tally.total
                dayModels[calendar.startOfDay(for: start), default: [:]][model, default: 0] += tally.total

                if let price = prices[model] {
                    cost += tally.cost(at: price)
                    if let name = price.name { names[model] = name }
                } else {
                    unpriced.insert(model)
                    unpricedTokens += tally.total
                }
            }

            slots.append(UsageLedger.Slot(start: start, tokens: tokens, cost: cost))

            let day = calendar.startOfDay(for: start)
            dayTokens[day, default: 0] += tokens
            dayCost[day, default: 0] += cost
            dayUnpriced[day, default: 0] += unpricedTokens
        }

        var byDate: [Date: LedgerDay] = [:]
        for (day, tokens) in dayTokens {
            byDate[day] = LedgerDay(
                date: day,
                tokens: tokens,
                cost: dayCost[day] ?? 0,
                unpricedTokens: dayUnpriced[day] ?? 0,
                models: dayModels[day] ?? [:]
            )
        }

        guard let earliest = byDate.keys.min(), let latest = byDate.keys.max() else { return .empty }

        // Fill the quiet days back in. Without them the bars would sit
        // shoulder to shoulder and a fortnight off would look like a weekend.
        var days: [LedgerDay] = []
        var cursor = earliest
        while cursor <= latest {
            days.append(
                byDate[cursor]
                    ?? LedgerDay(date: cursor, tokens: 0, cost: 0, unpricedTokens: 0, models: [:])
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return UsageLedger(
            days: days,
            earliest: earliest,
            unpricedModels: unpriced.sorted(),
            modelNames: names,
            slots: slots.sorted { $0.start < $1.start }
        )
    }

    // MARK: - Scanning

    private func scan(_ provider: Provider) -> Buckets {
        var cache = FileCache.load(for: provider)
        var buckets: Buckets = [:]
        var fresh: [String: FileCache.Entry] = [:]

        for file in Self.logFiles(for: provider) {
            guard let stamp = FileCache.Stamp(file) else { continue }
            let key = file.path

            // A log file is rewritten only by being appended to, so size and
            // modification date together are enough to know nothing changed.
            let entry: FileCache.Entry
            if let known = cache.files[key], known.stamp == stamp {
                entry = known
            } else {
                entry = FileCache.Entry(stamp: stamp, days: parse(file, provider: provider))
            }

            fresh[key] = entry
            for (day, models) in entry.days {
                for (model, tally) in models {
                    buckets[day, default: [:]][model] = (buckets[day]?[model] ?? TokenTally()) + tally
                }
            }
        }

        cache.files = fresh
        cache.save(for: provider)
        return buckets
    }

    private static func logFiles(for provider: Provider) -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let root: URL? = switch provider {
        case .claudeCode: home.appending(path: ".claude/projects")
        case .codex: home.appending(path: ".codex/sessions")
        // Antigravity is an editor and keeps nothing; OpenCode keeps its own
        // store rather than the JSONL these two parsers read.
        case .antigravity, .openCodeGo, .kimiCode: nil
        }

        guard let root else { return [] }

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private func parse(_ file: URL, provider: Provider) -> [String: [String: TokenTally]] {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [:] }

        switch provider {
        case .claudeCode: return parseClaudeCode(data)
        case .codex: return parseCodex(data)
        case .antigravity, .openCodeGo, .kimiCode: return [:]
        }
    }

    /// Claude Code writes one JSON object per message, each assistant reply
    /// carrying the token counts for the request that produced it.
    private func parseClaudeCode(_ data: Data) -> [String: [String: TokenTally]] {
        var days: [String: [String: TokenTally]] = [:]
        // Retries and resumed sessions can write the same reply twice; the
        // message id identifies it. This only catches repeats within a file,
        // which is where they actually happen.
        var seen: Set<String> = []

        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard
                contains(line, "\"usage\""),
                let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                root["type"] as? String == "assistant",
                let message = root["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any],
                let model = message["model"] as? String,
                // Placeholders Claude Code writes for its own errors; no
                // request was made, so there is nothing to price.
                model != "<synthetic>",
                let timestamp = root["timestamp"] as? String,
                let slot = slot(fromISO8601: timestamp)
            else { continue }

            if let id = message["id"] as? String {
                guard seen.insert(id).inserted else { continue }
            }

            let tally = TokenTally(
                input: int(usage["input_tokens"]),
                cacheWrite: int(usage["cache_creation_input_tokens"]),
                cacheRead: int(usage["cache_read_input_tokens"]),
                output: int(usage["output_tokens"])
            )
            guard tally.total > 0 else { continue }

            days[slot, default: [:]][model] = (days[slot]?[model] ?? TokenTally()) + tally
        }

        return days
    }

    /// Codex reports a running total for the session rather than a figure per
    /// turn, so each reading is differenced against the one before it. The
    /// running total only ever climbs, which makes the differences safe to add
    /// up — and it sidesteps the duplicate readings that summing Codex's own
    /// per-turn field would double-count.
    private func parseCodex(_ data: Data) -> [String: [String: TokenTally]] {
        var days: [String: [String: TokenTally]] = [:]
        var model: String?
        var previous: [String: Int]?

        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let isCount = contains(line, "\"token_count\"")
            guard isCount || contains(line, "\"model\"") else { continue }
            guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }

            let payload = root["payload"] as? [String: Any] ?? [:]

            // The model can change mid-session; usage is attributed to
            // whichever was in force when the reading was taken.
            if let named = payload["model"] as? String { model = named }

            guard
                isCount,
                payload["type"] as? String == "token_count",
                let totals = (payload["info"] as? [String: Any])?["total_token_usage"] as? [String: Any],
                let timestamp = root["timestamp"] as? String,
                let slot = slot(fromISO8601: timestamp),
                let model
            else { continue }

            let current = [
                "input": int(totals["input_tokens"]),
                "cached": int(totals["cached_input_tokens"]),
                "cacheWrite": int(totals["cache_write_input_tokens"]),
                "output": int(totals["output_tokens"])
            ]
            let delta = current.reduce(into: [String: Int]()) { result, entry in
                result[entry.key] = max(entry.value - (previous?[entry.key] ?? 0), 0)
            }
            previous = current

            // Codex counts cached tokens inside its input figure; the price
            // list treats them as two separate rates.
            let tally = TokenTally(
                input: max((delta["input"] ?? 0) - (delta["cached"] ?? 0), 0),
                cacheWrite: delta["cacheWrite"] ?? 0,
                cacheRead: delta["cached"] ?? 0,
                output: delta["output"] ?? 0
            )
            guard tally.total > 0 else { continue }

            days[slot, default: [:]][model] = (days[slot]?[model] ?? TokenTally()) + tally
        }

        return days
    }

    // MARK: - Line helpers

    /// Cheap substring test, so only the handful of lines that can carry
    /// counts are handed to the JSON parser.
    private func contains(_ line: Data, _ needle: String) -> Bool {
        line.range(of: Data(needle.utf8)) != nil
    }

    private func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }

    /// The quarter-hour a timestamp falls in, as a local-time key.
    private func slot(fromISO8601 text: String) -> String? {
        guard let date = isoWithFraction.date(from: text) ?? iso.date(from: text) else { return nil }

        let quarter = 15.0 * 60
        let floored = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / quarter).rounded(.down) * quarter)
        return slotFormatter.string(from: floored)
    }

    private let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let iso = ISO8601DateFormatter()

    /// Local time, so "today" means the user's today.
    private let slotFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

/// What has already been counted, so opening settings a second time doesn't
/// re-read a few hundred megabytes of transcripts.
private struct FileCache: Codable {
    struct Stamp: Codable, Equatable {
        let size: Int
        let modified: Double

        init?(_ file: URL) {
            guard
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = values.fileSize,
                let modified = values.contentModificationDate
            else { return nil }

            self.size = size
            self.modified = modified.timeIntervalSince1970
        }
    }

    struct Entry: Codable {
        let stamp: Stamp
        let days: [String: [String: TokenTally]]
    }

    var files: [String: Entry] = [:]

    static func load(for provider: Provider) -> FileCache {
        guard
            let data = try? Data(contentsOf: file(for: provider)),
            let cache = try? JSONDecoder().decode(FileCache.self, from: data)
        else { return FileCache() }
        return cache
    }

    func save(for provider: Provider) {
        PulseStorage.prepare()
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.file(for: provider), options: .atomic)
    }

    private static func file(for provider: Provider) -> URL {
        // The `2` is the bucket format. Quarter-hours replaced whole days, and
        // an old file's keys would parse as nothing at all — silently, which
        // is the worst way for a cache to be wrong.
        PulseStorage.directory.appending(path: "ledger-2-\(provider.rawValue).json")
    }
}
