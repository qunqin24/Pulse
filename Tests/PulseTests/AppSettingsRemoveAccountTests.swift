import SwiftUI
import Testing
@testable import Pulse

/// `removeAccount` promises to clear "everything stored against" an account.
/// The per-account stores in `AppSettings` are plain `[String: _]`/`Set<String>`
/// properties keyed by `AccountKey.id`, and it is easy to add a new one
/// without remembering to teach `removeAccount` about it — which is exactly
/// what happened to eight of them before this test existed. Every store is
/// set for two accounts here so a fix that only clears the first one it finds
/// still fails.
@Suite("AppSettings.removeAccount")
@MainActor
struct AppSettingsRemoveAccountTests {
    @Test("Removing an account clears every per-account store, and leaves a second account's settings alone")
    func clearsAllPerAccountStores() {
        let settings = AppSettings()
        let originalEnabled = settings.enabledAccounts

        let removed = settings.addAccount(.claudeCode, label: "Removed")
        let kept = settings.addAccount(.claudeCode, label: "Kept")

        defer {
            settings.extraAccounts.removeAll { $0.key == kept }
            settings.enabledAccounts = originalEnabled
            settings.pinnedWindows[kept.id] = nil
            settings.sources[kept.id] = nil
            settings.ringTints[kept.id] = nil
            settings.sessionBrowsers[kept.id] = nil
            settings.serverAddresses[kept.id] = nil
            settings.lowBalanceAlerts[kept.id] = nil
            settings.balanceBases[kept.id] = nil
            settings.balanceBudgets[kept.id] = nil
            settings.detailedCards.remove(kept.id)
            settings.robotAccounts.remove(kept.id)
            settings.robotColours[kept.id] = nil
            settings.robotPersonalities[kept.id] = nil
            settings.robotShapes[kept.id] = nil
            settings.splitAccounts.remove(kept.id)
            settings.menuBarAccount = nil
        }

        for account in [removed, kept] {
            settings.setPinnedWindow("weekly", for: account)
            settings.setSource(.endpoint, for: account)
            settings.setRingTint(.red, for: account)
            settings.setSessionBrowser(.chrome, for: account)
            settings.setServerAddress("https://example.com/\(account.id)", for: account)
            settings.setLowBalanceAlert(5, for: account)
            settings.setBalanceBasis(.budget, for: account)
            settings.setBalanceBudget(20, for: account)
            settings.setShowsDetailedCard(true, for: account)
            settings.setShowsRobot(true, for: account)
            settings.setRobotColour(.blue, for: account)
            settings.setRobotPersonality(.lively, for: account)
            settings.setRobotShape(.round, for: account)
            settings.setSplit(true, for: account)
        }

        // Sanity: both accounts actually hold the values, before either is removed.
        #expect(settings.pinnedWindow(for: removed) == "weekly")
        #expect(settings.pinnedWindow(for: kept) == "weekly")

        settings.menuBarAccount = removed.id
        settings.removeAccount(removed)
        // The menu bar no longer names an account that is gone.
        #expect(settings.menuBarAccount == nil)

        // The removed account's id is gone from every per-account store.
        #expect(settings.pinnedWindows[removed.id] == nil)
        #expect(settings.sources[removed.id] == nil)
        #expect(settings.ringTints[removed.id] == nil)
        #expect(settings.sessionBrowsers[removed.id] == nil)
        #expect(settings.serverAddresses[removed.id] == nil)
        #expect(settings.lowBalanceAlerts[removed.id] == nil)
        #expect(settings.balanceBases[removed.id] == nil)
        #expect(settings.balanceBudgets[removed.id] == nil)
        #expect(!settings.detailedCards.contains(removed.id))
        #expect(!settings.robotAccounts.contains(removed.id))
        #expect(settings.robotColours[removed.id] == nil)
        #expect(settings.robotPersonalities[removed.id] == nil)
        #expect(settings.robotShapes[removed.id] == nil)
        #expect(!settings.splitAccounts.contains(removed.id))

        // Reading them back through the account-scoped accessors agrees: every
        // one answers with its "nothing stored" default, not a leftover.
        #expect(settings.pinnedWindow(for: removed) == nil)
        #expect(settings.source(for: removed) == .automatic)
        #expect(settings.ringTint(for: removed) == nil)
        #expect(settings.sessionBrowser(for: removed) == nil)
        #expect(settings.serverAddress(for: removed) == "")
        #expect(settings.lowBalanceAlert(for: removed) == nil)
        #expect(settings.balanceBasis(for: removed) == .default)
        #expect(settings.balanceBudget(for: removed) == nil)
        #expect(!settings.showsDetailedCard(for: removed))
        #expect(!settings.showsRobot(for: removed))

        // A second account's own settings are untouched by the removal.
        #expect(settings.pinnedWindow(for: kept) == "weekly")
        #expect(settings.source(for: kept) == .endpoint)
        #expect(settings.ringTint(for: kept) != nil)
        #expect(settings.sessionBrowser(for: kept) == .chrome)
        #expect(settings.serverAddress(for: kept) == "https://example.com/\(kept.id)")
        #expect(settings.lowBalanceAlert(for: kept) == 5)
        #expect(settings.balanceBasis(for: kept) == .budget)
        #expect(settings.balanceBudget(for: kept) == 20)
        #expect(settings.splitAccounts.contains(kept.id))
        #expect(settings.showsRobot(for: kept))
        #expect(settings.robotColour(for: kept) != nil)
        #expect(settings.robotPersonality(for: kept) == .lively)
        #expect(settings.robotShape(for: kept) == .round)
    }
}
