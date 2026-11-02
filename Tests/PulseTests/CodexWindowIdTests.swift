import Foundation
import Testing
@testable import Pulse

/// The same Plus account read over both routes. A limit has to come back
/// under one id from either, or a pinned ring comes loose whenever the read
/// falls back to the app server (issue #102).
struct CodexWindowIdTests {
    private static var http: [String: Any] { [
        "plan_type": "plus",
        "rate_limit": [
            "primary_window": ["used_percent": 12, "limit_window_seconds": 18_000, "reset_at": 1_900_000_000],
            "secondary_window": ["used_percent": 40, "limit_window_seconds": 604_800, "reset_at": 1_900_500_000],
        ],
        "additional_rate_limits": [
            ["limit_name": "GPT-5-Codex-Spark", "metered_feature": "codex_bengalfox",
             "rate_limit": ["primary_window": ["used_percent": 5, "limit_window_seconds": 18_000]]],
        ],
    ] }

    private static var appServer: [String: Any] { [
        "rateLimitsByLimitId": [
            "codex": [
                "planType": "plus",
                "primary": ["usedPercent": 12, "windowDurationMins": 300, "resetsAt": 1_900_000_000],
                "secondary": ["usedPercent": 40, "windowDurationMins": 10_080, "resetsAt": 1_900_500_000],
            ],
            "codex_bengalfox": [
                "limitName": "GPT-5-Codex-Spark",
                "primary": ["usedPercent": 5, "windowDurationMins": 300],
            ],
        ],
    ] }

    @Test("Both routes name each limit the same way")
    func sameIds() {
        let overHTTP = CodexUsageService.parseUsageResponse(Self.http, for: AccountKey(.codex))
        let overAppServer = CodexUsageService.parseAppServerResponse(Self.appServer)
        #expect(Set(overHTTP.windows.map(\.id)) == Set(overAppServer.windows.map(\.id)))
        #expect(overHTTP.windows.map(\.id).contains("codex.primary_window"))
    }

    @Test("A ring pinned to the 5-hour limit stays on it over either route")
    func pinHolds() {
        for usage in [CodexUsageService.parseUsageResponse(Self.http, for: AccountKey(.codex)),
                      CodexUsageService.parseAppServerResponse(Self.appServer)] {
            #expect(usage.headlineWindow(preferring: "codex.primary_window")?.kind == .fiveHour)
        }
    }

    @Test("A pin saved under the app server's old spelling is renamed; others are left alone")
    func oldPinsRenamed() {
        let renamed = AppSettings.codexPinsNamedLikeHTTP([
            "codex": "codex.primary",
            "codex#a1": "codex_bengalfox.secondary",
            "codex#b2": "codex.secondary_window",
            "claudeCode": "claude.primary",
        ])
        #expect(renamed == [
            "codex": "codex.primary_window",
            "codex#a1": "codex_bengalfox.secondary_window",
            "codex#b2": "codex.secondary_window",
            "claudeCode": "claude.primary",
        ])
    }
}
