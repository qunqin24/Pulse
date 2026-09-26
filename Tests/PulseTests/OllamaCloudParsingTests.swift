import Foundation
import Testing
@testable import Pulse

/// Ollama publishes no quota API; the only place these two figures exist is
/// the signed-in settings page. Every HTML fixture below is built by hand to
/// match the shape `OllamaCloudPage.parse` looks for — two "usage" sections,
/// each with an explicit "N% used" total and an optional `data-time` reset —
/// as described in `Docs/ollama-cloud.md`. None of it is a captured page.
@Suite("Ollama Cloud parsing")
struct OllamaCloudParsingTests {
    private static func page(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "html", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    // MARK: - A normal page

    @Test("A normal page gives both windows, with their own resets")
    func normalPageGivesBothWindows() throws {
        let snapshot = try OllamaCloudPage.parse(try Self.page("ollama-page-normal"))

        #expect(abs(snapshot.session.usedFraction - 0.12) < 0.000_001)
        #expect(snapshot.session.resetsAt == Date(timeIntervalSince1970: 1_767_830_400)) // 2026-01-08
        #expect(abs(snapshot.weekly.usedFraction - 0.345) < 0.000_001)
        #expect(snapshot.weekly.resetsAt == Date(timeIntervalSince1970: 1_768_435_200)) // 2026-01-15

        let windows = OllamaCloudUsageService.windows(from: snapshot)
        #expect(windows.map(\.id) == ["ollama.session", "ollama.weekly"])
        #expect(windows[0].kind == .fiveHour)
        #expect(windows[0].windowSeconds == 5 * 3_600)
        #expect(windows[1].kind == .weekly)
        #expect(windows[1].windowSeconds == 7 * 86_400)
        #expect(windows.allSatisfy { !$0.isExhausted })
    }

    /// A window with no `data-time` element stays unknown rather than being
    /// guessed at — the row simply has no reset line.
    @Test("A window with no data-time element has no reset, not a guessed one")
    func windowWithNoDataTimeHasNoReset() throws {
        let snapshot = try OllamaCloudPage.parse(try Self.page("ollama-page-no-reset"))
        #expect(snapshot.session.resetsAt == nil)
        #expect(snapshot.weekly.resetsAt != nil)
    }

    @Test("100% used marks the window exhausted")
    func fullyUsedMarksExhausted() {
        let snapshot = OllamaCloudSnapshot(
            session: .init(usedFraction: 1, resetsAt: nil),
            weekly: .init(usedFraction: 0.5, resetsAt: nil)
        )
        let windows = OllamaCloudUsageService.windows(from: snapshot)
        #expect(windows[0].isExhausted)
        #expect(!windows[1].isExhausted)
    }

    // MARK: - Both windows are required

    /// A changed or partially rendered page must never turn the missing
    /// window into zero usage, and never silently omit a higher limit.
    @Test("A page missing one of the two windows is unreadable, not half-empty")
    func pageMissingOneWindowIsUnreadable() throws {
        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-only-session"))
        }
    }

