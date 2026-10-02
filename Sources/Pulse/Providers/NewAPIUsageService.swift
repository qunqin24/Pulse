// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A New API deployment's remaining credit, read with an `sk-` key.
///
/// [New API](https://github.com/QuantumNous/new-api) is the gateway most
/// self-run relays are built on — a fork line going back to one-api — and it
/// answers the **OpenAI-compatible billing routes**, which is what makes it
/// readable at all. The key is the ordinary one already in the reader's client
/// config; there is no separate credential to go and find.
///
/// Three requests, run together. The first two carry the key:
///
/// ```
/// GET {root}/v1/dashboard/billing/subscription   → hard_limit_usd, access_until
/// GET {root}/v1/dashboard/billing/usage          → total_usage
/// GET {root}/api/status                          → quota_display_type   (no key)
/// ```
///
/// ```json
/// { "object": "billing_subscription", "has_payment_method": true,
///   "soft_limit_usd": 25, "hard_limit_usd": 25,
///   "system_hard_limit_usd": 25, "access_until": 0 }
/// { "object": "list", "total_usage": 1234.5 }
/// ```
///
/// ## Two figures, and neither means what its name says
///
/// **`hard_limit_usd` is not a limit.** New API computes it as
/// `remaining + used` — see `controller/billing.go` — so it is everything the
/// key has ever had rather than a ceiling. **`total_usage` is in hundredths**,
/// because OpenAI's own route reported cents and the compatibility is
/// literal. So what Pulse actually reads is:
///
/// ```
/// remaining = hard_limit_usd − total_usage / 100
/// ```
///
/// Both sides are New API's own numbers, so the subtraction is arithmetic on
/// reported figures rather than an inference.
///
/// ## And no percentage is drawn from them
///
/// `used / (remaining + used)` looks like a ring and is not one. Which of two
/// unrelated things that denominator is depends on a **server** setting,
/// `DisplayTokenStatEnabled`, that appears nowhere in the reply:
///
/// - token stats **on** — the figures are the key's own, and a key with a
///   quota set on it really does have that allowance. The fraction would be
///   right.
/// - token stats **off** — the figures are the *account's*, and `used` is
///   lifetime. Somebody who has spent $900 over a year and just topped up
///   $100 would be shown as 90% spent with a full wallet, and every top-up
///   would grow the denominator.
///
/// One reply, two meanings, no way to tell them apart. So this draws the money
/// and no fraction, exactly as a sub2api wallet and DeepSeek's `balanceOnly`
/// do. [Docs/providers/newapi.md](../../../Docs/providers/newapi.md)
///
/// ## The unit is not in the reply either
///
/// The `_usd` in those field names is a lie on most deployments: New API
/// converts into whatever its operator set as the display type and keeps the
/// OpenAI field name. A CNY site reports yuan in `hard_limit_usd`; a TOKENS
/// site reports a token count. `GET /api/status` is public, needs no key, and
/// carries `quota_display_type` — so it is asked, and a site whose unit is not
/// a currency reports **no money at all** rather than tokens wearing a dollar
/// sign.
struct NewAPIUsageService: Sendable {
    let enteredKey: String?
    /// The deployment's address, as the reader typed it.
    let address: String?

    /// What New API substitutes for the amount when a key has
    /// `UnlimitedQuota` set — a literal in `controller/billing.go` rather than
    /// a flag in the reply, which is why it has to be recognised by value.
    static let unlimitedSentinel: Double = 100_000_000

    /// People paste a gateway's root, and people paste the base URL out of
    /// their client's config — which for an OpenAI-compatible endpoint ends in
    /// `/v1`.
    private static let typedSuffixes = ["/v1"]

    /// Every reading is stamped with the deployment and key it came from, so a
    /// cached reading from another server or account never stands in for this
    /// one's failure —
    /// see `ProviderUsage.requiresScopeMatch`. Moving from one deployment to
    /// another used to leave the old server's balance on the ring, marked
    /// stale, for up to a day whenever the new one refused.
    func fetch() async -> ProviderUsage {
        var usage = await read()
        usage.sourceScope = GatewayAddress.scope(of: address, key: enteredKey)
        return usage
    }

