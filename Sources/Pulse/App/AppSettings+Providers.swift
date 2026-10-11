// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// What the reader has told Pulse about *how to read* each provider: which route,
// which site, which browser, which gateway, what a balance is measured against,
// how often, and through which proxy. Every one of these changes what a
// provider is asked or how, so they go through `onChange` and a full refresh.
// The ones that do not say so.

extension AppSettings.Key {
    static let deepSeekBasis = "settings.deepSeekBasis"
    static let deepSeekBudget = "settings.deepSeekBudget"
    static let deepSeekCurrency = "settings.deepSeekCurrency"
    static let qoderSite = "settings.qoderSite"
    static let qoderShowsParts = "settings.qoderShowsParts"
    static let stepFunSite = "settings.stepFunSite"
    static let serverAddresses = "settings.serverAddresses"
    static let showsCodexResetCredits = "settings.showsCodexResetCredits"
    static let balanceBases = "settings.balanceBases"
    static let balanceBudgets = "settings.balanceBudgets"
    static let sessionBrowsers = "settings.sessionBrowsers"
    static let sources = "settings.sources"
    // Bumped when `.automatic` arrived and became the default: the old
    // key holds a fixed number of seconds for anyone who ran an earlier
    // build, which would quietly keep them on the cadence the new default
    // exists to replace.
    static let refreshInterval = "settings.refreshInterval.v2"
    static let networkProxy = "settings.networkProxy"
}

extension AppSettings.Default {
    static let qoderSite = QoderSite.international
    static let stepFunSite = StepFunSite.china
}

extension AppSettings {
    func deepSeekBasisChanged(from old: BalanceBasis) {
        guard deepSeekBasis != old else { return }
        defaults.set(deepSeekBasis.rawValue, forKey: Key.deepSeekBasis)
        onChange?()
    }

    func deepSeekBudgetChanged(from old: Double?) {
        guard deepSeekBudget != old else { return }
        defaults.set(deepSeekBudget, forKey: Key.deepSeekBudget)
        onChange?()
    }

    func deepSeekCurrencyChanged(from old: String?) {
        guard deepSeekCurrency != old else { return }
        defaults.set(deepSeekCurrency, forKey: Key.deepSeekCurrency)
        onChange?()
    }

    func qoderSiteChanged(from old: QoderSite) {
        guard qoderSite != old else { return }
        defaults.set(qoderSite.rawValue, forKey: Key.qoderSite)
        onChange?()
    }

    func qoderShowsPartsChanged(from old: Bool) {
        guard qoderShowsParts != old else { return }
        defaults.set(qoderShowsParts, forKey: Key.qoderShowsParts)
        onChange?()
    }

    func stepFunSiteChanged(from old: StepFunSite) {
        guard stepFunSite != old else { return }
        defaults.set(stepFunSite.rawValue, forKey: Key.stepFunSite)
        onChange?()
    }

    func serverAddressesChanged(from old: [String: String]) {
        guard serverAddresses != old else { return }
        defaults.set(serverAddresses, forKey: Key.serverAddresses)
        onChange?()
    }

    /// No `onChange`: Settings asks the store for the count itself.
    func showsCodexResetCreditsChanged(from old: Bool) {
        guard showsCodexResetCredits != old else { return }
        defaults.set(showsCodexResetCredits, forKey: Key.showsCodexResetCredits)
    }

    func balanceBasesChanged(from old: [String: String]) {
        guard balanceBases != old else { return }
        defaults.set(balanceBases, forKey: Key.balanceBases)
        onChange?()
    }

    func balanceBudgetsChanged(from old: [String: Double]) {
        guard balanceBudgets != old else { return }
        defaults.set(balanceBudgets, forKey: Key.balanceBudgets)
        onChange?()
    }

    func sessionBrowsersChanged(from old: [String: String]) {
        guard sessionBrowsers != old else { return }
        defaults.set(sessionBrowsers, forKey: Key.sessionBrowsers)
    }

    func sourcesChanged(from old: [String: String]) {
        guard sources != old else { return }
        defaults.set(sources, forKey: Key.sources)
        onChange?()
    }

