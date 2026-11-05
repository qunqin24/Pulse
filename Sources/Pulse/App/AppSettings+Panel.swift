// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

// The floating panel: whether it is shown, where it may go, how big it is, and
// everything about the rail that changes its length or thickness.
//
// **Two callbacks, chosen on purpose.** Showing or hiding the panel goes
// through `onChange` — it also starts and stops the activity watcher, which
// `UsageStore.settingsChanged` takes care of. Everything else here is layout
// or appearance, and goes through `onLayoutChange`, which re-places the panel
// and **does not refresh a single provider**. They all used to share
// `onChange`, so choosing a panel size cost every provider a request for
// figures that had not moved (`AppSettingsLayoutTests`).
//
// **The `PanelMetrics` ones set the metric before announcing the change.**
// Whoever reacts is about to measure the panel, and it has to already be the
// new size when they do. Only the settings the running app is drawn from move
// those globals (`drivesPanelMetrics`).

extension AppSettings.Key {
    static let panelVisible = "settings.panelVisible"
    static let hidesInFullScreen = "settings.hidesInFullScreen"
    static let hidesFromScreenCapture = "settings.hidesFromScreenCapture"
    static let followsActiveDisplay = "settings.followsActiveDisplay"
    static let snapsToEdges = "settings.snapsToEdges"
    static let liquidDocking = "settings.liquidDocking"
    static let panelSize = "settings.panelSize"
    static let railSpacing = "settings.railSpacing"
    static let topRailShowsPercentages = "settings.topRailShowsPercentages"
    static let sideRailShowsPercentages = "settings.sideRailShowsPercentages"
    static let labelAboveRing = "settings.labelAboveRing"
    static let freeAcrossFiguresBeside = "settings.freeAcrossFiguresBeside"
    static let usesRoundEnds = "settings.usesRoundEnds"
    static let showsWindowClock = "settings.showsWindowClock"
    static let showsForecast = "settings.showsForecast"
    static let usageBarStyle = "settings.usageBarStyle"
    static let detailedCards = "settings.detailedCards"
    static let usesGlass = "settings.usesGlass"
    static let glassTransparency = "settings.glassTransparency"
    static let usesLightPanel = "settings.usesLightPanel"
    static let autoCollapse = "settings.autoCollapse"
    static let splitAccounts = "settings.splitAccounts"
    static let shownModelGroups = "settings.shownModelGroups"
    /// New with the CX ArtLab robot. The removed mark's `settings.botMarks`
    /// is left alone and read by nothing (Docs/decisions/bot-mark-removed.md).
    static let robotAccounts = "settings.robotAccounts"
    static let robotColours = "settings.robotColours"
    static let robotPersonalities = "settings.robotPersonalities"
    static let robotShapes = "settings.robotShapes"
}

extension AppSettings.Default {
    static let isPanelVisible = true
    static let hidesInFullScreen = true
    static let hidesFromScreenCapture = false
    static let followsActiveDisplay = false
    static let snapsToEdges = true
    static let liquidDocking = false
    static let topRailShowsPercentages = false
    static let sideRailShowsPercentages = true
    static let labelAboveRing = false
    static let freeAcrossFiguresBeside = false
    static let usesRoundEnds = false
    static let showsWindowClock = false
    static let showsForecast = false
    static let usesGlass = false
    static let glassTransparency = PanelGlass.defaultTransparency
    static let usesLightPanel = false
    static let autoCollapse = true
}

extension AppSettings {
    func isPanelVisibleChanged(from old: Bool) {
        guard isPanelVisible != old else { return }
        defaults.set(isPanelVisible, forKey: Key.panelVisible)
        onChange?()
    }

    func hidesInFullScreenChanged(from old: Bool) {
        guard hidesInFullScreen != old else { return }
        defaults.set(hidesInFullScreen, forKey: Key.hidesInFullScreen)
        onLayoutChange?()
    }

    func hidesFromScreenCaptureChanged(from old: Bool) {
        guard hidesFromScreenCapture != old else { return }
        defaults.set(hidesFromScreenCapture, forKey: Key.hidesFromScreenCapture)
        onLayoutChange?()
    }

    func followsActiveDisplayChanged(from old: Bool) {
        guard followsActiveDisplay != old else { return }
        defaults.set(followsActiveDisplay, forKey: Key.followsActiveDisplay)
        onLayoutChange?()
    }

