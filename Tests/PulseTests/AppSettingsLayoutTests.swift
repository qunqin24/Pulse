import Foundation
import Testing
@testable import Pulse

/// A setting that only changes how the panel is drawn must not ask the usage
/// loop to do anything. `AppDelegate` answers `onChange` by re-placing the panel
/// **and** refreshing every provider (`UsageStore.settingsChanged`), so a size,
/// spacing or glass change routed there cost a request per provider for figures
/// that had not moved. Layout settings go through `onLayoutChange`, which
/// `AppDelegate` answers by re-placing the panel and nothing else.
///
/// The tests stop at `AppSettings`: which callback a setting fires is the whole
/// of the difference, and `AppDelegate` is only wired by launching the app.
@Suite("AppSettings layout callbacks")
@MainActor
struct AppSettingsLayoutTests {
    /// What each setting did to the two callbacks.
    private struct Calls {
        var change = 0
        var layout = 0
    }

    private final class Counter {
        var calls = Calls()
    }

    /// Fresh settings on an isolated suite, with both callbacks counted.
    private func counted() -> (AppSettings, Counter, cleanup: () -> Void) {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        let counter = Counter()
        settings.onChange = { counter.calls.change += 1 }
        settings.onLayoutChange = { counter.calls.layout += 1 }
        return (settings, counter, cleanup)
    }

    /// Every setting that only changes how the panel looks or where it sits,
    /// each moved off its default.
    private static let layoutSettings: [(name: String, change: (AppSettings) -> Void)] = [
        ("panelSize", { $0.panelSize = .large }),
        ("railSpacing", { $0.railSpacing = .roomy }),
        ("usageBarStyle", { $0.usageBarStyle = .segmented }),
        ("topRailShowsPercentages", { $0.topRailShowsPercentages = true }),
        ("sideRailShowsPercentages", { $0.sideRailShowsPercentages = false }),
        ("labelAboveRing", { $0.labelAboveRing = true }),
        ("freeAcrossFiguresBeside", { $0.freeAcrossFiguresBeside = true }),
        ("usesRoundEnds", { $0.usesRoundEnds = true }),
        ("showsWindowClock", { $0.showsWindowClock = true }),
        ("showsForecast", { $0.showsForecast = true }),
        ("detailedCards", { $0.setShowsDetailedCard(true, for: AccountKey(.codex)) }),
        ("usesGlass", { $0.usesGlass = true }),
        ("usesLightPanel", { $0.usesLightPanel = true }),
        ("autoCollapse", { $0.autoCollapse = false }),
        ("hidesInFullScreen", { $0.hidesInFullScreen = false }),
        ("hidesFromScreenCapture", { $0.hidesFromScreenCapture = true }),
        ("followsActiveDisplay", { $0.followsActiveDisplay = true }),
        ("snapsToEdges", { $0.snapsToEdges = false }),
        ("liquidDocking", { $0.liquidDocking = true }),
        ("showsSecondRing", { $0.showsSecondRing = true })
    ]

    @Test("Layout settings re-place the panel and do not refresh providers")
    func layoutSettingsDoNotRefresh() {
        for (name, change) in Self.layoutSettings {
            let (settings, counter, cleanup) = counted()
            defer { cleanup() }

            change(settings)

            #expect(counter.calls.layout == 1, "\(name) should re-place the panel once")
            #expect(counter.calls.change == 0, "\(name) must not refresh every provider")
        }
    }

    @Test("A layout setting set to the value it already has announces nothing")
    func unchangedLayoutSettingIsSilent() {
        for (name, change) in Self.layoutSettings {
            let (settings, counter, cleanup) = counted()
            defer { cleanup() }

            change(settings)
            change(settings)

            #expect(counter.calls.layout == 1, "\(name) fired again for the same value")
            #expect(counter.calls.change == 0, "\(name)")
        }
    }

    @Test("Layout settings are written whichever callback is wired")
    func layoutSettingsStillPersist() {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        settings.panelSize = .small
        settings.railSpacing = .compact

        #expect(defaults.string(forKey: "settings.panelSize") == "small")
        #expect(defaults.string(forKey: "settings.railSpacing") == "compact")
    }

    @Test("Settings that change what is fetched still refresh every provider")
    func dataSettingsStillRefresh() {
        let changes: [(name: String, change: (AppSettings) -> Void)] = [
            ("isPanelVisible", { $0.isPanelVisible = false }),
            ("enabledAccounts", { $0.enabledAccounts = ["codex"] }),
            ("sources", { $0.setSource(.endpoint, for: AccountKey(.codex)) }),
            ("refreshInterval", { $0.refreshInterval = .fiveMinutes }),
            ("qoderSite", { $0.qoderSite = .china }),
            ("stepFunSite", { $0.stepFunSite = .international }),
            ("deepSeekBasis", { $0.deepSeekBasis = .budget }),
            ("serverAddresses", { $0.setServerAddress("https://example.test", for: AccountKey(.sub2api)) }),
            ("balanceBases", { $0.setBalanceBasis(.budget, for: AccountKey(.newAPI)) }),
            ("splitAccounts", { $0.setSplit(true, for: AccountKey(.antigravity)) }),
            ("pinnedWindows", { $0.setPinnedWindow("weekly", for: AccountKey(.codex)) }),
            ("addAccount", { $0.addAccount(.claudeCode, label: "Work", slot: "work") })
        ]
        for (name, change) in changes {
            let (settings, counter, cleanup) = counted()
            defer { cleanup() }

            change(settings)

            #expect(counter.calls.change >= 1, "\(name) should still ask the usage loop to refresh")
            #expect(counter.calls.layout == 0, "\(name) is not a layout setting")
        }
    }

    @Test("Settings that were already callback-free stay that way")
    func quietSettingsStayQuiet() {
        let (settings, counter, cleanup) = counted()
        defer { cleanup() }

        settings.glassTransparency = 0.1
        settings.showsRemaining = true
        settings.warningThreshold = .ninety
        settings.dockShowsAlertColor = false
        settings.animatesRingActivity = false
        settings.setRingTint(nil, for: AccountKey(.codex))
        settings.spendSpan = .month
        settings.readsTokenSpend = true
        settings.alertThreshold = .ninety
        settings.alertsOnReset = true
        settings.resetOrder()
        settings.providerOrder = ["codex"]

        #expect(counter.calls.change == 0)
        #expect(counter.calls.layout == 0)
    }
}
