// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Notion AI's usage allowance on a Business or Enterprise workspace: a
/// rolling window (six hours when this was written) and the billing period,
/// each reported as credits used out of a limit.
///
/// Read with the browser session Notion's web app uses — the `token_v2`
/// cookie — from the two internal endpoints its own Settings → Notion AI →
/// Usage page calls, both on `app.notion.com`:
/// `POST /api/v3/getSpaces` for the workspaces this account can see, then
/// `POST /api/v3/getCreditRateLimitStatus` for the chosen one. Neither is a
/// public API. The shapes are second-hand — taken from CodexBar's Notion
/// provider and its fixtures, not from a captured reply.
///
/// **Which workspace.** Pulse has no picker for one, so it takes the first
/// workspace on a Business or Enterprise plan, or the first there is. A plan
/// without an allowance answers `not_applicable`, which is "no plan with
/// usage limits" — an answer, not an outage.
extension ProviderProfile {
    static let notionAI = ProviderProfile(
        displayName: "Notion AI",
        iconResource: "notion",
        credential: .sessionCookie(host: "notion.com", cookies: NotionAIUsageService.cookies),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        spendingIsWatchedLocally: false,
        setupSlug: "notion-ai",
        fetch: { await NotionAIUsageService.fetch($0) }
    )
}

enum NotionAIUsageService {
    /// `token_v2` is the session; without it every call is a 401.
    static let cookies = ["token_v2"]
    static let base = URL(string: "https://app.notion.com")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential.flatMap({ ProviderProfile.keep($0, cookies: cookies) }) else {
            return context.unavailable(.sessionMissing)
        }
        let http = session ?? cookieSession()
        defer { if session == nil { http.invalidateAndCancel() } }

