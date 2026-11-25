import Foundation
import Testing
@testable import Pulse

/// sub2api and New API accounts beyond the first (#125): each is another
/// deployment with its own address, key and name. Keys go to a temporary
/// folder and settings to a throwaway defaults suite — never this Mac's own.
@Suite("Gateway accounts")
@MainActor
struct GatewayAccountsTests {
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PulseTests.gatewayKeys.\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func withSettings(_ body: (AppSettings) throws -> Void) throws {
        let (defaults, cleanup) = TestDefaults.make("gatewayAccounts")
        defer { cleanup() }
        try body(AppSettings(defaults: defaults))
    }

    @Test("Only the two gateways add accounts by address, and both allow more than one")
    func whichProvidersAddByAddress() {
        let byAddress = Provider.builtIn.filter(\.addsAccountsByAddress)
        #expect(Set(byAddress) == [.sub2api, .newAPI])
        #expect(byAddress.allSatisfy { $0.supportsMultipleAccounts })
        #expect(byAddress.allSatisfy { $0.usesServerAddress })
    }

    @Test("The first account keeps the provider's key entry; an added one keeps its own")
    func keySlots() throws {
        try withSettings { settings in
            #expect(settings.keySlot(for: AccountKey(.sub2api)) == nil)
            #expect(settings.keySlot(for: AccountKey(.newAPI)) == nil)
            // MiniMax's first account still answers by its site.
            #expect(settings.keySlot(for: AccountKey(.minimax)) == settings.minimaxSite.keySlot)

            let added = settings.addAccount(.sub2api, label: "Work")
            #expect(settings.keySlot(for: added) == added.slot)
        }
    }

    @Test("Keys of the first account and two added ones are kept apart")
    func keysAreKeptPerAccount() throws {
        try withFolder { folder in
            try withSettings { settings in
                let first = AccountKey(.sub2api)
                let work = settings.addAccount(.sub2api, label: "Work")
                let home = settings.addAccount(.sub2api, label: "Home")

                for (account, key) in [(first, "sk-first"), (work, "sk-work"), (home, "sk-home")] {
                    #expect(APIKeyStore.setKey(key, for: .sub2api, slot: settings.keySlot(for: account), in: folder))
                }

                #expect(APIKeyStore.key(for: .sub2api, slot: settings.keySlot(for: first), in: folder) == "sk-first")
                #expect(APIKeyStore.key(for: .sub2api, slot: settings.keySlot(for: work), in: folder) == "sk-work")
                #expect(APIKeyStore.key(for: .sub2api, slot: settings.keySlot(for: home), in: folder) == "sk-home")
                // The primary entry is the one every existing install already has.
                #expect(APIKeyStore.key(for: .sub2api, in: folder) == "sk-first")
            }
        }
    }

    @Test("Each account has its own address")
    func addressesArePerAccount() throws {
        try withSettings { settings in
            let first = AccountKey(.newAPI)
            let added = settings.addAccount(.newAPI, label: "Relay")
            settings.setServerAddress("https://one.example.com", for: first)
            settings.setServerAddress("https://two.example.com", for: added)

            #expect(settings.serverAddress(for: first) == "https://one.example.com")
            #expect(settings.serverAddress(for: added) == "https://two.example.com")
        }
    }

    @Test("Added gateways are numbered from 2, filling a number freed by a removal")
    func labels() throws {
        try withFolder { folder in
            try withSettings { settings in
                let second = settings.addGatewayAccount(.sub2api)
                let third = settings.addGatewayAccount(.sub2api)
                #expect(second.map(settings.label(for:)) == "sub2api 2")
                #expect(third.map(settings.label(for:)) == "sub2api 3")
                // Another provider counts its own.
                #expect(settings.addGatewayAccount(.newAPI).map(settings.label(for:)) == "New API 2")

                if let second { settings.removeGatewayAccount(second, keysIn: folder) }
                #expect(settings.addGatewayAccount(.sub2api).map(settings.label(for:)) == "sub2api 2")

                // Not a gateway: nothing is added.
                #expect(settings.addGatewayAccount(.claudeCode) == nil)
            }
        }
    }

    @Test("Removing an added gateway forgets its key, address and name, and nothing of another account")
    func removal() throws {
        try withFolder { folder in
            try withSettings { settings in
                let first = AccountKey(.sub2api)
                let removed = try #require(settings.addGatewayAccount(.sub2api))
                let kept = try #require(settings.addGatewayAccount(.sub2api))

                for account in [first, removed, kept] {
                    APIKeyStore.setKey("sk-\(account.id)", for: .sub2api, slot: settings.keySlot(for: account), in: folder)
                    settings.setServerAddress("https://\(account.slot.isEmpty ? "first" : account.slot).example.com", for: account)
                }

                #expect(settings.removeGatewayAccount(removed, keysIn: folder))

                #expect(APIKeyStore.key(for: .sub2api, slot: removed.slot, in: folder) == nil)
                #expect(settings.serverAddress(for: removed).isEmpty)
                #expect(!settings.extraAccounts.contains { $0.key == removed })
                #expect(!settings.allAccounts.contains(removed))
                #expect(!settings.isEnabled(removed))

                #expect(APIKeyStore.key(for: .sub2api, slot: settings.keySlot(for: kept), in: folder) == "sk-\(kept.id)")
                #expect(APIKeyStore.key(for: .sub2api, in: folder) == "sk-sub2api")
                #expect(settings.serverAddress(for: kept) == "https://\(kept.slot).example.com")
                #expect(settings.serverAddress(for: first) == "https://first.example.com")
                #expect(settings.allAccounts.contains(kept))

                // The first account is never removed this way.
                #expect(!settings.removeGatewayAccount(first, keysIn: folder))
                #expect(APIKeyStore.key(for: .sub2api, in: folder) == "sk-sub2api")
            }
        }
    }

    @Test("A reading is filed under the account it was read for")
    func readingsCarryTheAccount() async {
        let added = AccountKey(.sub2api, slot: "work")
        // No key, so nothing is sent anywhere.
        let sub2api = await Sub2APIUsageService(enteredKey: nil, address: "https://a.example.com", account: added).fetch()
        #expect(sub2api.account == added)

        let relay = AccountKey(.newAPI, slot: "relay")
        let newAPI = await NewAPIUsageService(enteredKey: "sk-x", address: nil, account: relay).fetch()
        #expect(newAPI.account == relay)

        // The first account's reading is unchanged.
        #expect(await Sub2APIUsageService(enteredKey: nil, address: nil).fetch().account == AccountKey(.sub2api))
    }
}
