import Foundation
import Testing
@testable import Pulse

@Suite("Pulse navigation links")
struct PulseLinkTests {
    @Test("Added-account separators are encoded as path data, not fragments")
    func roundTrip() {
        let account = AccountKey(.claudeCode, slot: "work")
        let link = PulseLink.account(account)
        #expect(link.url.absoluteString == "pulse://account/claudeCode%23work")
        #expect(PulseLink(url: link.url) == link)
        #expect(PulseLink(url: PulseLink.settings.url) == .settings)
        #expect(PulseLink(url: PulseLink.integrations.url) == .integrations)
    }

    @Test("Malformed or action-bearing URLs are rejected", arguments: [
        "https://account/codex", "pulse://account/codex#work", "pulse://account/codex%23",
        "pulse://account/codex/extra", "pulse://account/codex?refresh=true", "pulse://account/unknown",
        "pulse://user@account/codex", "pulse://account:80/codex", "pulse://settings/extra",
        "pulse://refresh/codex", "pulse://account/claudeCode%23work%23other"
    ])
    func rejects(_ value: String) throws {
        #expect(PulseLink(url: try #require(URL(string: value))) == nil)
    }

    @MainActor
    @Test("Navigation selects only existing accounts and repeated links still clear search")
    func selectsExistingAccounts() {
        let navigation = SettingsNavigation()
        let account = AccountKey(.codex, slot: "work")
        navigation.open(.account(account), accounts: [account])
        #expect(navigation.pane == .account(account))
        let request = navigation.requestID
        navigation.open(.account(account), accounts: [account])
        #expect(navigation.requestID != request)
        navigation.open(.integrations, accounts: [])
        navigation.open(.account(account), accounts: [])
        #expect(navigation.pane == .integrations)
    }
}
