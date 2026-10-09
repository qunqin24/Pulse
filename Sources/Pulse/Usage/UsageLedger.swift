// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Tokens of each kind, which is what a price list needs to become money.
struct TokenTally: Codable, Sendable, Equatable {
    /// Fresh input — what wasn't served from the prompt cache.
    var input = 0
    var cacheWrite = 0
    var cacheRead = 0
    var output = 0
    /// The part of `cacheWrite` held for an hour rather than five minutes —
    /// **inside** `cacheWrite`, not beside it, so it is not in `total`.
    ///
    /// Anthropic bills a one-hour write at twice the input rate and a
    /// five-minute one at 1.25 times; the price list carries only the second.
    /// Claude Code writes most of its cache for the hour, so pricing every
    /// write at the five-minute rate put about half the cache-write money
    /// out of sight. Zero wherever a source does not say.
    var cacheWrite1h = 0
    /// Replies whose usage carried no cache field at all — not zero, absent.
    /// Claude Code pointed at a compatible endpoint that keeps no prompt
    /// cache writes usage without `cache_read_input_tokens`; its zero hits
    /// are not a cache that missed (`reportsNoCache`).
    var repliesWithoutCacheFields = 0
    /// The same tokens again, for requests whose context — input, cache read
    /// and cache write of the one request — was over a size, keyed by the
    /// largest of `contextBoundaries` it passed. A subset of this tally, not
    /// beside it, kept only where one request is one record (Claude Code's
    /// replies, Codex's readings), so a long-context tier can be priced
    /// (`ModelPrice.tier(forBand:)`). Empty everywhere else.
    var contextBands: [Int: TokenTally] = [:]

    /// The context sizes models.dev prices a tier from that a band is kept
    /// for: 128K, 200K (Gemini, and Anthropic's models on other providers),
    /// 256K, and OpenAI's 272K. A tier at a size between two of these is
    /// applied from the next one up, never early.
    static let contextBoundaries = [128_000, 200_000, 256_000, 272_000]

    /// This tally, marked as one request whose context was `context` tokens.
    func request(context: Int) -> TokenTally {
        guard let band = Self.contextBoundaries.last(where: { context > $0 }) else { return self }
        var copy = self
        var plain = self
        plain.contextBands = [:]
        copy.contextBands = [band: plain]
        return copy
    }

    var total: Int { input + cacheWrite + cacheRead + output }

    /// Every reply behind this tally said nothing about the cache, and none
    /// was read or written: there is no cache figure, not a zero one.
    var reportsNoCache: Bool { repliesWithoutCacheFields > 0 && cacheRead == 0 && cacheWrite == 0 }

    /// Everything sent that was not read back from the cache: plain input and
    /// what was written to the cache are the same new content, billed at two
    /// rates by the services that have a write step and at one by the rest.
    var fresh: Int { input + cacheWrite }

    /// Whether the recorded kinds plus an explicit unclassified count account
    /// for the reported total. Missing detail is never inferred by subtraction.
    func accountsFor(tokens: Int, unclassified: Int = 0) -> Bool {
        var total = 0
        for value in [input, cacheWrite, cacheRead, output, unclassified] {
            guard value >= 0 else { return false }
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return false }
            total = sum
        }
        return total == tokens
    }

    static func + (lhs: TokenTally, rhs: TokenTally) -> TokenTally {
        TokenTally(
            input: lhs.input + rhs.input,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            output: lhs.output + rhs.output,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h,
            repliesWithoutCacheFields: lhs.repliesWithoutCacheFields + rhs.repliesWithoutCacheFields,
            contextBands: lhs.contextBands.merging(rhs.contextBands, uniquingKeysWith: +)
        )
    }

    /// The token kinds less another tally's, for taking a band out of the
    /// whole before the rest is priced at the base rates.
    private func removing(_ other: TokenTally) -> TokenTally {
        TokenTally(
            input: max(input - other.input, 0),
            cacheWrite: max(cacheWrite - other.cacheWrite, 0),
            cacheRead: max(cacheRead - other.cacheRead, 0),
            output: max(output - other.output, 0),
            cacheWrite1h: max(cacheWrite1h - other.cacheWrite1h, 0)
        )
    }

    /// Rates are per million tokens. A missing cache rate falls back to the
    /// plain input rate — that is the provider's own arrangement for models
    /// that don't price the cache separately, not a guess.
    ///
    /// **The split is the only formula.** `cost(at:)` is this breakdown's
    /// total, so a day's money and the per-model money it is built from come
    /// out of one arithmetic instead of two that would eventually disagree.
    ///
    /// **A long-context request is priced at its tier, whole.** Each band's
    /// requests are taken out and priced at the tier their size reached; the
    /// rest at the base rates.
    func costBreakdown(at price: ModelPrice) -> TokenCost {
        var rest = self
        rest.contextBands = [:]
        var cost = TokenCost()
        for (band, requests) in contextBands {
            guard let tier = price.tier(forBand: band) else { continue }
            rest = rest.removing(requests)
            cost = cost + requests.flatCost(at: tier.price)
        }
        return cost + rest.flatCost(at: price)
    }

    private func flatCost(at price: ModelPrice) -> TokenCost {
        let hourWrites = min(max(cacheWrite1h, 0), cacheWrite)
        return TokenCost(
            input: Double(input) * price.input / 1_000_000,
            cacheWrite: (Double(cacheWrite - hourWrites) * (price.cacheWrite ?? price.input)
                + Double(hourWrites) * price.input * Self.hourWriteMultiplier) / 1_000_000,
            cacheRead: Double(cacheRead) * (price.cacheRead ?? price.input) / 1_000_000,
            output: Double(output) * price.output / 1_000_000
        )
    }

    func cost(at price: ModelPrice) -> Double {
        costBreakdown(at: price).total
    }

    /// A one-hour cache write against the plain input rate, as Anthropic
    /// publishes it. models.dev lists only the five-minute rate.
    static let hourWriteMultiplier = 2.0
}

extension TokenTally {
    private enum CodingKeys: String, CodingKey {
        case input, cacheWrite, cacheRead, output, cacheWrite1h, repliesWithoutCacheFields, contextBands
    }

    /// Every field optional on the way in: a cache written before a field
    /// existed still reads, as zero, rather than failing whole.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            input: try container.decodeIfPresent(Int.self, forKey: .input) ?? 0,
            cacheWrite: try container.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0,
            cacheRead: try container.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0,
            output: try container.decodeIfPresent(Int.self, forKey: .output) ?? 0,
            cacheWrite1h: try container.decodeIfPresent(Int.self, forKey: .cacheWrite1h) ?? 0,
            repliesWithoutCacheFields: try container.decodeIfPresent(Int.self, forKey: .repliesWithoutCacheFields) ?? 0,
            contextBands: try container.decodeIfPresent([Int: TokenTally].self, forKey: .contextBands) ?? [:]
        )
    }

    /// Only what is not zero goes out. Every quarter-hour of every model is a
    /// tally in the transcript cache, and most of its fields — the hour's
    /// writes, the bands — are empty for most of them.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for (key, value) in [
            (CodingKeys.input, input), (.cacheWrite, cacheWrite), (.cacheRead, cacheRead), (.output, output),
            (.cacheWrite1h, cacheWrite1h), (.repliesWithoutCacheFields, repliesWithoutCacheFields),
        ] where value != 0 {
            try container.encode(value, forKey: key)
        }
        if !contextBands.isEmpty { try container.encode(contextBands, forKey: .contextBands) }
    }
}

/// How long replies took to come back, and how much they wrote — what an
/// output speed is worked out from.
///
/// **Request sent to reply finished**, the only span both CLIs' logs bracket:
/// the line that sent the request (the user's message, or the last tool
/// result) and the last line of the reply. It includes the wait for the first
/// token, so it reads a little under the model's pure generation speed. Only
/// replies long enough for that wait not to dominate are counted
/// (`minimumOutput`), and none that took longer than `longest` — a retry or a
/// stall, not a speed.
///
/// **The wait for the first token** is a separate figure, and only Codex's:
/// it writes `time_to_first_token_ms` for the first request of each turn.
/// Claude Code's transcript has no such field — its first line is written
/// when a whole content block is done — so its latency is left unsaid rather
/// than guessed.
struct ReplyTiming: Codable, Sendable, Equatable {
    var outputTokens = 0
    var seconds = 0.0
    var replies = 0
    var firstTokenSeconds = 0.0
    var firstTokenTurns = 0

