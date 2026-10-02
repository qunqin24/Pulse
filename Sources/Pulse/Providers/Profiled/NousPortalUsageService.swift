// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Nous Portal, Nous Research's subscription for the Hermes inference API: a
/// monthly credit grant, and money bought on top of it.
///
/// **Read with the login Hermes Agent saved, and never renewed.** The portal's
/// account endpoint takes only the OAuth access token Hermes mints — an API key
/// buys inference and is refused there. Hermes keeps that token in
/// `~/.hermes/auth.json` (and a shared copy in `shared/nous_auth.json`). It
/// lives about an hour, and its refresh token is single-use: the portal rotates
/// it on every refresh and revokes the whole session when an old one is
/// replayed. A second client refreshing behind Hermes's back would sign Hermes
/// out, so Pulse only reads the current token and, once it has lapsed, says so
/// without sending it. Any `hermes` command renews it.
///
/// `GET {portal}/api/oauth/account` with the token. The portal is the one Hermes
/// stored only when it is `nousresearch.com` or beneath it, over https;
/// anything else is ignored and the default portal asked instead, so an edited
/// file cannot send the token somewhere else.
///
/// The shape is second-hand — taken from CodexBar's Nous provider and its
/// tests, not from a captured reply — and the fixture in the tests says so.
extension ProviderProfile {
    static let nousPortal = ProviderProfile(
        displayName: "Nous Portal",
        iconResource: "hermesagent",
        credential: .localLogin,
        accessDescription: { .localized("Reads the Nous Portal login Hermes Agent saved in ~/.hermes. No Keychain prompt.") },
        soleRoute: {
            (String.localized("Hermes Agent's login"),
             String.localized("Uses the login Hermes Agent already saved. Pulse never renews it."))
        },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "nous-portal",
        discoveryPaths: [".hermes"],
        fetch: { await NousPortalUsageService.fetch($0) }
    )
}

enum NousPortalUsageService {
    static let defaultPortal = URL(string: "https://portal.nousresearch.com")!

    /// A token this close to its expiry is treated as expired, so a request
    /// never races the portal's clock.
    static let expirySkew: TimeInterval = 60

