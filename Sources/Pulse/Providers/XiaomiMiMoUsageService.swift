// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Xiaomi's MiMo open platform, read through the console's own endpoints.
///
/// **A browser session, not a key.** The platform issues API keys for
/// inference, and none of them answer the console's account routes — the plan
/// and the balance are behind the same `api-platform_serviceToken` cookie the
/// web console uses. So the credential is a session, as Ollama's is, with the
/// same consequences: Safari's store needs Full Disk Access, and Chromium's
/// asks for keychain permission once.
///
/// **The ring is the Coding Plan, not the balance.** The account carries two
/// separate things: a monthly token allowance bought as a plan, and a prepaid
/// cash balance for anything past it. Only the first has a denominator, so
/// only the first can be a ring — the balance rides along as money on the
/// card, the way Command Code's does. An account with no plan is not a fault;
/// it is an account that buys tokens by the yuan, and it says so.
enum XiaomiMiMoError: Error, Equatable {
    case missingCookie
    case invalidCookie
    /// The session is there and the platform refused it — expired, or signed
    /// out elsewhere. Separate from `missingCookie`, because one is "set this
    /// up" and the other is "you already did, do it again".
    case sessionExpired
    case noPlan
    case unreadableReply(String)
    case rateLimited
    case serverError
    /// Nothing came back at all — no network, DNS, TLS, a timeout. Distinct
    /// from `unreadableReply`, which means something did come back.
    case unreachable
}

/// What one read of the console returns.
struct XiaomiMiMoSnapshot: Equatable, Sendable {
    /// The plan's month of tokens: used, and out of how many. Nil on an
    /// account that has no plan running, which is a real state rather than a
    /// failed read.
    struct Plan: Equatable, Sendable {
        let used: Int
        let limit: Int
        let periodEnd: Date?
        let code: String?
    }

    let plan: Plan?
    /// Money left on the account, and in what. Reported by every account,
    /// including one with no plan.
    let balance: Double?
    let currency: String?
}

/// The cookie names the console's own requests carry.
///
/// Only these are kept. A browser store for this host also holds analytics and
/// preference cookies, and a credential store that forwards everything it
/// found is a credential store that leaks whatever the site adds next.
enum XiaomiMiMoCookie {
    /// The two the platform will not answer without.
    static let required = ["api-platform_serviceToken", "userId"]
    /// Sent when present. The console includes them and the endpoints work
    /// without them, so they are carried rather than required — a session that
    /// only has the two above is still a session.
    static let optional = ["api-platform_ph", "api-platform_slh"]

    /// A `Cookie:` header reduced to the names above, or nil if the two
    /// required ones are not both in it.
    ///
    /// Takes what a browser store hands over *or* what somebody pasted out of
    /// their network tab, which is why the `Cookie:` prefix is tolerated and
    /// why the value is checked rather than trusted: a header assembled from
    /// an arbitrary string is a header injection if a value carries a newline.
    static func normalize(_ input: String) throws -> String {
        guard !input.unicodeScalars.contains(where: { $0.value < 32 || $0.value > 126 }) else {
            throw XiaomiMiMoError.invalidCookie
        }
        var header = input.trimmingCharacters(in: .whitespaces)
        if header.lowercased().hasPrefix("cookie:") {
            header = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard !header.isEmpty else { throw XiaomiMiMoError.missingCookie }
        guard header.utf8.count <= 32_768 else { throw XiaomiMiMoError.invalidCookie }

        let wanted = Set(required + optional)
        var kept: [String] = []
        var seen = Set<String>()
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard wanted.contains(name) else { continue }
            guard !value.isEmpty, !value.contains("\""), !value.contains("\\"),
                  !value.contains(" ") else {
                throw XiaomiMiMoError.invalidCookie
            }
            // A host-only row and a domain row for one name is normal in every
            // browser store, and the host match returns both. The first wins,
            // as it does in any cookie header — throwing here would discard
            // the whole browser over something that is not a fault. The lesson
            // is Ollama's; see `OllamaSessionCookie.normalize`.
            guard seen.insert(name).inserted else { continue }
            kept.append("\(name)=\(value)")
        }
        guard required.allSatisfy({ seen.contains($0) }) else {
            throw XiaomiMiMoError.invalidCookie
        }
        return kept.joined(separator: "; ")
    }
}

/// A read-only adapter for the console's account routes. Kept apart from the
/// app so the envelope and the parsing are testable without a session.
struct XiaomiMiMoClient: Sendable {
    static let host = "platform.xiaomimimo.com"
    static let base = URL(string: "https://platform.xiaomimimo.com/api/v1")!
    /// Where somebody is sent to sign in, and the page the console fetches
    /// these from — so the `Referer` is true rather than invented.
    static let consoleURL = URL(string: "https://platform.xiaomimimo.com/#/console/balance")!

    /// Optional only as a test seam. Production resolves the shared session at
    /// request time so a proxy change cannot leave a client holding the one
    /// that was invalidated.
    var session: URLSession?

