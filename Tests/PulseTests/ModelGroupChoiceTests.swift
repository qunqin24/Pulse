import Foundation
import Testing
@testable import Pulse

/// Which of a split account's model groups get a ring, and what the rail
/// reserves for them (#106).
@MainActor
struct ModelGroupChoiceTests {
    private let antigravity = AccountKey(.antigravity)
    private let known = ["Gemini", "Claude and GPT", "Gemini 4 Argon"]

    private func settings() -> (AppSettings, () -> Void) {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.setSplit(true, for: antigravity)
        return (settings, cleanup)
    }

    @Test("Every group is shown until one is switched off, and the budget follows the choice")
    func choiceAndBudget() {
        let (settings, cleanup) = settings()
        defer { cleanup() }
        #expect(settings.shownModelGroups(for: antigravity) == nil)
        #expect(settings.modelGroupBudget(for: antigravity) == 3)

        settings.setShowsModelGroup(false, "Claude and GPT", known: known, for: antigravity)
        #expect(!settings.showsModelGroup("Claude and GPT", for: antigravity))
        #expect(Set(settings.shownModelGroups(for: antigravity) ?? []) == ["Gemini", "Gemini 4 Argon"])
        #expect(settings.modelGroupBudget(for: antigravity) == 2)

        // Back to every group is stored as no choice.
        settings.setShowsModelGroup(true, "Claude and GPT", known: known, for: antigravity)
        #expect(settings.shownModelGroups(for: antigravity) == nil)
    }

    @Test("The last group shown stays shown")
    func lastGroupStays() {
        let (settings, cleanup) = settings()
        defer { cleanup() }
        settings.setShowsModelGroup(false, "Claude and GPT", known: known, for: antigravity)
        settings.setShowsModelGroup(false, "Gemini 4 Argon", known: known, for: antigravity)
        settings.setShowsModelGroup(false, "Gemini", known: known, for: antigravity)
        #expect(settings.shownModelGroups(for: antigravity) == ["Gemini"])
        #expect(settings.modelGroupBudget(for: antigravity) == 1)
    }

    @Test("The choice is stored and read back")
    func stored() {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let first = AppSettings(defaults: defaults)
        first.shownModelGroups = ["antigravity": ["Gemini"]]
        #expect(defaults.dictionary(forKey: "settings.shownModelGroups") as? [String: [String]] == ["antigravity": ["Gemini"]])
        #expect(AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan()).shownModelGroups == ["antigravity": ["Gemini"]])
    }

    @Test("Gemini.app's copy of agy is found when no other is installed")
    func geminiAppCLI() {
        let found = AntigravityUsageService.geminiAppCLI(home: "/Users/someone", app: nil, isExecutable: { $0 == "/Users/someone/.gemini/bin/agy" })
        #expect(found?.path == "/Users/someone/.gemini/bin/agy")
        #expect(AntigravityUsageService.geminiAppCLI(home: "/Users/someone", app: nil, isExecutable: { _ in false }) == nil)
    }

    @Test("The copy inside Gemini.app is found when the updater has not put one in ~/.gemini/bin (#129)")
    func geminiAppBundledCLI() {
        let app = URL(fileURLWithPath: "/Users/someone/Applications/Gemini.app")
        let bundled = "/Users/someone/Applications/Gemini.app/Contents/Helpers/agy"
        let found = AntigravityUsageService.geminiAppCLI(home: "/Users/someone", app: app, isExecutable: { $0 == bundled })
        #expect(found?.path == bundled)

        // Launch Services did not answer: the usual place is still tried.
        let fallback = "/Applications/Gemini.app/Contents/Helpers/agy"
        #expect(AntigravityUsageService.geminiAppCLI(home: "/Users/someone", app: nil, isExecutable: { $0 == fallback })?.path == fallback)
    }

    @Test("With both copies present, the one Gemini.app's updater keeps current is asked")
    func geminiAppPrefersUpdatedCLI() {
        let app = URL(fileURLWithPath: "/Applications/Gemini.app")
        let found = AntigravityUsageService.geminiAppCLI(home: "/Users/someone", app: app, isExecutable: { _ in true })
        #expect(found?.path == "/Users/someone/.gemini/bin/agy")
    }
}
