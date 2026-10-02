// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Warp: the plan's credits for the period, and any add-on credits bought or
/// granted on top.
///
/// Read with a key the user pastes, from the GraphQL query Warp's own app
/// sends — `GetRequestLimitInfo`, a read-only query posted to
/// `https://app.warp.dev/graphql/v2`. The API still calls credits
/// "requests". The shape is second-hand — taken from CodexBar's Warp provider
/// and its tests, not from a captured reply — and the fixture in the tests
/// says so.
///
/// - The plan's credits: `requestsUsedSinceLastRefresh` of `requestLimit`,
///   both stated, refilling at `nextRefreshTime`. The period's length is not
///   stated, so it is not claimed. An unlimited plan has no limit to draw.
/// - Add-on credits: each grant states what it was and what is left, so the
///   pack is their sum, spent after the plan's and never reset; the soonest
///   of them to lapse is shown as an expiry.
extension ProviderProfile {
    static let warp = ProviderProfile(
        displayName: "Warp",
        iconResource: "extension",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From Warp's settings, under API Keys. Stored encrypted on this Mac.") },
        setupSlug: "warp",
        discoveryPaths: ["/Applications/Warp.app", ".warp"],
        fetch: { await WarpUsageService.fetch($0) }
    )
}

enum WarpUsageService {
    static let endpoint = URL(string: "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo")!

    static let query = """
    query GetRequestLimitInfo($requestContext: RequestContext!) {
      user(requestContext: $requestContext) {
        __typename
        ... on UserOutput {
          user {
            requestLimitInfo { isUnlimited nextRefreshTime requestLimit requestsUsedSinceLastRefresh }
            bonusGrants { requestCreditsGranted requestCreditsRemaining expiration }
            workspaces { bonusGrantsInfo { grants { requestCreditsGranted requestCreditsRemaining expiration } } }
          }
        }
      }
    }
    """

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        switch await ProfileHTTP.data(for: request(key: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    static func request(key: String) -> URLRequest {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        var request = ProfileHTTP.bearer(endpoint, token: key)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // What Warp's app sends. The endpoint's edge limiter answers 429 to a
        // client that does not name itself as Warp.
        request.setValue("warp-app", forHTTPHeaderField: "x-warp-client-id")
        request.setValue("macOS", forHTTPHeaderField: "x-warp-os-category")
        request.setValue("macOS", forHTTPHeaderField: "x-warp-os-name")
        request.setValue(os, forHTTPHeaderField: "x-warp-os-version")
        request.setValue("Warp/1.0", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "operationName": "GetRequestLimitInfo",
            "query": query,
            "variables": [
                "requestContext": [
                    "clientContext": [String: Any](),
                    "osContext": ["category": "macOS", "name": "macOS", "version": os],
                ],
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Reading the reply

    private struct Reply: Decodable {
        struct Grant: Decodable {
            let requestCreditsGranted: Double?
            let requestCreditsRemaining: Double?
            let expiration: String?
        }

        struct Limit: Decodable {
            let isUnlimited: Bool?
            let nextRefreshTime: String?
            let requestLimit: Double?
            let requestsUsedSinceLastRefresh: Double?
        }

        struct Workspace: Decodable {
            struct Info: Decodable { let grants: [Grant]? }
            let bonusGrantsInfo: Info?
        }

        struct Account: Decodable {
            let requestLimitInfo: Limit?
            let bonusGrants: [Grant]?
            let workspaces: [Workspace]?
        }

        struct Output: Decodable { let user: Account? }
        struct Payload: Decodable { let user: Output? }
        struct Failure: Decodable { let message: String? }

        let data: Payload?
        let errors: [Failure]?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return context.unavailable(.unreadableReply)
        }
        // GraphQL answers a failed query with 200 and a list of errors.
        if let errors = reply.errors, !errors.isEmpty { return context.unavailable(.serverError) }
        guard let account = reply.data?.user?.user, let limit = account.requestLimitInfo else {
            return context.unavailable(.unreadableReply)
        }

        var windows: [UsageWindow] = []
        if limit.isUnlimited != true,
           let cap = limit.requestLimit, cap.isFinite, cap > 0,
           let used = limit.requestsUsedSinceLastRefresh, used.isFinite, used >= 0 {
            windows.append(UsageWindow(
                id: "warp.credits",
                kind: .credits,
                scope: nil,
                usedFraction: used / cap,
                // A sort key: the refill is stated, the period's length is not.
                windowSeconds: 30 * 86_400,
                resetsAt: ProfileHTTP.date(limit.nextRefreshTime),
                reportsLength: false,
                isExhausted: used >= cap
            ))
        }

        // Every grant with both figures, the user's own and each workspace's.
        let grants = ((account.bonusGrants ?? []) + (account.workspaces ?? []).flatMap { $0.bonusGrantsInfo?.grants ?? [] })
            .compactMap { grant -> (granted: Double, left: Double, expires: Date?)? in
                guard let granted = grant.requestCreditsGranted, granted.isFinite, granted > 0,
                      let left = grant.requestCreditsRemaining, left.isFinite, left >= 0
                else { return nil }
                return (granted, left, ProfileHTTP.date(grant.expiration))
            }
        let granted = grants.reduce(0) { $0 + $1.granted }
        if granted > 0 {
            let left = grants.reduce(0) { $0 + $1.left }
            var pack = UsageWindow(
                id: "warp.addon",
                kind: .topUp,
                scope: nil,
                usedFraction: max(granted - left, 0) / granted,
                // A sort key alone: spent after the plan's, and never reset.
                windowSeconds: 30 * 86_400,
                resetsAt: nil,
                reportsLength: false,
                isExhausted: left <= 0
            )
            pack.nextExpiry = UsageWindow.Expiry.soonest(
                of: grants.compactMap { grant in grant.expires.map { (grant.left, $0) } },
                after: now
            )
            windows.append(pack)
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, at: now)
    }
}