    func fetch(cookie: String) async throws -> XiaomiMiMoSnapshot {
        let header = try XiaomiMiMoCookie.normalize(cookie)

        // The plan is what the ring is for, so its failure is the call's
        // failure. The balance is a line on the card, so a balance route that
        // does not answer costs that line and nothing else.
        //
        // **What each route threw is kept, not discarded.** `try?` here made
        // every status `get` bothers to classify unreachable: an HTTP 401, a
        // 429 and a 500 all became three nils and came out as "the reply could
        // not be read". A session that needs signing in again has to say so.
        async let planDetail = outcome(of: "tokenPlan/detail", cookie: header)
        async let planUsage = outcome(of: "tokenPlan/usage", cookie: header)
        async let balance = outcome(of: "balance", cookie: header)

        let routes = await [planDetail, planUsage, balance]
        let detailData = try? routes[0].get()
        let usageData = try? routes[1].get()
        let balanceData = try? routes[2].get()

        // Every route is the same envelope, so one expired session shows up on
        // all three. Reported from whichever answered rather than from a
        // fourth request made only to ask.
        for data in [detailData, usageData, balanceData].compactMap({ $0 }) {
            if let refusal = Self.refusal(in: data) { throw refusal }
        }

        // Nothing answered. Report what the routes actually said rather than
        // one blanket sentence: the worst of the three, so a session problem
        // outranks a timeout and the reader is sent to the right remedy.
        if detailData == nil, usageData == nil, balanceData == nil {
            throw Self.worst(of: routes)
        }

        let money = balanceData.flatMap { try? Self.parseBalance($0) }
        return XiaomiMiMoSnapshot(
            plan: Self.parsePlan(detail: detailData, usage: usageData),
            balance: money?.amount,
            currency: money?.currency)
    }

    /// One route's answer, kept whichever way it went.
    private func outcome(of path: String, cookie: String) async -> Result<Data, XiaomiMiMoError> {
        do {
            return .success(try await get(path, cookie: cookie))
        } catch let error as XiaomiMiMoError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.unreachable)
        } catch {
            // A transport failure — no network, DNS, TLS, a timeout. **Not
            // `unreadableReply`**, which means something came back and could
            // not be parsed; `ConnectionRemedy` offers Setup help for that and
            // Retry for this, and a dropped wifi connection should not send
            // somebody to the documentation.
            return .failure(.unreachable)
        }
    }

    /// The most actionable of several failures.
    ///
    /// A session that has to be signed in again outranks a timeout: if one
    /// route says the login is refused and another merely timed out, the login
    /// is the thing to tell the reader about.
    private static func worst(of routes: [Result<Data, XiaomiMiMoError>]) -> XiaomiMiMoError {
        let failures = routes.compactMap { route -> XiaomiMiMoError? in
            guard case .failure(let error) = route else { return nil }
            return error
        }
        let rank: (XiaomiMiMoError) -> Int = { error in
            switch error {
            case .sessionExpired, .missingCookie, .invalidCookie: 3
            case .rateLimited, .serverError: 2
            case .unreachable: 1
            case .noPlan, .unreadableReply: 0
            }
        }
        return failures.max { rank($0) < rank($1) } ?? .unreachable
    }

    private func get(_ path: String, cookie: String) async throws -> Data {
        var request = URLRequest(url: Self.base.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://\(Self.host)", forHTTPHeaderField: "Origin")
        request.setValue(Self.consoleURL.absoluteString, forHTTPHeaderField: "Referer")

        let (data, response) = try await (session ?? NetworkSession.shared).data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw XiaomiMiMoError.unreadableReply("no HTTP response")
        }
        switch http.statusCode {
        case 200: return data
        // An expired session is answered by redirecting the API call at the
        // login flow, so a 3xx here is a sign-in problem rather than a moved
        // endpoint. `URLSession` follows redirects, so this is only reached
        // when one was not followed.
        case 300..<400, 401: throw XiaomiMiMoError.sessionExpired
        case 403: throw XiaomiMiMoError.sessionExpired
        case 429: throw XiaomiMiMoError.rateLimited
        case 500...599: throw XiaomiMiMoError.serverError
        default: throw XiaomiMiMoError.unreadableReply("HTTP \(http.statusCode)")
        }
    }

    /// The envelope's own verdict. The platform answers a refused session with
    /// **HTTP 200** and a code in the body, which is the shape that had Zhipu
    /// reporting "the service returned an error" for the commonest mistake
    /// there is — so the body is read on every route, not just the failing one.
    private static func refusal(in data: Data) -> XiaomiMiMoError? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        switch envelope.code {
        case 0: return nil
        case 401, 403: return .sessionExpired
        default: return nil
        }
    }

    static func parsePlan(detail: Data?, usage: Data?) -> XiaomiMiMoSnapshot.Plan? {
        let decoder = JSONDecoder()
        // **The envelope first, as `parseBalance` does.** The platform answers
        // over HTTP 200 whatever happened, so a body whose `code` is not zero
        // is a failure wearing a success's clothes. Read without this, a
        // `code` 500 carrying an empty `items` came out as "no Coding Plan on
        // this account" — a fault reported as a subscription.
        let usagePayload = usage
            .flatMap { try? decoder.decode(PlanUsage.self, from: $0) }
            .flatMap { $0.code == 0 ? $0 : nil }
        // `monthUsage.items` is a list because the console draws a row per
        // bucket; the plan's own allowance is the first. An empty list is an
        // account with no plan, which is why this returns nil rather than a
        // zero — a ring at 0% would say "you have a full month left".
        guard let item = usagePayload?.data?.monthUsage?.items.first, item.limit > 0 else {
            return nil
        }

        let detailPayload = detail
            .flatMap { try? decoder.decode(PlanDetail.self, from: $0) }
            .flatMap { $0.code == 0 ? $0 : nil }?.data
        // An expired plan reports last month's numbers until it is renewed.
        // Those are not a current allowance, so they are not drawn.
        if detailPayload?.expired == true { return nil }

        return .init(used: item.used,
                     limit: item.limit,
                     periodEnd: detailPayload?.currentPeriodEnd.flatMap(Self.date(from:)),
                     code: detailPayload?.planCode)
    }

    static func parseBalance(_ data: Data) throws -> (amount: Double, currency: String)? {
        let payload = try JSONDecoder().decode(Balance.self, from: data)
        guard payload.code == 0, let body = payload.data,
              let amount = Double(body.balance) else { return nil }
        let currency = body.currency.trimmingCharacters(in: .whitespaces)
        guard !currency.isEmpty else { return nil }
        return (amount, currency)
    }

    /// The console's own format, in UTC. Not ISO-8601, so `ISO8601DateFormatter`
    /// returns nil on it and the card silently loses its reset.
    static func date(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)
    }

    private struct Envelope: Decodable { let code: Int }

    private struct PlanDetail: Decodable {
        let code: Int
        let data: Body?
        struct Body: Decodable {
            let planCode: String?
            let currentPeriodEnd: String?
            let expired: Bool?
        }
    }

    private struct PlanUsage: Decodable {
        let code: Int
        let data: Body?
        struct Body: Decodable { let monthUsage: Month? }
        struct Month: Decodable { let items: [Item] }
        struct Item: Decodable {
            let name: String?
            let used: Int
            let limit: Int
        }
    }

    private struct Balance: Decodable {
        let code: Int
        let data: Body?
        struct Body: Decodable {
            let balance: String
            let currency: String
        }
    }
}

