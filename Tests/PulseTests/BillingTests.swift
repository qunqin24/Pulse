import Foundation
import Testing
@testable import Pulse

/// Which providers are subscriptions and which are API accounts, which decides
/// where each is listed. See `Provider.Billing`.
@Suite("Billing kind")
struct BillingTests {
    @Test("Money drawn down by the call is an API account; a plan is a subscription")
    func kinds() {
        for provider: Provider in [.deepSeek, .sub2api, .newAPI, .openAIPlatform, .xaiAPI, .moonshot, .liteLLM] {
            #expect(provider.billing == .api, "\(provider.rawValue)")
        }
        // A plan with a balance beside it is still a plan.
        for provider: Provider in [.claudeCode, .codex, .commandCode, .kimiCode, .clinePass, .amp, .kiloCode] {
            #expect(provider.billing == .subscription, "\(provider.rawValue)")
        }
    }

    @Test("Every API account that reports money says so, so its low-balance line is offered")
    func apiBalances() {
        for provider in Provider.builtIn where provider.billing == .api && provider.profile?.reportsSpendableBalance == true {
            #expect(provider.reportsSpendableBalance)
        }
    }
}

/// The Order group lists and moves only what the rail draws.
@Suite("Rail order among shown accounts")
@MainActor
struct ShownOrderTests {
    private func settings() -> AppSettings {
        AppSettings(enabledAccounts: ["codex", "claudeCode", "deepSeek"], providerOrder: ["codex", "kiro", "claudeCode", "deepSeek"])
    }

    @Test("An arrow moves past the next shown account, not past a hidden one")
    func arrowsSkipHidden() {
        let settings = settings()
        #expect(settings.shownAccounts.map(\.id) == ["codex", "claudeCode", "deepSeek"])
        settings.move(AccountKey(.claudeCode), by: -1)
        #expect(settings.shownAccounts.map(\.id) == ["claudeCode", "codex", "deepSeek"])
        // Kiro is off: it keeps a place, after the shown ones.
        #expect(settings.orderedAccounts.map(\.id).prefix(4) == ["claudeCode", "codex", "deepSeek", "kiro"])
    }

    @Test("A drop lands among the shown accounts, and the ends do nothing")
    func dropAndEnds() {
        let settings = settings()
        settings.move(AccountKey(.deepSeek), onto: AccountKey(.codex))
        #expect(settings.shownAccounts.map(\.id) == ["deepSeek", "codex", "claudeCode"])
        settings.move(AccountKey(.deepSeek), by: -1)
        #expect(settings.shownAccounts.map(\.id) == ["deepSeek", "codex", "claudeCode"])
        // A hidden account is not moved by either.
        settings.move(AccountKey(.kiro), by: 1)
        settings.move(AccountKey(.kiro), onto: AccountKey(.codex))
        #expect(settings.shownAccounts.map(\.id) == ["deepSeek", "codex", "claudeCode"])
    }
}

/// Codex's limit reset credits, as the card shows them: the count Codex
/// reported, or that it reported none.
@Suite("Codex reset credits")
@MainActor
struct CodexResetCreditsTests {
    @Test("The stated count is read, with the soonest expiry among the available ones")
    func count() {
        let limits: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 2,
            "credits": [
                ["title": "a", "status": "available", "expiresAt": 1_900_000_000],
                ["title": "b", "status": "available", "expiresAt": 1_800_000_000],
                ["title": "c", "status": "used", "expiresAt": 1_700_000_000],
            ],
        ]]
        #expect(CodexAccountUsageService.resetCredits(in: limits)
                == .available(count: 2, nextExpiry: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    @Test("Without a stated count, the available credits listed are the count")
    func counted() {
        let limits: [String: Any] = ["rateLimitResetCredits": ["credits": [["status": "available"], ["status": "used"]]]]
        #expect(CodexAccountUsageService.resetCredits(in: limits) == .available(count: 1, nextExpiry: nil))
        let none: [String: Any] = ["rateLimitResetCredits": ["credits": [[String: Any]]()]]
        #expect(CodexAccountUsageService.resetCredits(in: none) == .available(count: 0, nextExpiry: nil))
    }

    @Test("No reset-credit block is not zero: it is not reported")
    func unreported() {
        #expect(CodexAccountUsageService.resetCredits(in: [:]) == .unreported)
        #expect(CodexAccountUsageService.resetCredits(in: ["rateLimitResetCredits": [String: Any]()]) == .unreported)
        #expect(UsageDetailCard.resetCreditsText(.unreported) == String.localized("Not available"))
    }
}

