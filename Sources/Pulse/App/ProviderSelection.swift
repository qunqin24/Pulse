// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Restoring a choice is separate from discovering installed tools. Discovery
/// can suggest rows, but can never authorize a credential read.
struct ProviderSelection: Equatable {
    let enabledAccounts: Set<String>
    let suggestedProviders: Set<Provider>

    var needsSelection: Bool { enabledAccounts.isEmpty }

    // The existing keys also describe older releases. In 1.0.0 the enabled
    // list was absent until edited; its offered list was the implicit default.
    static let enabledKey = "settings.enabledProviders"
    static let offeredKey = "settings.offeredProviders"
    static let hasRunKey = "settings.hasRun"

    static func restore(
        in defaults: UserDefaults,
        knownAccounts: Set<String>,
        detected: Set<Provider>
    ) -> Self {
        let offered = defaults.stringArray(forKey: offeredKey)
        let stored: [String]?
        if defaults.object(forKey: enabledKey) != nil {
            // An empty or malformed stored choice is not 1.0.0's absent key.
            stored = defaults.stringArray(forKey: enabledKey) ?? []
        } else {
            stored = nil
        }
        let enabled = Set(stored ?? offered ?? []).intersection(knownAccounts)
        let knownProviders = Set(offered ?? Provider.builtIn.map(\.rawValue))
        let suggestions = Set(Provider.builtIn.filter {
            !enabled.isEmpty && !knownProviders.contains($0.rawValue)
                && !enabled.contains($0.rawValue) && detected.contains($0)
        })

        // First-run dismissal keeps an explicit empty choice, so it asks again
        // next launch. Upgrade suggestions are offered once, even if dismissed.
        defaults.set(Array(enabled).sorted(), forKey: enabledKey)
        defaults.set(Provider.builtIn.map(\.rawValue), forKey: offeredKey)
        defaults.set(true, forKey: hasRunKey)
        return Self(enabledAccounts: enabled, suggestedProviders: suggestions)
    }
}
