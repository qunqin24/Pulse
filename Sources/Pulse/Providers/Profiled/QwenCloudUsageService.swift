// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Qwen Cloud's individual Token Plan: a five-hour, a weekly and a monthly
/// allowance, each reported by the service as the share of it already used.
///
/// Read with a browser session from `qwencloud.com`, the way the console's
/// own subscription page reads it: the page's security token first (from the
/// page, a cookie, or the account endpoint), then
/// `POST https://cs-data.qwencloud.com/data/api.json` for the plan's usage and,
/// for its tier's name only, its subscription. The shape is second-hand —
/// taken from CodexBar's Qwen Cloud provider and its tests, not from a
/// captured reply.
///
/// **What is left out.** The plan's credit totals per window (the
/// `quota-config` route) are not asked for: Pulse has nowhere to show them,
/// and the share used is already the service's own figure. A reply in the
/// older subscription-summary shape is not read for figures; one that counts
/// no subscription at all is said as "no plan".
extension ProviderProfile {
    static let qwenCloud = ProviderProfile(
        displayName: "Qwen Cloud",
        iconResource: "qwen",
        credential: .sessionCookie(host: QwenCloudUsageService.cookieHost, cookies: QwenCloudUsageService.cookies),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        setupSlug: "qwen-cloud",
        fetch: { await QwenCloudUsageService.fetch($0) }
    )
}

enum QwenCloudUsageService {
    static let cookieHost = "qwencloud.com"
    /// A sign-in ticket first, any one of the three, which has to be there;
    /// then the account markers, the CSRF token the console checks, the
    /// browser id it echoes back, and its security token when kept as a
    /// cookie. Nothing else leaves the browser.
    static let cookies = [
        "login_qwencloud_ticket|login_aliyunid_ticket|qwen_sso_ticket",
        "login_current_pk", "login_aliyunid_pk", "login_aliyunid_csrf", "csrf", "cna", "sec_token",
    ]

    static let origin = "https://home.qwencloud.com"
    static let page = URL(string: "https://home.qwencloud.com/billing/subscription/token-plan-individual")!
    static let userInfo = URL(string: "https://home.qwencloud.com/tool/user/info.json")!
    static let usageAPI = "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage"
    static let subscriptionAPI = "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/subscription"
    /// The individual plan, international: the only one Qwen Cloud sells.
    static let commodityCode = "sfm_tokenplansolo_public_intl"

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential else { return context.unavailable(.sessionMissing) }
        let http = session ?? isolatedSession()
        defer { if session == nil { http.finishTasksAndInvalidate() } }

