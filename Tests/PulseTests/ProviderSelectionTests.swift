import Foundation
import Testing
@testable import Pulse

@Suite("Provider selection")
struct ProviderSelectionTests {
    private let primaryAccounts = Set(Provider.allCases.map(\.rawValue))

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "PulseTests.providerSelection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test("Fresh installs enable nothing, with or without detected tools", arguments: [
        Set<Provider>(), Set([Provider.claudeCode, .codex, .cursor]), Set(Provider.allCases)
    ])
    func freshInstall(detected: Set<Provider>) {
        withDefaults { defaults in
            let first = ProviderSelection.restore(in: defaults, knownAccounts: primaryAccounts, detected: detected)
            #expect(first.needsSelection)
            #expect(first.enabledAccounts.isEmpty)
            #expect(first.suggestedProviders.isEmpty)
            // Closing without a selection does not become an implicit choice
            // from the offered list that restoration just stamped.
            let second = ProviderSelection.restore(in: defaults, knownAccounts: primaryAccounts, detected: detected)
            #expect(second == first)
        }
    }

    @Test("A saved choice survives launch without adding detected services")
    func savedChoice() {
        withDefaults { defaults in
            _ = ProviderSelection.restore(in: defaults, knownAccounts: primaryAccounts, detected: [])
            // The enabled key is the same one the Settings toggle/Done stores.
            defaults.set([Provider.claudeCode.rawValue], forKey: ProviderSelection.enabledKey)
            let next = ProviderSelection.restore(
                in: defaults, knownAccounts: primaryAccounts, detected: Set(Provider.allCases)
            )
            #expect(!next.needsSelection)
            #expect(next.enabledAccounts == [Provider.claudeCode.rawValue])
            #expect(next.suggestedProviders.isEmpty)
        }
    }

    @Test("An upgrade suggests only new detected services, once, without enabling them")
    func upgradeSuggestions() {
        withDefaults { defaults in
            defaults.set(["codex"], forKey: ProviderSelection.enabledKey)
            defaults.set(["codex", "claudeCode"], forKey: ProviderSelection.offeredKey)
            let detected: Set<Provider> = [.claudeCode, .cursor, .grok]
            let first = ProviderSelection.restore(in: defaults, knownAccounts: primaryAccounts, detected: detected)
            #expect(first.enabledAccounts == ["codex"])
            #expect(first.suggestedProviders == [.cursor, .grok])
            // Dismissal, not just Done, must consume an upgrade offer.
            let second = ProviderSelection.restore(in: defaults, knownAccounts: primaryAccounts, detected: detected)
            #expect(second.enabledAccounts == ["codex"])
            #expect(second.suggestedProviders.isEmpty)
        }
    }

    @Test("An explicitly empty or unknown-only list asks again, even on an old install",
          arguments: [[], ["removed-provider"]])
    func invalidSelection(stored: [String]) {
        withDefaults { defaults in
            defaults.set(stored, forKey: ProviderSelection.enabledKey)
            defaults.set(["codex", "claudeCode"], forKey: ProviderSelection.offeredKey)
            defaults.set(true, forKey: ProviderSelection.hasRunKey)
            let selection = ProviderSelection.restore(
                in: defaults, knownAccounts: primaryAccounts, detected: Set(Provider.allCases)
            )
            #expect(selection.needsSelection)
            #expect(selection.enabledAccounts.isEmpty)
        }
    }

    @Test("Malformed preferences are not mistaken for the legacy absent key")
    func malformedSelection() {
        withDefaults { defaults in
            defaults.set("codex", forKey: ProviderSelection.enabledKey)
            defaults.set(["claudeCode"], forKey: ProviderSelection.offeredKey)
            #expect(ProviderSelection.restore(in: defaults, knownAccounts: primaryAccounts, detected: []).needsSelection)
        }
    }

    @Test("1.0.0's absent enabled key preserves only its historical implicit choice")
    func legacyAbsentSelection() {
        withDefaults { defaults in
            defaults.set(["codex", "claudeCode"], forKey: ProviderSelection.offeredKey)
            let selection = ProviderSelection.restore(in: defaults, knownAccounts: primaryAccounts, detected: [.cursor])
            #expect(selection.enabledAccounts == ["codex", "claudeCode"])
            #expect(selection.suggestedProviders == [.cursor])
            #expect(!selection.needsSelection)
        }
    }

    @Test("An extra account alone is a complete choice, and unknown ids do not enable primaries")
    func extraAccountOnly() {
        withDefaults { defaults in
            let extra = AccountKey(.codex, slot: "work")
            defaults.set([extra.id, "removed-provider"], forKey: ProviderSelection.enabledKey)
            defaults.set(Provider.allCases.map(\.rawValue), forKey: ProviderSelection.offeredKey)
            let selection = ProviderSelection.restore(
                in: defaults, knownAccounts: primaryAccounts.union([extra.id]), detected: Set(Provider.allCases)
            )
            #expect(selection.enabledAccounts == [extra.id])
            #expect(!selection.needsSelection)
        }
    }

    @Test("Discovery can mark credential files without opening or parsing them")
    func presenceOnlyDiscovery() {
        let home = URL(fileURLWithPath: "/synthetic-home")
        let paths = Set([
            ".local/share/opencode/auth.json", ".config/zhipu/api_key", ".commandcode/auth.json",
            "Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            "Library/Application Support/Windsurf/User/globalStorage/state.vscdb"
        ].map { home.appending(path: $0).path })
        // These files do not exist. A reader trying to open one cannot produce
        // a key, but presence alone is enough to show the detection hint.
        let found = Provider.installedOnThisMac(home: home, exists: paths.contains)
        #expect(found == [.openCodeGo, .glmCoding, .commandCode, .cursor, .devin])
    }

    @Test("Detection includes user Applications and an empty CLI directory")
    func appAndDirectoryDiscovery() {
        let home = URL(fileURLWithPath: "/synthetic-home")
        let paths = Set([".codex", ".kiro", "Applications/Grok Bot.app", "Applications/Antigravity.app", ".claude"]
            .map { home.appending(path: $0).path })
        #expect(Provider.installedOnThisMac(home: home, exists: paths.contains)
            == [.codex, .kiro, .grokBot, .antigravity, .claudeCode])
    }

    @Test("Before selection every store entry point stays idle")
    @MainActor
    func storeBeforeSelection() async {
        let settings = AppSettings(enabledAccounts: [])
        let store = UsageStore(settings: settings)
        store.start()
        store.settingsChanged()
        store.loadAPIKeys()
        store.refresh()
        store.refresh(AccountKey(.codex))
        store.refresh(AccountKey(.devin))
        #expect(await store.codexAccountUsage() == nil)
        #expect(!store.isRefreshing)
        #expect(store.diagnostics.isEmpty)
        #expect(settings.needsProviderSelection)
        settings.selectProviders([])
        #expect(settings.needsProviderSelection)
    }

    @Test("A chosen ring cannot be switched off into an empty rail")
    func lastRingStays() {
        let settings = AppSettings(enabledAccounts: [Provider.codex.rawValue])
        settings.setEnabled(false, for: AccountKey(.codex))
        #expect(!settings.needsProviderSelection)
        #expect(settings.shownAccounts == [AccountKey(.codex)])
    }
}