    /// Re-places the panel: a free upright rail is kept off the sides only
    /// while snapping is on (`PanelPlacement.sideMargin`).
    func snapsToEdgesChanged(from old: Bool) {
        guard snapsToEdges != old else { return }
        defaults.set(snapsToEdges, forKey: Key.snapsToEdges)
        onLayoutChange?()
    }

    func liquidDockingChanged(from old: Bool) {
        guard liquidDocking != old else { return }
        defaults.set(liquidDocking, forKey: Key.liquidDocking)
        onLayoutChange?()
    }

    func panelSizeChanged(from old: PanelSize) {
        guard panelSize != old else { return }
        if drivesPanelMetrics { PanelMetrics.use(panelSize) }
        defaults.set(panelSize.rawValue, forKey: Key.panelSize)
        onLayoutChange?()
    }

    func railSpacingChanged(from old: RailSpacing) {
        guard railSpacing != old else { return }
        if drivesPanelMetrics { PanelMetrics.use(railSpacing) }
        defaults.set(railSpacing.rawValue, forKey: Key.railSpacing)
        onLayoutChange?()
    }

    /// Changes the rail's thickness along the top.
    func topRailShowsPercentagesChanged(from old: Bool) {
        guard topRailShowsPercentages != old else { return }
        if drivesPanelMetrics { PanelMetrics.showTopPercentages(topRailShowsPercentages) }
        defaults.set(topRailShowsPercentages, forKey: Key.topRailShowsPercentages)
        onLayoutChange?()
    }

    /// Makes the rail shorter or longer down a side.
    func sideRailShowsPercentagesChanged(from old: Bool) {
        guard sideRailShowsPercentages != old else { return }
        if drivesPanelMetrics { PanelMetrics.showSidePercentages(sideRailShowsPercentages) }
        defaults.set(sideRailShowsPercentages, forKey: Key.sideRailShowsPercentages)
        onLayoutChange?()
    }

    func labelAboveRingChanged(from old: Bool) {
        guard labelAboveRing != old else { return }
        if drivesPanelMetrics { PanelMetrics.putLabelAboveRing(labelAboveRing) }
        defaults.set(labelAboveRing, forKey: Key.labelAboveRing)
        onLayoutChange?()
    }

    func freeAcrossFiguresBesideChanged(from old: Bool) {
        guard freeAcrossFiguresBeside != old else { return }
        if drivesPanelMetrics { PanelMetrics.putFreeAcrossFiguresBeside(freeAcrossFiguresBeside) }
        defaults.set(freeAcrossFiguresBeside, forKey: Key.freeAcrossFiguresBeside)
        onLayoutChange?()
    }

    func usesRoundEndsChanged(from old: Bool) {
        guard usesRoundEnds != old else { return }
        if drivesPanelMetrics { PanelMetrics.useRoundEnds(usesRoundEnds) }
        defaults.set(usesRoundEnds, forKey: Key.usesRoundEnds)
        onLayoutChange?()
    }

    func showsWindowClockChanged(from old: Bool) {
        guard showsWindowClock != old else { return }
        if drivesPanelMetrics { PanelMetrics.showWindowClock(showsWindowClock) }
        defaults.set(showsWindowClock, forKey: Key.showsWindowClock)
        onLayoutChange?()
    }

    func usageBarStyleChanged(from old: UsageBarStyle) {
        guard usageBarStyle != old else { return }
        if drivesPanelMetrics { PanelMetrics.use(usageBarStyle) }
        defaults.set(usageBarStyle.rawValue, forKey: Key.usageBarStyle)
        onLayoutChange?()
    }

    func showsForecastChanged(from old: Bool) {
        guard showsForecast != old else { return }
        if drivesPanelMetrics { PanelMetrics.showForecast(showsForecast) }
        defaults.set(showsForecast, forKey: Key.showsForecast)
        onLayoutChange?()
    }

    func detailedCardsChanged(from old: Set<String>) {
        guard detailedCards != old else { return }
        // The app's own settings only: a test's `AppSettings` must not
        // resize the frame every other test is measuring.
        if drivesPanelMetrics { PanelMetrics.showDetailedCard(!detailedCards.isEmpty) }
        defaults.set(detailedCards.sorted(), forKey: Key.detailedCards)
        onLayoutChange?()
    }

