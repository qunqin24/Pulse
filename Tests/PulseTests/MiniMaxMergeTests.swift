import Foundation
import Testing
@testable import Pulse

/// MiniMax CN folded into MiniMax (`MiniMaxMerge`): the key moves to the
/// minimaxi.com site's slot, and MiniMax CN's settings become MiniMax's only
/// where MiniMax CN was the one in use.
@Suite("MiniMax merge")
struct MiniMaxMergeTests {
    private static func keysDirectory() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "PulseMiniMaxMerge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A key file holding `key` under the retired provider's entry, as a
    /// build from before the merge left it.
    private static func storeRetiredKey(_ key: String, in directory: URL) throws {
        #expect(APIKeyStore.setKey(key, for: .minimax, slot: "staging", in: directory))
        let file = directory.appending(path: "keys.dat")
        var entries = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: file))
        entries[MiniMaxMerge.retired] = entries.removeValue(forKey: "minimax#staging")
        try JSONEncoder().encode(entries).write(to: file)
    }

    @Test("MiniMax CN on its own becomes MiniMax on minimaxi.com, with its key, place and ring settings")
    func cnInUse() throws {
        let (defaults, cleanup) = TestDefaults.make("MiniMaxMerge")
        defer { cleanup() }
        let keys = try Self.keysDirectory()
        defer { try? FileManager.default.removeItem(at: keys) }
        try Self.storeRetiredKey("cn-key", in: keys)

        defaults.set(["codex", "minimaxCN"], forKey: ProviderSelection.enabledKey)
        defaults.set(["claudeCode", "minimaxCN", "codex", "minimax"], forKey: "settings.providerOrder")
        defaults.set(["minimaxCN": "#FF0000", "minimax": "#00FF00"], forKey: "settings.ringTints")
        defaults.set(["minimaxCN": "minimaxCN.MiniMax-M2.interval"], forKey: "settings.pinnedWindows")
        defaults.set("minimaxCN", forKey: "settings.menuBarAccount")

        MiniMaxMerge.migrate(defaults: defaults, keys: keys)

        #expect(Set(defaults.stringArray(forKey: ProviderSelection.enabledKey) ?? []) == ["codex", "minimax"])
        #expect(defaults.string(forKey: AppSettings.Key.minimaxSite) == MiniMaxSite.china.rawValue)
        #expect(defaults.stringArray(forKey: "settings.providerOrder") == ["claudeCode", "minimax", "codex"])
        #expect(defaults.dictionary(forKey: "settings.ringTints") as? [String: String] == ["minimax": "#FF0000"])
        #expect(defaults.dictionary(forKey: "settings.pinnedWindows") as? [String: String]
            == ["minimax": "minimax.MiniMax-M2.interval"])
        #expect(defaults.string(forKey: "settings.menuBarAccount") == "minimax")
        #expect(APIKeyStore.key(for: .minimax, slot: MiniMaxSite.china.keySlot, in: keys) == "cn-key")
        #expect(APIKeyStore.key(for: .minimax, in: keys) == nil)
        #expect(defaults.bool(forKey: MiniMaxMerge.doneKey))

        let settings = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())
        #expect(settings.minimaxSite == .china)
        #expect(settings.keySlot(for: .minimax) == MiniMaxSite.china.keySlot)
    }

    @Test("With both on, MiniMax stays on minimax.io; MiniMax CN's key is kept for its site and fills only what MiniMax lacked")
    func bothInUse() throws {
        let (defaults, cleanup) = TestDefaults.make("MiniMaxMerge")
        defer { cleanup() }
        let keys = try Self.keysDirectory()
        defer { try? FileManager.default.removeItem(at: keys) }
        #expect(APIKeyStore.setKey("intl-key", for: .minimax, in: keys))
        try Self.storeRetiredKey("cn-key", in: keys)

        defaults.set(["minimax", "minimaxCN"], forKey: ProviderSelection.enabledKey)
        defaults.set(["minimaxCN", "minimax"], forKey: "settings.providerOrder")
        defaults.set(["minimaxCN": "#FF0000", "minimax": "#00FF00"], forKey: "settings.ringTints")

        MiniMaxMerge.migrate(defaults: defaults, keys: keys)

        #expect(defaults.stringArray(forKey: ProviderSelection.enabledKey) == ["minimax"])
        #expect(defaults.object(forKey: AppSettings.Key.minimaxSite) == nil)
        #expect(defaults.stringArray(forKey: "settings.providerOrder") == ["minimax"])
        #expect(defaults.dictionary(forKey: "settings.ringTints") as? [String: String] == ["minimax": "#00FF00"])
        #expect(APIKeyStore.key(for: .minimax, in: keys) == "intl-key")
        #expect(APIKeyStore.key(for: .minimax, slot: MiniMaxSite.china.keySlot, in: keys) == "cn-key")
    }

    @Test("It runs once, and settings that never mentioned MiniMax CN are left as they were")
    func once() throws {
        let (defaults, cleanup) = TestDefaults.make("MiniMaxMerge")
        defer { cleanup() }
        let keys = try Self.keysDirectory()
        defer { try? FileManager.default.removeItem(at: keys) }

        defaults.set(["codex"], forKey: ProviderSelection.enabledKey)
        defaults.set(["codex": "#123456"], forKey: "settings.ringTints")
        MiniMaxMerge.migrate(defaults: defaults, keys: keys)
        #expect(defaults.stringArray(forKey: ProviderSelection.enabledKey) == ["codex"])
        #expect(defaults.dictionary(forKey: "settings.ringTints") as? [String: String] == ["codex": "#123456"])
        #expect(defaults.bool(forKey: MiniMaxMerge.doneKey))

        // Done is done: a retired id written afterwards is not touched.
        defaults.set(["minimaxCN"], forKey: ProviderSelection.enabledKey)
        MiniMaxMerge.migrate(defaults: defaults, keys: keys)
        #expect(defaults.stringArray(forKey: ProviderSelection.enabledKey) == ["minimaxCN"])
    }

    @Test("Folding a setting: lists, ids, and settings by account")
    func folding() {
        #expect(MiniMaxMerge.folded("minimaxCN", cnWins: false) as? String == "minimax")
        #expect(MiniMaxMerge.folded("codex", cnWins: true) == nil)
        #expect(MiniMaxMerge.folded(["a", "minimaxCN", "b"], cnWins: false) as? [String] == ["a", "b"])
        #expect(MiniMaxMerge.folded(["minimax", "a", "minimaxCN"], cnWins: true) as? [String] == ["a", "minimax"])
        #expect(MiniMaxMerge.folded(["a": 1], cnWins: true) == nil)
        #expect(MiniMaxMerge.folded(["minimaxCN": 0.5], cnWins: false) as? [String: Double] == ["minimax": 0.5])
    }
}

