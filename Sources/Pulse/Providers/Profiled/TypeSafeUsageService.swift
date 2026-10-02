// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// TypeSafe: the credit balance on the console's billing page, read with the
/// signed-in console session.
///
/// **A pasted Cookie header, for now.** The console's session cookie has no
/// name anyone has written down — CodexBar deliberately keeps every cookie the
/// console sets rather than assume one — and "Read from browser" keeps only
/// cookies it can name. So the profile names none, the browser read finds
/// nothing, and the field takes the `Cookie` header copied from a request to
/// `console.typesafe.ai/settings/billing` instead. A "keep every cookie for
/// this host" import is the shared piece that would make Read work.
///
/// The billing figures come from a Next.js server action, not an API:
///
/// 1. The action's id is found in the billing page's own scripts — the page
///    lists its chunks, and one of them names `getBillingOverviewResult` beside
///    its id. Found once and kept for twelve hours; the page and chunks are
///    fetched again only when the id goes stale (the action answers 404).
/// 2. `POST /settings/billing` with `Next-Action: <id>` and a body of `[]` —
///    the read the page itself makes. It changes nothing.
/// 3. The reply is React's line format: `n:{json}` per line, and the line
///    with an `ok` key is the result.
///
/// The shapes are second-hand — taken from CodexBar's TypeSafe plugin and its
/// tests, not from captured replies — and the fixtures in the tests say so.
///
/// **What is left out, and why.** The cycle's spend has no limit to measure it
/// against and nowhere to go yet. Each credit grant's size and remainder are
/// reported, but a grant expires rather than resets, and the balance already
/// sums what is left of them.
extension ProviderProfile {
    static let typeSafe = ProviderProfile(
        displayName: "TypeSafe",
        billing: .api,
        iconResource: "extension",
        credential: .sessionCookie(host: "console.typesafe.ai", cookies: []),
        accessDescription: { .localized("Uses the Cookie header you paste in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("The Cookie header of a request to console.typesafe.ai/settings/billing. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "typesafe",
        fetch: { await TypeSafeUsageService.fetch($0) }
    )
}

enum TypeSafeUsageService {
    static let origin = "https://console.typesafe.ai"
    static let billingPage = URL(string: "https://console.typesafe.ai/settings/billing")!

    /// How long a found action id is trusted before the page is read again.
    static let actionLifetime: TimeInterval = 12 * 3_600
    /// At most this many of the page's scripts are opened looking for it.
    static let maximumChunks = 60

    /// The action id, kept for the launch. One console, one id.
    private actor ActionCache {
        var id: String?
        var foundAt: Date?

        func current(at now: Date) -> String? {
            guard let id, let foundAt, now.timeIntervalSince(foundAt) < TypeSafeUsageService.actionLifetime else { return nil }
            return id
        }

        func remember(_ id: String?, at now: Date) {
            self.id = id
            foundAt = id == nil ? nil : now
        }
    }

    private static let cache = ActionCache()

    static func fetch(_ context: ProfileContext, session: URLSession? = nil, now: Date = Date()) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential.map(cookieHeader), !cookie.isEmpty
        else { return context.unavailable(.sessionMissing) }

        var action: String
        var discovered = false
        if let cached = await cache.current(at: now) {
            action = cached
        } else {
            switch await discoverAction(cookie: cookie, session: session) {
            case .failure(let reason): return context.unavailable(reason)
            case .success(let found): action = found
            }
            discovered = true
            await cache.remember(action, at: now)
        }

        var reply = await post(action: action, cookie: cookie, session: session)
        // A 404 from the action is Next.js saying the id is stale: the console
        // was redeployed. Find it again, once.
        if case .success(let answer) = reply, answer.status == 404, !discovered {
            await cache.remember(nil, at: now)
            switch await discoverAction(cookie: cookie, session: session) {
            case .failure(let reason): return context.unavailable(reason)
            case .success(let found): action = found
            }
            await cache.remember(action, at: now)
            reply = await post(action: action, cookie: cookie, session: session)
        }

        switch reply {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let answer):
            switch ProfileHTTP.classify(answer, refused: .sessionExpired) {
            case .failure(let reason): return context.unavailable(reason)
            case .success(let data): return reading(from: data, context: context, now: now)
            }
        }
    }

    /// The header as pasted, with a leading `Cookie:` taken off if it came
    /// along.
    static func cookieHeader(_ pasted: String) -> String {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("cookie:") else { return trimmed }
        return String(trimmed.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespaces)
    }