    func robotAccountsChanged(from old: Set<String>) {
        guard robotAccounts != old else { return }
        defaults.set(robotAccounts.sorted(), forKey: Key.robotAccounts)
        onLayoutChange?()
    }

    func robotColoursChanged(from old: [String: String]) {
        guard robotColours != old else { return }
        defaults.set(robotColours, forKey: Key.robotColours)
        onLayoutChange?()
    }

    func robotPersonalitiesChanged(from old: [String: String]) {
        guard robotPersonalities != old else { return }
        defaults.set(robotPersonalities, forKey: Key.robotPersonalities)
        onLayoutChange?()
    }

    func robotShapesChanged(from old: [String: String]) {
        guard robotShapes != old else { return }
        defaults.set(robotShapes, forKey: Key.robotShapes)
        onLayoutChange?()
    }

    func usesGlassChanged(from old: Bool) {
        guard usesGlass != old else { return }
        defaults.set(usesGlass, forKey: Key.usesGlass)
        onLayoutChange?()
    }

    func usesLightPanelChanged(from old: Bool) {
        guard usesLightPanel != old else { return }
        defaults.set(usesLightPanel, forKey: Key.usesLightPanel)
        onLayoutChange?()
    }

    func autoCollapseChanged(from old: Bool) {
        guard autoCollapse != old else { return }
        defaults.set(autoCollapse, forKey: Key.autoCollapse)
        onLayoutChange?()
    }

    /// **Stays on `onChange`, unlike the rest of this file.** How many rings
    /// a split account has is read off its *reading* (`RailSlot.modelGroups`),
    /// so a refresh is what makes a split show both groups when the reading it
    /// has does not carry them yet.
    func splitAccountsChanged(from old: Set<String>) {
        guard splitAccounts != old else { return }
        // The rail is about to get longer. Before the change is announced,
        // so whoever re-measures the panel sees the size it will be.
        resizeRail()
        defaults.set(Array(splitAccounts), forKey: Key.splitAccounts)
        onChange?()
    }

    func showsDetailedCard(for account: AccountKey) -> Bool {
        detailedCards.contains(account.id)
    }

    func setShowsDetailedCard(_ shows: Bool, for account: AccountKey) {
        if shows { detailedCards.insert(account.id) } else { detailedCards.remove(account.id) }
    }

    func showsRobot(for account: AccountKey) -> Bool {
        robotAccounts.contains(account.id)
    }

    func setShowsRobot(_ shows: Bool, for account: AccountKey) {
        if shows { robotAccounts.insert(account.id) } else { robotAccounts.remove(account.id) }
    }

    /// The robot's own colour, or nil for Automatic. Kept apart from the
    /// ring's colour: the ring's says how much is used, the robot's only tells
    /// robots apart.
    func robotColour(for account: AccountKey) -> Color? {
        RingTint.color(from: robotColours[account.id])
    }

    func setRobotColour(_ colour: Color?, for account: AccountKey) {
        // As with the ring colour, a colour with no sRGB hex keeps the last
        // one rather than falling back to Automatic; only nil clears it.
        guard let colour else {
            robotColours[account.id] = nil
            return
        }
        guard let hex = colour.hexString else { return }
        robotColours[account.id] = hex
    }

    /// The robot's personality, or nil for Automatic.
    func robotPersonality(for account: AccountKey) -> RobotPersonality? {
        robotPersonalities[account.id].flatMap(RobotPersonality.init(rawValue:))
    }

    func setRobotPersonality(_ personality: RobotPersonality?, for account: AccountKey) {
        robotPersonalities[account.id] = personality?.rawValue
    }

    func robotShape(for account: AccountKey) -> RobotShape {
        robotShapes[account.id].flatMap(RobotShape.init(rawValue:)) ?? .standard
    }

    /// The standard shape is stored as nothing, like every other default.
    func setRobotShape(_ shape: RobotShape, for account: AccountKey) {
        robotShapes[account.id] = shape == .standard ? nil : shape.rawValue
    }

    /// Through `onLayoutChange`: the rings change and the rail with them,
    /// and nothing needs fetching again.
    func shownModelGroupsChanged(from old: [String: [String]]) {
        guard shownModelGroups != old else { return }
        resizeRail()
        defaults.set(shownModelGroups, forKey: Key.shownModelGroups)
        onLayoutChange?()
    }

    /// The groups chosen to get a ring, or nil for every group.
    func shownModelGroups(for account: AccountKey) -> [String]? {
        shownModelGroups[account.id]
    }

