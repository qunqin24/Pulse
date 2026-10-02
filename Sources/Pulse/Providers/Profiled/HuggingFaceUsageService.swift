// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Hugging Face: the account's ZeroGPU quota — GPU time on ZeroGPU Spaces,
/// counted in seconds and reported with how much is left and when it resets.
///
/// Read with an access token: one the user pastes, or failing that the one
/// `hf auth login` saved in `~/.cache/huggingface/token`. Any token that can
/// read the account will do.
///
/// `GET https://huggingface.co/api/spaces/zero-gpu/quota` — a documented Hub
/// endpoint. The shape is second-hand — taken from CodexBar's Hugging Face
/// plugin and its tests, not from a captured reply — and the fixture in the
/// tests says so.
///
/// **What is left out, and why.** Inference Providers' month-to-date charges
/// (`/api/settings/billing/usage-v2`) are spend: the reply states no allowance,
/// and its "included" amount and spending limit do not make one Pulse could
/// draw without deciding what the limit is measured against. The prepaid
/// credit wallet is only on the website, behind a browser session and an
/// identity check against the token; one credential cannot be both.
extension ProviderProfile {
    static let huggingFace = ProviderProfile(
        displayName: "Hugging Face",
        iconResource: "huggingface",
        credential: .apiKey(optional: true),
        accessDescription: { .localized("Uses a token entered in Settings, or reads the one hf auth login saved in ~/.cache/huggingface. No Keychain prompt.") },
        keySubtitle: { .localized("From huggingface.co/settings/tokens. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        brandColor: 0xFFD21E,
        setupSlug: "hugging-face",
        discoveryPaths: [".cache/huggingface/token"],
        fetch: { await HuggingFaceUsageService.fetch($0) }
    )
}

enum HuggingFaceUsageService {
    static let endpoint = URL(string: "https://huggingface.co/api/spaces/zero-gpu/quota")!

    static func fetch(
        _ context: ProfileContext,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        session: URLSession? = nil
    ) async -> ProviderUsage {
        // The pasted token first: it is the one somebody chose on purpose.
        let token: String
        let refused: ProviderUsage.Unavailability
        if let pasted = context.trimmedCredential {
            (token, refused) = (pasted, .apiKeyRefused)
        } else if let saved = savedToken(home: home) {
            (token, refused) = (saved, .localLoginExpired)
        } else {
            return context.unavailable(.apiKeyMissing)
        }

        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(endpoint, token: token), refused: refused, session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    /// The token `hf auth login` wrote: the file's first line. Only read,
    /// never written.
    static func savedToken(home: URL) -> String? {
        let file = home.appending(path: ".cache/huggingface/token")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first
        else { return nil }
        var token = line.trimmingCharacters(in: .whitespaces)
        if token.count >= 2, let first = token.first, first == token.last, first == "\"" || first == "'" {
            token = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return token.isEmpty ? nil : token
    }

    // MARK: - Reading the reply

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return context.unavailable(.unreadableReply) }

        // `base` is the quota and `current` what is left of it, in seconds of
        // GPU time. An account with no quota — or figures that aren't ones —
        // draws nothing rather than a zero.
        guard let base = seconds(root["base"]), base > 0,
              let current = seconds(root["current"])
        else { return context.unavailable(.noLimitsReported) }

        let window = UsageWindow(
            id: "huggingface.zeroGPU",
            kind: .daily,
            scope: "ZeroGPU",
            usedFraction: max(0, base - current) / base,
            // Hugging Face describes the quota as daily; the reply states only
            // when it resets, so the length is a sort key and not a claim.
            windowSeconds: 86_400,
            resetsAt: date(root["resetsAt"]),
            reportsLength: false,
            isExhausted: current <= 0
        )
        return context.reading([window], at: now)
    }

    private static func seconds(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let figure = number.doubleValue
        return figure.isFinite && figure >= 0 ? figure : nil
    }

    /// An ISO 8601 string, or seconds since 1970 within a sane range.
    private static func date(_ value: Any?) -> Date? {
        if let text = value as? String { return ProfileHTTP.date(text) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let seconds = number.doubleValue
        guard seconds.isFinite, seconds > 0, seconds < 64_092_211_200 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
