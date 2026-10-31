import Foundation
import Testing
@testable import Pulse

/// Which providers the detailed card can show a history for, from where, and
/// how several agents' records become one.
struct CardHistoryTests {
    @Test func eachSourceGoesToTheProvidersItBelongsTo() {
        #expect(Provider.claudeCode.cardHistory == .transcripts)
        #expect(Provider.codex.cardHistory == .transcripts)
        // The statistics Z.ai and Zhipu publish: asked of the provider, not read here.
        #expect(Provider.zai.cardHistory == .accountStatistics)
        #expect(Provider.glmCoding.cardHistory == .accountStatistics)
        #expect(Provider.kimiCode.cardHistory == .agents([.kimiCLI]))
        // A provider with no records anywhere has no section to show — until
        // its console sign-in is kept. Passed in: whether one is kept is this
        // Mac's state (another test's `loadAPIKeys()` reads the real store).
        #expect(Provider.deepSeek.cardHistory(openCodeSession: false, deepSeekSession: false) == nil)
        #expect(Provider.deepSeek.cardHistory(openCodeSession: false, deepSeekSession: true) == .accountLogs)
        #expect(Provider.openCodeGo.cardHistory(openCodeSession: true, deepSeekSession: false) == .accountLogs)
    }

    @Test func devinReadsItsOmpRecordsWhenItsOwnClientsAreAway() {
        // The two Devin clients plus the records an omp transcript routes to
        // the `devin` backend — the machine whose only Devin usage ran through
        // `omp --model devin/…`.
        #expect(
            Provider.devin.cardHistory
                == .agents([.devinCLI, .devinDesktop], slices: [
                    CardHistorySource.AgentSlice(agent: .omp, provider: "devin", vendor: "devin"),
                ])
        )
    }

    /// The settings pane shows a history exactly where the card does: the
    /// agents that borrow a provider's mark too, which the pane once left out
    /// — MiniMax's card had MiniMax Code's history and its pane had none.
    @Test func thePaneHasAHistoryWhereverTheCardDoes() {
        #expect(Provider.minimax.providesHistory)
        #expect(Provider.kimiCode.providesHistory)
        #expect(Provider.commandCode.providesHistory)
        #expect(Provider.claudeCode.providesHistory)
        #expect(Provider.zai.providesHistory)
        // Nothing reads a gateway's history.
        #expect(Provider.sub2api.cardHistory == nil)
        #expect(!Provider.sub2api.providesHistory)
    }

    @Test func onlyThisMacsRecordsWaitForTokenSpend() {
        #expect(CardHistorySource.transcripts.readsThisMac)
        #expect(CardHistorySource.agents([.grok]).readsThisMac)
        #expect(!CardHistorySource.accountStatistics.readsThisMac)
    }

    @Test func severalAgentsAddUpDayByDayWithTheGapsClosed() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        func day(_ offset: Int, _ tokens: Int, _ model: String) -> LedgerDay {
            LedgerDay(date: calendar.date(byAdding: .day, value: offset, to: start)!,
                      tokens: tokens, cost: Double(tokens) / 100, unpricedTokens: 0, models: [model: tokens])
        }
        func ledger(_ days: [LedgerDay]) -> UsageLedger {
            UsageLedger(days: days, earliest: days.first?.date, unpricedModels: [], modelNames: [:], slots: [])
        }

        let added = UsageLedger.adding([
            ledger([day(0, 100, "a"), day(1, 50, "a")]),
            ledger([day(1, 30, "b"), day(3, 20, "b")]),
            .empty,
        ])

        #expect(added.days.map(\.tokens) == [100, 80, 0, 20])
        #expect(added.days[1].models == ["a": 50, "b": 30])
        #expect(abs(added.allTime.cost - 2.0) < 0.0001)
        #expect(added.earliest == start)
    }

    /// The value estimate reads quarter-hours, so adding agents keeps them,
    /// in time order — `BudgetEstimator` takes the first as where the records begin.
    @Test func addingKeepsTheQuarterHoursInOrder() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        func ledger(_ offsets: [TimeInterval]) -> UsageLedger {
            let day = LedgerDay(date: Calendar.current.startOfDay(for: start), tokens: 10, cost: 1,
                                unpricedTokens: 0, models: [:])
            return UsageLedger(days: [day], earliest: start, unpricedModels: [], modelNames: [:],
                               slots: offsets.map { .init(start: start.addingTimeInterval($0), tokens: 10, cost: 0.5) })
        }
        let added = UsageLedger.adding([ledger([900, 2700]), ledger([0, 1800])])
        #expect(added.slots.map(\.start) == [0, 900, 1800, 2700].map { start.addingTimeInterval($0) })
        #expect(abs(added.spend(since: start.addingTimeInterval(900)).cost - 1.5) < 0.0001)
    }

    @Test func oneLedgerIsPassedThroughUntouched() {
        let only = UsageLedger(days: [LedgerDay(date: Date(timeIntervalSince1970: 0), tokens: 5, cost: 0,
                                                unpricedTokens: 5, models: [:])],
                               earliest: nil, unpricedModels: ["x"], modelNames: [:], slots: [])
        #expect(UsageLedger.adding([.empty, only]) == only)
        #expect(UsageLedger.adding([]).days.isEmpty)
    }

    /// OpenCode Go states what each limit is worth; there is nothing to estimate.
    @Test func noValueEstimateWhereTheProviderStatesTheAllowance() {
        #expect(!UsageDetailCard.estimatesValue(for: .openCodeGo))
        #expect(!UsageDetailCard.estimatesValue(for: .deepSeek))
        #expect(UsageDetailCard.estimatesValue(for: .claudeCode))
        #expect(UsageDetailCard.estimatesValue(for: .codex))
    }
}
