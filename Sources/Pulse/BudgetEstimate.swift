import Foundation

/// What a rate-limit window is worth in money.
///
/// The providers publish a percentage and nothing else — they will tell you a
/// weekly limit is 3% gone, never what the other 97% is worth. But the two
/// halves of that answer are both here: they report the percentage, and the
/// local logs say what was actually spent in the same stretch of time. Divide
/// one by the other and the window has a price.
///
/// This is the one number in Pulse that is **inferred rather than reported**,
/// so it is labelled as an estimate wherever it appears, and it is withheld
/// rather than guessed when the inputs can't support it:
///
/// - Too little used, and the percentage's own rounding swamps the answer —
///   at 1% used, a provider reporting whole numbers could mean anywhere from
///   0.5% to 1.5%, a three-fold spread in the result.
/// - Logs that start after the window did miss part of the spending, which
///   would put the window's worth too low.
/// - Work done on another machine is invisible here, and pulls the same way.
///   Nothing can detect that, which is the honest limit of this figure.
struct BudgetEstimate: Sendable, Equatable {
    /// What the whole window is worth.
    let full: Double
    /// What is left of it.
    let remaining: Double
    /// What has already gone, by this Mac's reckoning.
    let spent: Double
}

enum BudgetEstimator {
    /// Below this the percentage is too coarse to divide by. The providers
    /// report whole numbers, so at 2% used the true figure is somewhere
    /// between 1.5% and 2.5% and the answer carries about a quarter either
    /// way — wide, but it is labelled an estimate and a quarter either way
    /// still tells you whether a window is worth ten dollars or a thousand.
    /// Below 2% it stops meaning anything at all.
    static let minimumUsed = 0.02
    /// And below this there isn't enough money in play to be worth reporting.
    static let minimumSpend = 0.20

    static func estimate(
        for window: UsageWindow,
        ledger: UsageLedger,
        now: Date = Date()
    ) -> BudgetEstimate? {
        guard
            window.windowSeconds > 0,
            let resets = window.resetsAt,
            // Account-wide windows only. A limit scoped to one model is spent
            // by that model alone, but the logs' spending for the period is
            // everything together — dividing one by the other priced Claude
            // Code's 2%-used Fable window at ten thousand dollars, because
            // almost all of the money in it had gone through Opus.
            window.scope == nil,
            window.usedFraction >= minimumUsed
        else { return nil }

        let opened = resets.addingTimeInterval(-Double(window.windowSeconds))
        guard opened < now else { return nil }

        // Logs that begin after the window did would only show part of the
        // spending, and the shortfall lands straight in the answer.
        guard let firstLogged = ledger.slots.first?.start, firstLogged <= opened else { return nil }

        let spent = ledger.spend(since: opened).cost
        guard spent >= minimumSpend else { return nil }

        let full = spent / window.usedFraction
        return BudgetEstimate(full: full, remaining: max(full - spent, 0), spent: spent)
    }
}