    @Test("A page with neither label at all is unreadable")
    func pageWithNeitherLabelIsUnreadable() throws {
        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-changed"))
        }
    }

    // MARK: - The page has changed shape

    @Test("A duplicated label is ambiguous and refused")
    func duplicatedLabelIsRefused() throws {
        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-duplicate-label"))
        }
    }

    /// Reading the first model segment's width as the total would report a
    /// wrong figure with total confidence; refusing outright is the safer
    /// failure.
    @Test("Two candidate percentages in one section are ambiguous and refused")
    func twoPercentagesInOneSectionAreRefused() throws {
        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-ambiguous-percent"))
        }
    }

    @Test("A percentage outside 0 to 100 is refused rather than clamped")
    func outOfRangePercentageIsRefused() throws {
        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-percent-out-of-range"))
        }
    }

    @Test("More than one data-time candidate is ambiguous and refused")
    func multipleDataTimeCandidatesAreRefused() throws {
        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-multiple-times"))
        }
    }

    @Test("A data-time that is not a real date is refused")
    func malformedTimestampIsRefused() throws {
        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-malformed-time"))
        }
    }

    @Test("A section with the label but no percentage text is refused")
    func labelWithoutAPercentageIsRefused() throws {
        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-no-percent"))
        }
    }

    /// A signed-out session shows a login form where the usage page would be
    /// — a different instruction from "the page changed shape".
    @Test("A sign-in form on the page means signed out, not an unreadable page")
    func signInFormMeansSignedOut() throws {
        #expect(throws: OllamaCloudError.signedOut) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-signed-out"))
        }
    }

    @Test("An embedded entity declaration is refused before anything else is parsed")
    func entityDeclarationIsRefused() throws {
        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudPage.parse(try Self.page("ollama-page-entity-injection"))
        }
    }

    @Test("A page over the byte cap is refused without being read")
    func oversizedPageIsRefused() {
        let oversized = Data(repeating: 0x41, count: OllamaCloudPage.maximumBytes + 1)
        #expect(throws: OllamaCloudError.invalidPage) { try OllamaCloudPage.parse(oversized) }
    }

    // MARK: - HTTP and auth failure mapping

    private static func response(_ url: URL, status: Int, mimeType: String? = "text/html") -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: mimeType.map { ["Content-Type": $0] })!
    }

    @Test("A 200 on the settings page's own URL validates")
    func okOnTheRightURLValidates() throws {
        try OllamaCloudClient.validate(Self.response(OllamaCloudClient.settingsURL, status: 200))
    }

    /// A 200 from anywhere else — a redirect target, a different path, a
    /// non-HTML body — is not the settings page, whatever its status code.
    @Test("A 200 from the wrong place is unreadable, not a success")
    func okFromTheWrongPlaceIsUnreadable() {
        let wrongHost = URL(string: "https://evil.example/settings")!
        #expect(throws: OllamaCloudError.invalidPage) { try OllamaCloudClient.validate(Self.response(wrongHost, status: 200)) }

        let wrongPath = URL(string: "https://ollama.com/login")!
        #expect(throws: OllamaCloudError.invalidPage) { try OllamaCloudClient.validate(Self.response(wrongPath, status: 200)) }

        #expect(throws: OllamaCloudError.invalidPage) {
            try OllamaCloudClient.validate(Self.response(OllamaCloudClient.settingsURL, status: 200, mimeType: "application/json"))
        }
    }

    @Test("A redirect or 401/403 means signed out")
    func redirectOr401Or403MeansSignedOut() {
        for status in [300, 302, 401, 403] {
            #expect(throws: OllamaCloudError.signedOut) {
                try OllamaCloudClient.validate(Self.response(OllamaCloudClient.settingsURL, status: status))
            }
        }
    }

    @Test("429 is rate limited; other statuses are a server problem")
    func statusMapping() {
        #expect(throws: OllamaCloudError.rateLimited) {
            try OllamaCloudClient.validate(Self.response(OllamaCloudClient.settingsURL, status: 429))
        }
        #expect(throws: OllamaCloudError.serverError) {
            try OllamaCloudClient.validate(Self.response(OllamaCloudClient.settingsURL, status: 500))
        }
    }

    @Test("Every OllamaCloudError maps to its own unavailability reason")
    func everyErrorMapsToItsOwnReason() {
        #expect(OllamaCloudUsageService.reason(for: .missingCookie) == .ollamaSessionMissing)
        #expect(OllamaCloudUsageService.reason(for: .invalidCookie) == .ollamaSessionMissing)
        #expect(OllamaCloudUsageService.reason(for: .signedOut) == .ollamaSessionExpired)
        #expect(OllamaCloudUsageService.reason(for: .rateLimited) == .rateLimited)
        #expect(OllamaCloudUsageService.reason(for: .serverError) == .serverError)
        #expect(OllamaCloudUsageService.reason(for: .invalidPage) == .ollamaPageChanged)
    }

    @Test("A missing or empty cookie is reported without a network call")
    func missingOrEmptyCookieIsReportedWithoutFetching() async {
        let missing = await OllamaCloudUsageService(cookie: nil).fetch()
        #expect(missing.state == .unavailable(.ollamaSessionMissing))

        let empty = await OllamaCloudUsageService(cookie: "").fetch()
        #expect(empty.state == .unavailable(.ollamaSessionMissing))
    }

    // MARK: - The session cookie filter

    @Test("Analytics cookies are dropped, the recognized session names are kept")
    func normalizeDropsAnalytics() throws {
        let kept = try OllamaSessionCookie.normalize("_ga=GA1.1.1; wos-session=abc; _gid=x")
        #expect(kept == "wos-session=abc")
    }

    @Test("A NextAuth numbered chunk is recognized")
    func numberedChunkIsRecognized() throws {
        let kept = try OllamaSessionCookie.normalize("next-auth.session-token.0=part1; next-auth.session-token.1=part2")
        #expect(kept == "next-auth.session-token.0=part1; next-auth.session-token.1=part2")
    }

    @Test("A pasted Cookie header is accepted")
    func pastedHeaderIsAccepted() throws {
        #expect(try OllamaSessionCookie.normalize("Cookie: wos-session=abc") == "wos-session=abc")
    }

    @Test("A control character is refused, not forwarded")
    func controlCharacterIsRefused() {
        #expect(throws: OllamaCloudError.invalidCookie) {
            try OllamaSessionCookie.normalize("wos-session=abc\r\nX-Injected: 1")
        }
    }

    @Test("Nothing recognized in the header is an invalid cookie")
    func nothingRecognizedIsInvalid() {
        #expect(throws: OllamaCloudError.invalidCookie) { try OllamaSessionCookie.normalize("_ga=1; _gid=2") }
    }

    @Test("An empty header is a missing cookie, not an invalid one")
    func emptyHeaderIsMissing() {
        #expect(throws: OllamaCloudError.missingCookie) { try OllamaSessionCookie.normalize("Cookie: ") }
    }

    /// A host-only and a domain row for the same session name are both
    /// returned by the cookie store on purpose; the first wins rather than
    /// the whole browser being discarded.
    @Test("A repeated session name keeps the first")
    func repeatedNameKeepsFirst() throws {
        #expect(try OllamaSessionCookie.normalize("wos-session=first; wos-session=second") == "wos-session=first")
    }

    @Test("A value carrying a quote or a space is refused")
    func valueWithQuoteOrSpaceIsRefused() {
        #expect(throws: OllamaCloudError.invalidCookie) { try OllamaSessionCookie.normalize(#"wos-session="abc""#) }
        #expect(throws: OllamaCloudError.invalidCookie) { try OllamaSessionCookie.normalize("wos-session=a b") }
    }
}
