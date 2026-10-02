// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Zed, the editor: its edit-prediction allowance and its token spend against
/// the spending limit the account set.
///
/// **Read with a browser session, not the editor's login.** The editor keeps
/// its credential in the macOS Keychain, and reading that item is a Keychain
/// prompt Pulse does not ask for. zed.dev's own billing page has a signed-in
/// session instead, and that is what is read — imported on request, kept to
/// the `zed.session` cookie. Signing in only inside the editor does not create
/// one; signing in at zed.dev in a browser does.
///
/// `GET https://cloud.zed.dev/frontend/billing/usage` with the cookie. The
/// page's own frontend call, undocumented. The shape is second-hand — taken
/// from CodexBar's Zed plugin and its tests, not from a captured reply — and
/// the fixture in the tests says so.
///
/// A limit the account doesn't have is left off: unlimited predictions, or no
/// spending limit, draw nothing rather than a ring at zero.
extension ProviderProfile {
    static let zed = ProviderProfile(
        displayName: "Zed",
        iconResource: "extension",
        credential: .sessionCookie(host: "zed.dev", cookies: ["zed.session"]),
        accessDescription: { .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.") },
        setupSlug: "zed",
        discoveryPaths: ["/Applications/Zed.app", ".config/zed"],
        fetch: { await ZedUsageService.fetch($0) }
    )
}

enum ZedUsageService {
    static let endpoint = URL(string: "https://cloud.zed.dev/frontend/billing/usage")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential else { return context.unavailable(.sessionMissing) }
        var request = URLRequest(url: endpoint)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        switch await ProfileHTTP.data(for: request, refused: .sessionExpired, session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - Reading the reply

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["current_usage"] as? [String: Any]
        else { return context.unavailable(.unreadableReply) }

        var windows: [UsageWindow] = []

        // So many predictions in the account's allowance, and so many used.
        // The reply names no period; Zed's plans count them by the month, so
        // the length is a sort key and not a claim.
        if let predictions = usage["edit_predictions"] as? [String: Any],
           let used = count(predictions["used"]),
           let limit = predictionLimit(predictions["limit"]), limit > 0 {
            windows.append(UsageWindow(
                id: "zed.editPredictions",
                kind: .monthly,
                scope: "Edit Predictions",
                usedFraction: used / limit,
                windowSeconds: 30 * 86_400,
                resetsAt: nil,
                reportsLength: false,
                isExhausted: used >= limit
            ))
        }

        // Token spend against the spending limit, both in cents. No limit
        // set is spend with nothing to measure it against, and is left off.
        if let spend = usage["token_spend"] as? [String: Any],
           let spent = count(spend["spend_in_cents"]),
           let limit = count(spend["limit_in_cents"]), limit > 0 {
            windows.append(UsageWindow(
                id: "zed.tokenSpend",
                kind: .spend,
                scope: nil,
                usedFraction: spent / limit,
                windowSeconds: 30 * 86_400,
                resetsAt: nil,
                reportsLength: false,
                isExhausted: spent >= limit
            ))
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: (root["plan"] as? String).flatMap(planName), at: now)
    }

    /// A reported figure: a finite number, not negative. Anything else is
    /// left off rather than read as zero.
    private static func count(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let figure = number.doubleValue
        return figure.isFinite && figure >= 0 ? figure : nil
    }

    /// A number, or `{ "limited": n }`. `"unlimited"` and null are no limit.
    private static func predictionLimit(_ value: Any?) -> Double? {
        if let limited = value as? [String: Any] { return count(limited["limited"]) }
        return count(value)
    }

    /// `zed_pro_trial` → "Zed Pro Trial". A product's own name, so it is
    /// not translated.
    static func planName(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: { $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
