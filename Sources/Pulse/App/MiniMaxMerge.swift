// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// MiniMax CN folded into MiniMax, once, at launch.
///
/// The two were separate providers for one company's two storefronts, and are
/// now one provider with a site (`MiniMaxSite`). What was kept under
/// `minimaxCN` moves to `minimax`:
///
/// - **The key moves to the `minimaxi.com` site's slot** (`MiniMaxSite.keySlot`),
///   so a MiniMax key and a MiniMax CN key both survive, each where its site
///   reads it.
/// - **MiniMax CN wins only where it was the one in use**: switched on while
///   MiniMax was not. Then the site becomes `minimaxi.com`, and its ring's
///   settings — place on the rail, colour, mark, pinned limit — become
///   MiniMax's. Otherwise MiniMax's own stay, and MiniMax CN's fill only what
///   MiniMax never had.
///
/// Settings and the key file only; readings cached under `minimaxCN` are
/// never asked for again and go with the cache. Runs before settings are
/// restored, and marks itself done so it runs once.
enum MiniMaxMerge {
    static let retired = "minimaxCN"
    static let doneKey = "settings.mergedMiniMaxCN"

    /// Every setting kept by account id, so every one that can mention it.
    static let accountKeyed = [
        "settings.providerOrder", "settings.ringTints", "settings.detailedCards", "settings.splitAccounts",
        "settings.lowBalanceAlerts", "settings.pinnedWindows", "settings.sources", "settings.sessionBrowsers",
        "settings.balanceBases", "settings.balanceBudgets", "settings.serverAddresses", "settings.menuBarAccount",
        ProviderSelection.enabledKey, ProviderSelection.offeredKey,
    ]

    static func migrate(defaults: UserDefaults, keys directory: URL = PulseStorage.directory) {
        guard !defaults.bool(forKey: doneKey) else { return }

        let enabled = Set(defaults.stringArray(forKey: ProviderSelection.enabledKey) ?? [])
        let cnWins = enabled.contains(retired) && !enabled.contains(Provider.minimax.rawValue)

        // The key first, and the mark only once it is moved: a key file that
        // cannot be written is tried again at the next launch.
        guard APIKeyStore.moveRetiredEntry(
            retired, to: .minimax, slot: MiniMaxSite.china.keySlot, in: directory
        ) else { return }

        if cnWins { defaults.set(MiniMaxSite.china.rawValue, forKey: AppSettings.Key.minimaxSite) }
        for key in accountKeyed {
            guard let value = defaults.object(forKey: key) else { continue }
            if let moved = folded(value, cnWins: cnWins) { defaults.set(moved, forKey: key) }
        }
        defaults.set(true, forKey: doneKey)
    }

    /// One stored setting with `minimaxCN` folded into `minimax`, or nil when
    /// it never mentioned it.
    static func folded(_ value: Any, cnWins: Bool) -> Any? {
        let kept = Provider.minimax.rawValue
        switch value {
        case let id as String:
            return id == retired ? kept : nil

        case let ids as [String]:
            guard ids.contains(retired) else { return nil }
            // The retired one's place on the rail when it was the one in use.
            var result = cnWins ? ids.filter { $0 != kept } : ids
            result = cnWins ? result.map { $0 == retired ? kept : $0 } : result.filter { $0 != retired }
            var seen = Set<String>()
            return result.filter { seen.insert($0).inserted }

        case var byAccount as [String: Any]:
            guard let moved = byAccount.removeValue(forKey: retired) else { return nil }
            if cnWins || byAccount[kept] == nil {
                // A pinned limit names its window, and a window's id starts
                // with the provider's.
                if let window = moved as? String, window.hasPrefix(retired + ".") {
                    byAccount[kept] = kept + window.dropFirst(retired.count)
                } else {
                    byAccount[kept] = moved
                }
            }
            return byAccount

        default:
            return nil
        }
    }
}
