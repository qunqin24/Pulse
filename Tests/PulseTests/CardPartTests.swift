import Foundation
import Testing
@testable import Pulse

/// What each account's card shows (`CardPart`): the parts an account can show,
/// the older switches as the default, and an account's own list once changed.
/// Settings go to a throwaway defaults suite — never this Mac's own.
@Suite("Card contents")
@MainActor
struct CardPartTests {
    private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
        let (defaults, cleanup) = TestDefaults.make("cardParts")
        defer { cleanup() }
        try body(AppSettings(defaults: defaults), defaults)
    }

    @Test("Only what an account can show is offered")
    func available() {
        let claude = Set(CardPart.available(for: AccountKey(.claudeCode)))
        #expect(claude.isSuperset(of: [.plan, .updated, .forecast, .figures, .chart, .topModel, .cacheHitRate, .promptCache]))
        #expect(!claude.contains(.lastStep) && !claude.contains(.resetCredits) && !claude.contains(.amounts))
        let codex = Set(CardPart.available(for: AccountKey(.codex)))
        #expect(codex.isSuperset(of: [.lastStep, .resetCredits]))
        #expect(!codex.contains(.promptCache))
        // An added account's records are not its own: no history, no Codex extras.
        let added = Set(CardPart.available(for: AccountKey(.codex, slot: "work")))
        #expect(added == [.plan, .updated, .forecast])
        #expect(Set(CardPart.available(for: AccountKey(.qoder))).isSuperset(of: [.amounts, .figures, .chart]))
        #expect(!CardPart.available(for: AccountKey(.qoder)).contains(.topModel))
    }

    @Test("Until changed, an account shows the whole card; three parts keep their old switches")
    func defaults() {
        withSettings { settings, _ in
            #expect(settings.cardParts(for: AccountKey(.claudeCode))
                == [.plan, .updated, .value, .figures, .chart, .topModel, .cacheHitRate, .promptCache])
            #expect(settings.cardParts(for: AccountKey(.copilot)).isSuperset(of: [.plan, .updated]))
            #expect(settings.cardParts(for: AccountKey(.copilot)).isDisjoint(with: [.forecast, .amounts]))
            #expect(settings.cardParts(for: AccountKey(.codex)).isSuperset(of: [.plan, .lastStep, .figures]))
            #expect(!settings.cardParts(for: AccountKey(.codex)).contains(.resetCredits))

            settings.showsForecast = true
            settings.copilotShowsAmounts = true
            settings.showsCodexResetCredits = true
            #expect(settings.cardParts(for: AccountKey(.copilot)).isSuperset(of: [.forecast, .amounts]))
            #expect(settings.cardParts(for: AccountKey(.codex)).isSuperset(of: [.forecast, .resetCredits]))
        }
    }

    @Test("A change writes the account's own list, which then stays put and is kept")
    func ownList() {
        withSettings { settings, defaults in
            let all = settings.cardParts(for: AccountKey(.claudeCode))
            settings.showsForecast = true
            settings.setCardPart(.chart, shown: false, for: AccountKey(.claudeCode))
            #expect(settings.cardParts(for: AccountKey(.claudeCode)) == all.union([.forecast]).subtracting([.chart]))
            // The old switch no longer moves it.
            settings.showsForecast = false
            #expect(settings.cardParts(for: AccountKey(.claudeCode)).contains(.forecast))
            // Another account still follows the default.
            #expect(!settings.cardParts(for: AccountKey(.codex)).contains(.forecast))

            let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())
            #expect(back.cardParts(for: AccountKey(.claudeCode)) == all.union([.forecast]).subtracting([.chart]))
        }
    }

    @Test("Removing an added account forgets its card")
    func removed() {
        withSettings { settings, _ in
            let added = settings.addAccount(.codex, label: "Work")
            settings.setCardPart(.plan, shown: true, for: added)
            settings.removeAccount(added)
            #expect(settings.cardParts[added.id] == nil)
        }
    }
}
