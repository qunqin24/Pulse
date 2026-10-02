// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// ZoomMate, Zoom's AI assistant: one credit allowance against a budget cap,
/// for a billing cycle whose start and end the service states.
///
/// Read with a Zoom browser session, the way ZoomMate's own web client does:
/// the session is exchanged for a short-lived bearer token at
/// `GET /ai-computer/api/v1/login/?continue=https://zoommate.zoom.us/`, and
/// that token reads `GET /ai-computer/api/v1/credits/status`. Both are on
/// `ai.zoom.us`, with `zoommate.zoom.us` — which serves the same API — tried
/// when the first does not answer. The token is held for the one refresh and
/// never stored; nothing is written anywhere. The shapes are second-hand —
/// taken from CodexBar's ZoomMate provider and its tests, not from a
/// captured reply — and so are the cookie names.
///
/// Left out: the credit history and the pace built on it. That is spend over
/// thirty days, which Pulse has no place for, and pace is Pulse's own work
/// from the cycle it already draws.
extension ProviderProfile {
    static let zoomMate = ProviderProfile(
        displayName: "ZoomMate",
        iconResource: "extension",
        credential: .sessionCookie(host: "zoom.us", cookies: ZoomMateUsageService.cookies),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        spendingIsWatchedLocally: false,
        brandColor: 0x0B5CFF,
        setupSlug: "zoommate",
        fetch: { await ZoomMateUsageService.fetch($0) }
    )
}

enum ZoomMateUsageService {
    /// Zoom's session cookie, and Cloudflare's clearance beside it. Both are
    /// set on the parent `zoom.us`, which is why that is the host read.
    static let cookies = ["_zm_ssid", "cf_clearance"]
    /// The two hosts that serve ZoomMate's API, in the order its web client
    /// uses them. Nothing is sent anywhere else.
    static let hosts = ["ai.zoom.us", "zoommate.zoom.us"]
    private static let origin = "https://zoommate.zoom.us"

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential.flatMap({ ProviderProfile.keep($0, cookies: cookies) }) else {
            return context.unavailable(.sessionMissing)
        }
        let http = session ?? cookieSession()
        defer { if session == nil { http.invalidateAndCancel() } }

        var last: ProviderUsage.Unavailability = .unreachable
        for host in hosts {
            switch await status(host: host, cookie: cookie, session: http) {
            case .success(let data):
                return reading(from: data, context: context)
            // Only a host that did not answer is worth asking the other one
            // about. A refused session or an unreadable reply would be the
            // same on both.
            case .failure(let reason) where reason == .unreachable || reason == .serverError:
                last = reason
            case .failure(let reason):
                return context.unavailable(reason)
            }
        }
        return context.unavailable(last)
    }

    /// The session exchanged for a token, then the token for the status —
    /// both on the same host.
    private static func status(host: String, cookie: String, session: URLSession)
        async -> Result<Data, ProviderUsage.Unavailability> {
        var login = URLComponents()
        login.scheme = "https"
        login.host = host
        login.path = "/ai-computer/api/v1/login/"
        login.queryItems = [URLQueryItem(name: "continue", value: origin + "/")]
        guard let loginURL = login.url,
              let statusURL = URL(string: "https://\(host)/ai-computer/api/v1/credits/status")
        else { return .failure(.unreadableReply) }

        let token: String
        switch await get(loginURL, cookie: cookie, token: nil, session: session) {
        case .failure(let reason): return .failure(reason)
        case .success(let data):
            switch self.token(from: data) {
            case .failure(let reason): return .failure(reason)
            case .success(let minted): token = minted
            }
        }
        return await get(statusURL, cookie: cookie, token: token, session: session)
    }

    private static func get(_ url: URL, cookie: String, token: String?, session: URLSession)
        async -> Result<Data, ProviderUsage.Unavailability> {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(origin, forHTTPHeaderField: "Referer")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        switch await ProfileHTTP.reply(for: request, session: session) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let reply):
            // Redirects are refused, so a signed-out session arrives as the
            // redirect to Zoom's sign-in page.
            if (300..<400).contains(reply.status) { return .failure(.sessionExpired) }
            return ProfileHTTP.classify(reply, refused: .sessionExpired)
        }
    }

    /// A `Cookie` header set by hand is carried across a redirect to any
    /// host, so this session refuses redirects outright.
    private static func cookieSession() -> URLSession {
        let configuration = NetworkSession.configured(.ephemeral)
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    // MARK: - Reading the replies

    private struct Login: Decodable {
        struct Payload: Decodable { let nak: String? }

        let success: Bool?
        let data: Payload?
    }

    /// The bearer token is `data.nak`. A reply that says it failed is the
    /// session being turned away.
    static func token(from data: Data) -> Result<String, ProviderUsage.Unavailability> {
        guard let login = try? JSONDecoder().decode(Login.self, from: data) else { return .failure(.unreadableReply) }
        if let nak = login.data?.nak?.trimmingCharacters(in: .whitespacesAndNewlines), !nak.isEmpty {
            return .success(nak)
        }
        return .failure(login.success == false ? .sessionExpired : .unreadableReply)
    }

    private struct Reply: Decodable {
        struct Status: Decodable {
            let budgetCap: Double?
            let usedCredit: Double?
            let remainingCredit: Double?
            let allowOverage: Bool?
            let cycleStartDate: Double?
            let cycleEndDate: Double?
            let isQuotaAvailable: Bool?
            let isUnlimited: Bool?

            enum CodingKeys: String, CodingKey {
                case budgetCap = "budget_cap"
                case usedCredit = "used_credit"
                case remainingCredit = "remaining_credit"
                case allowOverage = "allow_overage"
                case cycleStartDate = "cycle_start_date"
                case cycleEndDate = "cycle_end_date"
                case isQuotaAvailable = "is_quota_available"
                case isUnlimited = "is_unlimited"
            }
        }

        struct Payload: Decodable {
            let creditStatus: Status?

            enum CodingKeys: String, CodingKey { case creditStatus = "credit_status" }
        }

        let data: Payload?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let status = reply.data?.creditStatus
        else { return context.unavailable(.unreadableReply) }

        // Unlimited has no cap to measure against, and a cap of nothing is
        // not one either. Neither is drawn as 0%.
        guard status.isUnlimited != true,
              let cap = status.budgetCap, cap.isFinite, cap > 0,
              let used = status.usedCredit ?? status.remainingCredit.map({ cap - $0 }),
              used.isFinite, used >= 0
        else { return context.unavailable(.noLimitsReported) }

        let start = date(status.cycleStartDate)
        let end = date(status.cycleEndDate)
        // The cycle's length is stated when both of its ends are.
        let stated = start.flatMap { start in end.map { Int($0.timeIntervalSince(start)) } }.flatMap { $0 > 0 ? $0 : nil }
        let fraction = used / cap
        let window = UsageWindow(
            id: "zoommate.credits",
            kind: .credits,
            scope: nil,
            usedFraction: fraction,
            windowSeconds: stated ?? 30 * 86_400,
            resetsAt: end,
            reportsLength: stated != nil,
            // Past the cap is only the end if overage isn't allowed.
            isExhausted: status.isQuotaAvailable == false || (fraction >= 1 && status.allowOverage != true)
        )
        return context.reading([window], at: now)
    }

    /// Epoch milliseconds.
    private static func date(_ milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds.isFinite, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
