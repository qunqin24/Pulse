import Foundation
import Testing
import UserNotifications
@testable import Pulse

/// Starting a usage window after it resets: when it is due, which windows
/// count, the hours it may act in, and what is sent.
@Suite("Window primer")
struct WindowPrimerTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ hour: Int, _ minute: Int = 0, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func window(_ kind: UsageWindow.Kind, resets: Date?, scope: String? = nil) -> UsageWindow {
        UsageWindow(id: "w", kind: kind, scope: scope, usedFraction: 0, windowSeconds: 18_000, resetsAt: resets)
    }

    // MARK: Fresh readings

    @Test("An idle-only start held for hours asks for a fresh reading; a known reset does not")
    func freshReading() {
        // Read idle at midnight, held to 07:00 by the allowed hours.
        let read = Self.at(0)
        #expect(WindowPrimer.needsFreshReading(dueByClock: false, receivedAt: read, now: Self.at(7)))
        #expect(!WindowPrimer.needsFreshReading(dueByClock: false, receivedAt: Self.at(6, 58), now: Self.at(7)))
        #expect(WindowPrimer.needsFreshReading(dueByClock: false, receivedAt: nil, now: Self.at(7)))
        #expect(!WindowPrimer.needsFreshReading(dueByClock: true, receivedAt: read, now: Self.at(7)))
    }

    @Test("A window is due by the clock only on a reset it saw coming")
    func dueByClock() {
        var seen = WindowPrimer.WindowState()
        seen.record(window(.fiveHour, resets: Self.at(9)), receivedAt: Self.at(8), now: Self.at(8), last: nil)
        #expect(!seen.dueByClock(last: nil, now: Self.at(9), hours: .default, calendar: Self.calendar))
        #expect(seen.dueByClock(last: nil, now: Self.at(9, 2), hours: .default, calendar: Self.calendar))

        var idle = WindowPrimer.WindowState()
        idle.record(window(.fiveHour, resets: nil), receivedAt: Self.at(8), now: Self.at(8), last: nil)
        #expect(!idle.dueByClock(last: nil, now: Self.at(9, 2), hours: .default, calendar: Self.calendar))
    }

    // MARK: Hours

    @Test("Daytime hours, overnight hours, and all day")
    func hoursContain() {
        let day = PrimerHours(start: 7, end: 23)
        #expect(day.contains(Self.at(7), calendar: Self.calendar))
        #expect(!day.contains(Self.at(23), calendar: Self.calendar))
        #expect(!day.contains(Self.at(3), calendar: Self.calendar))
        let night = PrimerHours(start: 22, end: 6)
        #expect(night.contains(Self.at(23), calendar: Self.calendar))
        #expect(night.contains(Self.at(2), calendar: Self.calendar))
        #expect(!night.contains(Self.at(12), calendar: Self.calendar))
        #expect(PrimerHours(start: 9, end: 9).contains(Self.at(3), calendar: Self.calendar))
    }

    @Test("Outside the hours, the next start is when they open, today or tomorrow")
    func nextStart() {
        let day = PrimerHours(start: 7, end: 23)
        #expect(day.next(after: Self.at(3), calendar: Self.calendar) == Self.at(7))
        #expect(day.next(after: Self.at(23, 30), calendar: Self.calendar) == Self.at(7, day: 2))
        #expect(day.next(after: Self.at(12), calendar: Self.calendar) == Self.at(12))
    }

    // MARK: When

    @Test("Due once the reset and its grace have passed, inside the hours")
    func dueAfterReset() {
        let hours = PrimerHours(start: 7, end: 23)
        let reset = Self.at(10)
        #expect(!WindowPrimer.isDue(reset: reset, current: nil, now: Self.at(10, 0), hours: hours, calendar: Self.calendar))
        #expect(WindowPrimer.isDue(reset: reset, current: nil, now: Self.at(10, 2), hours: hours, calendar: Self.calendar))
        #expect(!WindowPrimer.isDue(reset: nil, current: nil, now: Self.at(10, 2), hours: hours, calendar: Self.calendar))
    }

    @Test("Not due outside the hours")
    func notDueAtNight() {
        let hours = PrimerHours(start: 7, end: 23)
        #expect(!WindowPrimer.isDue(reset: Self.at(1), current: nil, now: Self.at(2), hours: hours, calendar: Self.calendar))
    }

    @Test("Not due when a reading since shows a later reset: it has been used")
    func notDueWhenAlreadyStarted() {
        let hours = PrimerHours(start: 7, end: 23)
        let reset = Self.at(10)
        let restarted = window(.fiveHour, resets: Self.at(15, 30))
        #expect(!WindowPrimer.isDue(reset: reset, current: restarted, now: Self.at(11), hours: hours, calendar: Self.calendar))
        // The same reset, still reported, is not a restart.
        let stale = window(.fiveHour, resets: reset)
        #expect(WindowPrimer.isDue(reset: reset, current: stale, now: Self.at(11), hours: hours, calendar: Self.calendar))
    }

    // MARK: Idle windows

    private func state(_ row: UsageWindow?, at date: Date, last: WindowPrimer.Run? = nil) -> WindowPrimer.WindowState {
        var state = WindowPrimer.WindowState()
        state.record(row, receivedAt: date, now: date, last: last)
        return state
    }

    private func next(_ state: WindowPrimer.WindowState, at date: Date, last: WindowPrimer.Run? = nil) -> Date? {
        state.nextStart(last: last, now: date, hours: .default, calendar: Self.calendar)
    }

    @Test("A present row with no reset waits a full minute from its first live sighting")
    func nilResetGrace() {
        let now = Self.at(10)
        let idle = window(.fiveHour, resets: nil)
        var observed = state(idle, at: now)
        let later = now.addingTimeInterval(59)
        observed.record(idle, receivedAt: later, now: later, last: nil)
        #expect(next(observed, at: later) == Self.at(10, 1))
        #expect(next(observed, at: Self.at(10, 1)) == Self.at(10, 1))

        // Losing the live row cancels the wake and breaks continuous grace.
        observed.record(nil, receivedAt: later, now: later, last: nil)
        #expect(next(observed, at: Self.at(10, 1)) == nil)
        observed.record(idle, receivedAt: Self.at(10, 2), now: Self.at(10, 2), last: nil)
        #expect(next(observed, at: Self.at(10, 2)) == Self.at(10, 3))
    }

    @Test("A countdown appearing during nil grace replaces the idle wake with its own deadline")
    func countdownDuringGrace() {
        var observed = state(window(.fiveHour, resets: nil), at: Self.at(10))
        let later = Self.at(10).addingTimeInterval(15)
        observed.record(window(.fiveHour, resets: Self.at(15)), receivedAt: later, now: later, last: nil)
        #expect(next(observed, at: Self.at(10, 1)) == Self.at(15, 1))
    }

    @Test("A clock armed by a live countdown is still due if the row disappears")
    func clockSurvivesMissingRow() {
        var observed = state(window(.fiveHour, resets: Self.at(11)), at: Self.at(10))
        observed.record(nil, receivedAt: Self.at(10, 30), now: Self.at(10, 30), last: nil)
        #expect(next(observed, at: Self.at(10, 30)) == Self.at(11, 1))
        #expect(next(observed, at: Self.at(11, 1)) == Self.at(11, 1))
    }

    @Test("A past timestamp supplies its own grace, even on the first live reading")
    func pastResetGrace() {
        let reset = Self.at(10)
        let row = window(.fiveHour, resets: reset)
        let justAfter = reset.addingTimeInterval(59)
        #expect(next(state(row, at: justAfter), at: justAfter) == Self.at(10, 1))
        #expect(next(state(row, at: Self.at(10, 2)), at: Self.at(10, 2)) == Self.at(10, 2))
        #expect(state(row, at: justAfter).reset == nil, "An already-past timestamp is never remembered as a countdown")
    }

    @Test("Codex reset_at zero survives in the raw live rows the starter sees")
    @MainActor
    func codexZeroReset() throws {
        let now = Self.at(12)
        let raw = CodexUsageService.parseUsageResponse([
            "rate_limit": ["primary_window": ["used_percent": 0, "limit_window_seconds": 18_000, "reset_at": 0]]
        ], for: AccountKey(.codex))
        let row = try #require(UsageStore.LiveWindows(raw, at: now)?.windows.first)
        #expect(row.resetsAt == Date(timeIntervalSince1970: 0))
        #expect(WindowPrimer.eligible(row, of: .codex))
        #expect(raw.current(at: now) == nil)
        #expect(next(state(row, at: now), at: now) == now)
    }

    @Test("Missing, cached, stale and unavailable rows cannot supply an idle start")
    @MainActor
    func onlyPresentLiveRowsStart() {
        let now = Self.at(12)
        let idle = window(.fiveHour, resets: nil)
        for status in [ProviderUsage.State.stale, .unavailable(.unreachable)] {
            let raw = ProviderUsage(account: AccountKey(.codex), windows: [idle], observedAt: now,
                                    state: status, plan: nil, creditBalance: nil)
            #expect(UsageStore.LiveWindows(raw, at: now) == nil)
        }
        // Pro can return a weekly row without a five-hour row.
        let raw = ProviderUsage(account: AccountKey(.codex), windows: [window(.weekly, resets: Self.at(18))],
                                observedAt: now, state: .live, plan: nil, creditBalance: nil)
        let rows = UsageStore.LiveWindows(raw, at: now)?.windows ?? []
        #expect(next(state(rows.first { $0.kind == .fiveHour }, at: now), at: now) == nil)
        #expect(next(state(rows.first, at: now), at: now) == Self.at(18, 1))
    }

    @Test("An idle window outside the hours wakes when they next open")
    func idleOutsideHours() {
        let now = Self.at(23, 30)
        let opens = PrimerHours.default.next(after: now, calendar: Self.calendar)
        #expect(next(state(window(.fiveHour, resets: Self.at(22)), at: now), at: now) == opens)
        // Grace itself can finish just after closing time.
        let closing = Self.at(23).addingTimeInterval(-30)
        #expect(next(state(window(.fiveHour, resets: nil), at: closing), at: closing) == opens)
    }

    @Test("Neither success nor failure repeats on a still-idle reading",
          arguments: [WindowStarter.Outcome.sent, .failed, .toolMissing, .timedOut])
    func unchangedIdleDoesNotRearm(_ outcome: WindowStarter.Outcome) {
        let last = (date: Self.at(10), outcome: outcome)
        let now = Self.at(12)
        for reset in [nil, Self.at(11), Date(timeIntervalSince1970: 0)] as [Date?] {
            let observed = state(window(.fiveHour, resets: reset), at: now, last: last)
            #expect(next(observed, at: Self.at(12, 2), last: last) == nil)
        }
        // A countdown that reset before the attempt cannot authorize another.
        var old = state(window(.fiveHour, resets: Self.at(9)), at: Self.at(8))
        old.record(window(.fiveHour, resets: nil), receivedAt: now, now: now, last: last)
        #expect(next(old, at: Self.at(12, 2), last: last) == nil)
    }

    @Test("After a failure the next observed reset must actually pass grace",
          arguments: [WindowStarter.Outcome.failed, .toolMissing, .timedOut])
    func nextResetAfterFailure(_ outcome: WindowStarter.Outcome) {
        let last = (date: Self.at(10), outcome: outcome)
        var observed = state(window(.fiveHour, resets: Self.at(12)), at: Self.at(11), last: last)
        let idle = window(.fiveHour, resets: Date(timeIntervalSince1970: 0))
        observed.record(idle, receivedAt: Self.at(11, 1), now: Self.at(11, 1), last: last)
        #expect(next(observed, at: Self.at(11, 1), last: last) == Self.at(12, 1))
        #expect(next(observed, at: Self.at(12, 1), last: last) == Self.at(12, 1))

        // Relaunch restores the evidence. Until another live row arrives
        // neither launch cache nor the passage of time alone can start it.
        var relaunched = WindowPrimer.WindowState(reset: observed.reset)
        #expect(next(relaunched, at: Self.at(13), last: last) == nil)
        relaunched.record(idle, receivedAt: Self.at(13), now: Self.at(13), last: last)
        #expect(next(relaunched, at: Self.at(13), last: last) == Self.at(13))
    }

    @Test("A success needs a countdown seen since the send, then an idle row")
    func completedCycleAfterSuccess() {
        let last = (date: Self.at(10), outcome: WindowStarter.Outcome.sent)
        let countdown = window(.fiveHour, resets: Self.at(15))
        let idle = window(.fiveHour, resets: Date(timeIntervalSince1970: 0))
        var observed = state(countdown, at: Self.at(9))
        // Changing hours after sending re-reads the pre-send snapshot.
        observed.record(countdown, receivedAt: Self.at(9), now: Self.at(11), last: last)
        var relaunched = WindowPrimer.WindowState(reset: observed.reset)
        relaunched.record(idle, receivedAt: Self.at(16), now: Self.at(16), last: last)
        #expect(next(relaunched, at: Self.at(16), last: last) == nil)

        // A new live fetch of the very same countdown is post-send evidence.
        observed.record(countdown, receivedAt: Self.at(11), now: Self.at(11), last: last)
        relaunched = WindowPrimer.WindowState(reset: observed.reset)
        #expect(next(relaunched, at: Self.at(16), last: last) == nil)
        relaunched.record(idle, receivedAt: Self.at(16), now: Self.at(16), last: last)
        #expect(next(relaunched, at: Self.at(16), last: last) == Self.at(16))
    }

    @Test("After a send, a reading with no reset cannot start a window still counting down")
    func contradictoryReadingAfterSuccess() {
        let last = (date: Self.at(10), outcome: WindowStarter.Outcome.sent)
        var observed = state(window(.fiveHour, resets: Self.at(15)), at: Self.at(10, 1), last: last)
        // A fallback route that keeps the row without its reset.
        observed.record(window(.fiveHour, resets: nil), receivedAt: Self.at(11), now: Self.at(11), last: last)
        #expect(next(observed, at: Self.at(11, 1), last: last) == Self.at(15, 1))
    }

    @Test("A sibling that resets while an attempt is running is a later reset, not one it covered")
    func siblingResetDuringAttempt() {
        let weeklyReset = Self.at(10).addingTimeInterval(30)
        // The attempt is stamped with when it began, 10:00, though it timed out at 10:02.
        let last = (date: Self.at(10), outcome: WindowStarter.Outcome.timedOut)
        var week = state(window(.weekly, resets: weeklyReset), at: Self.at(9))
        week.record(window(.weekly, resets: weeklyReset), receivedAt: Self.at(10, 3), now: Self.at(10, 3), last: last)
        #expect(next(week, at: Self.at(10, 3), last: last) == Self.at(10, 3))
    }

    @Test("Turning the switch back on lets an idle window be tried again; 'Last started' keeps the failure")
    @MainActor
    func reenablingAllowsRetry() {
        let (defaults, cleanup) = TestDefaults.make("WindowPrimerRearm")
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        settings.setPrimesWindows(true, for: .codex)
        settings.recordPrimerRun(for: .codex, outcome: .timedOut, at: Date().addingTimeInterval(60))
        #expect(settings.governingPrimerRun(for: .codex)?.outcome == .timedOut)
        // Turning it on again while on is not a new request.
        settings.setPrimesWindows(true, for: .codex)
        #expect(settings.governingPrimerRun(for: .codex)?.outcome == .timedOut)

        settings.recordPrimerRun(for: .codex, outcome: .timedOut, at: Date().addingTimeInterval(-60))
        settings.setPrimesWindows(false, for: .codex)
        settings.setPrimesWindows(true, for: .codex)
        #expect(settings.governingPrimerRun(for: .codex) == nil)
        #expect(settings.lastPrimerRun(for: .codex)?.outcome == .timedOut)
    }

    @Test("An idle five-hour window consumes one start and preserves the weekly clock")
    func siblingCountdownSurvives() {
        let now = Self.at(12)
        let idle = window(.fiveHour, resets: Self.at(11))
        var windows = ["five": state(idle, at: now), "week": state(window(.weekly, resets: Self.at(18)), at: now)]
        let starts = windows.compactMapValues { next($0, at: now) }
        #expect(starts == ["five": now, "week": Self.at(18, 1)])
        let sent = WindowPrimer.takeDue(starts, at: now, from: &windows)
        #expect(sent)
        #expect(Set(windows.keys) == ["week"])
        let last = (date: now, outcome: WindowStarter.Outcome.sent)
        windows["five"] = state(idle, at: Self.at(12, 2), last: last)
        // Seeing the week's countdown again after the send re-arms only the week.
        windows["week"]?.record(window(.weekly, resets: Self.at(18)), receivedAt: Self.at(12, 2),
                                now: Self.at(12, 2), last: last)
        let after = windows.compactMapValues { next($0, at: Self.at(12, 2), last: last) }
        #expect(after == ["week": Self.at(18, 1)])
    }

    @Test("Successful sends are silent and all three failure notices replace the previous one for the provider")
    @MainActor
    func failureNotices() throws {
        #expect(UsageAlerts.windowStarterFailure(for: .codex, outcome: .sent, title: "Work") == nil)
        var bodies: Set<String> = []
        for outcome in [WindowStarter.Outcome.timedOut, .toolMissing, .failed] {
            let request = try #require(UsageAlerts.windowStarterFailure(for: .codex, outcome: outcome, title: "Work"))
            #expect(request.identifier == "window-starter-codex")
            #expect(request.content.title == "Work")
            #expect(request.content.subtitle == String.localized("Couldn't start the window"))
            #expect(request.content.sound != nil)
            bodies.insert(request.content.body)
        }
        #expect(bodies.count == 3)
        #expect(!bodies.contains(""))
    }

    @Test("Starter permission and reset evidence survive relaunch independently of unreadable-usage alerts")
    @MainActor
    func rememberedSettings() {
        let (defaults, cleanup) = TestDefaults.make("WindowPrimer")
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        settings.setPrimesWindows(true, for: .codex)
        settings.recordPrimerRun(for: .codex, outcome: .timedOut, at: Self.at(10))
        let reset = WindowPrimer.Reset(date: Self.at(16), seenAt: Self.at(11))
        settings.rememberedPrimerResets = ["codex|weekly": reset]

        let restored = AppSettings(defaults: defaults)
        restored.restoreWindowStarter(from: defaults)
        #expect(restored.wantsAlerts)
        #expect(!restored.wantsUsageAlerts)
        #expect(restored.lastPrimerRun(for: .codex)?.outcome == .timedOut)
        #expect(restored.rememberedPrimerResets == ["codex|weekly": reset])
        restored.setPrimesWindows(false, for: .codex)
        #expect(!restored.wantsAlerts)
    }

    // MARK: Which

    @Test("Claude Code's five hours only; Codex's five hours and week; nothing scoped or inferred")
    func eligibility() {
        #expect(WindowPrimer.eligible(window(.fiveHour, resets: nil), of: .claudeCode))
        #expect(!WindowPrimer.eligible(window(.weekly, resets: nil), of: .claudeCode))
        #expect(WindowPrimer.eligible(window(.fiveHour, resets: nil), of: .codex))
        #expect(WindowPrimer.eligible(window(.weekly, resets: nil), of: .codex))
        #expect(!WindowPrimer.eligible(window(.weekly, resets: nil, scope: "Spark"), of: .codex))
        #expect(!WindowPrimer.eligible(window(.fiveHour, resets: nil), of: .cursor))
        var estimate = window(.fiveHour, resets: nil)
        estimate.estimate = .planPrice
        #expect(!WindowPrimer.eligible(estimate, of: .codex))
    }

    // MARK: What is sent

    @Test("Claude is asked with Haiku, no tools, no MCP, no user settings, nothing saved")
    func claudeArguments() {
        let arguments = WindowStarter.claudeArguments()
        #expect(arguments.starts(with: ["-p", "hi"]))
        #expect(arguments.contains("--no-session-persistence"))
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "--model" && $1 == "haiku" })
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "--tools" && $1 == "" })
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "--setting-sources" && $1 == "project" })
        #expect(arguments.contains("--strict-mcp-config"))
    }

    @Test("Codex is asked ephemerally, read-only, at low effort, with the model when one was found")
    func codexArguments() {
        let folder = URL(fileURLWithPath: "/tmp/starter")
        let arguments = WindowStarter.codexArguments(model: "gpt-5.6-luna", folder: folder)
        #expect(arguments.first == "exec")
        #expect(arguments.last == "hi")
        #expect(arguments.contains("--ephemeral"))
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "-m" && $1 == "gpt-5.6-luna" })
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "-s" && $1 == "read-only" })
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "-C" && $1 == "/tmp/starter" })
        #expect(!WindowStarter.codexArguments(model: nil, folder: folder).contains("-m"))
    }

    @Test("The cheapest Codex model: Luna by name, else one described as fast, else none")
    func cheapestModel() {
        func reply(_ models: [[String: Any]]) -> Data {
            try! JSONSerialization.data(withJSONObject: ["data": models])
        }
        let current = reply([
            ["id": "gpt-5.6-sol", "description": "Older coding model for complex work."],
            ["id": "gpt-5.6-luna", "description": "Older fast and efficient model."],
            ["id": "gpt-5.6-terra", "description": "Older balanced model."],
        ])
        #expect(WindowStarter.cheapestCodexModel(in: current) == "gpt-5.6-luna")
        let renamed = reply([
            ["id": "gpt-7-big", "description": "Frontier model."],
            ["id": "gpt-7-swift", "description": "Fast and cheap."],
        ])
        #expect(WindowStarter.cheapestCodexModel(in: renamed) == "gpt-7-swift")
        let hidden = reply([["id": "gpt-5.6-luna", "hidden": true, "description": "fast"]])
        #expect(WindowStarter.cheapestCodexModel(in: hidden) == nil)
        #expect(WindowStarter.cheapestCodexModel(in: reply([["id": "only", "description": "A model."]])) == nil)
        #expect(WindowStarter.cheapestCodexModel(in: Data("nope".utf8)) == nil)
    }

    @Test("Claude is looked for on PATH, then its own installer's folder, then the usual places")
    func claudeLocator() {
        let listed = CommandLocator.candidates(
            "claude", home: "/Users/me", path: "/usr/bin",
            extra: ["/Users/me/.claude/local/claude"],
            versions: { $0.hasSuffix(".nvm/versions/node") ? ["v20.0.0", "v24.1.0"] : [] }
        )
        #expect(Array(listed.prefix(3)) == ["/usr/bin/claude", "/Users/me/.claude/local/claude", "/opt/homebrew/bin/claude"])
        #expect(listed.contains("/Users/me/.local/bin/claude"))
        #expect(listed.filter { $0.contains(".nvm") } == [
            "/Users/me/.nvm/versions/node/v24.1.0/bin/claude", "/Users/me/.nvm/versions/node/v20.0.0/bin/claude",
        ])
    }

    @Test("Claude's project folder for the starter's directory is named the way Claude names it")
    func claudeProjectFolderName() {
        let folder = URL(fileURLWithPath: "/Users/me/Library/Application Support/Pulse/Window starter")
        #expect(WindowStarter.claudeProjectFolder(for: folder, home: "/Users/me").path
            == "/Users/me/.claude/projects/-Users-me-Library-Application-Support-Pulse-Window-starter")
    }

    @Test("A provider no longer started keeps no noted reset to wake for")
    func switchedOffForgetsResets() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let claude = AccountKey(.claudeCode).id, codex = AccountKey(.codex).id
        let noted = ["\(claude)|five_hour": reset, "\(codex)|primary": reset, "\(codex)|secondary": reset]
        #expect(Set(WindowPrimer.kept(noted, starting: [.codex]).keys) == ["\(codex)|primary", "\(codex)|secondary"])
        #expect(WindowPrimer.kept(noted, starting: []).isEmpty)
    }
}