    private func read() async -> ProviderUsage {
        guard let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) else {
            return .unavailable(.newAPI, reason: .apiKeyMissing)
        }

        let typed = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            return .unavailable(.newAPI, reason: .serverAddressMissing)
        }
        guard
            let subscriptionURL = Self.url(from: typed, path: "/v1/dashboard/billing/subscription"),
            let usageURL = Self.url(from: typed, path: "/v1/dashboard/billing/usage"),
            let statusURL = Self.url(from: typed, path: "/api/status")
        else {
            return .unavailable(.newAPI, reason: .serverAddressRefused)
        }

        async let subscriptionReply = Self.get(Subscription.self, from: subscriptionURL, key: key)
        async let usageReply = Self.get(Usage.self, from: usageURL, key: key)
        // **No key on this one.** It is the site's public configuration and
        // nothing about it is scoped to an account, so there is no reason to
        // hand it a credential.
        async let statusReply = Self.get(Status.self, from: statusURL, key: nil)

        let (subscription, usage, status) = await (subscriptionReply, usageReply, statusReply)

        guard case .reply(let subscription) = subscription else {
            return .unavailable(.newAPI, reason: subscription.failure ?? .unreadableReply)
        }
        // A key with no ceiling at all. A complete answer, not a fault — and
        // `remaining` computed against the sentinel would be a hundred million
        // of something.
        if Self.isUnlimited(subscription) {
            return .unavailable(.newAPI, reason: .noLimitsReported)
        }
        guard case .reply(let usage) = usage else {
            return .unavailable(.newAPI, reason: usage.failure ?? .unreadableReply)
        }

        // A status route that did not answer leaves the unit unknown. That is
        // not a reason to fail the reading, it is a reason not to put a
        // currency symbol on a number — so the reading reports nothing rather
        // than guessing dollars.
        guard
            let remaining = Self.remaining(subscription: subscription, usage: usage),
            let currency = Self.currency(of: status.reply)
        else {
            return .unavailable(.newAPI, reason: .noLimitsReported)
        }

        let wallet = ProviderUsage.CreditAmount(amount: remaining, currency: currency)
        return ProviderUsage(
            account: AccountKey(.newAPI),
            // **None, ever.** See the note above: the only fraction available
            // means two different things depending on a setting the reply does
            // not carry.
            windows: [],
            observedAt: Date(),
            state: .live,
            plan: status.reply?.data?.systemName.flatMap { $0.isEmpty ? nil : $0 },
            creditBalance: Self.money(wallet),
            creditRemaining: wallet
        )
    }

    // MARK: - The address

    /// Shared with the other self-hosted gateway — https except on a private
    /// network, no user info, no fragment, no query. See `GatewayAddress`.
    static func url(from typed: String, path: String) -> URL? {
        GatewayAddress.url(from: typed, path: path, trimming: typedSuffixes)
    }

    // MARK: - The requests

    /// One route's outcome.
    ///
    /// Its own type rather than `Result`, whose failure has to be an `Error` —
    /// and `Unavailability` is deliberately not one: it is a thing to display,
    /// not a thing to throw.
    enum Fetched<Reply: Sendable>: Sendable {
        case reply(Reply)
        case failed(ProviderUsage.Unavailability)

        var reply: Reply? {
            if case .reply(let reply) = self { return reply }
            return nil
        }

        var failure: ProviderUsage.Unavailability? {
            if case .failed(let reason) = self { return reason }
            return nil
        }
    }

    private static func get<Reply: Decodable & Sendable>(
        _ type: Reply.Type, from url: URL, key: String?
    ) async -> Fetched<Reply> {
        var request = URLRequest(url: url)
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await NetworkSession.shared.data(for: request) else {
            return .failed(.unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .failed(.apiKeyRefused)
        case 429: return .failed(.rateLimited)
        default: return .failed(.serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .failed(.unreadableReply)
        }
        return .reply(reply)
    }

    // MARK: - Reading the replies

    struct Subscription: Decodable {
        /// `remaining + used`, in the site's display unit. **Not a ceiling**,
        /// whatever the name says.
        let hardLimitUSD: Double?
        let softLimitUSD: Double?
        let systemHardLimitUSD: Double?
        /// The key's expiry as unix seconds, or 0 for none.
        let accessUntil: Double?

        enum CodingKeys: String, CodingKey {
            case hardLimitUSD = "hard_limit_usd"
            case softLimitUSD = "soft_limit_usd"
            case systemHardLimitUSD = "system_hard_limit_usd"
            case accessUntil = "access_until"
        }
    }

    struct Usage: Decodable {
        /// Used, in **hundredths** of the display unit — OpenAI's route
        /// reported cents and the compatibility is literal.
        let totalUsage: Double?

        enum CodingKeys: String, CodingKey {
            case totalUsage = "total_usage"
        }
    }

    /// The site's public configuration. No key, nothing account-scoped in it.
    struct Status: Decodable {
        struct Payload: Decodable {
            /// `USD`, `CNY`, `TOKENS` or `CUSTOM`.
            let quotaDisplayType: String?
            /// What older builds and one-api forks carry instead: a bool that
            /// only says whether the figures are money at all.
            let displayInCurrency: Bool?
            let systemName: String?

            enum CodingKeys: String, CodingKey {
                case quotaDisplayType = "quota_display_type"
                case displayInCurrency = "display_in_currency"
                case systemName = "system_name"
            }
        }

        let success: Bool?
        let data: Payload?
    }

    // MARK: - Mapping

    /// What is left: New API's own total, less New API's own usage.
    ///
    /// **Hundredths, not units.** `total_usage` is the amount times a hundred,
    /// and reading it as units makes a wallet look a hundred times emptier
    /// than it is — which is a notification announcing an account as spent.
    static func remaining(subscription: Subscription, usage: Usage) -> Double? {
        guard
            let total = subscription.hardLimitUSD, total.isFinite,
            let used = usage.totalUsage, used.isFinite
        else { return nil }
        return total - used / 100
    }

    /// Whether this key has no ceiling.
    ///
    /// New API substitutes a literal hundred million for the amount rather
    /// than setting a flag, so this is recognised by value. All three fields
    /// are written from the same variable, so agreement across them is what
    /// separates the sentinel from a deployment that genuinely sold somebody
    /// exactly that much.
    static func isUnlimited(_ subscription: Subscription) -> Bool {
        [subscription.hardLimitUSD, subscription.softLimitUSD, subscription.systemHardLimitUSD]
            .allSatisfy { $0 == unlimitedSentinel }
    }

    /// What the figures are denominated in, or nil when it cannot be said.
    ///
    /// **Nil rather than a default.** The `_usd` in the field names is not
    /// evidence: New API converts into the operator's chosen display type and
    /// keeps OpenAI's field name, so a CNY site reports yuan in
    /// `hard_limit_usd`. A site counting tokens or a custom unit is not money
    /// at all and reports none rather than tokens wearing a dollar sign.
    ///
    /// The older `display_in_currency` is read only when the newer field is
    /// absent — it distinguishes money from tokens and nothing more, so it can
    /// only ever answer USD, which is what the builds that carried it assumed.
    static func currency(of status: Status?) -> String? {
        guard let payload = status?.data else { return nil }

        if let type = payload.quotaDisplayType?.trimmingCharacters(in: .whitespaces).uppercased(),
           !type.isEmpty {
            switch type {
            case "USD": return "USD"
            case "CNY": return "CNY"
            // Tokens and an operator's own unit are not currencies. Neither is
            // anything this does not recognise: a new display type added
            // upstream must not be quietly priced in dollars.
            default: return nil
            }
        }

        guard let inCurrency = payload.displayInCurrency else { return nil }
        return inCurrency ? "USD" : nil
    }

    static func money(_ wallet: ProviderUsage.CreditAmount) -> String {
        wallet.amount.formatted(
            .currency(code: wallet.currency)
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }

    static func storedKey() -> String? { APIKeyStore.key(for: .newAPI) }
}
