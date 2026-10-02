// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Kilo Code: the account's credit balance, and the Kilo Pass allowance for
/// the current billing period when the account has a pass.
///
/// Read from the tRPC routes Kilo's own dashboard calls, in one batched GET:
/// `https://app.kilo.ai/api/trpc/user.getCreditBlocks,kiloPass.getState`. The
/// key is one the user pastes, or failing that the login the Kilo CLI saved in
/// `~/.local/share/kilo/auth.json`. The shape is second-hand — taken from
/// CodexBar's Kilo provider and its tests, not from a captured reply — and the
/// fixture in the tests says so.
///
/// **What is not read.** CodexBar also draws a ring from the credit blocks —
/// the sum of what each block started with against what is left of them —
/// and hunts a dozen alternative key names for each figure. The blocks start
/// and expire at different times, so their sum is not an allowance anyone
/// sells; the balance Kilo reports is shown as a balance instead. Only the
/// field names seen in a Kilo reply are read. Organizations, which CodexBar
/// can switch between, are not: the personal account is what the key reads.
extension ProviderProfile {
    static let kiloCode = ProviderProfile(
        displayName: "Kilo Code",
        iconResource: "kilocode",
        credential: .apiKey(optional: true),
        accessDescription: {
            .localized("Uses a key entered in Settings, or reads ~/.local/share/kilo/auth.json. No Keychain prompt.")
        },
        keySubtitle: {
            .localized("From app.kilo.ai. Optional — Pulse can use the login the Kilo CLI saved. Stored encrypted on this Mac.")
        },
        reportsSpendableBalance: true,
        setupSlug: "kilo-code",
        discoveryPaths: [
            ".local/share/kilo",
            "Library/Application Support/Code/User/globalStorage/kilocode.kilo-code",
        ],
        fetch: { await KiloCodeUsageService.fetch($0) }
    )
}

