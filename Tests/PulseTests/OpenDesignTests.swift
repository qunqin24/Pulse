import Foundation
import Testing
@testable import Pulse

/// Open Design's plan windows — the Coding Plan's (OpenDesign Go) and the
/// billing snapshot's — read with the console's browser session or the login
/// the desktop app saved.
///
/// **The fixtures are second-hand**: written from Open Design's own code
/// (contracts, the daemon's reads, the console's bundle) and from CodexBar's
/// and the DSH plugins' notes — not captured from a live account.
/// They pin the shape Pulse reads; they do not prove the shape is right.
@Suite("Open Design")
struct OpenDesignTests {
    private let context = ProfileContext(provider: .openDesign, credential: nil, serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// A home folder holding `~/.amr/config.json` with `json`, removed after.
    private func home(config json: String) throws -> (URL, () -> Void) {
        let home = FileManager.default.temporaryDirectory.appending(path: "OpenDesignTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: ".amr"), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: home.appending(path: ".amr/config.json"))
        return (home, { try? FileManager.default.removeItem(at: home) })
    }

    @Test("The five-hour and seven-day windows, the plan and the wallet")
    func snapshot() throws {
        let now = Date(timeIntervalSince1970: 1_762_848_000)
        let usage = OpenDesignUsageService.reading(from: try fixture("opendesign-billing-snapshot"), context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.openDesign))
        #expect(usage.windows.map(\.id) == ["openDesign.fiveHour", "openDesign.weekly"])

        let fiveHour = usage.windows[0]
        #expect(fiveHour.kind == .fiveHour)
        #expect(fiveHour.windowSeconds == 18_000)
        #expect(fiveHour.usedFraction == 1)
        #expect(fiveHour.isExhausted)
        #expect(fiveHour.resetsAt == ISO8601DateFormatter().date(from: "2026-11-11T12:00:00Z"))

        let weekly = usage.windows[1]
        #expect(weekly.kind == .weekly)
        #expect(weekly.windowSeconds == 604_800)
        #expect(abs(weekly.usedFraction - 0.55) < 0.000_1)
        #expect(!weekly.isExhausted)
        #expect(weekly.resetsAt == ISO8601DateFormatter().date(from: "2026-11-15T00:00:00Z"))

        #expect(usage.plan == "Plus")
        #expect(usage.creditBalance != nil)
    }

    @Test("OpenDesign Go: the Coding Plan's five-hour and seven-day windows, named by their length")
    func codingPlan() throws {
        let usage = OpenDesignUsageService.codingPlanReading(from: try fixture("opendesign-funding-check-go"), context: context)

        #expect(usage.state == .live)
        #expect(usage.windows.map(\.id) == ["openDesign.codingPlan.go-5h", "openDesign.codingPlan.go-7d"])

        let fiveHour = usage.windows[0]
        #expect(fiveHour.kind == .fiveHour)
        #expect(fiveHour.windowSeconds == 18_000)
        #expect(fiveHour.usedFraction == 1)
        #expect(fiveHour.isExhausted)
        #expect(fiveHour.resetsAt == ISO8601DateFormatter().date(from: "2026-11-11T12:00:00Z"))

        // Pools far past 2^53 still read as a share.
        let weekly = usage.windows[1]
        #expect(weekly.kind == .weekly)
        #expect(abs(weekly.usedFraction - 0.55) < 0.000_1)
        #expect(!weekly.isExhausted)

        #expect(usage.plan == "Go")
        #expect(usage.creditBalance != nil)
    }

    @Test("The console's coding-plan-usage reply: the plan object alone, remaining credits only")
    func consoleCodingPlanUsage() throws {
        let reply = Data(#"""
        {"eligible":true,"tier":"go","windows":[
          {"policyId":"go-7d","durationSeconds":604800,"remainingCredits":"45","limitCredits":"100","resetsAt":"2026-11-15T00:00:00Z"},
          {"policyId":"go-5h","durationSeconds":18000,"remainingCredits":"20","limitCredits":"20","resetsAt":"2026-11-11T12:00:00Z"}
        ]}
        """#.utf8)
        let usage = OpenDesignUsageService.codingPlanReading(from: reply, context: context)
        #expect(usage.state == .live)
        #expect(usage.plan == "Go")
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(usage.windows[0].usedFraction == 0)
        #expect(abs(usage.windows[1].usedFraction - 0.55) < 0.000_1)
        #expect(usage.creditBalance == nil)
    }

    @Test("A Coding Plan window of a length Pulse has no kind for is left off, not guessed")
    func codingPlanOddLength() {
        let reply = Data(#"""
        {"codingPlan":{"tier":"plus","windows":[
          {"policyId":"x","durationSeconds":5400,"usedCredits":"1","remainingCredits":"1","limitCredits":"2"},
          {"policyId":"y","durationSeconds":604800,"usedCredits":"1","remainingCredits":"0","limitCredits":"0"}
        ]}}
        """#.utf8)
        let usage = OpenDesignUsageService.codingPlanReading(from: reply, context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("Windows with no limit, an unknown kind or no figures are left off, never drawn as spent")
    func unusableWindows() {
        let reply = Data(#"""
        {"billing":{"planId":null},"designPlanWindows":[
          {"kind":"5h","remainingCredits":"0","limitCredits":"0"},
          {"kind":"30d","remainingCredits":"1","limitCredits":"2"},
          {"kind":"7d","limitCredits":"100"}
        ]}
        """#.utf8)
        let usage = OpenDesignUsageService.reading(from: reply, context: context)
        guard case .unavailable(let reason) = usage.state else {
            Issue.record("expected unavailable, got \(usage.state)")
            return
        }
        #expect(reason == .noLimitsReported)
    }

    @Test("A wallet alone still reads, with no ring of its own")
    func walletOnly() {
        let reply = Data(#"{"billing":{"planId":"go"},"wallet":{"balanceUsd":"3.00"}}"#.utf8)
        let usage = OpenDesignUsageService.reading(from: reply, context: context)
        #expect(usage.state == .live)
        #expect(usage.windows.isEmpty)
        #expect(usage.plan == "Go")
        #expect(usage.creditBalance != nil)
    }

    @Test("A reply that is not JSON is unreadable")
    func unreadable() {
        let usage = OpenDesignUsageService.reading(from: Data("<html>".utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("The owner's default personal workspace is read, not a team or an older personal one")
    func workspace() throws {
        #expect(OpenDesignUsageService.personalWorkspace(from: try fixture("opendesign-workspaces")) == "ws-personal-1")

        let noDefault = Data(#"{"items":[{"workspaceId":"t","workspaceType":"team"},{"workspaceId":"p","workspaceType":"personal"}]}"#.utf8)
        #expect(OpenDesignUsageService.personalWorkspace(from: noDefault) == "p")

        let teamOnly = Data(#"{"items":[{"workspaceId":"t","workspaceType":"team","isDefault":true}]}"#.utf8)
        #expect(OpenDesignUsageService.personalWorkspace(from: teamOnly) == nil)
        #expect(OpenDesignUsageService.personalWorkspace(from: Data("{}".utf8)) == nil)
    }

    @Test("The browser session goes as a Cookie header, the app's login as a bearer, both naming the workspace")
    func credentials() throws {
        let cookie = OpenDesignUsageService.Credential.session("__Secure-better-auth.session_token=abc")
        let url = OpenDesignUsageService.billingURL(cookie.api, "ws 1", "coding-plan-usage")
        #expect(url.absoluteString == "https://amr-api.open-design.ai/api/v1/workspaces/ws%201/billing/coding-plan-usage")
        let byCookie = cookie.request(url, workspace: "ws 1")
        #expect(byCookie.value(forHTTPHeaderField: "Cookie") == "__Secure-better-auth.session_token=abc")
        #expect(byCookie.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(byCookie.value(forHTTPHeaderField: "x-vela-workspace-id") == "ws 1")
        #expect(cookie.routes == ["coding-plan-usage", "snapshot"])
        #expect(cookie.refused == .sessionExpired)

        let app = OpenDesignUsageService.Credential.app(.init(controlKey: "ck", api: OpenDesignUsageService.defaultAPI))
        let byKey = app.request(url, workspace: "ws 1")
        #expect(byKey.value(forHTTPHeaderField: "Authorization") == "Bearer ck")
        #expect(byKey.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(app.routes.first == "funding-check")
        #expect(app.refused == .localLoginExpired)
    }

    @Test("Only the better-auth cookies are kept, and the session token must be among them")
    func cookieFilter() throws {
        let names = ["__Secure-better-auth.session_token", "__Secure-better-auth.*"]
        let kept = ProviderProfile.keep(
            "_ga=1; __Secure-better-auth.session_token=t; __Secure-better-auth.session_data=d; other=x",
            cookies: names
        )
        #expect(kept?.contains("__Secure-better-auth.session_token=t") == true)
        #expect(kept?.contains("__Secure-better-auth.session_data=d") == true)
        #expect(kept?.contains("_ga") == false)
        #expect(kept?.contains("other") == false)
        #expect(ProviderProfile.keep("__Secure-better-auth.session_data=d", cookies: names) == nil)
    }

    @Test("With no browser session and no app login, Pulse asks for the session, and sends nothing")
    func nothingToReadWith() async throws {
        let (folder, cleanup) = try home(config: #"{"profiles":{}}"#)
        defer { cleanup() }
        let usage = await OpenDesignUsageService.fetch(context, home: folder)
        #expect(usage.state == .unavailable(.sessionMissing))
    }

    @Test("The prod profile's control key and API address are read from ~/.amr")
    func savedLogin() throws {
        let (folder, cleanup) = try home(config: #"""
        {"profiles":{"prod":{"controlKey":" ck_live ","apiUrl":"https://amr-api.open-design.ai","runtimeKey":"rk"},
                     "test":{"controlKey":"ck_test"}}}
        """#)
        defer { cleanup() }
        let login = try #require(OpenDesignUsageService.savedLogin(home: folder))
        #expect(login.controlKey == "ck_live")
        #expect(login.api == URL(string: "https://amr-api.open-design.ai"))
    }

    @Test("No address saved means Open Design's own")
    func defaultAddress() throws {
        let (folder, cleanup) = try home(config: #"{"profiles":{"prod":{"controlKey":"ck"}}}"#)
        defer { cleanup() }
        #expect(OpenDesignUsageService.savedLogin(home: folder)?.api == OpenDesignUsageService.defaultAPI)
    }

    @Test("The key is never sent to an address that is not https on open-design.ai", arguments: [
        "http://amr-api.open-design.ai",
        "https://example.com",
        "https://open-design.ai.example.com",
        "https://user:pass@amr-api.open-design.ai",
    ])
    func foreignAddress(address: String) throws {
        let (folder, cleanup) = try home(config: #"{"profiles":{"prod":{"controlKey":"ck","apiUrl":"\#(address)"}}}"#)
        defer { cleanup() }
        #expect(OpenDesignUsageService.savedLogin(home: folder) == nil)
    }

    @Test("A login still in progress, a missing key or no file is no login")
    func missingLogin() throws {
        let (pending, cleanPending) = try home(config: #"{"profiles":{"prod":{"controlKey":"ck","pendingLogin":{"id":"x"}}}}"#)
        defer { cleanPending() }
        #expect(OpenDesignUsageService.savedLogin(home: pending) == nil)

        let (blank, cleanBlank) = try home(config: #"{"profiles":{"prod":{"controlKey":"  "}}}"#)
        defer { cleanBlank() }
        #expect(OpenDesignUsageService.savedLogin(home: blank) == nil)

        let nowhere = FileManager.default.temporaryDirectory.appending(path: "OpenDesignTests-missing-\(UUID().uuidString)")
        #expect(OpenDesignUsageService.savedLogin(home: nowhere) == nil)
    }
}
