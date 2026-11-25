// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// The alert rules. **Every one of them is off by default** and stays that way:
// Pulse says nothing unprompted until the reader asks it to. `UsageAlerts`
// observes the rules itself, so they do not go through `onChange` — which would
// refetch every provider for a rule that reads what is already on screen. (The
// one that does, the low-balance table, says why.) `onRecapAlertChange` exists
// so that switching the recap notice on in the first days of a month announces
// then.
//
// `UsageAlerts.isSupported` fences every entry point that talks to
// `UNUserNotificationCenter`; nothing in this file does.

extension AppSettings.Key {
    static let lowBalanceAlerts = "settings.lowBalanceAlerts"
    static let alertThreshold = "settings.alertThreshold"
    static let alertsOnReset = "settings.alertsOnReset"
    static let alertsOnFailure = "settings.alertsOnFailure"
    static let alertsOnOutage = "settings.alertsOnOutage"
    static let alertsOnRecap = "settings.alertsOnRecap"
}

extension AppSettings.Default {
    static let alertsOnReset = false
    static let alertsOnFailure = false
}

extension AppSettings {
    /// **Still `onChange`**, as it always was: this is not a layout setting,
    /// and whether a refresh is what a new threshold needs is not decided here.
    func lowBalanceAlertsChanged(from old: [String: Double]) {
        guard lowBalanceAlerts != old else { return }
        defaults.set(lowBalanceAlerts, forKey: Key.lowBalanceAlerts)
        onChange?()
    }

    func alertThresholdChanged(from old: AlertThreshold) {
        guard alertThreshold != old else { return }
        defaults.set(alertThreshold.rawValue, forKey: Key.alertThreshold)
    }

    func alertsOnResetChanged(from old: Bool) {
        guard alertsOnReset != old else { return }
        defaults.set(alertsOnReset, forKey: Key.alertsOnReset)
    }

    func alertsOnFailureChanged(from old: Bool) {
        guard alertsOnFailure != old else { return }
        defaults.set(alertsOnFailure, forKey: Key.alertsOnFailure)
    }

    func alertsOnOutageChanged(from old: Bool) {
        guard alertsOnOutage != old else { return }
        defaults.set(alertsOnOutage, forKey: Key.alertsOnOutage)
    }

    func alertsOnRecapChanged(from old: Bool) {
        guard alertsOnRecap != old else { return }
        defaults.set(alertsOnRecap, forKey: Key.alertsOnRecap)
        onRecapAlertChange?()
    }

    /// The balance this account should be warned below, or nil for no warning.
    func lowBalanceAlert(for account: AccountKey) -> Double? {
        lowBalanceAlerts[account.id]
    }

    /// Anything that is not a positive figure clears it: a warning below zero
    /// can never fire, and one at zero fires only once the account is already
    /// empty, which is the moment it is too late to be told.
    func setLowBalanceAlert(_ amount: Double?, for account: AccountKey) {
        var updated = lowBalanceAlerts
        updated[account.id] = amount.flatMap { $0 > 0 ? $0 : nil }
        lowBalanceAlerts = updated
    }

    /// Whether any rule about readings is on. What `UsageAlerts.observe`
    /// works for; the outage check reads status pages, not readings.
    var wantsUsageAlerts: Bool {
        alertThreshold != .off || alertsOnReset || alertsOnFailure || !lowBalanceAlerts.isEmpty
    }

    /// Whether anything at all would be posted. What decides if permission is
    /// worth asking for.
    var wantsAlerts: Bool {
        wantsUsageAlerts || alertsOnOutage || alertsOnRecap || !primedProviders.isEmpty
    }

    /// The settings `init` has no parameter for.
    func restoreNotifications(from defaults: UserDefaults) {
        alertsOnOutage = defaults.bool(forKey: Key.alertsOnOutage)
        alertsOnRecap = defaults.bool(forKey: Key.alertsOnRecap)
    }
}
