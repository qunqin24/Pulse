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
            settings.botMarks[kept.id] = nil
            settings.botPersonas[kept.id] = nil
            settings.botColours[kept.id] = nil
            settings.botShapes[kept.id] = nil
            settings.splitAccounts.remove(kept.id)
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
            settings.setShowsBotMark(true, for: account)
            settings.setBotPersona(.calm, for: account)
            settings.setBotColour(.blue, for: account)
            settings.setBotBody(.pebble, for: account)
            settings.setSplit(true, for: account)
        }

        // Sanity: both accounts actually hold the values, before either is removed.
        #expect(settings.pinnedWindow(for: removed) == "weekly")
        #expect(settings.pinnedWindow(for: kept) == "weekly")

        settings.removeAccount(removed)

        // The removed account's id is gone from every per-account store.
        #expect(settings.pinnedWindows[removed.id] == nil)
        #expect(settings.sources[removed.id] == nil)
        #expect(settings.ringTints[removed.id] == nil)
        #expect(settings.sessionBrowsers[removed.id] == nil)
        #expect(settings.serverAddresses[removed.id] == nil)
        #expect(settings.lowBalanceAlerts[removed.id] == nil)
        #expect(settings.balanceBases[removed.id] == nil)
        #expect(settings.balanceBudgets[removed.id] == nil)
        #expect(settings.botMarks[removed.id] == nil)
        #expect(settings.botPersonas[removed.id] == nil)
        #expect(settings.botColours[removed.id] == nil)
        #expect(settings.botShapes[removed.id] == nil)
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
        #expect(!settings.showsBotMark(for: removed))
        #expect(settings.botPersona(for: removed) == nil)
        #expect(settings.botColour(for: removed) == nil)
        #expect(settings.botBody(for: removed) == .default)

        // A second account's own settings are untouched by the removal.
        #expect(settings.pinnedWindow(for: kept) == "weekly")
        #expect(settings.source(for: kept) == .endpoint)
        #expect(settings.ringTint(for: kept) != nil)
        #expect(settings.sessionBrowser(for: kept) == .chrome)
        #expect(settings.serverAddress(for: kept) == "https://example.com/\(kept.id)")
        #expect(settings.lowBalanceAlert(for: kept) == 5)
        #expect(settings.balanceBasis(for: kept) == .budget)
        #expect(settings.balanceBudget(for: kept) == 20)
        #expect(settings.showsBotMark(for: kept))
        #expect(settings.botPersona(for: kept) == .calm)
        #expect(settings.botColour(for: kept) != nil)
        #expect(settings.botBody(for: kept) == .pebble)
        #expect(settings.splitAccounts.contains(kept.id))
    }
}
