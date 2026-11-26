// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// The window starter (`WindowPrimer`, `WindowStarter`): which providers it acts
// for, when, and what it last did. It is the one thing in Pulse that sends
// anything on the reader's behalf, so everything here is **off or empty by
// default** and is switched on only through Settings' confirmation. None of it
// goes through `onChange` — `WindowPrimer` observes these itself.

extension AppSettings.Key {
    static let primedProviders = "settings.primedProviders"
    static let primerStart = "settings.primerStart"
    static let primerEnd = "settings.primerEnd"
    static let primerResets = "settings.primerResets"
    static let primerRunTimes = "settings.primerRunTimes"
    static let primerRunOutcomes = "settings.primerRunOutcomes"
    static let primerArmedAt = "settings.primerArmedAt"
}

extension AppSettings {
    func primedProvidersChanged(from old: Set<String>) {
        guard primedProviders != old else { return }
        defaults.set(Array(primedProviders), forKey: Key.primedProviders)
    }

    func primerHoursChanged(from old: PrimerHours) {
        guard primerHours != old else { return }
        defaults.set(primerHours.start, forKey: Key.primerStart)
        defaults.set(primerHours.end, forKey: Key.primerEnd)
    }

    func primesWindows(for provider: Provider) -> Bool {
        primedProviders.contains(provider.rawValue)
    }

    func setPrimesWindows(_ on: Bool, for provider: Provider) {
        guard on else {
            primedProviders.remove(provider.rawValue)
            return
        }
        // Noted before the insert, which `WindowPrimer` observes.
        if !primesWindows(for: provider) {
            var armed = defaults.dictionary(forKey: Key.primerArmedAt) as? [String: Double] ?? [:]
            armed[provider.rawValue] = Date().timeIntervalSince1970
            defaults.set(armed, forKey: Key.primerArmedAt)
        }
        primedProviders.insert(provider.rawValue)
    }

    /// The attempt that still decides whether an idle window may be started.
    ///
    /// One from before the switch was last turned on does not: turning it back
    /// on, through the risk confirmation, is the reader asking for a fresh try.
    /// Without this a failed attempt could only be cleared by a reset Pulse saw
    /// coming, and the switch did nothing. "Last started" still shows it.
    func governingPrimerRun(for provider: Provider) -> (date: Date, outcome: WindowStarter.Outcome)? {
        guard let last = lastPrimerRun(for: provider) else { return nil }
        let armed = (defaults.dictionary(forKey: Key.primerArmedAt) as? [String: Double])?[provider.rawValue]
        if let armed, last.date.timeIntervalSince1970 < armed { return nil }
        return last
    }

    func lastPrimerRun(for provider: Provider) -> (date: Date, outcome: WindowStarter.Outcome)? {
        guard let time = primerRunTimes[provider.rawValue],
              let outcome = primerRunOutcomes[provider.rawValue].flatMap(WindowStarter.Outcome.init(rawValue:))
        else { return nil }
        return (Date(timeIntervalSince1970: time), outcome)
    }

    func recordPrimerRun(for provider: Provider, outcome: WindowStarter.Outcome, at date: Date) {
        primerRunTimes[provider.rawValue] = date.timeIntervalSince1970
        primerRunOutcomes[provider.rawValue] = outcome.rawValue
        defaults.set(primerRunTimes, forKey: Key.primerRunTimes)
        defaults.set(primerRunOutcomes, forKey: Key.primerRunOutcomes)
    }

    /// Only the provider, limit row and dates survive a relaunch.
    var rememberedPrimerResets: [String: WindowPrimer.Reset] {
        get {
            guard let data = defaults.data(forKey: Key.primerResets) else { return [:] }
            return (try? JSONDecoder().decode([String: WindowPrimer.Reset].self, from: data)) ?? [:]
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.primerResets)
        }
    }

    /// The settings `init` has no parameter for.
    func restoreWindowStarter(from defaults: UserDefaults) {
        primedProviders = Set(defaults.stringArray(forKey: Key.primedProviders) ?? [])
        if let start = defaults.object(forKey: Key.primerStart) as? Int,
           let end = defaults.object(forKey: Key.primerEnd) as? Int,
           (0...23).contains(start), (0...23).contains(end) {
            primerHours = PrimerHours(start: start, end: end)
        }
        primerRunTimes = defaults.dictionary(forKey: Key.primerRunTimes) as? [String: Double] ?? [:]
        primerRunOutcomes = defaults.dictionary(forKey: Key.primerRunOutcomes) as? [String: String] ?? [:]
    }
}
