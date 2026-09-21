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
    ///
    /// **The split is the only formula.** `cost(at:)` is this breakdown's
    /// total, so a day's money and the per-model money it is built from come
    /// out of one arithmetic instead of two that would eventually disagree.
    func costBreakdown(at price: ModelPrice) -> TokenCost {
        TokenCost(
            input: Double(input) * price.input / 1_000_000,
            cacheWrite: Double(cacheWrite) * (price.cacheWrite ?? price.input) / 1_000_000,
            cacheRead: Double(cacheRead) * (price.cacheRead ?? price.input) / 1_000_000,
            output: Double(output) * price.output / 1_000_000
        )
    }

    func cost(at price: ModelPrice) -> Double {
        costBreakdown(at: price).total
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
    /// The same day split by **kind** of token — fresh input, cache written,
    /// cache read, output.
    ///
    /// Carried rather than recomputed because the scan already has it: the
    /// cache keeps a `TokenTally` per model per quarter-hour and this used to
    /// throw three quarters of it away on the way to a single total. It is
    /// what separates "I sent a lot" from "I re-read a lot", which are priced
    /// an order of magnitude apart.
    var tally = TokenTally()

    /// The same day split by **raw model id**, each id with its own tally.
    ///
    /// A model's own categories cannot be recovered from `tally`, which is
    /// every model in the day added together, so the per-model breakdown is
    /// kept beside it. The key is the model id as written by the agent, not
    /// the display name — several ids can resolve to one name, and the
    /// drill-down adds them up itself.
    ///
    /// Empty for a day read before the model detail was kept, which is how a
    /// per-model breakdown knows its categories are missing rather than
    /// reading a model's whole total as one category.
    var modelTallies: [String: TokenTally] = [:]

    /// The same day split by **raw model id**, each id with what its own tokens
    /// cost at that model's own rates.
    ///
    /// A model absent here is one with no published price — counted, never
    /// priced, and never patched with a zero. Kept per raw id because several
    /// ids can resolve to one display name at different rates, and because a
    /// day's blended cost must never be prorated across the models in it.
    var modelCosts: [String: TokenCost] = [:]

    /// The same day split by **raw model id**, each id with the tokens that
    /// could not be placed in any of the four kinds.
    ///
    /// A source that reports a bare total, or a session total, has real tokens
    /// Pulse cannot classify; they are counted in `tokens` and `models` and
    /// listed here, but they are never invented into `input` and never priced.
    /// A raw id absent here has no such tokens. This is what lets a summary
    /// tell "some of this is unclassified" from "the split is broken", so a
    /// damaged ledger is not mistaken for a legitimate partial one.
    var modelUnclassifiedTokens: [String: Int] = [:]

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
        /// The quarter-hour's tokens split by **raw model id**, where the
        /// reader kept them.
        ///
        /// A `LedgerDay` has already thrown the time of day away, so a model's
        /// own hours can only come from here. Empty for a slot read before the
        /// detail was kept — which is how a per-model breakdown knows its hours
        /// cannot be trusted, rather than dividing the whole agent's usage by
        /// whatever model happened to be named.
        var models: [String: TokenTally] = [:]
    }

    /// Ascending by date, gaps closed so the chart reads as a calendar.
    /// Where the figures came from, which decides what may be said about
    /// them.
    ///
    /// The two are not interchangeable. Transcripts are this Mac's alone and
    /// carry the input, output and cache counts a price list needs; a
    /// provider's own statistics cover every machine on the account and give
    /// one token total per model, which cannot be priced. A card that showed
    /// money for the second would be inventing it.
    enum Origin: String, Codable, Sendable, Equatable {
        /// Scanned from the CLI's session files on this Mac.
        case localTranscripts
        /// Imported from decoded records — a capture, a dropped log, another
        /// tool's store — rather than read by one of the built-in readers.
        /// Still this Mac's own movement, so it can be priced when the kinds
        /// are known.
        case importedRecords
        /// Asked of the provider, so it covers the whole account. One token
        /// total per model and no money behind it.
        case providerStatistics

        /// Whether a ledger with this origin may appear in the token spend
        /// pane. Records read or imported here can; a provider's own
        /// statistics cannot, because they carry no money and would put a
        /// figure on a total half of it cannot carry.
        var supportsTokenSpend: Bool {
            switch self {
            case .localTranscripts, .importedRecords: true
            case .providerStatistics: false
            }
        }
    }

    var origin: Origin = .localTranscripts

    /// Whether some of this work has only session- or report-level timing, so
    /// the hour profile cannot be trusted.
    ///
    /// An imported aggregate record is placed on its real calendar day but not
    /// in a quarter-hour bucket — the hour it ran is not known. A summary that
    /// sees this withholds the per-hour figure rather than inventing one.
    var hasAggregateTiming = false

    /// Whether some of the counts behind this ledger may be missing.
    ///
    /// A store that cannot prove whether reasoning or cache tokens are already
    /// included in a reported figure gives Pulse figures that are real but may
    /// be short. A summary that sees this marks the total as partial rather
    /// than presenting a possibly incomplete count as whole. It never changes
    /// a token number or a price.
    var hasPartialCounts = false

    var days: [LedgerDay]
    var earliest: Date?
    /// Models seen in the logs that models.dev has no price for.
    ///
    /// `var` rather than `let` so a builder can add a raw id it saw only as
    /// unclassified tokens: it still has no money behind it.
    var unpricedModels: [String]
    /// How each model id is written by its provider, where models.dev says.
    ///
    /// `var` so a builder can resolve a display name for a raw id it saw only
    /// as unclassified tokens. A name is not a price: looking one up here
    /// never turns those tokens into money.
    var modelNames: [String: String]
    /// Ascending by start time. Only slots with work in them.
    var slots: [Slot]
    /// One per transcript file, which is one per session of that CLI.
    ///
    /// **Free, or nearly.** The scan already keys its cache by file path and
    /// already holds every file's own buckets; this is the same numbers rolled
    /// up a second way instead of being merged and forgotten.
    var sessions: [Session] = []

    /// One transcript: one conversation with the CLI.
    struct Session: Identifiable, Sendable, Equatable {
        /// A reported calendar day's work, independent of whether its hour is
        /// known. Used for span filtering, never as an hourly measurement.
        struct Day: Sendable, Equatable {
            let date: Date
            let tokens: Int
            let cost: Double
        }

        /// The file's path, which is unique and stable.
        let id: String
        /// What the CLI called it — a uuid for Claude Code, a timestamped
        /// rollout name for Codex. Shown because it is what the file is
        /// called, not because it means anything.
        let name: String
        /// What the conversation was called: the title the user set, else the
        /// words it opened with. Nil for a transcript that carries neither.
        let title: String?
        /// The working directory the session ran in, where the path says.
        ///
        /// Taken from the `cwd` the transcript states, which both CLIs
        /// write — so this is the directory's real name rather than the
        /// folder-name heuristic it replaced.
        let project: String?
        let start: Date
        let end: Date
        let tokens: Int
        let cost: Double
        /// The session's own quarter-hour buckets, priced — the same ones the
        /// day totals are folded from.
        ///
        /// **A conversation is not one indivisible number.** A session
        /// resumed across midnight, or over days, has work on more than one
        /// calendar day; without this detail a span can only take it whole or
        /// drop it, and a project's total then disagrees with the span's own.
        /// Empty when timing is aggregate, or on an older ledger. Calendar
        /// days below are the fallback; only a session with neither is counted whole.
        var slots: [Slot] = []
        /// Present for normalized records, including aggregate reports. A
        /// session may have exact days while having no trustworthy hours.
        var days: [Day] = []
    }

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
    private let home: URL
    private let cacheDirectory: URL?

    init(home: URL = URL(fileURLWithPath: NSHomeDirectory()), cacheDirectory: URL? = nil) {
        self.home = home
        self.cacheDirectory = cacheDirectory
    }

    func ledger(
        for provider: Provider, refresh: Bool = false, prices suppliedPrices: [String: ModelPrice]? = nil
    ) async -> UsageLedger {
        guard !Task.isCancelled else { return .empty }
        if !refresh, let cached = cached[provider] { return cached }

        let scanned = scan(provider)
        guard !Task.isCancelled else { return .empty }
        let prices: [String: ModelPrice]
        if let suppliedPrices { prices = suppliedPrices }
        else { prices = await ModelPrices.shared.prices() }
        guard !Task.isCancelled else { return .empty }
        var ledger = Self.priced(scanned.buckets, with: prices, calendar: .current)
        ledger.sessions = sessions(scanned.files, provider: provider, prices: prices)
        guard !Task.isCancelled else { return .empty }
        cached[provider] = ledger
        return ledger
    }

    // MARK: - Pricing

    /// The quarter-hour a moment falls in, as the key the buckets are held
    /// under. Shared with the readers that take their counts from a database
    /// rather than from a transcript, so every agent's day is cut the same way.
    nonisolated static func slotKey(for date: Date, calendar: Calendar = .current) -> String {
        let quarter = 15.0 * 60
        let floored = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / quarter).rounded(.down) * quarter)
        return sharedSlotFormatter.string(from: floored)
    }

    nonisolated static let sharedSlotFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// Turns a reader's running `slotKey` totals into the sorted, priced
    /// buckets a session carries.
    ///
    /// Shared by the readers that take their counts from a database, so a
    /// session's own detail is cut — and can be windowed — the same way the
    /// day totals are. The key is the one `slotKey(for:)` produced.
    nonisolated static func sessionSlots(
        _ totals: [String: (tokens: Int, cost: Double)]
    ) -> [UsageLedger.Slot] {
        totals
            .compactMap { key, value in
                sharedSlotFormatter.date(from: key).map {
                    UsageLedger.Slot(start: $0, tokens: value.tokens, cost: value.cost)
                }
            }
            .sorted { $0.start < $1.start }
    }

    nonisolated static func price(
        _ buckets: [String: [String: TokenTally]],
        with prices: [String: ModelPrice],
        calendar: Calendar = .current,
        vendor: String? = nil
    ) -> UsageLedger {
        priced(buckets, with: prices, calendar: calendar, vendor: vendor)
    }

    /// Turns buckets into days, slots and money.
    ///
    /// **Static and free of instance state**, so the readers that take their
    /// counts out of a database can price them exactly as the transcripts are
    /// priced. Two ways of turning tokens into dollars in one app is two
    /// figures that eventually disagree.
    nonisolated private static func priced(
        _ buckets: Buckets,
        with prices: [String: ModelPrice],
        calendar: Calendar,
        vendor: String? = nil
    ) -> UsageLedger {
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
        var dayModelTallies: [Date: [String: TokenTally]] = [:]
        var dayModelCosts: [Date: [String: TokenCost]] = [:]
        var dayTally: [Date: TokenTally] = [:]

        for (key, models) in buckets {
            guard !Task.isCancelled else { return .empty }
            guard let start = sharedSlotFormatter.date(from: key) else { continue }
            let day = calendar.startOfDay(for: start)

            var tokens = 0
            var cost = 0.0
            var unpricedTokens = 0

            for (model, tally) in models {
                tokens += tally.total
                dayModels[day, default: [:]][model, default: 0] += tally.total
                // Per model, so a drill-down can show one model's own split
                // rather than the whole day's.
                dayModelTallies[day, default: [:]][model, default: TokenTally()] =
                    (dayModelTallies[day]?[model] ?? TokenTally()) + tally
                dayTally[day, default: TokenTally()] = (dayTally[day] ?? TokenTally()) + tally

                if let price = ModelPrices.price(for: model, in: prices, vendor: vendor) {
                    let money = tally.costBreakdown(at: price)
                    cost += money.total
                    dayModelCosts[day, default: [:]][model, default: TokenCost()] =
                        (dayModelCosts[day]?[model] ?? TokenCost()) + money
                    if let name = price.name { names[model] = name }
                } else {
                    unpriced.insert(model)
                    unpricedTokens += tally.total
                }
            }

            slots.append(UsageLedger.Slot(start: start, tokens: tokens, cost: cost, models: models))

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
                models: dayModels[day] ?? [:],
                tally: dayTally[day] ?? TokenTally(),
                modelTallies: dayModelTallies[day] ?? [:],
                modelCosts: dayModelCosts[day] ?? [:]
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

    private func scan(_ provider: Provider) -> (buckets: Buckets, files: [String: FileCache.Entry]) {
        var cache = FileCache.load(for: provider, directory: cacheDirectory)
        var buckets: Buckets = [:]
        var fresh: [String: FileCache.Entry] = [:]

        for file in Self.logFiles(for: provider, home: home) {
            guard !Task.isCancelled else { return ([:], [:]) }
            guard let stamp = FileCache.Stamp(file) else { continue }
            let key = file.path

            // A log file is rewritten only by being appended to, so size and
            // modification date together are enough to know nothing changed.
            let entry: FileCache.Entry
            if let known = cache.files.removeValue(forKey: key), known.stamp == stamp {
                entry = known
            } else {
                let scanned = autoreleasepool { parse(file, provider: provider) }
                guard !Task.isCancelled else { return ([:], [:]) }
                entry = FileCache.Entry(
                    stamp: stamp, days: scanned.days, title: scanned.title, cwd: scanned.cwd
                )
            }

            fresh[key] = entry
            for (day, models) in entry.days {
                for (model, tally) in models {
                    buckets[day, default: [:]][model] = (buckets[day]?[model] ?? TokenTally()) + tally
                }
            }
        }

        cache.files = fresh
        cache.save(for: provider, directory: cacheDirectory)
        return (buckets, fresh)
    }

    /// One row per transcript, priced the same way the days are.
    ///
    /// The cache is keyed by path and holds each file's own buckets, so this
    /// is a second rollup of numbers already in hand rather than another pass
    /// over the transcripts.
    private func sessions(
        _ files: [String: FileCache.Entry],
        provider: Provider,
        prices: [String: ModelPrice]
    ) -> [UsageLedger.Session] {
        var sessions: [UsageLedger.Session] = []

        for (path, entry) in files {
            guard !Task.isCancelled else { return [] }
            var tokens = 0
            var cost = 0.0
            var start: Date?
            var end: Date?
            var slots: [UsageLedger.Slot] = []

            for (key, models) in entry.days {
                guard let at = slotFormatter.date(from: key) else { continue }
                start = min(start ?? at, at)
                end = max(end ?? at, at)

                var slotTokens = 0
                var slotCost = 0.0
                for (model, tally) in models {
                    tokens += tally.total
                    slotTokens += tally.total
                    if let price = ModelPrices.price(for: model, in: prices) {
                        let money = tally.cost(at: price)
                        cost += money
                        slotCost += money
                    }
                }
                slots.append(.init(start: at, tokens: slotTokens, cost: slotCost))
            }

            guard tokens > 0, let start, let end else { continue }

            let url = URL(fileURLWithPath: path)
            sessions.append(
                UsageLedger.Session(
                    id: path,
                    name: url.deletingPathExtension().lastPathComponent,
                    title: entry.title,
                    project: entry.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                        ?? Self.project(of: url, provider: provider),
                    start: start,
                    end: end,
                    tokens: tokens,
                    cost: cost,
                    slots: slots.sorted { $0.start < $1.start }
                )
            )
        }

        return sessions.sorted { $0.end > $1.end }
    }

    /// The fallback for a transcript that states no `cwd`.
    ///
    /// Claude Code names a project's directory for its path with every
    /// separator replaced by a dash (`-Users-me-Code-Pulse`), and the last
    /// segment of that is the best guess available — it is a guess, which is
    /// why the stated `cwd` is preferred wherever there is one. Codex files
    /// sit under a date and carry no directory in the path at all.
    static func project(of file: URL, provider: Provider) -> String? {
        guard provider == .claudeCode else { return nil }

        let folder = file.deletingLastPathComponent().lastPathComponent
        let parts = folder.split(separator: "-", omittingEmptySubsequences: true)
        guard let last = parts.last.map(String.init), !last.isEmpty else { return nil }
        return last
    }

    private static func logFiles(for provider: Provider, home: URL) -> [URL] {
        let root: URL? = switch provider {
        case .claudeCode: home.appending(path: ".claude/projects")
        case .codex: home.appending(path: ".codex/sessions")
        // Antigravity is an editor and keeps nothing; OpenCode keeps its own
        // store rather than the JSONL these two parsers read.
        case .kiro, .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot,
             .volcengine, .commandCode, .deepSeek, .devin, .xiaomiMiMo: nil
        }

        guard let root else { return [] }

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        while let file = autoreleasepool(invoking: { walker.nextObject() as? URL }) {
            guard !Task.isCancelled else { return [] }
            if file.pathExtension == "jsonl" { files.append(file) }
        }
        return files
    }

    /// What a transcript says about itself: what it was called and where it
    /// ran, beside the counts.
    ///
    /// Both come out of the same pass and are cached with it. Reading them
    /// later would mean opening every file again — a few hundred megabytes for
    /// two short strings.
    // `Sendable` because the internal `parseClaudeCode` is reached across the
    // actor's boundary by its test, and Swift 6 will not hand a non-`Sendable`
    // value out.
    struct Scanned: Codable, Sendable {
        var days: [String: [String: TokenTally]] = [:]
        /// The conversation's own name, where the CLI keeps one.
        var title: String?
        /// The directory it ran in, as the transcript states it. **Not decoded
        /// from the folder name**: Claude Code names its project folders for
        /// the path with every separator replaced by a dash, which cannot be
        /// reversed — a folder whose own name contains a dash is
        /// indistinguishable from a separator, and this Mac has several.
        var cwd: String?
    }

    // Internal for the on-disk streaming/cancellation regression fixtures.
    func parse(_ file: URL, provider: Provider) -> Scanned {
        switch provider {
        case .claudeCode: return parseClaudeCode(LogLines(at: file))
        case .codex: return parseCodex(LogLines(at: file))
        case .kiro, .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot,
             .volcengine, .commandCode, .deepSeek, .devin, .xiaomiMiMo: return Scanned()
        }
    }

    /// The opening prompt, cut to something a row can hold.
    ///
    /// **Not the whole message.** These are the user's own words and a row is
    /// one line; the point is to tell one conversation from another, which the
    /// first few words do.
    static func title(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        // A pasted file or a command envelope is not a title.
        guard !cleaned.hasPrefix("<"), !cleaned.hasPrefix("Caveat:") else { return nil }
        return cleaned.count <= 70 ? cleaned : String(cleaned.prefix(69)) + "…"
    }

    /// The first run of text in a message body, which is a string in the
    /// simple case and an array of typed parts in the rich one.
    static func text(in message: Any?) -> String? {
        if let text = message as? String { return text }
        guard let parts = message as? [[String: Any]] else { return nil }
        for part in parts {
            if let text = part["text"] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    /// Claude Code writes one JSON object per message, each assistant reply
    /// carrying the token counts for the request that produced it.
    ///
    /// **Internal rather than `private` so a test can drive the real parser**
    /// over a transcript it builds by hand, without reading the user's own
    /// `~/.claude` ([Docs/testing.md](../../Docs/testing.md) allows this when
    /// the comment says so — do not tidy it back). It changes no token count.
    func parseClaudeCode(_ data: Data) -> Scanned {
        parseClaudeCode(LogLines(data: data))
    }

    private func parseClaudeCode(_ lines: LogLines) -> Scanned {
        var scanned = Scanned()
        var days: [String: [String: TokenTally]] = [:]
        // Retries and resumed sessions can write the same reply twice; the
        // message id identifies it. This only catches repeats within a file,
        // which is where they actually happen.
        var seen: Set<String> = []

        lines.forEachLine { line in
            // What the session is called and where it ran. **A user-set title
            // can arrive long after the opening prompt** — Claude Code writes
            // `customTitle` when the conversation is renamed — so that one is
            // looked for on every line and the last valid one wins. `cwd` and
            // the opening prompt are only needed once each, which keeps the
            // ordinary line from being parsed twice.
            let renamed = contains(line, "\"customTitle\"")
            if renamed || scanned.title == nil || scanned.cwd == nil {
                if let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    if scanned.cwd == nil, let cwd = root["cwd"] as? String, !cwd.isEmpty {
                        scanned.cwd = cwd
                    }
                    // The user's own name outranks the opening prompt, and a
                    // later rename outranks an earlier one. An unreadable
                    // custom title (empty, or an envelope) leaves the title
                    // that was already found rather than clearing it.
                    if renamed, let custom = root["customTitle"] as? String,
                       let title = Self.title(from: custom) {
                        scanned.title = title
                    } else if scanned.title == nil,
                              root["type"] as? String == "user",
                              root["isSidechain"] as? Bool != true,
                              let message = root["message"] as? [String: Any],
                              let text = Self.text(in: message["content"]),
                              let title = Self.title(from: text) {
                        scanned.title = title
                    }
                }
            }

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
            else { return }

            if let id = message["id"] as? String {
                guard seen.insert(id).inserted else { return }
            }

            let tally = TokenTally(
                input: int(usage["input_tokens"]),
                cacheWrite: int(usage["cache_creation_input_tokens"]),
                cacheRead: int(usage["cache_read_input_tokens"]),
                output: int(usage["output_tokens"])
            )
            guard tally.total > 0 else { return }

            days[slot, default: [:]][model] = (days[slot]?[model] ?? TokenTally()) + tally
        }

        scanned.days = days
        return scanned
    }

    /// Codex reports a running total for the session rather than a figure per
    /// turn, so each reading is differenced against the one before it. The
    /// running total only ever climbs, which makes the differences safe to add
    /// up — and it sidesteps the duplicate readings that summing Codex's own
    /// per-turn field would double-count.
    private func parseCodex(_ lines: LogLines) -> Scanned {
        var scanned = Scanned()
        var days: [String: [String: TokenTally]] = [:]
        var model: String?
        var previous: [String: Int]?

        lines.forEachLine { line in
            if scanned.title == nil || scanned.cwd == nil {
                // The directory is stated once in the session header; the
                // opening prompt is a `response_item` whose payload is a
                // message with the user's role on it — **not** an `event_msg`,
                // which is what the first attempt looked for and why every
                // Codex session came out unnamed.
                if contains(line, "\"cwd\"") || contains(line, "\"\"role\":\"user\"\"") || contains(line, "\"role\":\"user\"") {
                    if let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                       let payload = root["payload"] as? [String: Any] {
                        if scanned.cwd == nil, let cwd = payload["cwd"] as? String, !cwd.isEmpty {
                            scanned.cwd = cwd
                        }
                        if scanned.title == nil,
                           payload["type"] as? String == "message",
                           payload["role"] as? String == "user",
                           let text = Self.text(in: payload["content"]),
                           let title = Self.title(from: text) {
                            scanned.title = title
                        }
                    }
                }
            }

            let isCount = contains(line, "\"token_count\"")
            guard isCount || contains(line, "\"model\"") else { return }
            guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }

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
            else { return }

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
            guard tally.total > 0 else { return }

            days[slot, default: [:]][model] = (days[slot]?[model] ?? TokenTally()) + tally
        }

        scanned.days = days
        return scanned
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
        /// What the transcript called itself, and where it ran. Optional
        /// because a file can carry neither — and because the cache on disk
        /// predates them.
        var title: String?
        var cwd: String?
    }

    var files: [String: Entry] = [:]

    static func load(for provider: Provider, directory: URL?) -> FileCache {
        guard
            let data = try? Data(contentsOf: file(for: provider, directory: directory)),
            let cache = try? JSONDecoder().decode(FileCache.self, from: data)
        else { return FileCache() }
        return cache
    }

    func save(for provider: Provider, directory: URL?) {
        guard !Task.isCancelled else { return }
        if directory == nil { PulseStorage.prepare() }
        guard let data = try? JSONEncoder().encode(self) else { return }
        guard !Task.isCancelled else { return }
        try? data.write(to: Self.file(for: provider, directory: directory), options: .atomic)
    }

    private static func file(for provider: Provider, directory: URL?) -> URL {
        // The `2` is the bucket format. Quarter-hours replaced whole days, and
        // an old file's keys would parse as nothing at all — silently, which
        // is the worst way for a cache to be wrong.
        // **The number is part of the contract.** `ledger-2` became `ledger-3`
        // when entries gained a title and a working directory; a cache written
        // by an earlier build still decodes, and would then hand back every
        // session unnamed for ever, because a file that has not changed is
        // never read again.
        //
        // **`ledger-3` became `ledger-4` because its titles are wrong.** The
        // parser that wrote them stopped looking for `customTitle` once a
        // session had a `cwd` and an opening prompt, so every rename made
        // after that was dropped — and a transcript that has not changed is
        // never opened again, so the fix to the parser alone could not reach
        // them. Renaming the file forces the one rescan that rereads them.
        (directory ?? PulseStorage.directory).appending(path: "ledger-4-\(provider.rawValue).json")
    }
}
