// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Sakana AI's subscription: a five-hour and a weekly limit, each stated as a
/// percentage on the console's billing page, and the pay-as-you-go credit
/// balance on the same page's other tab.
///
/// **A page, not an API.** Sakana publishes no usage route; the console
/// renders the figures on the server, so the page is read as HTML with the
/// browser session the user imports:
/// `GET https://console.sakana.ai/billing`, and `?tab=payAsYouGo` for the
/// balance, which that tab alone renders. The markup is second-hand — taken
/// from CodexBar's Sakana provider and its tests, not from a captured page —
/// and the fixtures in the tests say so. The session cookie's name is not
/// from CodexBar, which takes a whole pasted header: the console signs in
/// with Auth.js, whose cookies its sign-in page sets under the `authjs`
/// prefix. Unverified against a signed-in browser.
///
/// **Redirects are not followed.** A signed-out console redirects to its
/// sign-in page; following it would carry the session there and read the
/// sign-in page as a billing page. A redirect is an expired session.
///
/// The balance is best effort: a tab that fails, or does not state its figure
/// in dollars, leaves the balance off and the limits standing.
extension ProviderProfile {
    static let sakana = ProviderProfile(
        displayName: "Sakana AI",
        iconResource: "sakana",
        credential: .sessionCookie(host: SakanaUsageService.host, cookies: SakanaUsageService.cookies),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "sakana",
        fetch: { await SakanaUsageService.fetch($0) }
    )
}

enum SakanaUsageService {
    static let host = "console.sakana.ai"
    static let cookies = ["__Secure-authjs.session-token"]
    static let billing = URL(string: "https://console.sakana.ai/billing")!
    static let payAsYouGo = URL(string: "https://console.sakana.ai/billing?tab=payAsYouGo")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let header = context.trimmedCredential,
              let cookie = ProviderProfile.keep(header, cookies: cookies)
        else { return context.unavailable(.sessionMissing) }

        let owned = session == nil ? guardedSession() : nil
        defer { owned?.finishTasksAndInvalidate() }
        let session = session ?? owned

        async let page = ProfileHTTP.reply(for: request(billing, cookie: cookie), session: session)
        async let tab = ProfileHTTP.reply(for: request(payAsYouGo, cookie: cookie), session: session)

        switch await page {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let reply):
            if (300..<400).contains(reply.status) { return context.unavailable(.sessionExpired) }
            switch ProfileHTTP.classify(reply, refused: .sessionExpired) {
            case .failure(let reason):
                return context.unavailable(reason)
            case .success(let data):
                var balance: Data?
                if case .success(let other) = await tab, (200..<300).contains(other.status) { balance = other.data }
                return reading(from: data, payAsYouGo: balance, context: context)
            }
        }
    }

    /// Cookies only from the header Pulse holds, nothing kept between calls,
    /// and no redirect followed — see the note above.
    private static func guardedSession() -> URLSession {
        let configuration = NetworkSession.configured(.ephemeral)
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    private static func request(_ url: URL, cookie: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        // The labels read below are the English ones.
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    // MARK: - Reading the page

    /// The two limits the page names, with the length each one is.
    private static let known: [(label: String, id: String, kind: UsageWindow.Kind, seconds: Int)] = [
        ("5-hour", "sakana.five_hour", .fiveHour, 5 * 3_600),
        ("Weekly", "sakana.weekly", .weekly, 7 * 86_400),
    ]

    static func reading(
        from page: Data,
        payAsYouGo: Data? = nil,
        context: ProfileContext,
        now: Date = Date()
    ) -> ProviderUsage {
        guard let html = String(data: page, encoding: .utf8), !html.isEmpty else {
            return context.unavailable(.unreadableReply)
        }
        let windows = known.compactMap { limit -> UsageWindow? in
            guard let body = section(after: limit.label, in: html),
                  let text = capture(#"<p[^>]*>\s*([0-9]+(?:\.[0-9]+)?)% used\s*</p>"#, in: body),
                  let percent = Double(text), percent.isFinite, percent >= 0
            else { return nil }
            return UsageWindow(
                id: limit.id,
                kind: limit.kind,
                scope: nil,
                usedFraction: percent / 100,
                windowSeconds: limit.seconds,
                resetsAt: capture(#"<p[^>]*>\s*Resets on ([^<]+?)\s*</p>"#, in: body).flatMap(resetDate),
                isExhausted: percent >= 100
            )
        }
        let balance = payAsYouGo.flatMap { String(data: $0, encoding: .utf8) }.flatMap(creditBalance)

        guard !windows.isEmpty || balance != nil else { return context.unavailable(.unreadableReply) }
        return context.reading(
            windows,
            plan: capture(#"<div[^>]*data-slot="card-title"[^>]*>\s*<span>\s*([^<]+?)\s*</span>"#, in: html),
            creditBalance: balance.map(money),
            creditRemaining: balance.map { .init(amount: $0, currency: "USD") },
            at: now
        )
    }

    /// The card's "Credit balance", when it is stated in dollars. A figure
    /// without its `$` is left off rather than given a currency.
    static func creditBalance(in html: String) -> Double? {
        let pattern = #"<h2[^>]*>\s*Credit balance\s*</h2>[\s\S]{0,900}?<p[^>]*tabular-nums[^"]*"[^>]*>"#
            + #"\s*\$([0-9][0-9,]*(?:\.[0-9]+)?)\s*</p>"#
        guard let text = capture(pattern, in: html),
              let amount = Double(text.replacingOccurrences(of: ",", with: "")),
              amount.isFinite, amount >= 0
        else { return nil }
        return amount
    }

    /// What follows a limit's label, up to the next limit or the next card.
    private static func section(after label: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        guard let start = html.range(of: #"<p[^>]*>\s*\#(escaped)\s*</p>"#, options: .regularExpression) else {
            return nil
        }
        let rest = html[start.upperBound...]
        let boundary = #"<p[^>]*>\s*(?:5-hour|Weekly)\s*</p>|<div[^>]*data-slot=["']card(?:-title)?["'][^>]*>"#
        let end = rest.range(of: boundary, options: [.regularExpression, .caseInsensitive])?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    /// The page renders "Resets on June 23, 2026 at 2:53 PM" on the server, in
    /// UTC; only the browser's script moves it to local time afterwards.
    static func resetDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"
        return formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func money(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }
}
