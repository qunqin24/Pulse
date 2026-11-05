// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

/// What is typed into an account's connection and notification rows apart from
/// the credential: a self-hosted gateway's address, what the reader calls a
/// full balance, and the figure to warn below. Each is held as text and
/// committed on Save, so a half-entered value is never read as a setting.
@MainActor
@Observable
final class AccountEntryFields {
    private let store: UsageStore
    private let settings: AppSettings
    private let alerts: UsageAlerts

    init(store: UsageStore, settings: AppSettings, alerts: UsageAlerts) {
        self.store = store
        self.settings = settings
        self.alerts = alerts
    }

    /// The budget being typed, kept as text so a half-entered number is not
    /// read as a denominator on every keystroke.
    var balanceBudgetText = ""
    /// A self-hosted gateway's address being typed, committed on Save rather
    /// than on every keystroke — a half-typed host is a request nobody meant
    /// to make.
    var serverAddress = ""
    var serverAddressInvalid = false
    /// The low-balance figure being typed, kept as text for the same reason.
    var lowBalance = ""

    /// The pane opened, or its account or its switch changed: the stored
    /// figures are what the fields show.
    func seed(for account: AccountKey) {
        let shown = account.provider
        // The stored figure, shown in the field rather than left blank
        // beside a ring that is measuring against it.
        if hasBalanceRing(account) {
            balanceBudgetText = Self.text(settings.balanceBudget(for: account))
        }
        if shown.usesServerAddress {
            serverAddress = settings.serverAddress(for: account)
            serverAddressInvalid = false
        }
        if reportsBalance(account) {
            lowBalance = settings.lowBalanceAlert(for: account).map { String($0) } ?? ""
        }
    }

    /// Whether this account's ring is a balance's, with a basis to choose: an
    /// API account that reports money — and whose reading is money, not
    /// limits of its own. A sub2api group reports quota windows, which are the
    /// provider's figures; a basis picker beside them would change nothing,
    /// and a control that does nothing is worse than none. See `BalanceRing`.
    func hasBalanceRing(_ account: AccountKey) -> Bool {
        let takesRing = account.provider == .pulseExtension || account.provider == .xiaomiMiMo
            || account.provider.billing == .api
        guard takesRing, reportsBalance(account) else { return false }
        return store.usage(for: account).windows.allSatisfy { $0.estimate == .sinceTopUp || $0.estimate == .yourBudget }
    }

    /// Money in the account, spent by the call. A built-in provider's primary
    /// account says so by being that kind of provider. An extension says so
    /// by printing a balance, so it is asked of its reading instead: one that
    /// reports limits only has nothing a "warn below" figure could compare.
    func reportsBalance(_ account: AccountKey) -> Bool {
        if account.provider == .pulseExtension { return store.usage(for: account).creditRemaining != nil }
        // Xiaomi by its reading too: a pay-as-you-go account's balance is the
        // reading, while beside a Coding Plan it is only a line on the card.
        if account.provider == .xiaomiMiMo {
            return account.isPrimary && store.usage(for: account).creditRemaining != nil
        }
        return account.isPrimary && account.provider.reportsSpendableBalance
    }

    /// Blank clears it, which puts the pane back to asking for an address
    /// rather than leaving a ring pointed at a server that is no longer there.
    func saveServerAddress(for account: AccountKey) {
        let typed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            serverAddressInvalid = false
            serverAddress = ""
            settings.setServerAddress("", for: account)
            store.refresh(account)
            return
        }
        // The shared rule, not a provider's own: what makes an address usable
        // is the same question for both gateways, and only the route after it
        // differs.
        guard GatewayAddress.isUsable(typed) else {
            serverAddressInvalid = true
            return
        }
        serverAddressInvalid = false
        serverAddress = typed
        settings.setServerAddress(typed, for: account)
        store.refresh(account)
    }

    /// Blank clears it, which puts the ring back to showing the balance alone
    /// rather than a fraction of nothing.
    func saveBalanceBudget(for account: AccountKey) {
        settings.setBalanceBudget(Self.money(balanceBudgetText), for: account)
        balanceBudgetText = Self.text(settings.balanceBudget(for: account))
    }

    /// A figure typed into a settings field, or nil for anything that is not
    /// one.
    ///
    /// **`Double(_:)` alone is not this.** It accepts `"inf"`, `"infinity"`
    /// and `"1e999"`, all of which are `> 0`, and an infinite denominator makes
    /// `usedFraction` NaN — which `min`/`max` propagate rather than clamp, and
    /// which `Int(_:)` traps on. Persisted, that crashed the panel on every
    /// launch until the field was cleared.
    ///
    /// Parsed through a formatter rather than `Double(_:)` so a comma decimal
    /// separator is read rather than silently clearing the setting, and the
    /// currency symbol somebody types out of habit is ignored.
    private static func money(_ typed: String) -> Double? {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
            .filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.numberStyle = .decimal
        let value = formatter.number(from: trimmed)?.doubleValue
            ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))

        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// The stored figure back in the field — without the `.0` that
    /// `String(_:)` puts on every whole number.
    private static func text(_ amount: Double?) -> String {
        guard let amount else { return "" }
        return amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)
            .locale(LocalizationSource.locale))
    }

    func saveLowBalance(for account: AccountKey) {
        settings.setLowBalanceAlert(Self.money(lowBalance), for: account)
        lowBalance = Self.text(settings.lowBalanceAlert(for: account))
        // **The only alert control that was not asking.** Its three siblings in
        // the general pane all do, and without it a fresh install types a
        // figure into a group headed "Notifications" and is never told
        // anything: `observe` bails while authorization is `.notDetermined`,
        // and nothing else was ever going to ask.
        guard settings.lowBalanceAlert(for: account) != nil else { return }
        Task {
            // And reconsider straight away, like its siblings: a balance
            // already under the line when the figure is entered is announced
            // once, rather than waiting for a pass.
            if await alerts.requestAuthorizationIfNeeded() { store.reconsiderAlerts() }
        }
    }
}
