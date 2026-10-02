// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Venice: the balance its API spends from — US dollars, or DIEM, the token
/// Venice's stakers are allotted each epoch.
///
/// Read with an API key the user pastes, from
/// `GET https://api.venice.ai/api/v1/billing/balance`. The shape is second-hand
/// — taken from CodexBar's Venice plugin and its tests, not from a captured
/// reply — and the fixture in the tests says so.
///
/// **Only the balance, never a percentage.** The reply's `canConsume` is a
/// yes-or-no about whether the next call will go through; CodexBar draws it as
/// 100% or 0%, which is a health flag wearing a percentage's clothes. Pulse
/// shows the balance the reply states and draws no ring. Neither is the DIEM
/// epoch allocation drawn: what is left of it reads as a balance like the
/// dollars do.
extension ProviderProfile {
    static let venice = ProviderProfile(
        displayName: "Venice",
        billing: .api,
        iconResource: "venice",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From venice.ai's API settings. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "venice",
        fetch: { await VeniceUsageService.fetch($0) }
    )
}

enum VeniceUsageService {
    static let endpoint = URL(string: "https://api.venice.ai/api/v1/billing/balance")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(endpoint, token: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - Reading the reply

    private enum Figure {
        case missing
        case value(Double)
        case malformed
    }

    /// A number, or one written as a string; null or empty is missing.
    private static func figure(_ value: Any?) -> Figure {
        switch value {
        case nil, is NSNull: return .missing
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            return number.doubleValue.isFinite ? .value(number.doubleValue) : .malformed
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return .missing }
            guard let parsed = Double(trimmed), parsed.isFinite else { return .malformed }
            return .value(parsed)
        default: return .malformed
        }
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let canConsume = root["canConsume"] as? NSNumber, CFGetTypeID(canConsume) == CFBooleanGetTypeID(),
              let balances = root["balances"] as? [String: Any]
        else { return context.unavailable(.unreadableReply) }

        let currency = root["consumptionCurrency"]
        guard currency == nil || currency is NSNull || currency is String
        else { return context.unavailable(.unreadableReply) }

        let usd: Double?
        let diem: Double?
        switch (figure(balances["usd"]), figure(balances["diem"])) {
        case (.malformed, _), (_, .malformed):
            return context.unavailable(.unreadableReply)
        case let (dollarFigure, diemFigure):
            if case .value(let value) = dollarFigure { usd = value } else { usd = nil }
            if case .value(let value) = diemFigure { diem = value } else { diem = nil }
        }

        // The balance the account spends from, as the reply names it; failing
        // a name, dollars before DIEM.
        let spendsDIEM = (currency as? String)?.uppercased() == "DIEM"
        if spendsDIEM, let diem {
            return context.reading([], creditBalance: tokens(diem), at: now)
        }
        if let usd {
            return context.reading(
                [],
                creditBalance: money(usd),
                creditRemaining: ProviderUsage.CreditAmount(amount: usd, currency: "USD"),
                at: now
            )
        }
        if let diem {
            return context.reading([], creditBalance: tokens(diem), at: now)
        }
        return context.unavailable(.noLimitsReported)
    }

    static func money(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }

    /// DIEM is a token's symbol, the same in every language, so it follows
    /// the figure untranslated.
    static func tokens(_ amount: Double) -> String {
        amount.formatted(.number.precision(.fractionLength(2)).locale(LocalizationSource.locale)) + " DIEM"
    }
}
