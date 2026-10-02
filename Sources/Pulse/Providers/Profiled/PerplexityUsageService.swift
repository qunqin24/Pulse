// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Perplexity: the API credit on the account, and the monthly credit that
/// comes with a subscription when it is the only credit there is.
///
/// Read with the browser session the user imports, from the route the
/// account's usage page calls:
/// `GET https://www.perplexity.ai/rest/billing/credits?version=2.18&source=default`.
/// The shape is second-hand — taken from CodexBar's Perplexity plugin and its
/// tests, not from a captured reply — and the fixture in the tests says so.
///
/// **Money, in cents.** Every figure is a count of US cents: the balance, each
/// grant, the total used. The balance is shown as a balance.
///
/// **A ring only where the split is stated.** Perplexity reports how much each
/// grant was and how much was used in total — not which grant it was taken
/// from. CodexBar spends the total down the subscription's grant first, then
/// purchased, then bonus, and draws a ring for each; that order is its guess.
/// Pulse draws the subscription's ring only when that grant is the only one
/// on the account, where the total can have come from nowhere else, and draws
/// none at all when there is no such grant — never a full ring standing in
/// for one that is missing.
///
/// **Redirects are not followed**, so the session is never carried to
/// another host; a redirect is an expired session.
extension ProviderProfile {
    static let perplexity = ProviderProfile(
        displayName: "Perplexity",
        billing: .api,
        iconResource: "perplexity",
        credential: .sessionCookie(host: PerplexityUsageService.host, cookies: PerplexityUsageService.cookies),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        brandColor: 0x20808D,
        setupSlug: "perplexity",
        fetch: { await PerplexityUsageService.fetch($0) }
    )
}

enum PerplexityUsageService {
    static let host = "www.perplexity.ai"
    static let cookies = ["__Secure-next-auth.session-token"]
    static let endpoint = URL(string: "https://www.perplexity.ai/rest/billing/credits?version=2.18&source=default")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let header = context.trimmedCredential,
              let cookie = ProviderProfile.keep(header, cookies: cookies)
        else { return context.unavailable(.sessionMissing) }

        let owned = session == nil ? guardedSession() : nil
        defer { owned?.finishTasksAndInvalidate() }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // What the usage page's own request carries; the site sits behind a
        // bot screen that turns away a request that looks like no browser.
        request.setValue("https://www.perplexity.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://www.perplexity.ai/account/usage", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        switch await ProfileHTTP.reply(for: request, session: session ?? owned) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let reply):
            if (300..<400).contains(reply.status) { return context.unavailable(.sessionExpired) }
            switch ProfileHTTP.classify(reply, refused: .sessionExpired) {
            case .failure(let reason): return context.unavailable(reason)
            case .success(let data): return reading(from: data, context: context)
            }
        }
    }

    private static func guardedSession() -> URLSession {
        let configuration = NetworkSession.configured(.ephemeral)
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    // MARK: - Reading the reply

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let grants = field(object, "credit_grants", "creditGrants") as? [[String: Any]]
        else { return context.unavailable(.unreadableReply) }

        func number(_ from: [String: Any], _ snake: String, _ camel: String) -> Double? {
            (field(from, snake, camel) as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil }
        }

        // A grant that has lapsed is no longer part of anything.
        let live = grants.filter { grant in
            guard let expiry = number(grant, "expires_at_ts", "expiresAtTs") else { return true }
            return Date(timeIntervalSince1970: expiry) > now
        }
        func total(_ type: String) -> Double {
            live.filter { $0["type"] as? String == type }
                .compactMap { number($0, "amount_cents", "amountCents") }
                .reduce(0, +)
        }
        let recurring = total("recurring")
        let others = live.filter { $0["type"] as? String != "recurring" }
            .compactMap { number($0, "amount_cents", "amountCents") }
            .reduce(0, +)
        let purchased = number(object, "current_period_purchased_cents", "currentPeriodPurchasedCents") ?? 0
        let used = number(object, "total_usage_cents", "totalUsageCents")

        var windows: [UsageWindow] = []
        if recurring > 0, others <= 0, purchased <= 0, let used, used >= 0 {
            let renewal = number(object, "renewal_date_ts", "renewalDateTs").flatMap {
                $0 > 0 ? Date(timeIntervalSince1970: $0) : nil
            }
            windows.append(UsageWindow(
                id: "perplexity.recurring",
                kind: .credits,
                scope: nil,
                usedFraction: used / recurring,
                // A sort key: the renewal is stated, the period's length is not.
                windowSeconds: 30 * 86_400,
                resetsAt: renewal,
                reportsLength: false,
                isExhausted: used >= recurring
            ))
        }

        let balance = number(object, "balance_cents", "balanceCents").flatMap { $0 >= 0 ? $0 / 100 : nil }
        guard !windows.isEmpty || balance != nil else { return context.unavailable(.noLimitsReported) }
        return context.reading(
            windows,
            creditBalance: balance.map(money),
            creditRemaining: balance.map { .init(amount: $0, currency: "USD") },
            at: now
        )
    }

    /// Perplexity has answered with both spellings.
    private static func field(_ object: [String: Any], _ snake: String, _ camel: String) -> Any? {
        object[snake] ?? object[camel]
    }

    static func money(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }
}
