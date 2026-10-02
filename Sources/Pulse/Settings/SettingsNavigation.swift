// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

@MainActor
@Observable
final class SettingsNavigation {
    /// The first pane in the sidebar, which is where the panel is dressed.
    var pane: SettingsPane = .appearance
    var isWindowVisible = false
    private(set) var requestID = UUID()

    func open(_ link: PulseLink, accounts: [AccountKey]) {
        switch link {
        case .settings: pane = .appearance
        case .integrations: pane = .integrations
        case .account(let account):
            // A removed account's old link must not recreate an account pane.
            guard accounts.contains(account) else { return }
            pane = .account(account)
        }
        requestID = UUID()
    }
}
