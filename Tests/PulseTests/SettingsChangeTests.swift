import Foundation
import Testing
@testable import Pulse

@Suite("Settings change scope", .serialized)
@MainActor
struct SettingsChangeTests {
    /// Settings setters persist immediately. Restore their keys and metrics
    /// after each synchronous probe without touching a real account or key.
    private func preservingSettings(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let saved = defaults.dictionaryRepresentation()
        let size = PanelSize.allCases.first { $0.scale == PanelMetrics.scale }!
        let spacing = RailSpacing.allCases.first { $0.scale == PanelMetrics.spacing }!
        let top = PanelMetrics.topRailShowsPercentages
        let side = PanelMetrics.sideRailShowsPercentages
        let above = PanelMetrics.labelAboveRing
        let round = PanelMetrics.usesRoundEnds
        let forecast = PanelMetrics.showsForecast
        let capacity = PanelMetrics.railCapacity
        defer {
            let keys = Set(saved.keys).union(defaults.dictionaryRepresentation().keys)
            for key in keys where key.hasPrefix("settings.") || key == ProviderSelection.enabledKey {
                defaults.set(saved[key], forKey: key)
            }
            PanelMetrics.use(size)
            PanelMetrics.use(spacing)
            PanelMetrics.showTopPercentages(top)
            PanelMetrics.showSidePercentages(side)
            PanelMetrics.putLabelAboveRing(above)
            PanelMetrics.useRoundEnds(round)
            PanelMetrics.showForecast(forecast)
            PanelMetrics.makeRoom(for: capacity)
        }
        body()
    }

    @Test("Appearance updates reach AppKit without starting a refresh")
    func appearanceDoesNotRefresh() {
        preservingSettings {
            let settings = AppSettings(enabledAccounts: [Provider.deepSeek.rawValue])
            let store = UsageStore(settings: settings, activity: AgentActivityMonitor { _ in [:] })
            defer { store.stop() }
            var changes: [AppSettings.Change] = []
            settings.onChange = { change in
                changes.append(change)
                store.settingsChanged(change)
            }
            let edits: [(AppSettings) -> Void] = [
                { $0.panelSize = .large }, { $0.railSpacing = .compact },
                { $0.usesRoundEnds = true }, { $0.usesGlass = true },
                { $0.topRailShowsPercentages = true }, { $0.sideRailShowsPercentages = false },
                { $0.labelAboveRing = true }, { $0.showsForecast = true },
                { $0.showsSecondRing = true }, { $0.autoCollapse = false },
                { $0.hidesInFullScreen = false }, { $0.followsActiveDisplay = true },
                { $0.pinnedWindows = [Provider.deepSeek.rawValue: "balance"] },
                { $0.splitAccounts = [Provider.antigravity.rawValue] }
            ]
            for edit in edits {
                changes.removeAll()
                edit(settings)
                #expect(changes == [.appearance])
                #expect(!store.isRefreshing)
                #expect(store.diagnostics.isEmpty)
                edit(settings)
                #expect(changes == [.appearance], "Writing the same value must not notify again")
            }
            #expect(PanelMetrics.scale == PanelSize.large.scale)
            #expect(PanelMetrics.spacing == RailSpacing.compact.scale)
        }
    }

    @Test("Changing a source or gateway address names only changed accounts, including removals")
    func accountInputsAreScoped() {
        preservingSettings {
            let first = AccountKey(.claudeCode)
            let second = AccountKey(.claudeCode, slot: "synthetic")
            let settings = AppSettings(sources: [first.id: UsageSource.tooling.rawValue, second.id: UsageSource.automatic.rawValue])
            var changes: [AppSettings.Change] = []
            settings.onChange = { changes.append($0) }
            settings.sources[first.id] = UsageSource.desktopApp.rawValue
            settings.sources[first.id] = nil
            settings.serverAddresses = [Provider.sub2api.rawValue: "https://example.test"]
            #expect(changes == [.usage([first]), .usage([first]), .usage([AccountKey(.sub2api)])])
        }
    }

    @Test("Provider-specific settings do not ask unrelated providers")
    func providerInputsAreScoped() {
        preservingSettings {
            let settings = AppSettings()
            var changes: [AppSettings.Change] = []
            settings.onChange = { changes.append($0) }
            settings.deepSeekBasis = .budget
            settings.deepSeekBudget = 10
            settings.deepSeekCurrency = "USD"
            settings.qoderSite = .china
            #expect(changes == [
                .usage([AccountKey(.deepSeek)]), .usage([AccountKey(.deepSeek)]),
                .usage([AccountKey(.deepSeek)]), .usage([AccountKey(.qoder)])
            ])
        }
    }

    @Test("Selection refreshes newly enabled accounts; disabling and renaming do not")
    func accountMembership() {
        preservingSettings {
            let first = AccountKey(.deepSeek)
            let added = ExtraAccount(provider: .codex, slot: "synthetic", label: "Before")
            let settings = AppSettings(enabledAccounts: [first.id], extraAccounts: [added])
            var changes: [AppSettings.Change] = []
            settings.onChange = { changes.append($0) }
            settings.enabledAccounts.insert(added.id)
            settings.enabledAccounts.remove(first.id)
            settings.extraAccounts[0].label = "After"
            #expect(changes == [.accounts(added: [added.key]), .accounts(added: []), .appearance])
        }
    }

    @Test("Adding an account requests one first read after it becomes enabled")
    func addedAccountNotification() {
        preservingSettings {
            let settings = AppSettings(enabledAccounts: [Provider.deepSeek.rawValue])
            var requested: [AccountKey] = []
            settings.onChange = { change in
                if case .accounts(let added) = change { requested.append(contentsOf: added) }
            }
            let account = settings.addAccount(.codex, label: "Synthetic", slot: "synthetic")
            #expect(requested == [account])
            #expect(settings.shownAccounts.contains(account))
        }
    }

    @Test("Changing the interval reschedules without starting a request")
    func intervalDoesNotRefresh() {
        preservingSettings {
            let settings = AppSettings(enabledAccounts: [Provider.deepSeek.rawValue])
            let store = UsageStore(settings: settings, activity: AgentActivityMonitor { _ in [:] })
            defer { store.stop() }
            var changes: [AppSettings.Change] = []
            settings.onChange = { change in
                changes.append(change)
                store.settingsChanged(change)
            }
            settings.refreshInterval = .fiveMinutes
            #expect(changes == [.refreshInterval])
            #expect(store.currentInterval == 300)
            #expect(!store.isRefreshing)
            #expect(store.diagnostics.isEmpty)
        }
    }
}
