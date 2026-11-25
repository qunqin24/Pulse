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

/// Sends one message for an eligible account when a remembered reset comes
/// due or a live reading shows a window waiting for its first message.
@MainActor
final class WindowPrimer {
    private let store: UsageStore
    private let settings: AppSettings
    private let alerts: UsageAlerts
    private var timer: Timer?
    private var generation = 0
    private var inFlight: Set<Provider> = []
    private var windows: [String: WindowState]
    private var savedResets: [String: Reset]

    /// A reading can arrive a little after the reset it stated.
    nonisolated static let grace: TimeInterval = 60
    typealias Run = (date: Date, outcome: WindowStarter.Outcome)

    /// Evidence that this window had a countdown. A reset date alone cannot
    /// tell us whether the countdown was seen before or after the last send.
    struct Reset: Equatable, Codable {
        let date: Date
        let seenAt: Date
    }

    struct WindowState {
        private(set) var reset: Reset?
        private var clockArmed = false
        private var current: UsageWindow?
        private var nilSince: Date?

        init(reset: Reset? = nil) { self.reset = reset }

        mutating func record(_ window: UsageWindow?, receivedAt: Date, now: Date, last: Run?) {
            current = window
            guard let window else {
                nilSince = nil
                return
            }
            guard let date = window.resetsAt else {
                nilSince = nilSince ?? now
                return
            }
            nilSince = nil
            guard date > now else { return }
            clockArmed = true

            // Keep the first sighting after each attempt. Re-reading the same
            // store snapshot on a settings change cannot re-arm an idle start.
            if let reset, reset.date == date {
                guard let last, reset.seenAt <= last.date, receivedAt > last.date else { return }
            }
            reset = Reset(date: date, seenAt: receivedAt)
        }

        private func idleStart(last: Run?, now: Date) -> Date? {
            guard let current, (current.resetsAt ?? .distantPast) <= now,
                  let since = current.resetsAt ?? nilSince else { return nil }
            let idle = since.addingTimeInterval(WindowPrimer.grace)
            guard let last else { return idle }
            guard let reset, reset.date > last.date else { return nil }
            switch last.outcome {
            case .sent:
                return reset.seenAt > last.date ? idle : nil
            case .toolMissing, .failed, .timedOut:
                return max(idle, reset.date.addingTimeInterval(WindowPrimer.grace))
            }
        }

        /// Earliest permitted action for this window, shared by the timer and
        /// its callback. Restored evidence alone never arms the clock.
        func nextStart(last: Run?, now: Date, hours: PrimerHours, calendar: Calendar = .current) -> Date? {
            func allowed(_ date: Date) -> Date { hours.next(after: max(now, date), calendar: calendar) }
            let idle = idleStart(last: last, now: now).map(allowed)
            guard clockArmed, let reset, reset.date > (last?.date ?? .distantPast) else { return idle }
            let clock = allowed(reset.date.addingTimeInterval(WindowPrimer.grace))
            guard WindowPrimer.isDue(reset: reset.date, current: current, now: clock, hours: hours, calendar: calendar)
            else { return idle }
            return min(clock, idle ?? clock)
        }
    }

    init(store: UsageStore, settings: AppSettings, alerts: UsageAlerts) {
        self.store = store
        self.settings = settings
        self.alerts = alerts
        let saved = settings.rememberedPrimerResets
        savedResets = saved
        windows = saved.mapValues { WindowState(reset: $0) }
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

    /// The noted resets of the providers that will still be started.
    nonisolated static func kept<Value>(_ resets: [String: Value], starting providers: Set<Provider>) -> [String: Value] {
        let prefixes = providers.map { AccountKey($0).id + "|" }
        return resets.filter { key, _ in prefixes.contains { key.hasPrefix($0) } }
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

    private var starting: [Provider] {
        Self.providers.filter { settings.primesWindows(for: $0) && settings.isEnabled(AccountKey($0)) }
    }

    /// Track raw readings, switches and hours together. An absent row breaks
    /// continuous nil-reset grace, but a clock already armed can still ring.
    private func record() {
        let now = Date()
        _ = settings.primerHours
        let providers = starting
        windows = Self.kept(windows, starting: Set(providers))
        for provider in providers {
            let reading = store.rawLiveWindows(for: provider)
            var current: [String: UsageWindow] = [:]
            for window in reading?.windows ?? [] where Self.eligible(window, of: provider) {
                current["\(provider.rawValue)|\(window.id)"] = window
            }
            let last = settings.lastPrimerRun(for: provider)
            let known = Self.kept(windows, starting: [provider])
            for key in Set(known.keys).union(current.keys) {
                windows[key, default: WindowState()].record(
                    current[key], receivedAt: reading?.receivedAt ?? now, now: now, last: last
                )
            }
        }
        saveResets()
    }

    private func saveResets() {
        let resets = windows.compactMapValues(\.reset)
        guard resets != savedResets else { return }
        settings.rememberedPrimerResets = resets
        savedResets = resets
    }

    // MARK: - Acting

    private func starts(for provider: Provider, now: Date) -> [String: Date] {
        let last = settings.lastPrimerRun(for: provider)
        let hours = settings.primerHours
        return Self.kept(windows, starting: [provider]).compactMapValues {
            $0.nextStart(last: last, now: now, hours: hours)
        }
    }

    private func schedule() {
        timer?.invalidate()
        let now = Date()
        let times = starting.filter { !inFlight.contains($0) }.compactMap { starts(for: $0, now: now).values.min() }
        guard let soonest = times.min() else { return }
        let delay = max(soonest.timeIntervalSince(now), 5)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// One send consumes the due windows of this account together. A sibling
    /// with a later deadline keeps its clock and the evidence saved for relaunch.
    nonisolated static func takeDue(_ starts: [String: Date], at now: Date, from windows: inout [String: WindowState]) -> Bool {
        let due = starts.filter { $0.value <= now }
        for key in due.keys { windows[key] = nil }
        return !due.isEmpty
    }

    private func fire() {
        // A fetch or switch change can land before the observation task runs.
        record()
        let now = Date()
        for provider in starting where !inFlight.contains(provider) {
            let times = starts(for: provider, now: now)
            guard Self.takeDue(times, at: now, from: &windows) else { continue }
            inFlight.insert(provider)
            Task { @MainActor in
                let outcome = await WindowStarter.start(provider)
                self.inFlight.remove(provider)
                self.settings.recordPrimerRun(for: provider, outcome: outcome, at: Date())
                self.alerts.postWindowStarterFailure(for: provider, outcome: outcome)
                self.store.refresh(AccountKey(provider))
                self.schedule()
            }
        }
        saveResets()
        schedule()
    }
}
