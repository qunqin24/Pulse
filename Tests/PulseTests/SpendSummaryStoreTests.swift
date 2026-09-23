import Foundation
import Testing
@testable import Pulse

@Suite("Spend summary selection")
@MainActor
struct SpendSummaryStoreTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func context(span: SpendSpan = .week, id: UUID = UUID()) -> SpendSummaryStore.Context {
        .init(snapshotID: id, span: span,
              day: calendar.date(from: DateComponents(year: 2026, month: 9, day: 23))!, calendar: calendar)
    }

    private func request(_ context: SpendSummaryStore.Context, agent: SpendAgent? = nil,
                         model: String? = nil) -> SpendSummaryStore.Request {
        .init(scope: .init(context: context, agent: agent), model: model)
    }

    private var ledgers: [SpendAgent: UsageLedger] {
        [
            .codex: UsageLedgerReader.price(
                ["2026-09-22 09:00": ["a": TokenTally(input: 100), "b": TokenTally(input: 200)]],
                with: [:], calendar: calendar),
            .claudeCode: UsageLedgerReader.price(
                ["2026-09-23 10:00": ["a": TokenTally(input: 300)]], with: [:], calendar: calendar)
        ]
    }

    private actor Recorder {
        private(set) var work: [SpendSummaryStore.Work] = []
        func record(_ work: SpendSummaryStore.Work) { self.work.append(work) }
    }

    private nonisolated static func checkWorkerThread() {
        #expect(!Thread.isMainThread)
    }

    @Test("Model selection calculates only model detail, off the main thread; Back reuses the overview")
    func independentLevels() async {
        let recorder = Recorder()
        let store = SpendSummaryStore { work in
            Self.checkWorkerThread()
            await recorder.record(work)
            return SpendSummaryStore.calculate(work)
        }
        let context = context()
        let overview = request(context)
        await store.update(overview, ledgers: ledgers)
        #expect(store.presentation(for: overview).overview.tokens == 600)

        let first = request(context, model: "a")
        await store.update(first, ledgers: ledgers)
        #expect(store.presentation(for: first).model.tokens == 400)
        let second = request(context, model: "b")
        #expect(store.presentation(for: second).isCalculating)
        #expect(store.presentation(for: second).model.tokens == 0, "A new header must not show the previous model")
        await store.update(second, ledgers: ledgers)
        #expect(store.presentation(for: second).model.tokens == 200)
        store.cancel()
        await store.update(overview, ledgers: ledgers)
        #expect(!store.presentation(for: overview).isCalculating)

        let agent = request(context, agent: .codex)
        await store.update(agent, ledgers: ledgers)
        #expect(store.presentation(for: agent).focused.tokens == 300)
        let detail = request(context, agent: .codex, model: "a")
        await store.update(detail, ledgers: ledgers)
        #expect(store.presentation(for: detail).model.tokens == 100)
        let otherAgent = request(context, agent: .claudeCode, model: "a")
        await store.update(otherAgent, ledgers: ledgers)
        #expect(store.presentation(for: otherAgent).model.tokens == 300)
        let work = await recorder.work
        #expect(work.count == 6)
        #expect(work.map(\.overview) == [true, false, false, false, false, false])
        #expect(work.map(\.focused) == [false, false, false, true, false, true])
        #expect(work.map(\.model) == [false, true, true, false, true, true])
        store.reset()
        let released = store.presentation(for: otherAgent)
        #expect(released.overview.tokens == 0 && released.focused.tokens == 0 && released.model.tokens == 0)
        #expect(released.isCalculating)
    }

    @Test("Span and snapshot changes invalidate every affected level, including a completed empty result")
    func newInputs() async {
        let store = SpendSummaryStore()
        let week = context()
        let initial = request(week, agent: .codex, model: "a")
        await store.update(initial, ledgers: ledgers)
        let today = request(context(span: .today, id: week.snapshotID), agent: .codex, model: "a")
        #expect(store.presentation(for: today).isCalculating)
        await store.update(today, ledgers: ledgers)
        let figures = store.presentation(for: today)
        #expect(figures.overview.tokens == 300)
        #expect(figures.focused.tokens == 0)
        #expect(figures.model.tokens == 0)
        #expect(!figures.isCalculating, "A computed empty model is ready, not a reason to keep calculating")

        let replacement = request(context(), model: "a")
        await store.update(replacement, ledgers: [:])
        #expect(store.presentation(for: replacement).overview.tokens == 0)
        #expect(!store.presentation(for: replacement).isCalculating)
    }

    @Test("Day and calendar changes cannot reuse a previous cutoff")
    func calendarBoundary() async {
        let store = SpendSummaryStore()
        let original = context(span: .today)
        await store.update(request(original), ledgers: ledgers)
        let next = SpendSummaryStore.Context(snapshotID: original.snapshotID, span: .today,
                                            day: original.day.addingTimeInterval(86_400), calendar: calendar)
        #expect(store.presentation(for: request(next)).isCalculating)
        await store.update(request(next), ledgers: ledgers)
        #expect(store.presentation(for: request(next)).overview.tokens == 0)
        var changed = calendar
        changed.timeZone = TimeZone(secondsFromGMT: 3_600)!
        let differentCalendar = SpendSummaryStore.Context(snapshotID: next.snapshotID, span: .today,
                                                         day: next.day, calendar: changed)
        #expect(store.presentation(for: request(differentCalendar)).isCalculating)
    }

    /// Holds valid results even after cancellation, like a calculation that
    /// finishes its last synchronous loop before noticing it was superseded.
    private actor Gate {
        private var count = 0
        private var held: [Int: CheckedContinuation<Void, Never>] = [:]
        private var arrivals: [(Int, CheckedContinuation<Void, Never>)] = []

        func hold() async {
            count += 1
            let id = count
            await withCheckedContinuation { continuation in
                held[id] = continuation
                let ready = arrivals.filter { $0.0 <= count }
                arrivals.removeAll { $0.0 <= count }
                for (_, waiter) in ready { waiter.resume() }
            }
        }

        func waitFor(_ count: Int) async {
            if self.count >= count { return }
            await withCheckedContinuation { arrivals.append((count, $0)) }
        }

        func release(_ id: Int) { held.removeValue(forKey: id)?.resume() }
    }

    @Test("A slower old model cannot replace the newest model or its loading state")
    func latestSelectionWins() async {
        let gate = Gate()
        let store = SpendSummaryStore { work in
            let result = SpendSummaryStore.calculate(work)
            await gate.hold()
            return result
        }
        let context = context()
        let first = request(context, model: "a")
        let second = request(context, model: "b")
        let ledgers = ledgers
        let old = Task { await store.update(first, ledgers: ledgers) }
        await gate.waitFor(1)
        let latest = Task { await store.update(second, ledgers: ledgers) }
        await gate.waitFor(2)
        await gate.release(2)
        await latest.value
        #expect(store.presentation(for: second).model.tokens == 200)
        #expect(!store.presentation(for: second).isCalculating)
        await gate.release(1)
        await old.value
        #expect(store.presentation(for: second).model.tokens == 200)
        #expect(!store.presentation(for: second).isCalculating)
    }

    @Test("Cancellation and release reject results already calculated in the worker", arguments: [false, true])
    func abandonedWorkCannotPublish(reset: Bool) async {
        let gate = Gate()
        let store = SpendSummaryStore { work in
            let result = SpendSummaryStore.calculate(work)
            await gate.hold()
            return result
        }
        let request = request(context(), model: "a")
        let ledgers = ledgers
        let task = Task { await store.update(request, ledgers: ledgers) }
        await gate.waitFor(1)
        if reset { store.reset() } else { task.cancel() }
        await gate.release(1)
        await task.value
        #expect(store.presentation(for: request).overview.tokens == 0)
        #expect(store.presentation(for: request).model.tokens == 0)
        #expect(store.presentation(for: request).isCalculating)
    }
}