    static let minimumOutput = 100
    static let longest: TimeInterval = 10 * 60
    /// A first token later than this is a stall or a retry, not a latency.
    static let longestFirstToken: TimeInterval = 2 * 60

    /// One turn's wait for its first token, as the CLI measured it.
    static func firstToken(after seconds: Double) -> ReplyTiming? {
        guard seconds > 0, seconds <= longestFirstToken else { return nil }
        return ReplyTiming(firstTokenSeconds: seconds, firstTokenTurns: 1)
    }

    /// One reply, or nothing when it cannot stand for a speed.
    init?(output: Int, from sent: Date, to finished: Date) {
        let seconds = finished.timeIntervalSince(sent)
        guard output >= Self.minimumOutput, seconds > 0, seconds <= Self.longest else { return nil }
        self.init(outputTokens: output, seconds: seconds, replies: 1)
    }

    init(
        outputTokens: Int = 0, seconds: Double = 0, replies: Int = 0,
        firstTokenSeconds: Double = 0, firstTokenTurns: Int = 0
    ) {
        self.outputTokens = outputTokens
        self.seconds = seconds
        self.replies = replies
        self.firstTokenSeconds = firstTokenSeconds
        self.firstTokenTurns = firstTokenTurns
    }

    static func + (lhs: ReplyTiming, rhs: ReplyTiming) -> ReplyTiming {
        ReplyTiming(
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            seconds: lhs.seconds + rhs.seconds,
            replies: lhs.replies + rhs.replies,
            firstTokenSeconds: lhs.firstTokenSeconds + rhs.firstTokenSeconds,
            firstTokenTurns: lhs.firstTokenTurns + rhs.firstTokenTurns
        )
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
/// neither is a transcript the CLI deleted before Pulse ever read it. One
/// Pulse did read stays after the CLI prunes it: its counted share is kept
/// (`TranscriptArchive`, and `AgentArchive` for the other agents), so a
/// past day does not shrink when its files go.
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
        var unpricedTokens: Int = 0
        /// The quarter-hour's tokens split by **raw model id**, where the
        /// reader kept them.
        ///
        /// A `LedgerDay` has already thrown the time of day away, so a model's
        /// own hours can only come from here. Empty for a slot read before the
        /// detail was kept — which is how a per-model breakdown knows its hours
        /// cannot be trusted, rather than dividing the whole agent's usage by
        /// whatever model happened to be named.
        var models: [String: TokenTally] = [:]
        /// The quarter-hour's timed replies by **raw model id** — only the
        /// readers that can tell when a request went out and when its reply
        /// finished (Claude Code's and Codex's transcripts). Kept per slot,
        /// not per day, because a speed is only worth reading while it is
        /// recent (`outputSpeedsByModel(since:)`).
        var timings: [String: ReplyTiming] = [:]
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
        /// The provider's own log of every request on the account — OpenCode's
        /// console — with the tokens of each kind and **the cost it charged**.
        /// Whole account like the statistics, and unlike them priced: the
        /// money is reported, not worked out from a price list.
        case providerLogs

        /// Whether a ledger with this origin may appear in the token spend
        /// pane. Records read or imported here can; a provider's own
        /// statistics cannot, because they carry no money and would put a
        /// figure on a total half of it cannot carry.
        var supportsTokenSpend: Bool {
            switch self {
            case .localTranscripts, .importedRecords: true
            case .providerStatistics, .providerLogs: false
            }
        }
    }

    var origin: Origin = .localTranscripts

    /// What the money is counted in. Nil is dollars — the price lists and
    /// OpenCode's console are — and DeepSeek's console charges a CNY account
    /// in yuan, which a dollar sign would misstate by seven times.
    var currency: String?

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

    /// Whether the records behind this ledger say anything about the prompt
    /// cache. False for a store with no cache column (`SpendAgent.reportsCacheReads`):
    /// its zero hits would read as a cache that never hit, so there is no
    /// cache hit rate to give.
    var reportsCacheReads = true

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
            var unpricedTokens: Int = 0
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
        /// A session Codex ran itself to review another's planned action: no
        /// words of the user's, and no project. Shown as "Codex review"
        /// (`SessionLabel`) rather than as an unnamed file.
        var isReview = false
        /// The stated directory or source-scoped project, with identity kept
        /// separately from the short name shown in the pane.
        let project: UsageProject?
        let start: Date
        let end: Date
        let tokens: Int
        let cost: Double
        var unpricedTokens: Int = 0
        var estimatedCost: Double? { tokens > 0 && unpricedTokens == tokens ? nil : cost }
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

    /// What went through between two moments, with the quarter-hours at
    /// either edge counted for the share of them inside — the figure a
    /// window's worth divides.
    ///
    /// **Not `spend(since:)`.** That drops the quarter-hour a window opened in
    /// and counts everything up to now; the percentage it is set against was
    /// read at one moment, and a five-hour window's first requests — the ones
    /// that write the whole context to the cache — sit in the quarter-hour it
    /// opened in. Work inside a quarter-hour is taken as even, which is an
    /// approximation; leaving it out or counting it whole is a worse one.
    func cost(from start: Date, to end: Date) -> Double {
        share(from: start, to: end) { $0.cost }
    }

    /// The tokens in the same span, the same way — priced or not, which is
    /// what tells "nothing happened here" from "nothing here has a price".
    func tokens(from start: Date, to end: Date) -> Double {
        share(from: start, to: end) { Double($0.tokens) }
    }

    private func share(from start: Date, to end: Date, of value: (Slot) -> Double) -> Double {
        let quarter: TimeInterval = 15 * 60
        return slots.reduce(0) { total, slot in
            let overlap = min(slot.start.addingTimeInterval(quarter), end).timeIntervalSince(max(slot.start, start))
            return overlap > 0 ? total + value(slot) * min(overlap / quarter, 1) : total
        }
    }

    var today: LedgerDay? {
        days.last.flatMap { Calendar.current.isDateInToday($0.date) ? $0 : nil }
    }

    /// A span's tokens and money, and how many of the tokens had no price —
    /// so a span with none priced can say so rather than show `$0.00`.
    func total(overLast count: Int) -> (tokens: Int, cost: Double, unpriced: Int) {
        recent(count).reduce(into: (0, 0.0, 0)) {
            $0.0 += $1.tokens
            $0.1 += $1.cost
            $0.2 += $1.unpricedTokens
        }
    }

    var allTime: (tokens: Int, cost: Double, unpriced: Int) {
        days.reduce(into: (0, 0.0, 0)) {
            $0.0 += $1.tokens
            $0.1 += $1.cost
            $0.2 += $1.unpricedTokens
        }
    }

    /// The money to show for some work, or nil where none of it had a price:
    /// an unpriced model's work cost something, and `$0.00` says it did not.
    static func shownCost(_ cost: Double, tokens: Int, unpriced: Int) -> Double? {
        tokens > 0 && unpriced >= tokens ? nil : cost
    }