    func refreshIntervalChanged(from old: RefreshInterval) {
        guard refreshInterval != old else { return }
        defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval)
        onChange?()
    }

    func networkProxyChanged(from old: NetworkProxySettings) {
        guard networkProxy != old else { return }
        Self.storeNetworkProxy(networkProxy, in: defaults)
        NetworkSession.apply(networkProxy)
        onChange?()
    }

    // MARK: - Stored directly, for readers without an `AppSettings`

    /// The same choice read straight from the defaults, for a reader off the
    /// main actor (the detailed card's DeepSeek history, whose money follows it).
    nonisolated static var storedDeepSeekCurrency: String? {
        UserDefaults.standard.string(forKey: Key.deepSeekCurrency)
    }

    static func storedNetworkProxy(in defaults: UserDefaults) -> NetworkProxySettings {
        guard let data = defaults.data(forKey: Key.networkProxy),
              let settings = try? JSONDecoder().decode(NetworkProxySettings.self, from: data)
        else { return .default }
        return settings
    }

    static func storeNetworkProxy(_ settings: NetworkProxySettings, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Key.networkProxy)
    }

    static var networkProxyDefaultsKey: String { Key.networkProxy }

    // MARK: - Per-account accessors

    /// A stored route the provider doesn't offer resolves to `.automatic`
    /// rather than being handed on. Routes are keyed by account and providers
    /// gain and lose them between versions, so a list saved while one existed
    /// would otherwise pin a provider to a route that can only fail.
    func source(for account: AccountKey) -> UsageSource {
        let stored = sources[account.id].flatMap(UsageSource.init(rawValue:)) ?? .automatic
        return UsageSource.options(for: account).contains(stored) ? stored : .automatic
    }

    func setSource(_ source: UsageSource, for account: AccountKey) {
        var updated = sources
        updated[account.id] = source == .automatic ? nil : source.rawValue
        sources = updated
    }

    func balanceBasis(for account: AccountKey) -> BalanceBasis {
        if account == AccountKey(.deepSeek) { return deepSeekBasis }
        return balanceBases[account.id].flatMap(BalanceBasis.init(rawValue:)) ?? .default
    }

    func setBalanceBasis(_ basis: BalanceBasis, for account: AccountKey) {
        if account == AccountKey(.deepSeek) { deepSeekBasis = basis; return }
        balanceBases[account.id] = basis == .default ? nil : basis.rawValue
    }

    func balanceBudget(for account: AccountKey) -> Double? {
        account == AccountKey(.deepSeek) ? deepSeekBudget : balanceBudgets[account.id]
    }

    func setBalanceBudget(_ budget: Double?, for account: AccountKey) {
        if account == AccountKey(.deepSeek) { deepSeekBudget = budget; return }
        balanceBudgets[account.id] = budget
    }

    /// The browser an account's session is read from, or nil for "whichever".
    func sessionBrowser(for account: AccountKey) -> BrowserCookies.Browser? {
        sessionBrowsers[account.id].flatMap(BrowserCookies.Browser.init(rawValue:))
    }

    func setSessionBrowser(_ browser: BrowserCookies.Browser?, for account: AccountKey) {
        var updated = sessionBrowsers
        updated[account.id] = browser?.rawValue
        sessionBrowsers = updated
    }

    /// The gateway address entered for an account, trimmed, or empty.
    func serverAddress(for account: AccountKey) -> String {
        (serverAddresses[account.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Blank removes the entry rather than storing an empty string, so the
    /// stored dictionary carries only addresses somebody actually set.
    func setServerAddress(_ address: String, for account: AccountKey) {
        var updated = serverAddresses
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        updated[account.id] = trimmed.isEmpty ? nil : trimmed
        serverAddresses = updated
    }

    /// The settings `init` has no parameter for.
    func restoreProviders(from defaults: UserDefaults) {
        showsCodexResetCredits = defaults.bool(forKey: Key.showsCodexResetCredits)
        qoderShowsParts = defaults.bool(forKey: Key.qoderShowsParts)
        balanceBases = defaults.dictionary(forKey: Key.balanceBases) as? [String: String] ?? [:]
        balanceBudgets = (defaults.dictionary(forKey: Key.balanceBudgets) as? [String: Double] ?? [:])
            .filter { $0.value.isFinite && $0.value > 0 }
    }
}
