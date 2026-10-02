// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// LongCat's API platform: the account's token allowance, and the fuel packs
/// (加油包) bought on top of it, each reported as tokens used or left out of a
/// stated total.
///
/// Read with a browser session from `longcat.chat`, from the routes the
/// platform's usage page calls: `GET /api/v1/user-current` to prove the
/// session, `POST /api/pay/quota/metering/token-packs/summary` for an active
/// token pack, `GET /api/lc-platform/v1/tokenUsage` for the allowance when
/// there is no such pack, and `GET /api/lc-platform/v1/pending-fuel-packages`
/// for the fuel packs. The shape is second-hand — taken from CodexBar's
/// LongCat provider and its tests, not from a captured reply.
///
/// **Only figures the platform states.** The allowance needs a total and
/// either the tokens used or the tokens left; the fuel packs need their total
/// and at least one pack's tokens left. CodexBar fills a missing used figure
/// with zero and a missing remainder with the whole pack, which draws a full
/// ring nobody reported; here that row is left off. Neither states a length
/// or a reset, so neither claims one: the allowance is a credit allowance, the
/// packs a top-up whose soonest expiry is shown as an expiry, not a reset.
extension ProviderProfile {
    static let longCat = ProviderProfile(
        displayName: "LongCat",
        iconResource: "longcat",
        credential: .sessionCookie(host: LongCatUsageService.host, cookies: LongCatUsageService.cookies),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        setupSlug: "longcat",
        fetch: { await LongCatUsageService.fetch($0) }
    )
}

enum LongCatUsageService {
    static let host = "longcat.chat"
    /// The Meituan passport token first, which has to be there, and the
    /// account id beside it. Nothing else leaves the browser.
    static let cookies = ["passport_token", "uid"]

    static let origin = "https://longcat.chat"
    static let userPath = "/api/v1/user-current"
    static let tokenPacksPath = "/api/pay/quota/metering/token-packs/summary"
    static let tokenUsagePath = "/api/lc-platform/v1/tokenUsage"
    static let fuelPath = "/api/lc-platform/v1/pending-fuel-packages"

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential else { return context.unavailable(.sessionMissing) }
        let http = session ?? isolatedSession()
        defer { if session == nil { http.finishTasksAndInvalidate() } }

        // The one call that has to succeed before anything is believed: a
        // session the platform no longer takes answers here, not with zeros
        // further on.
        switch await ask(userPath, cookie: cookie, session: http) {
        case .failure(let reason): return context.unavailable(reason)
        case .success: break
        }

        // Best-effort: some sessions are not let into this route at all.
        let packs = try? await ask(tokenPacksPath, method: "POST", cookie: cookie, session: http).get()

        var tokenUsage: [String: Any]?
        if activeLot(in: packs) == nil {
            switch await ask(tokenUsagePath, cookie: cookie, session: http) {
            case .failure(let reason): return context.unavailable(reason)
            case .success(let payload): tokenUsage = payload
            }
        }

