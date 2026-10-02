// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

/// Hours of the day the window starter may act in, by the Mac's clock.
///
/// A window started at 3 a.m. resets at 8 — while somebody is asleep, and
/// again five hours later. Limiting it to waking hours costs nothing that
/// matters and keeps the account from looking like a machine that never
/// sleeps.
struct PrimerHours: Equatable, Sendable {
    /// 0–23. Equal start and end means all day.
    var start: Int
    var end: Int

    static let `default` = PrimerHours(start: 7, end: 23)

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if start == end { return true }
        return start < end ? (start..<end).contains(hour) : (hour >= start || hour < end)
    }

    /// The next moment at or after `date` inside these hours.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        if contains(date, calendar: calendar) { return date }
        let today = calendar.date(bySettingHour: start, minute: 0, second: 0, of: date) ?? date
        return today > date ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
    }
}

/// Starts a usage window as soon as it has reset, for the accounts whose
/// switch is on — see `WindowStarter` for why and how.
///
/// **By the clock, not by guessing from the reply.** A window that has reset
/// but not restarted is reported differently by each provider, and not
/// documented by either. What is certain is the reset time the last reading
/// stated: once it has passed, the window is over. So each eligible window's
/// reset is remembered, a timer is set for just after it, and at that moment
/// one "hi" is sent — unless a reading since shows a later reset, which means
/// the user has started it already.
///
/// Off by default, per provider, and only after the user has read what it
/// does (the confirmation in Settings). Only the first account of each: the
/// tools send as whoever they are signed in as, which is that account.
@MainActor
final class WindowPrimer {
    private let store: UsageStore
    private let settings: AppSettings
    private var timer: Timer?
    private var generation = 0
    private var inFlight: Set<Provider> = []
    /// The reset each eligible window was last seen to be heading for.
    private var resets: [String: Date] = [:]

    /// A reading can arrive a little after the reset it stated; the window
    /// is given this long to be over before it is started again.
    nonisolated static let grace: TimeInterval = 60

    init(store: UsageStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func start() {
        observe()
    }

    /// The windows starting helps. Claude Code's week resets at a fixed hour
    /// whatever anybody does, so only its five hours; Codex's five hours and
    /// week both wait for a first message. Account-wide limits only.
    nonisolated static func eligible(_ window: UsageWindow, of provider: Provider) -> Bool {
        guard window.scope == nil, window.estimate == nil else { return false }
        switch provider {
        case .claudeCode: return window.kind == .fiveHour
        case .codex: return window.kind == .fiveHour || window.kind == .weekly
        default: return false
        }
    }

    nonisolated static let providers: [Provider] = [.claudeCode, .codex]

    /// Whether a window whose last known reset was `reset` should be started
    /// now. `current` is the window as the latest reading has it.
    nonisolated static func isDue(
        reset: Date?, current: UsageWindow?, now: Date, hours: PrimerHours, calendar: Calendar = .current
    ) -> Bool {
        guard let reset, now >= reset.addingTimeInterval(grace), hours.contains(now, calendar: calendar) else { return false }
        // A later reset than the one that passed: somebody has used it since.
        if let next = current?.resetsAt, next > reset.addingTimeInterval(grace) { return false }
        return true
    }

    private static func key(_ account: AccountKey, _ window: UsageWindow) -> String {
        "\(account.id)|\(window.id)"
    }

    // MARK: - Watching

    private func observe() {
        generation += 1
        let current = generation
        withObservationTracking {
            record()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.observe()
            }
        }
        schedule()
    }

    /// Notes every eligible window's coming reset, reading what the tracking
    /// closure has to follow: the switches, the hours, and the readings.
    private func record() {
        let now = Date()
        _ = settings.primerHours
        for provider in Self.providers where settings.primesWindows(for: provider) {
            let account = AccountKey(provider)
            guard settings.isEnabled(account) else { continue }
            for window in store.usage(for: account).windows where Self.eligible(window, of: provider) {
                if let reset = window.resetsAt, reset > now {
                    resets[Self.key(account, window)] = reset
                }
            }
        }
    }

    // MARK: - Acting

    private func schedule() {
        timer?.invalidate()
        let hours = settings.primerHours
        let now = Date()
        let times = resets.values.map { hours.next(after: max($0.addingTimeInterval(Self.grace), now)) }
        guard let soonest = times.min() else { return }
        let delay = max(soonest.timeIntervalSince(now), 5)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        let now = Date()
        let hours = settings.primerHours
        for provider in Self.providers where settings.primesWindows(for: provider) && !inFlight.contains(provider) {
            let account = AccountKey(provider)
            guard settings.isEnabled(account) else { continue }
            let windows = store.usage(for: account).windows
            let due = resets.filter { key, reset in
                guard key.hasPrefix(account.id + "|") else { return false }
                let id = String(key.dropFirst(account.id.count + 1))
                return Self.isDue(reset: reset, current: windows.first { $0.id == id }, now: now, hours: hours)
            }
            guard !due.isEmpty else { continue }
            // One message starts every window of the account at once.
            for key in due.keys { resets[key] = nil }
            inFlight.insert(provider)
            Task { @MainActor in
                let outcome = await WindowStarter.start(provider)
                self.inFlight.remove(provider)
                self.settings.recordPrimerRun(for: provider, outcome: outcome, at: Date())
                // The new reset, so the next start is scheduled from it.
                self.store.refresh(account)
            }
        }
        // Whatever was not due yet — or the rest of the hours — is scheduled
        // again; the tracking only re-runs on a change.
        schedule()
    }
}
