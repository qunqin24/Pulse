// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Where the detailed card's history for a provider comes from, if anywhere.
///
/// Three sources, and they are not interchangeable (`UsageLedger.Origin`):
/// the two CLIs' own transcripts, the other agents' records the Token spend
/// pane reads, and the statistics Z.ai and Zhipu publish for the whole
/// account. The first two are this Mac's alone and are read only with Token
/// spend on; the third is asked of the provider, as the account's settings
/// pane already does, and carries no money.
enum CardHistorySource: Equatable, Sendable {
    case transcripts
    /// Every agent that borrows this provider's mark. Antigravity is three
    /// (editor, IDE, CLI) and Devin two, added up.
    ///
    /// **One store can serve more than one provider.** A multi-provider agent
    /// (Oh My Pi) can route a request to this provider's account, and the
    /// record it writes says so; `slices` are those records as their own
    /// ledger, so the card's history covers work done through another tool,
    /// not only this provider's own clients.
    case agents([SpendAgent], slices: [AgentSlice] = [])
    case accountStatistics
    /// A console's own record of the account, read with the console sign-in
    /// kept in Settings — OpenCode's request log, DeepSeek's daily usage: the
    /// whole account, priced as charged.
    case accountLogs

    /// The records inside another agent's store that name this provider as
    /// their backend — a view of that store, never a second agent.
    struct AgentSlice: Equatable, Sendable {
        let agent: SpendAgent
        let provider: String
        /// The plan vendor a slice's models are bought through, where the
        /// agent carrying the store is not the vendor itself: omp's `devin`
        /// records are priced at Devin's rates, not omp's (there are none).
        /// Nil leaves the lookup at `agent.priceVendor`, as before.
        var vendor: String? = nil
    }

    /// Whether this Mac's records are read, which only Token spend allows.
    var readsThisMac: Bool { self != .accountStatistics && self != .accountLogs }
}

extension Provider {
    var cardHistory: CardHistorySource? {
        cardHistory(openCodeSession: OpenCodeConsole.hasSession, deepSeekSession: DeepSeekConsole.hasSession)
    }

    /// The rule, with whether each console's sign-in is kept passed in: those
    /// are this Mac's state, which a test must not depend on.
    func cardHistory(openCodeSession: Bool, deepSeekSession: Bool) -> CardHistorySource? {
        if keepsLocalTranscripts { return .transcripts }
        if self == .zai || self == .glmCoding { return .accountStatistics }
        // The console's log once its session is kept — every machine, and
        // what was charged — and this Mac's OpenCode records until then.
        if self == .openCodeGo, openCodeSession { return .accountLogs }
        // DeepSeek's console usage once its sign-in is kept. No local
        // records stand in before that: nothing on this Mac logs it.
        if self == .deepSeek, deepSeekSession { return .accountLogs }
        let agents = SpendAgent.allCases.filter { $0.iconProvider == self && $0.provider == nil }
        var slices: [CardHistorySource.AgentSlice] = []
        // Devin through Oh My Pi: the transcript names `devin` as its
        // provider (`omp --model devin/…`), so those records answer the card
        // even where neither Devin client is installed. A nil provider key
        // asks only for records the agent itself wrote.
        if self == .devin {
            slices.append(CardHistorySource.AgentSlice(agent: .omp, provider: "devin", vendor: "devin"))
        }
        return agents.isEmpty && slices.isEmpty ? nil : .agents(agents, slices: slices)
    }
}

/// The ledgers the detailed card shows, read when a card that shows one opens.
///
/// Kept for the session, and read again once `lifetime` has passed, so sweeping
/// the rail does not rescan a store — or ask a provider again — at every ring.
@MainActor
@Observable
final class CardLedgers {
    private(set) var ledgers: [Provider: UsageLedger] = [:]
    private(set) var reading: Set<Provider> = []
    /// Asked and not answered: the provider's statistics did not come back.
    private(set) var failed: Set<Provider> = []
    /// Asked, and the saved session was turned away.
    private(set) var signedOut: Set<Provider> = []
    @ObservationIgnored private var readAt: [Provider: Date] = [:]
    /// What each ledger was read from. A source that has changed since — a
    /// console session read or removed in Settings — is read again at once.
    @ObservationIgnored private var readFrom: [Provider: CardHistorySource] = [:]
    /// What else the ledger was read with, where the source alone does not
    /// say: DeepSeek's sign-in and the currency its money follows. A new
    /// sign-in, another account's, or another currency is read again at once.
    @ObservationIgnored private var readWith: [Provider: String] = [:]
    /// When each live session's prompt cache lapses, for the providers whose
    /// logs let it be timed (Claude Code, Codex). Read on every opening, not on `lifetime`: one
    /// new message moves it, and a countdown five minutes behind is wrong.
    private(set) var promptCache: [Provider: PromptCacheReading] = [:]

