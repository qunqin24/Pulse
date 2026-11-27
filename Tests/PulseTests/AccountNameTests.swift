import Foundation
import Testing
@testable import Pulse

/// Every account can carry the user's own name, the first one included (#125).
/// Settings go to a throwaway defaults suite — never this Mac's own.
@Suite("Account names")
@MainActor
struct AccountNameTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let (defaults, cleanup) = TestDefaults.make("accountNames")
        defer { cleanup() }
        try body(defaults)
    }

    @Test("A first account takes a name; blank or cleared is the provider's again")
    func firstAccount() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let account = AccountKey(.sub2api)
            #expect(settings.label(for: account) == "sub2api")
            #expect(settings.givenName(for: account) == "")

            settings.rename(account, to: "公司网关")
            #expect(settings.label(for: account) == "公司网关")
            #expect(settings.givenName(for: account) == "公司网关")

            settings.rename(account, to: "   ")
            #expect(settings.label(for: account) == "sub2api")
            settings.rename(account, to: "")
            #expect(settings.accountNames[account.id] == nil)
            #expect(settings.label(for: AccountKey(.claudeCode)) == "Claude Code")
        }
    }

    @Test("The name is kept across launches")
    func persisted() {
        withDefaults { defaults in
            AppSettings(defaults: defaults).rename(AccountKey(.claudeCode), to: "Work")
            #expect(defaults.dictionary(forKey: "settings.accountNames") as? [String: String] == ["claudeCode": "Work"])
            let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())
            #expect(back.label(for: AccountKey(.claudeCode)) == "Work")
        }
    }

    @Test("An added account cleared to nothing shows the provider's name, not a blank")
    func addedAccount() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let added = settings.addAccount(.codex, label: "Team")
            #expect(settings.label(for: added) == "Team")
            settings.rename(added, to: "")
            #expect(settings.label(for: added) == "Codex")
            #expect(settings.givenName(for: added) == "")
        }
    }
}
