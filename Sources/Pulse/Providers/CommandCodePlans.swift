import Foundation

/// What each Command Code subscription grants per month, in US dollars.
///
/// **This is a table in a client, and that is a compromise made with open
/// eyes.** Everywhere else Pulse refuses to draw a percentage it was not given
/// both halves of. Command Code reports the monthly grant's *remainder*
/// (`credits.monthlyCredits`) and never its size, so the only way to say how
/// much of a plan is gone is to know what the plan holds — and that number is
/// published on the pricing page rather than in any reply. Its own CLI carries
/// this same table for this same reason, and so does CodexBar.
///
/// The compromise is bounded in two ways, and both matter more than the table:
///
/// 1. **A plan this table cannot size draws no ring at all.** Not zero, not a
///    guess. A missing row is the failure this design actually has, and it is
///    silent — so it must not be able to render as an untouched allowance for
///    someone whose money is already gone. CodexBar's table is missing
///    `teams-pro` and `individual-provider` today, and that is exactly what
///    those subscribers see.
/// 2. **The row is labelled `estimated` on the card**, which is the same
///    treatment the money forecast gets: an inferred figure may be shown, but
///    never dressed as a reported one.
///
/// Everything else about this provider — the five-hour and weekly windows, the
/// organisation's spend limits, the balance — is reported outright and does not
/// pass through here.
///
/// **When prices change, this file is the thing that goes stale.** It is kept
/// apart from the service for that reason: there is one place to look.
/// Last checked against `command-code@1.51.3`, 2026-09-09.
enum CommandCodePlans {
    /// Plan id, exactly as `subscriptions.data.planId` and
    /// `credits.planId` report it, to the dollars it grants each month.
    static let monthlyCreditsUSD: [String: Double] = [
        "individual-go": 10,
        "individual-provider": 15,
        "individual-pro": 30,
        // Not a typo and not a duplicate: the same displayed name, "Pro", at
        // two very different allowances. The clearest evidence there is that a
        // table like this cannot be reasoned about from the plan's *name*.
        "individual-pro-v1": 80,
        "teams-pro": 40,
        "individual-goat": 70,
        "individual-max": 150,
        "individual-ultra": 300,
    ]

    /// The monthly grant for a plan id, or nil for one this build has never
    /// heard of — which is a plan added or renamed since it shipped.
    ///
    /// Matched on the whole id, lowercased. The CLI matches on a *prefix*,
    /// which would size a hypothetical `individual-pro-v2` as the $30
    /// `individual-pro`; being wrong by $50 is worse here than saying nothing.
    static func monthlyCredits(forPlan id: String?) -> Double? {
        guard let id else { return nil }
        let normalized = id.lowercased().replacingOccurrences(of: "_", with: "-")
        return monthlyCreditsUSD[normalized]
    }
}
