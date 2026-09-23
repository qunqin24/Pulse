import Foundation

/// Every agent's spending added up, which is a different question from any one
/// agent's.
///
/// `AccountUsageCard` answers "how heavily am I using *this*" — one provider,
/// one ring's worth of history, opened from that provider's own pane. Nothing
/// answered "how much have I spent on coding agents", because that figure does
/// not belong to any provider and there was nowhere to put it. This is that
/// figure, and the split underneath it.
///
/// **It reuses the ledgers rather than rescanning.** `UsageLedgerReader` already
/// holds one per provider, priced from the same `ModelPrices` table; adding
/// them up is arithmetic over what is already in memory, not another pass over
/// a few hundred megabytes of transcripts.
///
/// **Only the agents that keep local transcripts can be in it.** A provider's
/// own statistics (Z.ai, Zhipu) report one token total per model and no money,
/// and folding those into a combined cost would put a figure on the total that
/// half of it cannot carry — so `Provider.keepsLocalTranscripts` is the gate,
/// not `providesHistory`.
struct SpendSummary: Equatable, Sendable {
    /// One agent's share of the total.
    struct Agent: Identifiable, Equatable, Sendable {
        let agent: SpendAgent
        let tokens: Int
        let cost: Double
        /// Tokens spent on models with no published price. Counted, not costed.
        let unpricedTokens: Int

        var id: SpendAgent { agent }
    }

    /// One model's share, across every agent that used it.
    ///
    /// **Tokens only, and deliberately.** The ledger keeps money per *day* and
    /// tokens per *model*; there is no per-model cost to add up, and working
    /// one out from a day's blended rate would be inventing it. The share is
    /// of tokens and the column says so.
    struct Model: Identifiable, Equatable, Sendable {
        /// The name the provider publishes, where models.dev has one.
        let name: String
        let tokens: Int
        /// Which agents sent work to it. One model can belong to two.
        let agents: [SpendAgent]

        var id: String { name }

        var share: Double = 0
    }

    /// One day, with every agent's work in it — the chart's bars, and the
    /// table's rows.
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let tokens: Int
        let cost: Double
        /// The day split by kind of token, summed across agents. Nothing here
        /// is recomputed: the ledger already carries it per day.
        var tally = TokenTally()
        /// Tokens that day with no price behind them, summed across agents.
        /// Carried so a row can show a dash rather than `$0` for work Pulse
        /// could not price, and so the figure is never silently priced at zero.
        var unpricedTokens: Int = 0

