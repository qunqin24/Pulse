// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// ElevenLabs: the subscription's character credits for the current billing
/// period — how many have been used, out of how many, and when they reset.
///
/// Read with a key the user pastes, from ElevenLabs' own subscription route:
/// `GET https://api.elevenlabs.io/v1/user/subscription`, key in `xi-api-key`.
/// The key needs the `user_read` permission. The shape is second-hand — taken
/// from CodexBar's ElevenLabs plugin and its docs, not from a captured reply
/// — and the fixture in the tests says so.
///
/// **Credits, not a month.** The period follows the subscription's billing
/// date and the reply states only when it ends, so the allowance claims no
/// length. Voice slots are left off: they are a count of voices kept, not an
/// allowance spent over time, and no kind of window here reads as one.
extension ProviderProfile {
    static let elevenLabs = ProviderProfile(
        displayName: "ElevenLabs",
        iconResource: "elevenlabs",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From elevenlabs.io, with the user_read permission. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        setupSlug: "elevenlabs",
        fetch: { await ElevenLabsUsageService.fetch($0) }
    )
}

enum ElevenLabsUsageService {
    static let endpoint = URL(string: "https://api.elevenlabs.io/v1/user/subscription")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        switch await ProfileHTTP.data(for: request(key: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    /// ElevenLabs takes its key in a header of its own rather than as a bearer.
    static func request(key: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    // MARK: - Reading the reply

    private struct Reply: Decodable {
        let tier: String?
        let characterCount: Double?
        let characterLimit: Double?
        let nextCharacterCountResetUnix: Double?

        enum CodingKeys: String, CodingKey {
            case tier
            case characterCount = "character_count"
            case characterLimit = "character_limit"
            case nextCharacterCountResetUnix = "next_character_count_reset_unix"
        }
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return context.unavailable(.unreadableReply)
        }

        var windows: [UsageWindow] = []
        // A limit of zero is no allowance at all, and is left off rather than
        // drawn as an empty ring.
        if let used = reply.characterCount, used.isFinite, used >= 0,
           let limit = reply.characterLimit, limit.isFinite, limit > 0 {
            windows.append(UsageWindow(
                id: "elevenlabs.characters",
                kind: .credits,
                scope: nil,
                usedFraction: used / limit,
                // A sort key only: the billing period's length is not stated.
                windowSeconds: 30 * 86_400,
                resetsAt: reply.nextCharacterCountResetUnix
                    .flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
                reportsLength: false,
                isExhausted: used >= limit
            ))
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: plan(reply.tier), at: now)
    }

    /// "creator" → "Creator", "growing_business" → "Growing Business". The
    /// tier is ElevenLabs' own plan name, so it is left untranslated.
    static func plan(_ tier: String?) -> String? {
        guard let tier = tier?.trimmingCharacters(in: .whitespacesAndNewlines), !tier.isEmpty else { return nil }
        return tier.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