struct XiaomiMiMoUsageService: Sendable {
    let cookie: String?
    var client = XiaomiMiMoClient()

    func fetch() async -> ProviderUsage {
        guard let cookie, !cookie.isEmpty else {
            return .unavailable(.xiaomiMiMo, reason: .xiaomiSessionMissing)
        }
        do {
            let snapshot = try await client.fetch(cookie: cookie)
            guard let plan = snapshot.plan else {
                // Not a failure: an account can buy tokens by the yuan with no
                // plan at all. Saying so beats a ring at 0%, which would read
                // as a full month nobody has.
                return .unavailable(.xiaomiMiMo, reason: .xiaomiNoCodingPlan)
            }

            let window = UsageWindow(
                id: "xiaomi.plan",
                kind: .monthly,
                scope: nil,
                usedFraction: Double(plan.used) / Double(plan.limit),
                // Thirty days is a **sort key, not a reported length**. The
                // platform states when the period ends and never how long it
                // is, and a billing month is not a fixed number of seconds —
                // so `reportsLength` is false and the window-clock arc and the
                // forecast leave it alone rather than dividing by a number
                // nobody stated. Copilot's calendar month is carried the same
                // way; see `UsageWindow.reportsLength`.
                windowSeconds: 30 * 86_400,
                resetsAt: plan.periodEnd,
                reportsLength: false,
                isExhausted: plan.used >= plan.limit)

            return .init(account: AccountKey(.xiaomiMiMo),
                         windows: [window],
                         observedAt: Date(),
                         state: .live,
                         plan: plan.code,
                         creditBalance: Self.money(snapshot))
        } catch let error as XiaomiMiMoError {
            let reason: ProviderUsage.Unavailability = switch error {
            case .missingCookie, .invalidCookie: .xiaomiSessionMissing
            case .sessionExpired: .xiaomiSessionExpired
            case .noPlan: .xiaomiNoCodingPlan
            case .rateLimited: .rateLimited
            case .serverError: .serverError
            case .unreadableReply: .unreadableReply
            case .unreachable: .unreachable
            }
            return .unavailable(.xiaomiMiMo, reason: reason)
        } catch {
            return .unavailable(.xiaomiMiMo, reason: .unreachable)
        }
    }

    /// The prepaid balance as a line on the card. A display string rather than
    /// a `creditRemaining`, because there is no allowance to compare it
    /// against — `reportsSpendableBalance` stays false and no "warn below"
    /// line is offered for something Pulse cannot say is running out.
    private static func money(_ snapshot: XiaomiMiMoSnapshot) -> String? {
        guard let balance = snapshot.balance, let currency = snapshot.currency else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: NSNumber(value: balance))
    }
}
