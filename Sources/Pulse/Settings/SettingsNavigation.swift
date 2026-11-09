// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

@MainActor
@Observable
final class SettingsNavigation {
    /// The first pane in the sidebar, which is where the panel is dressed.
    var pane: SettingsPane = .appearance {
        didSet {
            // Every way to a pane — the sidebar, a link, a button in a
            // pane — is a step the back button can undo; going back and
            // forward is not.
            guard pane != oldValue, !isStepping else { return }
            back.append(oldValue)
            if back.count > Self.depth { back.removeFirst() }
            forward.removeAll()
        }
    }
    var isWindowVisible = false
    /// The star request's banner, for the time this window stays open
    /// (`StarRequest`). Set as the window opens, cleared as it closes.
    var showsStarRequest = false
    private(set) var requestID = UUID()

    /// The panes visited before this one, and those gone back from — the
    /// toolbar's back and forward buttons, as in System Settings.
    private(set) var back: [SettingsPane] = []
    private(set) var forward: [SettingsPane] = []
    @ObservationIgnored private var isStepping = false
    private static let depth = 50

    /// A step back, past any pane that cannot be shown any more — an
    /// account removed since it was visited. `exists` says which can.
    func goBack(where exists: (SettingsPane) -> Bool) {
        step(from: &back, to: &forward, where: exists)
    }

    func goForward(where exists: (SettingsPane) -> Bool) {
        step(from: &forward, to: &back, where: exists)
    }

    private func step(from source: inout [SettingsPane], to other: inout [SettingsPane], where exists: (SettingsPane) -> Bool) {
        while let target = source.popLast() {
            guard exists(target) else { continue }
            other.append(pane)
            isStepping = true
            pane = target
            isStepping = false
            requestID = UUID()
            return
        }
    }

    /// Goes to a pane, as a link does.
    func open(_ pane: SettingsPane) {
        self.pane = pane
        requestID = UUID()
    }

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
