// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// The Token spend pane: how far back it counts, which view of the year chart is
// open, and whether Pulse reads local records at all. None of these is the
// usage loop's business, so none goes through `onChange` — that hook refreshes
// the quota providers. Each is stored through a `store…`/`stored…` pair that
// takes the defaults as an argument, so the round trip can be pinned against an
// isolated suite.

extension AppSettings.Key {
    static let spendSpan = "settings.spendSpan"
    static let spendCustomDays = "settings.spendCustomDays"
    static let spendActivityView = "settings.spendActivityView"
    static let readsTokenSpend = "settings.readsTokenSpend"
    static let estimatesAllClaudeProducts = "settings.estimatesAllClaudeProducts"
}

extension AppSettings.Default {
    static let readsTokenSpend = false
    static let estimatesAllClaudeProducts = true
}

extension AppSettings {
    func spendSpanChanged(from old: SpendSpan) {
        guard spendSpan != old else { return }
        Self.storeSpendSpan(spendSpan, in: defaults)
        // The first time the custom range is chosen it starts at the last
        // seven days as of now, not as of whenever the settings were built.
        if spendSpan == .custom, Self.storedSpendCustomDays(in: defaults) == nil {
            spendCustomDays = Self.defaultSpendCustomDays()
        }
    }

    func spendCustomDaysChanged(from old: ClosedRange<Date>) {
        guard spendCustomDays != old else { return }
        Self.storeSpendCustomDays(spendCustomDays, in: defaults)
    }

    func spendActivityViewChanged(from old: ActivityView) {
        guard spendActivityView != old else { return }
        Self.storeSpendActivityView(spendActivityView, in: defaults)
    }

    func readsTokenSpendChanged(from old: Bool) {
        guard readsTokenSpend != old else { return }
        Self.storeReadsTokenSpend(readsTokenSpend, in: defaults)
    }

    func estimatesAllClaudeProductsChanged(from old: Bool) {
        guard estimatesAllClaudeProducts != old else { return }
        Self.storeEstimatesAllClaudeProducts(estimatesAllClaudeProducts, in: defaults)
    }

    /// The span last chosen, or `.week` when nothing is stored or what is
    /// stored no longer names an offered range.
    ///
    /// Takes the store as an argument, rather than reaching for
    /// `UserDefaults.standard`, so the round trip can be pinned against an
    /// isolated suite. `restored()` and `spendSpan`'s observer both go through
    /// this and `storeSpendSpan`, so what a test exercises is the one
    /// production uses.
    static func storedSpendSpan(in defaults: UserDefaults) -> SpendSpan {
        defaults.string(forKey: Key.spendSpan)
            .flatMap(SpendSpan.init(rawValue:)) ?? .default
    }

    static func storeSpendSpan(_ span: SpendSpan, in defaults: UserDefaults) {
        defaults.set(span.rawValue, forKey: Key.spendSpan)
    }

    /// The last seven days through today, the custom range's starting point.
    static func defaultSpendCustomDays(now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        return (calendar.date(byAdding: .day, value: -6, to: today) ?? today)...today
    }

    /// The reader's own first and last day, stored as two times since 1970.
    /// Anything else — missing, the wrong shape, a last day before the first
    /// — is the default rather than a range that cannot be drawn.
    static func storedSpendCustomDays(in defaults: UserDefaults) -> ClosedRange<Date>? {
        guard let stored = defaults.array(forKey: Key.spendCustomDays) as? [Double], stored.count == 2,
              stored.allSatisfy(\.isFinite), stored[0] <= stored[1]
        else { return nil }
        return Date(timeIntervalSince1970: stored[0])...Date(timeIntervalSince1970: stored[1])
    }

    static func storeSpendCustomDays(_ days: ClosedRange<Date>, in defaults: UserDefaults) {
        defaults.set([days.lowerBound.timeIntervalSince1970, days.upperBound.timeIntervalSince1970],
                     forKey: Key.spendCustomDays)
    }

    /// The key the chosen span lives under. Internal so a test can store a
    /// value the picker no longer offers and prove the fallback; nothing
    /// outside the module can see it either way.
    static var spendSpanDefaultsKey: String { Key.spendSpan }

    /// The chart view last chosen, or the daily grid when nothing is stored or
    /// what is stored is no longer offered. Takes the store as an argument so
    /// the round trip can be pinned against an isolated suite.
    static func storedSpendActivityView(in defaults: UserDefaults) -> ActivityView {
        defaults.string(forKey: Key.spendActivityView)
            .flatMap(ActivityView.init(rawValue:)) ?? .default
    }

    static func storeSpendActivityView(_ view: ActivityView, in defaults: UserDefaults) {
        defaults.set(view.rawValue, forKey: Key.spendActivityView)
    }

    static var spendActivityViewDefaultsKey: String { Key.spendActivityView }

    static func storedReadsTokenSpend(in defaults: UserDefaults) -> Bool {
        defaults.settingsFlag(Key.readsTokenSpend, default: Default.readsTokenSpend)
    }

    static func storeReadsTokenSpend(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: Key.readsTokenSpend)
    }

    static func storedEstimatesAllClaudeProducts(in defaults: UserDefaults) -> Bool {
        defaults.settingsFlag(Key.estimatesAllClaudeProducts, default: Default.estimatesAllClaudeProducts)
    }

    static func storeEstimatesAllClaudeProducts(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: Key.estimatesAllClaudeProducts)
    }
}
