import Foundation
import Observation
import Testing
@testable import Pulse

@Suite("Added account refresh", .serialized)
@MainActor
struct AccountRefreshTests {
    private final class Requests {
        var accounts: [AccountKey] = []
        func read(_ account: AccountKey) -> ProviderUsage {
            accounts.append(account)
            return .unavailable(account, reason: .signedOut)
        }
    }

    private func idle(_ store: UsageStore) async {
        // Other suites animate on the main actor for longer than a short
        // timeout. Wait for completion itself, not time spent waiting to run.
        while store.isRefreshing {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = store.isRefreshing
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }

    @Test("A timer pass skips a recently checked added account, even after failure")
    func timerDoesNotRepeatAddedRequest() async {
        let extra = ExtraAccount(provider: .codex, slot: "synthetic", label: "Synthetic")
        let settings = AppSettings(
            enabledAccounts: [Provider.deepSeek.rawValue, extra.key.id], extraAccounts: [extra]
        )
        let requests = Requests()
        let store = UsageStore(settings: settings, activity: AgentActivityMonitor { _ in [:] },
                               readAddedAccount: { requests.read($0) })
        defer { store.stop() }
        store.refresh(dueOnly: true)
        await idle(store)
        #expect(requests.accounts == [extra.key])
        let before = store.diagnostics[Provider.deepSeek.rawValue]?.checkedAt
        store.refresh(dueOnly: true)
        await idle(store)
        #expect(requests.accounts == [extra.key])
        #expect(store.diagnostics[Provider.deepSeek.rawValue]?.checkedAt == before)

        // Explicit full refreshes still ask now, regardless of the cadence.
        store.refresh()
        await idle(store)
        #expect(requests.accounts == [extra.key, extra.key])
    }

    @Test("A manual check advances only that account's schedule")
    func manualRefreshCounts() async {
        let first = ExtraAccount(provider: .codex, slot: "first", label: "First")
        let second = ExtraAccount(provider: .codex, slot: "second", label: "Second")
        let settings = AppSettings(enabledAccounts: [first.key.id, second.key.id], extraAccounts: [first, second])
        let requests = Requests()
        let store = UsageStore(settings: settings, activity: AgentActivityMonitor { _ in [:] },
                               readAddedAccount: { requests.read($0) })
        defer { store.stop() }
        store.refresh(first.key)
        await idle(store)
        store.refresh(dueOnly: true)
        await idle(store)
        #expect(requests.accounts == [first.key, second.key])
    }

    @Test("Only an explicit refresh queues a full pass while a manual read is running", arguments: [true, false])
    func refreshDuringManualRead(dueOnly: Bool) async {
        let extra = ExtraAccount(provider: .codex, slot: "overlap", label: "Overlap")
        let settings = AppSettings(enabledAccounts: [extra.key.id], extraAccounts: [extra])
        let requests = Requests()
        var duringRead: (() -> Void)?
        let store = UsageStore(settings: settings, activity: AgentActivityMonitor { _ in [:] },
                               readAddedAccount: { account in
            let tick = duringRead
            duringRead = nil
            tick?()
            return requests.read(account)
        })
        defer { store.stop() }
        duringRead = { [weak store] in store?.refresh(dueOnly: dueOnly) }
        store.refresh(extra.key)
        await idle(store)
        #expect(requests.accounts == (dueOnly ? [extra.key] : [extra.key, extra.key]))
    }
}