    private static func post(action: String, cookie: String, session: URLSession?)
        async -> Result<ProfileHTTP.Reply, ProviderUsage.Unavailability> {
        var request = URLRequest(url: billingPage)
        request.httpMethod = "POST"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(action, forHTTPHeaderField: "Next-Action")
        request.setValue("text/x-component", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("[]".utf8)
        request.timeoutInterval = 15
        return await ProfileHTTP.reply(for: request, session: session)
    }

    // MARK: - Finding the action

    private static func discoverAction(cookie: String, session: URLSession?)
        async -> Result<String, ProviderUsage.Unavailability> {
        var request = URLRequest(url: billingPage)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let page: String
        switch await ProfileHTTP.data(for: request, refused: .sessionExpired, session: session) {
        case .failure(let reason): return .failure(reason)
        case .success(let data): page = String(decoding: data, as: UTF8.self)
        }
        // A lapsed session lands on the sign-in page, redirected or not.
        if isLoginLanding(page) { return .failure(.sessionExpired) }

        // The scripts are the site's public code: asked for without the cookie.
        for chunk in chunkURLs(inPage: page) {
            var request = URLRequest(url: chunk)
            request.timeoutInterval = 5
            switch await ProfileHTTP.reply(for: request, session: session) {
            case .failure: continue
            case .success(let reply):
                if reply.status == 429 { return .failure(.rateLimited) }
                if reply.status >= 500 { return .failure(.serverError) }
                guard (200..<300).contains(reply.status) else { continue }
                if let id = actionID(inChunk: String(decoding: reply.data, as: UTF8.self)) { return .success(id) }
            }
        }
        return .failure(.unreadableReply)
    }

    /// The console's sign-in route, as its own page names it in the React
    /// payload — escaped or not.
    static func isLoginLanding(_ body: String) -> Bool {
        body.range(of: #"\\?"\(auth\)\\?",\{\\?"children\\?":\[\\?"login\\?""#, options: .regularExpression) != nil
    }

    /// The page's own script chunks: same origin, JavaScript, in order, each
    /// once, and no more than `maximumChunks` of them.
    static func chunkURLs(inPage html: String) -> [URL] {
        let pattern = try! NSRegularExpression(
            pattern: #"<script\b[^>]*\bsrc=["']([^"']+)["'][^>]*>"#, options: [.caseInsensitive]
        )
        let text = html as NSString
        var urls: [URL] = []
        for match in pattern.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            guard urls.count < maximumChunks else { break }
            let source = text.substring(with: match.range(at: 1))
            let absolute = source.hasPrefix("/") && !source.hasPrefix("//") ? origin + source : source
            guard absolute.hasPrefix(origin + "/"),
                  absolute.range(of: #"\.js($|\?)"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let url = URL(string: absolute), !urls.contains(url)
            else { continue }
            urls.append(url)
        }
        return urls
    }

    /// The id written just before `"getBillingOverviewResult"` in a chunk.
    static func actionID(inChunk script: String) -> String? {
        let pattern = try! NSRegularExpression(
            pattern: #""([0-9a-f]{40,})"[^)]{0,150}"getBillingOverviewResult""#, options: [.caseInsensitive]
        )
        let text = script as NSString
        guard let match = pattern.firstMatch(in: script, range: NSRange(location: 0, length: text.length))
        else { return nil }
        return text.substring(with: match.range(at: 1))
    }

    // MARK: - Reading the reply

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        let body = String(decoding: data, as: UTF8.self)
        if isLoginLanding(body) { return context.unavailable(.sessionExpired) }

        // Each line is `id:payload`; the result is the object with `ok`.
        let result = body.split(whereSeparator: \.isNewline).lazy.compactMap { line -> [String: Any]? in
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                  let object = try? JSONSerialization.jsonObject(with: Data(line[line.index(after: colon)...].utf8))
                    as? [String: Any],
                  object["ok"] != nil
            else { return nil }
            return object
        }.first
        guard let result else { return context.unavailable(.unreadableReply) }
        guard result["ok"] as? Bool == true else { return context.unavailable(.serverError) }

        guard let billing = (result["data"] as? [String: Any])?["billing"] as? [String: Any],
              let figure = billing["balance"] as? NSNumber, CFGetTypeID(figure) != CFBooleanGetTypeID(),
              figure.doubleValue.isFinite
        else { return context.unavailable(.unreadableReply) }
        let balance = figure.doubleValue

        return context.reading(
            [],
            plan: (billing["plan"] as? String).flatMap(planName),
            creditBalance: money(balance),
            creditRemaining: ProviderUsage.CreditAmount(amount: balance, currency: "USD"),
            at: now
        )
    }

    /// `free_plan` → "Free"; `pro-monthly` → "Pro Monthly".
    static func planName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed == "free_plan" { return "Free" }
        let words = trimmed.split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// The console prices and shows credit in dollars; the reply carries the
    /// figure only.
    static func money(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }
}