    /// Long enough that moving between rings does not rescan, short enough
    /// that "Today" is today's. The menu's tabs keep the same.
    static let lifetime: TimeInterval = 5 * 60

    /// Qoder's last 31 days from the account's own records (issue #88), or
    /// nil: not asked, not answered, or answered with less than the whole month.
    private(set) var qoderCredits: QoderCreditDays?
    @ObservationIgnored private var qoderReadAt: Date?
    @ObservationIgnored private var qoderReadWith: String?
    @ObservationIgnored private var readingQoder = false

    /// Asks Qoder for the month when the detailed card opens, at most once a `lifetime`
    /// for the same session and site — never on the refresh timer, so the
    /// records are requested only when somebody is looking at them. Another
    /// session or site drops the figures at once: they were another account's.
    func readQoderCredits(cookie: String, site: QoderSite) {
        let with = "\(site.rawValue)|\(cookie.hashValue)"
        if qoderReadWith != with {
            // Recorded now, not when a read starts: a read still out for the
            // old session must find it changed and drop what it brings back.
            qoderCredits = nil
            qoderReadAt = nil
            qoderReadWith = with
        }
        let fresh = qoderReadAt.map { Date().timeIntervalSince($0) < Self.lifetime } ?? false
        guard !fresh, !readingQoder else { return }
        readingQoder = true
        Task { [weak self] in
            let credits = await QoderClient().fetchCreditDays(cookie: cookie, site: site)
            guard let self, self.qoderReadWith == with else {
                self?.readingQoder = false
                return
            }
            self.qoderCredits = credits
            self.qoderReadAt = Date()
            self.readingQoder = false
        }
    }

    /// What the card says for this provider: the last figures while a new read
    /// runs, so the section does not blank out and come back.
    func spend(for provider: Provider) -> UsageDetailCard.Spend {
        if let ledger = ledgers[provider] {
            return ledger.days.isEmpty ? .empty : .ledger(ledger)
        }
        if reading.contains(provider) { return .reading }
        if signedOut.contains(provider) { return .signedOut }
        return failed.contains(provider) ? .failed : .empty
    }

    /// Reads the provider's history unless it was read in the last few minutes.
    ///
    /// **Not tied to the card.** Started from a view task, a sweep down the
    /// rail cancels it at the next ring, and a cancelled read comes back empty
    /// — which would be stored as "no history". Run to the end instead; the
    /// readers' own caches make the next one cheap.
    func read(_ provider: Provider, from source: CardHistorySource) {
        let with = Self.inputs(for: provider)
        let fresh = readFrom[provider] == source && readWith[provider] == with
            && (readAt[provider].map { Date().timeIntervalSince($0) < Self.lifetime } ?? false)
        guard !fresh, !reading.contains(provider) else { return }
        if readFrom[provider] != source || readWith[provider] != with {
            // Another source's figures are not this one's to stand in for.
            ledgers[provider] = nil
            failed.remove(provider)
            signedOut.remove(provider)
        }
        reading.insert(provider)
        readFrom[provider] = source
        readWith[provider] = with
        Task { [weak self] in
            let outcome = await Self.ledger(for: provider, from: source)
            guard let self else { return }
            // **Signed in to another account while this was out.** The answer
            // is the old account's; it is dropped, and the account now kept
            // is read instead of being shown the other one's history.
            guard Self.inputs(for: provider) == with else {
                self.reading.remove(provider)
                self.readWith[provider] = nil
                self.ledgers[provider] = nil
                if let current = provider.cardHistory { self.read(provider, from: current) }
                return
            }
            switch outcome {
            case .answered(let ledger):
                self.ledgers[provider] = ledger
                self.failed.remove(provider)
                self.signedOut.remove(provider)
            case .signedOut:
                self.ledgers[provider] = nil
                self.signedOut.insert(provider)
            case .failed:
                self.failed.insert(provider)
            }
            self.readAt[provider] = Date()
            self.reading.remove(provider)
        }
    }

    /// Which login, and which currency, a console's ledger was read with.
    /// Hashed, in memory only, so a change can be noticed without the secret
    /// being kept a second time.
    ///
    /// **OpenCode's sign-in counts too.** Only DeepSeek's did, so reading a
    /// second OpenCode workspace's session in Settings left the card on the
    /// first workspace's history for as long as `lifetime` held it fresh.
    private static func inputs(for provider: Provider) -> String {
        switch provider {
        case .deepSeek:
            let token = DeepSeekConsole.keptToken.map { String($0.hashValue) } ?? ""
            return "\(token)|\(AppSettings.storedDeepSeekCurrency ?? "")"
        case .openCodeGo:
            return APIKeyStore.key(for: provider, slot: OpenCodeConsole.slot).map { String($0.hashValue) } ?? ""
        default:
            return ""
        }
    }