        var id: Date { date }
    }

    /// One transcript, with the agent that wrote it.
    struct Session: Identifiable, Equatable, Sendable {
        let agent: SpendAgent
        let session: UsageLedger.Session

        var id: String { session.id }
    }

    /// One identified project, across every session in the selected span.
    struct Project: Identifiable, Equatable, Sendable {
        struct ID: Hashable, Sendable {
            let identity: UsageProject.Identity
            // A label alone cannot prove that two agents mean the same project.
            let agent: SpendAgent?

            init(_ project: UsageProject, agent: SpendAgent) {
                identity = project.identity
                if case .label = project.identity { self.agent = agent }
                else { self.agent = nil }
            }
        }

        let id: ID
        let name: String
        let tokens: Int
        let cost: Double
        let sessions: Int
        let lastUsed: Date
    }

    func projectName(for row: Session) -> String? {
        guard let project = row.session.project else { return nil }
        let id = Project.ID(project, agent: row.agent)
        return projects.first { $0.id == id }?.name ?? project.name
    }

    var tokens = 0
    var cost = 0.0
    /// The whole span split by kind of token. Fresh input, cache written,
    /// cache read and output are priced an order of magnitude apart, so "four
    /// billion tokens" says much less than this does.
    var tally = TokenTally()
    var unpricedTokens = 0
    var agents: [Agent] = []
    var models: [Model] = []
    var days: [Day] = []
    /// Newest first.
    var sessions: [Session] = []
    /// Heaviest first.
    var projects: [Project] = []
    /// Models seen in the logs that models.dev has no price for, named so the
    /// footnote can say which.
    var unpricedModels: [String] = []

    /// Whether any contributing ledger had only session- or report-level
    /// timing for some of its work, so the hour figure must not be drawn.
    var hasAggregateTiming = false

    /// Whether any contributing ledger's counts may be missing. When set, the
    /// total is a floor rather than a whole: the UI says "partial" instead of
    /// quietly under-reporting. It adds no tokens and changes no price.
    var hasPartialCounts = false

    var isEmpty: Bool { tokens == 0 && cost == 0 }

    /// The heaviest day in the span, across every agent — which is not the
    /// same day as any one agent's heaviest.
    var busiestDay: Day? { days.max { $0.tokens < $1.tokens } }

    /// Days with anything on them. A span is drawn with its gaps so the chart
    /// reads as a calendar, but "you used it on 14 days" is about the work.
    var activeDays: Int { days.count { $0.tokens > 0 } }

    /// Tokens by calendar month, newest last.
    var months: [Day] = []

    /// Tokens by hour of the local day, 0–23. Built from the ledger's
    /// quarter-hour buckets, which is the only place the time of day survives:
    /// a `LedgerDay` has already thrown it away.
    var hours: [Int: Int] = [:]

    /// Hours with anything in them, for the day-long span where "how many of
    /// the seven days" is a question about one day.
    var activeHours: Int { hours.count { $0.value > 0 } }

    /// The hour with the most tokens in it. Nil where nothing was recorded, so
    /// an empty span does not report a busy midnight.
    var peakHour: Int? {
        hours.max { $0.value < $1.value }.map(\.key)
    }

    /// The run of days with work on them ending at the most recent day, and
    /// the longest such run anywhere in the span.
    ///
    /// **Counted back from the end of the series, not from today.** The series
    /// runs to today, so a streak that ended yesterday is correctly zero — but
    /// the same code over a ledger that stops earlier would otherwise report a
    /// streak that ended weeks ago as current.
    var currentStreak: Int {
        var run = 0
        for day in days.reversed() {
            guard day.tokens > 0 else { break }
            run += 1
        }
        return run
    }

    var longestStreak: Int {
        var best = 0
        var run = 0
        for day in days {
            run = day.tokens > 0 ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// The day rows, in the order a column asks for.
    ///
    /// **Sorting is data, not layout**, so it lives here rather than on the
    /// view: it is the same question asked of the same rows whoever is asking,
    /// and a `View` is isolated to the main actor for reasons that have nothing
    /// to do with ordering a list.
    static func sorted(
        _ days: [Day],
        by column: DayColumn,
        ascending: Bool
    ) -> [Day] {
        let ordered = days.sorted { lhs, rhs in
            switch column {
            case .date: lhs.date < rhs.date
            case .input: lhs.tally.input < rhs.tally.input
            case .output: lhs.tally.output < rhs.tally.output
            case .cacheRead: lhs.tally.cacheRead < rhs.tally.cacheRead
            case .cacheWrite: lhs.tally.cacheWrite < rhs.tally.cacheWrite
            case .total: lhs.tokens < rhs.tokens
            case .cost: lhs.cost < rhs.cost
            }
        }
        return ascending ? ordered : ordered.reversed()
    }

    /// The part of a session that falls inside the span, or nil where none
    /// does.
    ///
    /// This is the whole reason a session carries its own buckets. A session
    /// whose work straddles the cutoff contributes only its in-span
    /// quarter-hours, so a project's money and the span's own total are the
    /// same sum — never the whole conversation, and never a share of it
    /// worked out from a ratio.
    ///
    /// Calendar-day buckets also preserve the span when a report has no exact
    /// hour. They are used only when quarter-hour buckets are unavailable.
    /// A session with neither kind of bucket is one read before the ledger kept them:
    /// it falls back to being counted whole when it ended inside the span,
    /// which is the old rule and never a silent zero.
    private static func window(
        _ session: UsageLedger.Session,
        cutoff: Date?
    ) -> (tokens: Int, cost: Double, last: Date)? {
        guard let cutoff else { return (session.tokens, session.cost, session.end) }

        guard !session.slots.isEmpty else {
            if !session.days.isEmpty {
                let days = session.days.filter { $0.date >= cutoff }
                guard let last = days.map(\.date).max() else { return nil }
                return (days.reduce(0) { $0 + $1.tokens }, days.reduce(0.0) { $0 + $1.cost }, last)
            }
            return session.end >= cutoff ? (session.tokens, session.cost, session.end) : nil
        }

        var tokens = 0
        var cost = 0.0
        var last = cutoff
        var found = false
        for slot in session.slots where slot.start >= cutoff {
            found = true
            tokens += slot.tokens
            cost += slot.cost
            last = max(last, slot.start)
        }
        return found ? (tokens, cost, last) : nil
    }

    /// Adds the ledgers up over the last `span` days, or over everything when
    /// `span` is nil.
    ///
    /// Dates are the ledgers' own day keys, which are already local midnights,
    /// so two agents' work on one day lands on one bar without any rounding
    /// here.
    ///
    /// **The span is a window on the calendar, not each ledger's last N
    /// entries.** Taking the suffix of every ledger looks equivalent and is
    /// not: an agent last used a fortnight ago contributes its *own* last
    /// seven recorded days, and "the last 7 days" then drew nine bars. The
    /// cutoff is a date, and the series is padded out to the whole window so a
    /// day nobody worked is a gap in a calendar rather than a missing column.
    static func of(
        _ ledgers: [SpendAgent: UsageLedger],
        overLast span: Int?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SpendSummary {
        var summary = SpendSummary()

        let today = calendar.startOfDay(for: now)
        let cutoff = span.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: today) }

        var dayTokens: [Date: Int] = [:]
        var dayCost: [Date: Double] = [:]
        var dayTally: [Date: TokenTally] = [:]
        var dayUnpriced: [Date: Int] = [:]
        var hourTokens: [Int: Int] = [:]
        var tally = TokenTally()
        var modelTokens: [String: Int] = [:]
        var modelAgents: [String: Set<SpendAgent>] = [:]
        var unpriced: Set<String> = []
        var projectTokens: [Project.ID: Int] = [:]
        var projectCost: [Project.ID: Double] = [:]
        var projectSessions: [Project.ID: Int] = [:]
        var projectLastUsed: [Project.ID: Date] = [:]
        var projectMetadata: [Project.ID: UsageProject] = [:]
        var hasAggregate = false
        var hasPartial = false

        for (agent, ledger) in ledgers {
            // A ledger that cannot be priced has no place in a combined cost.
            // Local records and imported ones can be; a provider's own
            // statistics carry one total per model and no money.
            guard ledger.origin.supportsTokenSpend else { continue }

            let window = cutoff.map { start in ledger.days.filter { $0.date >= start } } ?? ledger.days
            guard !window.isEmpty else { continue }

            var agentTokens = 0
            var agentCost = 0.0
            var agentUnpriced = 0

            for day in window {
                agentTokens += day.tokens
                agentCost += day.cost
                agentUnpriced += day.unpricedTokens
                tally = tally + day.tally

                dayTokens[day.date, default: 0] += day.tokens
                dayCost[day.date, default: 0] += day.cost
                dayUnpriced[day.date, default: 0] += day.unpricedTokens
                dayTally[day.date] = (dayTally[day.date] ?? TokenTally()) + day.tally

                for (model, tokens) in day.models {
                    let name = ledger.modelNames[model] ?? model
                    modelTokens[name, default: 0] += tokens
                    modelAgents[name, default: []].insert(agent)
                }
            }

            // The time of day, which only the quarter-hour buckets carry.
            // Bucketed by the hour their start falls in: a bucket never
            // straddles one.
            for slot in ledger.slots where cutoff.map({ slot.start >= $0 }) ?? true {
                guard slot.tokens > 0 else { continue }
                hourTokens[calendar.component(.hour, from: slot.start), default: 0] += slot.tokens
            }

            // **A session is counted by the part of it that falls in the
            // span, not by when it ended.** A conversation that ran past
            // midnight, or was resumed over days, used to be added whole to
            // whichever day it finished on — so a project could report
            // yesterday's $9 under today's $1. Its own quarter-hour buckets
            // are what make the window exact, and they are priced, so the
            // money is a sum rather than a proportion guessed from the total.
            for session in ledger.sessions {
                guard let windowed = Self.window(session, cutoff: cutoff) else { continue }

                // The row carries the span's portion, so the list and the
                // totals above it are the same arithmetic. Its `start` and
                // `end` stay the conversation's own, which is when it ran.
                summary.sessions.append(
                    Session(
                        agent: agent,
                        session: UsageLedger.Session(
                            id: session.id, name: session.name, title: session.title,
                            project: session.project, start: session.start, end: session.end,
                            tokens: windowed.tokens, cost: windowed.cost, slots: session.slots, days: session.days
                        )
                    )
                )

                guard let metadata = session.project else { continue }
                let project = Project.ID(metadata, agent: agent)
                projectMetadata[project] = metadata
                projectTokens[project, default: 0] += windowed.tokens
                projectCost[project, default: 0] += windowed.cost
                projectSessions[project, default: 0] += 1
                projectLastUsed[project] = max(projectLastUsed[project] ?? windowed.last, windowed.last)
            }

            guard agentTokens > 0 || agentCost > 0 else { continue }

            // A ledger that contributed and had aggregate timing taints the
            // hour figure for the whole scope; a ledger that contributed
            // nothing does not. The same rule marks the total partial.
            if ledger.hasAggregateTiming { hasAggregate = true }
            if ledger.hasPartialCounts { hasPartial = true }

            summary.agents.append(
                Agent(agent: agent, tokens: agentTokens, cost: agentCost, unpricedTokens: agentUnpriced)
            )
            summary.tokens += agentTokens
            summary.cost += agentCost
            summary.unpricedTokens += agentUnpriced
            unpriced.formUnion(ledger.unpricedModels)
        }

        // Heaviest first: the list is read to find where the work went, and an
        // alphabetical one makes that a search.
        summary.agents.sort { $0.tokens > $1.tokens }

        let overall = modelTokens.values.reduce(0, +)
        summary.models = modelTokens
            .map { name, tokens in
                Model(
                    name: name,
                    tokens: tokens,
                    // Sorted so a row's agents do not shuffle between reads.
                    agents: (modelAgents[name] ?? []).sorted { $0.displayName < $1.displayName },
                    share: overall > 0 ? Double(tokens) / Double(overall) : 0
                )
            }
            .sorted { $0.tokens > $1.tokens }

        // Every day in the window, including the empty ones: a chart whose
        // bars are only the days with work on them compresses a quiet
        // fortnight into nothing and reads as a busy one.
        let first = cutoff ?? dayTokens.keys.min() ?? today
        let last = max(today, dayTokens.keys.max() ?? today)
        var cursor = min(first, last)
        while cursor <= last {
            summary.days.append(
                Day(
                    date: cursor,
                    tokens: dayTokens[cursor] ?? 0,
                    cost: dayCost[cursor] ?? 0,
                    tally: dayTally[cursor] ?? TokenTally(),
                    unpricedTokens: dayUnpriced[cursor] ?? 0
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        // Months are rolled up from the padded day series, so a month with no
        // work in it is still a row rather than a hole in the sequence.
        var monthTokens: [Date: Int] = [:]
        var monthCost: [Date: Double] = [:]
        var monthUnpriced: [Date: Int] = [:]
        for day in summary.days {
            guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: day.date))
            else { continue }
            monthTokens[month, default: 0] += day.tokens
            monthCost[month, default: 0] += day.cost
            monthUnpriced[month, default: 0] += day.unpricedTokens
        }
        summary.months = monthTokens
            .map {
                Day(
                    date: $0.key, tokens: $0.value, cost: monthCost[$0.key] ?? 0,
                    unpricedTokens: monthUnpriced[$0.key] ?? 0
                )
            }
            .sorted { $0.date < $1.date }

        summary.sessions.sort { $0.session.end > $1.session.end }
        let knownProjects = Set(projectMetadata.values)
        summary.projects = projectTokens
            .map { id, tokens in
                let metadata = projectMetadata[id]!
                var name = UsageProject.displayName(for: metadata, among: knownProjects)
                if let agent = id.agent, projectMetadata.keys.contains(where: { $0 != id && projectMetadata[$0]?.name == name }) {
                    name += " · " + agent.displayName
                }
                return Project(
                    id: id, name: name,
                    tokens: tokens,
                    cost: projectCost[id] ?? 0,
                    sessions: projectSessions[id] ?? 0,
                    lastUsed: projectLastUsed[id] ?? .distantPast
                )
            }
            .sorted { $0.tokens > $1.tokens }

        summary.tally = tally
        summary.hours = hourTokens
        summary.unpricedModels = unpriced.sorted()
        summary.hasAggregateTiming = hasAggregate
        summary.hasPartialCounts = hasPartial

        return summary
    }
}
