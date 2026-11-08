// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Builds the readings only when their observed inputs change. The child owns
/// pointer/card state and shares these entries across layout and hit testing.
struct FloatingUsagePanelView: View {
    let store: UsageStore
    let settings: AppSettings
    let placement: PanelPlacement

    /// The clock arc moves to the minute even when quota refresh backs off.
    @State private var minute = Date()

    var body: some View {
        // Formatting reads the selected language through a plain function.
        let _ = settings.language
        let entries = entries
        FloatingUsagePanelContent(store: store, settings: settings, entries: entries, placement: placement)
            .task(id: settings.showsWindowClock) {
                guard settings.showsWindowClock else { return }
                while !Task.isCancelled {
                    minute = Date()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
    }

    /// Only the providers switched on in settings, so the rail shrinks when
    /// one is turned off.
    private var entries: [RailEntry] {
        Self.spreadingRobots(railEntries, settings: settings)
    }

    /// Every robot's colour and personality, decided across the rail at once:
    /// a chosen colour, else the product's own, else a wheel colour far from
    /// its neighbours; a chosen personality, else one that differs from them.
    static func spreadingRobots(_ entries: [RailEntry], settings: AppSettings) -> [RailEntry] {
        let robots = entries.indices.filter { entries[$0].robot != nil }
        let accounts = robots.map { entries[$0].slot.account }
        let inks = RobotAutomatic.inks(for: accounts.map(\.provider),
                                       custom: accounts.map { RobotInk(hex: settings.robotColours[$0.id]) })
        let personalities = RobotAutomatic.spread(accounts.map(settings.robotPersonality(for:)),
                                                  over: RobotAutomatic.personalities)
        var entries = entries
        for (n, index) in robots.enumerated() {
            entries[index].robot?.ink = inks[n].ink
            entries[index].robot?.inkIsChosen = inks[n].chosen
            entries[index].robot?.personality = personalities[n]
        }
        return entries
    }

    private var railEntries: [RailEntry] {
        RailSlot.rail(
            for: settings.shownAccounts,
            isSplit: settings.isSplit,
            groups: { RailSlot.modelGroups(of: store.usage(for: $0)) },
            shown: settings.shownModelGroups(for:)
        ).map { slot in
            let usage = store.usage(for: slot.account)
            return entry(
                for: slot,
                usage: slot.group.map { Self.usage(usage, keeping: $0) } ?? usage
            )
        }
    }

    /// The same reading with only one group's limits in it, so every figure
    /// downstream — the ring, the card, the second ring — is about that group.
    private static func usage(_ usage: ProviderUsage, keeping group: String) -> ProviderUsage {
        ProviderUsage(
            account: usage.account,
            windows: usage.windows.filter { $0.scope == group },
            observedAt: usage.observedAt,
            state: usage.state,
            plan: usage.plan,
            creditBalance: usage.creditBalance
        )
    }

    private func entry(for slot: RailSlot, usage: ProviderUsage) -> RailEntry {
        let account = slot.account
        let label = settings.label(for: account)
        let pinned = settings.pinnedWindow(for: account)
        let headline = usage.headlineWindow(preferring: pinned)

        // An unavailable reading must not draw remembered money as current.
        let figure: String? = if headline == nil, case .unavailable = usage.state {
            nil
        } else if headline == nil {
            usage.creditRemaining?.railText() ?? usage.creditBalance
        } else {
            nil
        }

        return RailEntry(
            usage: usage,
            headline: headline,
            // Activity is per provider: transcripts do not identify accounts.
            isRunning: store.isRunning(account.provider),
            isRefreshing: store.isRefreshing(account),
            tint: settings.ringTint(for: account),
            slot: slot,
            title: slot.group.map { "\(label) · \($0)" } ?? label,
            windowClock: settings.showsWindowClock
                ? headline?.windowClockFraction(direction: settings.windowClockDirection, at: minute)
                : nil,
            figure: figure,
            second: settings.showsSecondRing ? usage.secondWindow(preferring: pinned) : nil,
            showsRemaining: settings.showsRemaining,
            robot: settings.showsRobot(for: account)
                ? RobotCue(justReset: store.justReset(account),
                           justFinished: store.justFinishedWorking(account.provider),
                           shape: settings.robotShape(for: account))
                : nil,
            iconData: settings.pulseExtension(for: account)?.iconData
        )
    }
}
