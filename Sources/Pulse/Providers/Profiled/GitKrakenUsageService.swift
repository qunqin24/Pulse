// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// GitKraken AI: the account's AI credits used out of its allowance, and the
/// organization's shared pool beside it where there is one.
///
/// Read with an access token the user copies by hand from gitkraken.dev —
/// GitKraken issues no API key for this — from the route its own usage page
/// and GitLens call: `GET https://api.gitkraken.dev/v1/ai-tasks/usage`. The
/// shape is second-hand — taken from CodexBar's GitKraken plugin, which
/// follows GitLens's parser, not from a captured reply — and the fixture in
/// the tests says so.
///
/// **Credits, not a week.** CodexBar calls the allowance weekly; the reply
/// states only `resetsOn`, so no length is claimed. A limit of `-1`
/// (unlimited) or `0` (no allowance) is a statement with no fraction in it,
/// and draws nothing. The organization picker CodexBar offers (`gk-org-id`)
/// has no setting here, so the token's default organization is the one read.
extension ProviderProfile {
    static let gitKraken = ProviderProfile(
        displayName: "GitKraken AI",
        iconResource: "extension",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the access token you enter in Settings. No Keychain prompt.") },
        keySubtitle: {
            .localized("The Bearer token from gitkraken.dev's usage request, copied from the browser's developer tools. Stored encrypted on this Mac.")
        },
        spendingIsWatchedLocally: false,
        setupSlug: "gitkraken",
        fetch: { await GitKrakenUsageService.fetch($0) }
    )
}

enum GitKrakenUsageService {
    static let endpoint = URL(string: "https://api.gitkraken.dev/v1/ai-tasks/usage")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        // People copy the whole header value, "Bearer" and all.
        guard let token = token(from: context.trimmedCredential) else { return context.unavailable(.apiKeyMissing) }

        var request = ProfileHTTP.bearer(endpoint, token: token)
        // GitKraken's API asks every caller to name itself.
        request.setValue("Pulse", forHTTPHeaderField: "Client-Name")
        request.setValue(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            forHTTPHeaderField: "Client-Version"
        )

        switch await ProfileHTTP.data(for: request, session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    /// The token alone, without a leading "Bearer", or nil if nothing is left.
    static func token(from pasted: String?) -> String? {
        guard var words = pasted?.split(whereSeparator: \.isWhitespace), !words.isEmpty else { return nil }
        if words[0].lowercased() == "bearer" { words.removeFirst() }
        guard words.count == 1 else { return nil }
        return String(words[0])
    }

    // MARK: - Reading the reply

    struct Quota: Decodable {
        let used: Double?
        let limit: Double?
    }

    private struct Reply: Decodable {
        struct Payload: Decodable {
            let used: Double?
            let limit: Double?
            let resetsOn: String?
            let organization: Quota?
        }

        let data: Payload?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let payload = reply.data,
              payload.used != nil
        else { return context.unavailable(.unreadableReply) }

        let resetsAt = ProfileHTTP.date(payload.resetsOn)
        var windows: [UsageWindow] = []
        if let used = fraction(used: payload.used, limit: payload.limit) {
            windows.append(window(id: "gitkraken.personal", kind: .credits, used: used, resetsAt: resetsAt))
        }
        if let used = fraction(used: payload.organization?.used, limit: payload.organization?.limit) {
            windows.append(window(id: "gitkraken.organization", kind: .sharedCredits, used: used, resetsAt: resetsAt))
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, at: now)
    }

    /// Used out of a positive limit. `-1` is "unlimited" and `0` is "no
    /// allowance": neither is a denominator.
    static func fraction(used: Double?, limit: Double?) -> Double? {
        guard let used, used.isFinite, used >= 0, let limit, limit.isFinite, limit > 0 else { return nil }
        return used / limit
    }

    private static func window(id: String, kind: UsageWindow.Kind, used: Double, resetsAt: Date?) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: used,
            // A sort key only: the reply does not state the period.
            windowSeconds: 7 * 86_400,
            resetsAt: resetsAt,
            reportsLength: false,
            isExhausted: used >= 1
        )
    }
}