    static func fetch(
        _ context: ProfileContext,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        now: Date = Date(),
        session: URLSession? = nil
    ) async -> ProviderUsage {
        let login: StoredLogin
        switch storedLogin(home: home, now: now) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let found): login = found
        }

        let url = login.portal.appending(path: "api/oauth/account")
        switch await ProfileHTTP.data(
            for: ProfileHTTP.bearer(url, token: login.token),
            refused: .localLoginExpired,
            session: session
        ) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context, now: now)
        }
    }

    // MARK: - Hermes's saved login

    struct StoredLogin: Equatable {
        let token: String
        let portal: URL
        let expiresAt: Date?
    }

    /// The two files Hermes writes, the per-profile one first.
    static func loginFiles(home: URL) -> [URL] {
        let root = home.appending(path: ".hermes")
        return [root.appending(path: "auth.json"), root.appending(path: "shared/nous_auth.json")]
    }

    /// The first usable login, or why there is none. A token that has lapsed
    /// is not sent: the answer would only be a refusal, and it is already
    /// known.
    static func storedLogin(home: URL, now: Date) -> Result<StoredLogin, ProviderUsage.Unavailability> {
        var sawExpired = false
        for file in loginFiles(home: home) {
            guard let data = try? Data(contentsOf: file), let login = login(from: data) else { continue }
            if let expiresAt = login.expiresAt, expiresAt.timeIntervalSince(now) <= expirySkew {
                sawExpired = true
                continue
            }
            return .success(login)
        }
        return .failure(sawExpired ? .localLoginExpired : .localLoginMissing)
    }

    /// Hermes writes one of three shapes: `providers.nous`, a
    /// `credential_pool.nous` list, or the state object on its own.
    static func login(from data: Data) -> StoredLogin? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let providers = root["providers"] as? [String: Any],
           let nous = providers["nous"] as? [String: Any],
           let login = entry(nous) {
            return login
        }
        // The pool's newest login, as Hermes itself picks it: the one whose
        // token lasts longest.
        if let pool = root["credential_pool"] as? [String: Any],
           let entries = pool["nous"] as? [[String: Any]] {
            let logins = entries.compactMap(entry)
            if let newest = logins.max(by: { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }) {
                return newest
            }
        }
        return entry(root)
    }

    private static func entry(_ state: [String: Any]) -> StoredLogin? {
        guard let token = (state["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }
        return StoredLogin(
            token: token,
            portal: trustedPortal(state["portal_base_url"] as? String) ?? defaultPortal,
            expiresAt: ProfileHTTP.date(state["expires_at"] as? String) ?? jwtExpiry(token)
        )
    }

    /// The portal Hermes stored, only if it is Nous's own and over https.
    static func trustedPortal(_ raw: String?) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        guard let parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased(),
              host == "nousresearch.com" || host.hasSuffix(".nousresearch.com"),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty, parts.query == nil, parts.fragment == nil
        else { return nil }
        return parts.url
    }

    /// The `exp` claim of a JWT, for a login saved without an expiry.
    static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = (claims["exp"] as? NSNumber)?.doubleValue
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: - Reading the reply

    /// A money field: a finite number, or a decimal written as a string.
    /// Missing is nil; anything else is a reply that can't be trusted.
    private enum Amount {
        case missing
        case value(Double)
        case malformed
    }

    private static func amount(_ value: Any?) -> Amount {
        switch value {
        case nil, is NSNull: return .missing
        case let number as NSNumber:
            // JSONSerialization hands booleans over as numbers too.
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return .malformed }
            return .value(number.doubleValue)
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^[+-]?(\d+(\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil,
                  let parsed = Double(trimmed), parsed.isFinite
            else { return .malformed }
            return .value(parsed)
        default: return .malformed
        }
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return context.unavailable(.unreadableReply) }
        if let error = root["error"], !(error is NSNull) { return context.unavailable(.serverError) }

        let subscription = root["subscription"] as? [String: Any] ?? [:]
        let access = root["paid_service_access"] as? [String: Any] ?? [:]

        var malformed = false
        func read(_ value: Any?) -> Double? {
            switch amount(value) {
            case .missing: return nil
            case .value(let number): return number
            case .malformed: malformed = true; return nil
            }
        }
        let monthly = read(subscription["monthly_credits"])
        let remaining = read(subscription["credits_remaining"]) ?? read(access["subscription_credits_remaining"])
        let purchased = read(root["purchased_credits_remaining"]) ?? read(access["purchased_credits_remaining"])
        let total = read(access["total_usable_credits"])
        let rollover = read(subscription["rollover_credits"])

        guard !malformed, [monthly, remaining, purchased, total, rollover].contains(where: { $0 != nil })
        else { return context.unavailable(.unreadableReply) }

        // The month's grant, as the portal states both its size and what is
        // left of it. A plan with no grant — the free tier — draws no ring
        // rather than a zero.
        var windows: [UsageWindow] = []
        if let monthly, monthly > 0, let remaining {
            let used = max(0, monthly - max(0, remaining))
            windows.append(UsageWindow(
                id: "nousportal.monthly",
                kind: .monthly,
                scope: nil,
                usedFraction: used / monthly,
                // A billing cycle, not a stated length: a sort key only.
                windowSeconds: 30 * 86_400,
                resetsAt: ProfileHTTP.date(subscription["current_period_end"] as? String),
                reportsLength: false,
                isExhausted: remaining <= 0
            ))
        }

        // What can still be spent, the grant and top-ups together; the top-ups
        // alone when that is all the portal says.
        let balance = total ?? purchased
        guard !windows.isEmpty || balance != nil else { return context.unavailable(.noLimitsReported) }

        let plan = (subscription["plan"] as? String)?.trimmingCharacters(in: .whitespaces)
        return context.reading(
            windows,
            plan: plan?.isEmpty == false ? plan : nil,
            creditBalance: balance.map(money),
            creditRemaining: balance.map { ProviderUsage.CreditAmount(amount: $0, currency: "USD") },
            at: now
        )
    }

    /// Portal credits are dollars; the portal prices and shows them that way.
    static func money(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }
}