enum KiloCodeUsageService {
    /// The two procedures, batched, each with no input.
    static let endpoint: URL = {
        var components = URLComponents(string: "https://app.kilo.ai/api/trpc/user.getCreditBlocks,kiloPass.getState")!
        components.queryItems = [
            URLQueryItem(name: "batch", value: "1"),
            URLQueryItem(name: "input", value: #"{"0":{"json":null},"1":{"json":null}}"#),
        ]
        return components.url!
    }()

    static func fetch(
        _ context: ProfileContext,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        session: URLSession? = nil
    ) async -> ProviderUsage {
        // A pasted key first; the CLI's login only when there is none. Each
        // is refused in its own words, because the remedy differs.
        let token: String
        let refused: ProviderUsage.Unavailability
        if let key = context.trimmedCredential {
            (token, refused) = (key, .apiKeyRefused)
        } else {
            let file = home.appendingPathComponent(".local/share/kilo/auth.json")
            guard let data = try? Data(contentsOf: file) else { return context.unavailable(.apiKeyMissing) }
            guard let saved = savedToken(from: data) else { return context.unavailable(.localLoginMissing) }
            (token, refused) = (saved, .localLoginExpired)
        }

        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(endpoint, token: token), refused: refused, session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context, refused: refused)
        }
    }

    /// `kilo.access` in the CLI's `auth.json`.
    static func savedToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = ((json["kilo"] as? [String: Any])?["access"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }
        return token
    }

    // MARK: - Reading the reply

    /// The tiers Kilo sells, by the names its own pricing uses. Any other tier
    /// is still a Kilo Pass, and is called only that.
    private static let tiers = ["tier_19": "Starter", "tier_49": "Pro", "tier_199": "Expert"]

    static func reading(
        from data: Data,
        context: ProfileContext,
        refused: ProviderUsage.Unavailability = .apiKeyRefused,
        now: Date = Date()
    ) -> ProviderUsage {
        guard let entries = batch(from: data),
              entries.contains(where: { $0?["result"] != nil || $0?["error"] != nil })
        else { return context.unavailable(.unreadableReply) }
        // A procedure answering with an error: refused if it says so, and
        // otherwise nothing Pulse can read. Each carries its own.
        for entry in entries.compactMap({ $0 }) {
            guard let error = entry["error"] else { continue }
            let text = String(describing: error).lowercased()
            return context.unavailable(
                text.contains("unauthorized") || text.contains("forbidden") ? refused : .unreadableReply
            )
        }

        let blocks = entries[0].flatMap(payload)
        let pass = entries[1].flatMap(payload)

        let balance = blocks.flatMap(Self.balance)
        let subscription = pass?["subscription"] as? [String: Any]
        let windows = subscription.flatMap(Self.window).map { [$0] } ?? []

        guard !windows.isEmpty || balance != nil else { return context.unavailable(.noLimitsReported) }

        let plan = subscription.map { (($0["tier"] as? String).flatMap { tiers[$0] }) ?? "Kilo Pass" }
        let wallet = balance.map { ProviderUsage.CreditAmount(amount: $0, currency: "USD") }
        return context.reading(
            windows,
            plan: plan,
            creditBalance: wallet.map(money),
            creditRemaining: wallet,
            at: now
        )
    }

    /// The batch's replies in procedure order, as a JSON array or as an
    /// object keyed by index. A procedure with no reply is nil.
    private static func batch(from data: Data) -> [[String: Any]?]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let array = root as? [Any] {
            return (0..<2).map { $0 < array.count ? array[$0] as? [String: Any] : nil }
        }
        if let object = root as? [String: Any] {
            return (0..<2).map { object[String($0)] as? [String: Any] }
        }
        return nil
    }

    /// `result.data`, or `result.data.json` where the router wraps it.
    private static func payload(_ entry: [String: Any]) -> [String: Any]? {
        guard let data = (entry["result"] as? [String: Any])?["data"] as? [String: Any] else { return nil }
        if data.keys.contains("json") { return data["json"] as? [String: Any] }
        return data
    }

    /// In micro-dollars on the wire. The account's total where Kilo states
    /// it; otherwise what is left in each block, added up.
    private static func balance(_ blocks: [String: Any]) -> Double? {
        let micro: Double?
        if let total = number(blocks["totalBalance_mUsd"]) {
            micro = total
        } else {
            let left = (blocks["creditBlocks"] as? [[String: Any]] ?? []).compactMap { number($0["balance_mUsd"]) }
            micro = left.isEmpty ? nil : left.reduce(0, +)
        }
        guard let micro, micro.isFinite, micro >= 0 else { return nil }
        return micro / 1_000_000
    }

    /// The pass's period: what has been used of the base credits and the
    /// bonus on top, both as Kilo reports them. A period with no stated size
    /// draws nothing. It resets when the pass bills again; how long that is
    /// is not stated, so the thirty days are a sort key only.
    private static func window(_ subscription: [String: Any]) -> UsageWindow? {
        guard let used = number(subscription["currentPeriodUsageUsd"]), used.isFinite, used >= 0,
              let base = number(subscription["currentPeriodBaseCreditsUsd"]), base.isFinite, base >= 0
        else { return nil }
        let bonus = number(subscription["currentPeriodBonusCreditsUsd"]).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        let size = base + bonus
        guard size > 0 else { return nil }
        return UsageWindow(
            id: "kilocode.pass",
            kind: .credits,
            scope: nil,
            usedFraction: used / size,
            windowSeconds: 30 * 86_400,
            resetsAt: ProfileHTTP.date(subscription["nextBillingAt"] as? String),
            reportsLength: false,
            isExhausted: used >= size
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        // A JSON `true` decodes as an NSNumber too, and is not a figure.
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            number.doubleValue
        case let text as String:
            Double(text.trimmingCharacters(in: .whitespaces))
        default:
            nil
        }
    }

    static func money(_ wallet: ProviderUsage.CreditAmount) -> String {
        wallet.amount.formatted(
            .currency(code: wallet.currency)
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }
}
