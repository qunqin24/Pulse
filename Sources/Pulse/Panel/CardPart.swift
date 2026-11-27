// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// One thing an account's card can show beyond its limits, each switched on
/// or off per account in Settings → the account → Card contents.
///
/// **One list instead of five scattered switches.** The card's extras used to
/// hang off a global Forecast switch, a per-account Detailed card switch,
/// Copilot's and Qoder's amounts, and Codex's reset credits. They are all
/// here now; those settings still decide what an account shows until somebody
/// changes its list (`AppSettings.legacyCardParts`), so nothing moves on
/// upgrade.
enum CardPart: String, CaseIterable, Sendable {
    case plan
    case updated
    case forecast
    case value
    case amounts
    case figures
    case chart
    case topModel
    case cacheHitRate
    case promptCache
    case lastStep
    case resetCredits

    /// What the detailed card used to switch on all at once.
    static let detailed: Set<CardPart> = [
        .plan, .updated, .value, .figures, .chart, .topModel, .cacheHitRate, .promptCache, .lastStep,
    ]

    /// The parts drawn in the card's history section, which needs the
    /// account's ledger read (`UsageDetailCard.Spend`).
    static let history: Set<CardPart> = [.figures, .chart, .topModel, .cacheHitRate, .promptCache, .lastStep]

    /// The parts that make the card taller than its limits: the panel's
    /// frame is worked out before SwiftUI lays anything out, so any account
    /// showing one of these budgets the detailed height for all.
    static let tall: Set<CardPart> = detailed

    /// The parts this account can show at all — a switch for something that
    /// can never appear is worse than none.
    static func available(for account: AccountKey) -> [CardPart] {
        let provider = account.provider
        let history = account.isPrimary && provider.cardHistory != nil
        // Qoder's month comes from its own records, in credits: figures and
        // a chart, no models (`QoderCreditSection`, #88).
        let qoder = account == AccountKey(.qoder)
        return allCases.filter { part in
            switch part {
            case .plan, .updated, .forecast: true
            // Priced from this Mac's ledger, for the providers whose value
            // can be estimated (`UsageDetailCard.estimatesValue`).
            case .value: history && UsageDetailCard.estimatesValue(for: provider)
            case .amounts: provider == .copilot || provider == .qoder
            case .figures, .chart: history || qoder
            case .topModel, .cacheHitRate: history
            case .promptCache: history && PromptCacheReading.supports(provider)
            case .lastStep, .resetCredits: account == AccountKey(.codex)
            }
        }
    }

    var title: String {
        switch self {
        case .plan: .localized("Plan")
        case .updated: .localized("Update time")
        case .forecast: .localized("Forecast")
        case .value: .localized("Estimated value")
        case .amounts: .localized("Quota amounts")
        case .figures: .localized("Today, 7 days and 31 days")
        case .chart: .localized("31-day chart")
        case .topModel: .localized("Top model")
        case .cacheHitRate: .localized("Cache hit rate")
        case .promptCache: .localized("Prompt cache")
        case .lastStep: .localized("Last step's speed")
        case .resetCredits: .localized("Limit reset credits")
        }
    }
}
