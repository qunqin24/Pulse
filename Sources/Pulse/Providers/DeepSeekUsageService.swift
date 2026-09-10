import Foundation

/// DeepSeek's prepaid balance.
///
/// One documented route, `GET https://api.deepseek.com/user/balance`, reached
/// with a key the user pastes into Settings and kept encrypted on this Mac.
/// Unlike most of this directory it is not an undocumented account endpoint
/// borrowed from a product's own UI — it is in DeepSeek's published API
/// reference, alongside chat completions.
///
/// ```json
/// { "is_available": true,
///   "balance_infos": [ { "currency": "CNY", "total_balance": "110.00",
///                        "granted_balance": "10.00",
///                        "topped_up_balance": "100.00" } ] }
/// ```
///
/// **There is no allowance, no window, no reset and no spend history** — not in
/// this reply and not anywhere else in the API. Every other provider Pulse
/// carries reports at least one percentage; this one reports money and stops.
/// So the denominator behind the ring has to come from somewhere, and
/// `DeepSeekBasis` is the enumeration of the only three places it can:
/// something Pulse watched, nothing at all, or a figure the user typed. Which
/// is in force is the user's choice and is stated on the card either way.
///
/// Every figure arrives as a **string**, including the money, and is parsed
/// here so nothing downstream has to know that.
struct DeepSeekUsageService: Sendable {
    let enteredKey: String?
    /// Which denominator to use. The user's choice, defaulting to the measured
    /// one.
    let basis: DeepSeekBasis
    /// What the user calls a full tank, for `.budget`. Nil, zero or negative
    /// leaves that mode with no denominator, which draws the balance alone
    /// rather than a fraction of a number nobody gave.
    let budget: Double?
    /// Which currency the ring follows when the account holds more than one.
    /// Nil takes the first the reply lists that has any money in it.
    let currency: String?

    private static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

    func fetch() async -> ProviderUsage {
        guard let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) else {
            return .unavailable(.deepSeek, reason: .apiKeyMissing)
        }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .unavailable(.deepSeek, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(.deepSeek, reason: .apiKeyRefused)
        case 429: return .unavailable(.deepSeek, reason: .rateLimited)
        default: return .unavailable(.deepSeek, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(.deepSeek, reason: .unreadableReply)
        }

        guard let purse = Self.purse(from: reply, preferring: currency) else {
            return .unavailable(.deepSeek, reason: .noLimitsReported)
        }

        // The mark is advanced on every reading, whichever basis is in force:
        // switching to "since top-up" later should find a peak already there
        // rather than start over from whatever the balance happens to be that
        // afternoon.
        var marks = DeepSeekBaseline.marks()
        let mark = DeepSeekBaseline.advanced(
            marks[purse.currency], seeing: purse.total, at: Date()
        )
        if marks[purse.currency] != mark {
            marks[purse.currency] = mark
            DeepSeekBaseline.store(marks)
        }

        return ProviderUsage(
            account: AccountKey(.deepSeek),
            windows: Self.windows(
                purse: purse, basis: basis, budget: budget, peak: mark.peak,
                since: mark.setAt, isAvailable: reply.isAvailable
            ),
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: Self.balance(purse)
        )
    }

    // MARK: - Reading the reply

    struct Reply: Decodable {
        struct Info: Decodable {
            let currency: String?
            /// Granted plus topped up. Money, as a string.
            let totalBalance: String?
            let grantedBalance: String?
            let toppedUpBalance: String?

            enum CodingKeys: String, CodingKey {
                case currency
                case totalBalance = "total_balance"
                case grantedBalance = "granted_balance"
                case toppedUpBalance = "topped_up_balance"
            }
        }

        /// DeepSeek's own word for whether this account can still make calls.
        let isAvailable: Bool?
        let balanceInfos: [Info]?

        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    /// One currency's money, with the strings turned into numbers.
    struct Purse: Equatable, Sendable {
        let currency: String
        let total: Double
        let granted: Double?
        let toppedUp: Double?
    }

    /// Which currency the ring follows.
    ///
    /// **The reply is an array**, and an account can hold both CNY and USD.
    /// They cannot be added together and Pulse will not pick a "main" one by
    /// comparing figures across currencies — ¥100 against $10 is not a
    /// comparison. So: the user's choice if they made one, else the first
    /// entry with money in it, else the first entry at all. The card lists
    /// every currency regardless of which one the ring follows.
    static func purse(from reply: Reply, preferring currency: String?) -> Purse? {
        let purses = (reply.balanceInfos ?? []).compactMap(purse(from:))
        guard !purses.isEmpty else { return nil }

        if let currency, let chosen = purses.first(where: { $0.currency == currency }) {
            return chosen
        }
        return purses.first(where: { $0.total > 0 }) ?? purses.first
    }

    static func purse(from info: Reply.Info) -> Purse? {
        guard
            let currency = info.currency, !currency.isEmpty,
            let total = money(info.totalBalance)
        else { return nil }

        return Purse(
            currency: currency,
            total: total,
            granted: money(info.grantedBalance),
            toppedUp: money(info.toppedUpBalance)
        )
    }

    /// Money arrives as a string. A field that is absent or unparseable is
    /// **absent**, not zero — the same rule the other services learned the hard
    /// way, because a balance read as zero is a full red ring and a
    /// notification saying the account is spent.
    static func money(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    // MARK: - Mapping

    /// At most one window, because there is at most one denominator.
    ///
    /// `.balanceOnly` produces none at all and the rail shows the money in
    /// place of a percentage. The other two produce a single `.spend` row whose
    /// `scope` names where its denominator came from, because that is the whole
    /// question a reader has about it.
    ///
    /// **No length and no reset**, ever. Prepaid credit does not turn over, so
    /// `reportsLength` is false and the seconds exist only to sort the row.
    static func windows(
        purse: Purse,
        basis: DeepSeekBasis,
        budget: Double?,
        peak: Double,
        since: Date,
        isAvailable: Bool?
    ) -> [UsageWindow] {
        let measured: (fraction: Double, scope: String)? = switch basis {
        case .balanceOnly:
            nil
        case .sinceTopUp:
            DeepSeekBaseline.usedFraction(balance: purse.total, peak: peak)
                .map { ($0, String.localized("since top-up")) }
        case .budget:
            budget.flatMap { budget in
                budget > 0
                    ? (min(max((budget - purse.total) / budget, 0), 1), String.localized("of your budget"))
                    : nil
            }
        }

        guard let measured else { return [] }

        return [
            UsageWindow(
                id: "balance",
                kind: .balance,
                scope: measured.scope,
                usedFraction: measured.fraction,
                windowSeconds: 30 * 86_400,
                resetsAt: nil,
                reportsLength: false,
                // The denominator is Pulse's own observation in one mode and
                // the reader's own figure in the other. Neither is DeepSeek's,
                // and the card says which.
                isEstimated: true,
                // **DeepSeek's own word**, not the arithmetic: `is_available`
                // is the flag it sets when the balance can no longer pay for a
                // call. A budget the reader set low can reach 100% with money
                // still in the account, and that is not the account being spent.
                isExhausted: isAvailable == false
            )
        ]
    }

    /// What is left, in the currency the account is priced in.
    static func balance(_ purse: Purse) -> String {
        purse.total.formatted(
            .currency(code: purse.currency)
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }

    static func storedKey() -> String? { APIKeyStore.key(for: .deepSeek) }
}