        let fuel = try? await ask(fuelPath, cookie: cookie, session: http).get()
        return reading(packs: packs, tokenUsage: tokenUsage, fuel: fuel, context: context)
    }

    /// Its own session: no cookie jar, and no redirects, so an expired
    /// session's bounce to a sign-in page is seen as one and never followed
    /// with the cookie attached.
    private static func isolatedSession() -> URLSession {
        let configuration = NetworkSession.configured(.ephemeral)
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    static func request(_ path: String, method: String = "GET", cookie: String) -> URLRequest {
        var request = URLRequest(url: URL(string: origin + path)!)
        request.httpMethod = method
        request.timeoutInterval = 15
        if method == "POST" {
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("\(origin)/platform/usage", forHTTPHeaderField: "Referer")
        return request
    }

    private static func ask(
        _ path: String, method: String = "GET", cookie: String, session: URLSession
    ) async -> Result<[String: Any], ProviderUsage.Unavailability> {
        let data: Data
        switch await ProfileHTTP.reply(for: request(path, method: method, cookie: cookie), session: session) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let reply) where (300..<400).contains(reply.status):
            return .failure(.sessionExpired)
        case .success(let reply):
            switch ProfileHTTP.classify(reply, refused: .sessionExpired) {
            case .failure(let reason): return .failure(reason)
            case .success(let body): data = body
            }
        }
        return payload(of: data)
    }

    /// The platform's envelope, `{ code, message, data }`: the `data` of a
    /// code that is a success, or the reason there is none.
    static func payload(of data: Data) -> Result<[String: Any], ProviderUsage.Unavailability> {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .failure(.unreadableReply) }
        if let raw = envelope["code"] {
            guard let code = number(raw).flatMap({ Int(exactly: $0) }) else { return .failure(.unreadableReply) }
            switch code {
            case 0, 200: break
            case 401, 403: return .failure(.sessionExpired)
            default: return .failure(.serverError)
            }
        }
        guard let payload = (envelope["data"] ?? envelope) as? [String: Any] else {
            return .failure(.unreadableReply)
        }
        return .success(payload)
    }

    // MARK: - Reading the replies

    /// The windows, from the unwrapped `data` of each route. Nil for a route
    /// not asked or not answered.
    static func reading(
        packs: [String: Any]?, tokenUsage: [String: Any]?, fuel: [String: Any]?,
        context: ProfileContext, now: Date = Date()
    ) -> ProviderUsage {
        var windows: [UsageWindow] = []

        if let lot = activeLot(in: packs) {
            if let total = number(lot["totalToken"]), let used = number(lot["consumedToken"]), used >= 0 {
                windows.append(allowance(used: used, total: total))
            }
        } else if let tokenUsage {
            // The account-wide figure; `extData` beside it is per model.
            let usage = (tokenUsage["usage"] as? [String: Any]) ?? tokenUsage
            // The route has to state a total at all; one that does not is not
            // a reply this reads, and saying "no limits" would hide that.
            guard let total = number(usage["totalToken"]) else { return context.unavailable(.unreadableReply) }
            if total > 0 {
                let used = number(usage["usedToken"]) ?? number(usage["availableToken"]).map { total - $0 }
                if let used, used >= 0 { windows.append(allowance(used: used, total: total)) }
            }
        }

        if let fuel, let window = fuelWindow(fuel, now: now) { windows.append(window) }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, at: now)
    }

    /// A token pack counts only while the platform calls it active and gives
    /// it a size; an expired or empty one leaves the allowance to the older
    /// route, which is what the platform's page does.
    private static func activeLot(in packs: [String: Any]?) -> [String: Any]? {
        guard let lot = packs?["currentLot"] as? [String: Any],
              (lot["status"] as? String)?.uppercased() == "ACTIVE",
              let total = number(lot["totalToken"]), total > 0
        else { return nil }
        return lot
    }

    private static func allowance(used: Double, total: Double) -> UsageWindow {
        UsageWindow(
            id: "longcat.tokens",
            kind: .credits,
            scope: nil,
            usedFraction: used / total,
            windowSeconds: 30 * 86_400,
            resetsAt: nil,
            reportsLength: false,
            isExhausted: used >= total
        )
    }

    /// The fuel packs as one top-up: their stated total, less what each pack
    /// says it has left, with the soonest to lapse as the expiry.
    private static func fuelWindow(_ fuel: [String: Any], now: Date) -> UsageWindow? {
        guard let total = number(fuel["totalQuota"]), total > 0 else { return nil }
        let packs = (fuel["list"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        let left = packs.compactMap { number($0["availableToken"]) }.filter { $0 >= 0 }
        guard !left.isEmpty else { return nil }
        let remaining = left.reduce(0, +)
        let used = max(total - remaining, 0)

        var window = UsageWindow(
            id: "longcat.fuel",
            kind: .topUp,
            scope: nil,
            usedFraction: used / total,
            windowSeconds: 60 * 86_400,
            resetsAt: nil,
            reportsLength: false,
            isExhausted: remaining <= 0
        )
        let parts = packs.compactMap { pack -> (amount: Double, at: Date)? in
            guard let amount = number(pack["availableToken"]), let at = date(pack["expireTime"]) else { return nil }
            return (amount, at)
        }
        window.nextExpiry = UsageWindow.Expiry.soonest(of: parts, after: now)
        return window
    }

    /// A number, or a string that is one. Never a boolean.
    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue.isFinite ? number.doubleValue : nil
        }
        if let text = value as? String { return Double(text).flatMap { $0.isFinite ? $0 : nil } }
        return nil
    }

    /// Epoch seconds or milliseconds, ISO 8601, or `yyyy-MM-dd HH:mm:ss`.
    static func date(_ value: Any?) -> Date? {
        if let epoch = number(value) {
            let seconds = epoch > 1_000_000_000_000 ? epoch / 1_000 : epoch
            return seconds > 1_000_000_000 ? Date(timeIntervalSince1970: seconds) : nil
        }
        guard let text = value as? String else { return nil }
        if let date = ProfileHTTP.date(text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)
    }
}