/// The two MiniMax sites are two accounts: a failed read on one never stands
/// in for the other's figures (review, 2026-10-16).
@Suite("MiniMax site scope")
struct MiniMaxSiteScopeTests {
    private func reading(site: MiniMaxSite, key: String, used: Double? = nil) -> ProviderUsage {
        var usage: ProviderUsage
        if let used {
            let window = UsageWindow(id: "w", kind: .monthly, scope: nil, usedFraction: used,
                                     windowSeconds: 0, resetsAt: nil, reportsLength: false)
            usage = ProviderUsage(account: AccountKey(.minimax), windows: [window], observedAt: Date(),
                                  state: .live, plan: nil, creditBalance: nil)
        } else {
            usage = .unavailable(AccountKey(.minimax), reason: .unreachable)
        }
        usage.sourceScope = MiniMaxUsageService.scope(site: site, key: key)
        return usage
    }

    @Test("A failed read on the other site does not fall back to this site's figures")
    func otherSiteIsNotAFallback() async {
        let file = FileManager.default.temporaryDirectory.appending(path: "MiniMaxScope-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        _ = await cache.reconciled(reading(site: .international, key: "intl-key", used: 0.82))

        let china = await cache.reconciled(reading(site: .china, key: "cn-key"))
        #expect(china.state == .unavailable(.unreachable))
        #expect(china.windows.isEmpty)

        // The same site and key still fall back, as before.
        let again = await cache.reconciled(reading(site: .international, key: "intl-key"))
        #expect(again.windows.first?.usedFraction == 0.82)
    }

    @Test("The scope names the site and a fingerprint of the key, never the key")
    func scopeNamesNoKey() throws {
        let scope = try #require(MiniMaxUsageService.scope(site: .china, key: "secret-key"))
        #expect(scope.organization == MiniMaxSite.china.apiHost)
        #expect(scope.identity?.contains("secret") == false)
        #expect(MiniMaxUsageService.scope(site: .china, key: "  ") == nil)
        #expect(!UsageScope.match(scope, MiniMaxUsageService.scope(site: .international, key: "secret-key")))
    }

    @Test("Forgetting an account drops its kept reading")
    func forget() async {
        let file = FileManager.default.temporaryDirectory.appending(path: "MiniMaxForget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        _ = await cache.reconciled(reading(site: .international, key: "k", used: 0.5))
        #expect(await cache.lastReading(for: AccountKey(.minimax)) != nil)
        await cache.forget(AccountKey(.minimax))
        #expect(await cache.lastReading(for: AccountKey(.minimax)) == nil)
    }
}