/// Starting `codex app-server` from a GUI app, whose PATH has no `node`.
@Suite("Codex helper environment")
struct CodexHelperEnvironmentTests {
    @Test("The folder codex was found in leads PATH, once, and nothing else changes")
    func pathLeadsWithCodexFolder() {
        let codex = URL(fileURLWithPath: "/Users/me/.nvm/versions/node/v24/bin/codex")
        let environment = CodexAppServer.environment(
            for: codex,
            over: ["PATH": "/usr/bin:/Users/me/.nvm/versions/node/v24/bin:/bin", "HTTPS_PROXY": "http://proxy:8080"]
        )
        #expect(environment["PATH"] == "/Users/me/.nvm/versions/node/v24/bin:/usr/bin:/bin")
        #expect(environment["HTTPS_PROXY"] == "http://proxy:8080")
    }

    @Test("With no PATH at all, the system folders follow")
    func noInheritedPath() {
        let environment = CodexAppServer.environment(for: URL(fileURLWithPath: "/opt/homebrew/bin/codex"), over: [:])
        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }
}

/// Where Pulse looks for `codex`, which a GUI app has to do by hand.
@Suite("Codex locator")
struct CodexLocatorTests {
    @Test("The desktop apps' own codex is looked for, and the newest managed version before older ones")
    func candidates() {
        let listed = CodexAppServer.candidates(home: "/Users/me", path: "/usr/bin:/bin") { root in
            root.hasSuffix(".nvm/versions/node") ? ["v20.1.0", "v24.11.1"] : []
        }
        #expect(listed.first == "/usr/bin/codex")
        #expect(listed.contains("/Applications/Codex.app/Contents/Resources/codex"))
        #expect(listed.contains("/Applications/ChatGPT.app/Contents/Resources/codex"))
        #expect(listed.contains("/Users/me/Applications/ChatGPT.app/Contents/Resources/codex"))
        let nvm = listed.filter { $0.contains(".nvm") }
        #expect(nvm == ["/Users/me/.nvm/versions/node/v24.11.1/bin/codex", "/Users/me/.nvm/versions/node/v20.1.0/bin/codex"])
    }

    @Test("No codex is said apart from Codex reporting none")
    @MainActor
    func missingIsItsOwnWords() {
        #expect(UsageDetailCard.resetCreditsText(.codexMissing) != UsageDetailCard.resetCreditsText(.unreported))
    }
}

@Suite("Codex locator, app from Launch Services")
struct CodexLocatorAppTests {
    @Test("The app Launch Services names is asked before the fixed places")
    func appFirst() {
        let listed = CodexAppServer.candidates(
            home: "/Users/me", path: nil,
            app: URL(fileURLWithPath: "/Volumes/Apps/ChatGPT.app"),
            versions: { _ in [] }
        )
        #expect(Array(listed.prefix(2)) == [
            "/Volumes/Apps/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Volumes/Apps/ChatGPT.app/Contents/Resources/codex",
        ])
    }

    @Test("ChatGPT 26.924's layout is looked for before the one it replaced (issue #67)")
    func newerLayoutFirst() {
        let listed = CodexAppServer.candidates(home: "/Users/me", path: nil, versions: { _ in [] })
        let new = listed.firstIndex(of: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        let old = listed.firstIndex(of: "/Applications/ChatGPT.app/Contents/Resources/codex")
        #expect(new != nil && old != nil)
        #expect(new! < old!)
        #expect(listed.contains("/Users/me/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex"))
    }
}