        let workspace: Workspace
        switch await post("getSpaces", body: [:], cookie: cookie, session: http) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data):
            guard let spaces = workspaces(from: data) else { return context.unavailable(.unreadableReply) }
            guard let chosen = choose(from: spaces) else { return context.unavailable(.noPlan) }
            workspace = chosen
        }

        switch await post("getCreditRateLimitStatus", body: ["spaceId": workspace.id], cookie: cookie, session: http) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data): return reading(from: data, plan: workspace.tier, context: context)
        }
    }

    private static func post(
        _ method: String, body: [String: String], cookie: String, session: URLSession
    ) async -> Result<Data, ProviderUsage.Unavailability> {
        var request = URLRequest(url: base.appending(path: "api/v3/\(method)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(base.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        switch await ProfileHTTP.reply(for: request, session: session) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let reply):
            // Redirects are refused, so a signed-out session arrives as the
            // redirect to the sign-in page rather than as the page.
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

    // MARK: - Workspaces

    struct Workspace: Equatable, Sendable {
        let id: String
        /// The plan as Notion spells it — "business", "enterprise", "free".
        let subscriptionTier: String?

        var hasAllowance: Bool { ["business", "enterprise"].contains(subscriptionTier?.lowercased()) }
        /// The plan's name for the card, capitalised as Notion's own page does.
        var tier: String? {
            guard let raw = subscriptionTier?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
            return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    /// `getSpaces` is a record map keyed by user id, each holding its
    /// `notion_user` and `space` records. Only a reply that names exactly one
    /// user is read: taking whichever key came first could report another
    /// account's allowance. Nil when it cannot be read; empty when it names
    /// the user and no workspace.
    static func workspaces(from data: Data) -> [Workspace]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let identified = root.keys.filter { key in
            let users = (root[key] as? [String: Any])?["notion_user"] as? [String: Any]
            return users?[key].flatMap(record)?["id"] as? String == key
        }
        let userID: String
        if identified.count == 1, let only = identified.first {
            userID = only
        } else if identified.isEmpty, root.count == 1, let only = root.keys.first {
            // Older replies leave the id out of the record; one key is still one user.
            userID = only
        } else {
            return nil
        }
        guard let container = root[userID] as? [String: Any] else { return nil }
        let spaces = container["space"] as? [String: Any] ?? [:]
        return spaces.keys.sorted().compactMap { key in
            guard let fields = spaces[key].flatMap(record) else { return nil }
            return Workspace(id: fields["id"] as? String ?? key, subscriptionTier: fields["subscription_tier"] as? String)
        }
    }

    /// Records come as `{"value": {…}}` or, newer, `{"value": {"value": {…}}}`.
    private static func record(_ raw: Any) -> [String: Any]? {
        guard let outer = raw as? [String: Any] else { return nil }
        guard let value = outer["value"] as? [String: Any] else { return outer }
        return value["value"] as? [String: Any] ?? value
    }

    static func choose(from workspaces: [Workspace]) -> Workspace? {
        workspaces.first(where: \.hasAllowance) ?? workspaces.first
    }

    // MARK: - The allowance

    private struct Reply: Decodable {
        struct Rolling: Decodable {
            let window: String?
            let used: Double?
            let limit: Double?
        }

        struct Billing: Decodable {
            let used: Double?
            let limit: Double?
            let periodEndMs: Double?
        }

        let status: String?
        let window: Rolling?
        let resetsInSeconds: Double?
        let billingPeriodWindow: Billing?
    }

    static func reading(from data: Data, plan: String? = nil, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return context.unavailable(.unreadableReply)
        }
        if reply.status?.lowercased() == "not_applicable" { return context.unavailable(.noPlan) }
        // Every field is optional, so an unrelated body decodes as all nil.
        guard reply.window != nil || reply.billingPeriodWindow != nil else {
            return context.unavailable(.unreadableReply)
        }

        var windows: [UsageWindow] = []
        if let rolling = reply.window, let used = fraction(rolling.used, of: rolling.limit) {
            let reset = reply.resetsInSeconds.flatMap { $0 >= 0 && $0.isFinite ? now.addingTimeInterval($0) : nil }
            let (kind, seconds, stated) = length(of: rolling.window)
            windows.append(UsageWindow(
                id: "notion.rolling", kind: kind, scope: nil, usedFraction: used,
                windowSeconds: seconds, resetsAt: reset, reportsLength: stated, isExhausted: used >= 1
            ))
        }
        if let billing = reply.billingPeriodWindow, let used = fraction(billing.used, of: billing.limit) {
            // A billing period is only as long as the month it falls in, and
            // Notion states only its end.
            let reset = billing.periodEndMs.flatMap { $0 > 0 && $0.isFinite ? Date(timeIntervalSince1970: $0 / 1000) : nil }
            windows.append(UsageWindow(
                id: "notion.billing", kind: .monthly, scope: nil, usedFraction: used,
                windowSeconds: 30 * 86_400, resetsAt: reset, reportsLength: false, isExhausted: used >= 1
            ))
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows.sorted { $0.windowSeconds < $1.windowSeconds }, plan: plan, at: now)
    }

    /// Credits used over the stated limit. A missing or non-positive limit is
    /// nothing to measure against, not 0%. Over the limit is kept as reported.
    private static func fraction(_ used: Double?, of limit: Double?) -> Double? {
        guard let used, let limit, used.isFinite, limit.isFinite, used >= 0, limit > 0 else { return nil }
        return used / limit
    }

    /// Notion states the rolling window as a token — `6h`. A token that
    /// can't be read leaves the allowance with no length claimed.
    static func length(of token: String?) -> (UsageWindow.Kind, Int, Bool) {
        guard let raw = token?.trimmingCharacters(in: .whitespaces).lowercased(), let unit = raw.last,
              let value = Int(raw.dropLast()), value > 0
        else { return (.credits, 86_400, false) }
        let unitSeconds: Int
        switch unit {
        case "m": unitSeconds = 60
        case "h": unitSeconds = 3_600
        case "d": unitSeconds = 86_400
        case "w": unitSeconds = 7 * 86_400
        default: return (.credits, 86_400, false)
        }
        let seconds = value * unitSeconds
        switch seconds {
        case 5 * 3_600: return (.fiveHour, seconds, true)
        case 86_400: return (.daily, seconds, true)
        case 7 * 86_400: return (.weekly, seconds, true)
        default: return (.other(seconds: seconds), seconds, true)
        }
    }
}
