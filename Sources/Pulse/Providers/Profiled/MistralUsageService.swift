// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Mistral: the subscription's included allowances — API and Vibe — each as
/// the percentage Mistral reports, and the account's available credit.
///
/// Read with the Mistral Admin browser session, from what Mistral's own admin
/// pages load: `GET https://admin.mistral.ai/api/billing/credits`, the
/// `https://admin.mistral.ai/subscription` page (whose server-rendered data
/// carries the allowances), and — only when that page has no Vibe allowance —
/// `console.mistral.ai`'s `billing.vibeUsage`. The shapes are second-hand —
/// taken from CodexBar's Mistral provider and its tests, not from captured
/// replies — and the fixtures in the tests say so.
///
/// **What is not read.** CodexBar's headline figure is the month's spend,
/// which it works out from token counts and a price table of its own. That is
/// an estimate, and Pulse shows only what Mistral itself reports.
///
/// **The session cookie's name is not fixed.** Mistral signs in with Ory,
/// whose session cookie is `ory_session_` followed by the deployment's own
/// suffix, so the name below is a prefix (`ProviderProfile.keep`). Read from
/// the browser or pasted, only the `ory_session_…` and `csrftoken` cookies are
/// ever sent.
extension ProviderProfile {
    static let mistral = ProviderProfile(
        displayName: "Mistral",
        iconResource: "mistral",
        credential: .sessionCookie(host: "mistral.ai", cookies: ["ory_session_*", "csrftoken"]),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "mistral",
        discoveryPaths: [".vibe"],
        fetch: { await MistralUsageService.fetch($0) }
    )
}

