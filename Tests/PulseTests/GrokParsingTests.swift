import Foundation
import Testing
@testable import Pulse

/// Grok's billing reply is not published API, and nobody here holds a real
/// SuperGrok account to capture one from. Every fixture below is built by
/// hand from the field names and behaviour `GrokUsageService` decodes and
/// from `Docs/providers/grok.md` — not captured from a live account.
@Suite("Grok parsing")
struct GrokParsingTests {
    private static func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
    }

    private static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: try fixtureURL(name))
    }

    private static func config(_ name: String) throws -> GrokUsageService.Billing.Config {
        let billing = try JSONDecoder().decode(GrokUsageService.Billing.self, from: try fixture(name))
        return try #require(billing.config)
    }

    // MARK: - The stored login

    /// No file at all is "never signed in" — the CLI has never run `grok
    /// login` here — and that is a different instruction from a login that
    /// went stale.
    @Test("No auth file at all is never signed in")
    func noAuthFileIsNeverSignedIn() async {
        let missing = URL(fileURLWithPath: "/tmp/pulse-grok-test-\(UUID().uuidString)/auth.json")
        let service = GrokUsageService(authFile: missing)
        let usage = await service.fetch()
        #expect(usage.state == .unavailable(.grokSignInRequired))
    }

    /// Every stored entry aged out. That is "signed in, and the login has
    /// gone stale" rather than "never signed in", and the two carry different
    /// remedies (`.grokLoginExpired` vs `.grokSignInRequired`).
    @Test("An auth file with only expired entries reads as expired, not absent")
    func allExpiredEntriesReadAsExpired() async throws {
        let service = GrokUsageService(authFile: try Self.fixtureURL("grok-auth-expired"))
        let usage = await service.fetch()
        #expect(usage.state == .unavailable(.grokLoginExpired))
    }

    /// The freshest unexpired entry wins over one that has aged out, even
    /// though the expired one used to be usable.
    @Test("The freshest unexpired entry is the one used, not an expired one beside it")
    func freshestUnexpiredEntryWins() throws {
        let service = GrokUsageService(authFile: try Self.fixtureURL("grok-auth-multiple"))
        guard case .usable(let token) = service.storedLogin() else {
            Issue.record("expected a usable login")
            return
        }
        #expect(token == "fresh-token")
    }

    /// An undated entry is a last resort, not a winner: parked at
    /// `.distantFuture` it would beat every dated entry; parked at
    /// `.distantPast` it loses to one, which is what a fallback should do.
    /// With nothing else in the file, it is still usable.
    @Test("An undated entry is usable when it is all there is")
    func undatedEntryIsUsableAlone() throws {
        let service = GrokUsageService(authFile: try Self.fixtureURL("grok-auth-undated-only"))
        guard case .usable(let token) = service.storedLogin() else {
            Issue.record("expected a usable login")
            return
        }
        #expect(token == "undated-token")
    }

    /// An entry with no `key` at all does not count as ever having signed
    /// in — it is skipped before `sawEntry` is set, so a file holding only
    /// broken entries reads the same as no file.
    @Test("An entry without a key does not count as a sign-in")
    func entryWithoutAKeyIsNotASignIn() throws {
        let service = GrokUsageService(authFile: try Self.fixtureURL("grok-auth-no-key"))
        guard case .none = service.storedLogin() else {
            Issue.record("expected no login at all")
            return
        }
    }

    // MARK: - The billing reply → one window

    @Test("A normal reply becomes one weekly window with the stated fraction")
    func normalReplyBecomesOneWeeklyWindow() throws {
        let window = try #require(GrokUsageService.window(from: try Self.config("grok-billing-weekly")))

        #expect(window.id == "grok-pool")
        #expect(window.kind == .weekly)
        #expect(window.scope == nil)
        #expect(abs(window.usedFraction - 0.425) < 0.000_001)
        #expect(window.windowSeconds == 7 * 86_400)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_767_830_400)) // 2026-01-08T00:00:00Z
        #expect(window.reportsLength)
        // Grok's reply carries no flag equivalent to DeepSeek's `is_available`,
        // so nothing here may call the account spent.
        #expect(!window.isExhausted)
    }

    @Test("A period around thirty days is named monthly")
    func aroundThirtyDaysIsMonthly() throws {
        let window = try #require(GrokUsageService.window(from: try Self.config("grok-billing-monthly")))
        #expect(window.kind == .monthly)
    }

    @Test("A period that is neither familiar length is shown under its own duration")
    func unfamiliarLengthIsOther() throws {
        let window = try #require(GrokUsageService.window(from: try Self.config("grok-billing-other-length")))
        #expect(window.kind == .other(seconds: 2 * 86_400))
    }

    /// The payload is proto3 with implicit presence, so a true zero is simply
    /// absent from the wire — but only inside a period that is actually
    /// running. Wide-open bounds around "now" stand in for a period that has
    /// not ended, since the production code checks against the real clock.
    @Test("An absent percentage inside a running period reads as zero")
    func absentPercentageInsideARunningPeriodIsZero() throws {
        let window = try #require(GrokUsageService.window(from: try Self.config("grok-billing-percent-absent-active")))
        #expect(window.usedFraction == 0)
    }

    /// A reply describing a period that has already ended says nothing about
    /// the one that followed it. Reading that as 0% would report an empty
    /// pool as a full one.
    @Test("An absent percentage in an ended period produces no window")
    func absentPercentageInAnEndedPeriodProducesNoWindow() throws {
        #expect(GrokUsageService.window(from: try Self.config("grok-billing-percent-absent-ended")) == nil)
    }

    /// Neither `currentPeriod` nor the flat `billingPeriod*` pair is present,
    /// so there is nothing to measure a length from at all.
    @Test("No timestamps at all produces no window")
    func noTimestampsProducesNoWindow() throws {
        #expect(GrokUsageService.window(from: try Self.config("grok-billing-no-timestamps")) == nil)
    }

    /// Current behaviour; possibly wrong: a percentage past 100 clamps the
    /// drawn fraction to a full ring, but `window(from:)` never sets
    /// `isExhausted` — there is no field in this reply that plays the role
    /// DeepSeek's `is_available` or Grok Bot's `usagePercent >= 100` do, so
    /// nothing marks it. `GrokBotUsageService.window(from:)` sets
    /// `isExhausted: percent >= 100` from the same kind of figure, so the two
    /// Grok-branded rings disagree on whether reaching 100% is "spent".
    @Test("A percentage over 100 clamps the fraction but does not mark exhausted")
    func percentageOver100ClampsWithoutMarkingExhausted() throws {
        let window = try #require(GrokUsageService.window(from: try Self.config("grok-billing-exhausted")))
        #expect(window.usedFraction == 1)
        #expect(!window.isExhausted)
    }

    // MARK: - The plan's name

    @Test("The plan name is read and trimmed")
    func planNameIsReadAndTrimmed() throws {
        let settings = try JSONDecoder().decode(GrokUsageService.Settings.self, from: try Self.fixture("grok-settings"))
        #expect(GrokUsageService.planName(from: settings) == "SuperGrok")
    }

    /// Whitespace-only is not a name — the same "absent has said nothing"
    /// rule the rest of the parsers follow.
    @Test("A blank plan name is nil, not an empty string")
    func blankPlanNameIsNil() throws {
        let settings = try JSONDecoder().decode(GrokUsageService.Settings.self, from: try Self.fixture("grok-settings-blank"))
        #expect(GrokUsageService.planName(from: settings) == nil)
    }

    @Test("A missing plan field is nil")
    func missingPlanFieldIsNil() throws {
        let settings = try JSONDecoder().decode(GrokUsageService.Settings.self, from: Data("{}".utf8))
        #expect(GrokUsageService.planName(from: settings) == nil)
    }

    // MARK: - Unreadable replies

    @Test("A reply with no config object at all decodes but reports nothing")
    func replyWithNoConfigDecodesButReportsNothing() throws {
        let billing = try JSONDecoder().decode(GrokUsageService.Billing.self, from: Data("{}".utf8))
        #expect(billing.config == nil)
    }
}