    /// The last `count` **calendar** days, today included, oldest first.
    ///
    /// **Not the last `count` entries.** `days` runs from the first record to
    /// the last and stops there, so its tail is the last days anything was
    /// used: after a fortnight off, "the last seven days" would have been the
    /// seven before the break, with their money and their cache rate. Days
    /// after the last record are filled in as quiet; days before the first are
    /// left off, so a week-old install does not draw a month of empty bars.
    func recent(_ count: Int, now: Date = Date()) -> [LedgerDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard count > 0, let first = days.first,
              let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) else { return [] }
        let byDate = Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0) }) { kept, _ in kept }
        var cursor = max(calendar.startOfDay(for: start), calendar.startOfDay(for: first.date))
        var span: [LedgerDay] = []
        while cursor <= today {
            span.append(byDate[cursor] ?? LedgerDay(date: cursor, tokens: 0, cost: 0, unpricedTokens: 0, models: [:]))
            // `startOfDay` again: a midnight DST start would otherwise leave
            // every later day at 01:00, off its key.
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: next)
        }
        return span
    }

    /// How much of the input over a span was served from the prompt cache:
    /// cache reads over every input token — fresh, written to the cache, and
    /// read from it. Output is not input and is left out.
    ///
    /// **Only where every token was sorted into its kind.** A source that
    /// reports a bare total leaves tokens no kind can claim, and dividing
    /// around them would state a rate for part of the work as though it were
    /// the whole; so would a store that cannot prove its counts are complete.
    /// Nil then, and nil with no input at all.
    func cacheHitRate(overLast count: Int) -> Double? {
        guard case .measured(let tally) = cacheReading(in: recent(count)) else { return nil }
        let input = tally.input + tally.cacheWrite + tally.cacheRead
        guard input > 0 else { return nil }
        return Double(tally.cacheRead) / Double(input)
    }

    /// What a span's records say about the prompt cache — the rule
    /// `cacheHitRate` applies, kept apart so a rate over several ledgers (the
    /// recap's) adds up the same measured tallies instead of working the rule
    /// out a second way.
    enum CacheReading: Equatable, Sendable {
        /// The input kinds the rate is measured over: cache reads, and every
        /// input token beside them, from the models that said anything about
        /// the cache.
        case measured(TokenTally)
        /// The store (or every model in it) records no cache. Its zero hits
        /// are not a cache that missed, so it has no part in a rate.
        case unrecorded
        /// Counts that may be missing or cannot be sorted into their kinds:
        /// a rate over them would state part of the work as the whole.
        case unvouched
    }

    func cacheReading(in span: [LedgerDay]) -> CacheReading {
        guard reportsCacheReads else { return .unrecorded }
        guard !hasPartialCounts else { return .unvouched }
        let tally = span.reduce(TokenTally()) { $0 + $1.tally }
        let tokens = span.reduce(0) { $0 + $1.tokens }
        guard tally.total == tokens else { return .unvouched }

        // **A model that said nothing about the cache is left out of the
        // rate**, not counted as all misses: its input would sit in the
        // denominator with no hits possible above it. Where every model is
        // such a one, there is no rate. Days read before per-model tallies
        // were kept can only be judged whole.
        var byModel: [String: TokenTally] = [:]
        var split = true
        for day in span {
            if day.tokens > 0, day.modelTallies.isEmpty { split = false }
            for (raw, model) in day.modelTallies { byModel[raw] = (byModel[raw] ?? TokenTally()) + model }
        }
        let measured = split ? byModel.values.filter { !$0.reportsNoCache }.reduce(TokenTally(), +) : tally
        guard !measured.reportsNoCache else { return .unrecorded }
        return .measured(measured)
    }

    /// One model's cache hit rate over a span, and how much input it is
    /// measured over — the order they are listed in.
    struct ModelCacheRate: Equatable, Sendable {
        let name: String
        let rate: Double
        let inputTokens: Int
    }

    /// `cacheHitRate` for each model, most input first.
    ///
    /// Grouped by **display name**, the way the top model is: several raw ids
    /// can be one model. A model is left out when any of its tokens in the
    /// span cannot be vouched for by kind — a day that counted it with no
    /// split kept (read before the split was), or tokens its source could not
    /// classify — so no model's rate is worked out over part of its work.
    func cacheHitRatesByModel(overLast count: Int) -> [ModelCacheRate] {
        guard !hasPartialCounts, reportsCacheReads else { return [] }
        var tallies: [String: TokenTally] = [:]
        var unvouched: Set<String> = []
        for day in recent(count) {
            for (raw, tokens) in day.models where tokens > 0 {
                let name = modelNames[raw] ?? raw
                guard let tally = day.modelTallies[raw], (day.modelUnclassifiedTokens[raw] ?? 0) == 0 else {
                    unvouched.insert(name)
                    continue
                }
                tallies[name, default: TokenTally()] = (tallies[name] ?? TokenTally()) + tally
            }
        }
        return tallies.compactMap { name, tally in
            let input = tally.input + tally.cacheWrite + tally.cacheRead
            guard !unvouched.contains(name), !tally.reportsNoCache, input > 0 else { return nil }
            return ModelCacheRate(name: name, rate: Double(tally.cacheRead) / Double(input), inputTokens: input)
        }
        .sorted { $0.inputTokens != $1.inputTokens ? $0.inputTokens > $1.inputTokens : $0.name < $1.name }
    }

    /// One model's output speed over a span — output tokens per second across
    /// its timed replies — and its average wait for the first token. Either
    /// is nil when too few were timed.
    struct ModelSpeed: Equatable, Sendable {
        let name: String
        let tokensPerSecond: Double?
        let firstToken: TimeInterval?
        let outputTokens: Int
    }

    /// Fewer timed replies (or turns) than this and a model's figure is one or
    /// two requests' luck, so it is left out.
    static let fewestTimedReplies = 5

    /// How far back a speed is read: the last day, rolling. A month's
    /// average says how the model was, not how it is.
    static let speedSpan: TimeInterval = 24 * 3600

    /// `ReplyTiming` added up per model since a moment, most output first.
    ///
    /// **All output over all time**, not an average of each reply's speed: a
    /// short reply and a long one weigh what they wrote. The first-token wait
    /// is the mean over turns. Grouped by display name like the cache rates.
    /// A quarter-hour straddling `start` is left out.
    func outputSpeedsByModel(since start: Date) -> [ModelSpeed] {
        var timings: [String: ReplyTiming] = [:]
        for slot in slots where slot.start >= start {
            for (raw, timing) in slot.timings {
                let name = modelNames[raw] ?? raw
                timings[name, default: ReplyTiming()] = (timings[name] ?? ReplyTiming()) + timing
            }
        }
        return timings.compactMap { name, timing in
            let speed = timing.replies >= Self.fewestTimedReplies && timing.seconds > 0
                ? Double(timing.outputTokens) / timing.seconds : nil
            let firstToken = timing.firstTokenTurns >= Self.fewestTimedReplies
                ? timing.firstTokenSeconds / Double(timing.firstTokenTurns) : nil
            guard speed != nil || firstToken != nil else { return nil }
            return ModelSpeed(
                name: name, tokensPerSecond: speed, firstToken: firstToken,
                outputTokens: speed == nil ? 0 : timing.outputTokens
            )
        }
        .sorted { $0.outputTokens != $1.outputTokens ? $0.outputTokens > $1.outputTokens : $0.name < $1.name }
    }

    /// Each model's share of the tokens over a span, largest first — the
    /// whole list `topModel` is the head of, grouped by display name.
    func modelShares(overLast count: Int) -> [(name: String, tokens: Int, share: Double)] {
        var totals: [String: Int] = [:]
        for day in recent(count) {
            for (raw, tokens) in day.models where tokens > 0 { totals[modelNames[raw] ?? raw, default: 0] += tokens }
        }
        let overall = totals.values.reduce(0, +)
        guard overall > 0 else { return [] }
        return totals
            .map { (name: $0.key, tokens: $0.value, share: Double($0.value) / Double(overall)) }
            .sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.name < $1.name }
    }

    /// The heaviest day in a span. Scoped rather than all-time so it sits
    /// beside the other figures on the card without quietly changing the
    /// window they all share.
    func busiestDay(overLast count: Int) -> LedgerDay? {
        recent(count).max { $0.tokens < $1.tokens }
    }

    /// The model most of the work went through, and how much of it. Falls back
    /// to the whole history when the recent window is quiet, so the line
    /// doesn't vanish after a week off.
    func topModel(overLast count: Int) -> (name: String, share: Double)? {
        let recent = recent(count)
        let window = recent.contains { $0.tokens > 0 } ? recent : days

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

    /// The number in `ledger-<n>-<provider>.json`; see `FileCache.file`.
    nonisolated static let cacheVersion = 9

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
        var ledger = Self.priced(scanned.buckets, with: prices, calendar: .current, timings: scanned.timings)
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
        _ totals: [String: (tokens: Int, cost: Double, unpriced: Int)]
    ) -> [UsageLedger.Slot] {
        totals
            .compactMap { key, value in
                sharedSlotFormatter.date(from: key).map {
                    UsageLedger.Slot(start: $0, tokens: value.tokens, cost: value.cost, unpricedTokens: value.unpriced)
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
        vendor: String? = nil,
        timings: [String: [String: ReplyTiming]] = [:]
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
        var lookup = ModelPriceLookup(prices)

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

                if let price = lookup.price(for: model, vendor: vendor) {
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

            slots.append(UsageLedger.Slot(
                start: start, tokens: tokens, cost: cost, unpricedTokens: unpricedTokens,
                models: models, timings: timings[key] ?? [:]
            ))

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
            // `startOfDay` again: a midnight DST start would otherwise leave
            // every later day at 01:00, off its key.
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: next)
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

    private func scan(
        _ provider: Provider
    ) -> (buckets: Buckets, timings: [String: [String: ReplyTiming]], files: [String: FileCache.Entry]) {
        var cache = FileCache.load(for: provider, directory: cacheDirectory)
        // Nil when the archive is there and cannot be read: nothing is moved
        // into it, and the files it would have kept stay in the cache instead.
        // **Off for a reader pointed at another home without its own cache
        // folder** — its scan must neither read this Mac's kept history into
        // its figures nor keep its files into it; gone files are then dropped,
        // as before there was an archive.
        let archives = cacheDirectory != nil
            || home.standardizedFileURL == URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        var archive = archives ? TranscriptArchive.load(for: provider, directory: cacheDirectory) : TranscriptArchive()
        var archiveChanged = false
        var buckets: Buckets = [:]
        var timings: [String: [String: ReplyTiming]] = [:]
        var fresh: [String: FileCache.Entry] = [:]
        var names: Set<String> = []
        var changed = false

        let roots = Self.roots(for: provider, home: home)
        for file in Self.logFiles(in: roots) {
            guard !Task.isCancelled else { return ([:], [:], [:]) }
            guard let stamp = FileCache.Stamp(file) else { continue }
            let key = file.path
            if provider == .codex { names.insert(file.lastPathComponent) }

            // A log file is rewritten only by being appended to, so size and
            // modification date together are enough to know nothing changed.
            if let known = cache.files.removeValue(forKey: key), known.stamp == stamp {
                fresh[key] = known
            } else {
                changed = true
                let scanned = autoreleasepool { parse(file, provider: provider) }
                guard !Task.isCancelled else { return ([:], [:], [:]) }
                fresh[key] = FileCache.Entry(
                    stamp: stamp, days: scanned.days, title: scanned.title, cwd: scanned.cwd,
                    isReview: scanned.isReview ? true : nil,
                    timings: scanned.timings, replies: scanned.replies,
                    runningTotals: scanned.runningTotals.isEmpty ? nil : scanned.runningTotals
                )
            }
        }

        // A transcript back where the archive kept it — at its path, or, for
        // Codex, under its name somewhere else — is read from the file again,
        // not kept as well. A rollout's name carries its session id, so one
        // cannot be another conversation's; Claude Code has same-named files
        // in different folders (`journal.jsonl`) and is matched by path only.
        if let kept = archive?.files {
            let back = kept.keys.filter { fresh[$0] != nil || names.contains(Self.fileName($0)) }
            for path in back { archive?.files[path] = nil }
            archiveChanged = !back.isEmpty
        }

        // Entries left in the old cache are files gone since the last scan.
        // They are counted once more beside the live ones, so the dedupe below
        // splits the replies exactly as it did while they existed, and then
        // kept. Not kept: a Codex rollout whose name is still among the live
        // ones, which was moved (Codex moves a session it archives) and is that
        // file now; one already kept, by a scan that could not write the cache
        // after it; and one outside the folders this reader reads, which is no
        // transcript of this Mac's (a cache another home's scan wrote).
        let gone = !archives ? [:] : cache.files.filter { path, _ in
            !names.contains(Self.fileName(path)) && archive?.files[path] == nil
                && Self.isInside(path, roots)
        }

        // Each reply once, for the file it appeared in first — the original
        // conversation, not a resumed or forked copy of its history. Files are
        // taken oldest work first, then by name, then by path, so the choice
        // is stable. A Codex fork goes after every session that is not one:
        // it can open in the quarter-hour its parent did, and its parent's
        // readings must already be counted when its copies of them come by.
        // Codex names a rollout for when it was made, so by name a fork of a
        // fork still follows the fork it came from. **Kept files go before all
        // of them**: what they counted was settled while they existed, and
        // their claims hold it.
        let ordered = fresh.merging(gone) { live, _ in live }.map {
            (key: $0.key, entry: $0.value, first: $0.value.firstSlot ?? "", fork: $0.value.isFork)
        }.sorted { lhs, rhs in
            if lhs.fork != rhs.fork { return !lhs.fork }
            if lhs.first != rhs.first { return lhs.first < rhs.first }
            let left = (lhs.key as NSString).lastPathComponent, right = (rhs.key as NSString).lastPathComponent
            return left != right ? left < right : lhs.key < rhs.key
        }
        let kept = archive?.files ?? [:]
        let keptClaims = Set(kept.values.flatMap { ClaimDigest.unpack($0.claims) })
        let keptTotals = Set(kept.values.flatMap { ClaimDigest.unpack($0.totals) })
        var claimed: Set<String> = []
        var totals: Set<String> = []
        var counted: [String: FileCache.Entry] = [:]
        for (key, entry, _, fork) in ordered {
            guard !Task.isCancelled else { return ([:], [:], [:]) }
            let keeping = archive != nil && gone[key] != nil
            var days = entry.days
            // A fork's lines carry the instant it was made, not when its work
            // ran, and its replayed readings are dropped below: its timings
            // would time nothing real.
            var fileTimings = fork ? [:] : entry.timings ?? [:]
            var ownClaims: [UInt64] = []
            var ownTotals = keeping ? (entry.runningTotals ?? []).map(ClaimDigest.of) : []
            // An original session's totals are claimed before any fork is
            // read: the forks come after every file that is not one.
            totals.formUnion(entry.runningTotals ?? [])
            for (id, reply) in entry.replies ?? [:] {
                if reply.fromFork == true, let total = reply.runningTotal,
                   totals.contains(total) || keptTotals.contains(ClaimDigest.of(total)) { continue }
                guard !keptClaims.contains(ClaimDigest.of(id)), claimed.insert(id).inserted else { continue }
                if let total = reply.runningTotal {
                    totals.insert(total)
                    if keeping { ownTotals.append(ClaimDigest.of(total)) }
                }
                if keeping { ownClaims.append(ClaimDigest.of(id)) }
                days[reply.slot, default: [:]][reply.model] = (days[reply.slot]?[reply.model] ?? TokenTally()) + reply.tally
                if let timing = reply.timing {
                    fileTimings[reply.slot, default: [:]][reply.model] =
                        (fileTimings[reply.slot]?[reply.model] ?? ReplyTiming()) + timing
                }
            }
            counted[key] = FileCache.Entry(
                stamp: entry.stamp, days: days, title: entry.title, cwd: entry.cwd,
                isReview: entry.isReview, timings: fileTimings
            )
            if keeping {
                archive?.files[key] = TranscriptArchive.Kept(
                    days: days, timings: fileTimings.isEmpty ? nil : fileTimings,
                    title: entry.title, cwd: entry.cwd, isReview: entry.isReview,
                    claims: ClaimDigest.pack(ownClaims), totals: ClaimDigest.pack(ownTotals),
                    kept: Date()
                )
                archiveChanged = true
            }
            Self.add(days, fileTimings, to: &buckets, &timings)
        }

        // What was kept before this scan, added as it was counted.
        for (path, file) in kept {
            guard !Task.isCancelled else { return ([:], [:], [:]) }
            counted[path] = FileCache.Entry(
                stamp: FileCache.Stamp(size: 0, modified: 0), days: file.days, title: file.title, cwd: file.cwd,
                isReview: file.isReview, timings: file.timings
            )
            Self.add(file.days, file.timings ?? [:], to: &buckets, &timings)
        }

        // The archive is written before the cache lets the gone files go, and
        // if it cannot be, they stay in the cache to be kept by a later scan.
        // Repricing unchanged transcripts does not change either file or
        // warrant a write.
        let keptSafely = !archives || !archiveChanged || archive?.save(for: provider, directory: cacheDirectory) == true
        if changed || !cache.files.isEmpty {
            cache.files = fresh
            if archive == nil || !keptSafely { cache.files.merge(gone) { live, _ in live } }
            cache.save(for: provider, directory: cacheDirectory)
        }
        // The sessions are cut from the counted entries, so a resumed
        // conversation's row holds only what was done in it.
        return (buckets, timings, counted)
    }

    /// One file's counted quarter-hours and timings, added to the provider's.
    private static func add(
        _ days: [String: [String: TokenTally]], _ fileTimings: [String: [String: ReplyTiming]],
        to buckets: inout Buckets, _ timings: inout [String: [String: ReplyTiming]]
    ) {
        for (day, models) in days {
            for (model, tally) in models {
                buckets[day, default: [:]][model] = (buckets[day]?[model] ?? TokenTally()) + tally
            }
        }
        for (day, models) in fileTimings {
            for (model, timing) in models {
                timings[day, default: [:]][model] = (timings[day]?[model] ?? ReplyTiming()) + timing
            }
        }
    }

    private static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// One row per conversation, priced the same way the days are.
    ///
    /// The cache is keyed by path and holds each file's own buckets, so this
    /// is a second rollup of numbers already in hand rather than another pass
    /// over the transcripts.
    ///
    /// **A conversation can be several files.** Claude Code writes each
    /// subagent's transcript beside its parent's (`sessionFile(of:)`); those
    /// files' tokens are real and are in the days, models and projects like
    /// any other, but as rows they were a "Pulse" session apiece. They are
    /// folded into the parent's row here — summed, the span widened — after
    /// `scan` has counted every reply once, so nothing is counted twice.
    private func sessions(
        _ files: [String: FileCache.Entry],
        provider: Provider,
        prices: [String: ModelPrice]
    ) -> [UsageLedger.Session] {
        /// One conversation's files, added up.
        struct Rollup {
            var tokens = 0
            var cost = 0.0
            var unpriced = 0
            var start: Date?
            var end: Date?
            /// By quarter-hour key (`slotKey(for:)`).
            var slots: [String: (tokens: Int, cost: Double, unpriced: Int)] = [:]
            /// Where the conversation ran and what it was called — the
            /// parent's own when it has them, else the first subagent's (by
            /// path, so the choice is stable).
            var title: String?
            var cwd: String?
            var isReview = false
            var parentSeen = false
        }

        var rollups: [String: Rollup] = [:]
        var lookup = ModelPriceLookup(prices)

        for (path, entry) in files.sorted(by: { $0.key < $1.key }) {
            guard !Task.isCancelled else { return [] }
            let group = provider == .claudeCode ? Self.sessionFile(of: path) : path
            var rollup = rollups[group] ?? Rollup()

            for (key, models) in entry.days {
                guard let at = slotFormatter.date(from: key) else { continue }

                var slot = rollup.slots[key] ?? (0, 0, 0)
                let before = slot.tokens
                for (model, tally) in models {
                    rollup.tokens += tally.total
                    slot.tokens += tally.total
                    if let price = lookup.price(for: model) {
                        let money = tally.cost(at: price)
                        rollup.cost += money
                        slot.cost += money
                    } else {
                        rollup.unpriced += tally.total
                        slot.unpriced += tally.total
                    }
                }
                rollup.slots[key] = slot
                // A quarter-hour with no tokens in it is not when the
                // conversation ran.
                guard slot.tokens > before else { continue }
                rollup.start = min(rollup.start ?? at, at)
                rollup.end = max(rollup.end ?? at, at)
            }
            // A parent whose every reply was counted in another file still
            // names the conversation, so this is not skipped for having no
            // work of its own left.
            if group == path {
                rollup.parentSeen = true
                rollup.title = entry.title ?? rollup.title
                rollup.cwd = entry.cwd ?? rollup.cwd
                rollup.isReview = entry.isReview == true
            } else if !rollup.parentSeen {
                rollup.title = rollup.title ?? entry.title
                rollup.cwd = rollup.cwd ?? entry.cwd
            }
            rollups[group] = rollup
        }

        var sessions: [UsageLedger.Session] = []
        for (path, rollup) in rollups {
            guard rollup.tokens > 0, let start = rollup.start, let end = rollup.end else { continue }
            let url = URL(fileURLWithPath: path)
            sessions.append(
                UsageLedger.Session(
                    id: path,
                    name: url.deletingPathExtension().lastPathComponent,
                    title: rollup.title,
                    isReview: rollup.isReview,
                    project: UsageProject(rollup.cwd)
                        ?? Self.project(of: url, provider: provider),
                    start: start,
                    end: end,
                    tokens: rollup.tokens,
                    cost: rollup.cost,
                    unpricedTokens: rollup.unpriced,
                    slots: Self.sessionSlots(rollup.slots)
                )
            )
        }

        return sessions.sorted { $0.end > $1.end }
    }

    /// The transcript a Claude Code file belongs to: its own path, or for a
    /// subagent's — `<project>/<session>/subagents/agent-<id>.jsonl` — the
    /// parent's, `<project>/<session>.jsonl`, whether or not that file is
    /// still there. A string rule, like the rest of the grouping.
    static func sessionFile(of path: String) -> String {
        guard let range = path.range(of: "/subagents/"), range.lowerBound > path.startIndex, path.hasSuffix(".jsonl")
        else { return path }
        return String(path[..<range.lowerBound]) + ".jsonl"
    }

    /// The fallback for a transcript that states no `cwd`.
    ///
    /// Claude Code names a project's directory for its path with every
    /// separator replaced by a dash (`-Users-me-Code-Pulse`), and the last
    /// segment of that is the best guess available — it is a guess, which is
    /// why the stated `cwd` is preferred wherever there is one. Codex files
    /// sit under a date and carry no directory in the path at all.
    static func project(of file: URL, provider: Provider) -> UsageProject? {
        guard provider == .claudeCode else { return nil }

        let folder = file.deletingLastPathComponent().lastPathComponent
        let parts = folder.split(separator: "-", omittingEmptySubsequences: true)
        guard let last = parts.last.map(String.init), !last.isEmpty else { return nil }
        return UsageProject(source: file.deletingLastPathComponent().path, name: last)
    }

    /// The folders a provider's transcripts are read from.
    private static func roots(for provider: Provider, home: URL) -> [URL] {
        // None of the profiled providers leaves transcripts here either.
        guard let written = provider.handWritten else { return [] }
        // Codex moves a session it archives out of `sessions` into
        // `archived_sessions`; the work in it was still done.
        let roots: [URL] = switch written {
        case .claudeCode: [home.appending(path: ".claude/projects")]
        case .codex: [home.appending(path: ".codex/sessions"), home.appending(path: ".codex/archived_sessions")]
        // Antigravity is an editor and keeps nothing; OpenCode keeps its own
        // store rather than the JSONL these two parsers read.
        case .kiro, .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot,
             .volcengine, .commandCode, .deepSeek, .devin, .xiaomiMiMo,
             .sub2api, .newAPI, .v2ex, .qoder, .stepFun, .pulseExtension: []
        }
        return roots
    }

    /// Whether a path lies inside one of the folders, as written or as the
    /// link it may be resolves (a `~/.claude` linked elsewhere is walked at
    /// its target). `/var` and `/tmp` are links into `/private`, and the walker
    /// can hand back either spelling (`resolvingSymlinksInPath` strips
    /// `/private` rather than adding it), so both sides are compared without it.
    private static func isInside(_ path: String, _ roots: [URL]) -> Bool {
        func plain(_ path: String) -> String {
            path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
        }
        return roots.contains { root in
            [root.path, root.resolvingSymlinksInPath().path].contains { plain(path).hasPrefix(plain($0) + "/") }
        }
    }

    private static func logFiles(in roots: [URL]) -> [URL] {
        var files: [URL] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let file = autoreleasepool(invoking: { walker.nextObject() as? URL }) {
                guard !Task.isCancelled else { return [] }
                if file.pathExtension == "jsonl" { files.append(file) }
            }
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
        /// A Codex session that opens with a review request instead of the
        /// user's words (`codexReviewOpening`).
        var isReview = false
        /// Timed replies by quarter-hour and then model (`ReplyTiming`).
        var timings: [String: [String: ReplyTiming]] = [:]
        /// Claude Code's replies by message id, and a Codex fork's readings by
        /// the running total they reached, kept apart from `days` so that
        /// `scan` can count each **once across files** (`ScannedReply`).
        var replies: [String: ScannedReply] = [:]
        /// The running totals a Codex session that is not a fork reached,
        /// which its forks' replayed readings repeat (`parseCodex`).
        var runningTotals: [String] = []

        /// `days` with the replies folded in — one file's own figures.
        var allDays: [String: [String: TokenTally]] {
            var days = days
            for reply in replies.values {
                days[reply.slot, default: [:]][reply.model] = (days[reply.slot]?[reply.model] ?? TokenTally()) + reply.tally
            }
            return days
        }

        /// `timings` with the replies' own folded in.
        var allTimings: [String: [String: ReplyTiming]] {
            var timings = timings
            for reply in replies.values {
                guard let timing = reply.timing else { continue }
                timings[reply.slot, default: [:]][reply.model] = (timings[reply.slot]?[reply.model] ?? ReplyTiming()) + timing
            }
            return timings
        }
    }

    /// One Claude Code reply: where it landed, on which model, what it cost
    /// in tokens, and how long it took where that could be timed.
    ///
    /// **Kept by message id because a reply can be in more than one file.**
    /// Resuming or forking a conversation starts a new transcript that opens
    /// with a copy of the old one's history — the same message ids at the same
    /// times. Added up file by file, every resumed session counted its history
    /// again: on the Mac this was found on, 1,768 replies sat in two or more
    /// files and 28% of the tokens counted were copies.
    struct ScannedReply: Codable, Sendable, Equatable {
        let slot: String
        let model: String
        let tally: TokenTally
        var timing: ReplyTiming?
        /// A Codex reading's running total. Every counted reading claims it;
        /// a reading from a forked rollout is dropped when an earlier file
        /// already did, because it is the parent's request played back.
        ///
        /// **Only a fork's readings are ever dropped this way.** Two unrelated
        /// sessions can reach the same small total — the same prompt sent
        /// twice, the window starter's "hi" — and neither is a copy.
        var runningTotal: String?
        var fromFork: Bool?
    }

    // Internal for the on-disk streaming/cancellation regression fixtures.
    func parse(_ file: URL, provider: Provider) -> Scanned {
        // No profiled provider leaves a transcript this reads either.
        guard let written = provider.handWritten else { return Scanned() }
        switch written {
        case .claudeCode: return parseClaudeCode(LogLines(at: file))
        case .codex: return parseCodex(LogLines(at: file))
        case .kiro, .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot,
             .volcengine, .commandCode, .deepSeek, .devin, .xiaomiMiMo,
             .sub2api, .newAPI, .v2ex, .qoder, .stepFun, .pulseExtension: return Scanned()
        }
    }

    /// The opening prompt, cut to something a row can hold.
    ///
    /// **Not the whole message.** These are the user's own words and a row is
    /// one line; the point is to tell one conversation from another, which the
    /// first few words do.
    ///
    /// **Links are unwrapped, not shown as markup.** `[text](url)` reads as
    /// its text and `[url]` or `<url>` as the url. A message that opens with a
    /// line that is only a link and carries words below it is named for the
    /// first of those lines — the link is what was pasted, the words are the
    /// request. A message that is only a link reads as `host/first-segment/…`
    /// (`compactLink(_:)`), never as a scheme and a long path.
    static func title(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A pasted file or a command envelope is not a title. A `<url>` is
        // markdown's way to write a link, not an envelope.
        guard !trimmed.hasPrefix("<") || trimmed.hasPrefix("<http"), !trimmed.hasPrefix("Caveat:") else { return nil }

        let lines = trimmed.split(whereSeparator: \.isNewline)
            .map { collapsingWhitespace(unwrappingLinks(String($0))) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }

        let cleaned: String
        if isLinkOnly(first) {
            // The first line of words below the link, else the link itself.
            cleaned = lines.first { !isLinkOnly($0) } ?? compactLink(first)
        } else {
            cleaned = lines.joined(separator: " ")
        }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.count <= 70 ? cleaned : String(cleaned.prefix(69)) + "…"
    }

    /// `[text](url)` as `text`, `[](url)` as `url`, `[url]` and `<url>` as the
    /// url.
    private static func unwrappingLinks(_ line: String) -> String {
        var result = line
        for (pattern, template) in [
            (#"!?\[([^\]]+)\]\([^)]*\)"#, "$1"),
            (#"!?\[\]\(([^)\s]+)[^)]*\)"#, "$1"),
            (#"\[(https?://[^\]\s]+)\]"#, "$1"),
            (#"<(https?://[^>\s]+)>"#, "$1"),
        ] {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return result
    }

    private static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func isLinkOnly(_ line: String) -> Bool {
        line.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil
    }

    /// `host/first-path-segment/…` for a link: no scheme, no brackets, no
    /// query. The ellipsis marks that there is more path after the segment.
    /// A link that cannot be read is shown without its scheme.
    static func compactLink(_ link: String) -> String {
        guard let components = URLComponents(string: link), let host = components.host, !host.isEmpty else {
            return link.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
        }
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = segments.first else { return host }
        return "\(host)/\(first)" + (segments.count > 1 ? "/…" : "")
    }

    /// The opening of the message Codex puts first in a session it runs to
    /// review another's planned action.
    static let codexReviewOpening = "The following is the Codex agent history"

    /// Whether a Codex user-role message is a review request rather than the
    /// user's words (`codexTitle(in:)` gives such a message no title).
    static func isCodexReview(in content: Any?) -> Bool {
        text(in: content)?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(codexReviewOpening) == true
    }

    /// What a Codex user-role message says **in the user's own words**, as a
    /// title, or nil when the message is context Codex put there itself.
    ///
    /// **Codex writes more user-role messages than the user does.** A rollout
    /// opens with `# AGENTS.md instructions for …` and an
    /// `<environment_context>` (or `<recommended_plugins>`), and the app adds
    /// `<turn_aborted>`, `<subagent_notification>` and `<image>` envelopes
    /// later; the IDE extension puts `# Context from my IDE setup:` before the
    /// request, which follows `## My request for Codex:`. The first of these
    /// used to be the title, so sessions were named for their instructions. A
    /// session Codex runs to review another's planned action opens with a
    /// message that says so, and that is not the user's either. Envelopes
    /// start with `<`, which `title(from:)` already refuses.
    ///
    /// Only the message's first part is read, as for Claude Code: the rest of
    /// an injected message can be a transcript.
    static func codexTitle(in content: Any?) -> String? {
        guard let text = text(in: content) else { return nil }
        var opening = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if opening.hasPrefix("# AGENTS.md instructions")
            || opening.hasPrefix(codexReviewOpening) {
            return nil
        }
        if opening.hasPrefix("# Context from my IDE setup") || opening.hasPrefix("# Files mentioned by the user") {
            guard let marker = opening.range(of: "## My request for Codex:") else { return nil }
            opening = String(opening[marker.upperBound...])
        }
        return title(from: opening)
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
        // **A reply is written over several lines**, one per content block,
        // each carrying the usage so far — the output count climbs to the
        // last. Kept by message id with the last line's counts, which also
        // absorbs the repeats retries write within a file; copies in other
        // files are `scan`'s to drop (`ScannedReply`). Keeping the first
        // line's, as this did, missed about a quarter of the output.
        var replies: [String: ScannedReply] = [:]
        var clock = ReplyClock()

        lines.forEachLine { line in
            // A request goes out on the user's message or the last tool
            // result. Only the time is wanted, and a tool result can be a
            // whole file, so it is cut out of the line rather than parsed.
            // The top-level `type` and `timestamp` are the only ones a user
            // line has unescaped.
            if contains(line, "\"type\":\"user\""), let sent = timestamp(in: line).flatMap(date(fromISO8601:)) {
                clock.sent(at: sent)
            }

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
                let at = date(fromISO8601: timestamp)
            else { return }
            let slot = slot(of: at)

            let written = int(usage["cache_creation_input_tokens"])
            let tally = TokenTally(
                input: int(usage["input_tokens"]),
                cacheWrite: written,
                cacheRead: int(usage["cache_read_input_tokens"]),
                output: int(usage["output_tokens"]),
                cacheWrite1h: min(int((usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"]), written),
                repliesWithoutCacheFields: usage["cache_read_input_tokens"] == nil
                    && usage["cache_creation_input_tokens"] == nil ? 1 : 0
            )
            // One reply is one request; all it was sent is its context.
            .request(context: int(usage["input_tokens"]) + written + int(usage["cache_read_input_tokens"]))

            guard let id = message["id"] as? String else {
                if tally.total > 0 { days[slot, default: [:]][model] = (days[slot]?[model] ?? TokenTally()) + tally }
                return
            }
            // Placed at its first line, counted at its last.
            let placed = replies[id]?.slot ?? slot
            replies[id] = ScannedReply(slot: placed, model: model, tally: tally)
            clock.reply(id, model: model, slot: placed, output: tally.output, at: at)
        }
        clock.finish()

        for (id, timing) in clock.timings { replies[id]?.timing = timing }
        scanned.days = days
        scanned.replies = replies.filter { $0.value.tally.total > 0 }
        return scanned
    }

    /// Times Claude Code's replies as their lines go by: from the last line
    /// that sent a request to the last line of the reply.
    ///
    /// **Not before the previous reply finished.** A tool result can land
    /// between two lines of the reply that asked for it (seen in a few
    /// hundred replies here); the next request still waits for the reply to
    /// end.
    private struct ReplyClock {
        /// By message id, so the timing travels with its reply (`ScannedReply`).
        private(set) var timings: [String: ReplyTiming] = [:]
        private var pending: Date?
        private var open: (id: String, model: String, slot: String, sent: Date?, finished: Date, output: Int)?
        private var lastFinished: Date?
        private var done: Set<String> = []

        mutating func sent(at date: Date) { pending = date }

        mutating func reply(_ id: String, model: String, slot: String, output: Int, at date: Date) {
            if open?.id == id {
                open?.finished = date
                open?.output = output
                return
            }
            finish()
            // A reply seen again after another — a resumed session's copy —
            // was timed the first time.
            guard !done.contains(id) else { return }
            let sent = pending.map { start in lastFinished.map { max($0, start) } ?? start }
            pending = nil
            open = (id, model, slot, sent, date, output)
        }

        mutating func finish() {
            guard let reply = open else { return }
            open = nil
            done.insert(reply.id)
            lastFinished = reply.finished
            guard let sent = reply.sent,
                  let timing = ReplyTiming(output: reply.output, from: sent, to: reply.finished) else { return }
            timings[reply.id] = timing
        }
    }

    /// Codex reports a running total for the session rather than a figure per
    /// turn, so each reading is differenced against the one before it. The
    /// running total only ever climbs, which makes the differences safe to add
    /// up — and it sidesteps the duplicate readings that summing Codex's own
    /// per-turn field would double-count.
    ///
    /// **A forked session opens with its parent's running total.** Codex
    /// Desktop's sub-agents start a new rollout (`session_meta.forked_from_id`)
    /// whose first reading is the parent's whole total so far, and whose first
    /// turn (`task_started` with a `rollout-N` id rather than a UUID) replays
    /// the parent's readings one by one. Differenced from zero, that copy was
    /// counted as the child's own work: on the Mac this was found on, 21 forks
    /// added 2.3 billion tokens of their parents' history, most of what Codex
    /// was said to have used. So a fork's first reading counts only its own
    /// request, its replayed turn counts nothing, and every counted reading is
    /// kept by the running total it brought the session to (`ScannedReply`) so
    /// `scan` counts a reading copied into another file once.
    private func parseCodex(_ lines: LogLines) -> Scanned {
        var scanned = Scanned()
        var days: [String: [String: TokenTally]] = [:]
        var replies: [String: ScannedReply] = [:]
        var runningTotals: [String] = []
        var model: String?
        var previous: [String: Int]?
        var clock = CodexReplyClock()
        var lastCountSlot: String?
        var forked = false
        var replaying = false
        // Which session a reading belongs to. A rollout with no header gets
        // one of its own, so it is never taken for another file's.
        var session = UUID().uuidString
        var headed = false

        lines.forEachLine { line in
            // The rollout's own header is its first; any later one is history.
            if !headed, contains(line, "\"session_meta\""),
               let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               root["type"] as? String == "session_meta",
               let payload = root["payload"] as? [String: Any] {
                headed = true
                if let id = payload["id"] as? String, !id.isEmpty { session = id }
                if let parent = payload["forked_from_id"] as? String, !parent.isEmpty { forked = true }
            }

            // A turn begins; in a fork, the one Codex calls `rollout-N` is the
            // parent's history played back.
            if contains(line, "\"task_started\""),
               let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let payload = root["payload"] as? [String: Any],
               payload["type"] as? String == "task_started" {
                let turn = payload["turn_id"] as? String ?? ""
                replaying = forked && turn.hasPrefix("rollout-")
                return
            }

            // What a reply's timing needs: when each request went out (a
            // tool's output, or the user's message) and when the model last
            // wrote. Cut out of the line, as Claude Code's are — a tool's
            // output can be long.
            if contains(line, "\"type\":\"response_item\""),
               let at = timestamp(in: line).flatMap(date(fromISO8601:)) {
                if contains(line, "_call_output\"") || contains(line, "\"role\":\"user\"") {
                    clock.sent(at: at)
                } else if Self.codexModelItems.contains(where: { contains(line, $0) }) {
                    clock.wrote(at: at)
                }
            }

            if (scanned.title == nil && !scanned.isReview) || scanned.cwd == nil {
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
                        if scanned.title == nil, !scanned.isReview,
                           payload["type"] as? String == "message",
                           payload["role"] as? String == "user" {
                            // A review session's first words are the review
                            // request: it is marked, and has no title.
                            if Self.isCodexReview(in: payload["content"]) {
                                scanned.isReview = true
                            } else if let title = Self.codexTitle(in: payload["content"]) {
                                scanned.title = title
                            }
                        }
                    }
                }
            }

            // Codex's own measure of the wait for the first token, once per
            // turn, put down to the model in force.
            if contains(line, "\"task_complete\""),
               let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let payload = root["payload"] as? [String: Any],
               payload["type"] as? String == "task_complete",
               let wait = (payload["time_to_first_token_ms"] as? NSNumber)?.doubleValue,
               let model {
                // Put with the turn's last count, so it lands in a quarter-hour
                // that has the turn's tokens — slots hold only work.
                let slot = lastCountSlot ?? (root["timestamp"] as? String).flatMap(slot(fromISO8601:))
                if let slot { clock.firstToken(after: wait / 1000, slot: slot, model: model) }
                return
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

            let current = codexCounts(totals)
            // A fork's first reading is its parent's total plus its own first
            // request; only the request is the fork's.
            if previous == nil, forked {
                let last = ((payload["info"] as? [String: Any])?["last_token_usage"] as? [String: Any])
                    .map(codexCounts) ?? [:]
                previous = current.merging(last) { total, own in max(total - own, 0) }
            }
            let delta = current.reduce(into: [String: Int]()) { result, entry in
                result[entry.key] = max(entry.value - (previous?[entry.key] ?? 0), 0)
            }
            previous = current
            guard !replaying else { return }

            // Codex counts cached tokens inside its input figure; the price
            // list treats them as two separate rates.
            let tally = TokenTally(
                input: max((delta["input"] ?? 0) - (delta["cached"] ?? 0), 0),
                cacheWrite: delta["cacheWrite"] ?? 0,
                cacheRead: delta["cached"] ?? 0,
                output: delta["output"] ?? 0
            )
            // A reading is one request, and its own input — cached part
            // included — is how full that request's context was.
            .request(context: int(((payload["info"] as? [String: Any])?["last_token_usage"] as? [String: Any])?["input_tokens"]))
            guard tally.total > 0 else { return }

            // The running total this reading brought the session to: a copy
            // of it in a fork's rollout is the parent's request.
            let total = [
                current["input"] ?? 0, current["cached"] ?? 0, current["output"] ?? 0, int(totals["total_tokens"])
            ].map(String.init).joined(separator: ":")
            // Only a fork's readings can be copies, so only a fork keeps them
            // one by one; any other session adds its readings up and keeps
            // just the totals they reached, for its forks to be checked against.
            if forked {
                let id = "codex:\(session):\(total)"
                guard replies[id] == nil else { return }
                replies[id] = ScannedReply(slot: slot, model: model, tally: tally, runningTotal: total, fromFork: true)
            } else {
                days[slot, default: [:]][model] = (days[slot]?[model] ?? TokenTally()) + tally
                runningTotals.append(total)
            }
            lastCountSlot = slot
            clock.counted(output: tally.output, slot: slot, model: model)
        }

        scanned.days = days
        scanned.replies = replies
        scanned.runningTotals = runningTotals
        scanned.timings = clock.timings
        return scanned
    }

    private func codexCounts(_ usage: [String: Any]) -> [String: Int] {
        [
            "input": int(usage["input_tokens"]),
            "cached": int(usage["cached_input_tokens"]),
            "cacheWrite": int(usage["cache_write_input_tokens"]),
            "output": int(usage["output_tokens"])
        ]
    }

    /// What the model writes in a Codex rollout, as opposed to what is
    /// handed to it. `"function_call"` with its closing quote is not
    /// `"function_call_output"`.
    private static let codexModelItems = [
        "\"role\":\"assistant\"", "\"type\":\"reasoning\"", "\"type\":\"function_call\"",
        "\"type\":\"custom_tool_call\"", "\"type\":\"web_search_call\"", "\"type\":\"local_shell_call\""
    ]

    /// Times Codex's replies: from the request to the model's last item.
    ///
    /// **The count arrives late.** Codex writes a reply's `token_count` once
    /// the tool it asked for has run, after that tool's output — which is
    /// also the next request going out. So a request closes the reply before
    /// it, and the count that follows is paired with that reply.
    private struct CodexReplyClock {
        private(set) var timings: [String: [String: ReplyTiming]] = [:]
        private var sent: Date?
        private var wrote: Date?
        private var closed: (sent: Date, finished: Date)?

        mutating func sent(at date: Date) {
            if let sent, let wrote, wrote > sent { closed = (sent, wrote) }
            sent = date
            wrote = nil
        }

        mutating func wrote(at date: Date) {
            if sent != nil { wrote = date }
        }

        mutating func firstToken(after seconds: Double, slot: String, model: String) {
            guard let timing = ReplyTiming.firstToken(after: seconds) else { return }
            timings[slot, default: [:]][model] = (timings[slot]?[model] ?? ReplyTiming()) + timing
        }

        mutating func counted(output: Int, slot: String, model: String) {
            var span = closed
            closed = nil
            if span == nil, let sent, let wrote, wrote > sent {
                span = (sent, wrote)
                self.sent = nil
                self.wrote = nil
            }
            guard let span, let timing = ReplyTiming(output: output, from: span.sent, to: span.finished) else { return }
            timings[slot, default: [:]][model] = (timings[slot]?[model] ?? ReplyTiming()) + timing
        }
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
        date(fromISO8601: text).map(slot(of:))
    }

    private func date(fromISO8601 text: String) -> Date? {
        isoWithFraction.date(from: text) ?? iso.date(from: text)
    }

    /// The first `"timestamp":"…"` value in a line, cut out without parsing
    /// the rest of it.
    private func timestamp(in line: Data) -> String? {
        let key = Data("\"timestamp\":\"".utf8)
        guard let start = line.range(of: key)?.upperBound,
              let end = line[start...].firstIndex(of: 0x22) else { return nil }
        return String(data: line[start..<end], encoding: .utf8)
    }

    private func slot(of date: Date) -> String {
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

        init(size: Int, modified: Double) {
            self.size = size
            self.modified = modified
        }

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
        /// Set for a Codex review session; `ledger-9` is what makes it present.
        var isReview: Bool?
        /// Optional for the same reason; `ledger-5` is what makes it present.
        var timings: [String: [String: ReplyTiming]]?
        /// Claude Code's replies and Codex's readings by id (`ScannedReply`),
        /// counted across files by `scan`; `ledger-6` is what makes it
        /// present, `ledger-7` what puts Codex in it.
        var replies: [String: UsageLedgerReader.ScannedReply]?
        /// `Scanned.runningTotals`; `ledger-7` is what makes it present.
        var runningTotals: [String]?

        /// A Codex rollout forked from another session (`ScannedReply.fromFork`).
        var isFork: Bool { replies?.values.contains { $0.fromFork == true } ?? false }

        /// The earliest quarter-hour with work in it.
        var firstSlot: String? {
            let day = days.keys.min()
            let reply = replies?.values.lazy.map(\.slot).min()
            if let day, let reply { return min(day, reply) }
            return day ?? reply
        }
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
        //
        // **`ledger-5`: Claude Code's output was short, and replies untimed.**
        // A reply written over several lines carries a running output count,
        // and the first line's was kept — about a quarter of the output went
        // uncounted. Entries also gained `timings`. Both need every file read
        // once more.
        //
        // **`ledger-6`: a reply counted once across files.** A resumed or
        // forked conversation's transcript opens with a copy of the old one's
        // history; entries now keep Claude Code's replies by id so `scan` can
        // drop the copies.
        //
        // **`ledger-7`: Codex forks counted their parents' history.** Codex
        // readings are now kept by running total and a fork's inherited
        // readings are dropped (`parseCodex`); Claude Code's cache writes now
        // keep their one-hour share (`TokenTally.cacheWrite1h`). Both need
        // every file read once more.
        //
        // **`ledger-8`: Codex titles were its injected context.** An entry's
        // title was the first user-role message, which for Codex is the
        // AGENTS.md instructions or the environment (`codexTitle(in:)`), and
        // a rollout that has not changed is never read again.
        //
        // **`ledger-9`: Codex review sessions are marked.** Entries gained
        // `isReview` (a session Codex ran to review another's action, which
        // has no words of the user's), and titles now unwrap links; a rollout
        // that has not changed is never read again.
        //
        // **No new number for the archive.** An entry holds what it held; a
        // deleted transcript's counted share moves to `TranscriptArchive`, a
        // file of its own. A new number would have thrown away this file —
        // the one record of every transcript deleted since the last scan,
        // which is what the archive is made from.
        //
        // **The number lives in `UsageLedgerReader.cacheVersion`**, where
        // `PulseStorage.isSuperseded` reads it: every `ledger-<n>-*` below it
        // is cleaned away without a name being added to a list.
        (directory ?? PulseStorage.directory).appending(path: "ledger-\(UsageLedgerReader.cacheVersion)-\(provider.rawValue).json")
    }
}
