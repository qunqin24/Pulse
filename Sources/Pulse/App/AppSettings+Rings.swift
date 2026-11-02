// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import SwiftUI

// How a ring looks, account by account and for the rail as a whole: its tint,
// the clock arc, which figure it shows, the colour it turns
// near a limit. Most of it is `@Observable` and redraws whoever read it, and
// needs no callback at all; the exceptions say so.

extension AppSettings.Key {
    static let pinnedWindows = "settings.pinnedWindows"
    static let ringTints = "settings.ringTints"
    static let windowClockDirection = "settings.windowClockDirection"
    static let showsRemaining = "settings.showsRemaining"
    static let warningThreshold = "settings.warningThreshold"
    static let dockShowsAlertColor = "settings.dockShowsAlertColor"
    static let showsSecondRing = "settings.showsSecondRing"
    static let animatesRingActivity = "settings.animatesRingActivity"
}

extension AppSettings.Default {
    static let showsRemaining = false
    static let dockShowsAlertColor = true
    static let showsSecondRing = false
    static let animatesRingActivity = true
}

extension AppSettings {
    /// **Still `onChange`**, which refreshes every provider, although the pin
    /// is resolved at display time and fetches nothing different. Left as it
    /// was: it is not a layout setting, and what the pin changes on the card is
    /// not this file's to decide.
    func pinnedWindowsChanged(from old: [String: String]) {
        guard pinnedWindows != old else { return }
        defaults.set(pinnedWindows, forKey: Key.pinnedWindows)
        onChange?()
    }

    func ringTintsChanged(from old: [String: String]) {
        guard ringTints != old else { return }
        defaults.set(ringTints, forKey: Key.ringTints)
    }

    func windowClockDirectionChanged(from old: WindowClockDirection) {
        guard windowClockDirection != old else { return }
        Self.storeWindowClockDirection(windowClockDirection, in: defaults)
    }

    func showsRemainingChanged(from old: Bool) {
        guard showsRemaining != old else { return }
        defaults.set(showsRemaining, forKey: Key.showsRemaining)
    }

    func warningThresholdChanged(from old: WarningThreshold) {
        guard warningThreshold != old else { return }
        defaults.set(warningThreshold.rawValue, forKey: Key.warningThreshold)
    }

    func dockShowsAlertColorChanged(from old: Bool) {
        guard dockShowsAlertColor != old else { return }
        defaults.set(dockShowsAlertColor, forKey: Key.dockShowsAlertColor)
    }

    /// Moves nothing in the frame: what is drawn inside the ring is decided
    /// from the reading, and the second window is already in it. Re-places the
    /// panel, which does no harm, and fetches nothing.
    func showsSecondRingChanged(from old: Bool) {
        guard showsSecondRing != old else { return }
        defaults.set(showsSecondRing, forKey: Key.showsSecondRing)
        onLayoutChange?()
    }

    func animatesRingActivityChanged(from old: Bool) {
        guard animatesRingActivity != old else { return }
        defaults.set(animatesRingActivity, forKey: Key.animatesRingActivity)
    }

    // MARK: - Stored directly, for readers without an `AppSettings`

    static func storedWindowClockDirection(in defaults: UserDefaults) -> WindowClockDirection {
        defaults.string(forKey: Key.windowClockDirection)
            .flatMap(WindowClockDirection.init(rawValue:)) ?? .default
    }

    static func storeWindowClockDirection(
        _ direction: WindowClockDirection,
        in defaults: UserDefaults
    ) {
        defaults.set(direction.rawValue, forKey: Key.windowClockDirection)
    }

    static var windowClockDirectionDefaultsKey: String { Key.windowClockDirection }

    /// A Codex pin made while the app server answered, renamed to the id the
    /// same limit carries on the HTTP route.
    ///
    /// The app server once named its limits `codex.primary`, the endpoint
    /// `codex.primary_window`, so a pin made on one route did not match on the
    /// other and the ring fell back to the fullest limit (issue #102). Both
    /// now use the endpoint's spelling; this carries an old pin across.
    static func codexPinsNamedLikeHTTP(_ pins: [String: String]) -> [String: String] {
        pins.reduce(into: [:]) { result, pin in
            let isCodex = AccountKey(id: pin.key)?.provider == .codex
            let renamed = isCodex && (pin.value.hasSuffix(".primary") || pin.value.hasSuffix(".secondary"))
            result[pin.key] = renamed ? pin.value + "_window" : pin.value
        }
    }

    // MARK: - Per-account accessors

    /// The window pinned for an account, if any.
    func pinnedWindow(for account: AccountKey) -> String? {
        pinnedWindows[account.id]
    }

    func setPinnedWindow(_ id: String?, for account: AccountKey) {
        var updated = pinnedWindows
        updated[account.id] = id
        pinnedWindows = updated
    }

    /// The colour chosen for an account's ring, or nil to colour it by usage.
    func ringTint(for account: AccountKey) -> Color? {
        RingTint.color(from: ringTints[account.id])
    }

    func setRingTint(_ colour: Color?, for account: AccountKey) {
        // A colour that will not convert to sRGB has no hex, and storing that
        // nil would *remove* the key — silently putting the account back on
        // Automatic and taking the colour row off the pane, which reads as the
        // picker having refused to work. Keep whatever was chosen last
        // instead; only an explicit nil clears it.
        guard let colour else {
            var updated = ringTints
            updated[account.id] = nil
            ringTints = updated
            return
        }
        guard let hex = colour.hexString else { return }

        var updated = ringTints
        updated[account.id] = hex
        ringTints = updated
    }
}
