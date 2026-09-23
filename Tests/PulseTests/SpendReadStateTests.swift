import Foundation
import Testing
@testable import Pulse

/// The same window-scoped state used by SettingsView, with completed snapshots
/// supplied by hand. No view rendering, file traversal or provider access.
@Suite("Spend pane result lifetime")
struct SpendReadStateTests {
    private func request(
        selected: Bool = true, enabled: Bool = true, visible: Bool = true, rescan: Int = 0
    ) -> SpendReadState.Request {
        .init(isEnabled: enabled, isWindowVisible: visible, isPaneSelected: selected, rescan: rescan)
    }

    private func snapshot(tokens: Int = 100) -> AgentLedgers.Snapshot {
        let ledger = UsageLedgerReader.price(
            ["2026-09-19 09:00": ["model": TokenTally(input: tokens)]], with: [:]
        )
        return .init(ledgers: [.codex: ledger, .workBuddy: .empty], notes: [.workBuddy: ["unreadable record"]])
    }

    private func scan(_ action: SpendReadState.Action) throws -> (id: UUID, refresh: Bool) {
        let read: (UUID, Bool)? = if case .scan(let id, let refresh) = action { (id, refresh) } else { nil }
        return try #require(read, "A read should start rather than reuse or release a snapshot")
    }

    @Test("Completed figures, empty sources and read-limit notes survive sidebar round trips")
    func sidebarReuse() throws {
        var state = SpendReadState()
        let first = try scan(state.prepare(request()))
        #expect(!first.refresh)
        let completed = state.complete(snapshot(), for: first.id)
        let finished = state.finish(first.id)
        #expect(completed)
        #expect(finished)
        #expect(state.snapshotID == first.id)

        for _ in 0..<3 {
            #expect(state.prepare(request(selected: false)) == .retain)
            #expect(state.prepare(request()) == .retain)
            #expect(state.snapshot?.ledgers[.codex]?.allTime.tokens == 100)
            #expect(state.snapshot?.ledgers[.workBuddy]?.allTime.tokens == 0)
            #expect(state.snapshot?.notes[.workBuddy] == ["unreadable record"])
        }
    }

    @Test("A successfully empty scan is cached too")
    func emptyResultIsCompleted() throws {
        var state = SpendReadState()
        let first = try scan(state.prepare(request()))
        state.complete(.init(), for: first.id)
        state.finish(first.id)
        #expect(state.prepare(request(selected: false)) == .retain)
        #expect(state.prepare(request()) == .retain)
        #expect(state.snapshot != nil)
        #expect(state.snapshot?.ledgers.isEmpty == true)
    }

    @Test("Disabling or closing releases results even while a different pane is selected", arguments: [false, true])
    func releaseAwayFromPane(closeWindow: Bool) throws {
        var state = SpendReadState()
        let first = try scan(state.prepare(request()))
        state.complete(snapshot(), for: first.id)
        state.finish(first.id)
        let away = request(selected: false)
        #expect(state.prepare(away) == .retain)
        let released = request(selected: false, enabled: closeWindow, visible: !closeWindow)
        // These must also be different task ids: a single "inactive" id would
        // never notify the view of a window closed after switching away.
        #expect(away != released)
        #expect(state.prepare(released) == .release)
        #expect(state.snapshot == nil)
        #expect(state.snapshotID == nil)
        #expect(state.prepare(request(selected: false)) == .retain)
        let reopened = try scan(state.prepare(request()))
        #expect(!reopened.refresh, "A new window/enabling may still use the disk cache")
    }

    @Test("Rescan releases the old detail and forces exactly one new read")
    func explicitRescan() throws {
        var state = SpendReadState()
        let first = try scan(state.prepare(request()))
        state.complete(snapshot(), for: first.id)
        state.finish(first.id)

        let rescan = try scan(state.prepare(request(rescan: 1)))
        #expect(rescan.refresh)
        #expect(state.snapshot == nil)
        #expect(state.snapshotID == nil)
        state.complete(snapshot(tokens: 200), for: rescan.id)
        state.finish(rescan.id)
        #expect(state.snapshotID == rescan.id)
        #expect(state.prepare(request(selected: false, rescan: 1)) == .retain)
        #expect(state.prepare(request(rescan: 1)) == .retain)
        #expect(state.snapshot?.ledgers[.codex]?.allTime.tokens == 200)
    }

    @Test("Leaving an unfinished scan rejects its late results and progress, then retries on return")
    func cancelledPredecessorCannotPublish() throws {
        var state = SpendReadState()
        let old = try scan(state.prepare(request()))
        #expect(state.prepare(request(selected: false)) == .retain)
        #expect(!state.isCurrent(old.id))
        let completedWhileAway = state.complete(snapshot(), for: old.id)
        #expect(!completedWhileAway)
        #expect(state.snapshot == nil)

        let replacement = try scan(state.prepare(request()))
        #expect(replacement.id != old.id)
        let completedAfterReplacement = state.complete(snapshot(), for: old.id)
        let finishedOld = state.finish(old.id)
        #expect(!completedAfterReplacement)
        #expect(!finishedOld, "An old defer must not clear the replacement's loading state")
        #expect(state.isCurrent(replacement.id))
        let completedReplacement = state.complete(snapshot(tokens: 200), for: replacement.id)
        let finishedReplacement = state.finish(replacement.id)
        #expect(completedReplacement)
        #expect(finishedReplacement)
        #expect(state.snapshot?.ledgers[.codex]?.allTime.tokens == 200)
    }

    @Test("A failed or cancelled rescan is not mistaken for a completed snapshot")
    func unfinishedRescanRetries() throws {
        var state = SpendReadState()
        let first = try scan(state.prepare(request()))
        state.complete(snapshot(), for: first.id)
        state.finish(first.id)
        let rescan = try scan(state.prepare(request(rescan: 1)))
        state.finish(rescan.id)
        #expect(state.snapshot == nil)
        #expect(state.prepare(request(selected: false, rescan: 1)) == .retain)
        let retry = try scan(state.prepare(request(rescan: 1)))
        #expect(!retry.refresh)
    }

    @Test("No reading starts while disabled, closed or on another pane")
    func inactiveDoesNotRead() {
        var state = SpendReadState()
        #expect(state.prepare(request(enabled: false)) == .release)
        #expect(state.prepare(request(visible: false)) == .release)
        #expect(state.prepare(request(selected: false)) == .retain)
        #expect(state.snapshot == nil)
    }
}
