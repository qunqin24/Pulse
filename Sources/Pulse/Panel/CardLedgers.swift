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
    case agents([SpendAgent])
    case accountStatistics

    /// Whether this Mac's records are read, which only Token spend allows.
    var readsThisMac: Bool { self != .accountStatistics }
}

extension Provider {
    var cardHistory: CardHistorySource? {
        if keepsLocalTranscripts { return .transcripts }
        if self == .zai || self == .glmCoding { return .accountStatistics }
        let agents = SpendAgent.allCases.filter { $0.iconProvider == self && $0.provider == nil }
        return agents.isEmpty ? nil : .agents(agents)
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
    @ObservationIgnored private var readAt: [Provider: Date] = [:]
    /// When each live session's prompt cache lapses, for the providers whose
    /// logs let it be timed (Claude Code, Codex). Read on every opening, not on `lifetime`: one
    /// new message moves it, and a countdown five minutes behind is wrong.
    private(set) var promptCache: [Provider: PromptCacheReading] = [:]

    /// Long enough that moving between rings does not rescan, short enough
    /// that "Today" is today's. The menu's tabs keep the same.
    static let lifetime: TimeInterval = 5 * 60

    /// What the card says for this provider: the last figures while a new read
    /// runs, so the section does not blank out and come back.
    func spend(for provider: Provider) -> UsageDetailCard.Spend {
        if let ledger = ledgers[provider] {
            return ledger.days.isEmpty ? .empty : .ledger(ledger)
        }
        if reading.contains(provider) { return .reading }
        return failed.contains(provider) ? .failed : .empty
    }

    /// Reads the provider's history unless it was read in the last few minutes.
    ///
    /// **Not tied to the card.** Started from a view task, a sweep down the
    /// rail cancels it at the next ring, and a cancelled read comes back empty
    /// — which would be stored as "no history". Run to the end instead; the
    /// readers' own caches make the next one cheap.
    func read(_ provider: Provider, from source: CardHistorySource) {
        let fresh = readAt[provider].map { Date().timeIntervalSince($0) < Self.lifetime } ?? false
        guard !fresh, !reading.contains(provider) else { return }
        reading.insert(provider)
        Task { [weak self] in
            let ledger = await Self.ledger(for: provider, from: source)
            guard let self else { return }
            if let ledger {
                self.ledgers[provider] = ledger
                self.failed.remove(provider)
            } else {
                self.failed.insert(provider)
            }
            self.readAt[provider] = Date()
            self.reading.remove(provider)
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

    /// Nil when the provider was asked and did not answer.
    private static func ledger(for provider: Provider, from source: CardHistorySource) async -> UsageLedger? {
        switch source {
        case .transcripts:
            return await UsageLedgerReader.shared.ledger(for: provider, refresh: true)
        case .agents(let agents):
            var ledgers: [UsageLedger] = []
            for agent in agents { ledgers.append(await AgentLedgers.shared.ledger(for: agent)) }
            return UsageLedger.adding(ledgers)
        case .accountStatistics:
            let read = await ZaiUsageService(provider: provider, enteredKey: APIKeyStore.key(for: provider)).history()
            switch read {
            case .answered(let ledger): return ledger
            case .notConfigured, .notAsked: return .empty
            case .failed: return nil
            }
        }
    }
}

extension UsageLedger {
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
