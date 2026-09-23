import Foundation
import Observation

/// Window-scoped arithmetic over a completed read. Each level keeps one
/// result, so opening a model does not rebuild its overview or agent summary.
@MainActor
@Observable
final class SpendSummaryStore {
    struct Context: Hashable, Sendable {
        let snapshotID: UUID
        let span: SpendSpan
        let day: Date
        let calendar: Calendar
    }

    struct Scope: Hashable, Sendable {
        let context: Context
        let agent: SpendAgent?
    }

    struct Request: Hashable, Sendable {
        let scope: Scope
        let model: String?
    }

    struct Work: Sendable {
        let request: Request
        let ledgers: [SpendAgent: UsageLedger]
        let overview: Bool
        let focused: Bool
        let model: Bool

        var isEmpty: Bool { !overview && !focused && !model }
    }

    struct Result: Sendable {
        var overview: SpendSummary?
        var focused: SpendSummary?
        var model: ModelSpendSummary?
    }

    struct Presentation {
        var overview = SpendSummary()
        var focused = SpendSummary()
        var model = ModelSpendSummary()
        var isCalculating = false
    }

    private struct Entry<Key: Equatable, Value> {
        let key: Key
        let value: Value
    }

    private var overview: Entry<Context, SpendSummary>?
    private var focused: Entry<Scope, SpendSummary>?
    private var model: Entry<Request, ModelSpendSummary>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var worker: Task<Result, Never>?
    private let calculate: @Sendable (Work) async -> Result

    init(calculate: @escaping @Sendable (Work) async -> Result = { SpendSummaryStore.calculate($0) }) {
        self.calculate = calculate
    }

    /// Gate display by the selection too: a SwiftUI task may not have started
    /// yet when the new header is drawn. Old figures must never wear that header.
    func presentation(for request: Request?) -> Presentation {
        guard let request else { return Presentation() }
        var result = Presentation()
        if let overview, overview.key == request.scope.context { result.overview = overview.value }
        if let focused, focused.key == request.scope { result.focused = focused.value }
        if let model, model.key == request { result.model = model.value }
        result.isCalculating = needsOverview(request) || needsFocus(request) || needsModel(request)
        return result
    }

    func update(_ request: Request, ledgers: [SpendAgent: UsageLedger]) async {
        guard !Task.isCancelled else { return }
        cancel()
        let generation = generation
        let work = Work(request: request, ledgers: ledgers, overview: needsOverview(request),
                        focused: needsFocus(request), model: needsModel(request))
        guard !work.isEmpty else { return }

        // Task {} inherits MainActor here; detached is deliberate. The worker
        // receives only immutable, Sendable inputs and returns plain summaries.
        let worker = Task.detached(priority: .userInitiated) { [calculate] in
            await calculate(work)
        }
        self.worker = worker
        defer {
            if generation == self.generation { self.worker = nil }
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard generation == self.generation, !Task.isCancelled, !worker.isCancelled else { return }
        if let value = result.overview { overview = Entry(key: request.scope.context, value: value) }
        if let value = result.focused { focused = Entry(key: request.scope, value: value) }
        if let value = result.model { model = Entry(key: request, value: value) }
    }

    /// Leaving the pane cancels work but keeps completed figures for Back.
    func cancel() {
        generation += 1
        worker?.cancel()
        worker = nil
    }

    /// Closing, disabling or rescanning releases the previous snapshot's detail.
    func reset() {
        cancel()
        overview = nil
        focused = nil
        model = nil
    }

    private func needsOverview(_ request: Request) -> Bool { overview?.key != request.scope.context }
    private func needsFocus(_ request: Request) -> Bool {
        request.scope.agent != nil && focused?.key != request.scope
    }
    private func needsModel(_ request: Request) -> Bool {
        request.model != nil && model?.key != request
    }

    nonisolated static func calculate(_ work: Work) -> Result {
        let context = work.request.scope.context
        var result = Result()
        guard !Task.isCancelled else { return result }
        if work.overview {
            result.overview = SpendSummary.of(work.ledgers, overLast: context.span.days,
                                              now: context.day, calendar: context.calendar)
        }
        guard !Task.isCancelled else { return result }
        let scoped = work.request.scope.agent.map { agent in
            work.ledgers.filter { $0.key == agent }
        } ?? work.ledgers
        if work.focused {
            result.focused = SpendSummary.of(scoped, overLast: context.span.days,
                                             now: context.day, calendar: context.calendar)
        }
        guard !Task.isCancelled else { return result }
        if work.model, let name = work.request.model {
            result.model = ModelSpendSummary.of(scoped, named: name, overLast: context.span.days,
                                                now: context.day, calendar: context.calendar)
        }
        return result
    }
}