        let token: String
        switch await securityToken(cookie: cookie, session: http) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let found): token = found
        }

        let usage: Data
        switch await ask(usageAPI, data: [:], token: token, cookie: cookie, session: http) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data): usage = data
        }

        let found = reading(from: usage, context: context)
        guard found.state == .live else { return found }
        // The tier's name only; a failure here costs the label, not the figures.
        guard case .success(let subscription) = await ask(
            subscriptionAPI, data: ["commodityCode": commodityCode], token: token, cookie: cookie, session: http
        ), let plan = planName(from: subscription) else { return found }
        return context.reading(found.windows, plan: plan, at: found.observedAt ?? Date())
    }

    /// Its own session: no cookie jar, so nothing the console sets is kept or
    /// sent back, and no redirects, so a sign-in page elsewhere is never
    /// handed the session.
    private static func isolatedSession() -> URLSession {
        let configuration = NetworkSession.configured(.ephemeral)
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    // MARK: - The security token

    /// The console's `sec_token`, which every gateway call carries: from the
    /// subscription page, then from the session's own cookie, then from the
    /// account endpoint. None of the three is a sign-in the console accepts.
    private static func securityToken(
        cookie: String, session: URLSession
    ) async -> Result<String, ProviderUsage.Unavailability> {
        var pageFailure: ProviderUsage.Unavailability?

        var request = URLRequest(url: page)
        request.timeoutInterval = 15
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        switch await ProfileHTTP.reply(for: request, session: session) {
        case .failure(let reason):
            pageFailure = reason
        case .success(let reply) where reply.status == 200:
            if let html = String(data: reply.data, encoding: .utf8), !isSignInPage(html),
               let token = securityToken(inPage: html) {
                return .success(token)
            }
        case .success(let reply):
            if (500...599).contains(reply.status) { pageFailure = .serverError }
        }

        if let token = cookieValue("sec_token", in: cookie) { return .success(token) }

        var info = URLRequest(url: userInfo)
        info.timeoutInterval = 15
        info.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        info.setValue(cookie, forHTTPHeaderField: "Cookie")
        if case .success(let reply) = await ProfileHTTP.reply(for: info, session: session), reply.status == 200,
           let object = try? JSONSerialization.jsonObject(with: reply.data),
           let token = AlibabaConsoleJSON.firstString(["secToken", "sec_token", "csrfToken", "token"],
                                                      in: AlibabaConsoleJSON.expanded(object)) {
            return .success(token)
        }

        // A page that could not be reached says more than a token not found.
        return .failure(pageFailure ?? .sessionExpired)
    }

    static func securityToken(inPage html: String) -> String? {
        let patterns = [
            #""secToken"\s*:\s*"([^"]+)""#,
            #""sec_token"\s*:\s*"([^"]+)""#,
            #"secToken['"]?\s*[:=]\s*['"]([^'"]+)['"]"#,
            #"sec_token['"]?\s*[:=]\s*['"]([^'"]+)['"]"#,
            #"csrfToken['"]?\s*[:=]\s*['"]([^'"]+)['"]"#,
        ]
        let range = NSRange(html.startIndex..., in: html)
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: html, range: range),
                  let found = Range(match.range(at: 1), in: html)
            else { continue }
            let token = html[found].trimmingCharacters(in: .whitespaces)
            if !token.isEmpty { return token }
        }
        return nil
    }

    static func isSignInPage(_ html: String) -> Bool {
        let page = html.lowercased()
        return ["passport.alibabacloud.com", "signin.aliyun.com", "account.alibabacloud.com/login",
                "login.qwencloud.com"].contains(where: page.contains)
            || (page.contains("login") && page.contains("password") && page.contains("sign in"))
    }

    private static func cookieValue(_ name: String, in header: String) -> String? {
        header.split(separator: ";").lazy.compactMap { part -> String? in
            let pair = part.trimmingCharacters(in: .whitespaces)
            guard pair.hasPrefix(name + "=") else { return nil }
            let value = String(pair.dropFirst(name.count + 1))
            return value.isEmpty ? nil : value
        }.first
    }

    // MARK: - The gateway

    static func request(_ api: String, data: [String: String], token: String, cookie: String) -> URLRequest {
        var components = URLComponents(string: "https://cs-data.qwencloud.com/data/api.json")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "IntlBroadScopeAspnGateway"),
            URLQueryItem(name: "product", value: "sfm_bailian"),
            URLQueryItem(name: "api", value: api),
            URLQueryItem(name: "_v", value: "undefined"),
        ]

        // The envelope the console page wraps every call in.
        var cornerstone: [String: String] = [
            "feTraceId": UUID().uuidString.lowercased(),
            "feURL": page.absoluteString,
            "protocol": "V2",
            "console": "ONE_CONSOLE",
            "productCode": "p_efm",
            "domain": "home.qwencloud.com",
            "consoleSite": "QWENCLOUD",
            "userNickName": "",
            "userPrincipalName": "",
            "xsp_lang": "en-US",
        ]
        if let browser = cookieValue("cna", in: cookie) { cornerstone["X-Anonymous-Id"] = browser }
        var payload: [String: Any] = data
        payload["cornerstoneParam"] = cornerstone
        let params = (try? JSONSerialization.data(withJSONObject: ["Api": api, "V": "1.0", "Data": payload],
                                                   options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = form([
            ("product", "sfm_bailian"),
            ("action", "IntlBroadScopeAspnGateway"),
            ("sec_token", token),
            ("region", "ap-southeast-1"),
            ("language", "en-US"),
            ("params", params),
        ])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(page.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let csrf = cookieValue("login_aliyunid_csrf", in: cookie) ?? cookieValue("csrf", in: cookie) {
            request.setValue(csrf, forHTTPHeaderField: "x-xsrf-token")
            request.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        }
        return request
    }

    /// A form body with everything but the unreserved characters escaped, so
    /// a `+`, `&` or `=` inside the token or the JSON arrives as itself.
    static func form(_ fields: [(String, String)]) -> Data {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        let escape = { (text: String) in text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
        return Data(fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&").utf8)
    }

    private static func ask(
        _ api: String, data: [String: String], token: String, cookie: String, session: URLSession
    ) async -> Result<Data, ProviderUsage.Unavailability> {
        switch await ProfileHTTP.reply(for: request(api, data: data, token: token, cookie: cookie), session: session) {
        case .failure(let reason):
            return .failure(reason)
        // Redirects are not followed, so a signed-out session shows here as
        // the redirect to the sign-in page itself.
        case .success(let reply) where (300..<400).contains(reply.status):
            return .failure(.sessionExpired)
        case .success(let reply):
            return ProfileHTTP.classify(reply, refused: .sessionExpired)
        }
    }

    // MARK: - Reading the reply

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let tree = AlibabaConsoleJSON.expanded(object) as? [String: Any]
        else {
            let text = String(decoding: data.prefix(4_096), as: UTF8.self).lowercased()
            return context.unavailable(text.contains("<html") && isSignInPage(text) ? .sessionExpired : .unreadableReply)
        }

        switch AlibabaConsoleJSON.failure(in: tree) {
        case .signedOut: return context.unavailable(.sessionExpired)
        case .failed: return context.unavailable(.serverError)
        case nil: break
        }

        let windows = AlibabaTokenPlanUsageService.rollingWindows(in: tree, id: "qwenCloud", now: now)
        if !windows.isEmpty { return context.reading(windows, at: now) }

        // The older summary shape, counting the account's subscriptions.
        if let count = AlibabaConsoleJSON.firstInt(["TotalCount", "totalCount"], in: tree), count == 0 {
            return context.unavailable(.noPlan)
        }
        return context.unavailable(.noLimitsReported)
    }

    /// The tier the subscription names, as the console spells it on the page.
    static func planName(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let tree = AlibabaConsoleJSON.expanded(object)
        guard let code = AlibabaConsoleJSON.firstString(["specCode", "spec_code", "planName", "plan_name"], in: tree)
        else { return nil }
        return ["lite", "standard", "pro", "max"].contains(code.lowercased()) ? code.capitalized : code
    }
}
