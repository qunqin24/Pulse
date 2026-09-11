import Foundation
import Observation

@MainActor
@Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
    private(set) var requestID = UUID()

    func open(_ link: PulseLink, accounts: [AccountKey]) {
        switch link {
        case .settings: pane = .general
        case .integrations: pane = .integrations
        case .account(let account):
            // A removed account's old link must not recreate an account pane.
            guard accounts.contains(account) else { return }
            pane = .account(account)
        }
        requestID = UUID()
    }
}