    /// The latest session's cache, read off the main thread: a directory
    /// listing and the tail of one file, cheap enough for every card opening.
    func readPromptCache(_ provider: Provider) {
        guard PromptCacheReading.supports(provider) else { return }
        Task { [weak self] in
            let reading = await Task.detached(priority: .utility) { PromptCacheReading.read(for: provider) }.value
            self?.promptCache[provider] = reading
        }
    }

    private static func ledger(for provider: Provider, from source: CardHistorySource) async -> OpenCodeConsole.Read {
        switch source {
        case .transcripts:
            return .answered(await UsageLedgerReader.shared.ledger(for: provider, refresh: true))
        case .agents(let agents, let slices):
            return .answered(await UsageLedger.reading(agents, slices: slices))
        case .accountStatistics:
            let read = await ZaiUsageService(provider: provider, enteredKey: APIKeyStore.key(for: provider)).history()
            switch read {
            case .answered(let ledger): return .answered(ledger)
            case .notConfigured, .notAsked: return .answered(.empty)
            case .failed: return .failed
            }
        case .accountLogs where provider == .deepSeek:
            guard let token = DeepSeekConsole.keptToken else { return .signedOut }
            return await DeepSeekConsoleHistory.shared.ledger(token: token, currency: AppSettings.storedDeepSeekCurrency)
        case .accountLogs:
            guard let cookie = APIKeyStore.key(for: provider, slot: OpenCodeConsole.slot) else { return .signedOut }
            return await OpenCodeConsoleHistory.shared.ledger(cookie: cookie)
        }
    }
}

extension UsageLedger {
    /// Every agent that borrows a provider's mark, read and added up: the
    /// card's history for that provider and its settings pane's, read the
    /// same way so the two cannot disagree.
    static func reading(_ agents: [SpendAgent], slices: [CardHistorySource.AgentSlice] = []) async -> UsageLedger {
        var ledgers: [UsageLedger] = []
        for agent in agents { ledgers.append(await AgentLedgers.shared.ledger(for: agent)) }
        for slice in slices {
            ledgers.append(await AgentLedgers.shared.ledger(
                for: slice.agent, provider: slice.provider, vendor: slice.vendor
            ))
        }
        var combined = adding(ledgers)
        combined.reportsCacheReads = agents.contains { $0.reportsCacheReads }
            || slices.contains { $0.agent.reportsCacheReads }
        return combined
    }

    /// Several agents' ledgers as one, day by day — what the card needs of
    /// them and no more: tokens, money, token kinds and models per day, the
    /// models' names, and the quarter-hours the value estimate reads. The finer detail
    /// (sessions, token kinds) is left behind, because nothing on the card
    /// reads it.
    static func adding(_ ledgers: [UsageLedger]) -> UsageLedger {
        let present = ledgers.filter { !$0.days.isEmpty }
        guard present.count > 1 else { return present.first ?? .empty }

        var tokens: [Date: Int] = [:]
        var cost: [Date: Double] = [:]
        var unpriced: [Date: Int] = [:]
        var models: [Date: [String: Int]] = [:]
        var tallies: [Date: TokenTally] = [:]
        for day in present.flatMap(\.days) {
            tallies[day.date, default: TokenTally()] = (tallies[day.date] ?? TokenTally()) + day.tally
            tokens[day.date, default: 0] += day.tokens
            cost[day.date, default: 0] += day.cost
            unpriced[day.date, default: 0] += day.unpricedTokens
            models[day.date, default: [:]].merge(day.models, uniquingKeysWith: +)
        }
        // Calendar order, gaps closed, as a single reader's ledger has them —
        // `recent(_:)` counts days, not dates.
        let calendar = Calendar.current
        guard let first = tokens.keys.min(), let last = tokens.keys.max() else { return .empty }
        var days: [LedgerDay] = []
        var date = first
        while date <= last {
            var day = LedgerDay(
                date: date, tokens: tokens[date] ?? 0, cost: cost[date] ?? 0,
                unpricedTokens: unpriced[date] ?? 0, models: models[date] ?? [:]
            )
            day.tally = tallies[date] ?? TokenTally()
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        var ledger = UsageLedger(
            days: days,
            earliest: present.compactMap(\.earliest).min(),
            unpricedModels: Array(Set(present.flatMap(\.unpricedModels))).sorted(),
            modelNames: present.reduce(into: [:]) { $0.merge($1.modelNames) { first, _ in first } },
            slots: present.flatMap(\.slots).sorted { $0.start < $1.start }
        )
        ledger.origin = present.contains { $0.origin == .importedRecords } ? .importedRecords : .localTranscripts
        // One agent that cannot vouch for its counts leaves the sum unvouched.
        ledger.hasPartialCounts = present.contains(where: \.hasPartialCounts)
        return ledger
    }
}
