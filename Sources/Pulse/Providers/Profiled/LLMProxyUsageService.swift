// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// LLM API Key Proxy, a self-hosted gateway: the quota groups it reports for
/// the upstream accounts behind it, each as a percentage left and a reset.
///
/// Read with the key the user pastes and the proxy address they enter, from
/// the proxy's own statistics route: `GET <address>/v1/quota-stats`, bearer
/// key. The key goes to that address and nowhere else. The shape is
/// second-hand — taken from CodexBar's LLM Proxy plugin and its tests, not
/// from a captured reply — and the fixture in the tests says so.
///
/// **Each group is its own row.** CodexBar folds every group into one
/// figure — the lowest remainder anywhere — which is a number no upstream
/// account reported. Here each group keeps its own, scoped by the upstream's
/// name and the group's. None states its length, so each is an allowance
/// with a reset and no claimed period.
///
/// Request counts, token counts and the approximate cost are spend with no
/// limit behind them, which Pulse has nowhere to show yet, and are left off.
extension ProviderProfile {
    static let llmProxy = ProviderProfile(
        displayName: "LLM API Key Proxy",
        billing: .api,
        iconResource: "extension",
        credential: .keyAndAddress,
        accessDescription: {
            .localized("Sends the key you enter only to the server address you enter. No Keychain prompt.")
        },
        keySubtitle: { .localized("The same key your AI client uses for this gateway. Sent only to the address above. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        requiresScopeMatch: true,
        setupSlug: "llm-proxy",
        fetch: { await LLMProxyUsageService.fetch($0) }
    )
}

enum LLMProxyUsageService {
    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        var usage = await read(context, session: session)
        // Stamped with the proxy and key, so a reading from one never
        // stands in for another's failure.
        usage.sourceScope = GatewayAddress.scope(of: context.serverAddress, key: context.trimmedCredential)
        return usage
    }

    private static func read(_ context: ProfileContext, session: URLSession?) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        let typed = (context.serverAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return context.unavailable(.serverAddressMissing) }
        // The service root or its `/v1` base both lead to `/v1/quota-stats`.
        guard let url = GatewayAddress.url(from: typed, path: "/v1/quota-stats", trimming: ["/v1"]) else {
            return context.unavailable(.serverAddressRefused)
        }
        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(url, token: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - Reading the reply

    struct Group: Decodable {
        let remainingPercent: Double?
        let resetTime: String?

        enum CodingKeys: String, CodingKey {
            case remainingPercent = "remaining_percent"
            case resetTime = "reset_time"
        }
    }

    /// `quota_groups` comes keyed by the group's name or as a plain list.
    private struct Groups: Decodable {
        let named: [(name: String?, group: Group)]

        init(from decoder: any Decoder) throws {
            if let keyed = try? decoder.singleValueContainer().decode([String: Group].self) {
                named = keyed.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            } else {
                named = try decoder.singleValueContainer().decode([Group].self).map { (nil, $0) }
            }
        }
    }

    private struct Upstream: Decodable {
        let quotaGroups: Groups?

        enum CodingKeys: String, CodingKey { case quotaGroups = "quota_groups" }

        /// A malformed `quota_groups` is left out rather than failing the
        /// whole reply, as CodexBar does.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            quotaGroups = try? container.decodeIfPresent(Groups.self, forKey: .quotaGroups)
        }
    }

    private struct Reply: Decodable { let providers: [String: Upstream] }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return context.unavailable(.unreadableReply)
        }

        var windows: [UsageWindow] = []
        for (upstream, stats) in reply.providers.sorted(by: { $0.key < $1.key }) {
            for (index, entry) in (stats.quotaGroups?.named ?? []).enumerated() {
                guard let left = entry.group.remainingPercent, left.isFinite, (0...100).contains(left) else { continue }
                // Upstream and group names are the proxy's own identifiers —
                // "gemini_cli", "claude-sonnet" — so they stay untranslated.
                let name = entry.name.flatMap { $0 == "default" ? nil : $0 }
                windows.append(UsageWindow(
                    id: "llmproxy.\(upstream).\(entry.name ?? String(index))",
                    kind: .credits,
                    scope: [upstream, name].compactMap { $0 }.joined(separator: " · "),
                    usedFraction: (100 - left) / 100,
                    // A sort key only: no group states its period.
                    windowSeconds: 86_400,
                    resetsAt: ProfileHTTP.date(entry.group.resetTime),
                    reportsLength: false,
                    isExhausted: left <= 0
                ))
            }
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, at: now)
    }
}
