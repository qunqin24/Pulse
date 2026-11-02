import Foundation
import SwiftUI
import Testing
@testable import Pulse

/// Every setting writes the value it was given under the key it has always
/// had. The key names are spelled out here on purpose: they are the stored
/// format, and a rename in `AppSettings` would silently reset everybody's
/// choice — nothing else would fail.
///
/// Runs against an isolated defaults suite, never `UserDefaults.standard`.
@Suite("AppSettings persistence")
@MainActor
struct AppSettingsPersistenceTests {
    /// A throwaway defaults domain, removed when the test ends.
    static func isolatedDefaults() -> (UserDefaults, cleanup: () -> Void) {
        TestDefaults.make("AppSettings")
    }

    @Test("Building settings writes nothing")
    func initWritesNothing() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }

        _ = AppSettings(defaults: defaults)

        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("settings.") }.isEmpty)
    }

    @Test("Flags are stored as booleans under their own keys")
    func flags() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        // Each flag is flipped away from its shipped default.
        let flips: [(String, ReferenceWritableKeyPath<AppSettings, Bool>, Bool)] = [
            ("settings.panelVisible", \.isPanelVisible, false),
            ("settings.hidesMenuBarIcon", \.hidesMenuBarIcon, true),
            ("settings.showsDockIconInSettings", \.showsDockIconInSettings, false),
            ("settings.showsUsageInMenuBar", \.showsUsageInMenuBar, true),
            ("settings.showsMenuDashboard", \.showsMenuDashboard, true),
            ("settings.hidesInFullScreen", \.hidesInFullScreen, false),
            ("settings.hidesFromScreenCapture", \.hidesFromScreenCapture, true),
            ("settings.followsActiveDisplay", \.followsActiveDisplay, true),
            ("settings.snapsToEdges", \.snapsToEdges, false),
            ("settings.liquidDocking", \.liquidDocking, true),
            ("settings.showsCodexResetCredits", \.showsCodexResetCredits, true),
            ("settings.qoderShowsAmounts", \.qoderShowsAmounts, true),
            ("settings.usesGlass", \.usesGlass, true),
            ("settings.usesLightPanel", \.usesLightPanel, true),
            ("settings.autoCollapse", \.autoCollapse, false),
            ("settings.topRailShowsPercentages", \.topRailShowsPercentages, true),
            ("settings.sideRailShowsPercentages", \.sideRailShowsPercentages, false),
            ("settings.labelAboveRing", \.labelAboveRing, true),
            ("settings.freeAcrossFiguresBeside", \.freeAcrossFiguresBeside, true),
            ("settings.usesRoundEnds", \.usesRoundEnds, true),
            ("settings.showsWindowClock", \.showsWindowClock, true),
            ("settings.showsRemaining", \.showsRemaining, true),
            ("settings.dockShowsAlertColor", \.dockShowsAlertColor, false),
            ("settings.showsForecast", \.showsForecast, true),
            ("settings.showsSecondRing", \.showsSecondRing, true),
            ("settings.animatesRingActivity", \.animatesRingActivity, false),
            ("settings.readsTokenSpend", \.readsTokenSpend, true),
            ("settings.alertsOnReset", \.alertsOnReset, true),
            ("settings.alertsOnFailure", \.alertsOnFailure, true),
            ("settings.alertsOnOutage", \.alertsOnOutage, true),
            ("settings.alertsOnRecap", \.alertsOnRecap, true),
            ("settings.recapHidesProjects", \.recapHidesProjects, true)
        ]
        for (key, path, value) in flips {
            #expect(settings[keyPath: path] != value, "\(key) should start on the other side")
            settings[keyPath: path] = value
            #expect(defaults.object(forKey: key) as? Bool == value, "\(key)")
        }
    }

    @Test("Choices are stored as their raw values under their own keys")
    func choices() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        settings.menuBarStyle = .ring
        #expect(defaults.string(forKey: "settings.menuBarStyle") == "ring")
        settings.displayCurrency = .cny
        #expect(defaults.string(forKey: "settings.displayCurrency") == "cny")
        settings.setManualExchangeRate(7.1, for: .cny)
        #expect(defaults.dictionary(forKey: "settings.manualExchangeRates") as? [String: Double] == ["CNY": 7.1])
        settings.setManualExchangeRate(nil, for: .cny)
        #expect(defaults.dictionary(forKey: "settings.manualExchangeRates") as? [String: Double] == [:])
        settings.menuBarAccount = "claudeCode"
        #expect(defaults.string(forKey: "settings.menuBarAccount") == "claudeCode")
        settings.menuBarAccount = nil
        #expect(defaults.object(forKey: "settings.menuBarAccount") == nil)

        settings.deepSeekBasis = .budget
        #expect(defaults.string(forKey: "settings.deepSeekBasis") == "budget")
        settings.deepSeekBudget = 42
        #expect(defaults.object(forKey: "settings.deepSeekBudget") as? Double == 42)
        settings.deepSeekCurrency = "CNY"
        #expect(defaults.string(forKey: "settings.deepSeekCurrency") == "CNY")
        settings.qoderSite = .china
        #expect(defaults.string(forKey: "settings.qoderSite") == "china")
        settings.stepFunSite = .international
        #expect(defaults.string(forKey: "settings.stepFunSite") == StepFunSite.international.rawValue)

        // The v2 key: the old one held a fixed number of seconds.
        settings.refreshInterval = .fiveMinutes
        #expect(defaults.object(forKey: "settings.refreshInterval.v2") as? Int == 300)
        settings.panelSize = .large
        #expect(defaults.string(forKey: "settings.panelSize") == "large")
        settings.railSpacing = .roomy
        #expect(defaults.string(forKey: "settings.railSpacing") == "roomy")
        settings.usageBarStyle = .segmented
        #expect(defaults.string(forKey: "settings.usageBarStyle") == "segmented")
        settings.windowClockDirection = .remaining
        #expect(defaults.string(forKey: "settings.windowClockDirection") == "remaining")
        settings.warningThreshold = .ninety
        #expect(defaults.object(forKey: "settings.warningThreshold") as? Int == 90)
        settings.glassTransparency = 0.25
        #expect(defaults.object(forKey: "settings.glassTransparency") as? Double == 0.25)

        settings.spendSpan = .quarter
        #expect(defaults.string(forKey: "settings.spendSpan") == "quarter")
        settings.spendActivityView = .weekly
        #expect(defaults.string(forKey: "settings.spendActivityView") == "weekly")

        settings.alertThreshold = .ninetyFive
        #expect(defaults.object(forKey: "settings.alertThreshold") as? Int == 95)
        settings.recapAnnouncedMonth = "2026-09"
        #expect(defaults.string(forKey: "settings.recapAnnouncedMonth") == "2026-09")
        settings.recapMonthlyPrice = 20
        #expect(defaults.object(forKey: "settings.recapMonthlyPrice") as? Double == 20)
        settings.recapMonthlyPrice = nil
        #expect(defaults.object(forKey: "settings.recapMonthlyPrice") == nil)

        let shortcut = GlobalShortcut(keyCode: 35, modifiers: [.command, .option])
        settings.openSettingsShortcut = shortcut
        #expect(defaults.string(forKey: "settings.openSettingsShortcut") == shortcut?.storage)
        settings.togglePanelShortcut = shortcut
        #expect(defaults.string(forKey: "settings.togglePanelShortcut") == shortcut?.storage)

        settings.primerHours = PrimerHours(start: 9, end: 17)
        #expect(defaults.object(forKey: "settings.primerStart") as? Int == 9)
        #expect(defaults.object(forKey: "settings.primerEnd") as? Int == 17)
    }

    @Test("Per-account tables and sets are stored under their own keys")
    func tables() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        settings.serverAddresses = ["sub2api": "https://example.test"]
        #expect(defaults.dictionary(forKey: "settings.serverAddresses") as? [String: String] == ["sub2api": "https://example.test"])
        settings.lowBalanceAlerts = ["deepSeek": 5]
        #expect(defaults.dictionary(forKey: "settings.lowBalanceAlerts") as? [String: Double] == ["deepSeek": 5])
        settings.balanceBases = ["newAPI": "budget"]
        #expect(defaults.dictionary(forKey: "settings.balanceBases") as? [String: String] == ["newAPI": "budget"])
        settings.balanceBudgets = ["newAPI": 10]
        #expect(defaults.dictionary(forKey: "settings.balanceBudgets") as? [String: Double] == ["newAPI": 10])
        settings.pinnedWindows = ["codex": "weekly"]
        #expect(defaults.dictionary(forKey: "settings.pinnedWindows") as? [String: String] == ["codex": "weekly"])
        settings.sources = ["codex": "usage"]
        #expect(defaults.dictionary(forKey: "settings.sources") as? [String: String] == ["codex": "usage"])
        settings.sessionBrowsers = ["devin": "chrome"]
        #expect(defaults.dictionary(forKey: "settings.sessionBrowsers") as? [String: String] == ["devin": "chrome"])
        settings.ringTints = ["codex": "#112233"]
        #expect(defaults.dictionary(forKey: "settings.ringTints") as? [String: String] == ["codex": "#112233"])
        settings.providerOrder = ["codex", "claudeCode"]
        #expect(defaults.stringArray(forKey: "settings.providerOrder") == ["codex", "claudeCode"])
        settings.splitAccounts = ["antigravity"]
        #expect(defaults.stringArray(forKey: "settings.splitAccounts") == ["antigravity"])
        settings.primedProviders = ["codex"]
        #expect(defaults.stringArray(forKey: "settings.primedProviders") == ["codex"])
        settings.setShowsDetailedCard(true, for: AccountKey(.codex))
        #expect(defaults.stringArray(forKey: "settings.detailedCards") == ["codex"])
        settings.setShowsRobot(true, for: AccountKey(.codex))
        #expect(defaults.stringArray(forKey: "settings.robotAccounts") == ["codex"])
        // A key of its own: the removed mark's is never read or written.
        #expect(defaults.object(forKey: "settings.botMarks") == nil)
        settings.setRobotColour(Color(red: 1, green: 0, blue: 0), for: AccountKey(.codex))
        #expect(defaults.dictionary(forKey: "settings.robotColours") as? [String: String] == ["codex": "#FF0000"])
        settings.setRobotPersonality(.calm, for: AccountKey(.codex))
        #expect(defaults.dictionary(forKey: "settings.robotPersonalities") as? [String: String] == ["codex": "calm"])
        settings.setRobotShape(.square, for: AccountKey(.codex))
        #expect(defaults.dictionary(forKey: "settings.robotShapes") as? [String: String] == ["codex": "square"])
        // Back to the defaults stores nothing.
        settings.setRobotPersonality(nil, for: AccountKey(.codex))
        settings.setRobotShape(.standard, for: AccountKey(.codex))
        #expect(defaults.dictionary(forKey: "settings.robotPersonalities") as? [String: String] == [:])
        #expect(defaults.dictionary(forKey: "settings.robotShapes") as? [String: String] == [:])
        for old in ["settings.botPersonas", "settings.botColours", "settings.botShapes"] {
            #expect(defaults.object(forKey: old) == nil)
        }
        settings.enabledAccounts = ["codex"]
        #expect(defaults.stringArray(forKey: "settings.enabledProviders") == ["codex"])

        let extra = settings.addAccount(.claudeCode, label: "Work", slot: "work")
        let stored = defaults.data(forKey: "settings.extraAccounts")
            .flatMap { try? JSONDecoder().decode([ExtraAccount].self, from: $0) }
        #expect(stored?.map(\.key) == [extra])

        settings.recordPrimerRun(for: .codex, outcome: .sent, at: Date(timeIntervalSince1970: 100))
        #expect(defaults.dictionary(forKey: "settings.primerRunTimes") as? [String: Double] == ["codex": 100])
        #expect(defaults.dictionary(forKey: "settings.primerRunOutcomes") as? [String: String] == ["codex": WindowStarter.Outcome.sent.rawValue])
    }

    @Test("What was written is what a relaunch restores")
    func roundTrip() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }
        let first = AppSettings(defaults: defaults)

        first.isPanelVisible = false
        first.hidesMenuBarIcon = true
        first.showsDockIconInSettings = false
        first.showsUsageInMenuBar = true
        first.showsMenuDashboard = true
        first.menuBarAccount = "codex"
        first.menuBarStyle = .ring
        first.displayCurrency = .jpy
        first.setManualExchangeRate(150, for: .jpy)
        first.hidesInFullScreen = false
        first.followsActiveDisplay = true
        first.openSettingsShortcut = GlobalShortcut(keyCode: 35, modifiers: [.command, .option])
        first.togglePanelShortcut = GlobalShortcut(keyCode: 36, modifiers: [.control])
        first.deepSeekBasis = .budget
        first.deepSeekBudget = 42
        first.deepSeekCurrency = "CNY"
        first.qoderSite = .china
        first.stepFunSite = .international
        first.serverAddresses = ["sub2api": "https://example.test"]
        first.lowBalanceAlerts = ["deepSeek": 5]
        first.enabledAccounts = ["codex", "claudeCode"]
        first.providerOrder = ["codex", "claudeCode"]
        first.pinnedWindows = ["codex": "weekly"]
        first.sources = ["codex": "endpoint"]
        first.sessionBrowsers = ["devin": "chrome"]
        first.ringTints = ["codex": "#112233"]
        first.refreshInterval = .fiveMinutes
        first.autoCollapse = false
        first.panelSize = .large
        first.railSpacing = .roomy
        first.usageBarStyle = .segmented
        first.usesGlass = true
        first.glassTransparency = 0.25
        first.usesLightPanel = true
        first.topRailShowsPercentages = true
        first.sideRailShowsPercentages = false
        first.labelAboveRing = true
        first.freeAcrossFiguresBeside = true
        first.usesRoundEnds = true
        first.showsWindowClock = true
        first.windowClockDirection = .remaining
        first.showsRemaining = true
        first.warningThreshold = .ninety
        first.dockShowsAlertColor = false
        first.showsForecast = true
        first.showsSecondRing = true
        first.animatesRingActivity = false
        first.splitAccounts = ["antigravity"]
        first.spendSpan = .quarter
        first.spendActivityView = .weekly
        first.readsTokenSpend = true
        first.alertThreshold = .ninetyFive
        first.alertsOnReset = true
        first.alertsOnFailure = true
        first.alertsOnOutage = true
        first.alertsOnRecap = true
        first.recapAnnouncedMonth = "2026-09"
        first.recapMonthlyPrice = 20
        first.recapHidesProjects = true
        first.showsCodexResetCredits = true
        first.balanceBases = ["newAPI": "budget"]
        first.balanceBudgets = ["newAPI": 10]
        first.detailedCards = ["codex"]
        first.robotAccounts = ["claudeCode"]
        first.robotColours = ["claudeCode": "#4A90E2"]
        first.robotPersonalities = ["claudeCode": "lively"]
        first.robotShapes = ["claudeCode": "round"]
        first.primedProviders = ["codex"]
        first.primerHours = PrimerHours(start: 9, end: 17)
        first.recordPrimerRun(for: .codex, outcome: .sent, at: Date(timeIntervalSince1970: 100))
        let extra = first.addAccount(.claudeCode, label: "Work", slot: "work")

        let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())

        #expect(back.isPanelVisible == false)
        #expect(back.hidesMenuBarIcon)
        #expect(back.showsDockIconInSettings == false)
        #expect(back.showsUsageInMenuBar)
        #expect(back.showsMenuDashboard)
        #expect(back.menuBarAccount == "codex")
        #expect(back.menuBarStyle == .ring)
        #expect(back.displayCurrency == .jpy)
        #expect(back.manualExchangeRates == ["JPY": 150])
        #expect(back.hidesInFullScreen == false)
        #expect(back.followsActiveDisplay)
        #expect(back.openSettingsShortcut == first.openSettingsShortcut)
        #expect(back.togglePanelShortcut == first.togglePanelShortcut)
        #expect(back.deepSeekBasis == .budget)
        #expect(back.deepSeekBudget == 42)
        #expect(back.deepSeekCurrency == "CNY")
        #expect(back.qoderSite == .china)
        #expect(back.stepFunSite == .international)
        #expect(back.serverAddresses == ["sub2api": "https://example.test"])
        #expect(back.lowBalanceAlerts == ["deepSeek": 5])
        #expect(back.enabledAccounts == first.enabledAccounts.union([extra.id]))
        #expect(back.extraAccounts.map(\.key) == [extra])
        #expect(back.providerOrder == first.providerOrder)
        #expect(back.pinnedWindows == ["codex": "weekly"])
        #expect(back.sources == ["codex": "endpoint"])
        #expect(back.sessionBrowsers == ["devin": "chrome"])
        #expect(back.ringTints == ["codex": "#112233"])
        #expect(back.refreshInterval == .fiveMinutes)
        #expect(back.autoCollapse == false)
        #expect(back.panelSize == .large)
        #expect(back.railSpacing == .roomy)
        #expect(back.usageBarStyle == .segmented)
        #expect(back.usesGlass)
        #expect(back.glassTransparency == 0.25)
        #expect(back.usesLightPanel)
        #expect(back.topRailShowsPercentages)
        #expect(back.sideRailShowsPercentages == false)
        #expect(back.labelAboveRing)
        #expect(back.freeAcrossFiguresBeside)
        #expect(back.usesRoundEnds)
        #expect(back.showsWindowClock)
        #expect(back.windowClockDirection == .remaining)
        #expect(back.showsRemaining)
        #expect(back.warningThreshold == .ninety)
        #expect(back.dockShowsAlertColor == false)
        #expect(back.showsForecast)
        #expect(back.showsSecondRing)
        #expect(back.animatesRingActivity == false)
        #expect(back.splitAccounts == ["antigravity"])
        #expect(back.spendSpan == .quarter)
        #expect(back.spendActivityView == .weekly)
        #expect(back.readsTokenSpend)
        #expect(back.alertThreshold == .ninetyFive)
        #expect(back.alertsOnReset)
        #expect(back.alertsOnFailure)
        #expect(back.alertsOnOutage)
        #expect(back.alertsOnRecap)
        #expect(back.recapAnnouncedMonth == "2026-09")
        #expect(back.recapMonthlyPrice == 20)
        #expect(back.recapHidesProjects)
        #expect(back.showsCodexResetCredits)
        #expect(back.balanceBases == ["newAPI": "budget"])
        #expect(back.balanceBudgets == ["newAPI": 10])
        #expect(back.detailedCards == ["codex"])
        #expect(back.robotAccounts == ["claudeCode"])
        #expect(back.robotColours == ["claudeCode": "#4A90E2"])
        #expect(back.robotPersonality(for: AccountKey(.claudeCode)) == .lively)
        #expect(back.robotShape(for: AccountKey(.claudeCode)) == .round)
        #expect(back.primedProviders == ["codex"])
        #expect(back.primerHours == PrimerHours(start: 9, end: 17))
        #expect(back.lastPrimerRun(for: .codex)?.outcome == .sent)
        #expect(back.lastPrimerRun(for: .codex)?.date == Date(timeIntervalSince1970: 100))
        // The restoring instance is not the app's own: it never moves the
        // globals the running panel is measured from.
        #expect(back.drivesPanelMetrics == false)
    }

    @Test("Nothing stored restores every shipped default")
    func emptyDefaultsRestoreTheDefaults() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }

        let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())
        let fresh = AppSettings(defaults: defaults)

        #expect(back.isPanelVisible == fresh.isPanelVisible)
        #expect(back.hidesMenuBarIcon == false)
        #expect(back.showsDockIconInSettings)
        #expect(back.hidesInFullScreen)
        #expect(back.followsActiveDisplay == false)
        #expect(back.qoderSite == fresh.qoderSite)
        #expect(back.stepFunSite == fresh.stepFunSite)
        #expect(back.autoCollapse)
        #expect(back.usesGlass == false)
        #expect(back.glassTransparency == fresh.glassTransparency)
        #expect(back.usesLightPanel == false)
        #expect(back.topRailShowsPercentages == false)
        #expect(back.sideRailShowsPercentages)
        #expect(back.showsForecast == false)
        #expect(back.dockShowsAlertColor)
        #expect(back.animatesRingActivity)
        #expect(back.readsTokenSpend == false)
        #expect(back.alertThreshold == .off)
        #expect(back.alertsOnReset == false)
        #expect(back.alertsOnFailure == false)
        #expect(back.alertsOnOutage == false)
        #expect(back.alertsOnRecap == false)
        #expect(back.primerHours == .default)
        #expect(!back.wantsAlerts)
    }

    @Test("A ring pinned to Qoder's total survives a relaunch with the parts on (#89)")
    func qoderTotalPinSurvivesRelaunch() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }
        defaults.set(true, forKey: "settings.qoderShowsParts")
        defaults.set(["qoder": "qoder.credits"], forKey: "settings.pinnedWindows")

        let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())

        #expect(back.qoderShowsParts)
        #expect(back.pinnedWindows["qoder"] == "qoder.credits")
        #expect((defaults.dictionary(forKey: "settings.pinnedWindows") as? [String: String])?["qoder"] == "qoder.credits")

        // Turning the parts on by hand still frees the total's pin (#76).
        back.qoderShowsParts = false
        back.qoderShowsParts = true
        #expect(back.pinnedWindows["qoder"] == nil)
    }

    @Test("The enabled set refuses to go empty")
    func enabledSetStaysNonEmpty() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(enabledAccounts: ["codex"], defaults: defaults)

        settings.enabledAccounts = []

        #expect(settings.enabledAccounts == ["codex"])
    }

    @Test("Glass transparency is clamped to 0...1")
    func glassTransparencyClamps() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        settings.glassTransparency = 3
        #expect(settings.glassTransparency == 1)
        settings.glassTransparency = -2
        #expect(settings.glassTransparency == 0)
    }

    @Test("A recap price that is not a positive amount is dropped")
    func recapPriceNormalised() {
        let (defaults, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        settings.recapMonthlyPrice = -5
        #expect(settings.recapMonthlyPrice == nil)
        settings.recapMonthlyPrice = 30
        #expect(settings.recapMonthlyPrice == 30)
    }
}
