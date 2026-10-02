// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A ring for an account that reports money and no allowance.
///
/// DeepSeek was the first, and its three modes are the rule for every API
/// account since: the denominator is the highest balance Pulse **watched**
/// since it last rose, a figure the **reader typed**, or nothing — in which
/// case the rail shows the money itself. See `BalanceBasis` and
/// Docs/providers/deepseek.md. Nothing here is a provider's figure, which is
/// why every window it makes carries an `Estimate` naming where it came from.
enum BalanceRing {
    /// The one window a balance can have, or nil where the basis gives no
    /// denominator.
    ///
    /// **No length and no reset**, ever: prepaid money does not turn over, so
    /// `reportsLength` is false and the seconds only sort the row.
    /// `isExhausted` is the provider's own word where it has one — a budget
    /// set low can reach 100% with money still in the account.
    static func window(
        balance: Double,
        basis: BalanceBasis,
        budget: Double?,
        peak: Double,
        isExhausted: Bool
    ) -> UsageWindow? {
        let measured: (fraction: Double, estimate: UsageWindow.Estimate)? = switch basis {
        case .balanceOnly:
            nil
        case .sinceTopUp:
            DeepSeekBaseline.usedFraction(balance: balance, peak: peak).map { ($0, .sinceTopUp) }
        case .budget:
            // Finite, not merely positive: an infinite denominator makes the
            // fraction NaN, which the clamps propagate rather than catch.
            budget.flatMap { budget in
                budget.isFinite && budget > 0
                    ? (min(max((budget - balance) / budget, 0), 1), .yourBudget)
                    : nil
            }
        }
        guard let measured else { return nil }
        return UsageWindow(
            id: "balance",
            kind: .balance,
            scope: nil,
            usedFraction: measured.fraction,
            windowSeconds: 30 * 86_400,
            resetsAt: nil,
            reportsLength: false,
            estimate: measured.estimate,
            isExhausted: isExhausted
        )
    }

    /// A live reading of money and nothing else, with the ring its basis gives
    /// it — and the watched mark advanced on the way, whichever basis is in
    /// force, so switching to "since top-up" later finds a peak already there.
    ///
    /// Anything else is handed back as it came: a reading that already has
    /// limits of its own is the provider's figure and needs no denominator
    /// from anyone, and a failure has no balance to watch.
    @MainActor
    static func applying(
        basis: BalanceBasis,
        budget: Double?,
        to usage: ProviderUsage,
        baselines: BalanceBaselines = .shared,
        now: Date = Date()
    ) -> ProviderUsage {
        guard usage.state == .live, usage.windows.isEmpty, let money = usage.creditRemaining else { return usage }
        let mark = baselines.advance(account: usage.account, currency: money.currency, seeing: money.amount, at: now)
        // **Never spent on Pulse's say-so.** A balance at or below zero is
        // arithmetic, not the provider's word: Moonshot runs negative and
        // keeps working, and xAI's posted ledger can read zero mid-cycle with
        // credit left. Only a provider flag may call an account spent
        // (DeepSeek's `is_available`), and none reaches here, so a balance
        // ring rises to 99% and says no more — see `UsageAlerts.step`.
        guard let window = window(
            balance: money.amount, basis: basis, budget: budget, peak: mark.peak,
            isExhausted: false
        ) else { return usage }
        var ringed = usage
        ringed.windows = [window]
        return ringed
    }
}

/// The watched peaks behind "since top-up", for every API account but
/// DeepSeek, which keeps its own file from before there were others. One mark
/// per account and currency: a CNY peak is not a denominator for a USD balance.
@MainActor
final class BalanceBaselines {
    static let shared = BalanceBaselines(file: PulseStorage.directory.appending(path: "balance-baseline.json"))

    /// Nil keeps the marks in memory only, which is what a test wants.
    private let file: URL?
    private var marks: [String: DeepSeekBaseline.Mark]?

    init(file: URL?) {
        self.file = file
    }

    /// The mark after seeing `balance`: a first sight and a top-up set it,
    /// anything else leaves it. Written to disk only when it moved.
    func advance(account: AccountKey, currency: String, seeing balance: Double, at now: Date) -> DeepSeekBaseline.Mark {
        var all = marks ?? file.map(Self.load) ?? [:]
        let key = "\(account.id)|\(currency)"
        let mark = DeepSeekBaseline.advanced(all[key], seeing: balance, at: now)
        if all[key] != mark {
            all[key] = mark
            if let file { Self.store(all, to: file) }
        }
        marks = all
        return mark
    }

    private static let disk = DispatchQueue(label: "Pulse.balance-baseline", qos: .utility)

    private static func load(_ file: URL) -> [String: DeepSeekBaseline.Mark] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: DeepSeekBaseline.Mark].self, from: data)) ?? [:]
    }

    private static func store(_ marks: [String: DeepSeekBaseline.Mark], to destination: URL) {
        disk.async {
            PulseStorage.prepare()
            guard let data = try? JSONEncoder().encode(marks) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }
}