    /// Whether `group` gets a ring on this account.
    func showsModelGroup(_ group: String, for account: AccountKey) -> Bool {
        shownModelGroups[account.id].map { $0.contains(group) } ?? true
    }

    /// Shows or hides one group's ring. `known` is every group the account's
    /// reading carries, which an unset choice ("every group") stands for.
    /// **The last shown group stays shown:** a split account with no ring
    /// would be an account gone from the rail; switching the split off is
    /// how to have one ring.
    func setShowsModelGroup(_ shows: Bool, _ group: String, known: [String], for account: AccountKey) {
        var chosen = shownModelGroups[account.id] ?? known
        if shows {
            if !chosen.contains(group) { chosen.append(group) }
        } else {
            chosen.removeAll { $0 == group }
            guard !chosen.filter(known.contains).isEmpty else { return }
        }
        var updated = shownModelGroups
        // Every known group shown is the same as no choice, and stored so.
        updated[account.id] = Set(known).isSubset(of: chosen) ? nil : chosen
        shownModelGroups = updated
    }

    func isSplit(_ account: AccountKey) -> Bool {
        account.provider.splitsByModelGroup && splitAccounts.contains(account.id)
    }

    func setSplit(_ split: Bool, for account: AccountKey) {
        var updated = splitAccounts
        if split { updated.insert(account.id) } else { updated.remove(account.id) }
        splitAccounts = updated
    }

    /// Makes room for the rings that are shown. A no-op for any instance but
    /// the app's own — see `drivesPanelMetrics`.
    func resizeRail() {
        guard drivesPanelMetrics else { return }
        PanelMetrics.makeRoom(for: railSlotCount)
    }

    /// How many rings the rail has to have room for.
    ///
    /// **The shown accounts, not every account.** It used to be every one, so
    /// that switching a provider off never resized the window. That stopped
    /// being affordable once there were dozens of providers: the transparent
    /// window was reserving a rail for all of them, thousands of points taller
    /// than any screen, for rings nobody had switched on. Switching one on or
    /// off now resizes the window — from Settings, never while a card is
    /// opening — and `settingsChanged()` re-places it on the way.
    ///
    /// A split account is still counted for the groups it can produce rather
    /// than the groups a reading happens to carry, so a reading never moves
    /// the budget: only a setting does.
    var railSlotCount: Int {
        shownAccounts.reduce(0) { total, account in
            total + (isSplit(account) ? modelGroupBudget(for: account) : 1)
        }
    }

    /// The rings a split account reserves: the groups chosen to show, or as
    /// many as the provider can produce while every group is shown.
    func modelGroupBudget(for account: AccountKey) -> Int {
        let cap = account.provider.modelGroupCount
        return shownModelGroups[account.id].map { min(max($0.count, 1), cap) } ?? cap
    }

    /// Brings `PanelMetrics` in line with what was just restored, before this
    /// instance is allowed to move it.
    func applyPanelMetrics() {
        PanelMetrics.use(panelSize)
        PanelMetrics.use(railSpacing)
        PanelMetrics.showTopPercentages(topRailShowsPercentages)
        PanelMetrics.showSidePercentages(sideRailShowsPercentages)
        PanelMetrics.putLabelAboveRing(labelAboveRing)
        PanelMetrics.putFreeAcrossFiguresBeside(freeAcrossFiguresBeside)
        PanelMetrics.showWindowClock(showsWindowClock)
        PanelMetrics.useRoundEnds(usesRoundEnds)
        PanelMetrics.showForecast(showsForecast)
        PanelMetrics.use(usageBarStyle)
        PanelMetrics.showDetailedCard(!detailedCards.isEmpty)
    }

    /// The settings `init` has no parameter for.
    func restorePanel(from defaults: UserDefaults) {
        detailedCards = Set(defaults.stringArray(forKey: Key.detailedCards) ?? [])
        robotAccounts = Set(defaults.stringArray(forKey: Key.robotAccounts) ?? [])
        robotColours = defaults.dictionary(forKey: Key.robotColours) as? [String: String] ?? [:]
        robotPersonalities = defaults.dictionary(forKey: Key.robotPersonalities) as? [String: String] ?? [:]
        robotShapes = defaults.dictionary(forKey: Key.robotShapes) as? [String: String] ?? [:]
    }
}
