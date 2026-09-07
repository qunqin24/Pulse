import Foundation
import Testing
@testable import Pulse

/// `UsageCache.reconciled`, which decides what a card actually shows when a
/// fetch comes back empty — and which is where "a reading could go backwards"
/// was fixed. Exercised against a scratch file, which is what `init(file:)`
/// exists for.
@Suite("Cache reconciliation")
struct UsageCacheTests {
    private static let account = AccountKey(.codex)

    private static func cache() -> UsageCache {
        UsageCache(
            file: FileManager.default.temporaryDirectory
                .appending(path: "pulse-cache-test-\(UUID().uuidString).json")
        )
    }

    private static func window(_ id: String = "5h", used: Double, resetsAt: Date?) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: .fiveHour,
            scope: nil,
            usedFraction: used,
            windowSeconds: 5 * 3_600,
            resetsAt: resetsAt
        )
    }

    private static func live(_ windows: [UsageWindow], at observedAt: Date) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: windows,
            observedAt: observedAt,
            state: .live,
            plan: "Pro",
            creditBalance: nil
        )
    }

    /// An hour out, so nothing here trips the reset filter by accident.
    private static var soon: Date { Date().addingTimeInterval(3_600) }

    @Test("A live reading is handed back as it is, and banked")
    func liveIsStored() async {
        let cache = Self.cache()
        let reading = Self.live([Self.window(used: 0.4, resetsAt: Self.soon)], at: Date())

        let out = await cache.reconciled(reading)
        #expect(out.state == .live)
        #expect(out.windows.count == 1)

        let banked = await cache.lastReading(for: Self.account)
        #expect(banked?.state == .stale)
        #expect(banked?.windows.first?.usedFraction == 0.4)
    }

    @Test("A failed fetch falls back to the banked figures, marked stale")
    func failureFallsBackToCache() async {
        let cache = Self.cache()
        let observedAt = Date().addingTimeInterval(-300)
        _ = await cache.reconciled(Self.live([Self.window(used: 0.4, resetsAt: Self.soon)], at: observedAt))

        let out = await cache.reconciled(.unavailable(Self.account, reason: .unreachable))
        #expect(out.state == .stale)
        #expect(out.windows.first?.usedFraction == 0.4)
        // It carries its own date, so the card can say how old it is.
        #expect(out.observedAt.map { abs($0.timeIntervalSince(observedAt)) < 1 } == true)
    }

    @Test("A missing credential is never papered over")
    func missingCredentialIsReported() async {
        let cache = Self.cache()
        _ = await cache.reconciled(Self.live([Self.window(used: 0.4, resetsAt: Self.soon)], at: Date()))

        for reason: ProviderUsage.Unavailability in [
            .apiKeyMissing, .ollamaSessionMissing, .signedOut,
            .claudeDesktopNotSignedIn, .claudeDesktopKeyRefused
        ] {
            let out = await cache.reconciled(.unavailable(Self.account, reason: reason))
            #expect(out.state == .unavailable(reason), "\(reason) must not be hidden behind the cache")
        }
    }

    @Test("A reading never goes backwards")
    func olderReadingDoesNotWin() async {
        let cache = Self.cache()
        let newer = Date()
        _ = await cache.reconciled(Self.live([Self.window(used: 0.9, resetsAt: Self.soon)], at: newer))

        // The status-line route calls its capture live for ten minutes, so a
        // live reading can arrive older than what the endpoint banked. The
        // later of the two wins, not the one that called itself live.
        let out = await cache.reconciled(
            Self.live([Self.window(used: 0.5, resetsAt: Self.soon)], at: newer.addingTimeInterval(-600))
        )
        #expect(out.windows.first?.usedFraction == 0.9)
        #expect(out.state == .stale)
    }

    @Test("A window that has already reset is dropped, not aged")
    func expiredWindowIsDropped() async {
        let cache = Self.cache()
        _ = await cache.reconciled(
            Self.live([Self.window(used: 0.9, resetsAt: Date().addingTimeInterval(-60))], at: Date())
        )

        // Its only window has reset, so there is nothing left worth showing —
        // and the failure is reported rather than dressed in yesterday's
        // percentages.
        let out = await cache.reconciled(.unavailable(Self.account, reason: .unreachable))
        #expect(out.state == .unavailable(.unreachable))
    }

    @Test("Nothing older than a day is offered")
    func staleBeyondADayIsDropped() async {
        let cache = Self.cache()
        _ = await cache.reconciled(
            Self.live(
                [Self.window(used: 0.9, resetsAt: Date().addingTimeInterval(48 * 3_600))],
                at: Date().addingTimeInterval(-(UsageCache.maximumAge + 3_600))
            )
        )

        let out = await cache.reconciled(.unavailable(Self.account, reason: .unreachable))
        #expect(out.state == .unavailable(.unreachable))
    }

    @Test("A fetch with nothing in it takes the cache's figures")
    func emptyFetchTakesTheCache() async {
        let cache = Self.cache()
        _ = await cache.reconciled(Self.live([Self.window(used: 0.4, resetsAt: Self.soon)], at: Date()))

        let empty = ProviderUsage(
            account: Self.account,
            windows: [],
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: nil
        )
        let out = await cache.reconciled(empty)
        #expect(out.windows.count == 1)
        #expect(out.state == .stale)
    }
}
