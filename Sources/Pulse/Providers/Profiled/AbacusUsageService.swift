// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Abacus AI's ChatLLM / RouteLLM plan: one allowance of compute credits,
/// with the used amount and the total both reported, and the next billing
/// date as its reset.
///
/// Read with a browser session from `apps.abacus.ai`, from the two endpoints
/// its own web app calls: `GET /api/_getOrganizationComputePoints` for the
/// credits, and `POST /api/_getBillingInfo` for the next billing date and the
/// plan's name. The second is optional: without it the credits still show,
/// with no reset. The shapes are second-hand — taken from CodexBar's Abacus
/// provider and its tests, not from a captured reply — and so are the cookie
/// names, which neither source pins down.
///
/// **No length is claimed.** Nothing in either reply says how long a cycle
/// is; the billing date says only when this one ends. The thirty days on the
/// window are a sort key.
extension ProviderProfile {
    static let abacus = ProviderProfile(
        displayName: "Abacus AI",
        iconResource: "extension",
        credential: .sessionCookie(host: "abacus.ai", cookies: AbacusUsageService.cookies),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        spendingIsWatchedLocally: false,
        setupSlug: "abacus",
        fetch: { await AbacusUsageService.fetch($0) }
    )
}

enum AbacusUsageService {
    /// Abacus's session sits under any one of these names; CodexBar accepts
    /// each of them and names none as the one. Any one is enough, and every
    /// one present is kept.
    static let cookies = ["sessionid|session_id|session_token|auth_token|access_token"]
    static let pointsURL = URL(string: "https://apps.abacus.ai/api/_getOrganizationComputePoints")!
    static let billingURL = URL(string: "https://apps.abacus.ai/api/_getBillingInfo")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential.flatMap({ ProviderProfile.keep($0, cookies: cookies) }) else {
            return context.unavailable(.sessionMissing)
        }
        let http = session ?? cookieSession()
        defer { if session == nil { http.invalidateAndCancel() } }

        async let points = send(pointsURL, method: "GET", cookie: cookie, session: http)
        async let billing = send(billingURL, method: "POST", cookie: cookie, session: http)

        switch await points {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            // The billing date is extra: a failure there costs only the reset.
            let billingData = try? await billing.get()
            return reading(points: data, billing: billingData, context: context)
        }
    }

    private static func send(_ url: URL, method: String, cookie: String, session: URLSession)
        async -> Result<Data, ProviderUsage.Unavailability> {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }

        switch await ProfileHTTP.reply(for: request, session: session) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let reply):
            // Redirects are refused, so a signed-out session arrives as the
            // redirect to the sign-in page.
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

    /// Both endpoints answer `{ success, result, error }`, and a refused
    /// session can come back as a 200 that says so in `error`.
    private struct Envelope<Payload: Decodable>: Decodable {
        let success: Bool?
        let result: Payload?
        let error: String?
    }

    private struct Points: Decodable {
        let totalComputePoints: Double?
        let computePointsLeft: Double?
    }

    private struct Billing: Decodable {
        let nextBillingDate: String?
        let currentTier: String?
    }

    static func reading(points data: Data, billing: Data?, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        let points: Points
        switch payload(Points.self, from: data) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let found): points = found
        }

        // Both halves are reported; neither is ever assumed.
        guard let total = points.totalComputePoints, let left = points.computePointsLeft,
              total.isFinite, left.isFinite, total > 0
        else { return context.unavailable(.noLimitsReported) }

        let plan = billing.flatMap { try? payload(Billing.self, from: $0).get() }
        let used = max(0, total - left) / total
        let window = UsageWindow(
            id: "abacus.credits",
            kind: .credits,
            scope: nil,
            usedFraction: used,
            windowSeconds: 30 * 86_400,
            resetsAt: ProfileHTTP.date(plan?.nextBillingDate),
            reportsLength: false,
            isExhausted: left <= 0
        )
        let tier = plan?.currentTier?.trimmingCharacters(in: .whitespaces)
        return context.reading([window], plan: tier?.isEmpty == false ? tier : nil, at: now)
    }

    private static func payload<Payload: Decodable>(_ type: Payload.Type, from data: Data)
        -> Result<Payload, ProviderUsage.Unavailability> {
        guard let envelope = try? JSONDecoder().decode(Envelope<Payload>.self, from: data) else {
            return .failure(.unreadableReply)
        }
        if envelope.success == true, let result = envelope.result { return .success(result) }
        guard envelope.success == false else { return .failure(.unreadableReply) }
        let error = envelope.error?.lowercased() ?? ""
        let signedOut = ["expired", "session", "login", "authenticate", "unauthorized", "unauthenticated", "forbidden"]
            .contains { error.contains($0) }
        return .failure(signedOut ? .sessionExpired : .serverError)
    }
}