enum MistralUsageService {
    static let creditsEndpoint = URL(string: "https://admin.mistral.ai/api/billing/credits")!
    static let subscriptionPage = URL(string: "https://admin.mistral.ai/subscription")!
    static let vibeEndpoint: URL = {
        var components = URLComponents(string: "https://console.mistral.ai/api-ui/trpc/billing.vibeUsage")!
        components.queryItems = [
            URLQueryItem(name: "batch", value: "1"),
            URLQueryItem(name: "input", value: #"{"0":{"json":null,"meta":{"values":["undefined"],"v":1}}}"#),
        ]
        return components.url!
    }()

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let pasted = context.trimmedCredential else { return context.unavailable(.sessionMissing) }
        guard let cookies = sessionCookies(from: pasted) else { return context.unavailable(.sessionMissing) }

        // Credit first: it is the one JSON route, so it is where a session
        // that no longer works is found out.
        let credit: ProviderUsage.CreditAmount?
        switch await data(for: request(creditsEndpoint, cookies: cookies, accept: "application/json"), session: session) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let body): credit = Self.credit(from: body)
        }

        // The allowances are best-effort, as they are in Mistral's own pages:
        // an account without a subscription has none.
        var allowances = Allowances()
        if case .success(let page) = await data(
            for: request(subscriptionPage, cookies: cookies, accept: "text/html"), session: session
        ) {
            allowances = Self.allowances(fromPage: String(decoding: page, as: UTF8.self))
        }
        if allowances.vibe == nil, cookies.csrf != nil,
           case .success(let body) = await data(for: vibeRequest(cookies: cookies), session: session) {
            allowances.vibe = vibe(from: body)
        }

        return reading(allowances, credit: credit, context: context)
    }

    // MARK: - The session

    struct Cookies: Equatable {
        /// `ory_session_…=…`, however many there are.
        let session: [String]
        let csrf: String?

        var header: String { (session + (csrf.map { ["csrftoken=\($0)"] } ?? [])).joined(separator: "; ") }
    }

    /// Only the Ory session and the CSRF token out of a pasted `Cookie:`
    /// header (with or without the `Cookie:` in front). Nothing else leaves.
    static func sessionCookies(from header: String) -> Cookies? {
        var text = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("cookie:") { text = String(text.dropFirst("cookie:".count)) }

        var session: [String] = []
        var csrf: String?
        for part in text.split(separator: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces)
            guard let equals = pair.firstIndex(of: "=") else { continue }
            let name = String(pair[..<equals])
            let value = String(pair[pair.index(after: equals)...])
            guard !value.isEmpty, value.rangeOfCharacter(from: CharacterSet(charactersIn: ",\r\n")) == nil
            else { continue }
            if name.hasPrefix("ory_session_"), name.count > "ory_session_".count {
                session.append("\(name)=\(value)")
            } else if name == "csrftoken", csrf == nil {
                csrf = value
            }
        }
        return session.isEmpty ? nil : Cookies(session: session, csrf: csrf)
    }

    // MARK: - Reading the replies

    private struct CreditReply: Decodable {
        let walletAmount: Double?
        let creditNotesAmount: Double?
        let ongoingUsageBalance: Double?
        let currency: String?

        enum CodingKeys: String, CodingKey {
            case walletAmount = "wallet_amount"
            case creditNotesAmount = "credit_notes_amount"
            case ongoingUsageBalance = "ongoing_usage_balance"
            case currency
        }
    }

    /// What is available to spend: the wallet and any credit notes, less the
    /// usage already run up against them and not yet settled — all three as
    /// Mistral reports them. Left off if the wallet or the currency is
    /// missing, or if the result is below zero, which is a debt and not a
    /// balance.
    static func credit(from data: Data) -> ProviderUsage.CreditAmount? {
        guard let reply = try? JSONDecoder().decode(CreditReply.self, from: data),
              let wallet = reply.walletAmount,
              let currency = reply.currency?.trimmingCharacters(in: .whitespaces).uppercased(),
              currency.count == 3
        else { return nil }
        let available = wallet + (reply.creditNotesAmount ?? 0) - (reply.ongoingUsageBalance ?? 0)
        guard available.isFinite, available >= 0 else { return nil }
        return .init(amount: available, currency: currency)
    }

    struct Allowance: Equatable {
        let percentUsed: Double
        let resetsAt: Date?
    }

    struct Allowances: Equatable {
        var api: Allowance?
        var vibe: Allowance?
    }

    /// The subscription page is a Next.js page: its data arrives as strings
    /// pushed onto `self.__next_f`, which together make one stream. The
    /// allowances are `api_budget` and `vibe_budget` objects inside it. Where
    /// the stream carries two different values under one name, neither is
    /// taken — there is no telling which is this account's.
    static func allowances(fromPage html: String) -> Allowances {
        let stream = flightStream(in: html)
        return Allowances(api: budget(named: "api_budget", in: stream), vibe: budget(named: "vibe_budget", in: stream))
    }

    private static func flightStream(in html: String) -> String {
        let marker = "self.__next_f.push("
        var chunks: [String] = []
        var cursor = html.startIndex
        while let found = html.range(of: marker, range: cursor..<html.endIndex) {
            cursor = found.upperBound
            guard let start = html[cursor...].firstIndex(where: { !$0.isWhitespace }), html[start] == "[",
                  let end = containerEnd(in: html, from: start)
            else { continue }
            if let array = try? JSONSerialization.jsonObject(with: Data(html[start..<end].utf8)) as? [Any],
               array.count >= 2, (array[0] as? NSNumber)?.intValue == 1, let chunk = array[1] as? String {
                chunks.append(chunk)
            }
            cursor = end
        }
        return chunks.joined()
    }

    /// Where the JSON array or object opening at `start` closes, skipping
    /// whatever is inside strings. Nil if it never does, or closes wrongly.
    static func containerEnd(in text: String, from start: String.Index) -> String.Index? {
        var closers: [Character] = []
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else {
                switch character {
                case "\"": inString = true
                case "[": closers.append("]")
                case "{": closers.append("}")
                case "]", "}":
                    guard closers.last == character else { return nil }
                    closers.removeLast()
                    if closers.isEmpty { return text.index(after: index) }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func budget(named name: String, in stream: String) -> Allowance? {
        var found: Set<String> = []
        var budgets: [Allowance] = []
        var cursor = stream.startIndex
        while let key = stream.range(of: "\"\(name)\":", range: cursor..<stream.endIndex) {
            cursor = key.upperBound
            guard let start = stream[cursor...].firstIndex(where: { !$0.isWhitespace }), stream[start] == "{",
                  let end = containerEnd(in: stream, from: start)
            else { continue }
            let object = String(stream[start..<end])
            cursor = end
            guard found.insert(object).inserted, let budget = allowance(fromBudget: Data(object.utf8)) else { continue }
            budgets.append(budget)
        }
        return budgets.count == 1 ? budgets[0] : nil
    }

    private struct BudgetReply: Decodable {
        let usagePercentage: Double?
        let resetAt: String?

        enum CodingKeys: String, CodingKey {
            case usagePercentage = "usage_percentage"
            case resetAt = "reset_at"
        }
    }

    /// One allowance, by its reported percentage. A server-rendered date may
    /// arrive as React's `$D…` form, which is the same stamp behind a tag.
    static func allowance(fromBudget data: Data) -> Allowance? {
        (try? JSONDecoder().decode(BudgetReply.self, from: data)).flatMap(allowance)
    }

    private static func allowance(_ reply: BudgetReply) -> Allowance? {
        guard let percent = reply.usagePercentage, percent.isFinite, percent >= 0 else { return nil }
        let stamp = reply.resetAt.map { $0.hasPrefix("$D") ? String($0.dropFirst(2)) : $0 }
        return Allowance(percentUsed: percent, resetsAt: ProfileHTTP.date(stamp))
    }

    private struct VibeReply: Decodable {
        struct Result: Decodable {
            struct Payload: Decodable { let json: BudgetReply? }
            let data: Payload?
        }

        let result: Result?
    }

    /// The console's Vibe figure, used only when the subscription page has
    /// none: `[{ result: { data: { json: { usage_percentage, reset_at } } } }]`.
    static func vibe(from data: Data) -> Allowance? {
        guard let replies = try? JSONDecoder().decode([VibeReply].self, from: data),
              let json = replies.first?.result?.data?.json
        else { return nil }
        return allowance(json)
    }

    /// Mistral bills a subscription by the month, and the allowances reset
    /// with it; the month's length is not a stated one, so it only sorts.
    static func reading(_ allowances: Allowances, credit: ProviderUsage.CreditAmount?, context: ProfileContext,
                        now: Date = Date()) -> ProviderUsage {
        let windows = [("api", "API", allowances.api), ("vibe", "Vibe", allowances.vibe)]
            .compactMap { id, scope, allowance -> UsageWindow? in
                guard let allowance else { return nil }
                return UsageWindow(
                    id: "mistral.\(id)",
                    kind: .monthly,
                    scope: scope,
                    usedFraction: allowance.percentUsed / 100,
                    windowSeconds: 30 * 86_400,
                    resetsAt: allowance.resetsAt,
                    reportsLength: false,
                    isExhausted: allowance.percentUsed >= 100
                )
            }

        guard !windows.isEmpty || credit != nil else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, creditBalance: credit.map(money), creditRemaining: credit, at: now)
    }

    static func money(_ wallet: ProviderUsage.CreditAmount) -> String {
        wallet.amount.formatted(
            .currency(code: wallet.currency)
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }

    // MARK: - Requests

    private static func request(_ url: URL, cookies: Cookies, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.setValue(cookies.header, forHTTPHeaderField: "Cookie")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("https://admin.mistral.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://admin.mistral.ai/organization/billing", forHTTPHeaderField: "Referer")
        if let csrf = cookies.csrf { request.setValue(csrf, forHTTPHeaderField: "X-CSRFTOKEN") }
        return request
    }

    /// The console is a different origin, so it gets only what it needs: the
    /// session, the CSRF cookie, and the same token as a header.
    private static func vibeRequest(cookies: Cookies) -> URLRequest {
        var request = URLRequest(url: vibeEndpoint)
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.setValue(cookies.header, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let csrf = cookies.csrf { request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken") }
        return request
    }

    /// One request, with redirects not followed. A missing or expired session
    /// is answered with a redirect to Mistral's sign-in page; followed, it
    /// would read as a page that "worked" and carry the cookies along with it.
    static func data(for request: URLRequest, session: URLSession? = nil) async
        -> Result<Data, ProviderUsage.Unavailability> {
        guard let (data, response) = try? await (session ?? NetworkSession.shared)
                .data(for: request, delegate: StayPut.shared),
              let http = response as? HTTPURLResponse
        else { return .failure(.unreachable) }
        return status(ProfileHTTP.Reply(data: data, status: http.statusCode))
    }

    /// A redirect is a session that no longer works; everything else means
    /// what it means everywhere.
    static func status(_ reply: ProfileHTTP.Reply) -> Result<Data, ProviderUsage.Unavailability> {
        if (300..<400).contains(reply.status) { return .failure(.sessionExpired) }
        return ProfileHTTP.classify(reply, refused: .sessionExpired)
    }
}

/// Declines every redirect, so the 3xx itself comes back.
private final class StayPut: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = StayPut()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
