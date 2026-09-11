import Foundation
import Testing
@testable import Pulse

@Suite("Connection diagnostics")
struct ConnectionDiagnosticTests {
    private func reading(_ account: AccountKey, at date: Date, state: ProviderUsage.State = .live) -> ProviderUsage {
        ProviderUsage(account: account, windows: [
            UsageWindow(id: "weekly", kind: .weekly, scope: nil, usedFraction: 0.5,
                        windowSeconds: 604_800, resetsAt: nil)
        ], observedAt: date, state: state, plan: "private-plan", creditBalance: "private-balance")
    }

    @Test("A failed route stays visible when the cache supplies another route's reading")
    func failureThroughCache() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "pulse-diagnostic-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        let account = AccountKey(.claudeCode)
        let observedAt = Date().addingTimeInterval(-300)
        _ = await cache.reconciled(reading(account, at: observedAt).recording(.desktopSession))
        let raw = ProviderUsage.unavailable(account, reason: .rateLimited).recording(.endpoint)
        let displayed = await cache.reconciled(raw)
        let diagnostic = ConnectionDiagnostic(raw: raw, displayed: displayed, previous: nil, now: Date())

        #expect(displayed.isCached)
        #expect(displayed.origin == .desktopSession)
        #expect(diagnostic.state == .unavailable(.rateLimited))
        #expect(diagnostic.attempts.first?.route == .endpoint)
        #expect(diagnostic.lastSuccessfulReadingAt == observedAt)

        // Reopen the file: provenance has to survive a restart, not just memory.
        let restarted = await UsageCache(file: file).lastReading(for: account)
        #expect(restarted?.origin == .desktopSession)
        #expect(restarted?.isCached == true)
        #expect(restarted?.attempts.isEmpty == true)
    }

    @Test("An older live capture is a successful check even when a newer cache wins")
    func captureDoesNotTurnIntoFailure() async {
        let file = FileManager.default.temporaryDirectory.appending(path: "pulse-diagnostic-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        let account = AccountKey(.claudeCode)
        let newer = Date()
        _ = await cache.reconciled(reading(account, at: newer).recording(.endpoint))
        let raw = reading(account, at: newer.addingTimeInterval(-60)).recording(.statusLine)
        let displayed = await cache.reconciled(raw)
        let diagnostic = ConnectionDiagnostic(raw: raw, displayed: displayed, previous: nil, now: newer)
        #expect(diagnostic.state == .live)
        #expect(displayed.origin == .endpoint)
        #expect(diagnostic.attempts.first?.route == .statusLine)
        #expect(diagnostic.lastSuccessfulReadingAt == newer)
    }

    @Test("A stale capture can be displayed directly without being called cached")
    func staleIsNotCache() async {
        let file = FileManager.default.temporaryDirectory.appending(path: "pulse-diagnostic-\(UUID()).json")
        let cache = UsageCache(file: file)
        let raw = reading(AccountKey(.claudeCode), at: Date(), state: .stale).recording(.statusLine)
        let displayed = await cache.reconciled(raw)
        #expect(!displayed.isCached)
        #expect(displayed.origin == .statusLine)
    }

    @Test("Old cache files have an unknown source rather than an inferred one")
    func legacyCacheSource() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "pulse-diagnostic-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = try JSONSerialization.data(withJSONObject: ["codex": [
            "windows": [], "observedAt": Date().timeIntervalSinceReferenceDate, "creditBalance": "$9"
        ]])
        try data.write(to: file)
        let restored = await UsageCache(file: file).lastReading(for: AccountKey(.codex))
        #expect(restored?.isCached == true)
        #expect(restored?.origin == nil)
    }

    @Test("Copied diagnostics contain only allowlisted fields, including earlier failures")
    func redactedReport() {
        let account = AccountKey(.claudeCode, slot: "private-email@example.com")
        let earlier = ProviderUsage.unavailable(account, reason: .claudeLoginExpired).recording(.endpoint)
        let raw = reading(account, at: Date()).recording(.desktopSession, after: earlier.attempts)
        let diagnostic = ConnectionDiagnostic(raw: raw, displayed: raw, previous: nil, now: Date())
        let report = ConnectionDiagnostic.report(account: account, preference: .automatic,
            displayed: raw, diagnostic: diagnostic, version: "test", now: Date())
        #expect(!report.contains("private-"))
        #expect(report.contains("accountType: added"))
        #expect(report.contains("endpoint -> claudeLoginExpired"))
        #expect(report.contains("desktopSession -> live"))
        #expect(!report.contains("0.5"))
    }

    @Test("Reauthentication targets an added account, never its ambient CLI")
    func remediesRespectAccountIdentity() {
        for (provider, reason): (Provider, ProviderUsage.Unavailability) in [
            (.claudeCode, .claudeLoginExpired), (.codex, .signInRequired),
            (.grok, .grokLoginExpired), (.grokBot, .cursorLoginExpired)
        ] {
            #expect(ConnectionRemedy.forReason(reason, account: AccountKey(provider, slot: "work")) == .signIn)
            #expect(ConnectionRemedy.forReason(reason, account: AccountKey(provider)) != .signIn)
        }
        #expect(ConnectionRemedy.forReason(.awaitingResponse, account: AccountKey(.claudeCode)) == nil)
        #expect(ConnectionRemedy.forReason(.apiKeyRefused, account: AccountKey(.deepSeek)) == .editCredential)
        #expect(ConnectionRemedy.forReason(.claudeDesktopKeyRefused, account: AccountKey(.claudeCode)) == .retry)
    }

    @Test("Pinned routes record credential failures without contacting a provider")
    func serviceBoundariesRecordFailures() async {
        var codex = CodexUsageService(server: CodexAppServer())
        codex.authFile = FileManager.default.temporaryDirectory.appending(path: "absent-\(UUID())")
        let codexResult = await codex.fetch(source: .endpoint)
        #expect(codexResult.attempts == [.init(route: .endpoint, state: .unavailable(.signInRequired))])
        let arkResult = await VolcengineUsageService(enteredKey: nil).fetch(source: .endpoint)
        #expect(arkResult.attempts == [.init(route: .endpoint, state: .unavailable(.apiKeyMissing))])
    }
}
