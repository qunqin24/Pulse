// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CryptoKit
import Foundation

/// JetBrains AI's quota asked of JetBrains with the login Pulse signed in to
/// itself (`JetBrainsLogin`), for IDEs that no longer save it on this Mac.
///
/// **Ported from rock3r/headroom (Apache-2.0)**,
/// `core/quota/src/commonMain/kotlin/dev/sebastiano/headroom/quota/JetBrainsAiQuotaReader.kt`
/// and `JetBrainsAccessOption.kt` at commit 9a2851d, which say each step is
/// the Junie CLI's or the IDE's. The request shapes and reply shapes below are
/// headroom's, pinned by its tests and fixtures; Pulse has not sent any of
/// them to a live account.
///
/// 1. The refresh token is switched to the `jcp-user-management` audience
///    (`grant_type=switch_audience` at the JetBrains Account token endpoint),
///    and that token lists the account's AI access options
///    (`GET api.jetbrains.cloud/user-management/api/ai-access-options`).
/// 2. Every enabled option is read, at most five:
///    - **a licence** (the account's own, AI Pro and the like): the ID token
///      obtains a JetBrains AI token for it
///      (`POST api.jetbrains.ai/auth/jetbrains-jwt/provide-access/license/v2`),
///      which reads `POST /user/v5/quota/get` and
///      `/user/v5/quota/metadata/refill` in a `Grazie-Authenticate-JWT` header;
///    - **a workspace seat** (an organisation's): the refresh token is
///      switched to `org-service`, which reads the signed list of the
///      account's organisations (`GET api.jetbrains.cloud/org/orgsuserinfo`),
///      then to `ai-access` for that organisation and workspace, and that
///      token reads `GET api.jetbrains.ai/quota/api/quota/get` and
///      `/quota/api/quota/refill` — the IDE's own `JcpQuotaClient` paths.
/// 3. Each answer is mapped as the IDE's file is (`JetBrainsAIUsageService`):
///    `current` of `maximum`, the refill's `next` as the reset, and the
///    tariff's `period` as the length when it states one.
///
/// **Left out of headroom's flow:** the free `grazie-lite` licence it falls
/// back to (`POST /auth/jetbrains-jwt/license/obtain/grazie-lite`) — a call
/// named "obtain" may give the account a licence, and Pulse only reads; and
/// the window that pools several licences, which is arithmetic Pulse would be
/// drawing, not a figure JetBrains stated.
///
/// A token an audience switch returns, a new refresh token included, is never
/// stored, as in headroom.
enum JetBrainsAIOnlineQuota {
    typealias Send = JetBrainsLogin.Send

    static let aiBase = URL(string: "https://api.jetbrains.ai")!
    static let accessOptions = URL(string: "https://api.jetbrains.cloud/user-management/api/ai-access-options")!
    static let orgsUserInfo = URL(string: "https://api.jetbrains.cloud/org/orgsuserinfo")!
    /// headroom sends its own name here; Pulse sends its own the same way.
    static let agent = #"{"name":"Pulse","version":"1"}"#
    static let maxSources = 5

    // MARK: - The reading

    /// The quota for a stored login, renewing it first when it is close to
    /// expiring. `keep` stores a renewal; it is `AccountCredentialStore.renewed`
    /// in the app, which never writes one over a removed login.
    static func usage(
        login stored: AccountCredentials,
        context: ProfileContext,
        now: Date = Date(),
        send: Send = JetBrainsLogin.liveSend,
        keep: @Sendable (AccountCredentials) -> Void = { AccountCredentialStore.renewed($0, for: JetBrainsLogin.account) }
    ) async -> ProviderUsage {
        var login = stored
        if login.expiresAt.timeIntervalSince(now) <= 60 {
            do {
                login = try await JetBrainsLogin.refresh(login, send: send)
            } catch {
                return context.unavailable(LiveUsageServices.renewalFailure(error))
            }
            keep(login)
        }

        let token: String
        switch await switchAudience("jcp-user-management", refreshToken: login.refreshToken, send: send) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let switched): token = switched
        }

        let sources: [Source]
        switch await send(get(accessOptions, bearer: token)) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let reply):
            switch ProfileHTTP.classify(reply, refused: .signedOut) {
            case .failure(let reason): return context.unavailable(reason)
            case .success(let data):
                guard let parsed = Self.sources(in: data) else { return context.unavailable(.unreadableReply) }
                sources = parsed
            }
        }
        // The account has no licence or seat with AI switched on.
        guard !sources.isEmpty else { return context.unavailable(.noPlan) }

        // One signed list of organisations for every seat, read once.
        var organisations: Result<String, ProviderUsage.Unavailability>?
        if sources.contains(where: { if case .workspace = $0 { true } else { false } }) {
            organisations = await readOrganisations(refreshToken: login.refreshToken, send: send)
        }

        var read: [(Source, Quota)] = []
        var failures: [ProviderUsage.Unavailability] = []
        for source in sources {
            let result: Result<Quota?, ProviderUsage.Unavailability>
            switch source {
            case .license(let id, _):
                result = await readLicense(id, idToken: login.idToken, send: send)
            case .workspace(let workspace, let organisation, _):
                switch organisations {
                case .success(let signed)?:
                    result = await readSeat(workspace: workspace, organisation: organisation, signedList: signed,
                                            refreshToken: login.refreshToken, send: send)
                case .failure(let reason)?: result = .failure(reason)
                case nil: result = .failure(.unreadableReply)
                }
            }
            switch result {
            case .success(let quota?): read.append((source, quota))
            case .success(nil): break
            case .failure(let reason): failures.append(reason)
            }
        }

        guard !read.isEmpty else {
            // Every option answered without figures: a quota without a size.
            return context.unavailable(failures.first ?? .noLimitsReported)
        }
        let several = read.count > 1
        let windows = read.map { source, quota in
            window(quota, id: several ? "jetbrains.quota.\(source.hashedID)" : "jetbrains.quota",
                   scope: several ? source.label : nil)
        }
        .sorted { $0.usedFraction > $1.usedFraction }
        let plan: String? = if !several, case .license(_, let code?) = read[0].0 { productName(code) } else { nil }
        return context.reading(windows, plan: plan, at: now)
    }

    // MARK: - Access options

    /// One licence or workspace seat to read.
    enum Source: Equatable, Sendable {
        case license(id: String, code: String?)
        case workspace(id: String, organisation: String?, name: String?)

        /// Stable across readings and not the id itself: the first six bytes
        /// of its SHA-256, as headroom's window ids are.
        var hashedID: String {
            let id: String = switch self {
            case .license(let id, _), .workspace(let id, _, _): id
            }
            return SHA256.hash(data: Data(id.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        }

        /// What the card calls it when there are several: the licence's
        /// product or the workspace's own name, never translated.
        var label: String? {
            switch self {
            case .license(_, let code): code.map(JetBrainsAIOnlineQuota.productName)
            case .workspace(_, _, let name): name
            }
        }
    }

    /// The options of an `ai-access-options` reply that can be read, or nil
    /// when the reply has no list of them. As headroom's `quotaSources`: only
    /// enabled options; a `workspace` with a workspace id is a seat; anything
    /// else with a licence id is a licence; no more than five, no repeats.
    static func sources(in data: Data) -> [Source]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let options = json["aiAccessOptions"] as? [Any]
        else { return nil }
        var found: [Source] = []
        for case let option as [String: Any] in options {
            guard option["aiAccessEnabled"] as? Bool == true else { continue }
            func text(_ key: String) -> String? {
                (option[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            }
            let source: Source
            if (text("type") ?? "").caseInsensitiveCompare("workspace") == .orderedSame, let workspace = text("workspaceId") {
                source = .workspace(id: workspace, organisation: text("orgId"), name: text("workspaceName") ?? text("orgName"))
            } else if let license = text("licenseId") {
                source = .license(id: license, code: text("name"))
            } else {
                continue
            }
            if !found.contains(where: { $0.hashedID == source.hashedID }) { found.append(source) }
            if found.count == maxSources { break }
        }
        return found
    }

    /// headroom's `jetBrainsPlanLabel`. An unknown code is shown as it is.
    static func productName(_ code: String) -> String {
        switch code {
        case "AIP": "JetBrains AI Pro"
        case "AIU": "JetBrains AI Ultimate"
        case "JUNP": "Junie"
        default: code
        }
    }

    // MARK: - Requests

    /// `grant_type=switch_audience`, in the order the Junie CLI sends the
    /// fields (headroom's `switchAudience`). A refusal is the refresh token
    /// refused — the login is gone — so it is `.signedOut`.
    static func switchAudienceRequest(_ audience: String, refreshToken: String, scope: [(String, String)] = []) -> URLRequest {
        JetBrainsLogin.tokenRequest([
            ("grant_type", "switch_audience"),
            ("refresh_token", refreshToken),
            ("audience", audience),
            ("client_id", JetBrainsLogin.clientID),
        ] + scope)
    }

    private static func switchAudience(
        _ audience: String,
        refreshToken: String,
        scope: [(String, String)] = [],
        send: Send
    ) async -> Result<String, ProviderUsage.Unavailability> {
        switch await send(switchAudienceRequest(audience, refreshToken: refreshToken, scope: scope)) {
        case .failure(let reason): return .failure(reason)
        case .success(let reply):
            // The token endpoint answers a refused grant with 400.
            let refusal = reply.status == 400 ? ProfileHTTP.Reply(data: reply.data, status: 401) : reply
            switch ProfileHTTP.classify(refusal, refused: .signedOut) {
            case .failure(let reason): return .failure(reason)
            case .success(let data):
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let token = json["access_token"] as? String, !token.isEmpty
                else { return .failure(.unreadableReply) }
                return .success(token)
            }
        }
    }

    static func get(_ url: URL, bearer token: String) -> URLRequest {
        ProfileHTTP.bearer(url, token: token)
    }

    /// A JSON POST, the licence route's: headroom sends `{}` when there is
    /// nothing to say.
    static func post(_ url: URL, headers: [String: String], body: String = "{}") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = Data(body.utf8)
        return request
    }

    static func provideAccessRequest(license: String, idToken: String) -> URLRequest {
        let body = (try? JSONSerialization.data(withJSONObject: ["licenseId": license]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return post(aiBase.appending(path: "auth/jetbrains-jwt/provide-access/license/v2"),
                    headers: ["Authorization": "Bearer \(idToken)"], body: body)
    }

    static func licenseQuotaRequests(grazieToken: String) -> (quota: URLRequest, refill: URLRequest) {
        let headers = ["Grazie-Authenticate-JWT": grazieToken, "Grazie-Agent": agent]
        return (post(aiBase.appending(path: "user/v5/quota/get"), headers: headers),
                post(aiBase.appending(path: "user/v5/quota/metadata/refill"), headers: headers))
    }

    static func seatQuotaRequests(seatToken: String) -> (quota: URLRequest, refill: URLRequest) {
        (get(aiBase.appending(path: "quota/api/quota/get"), bearer: seatToken),
         get(aiBase.appending(path: "quota/api/quota/refill"), bearer: seatToken))
    }

    private static func readLicense(
        _ license: String,
        idToken: String?,
        send: Send
    ) async -> Result<Quota?, ProviderUsage.Unavailability> {
        // A login always carries one after sign-in (`openid`); without it the
        // licence cannot be asked, and signing in again gives one.
        guard let idToken else { return .failure(.signedOut) }
        let grazie: String
        switch await json(provideAccessRequest(license: license, idToken: idToken), send: send) {
        case .failure(let reason): return .failure(reason)
        case .success(let reply):
            guard let token = reply["token"] as? String, !token.isEmpty else { return .failure(.unreadableReply) }
            grazie = token
        }
        let requests = licenseQuotaRequests(grazieToken: grazie)
        return await readQuota(requests.quota, refill: requests.refill, send: send)
    }

    /// The signed list of organisations a seat's token request needs: the
    /// first JWT-shaped text in the reply, as the Junie CLI finds it
    /// (headroom's `readOrgsUserInfo`).
    private static func readOrganisations(refreshToken: String, send: Send) async -> Result<String, ProviderUsage.Unavailability> {
        let token: String
        switch await switchAudience("org-service", refreshToken: refreshToken, send: send) {
        case .failure(let reason): return .failure(reason)
        case .success(let switched): token = switched
        }
        switch await send(get(orgsUserInfo, bearer: token)) {
        case .failure(let reason): return .failure(reason)
        case .success(let reply):
            switch ProfileHTTP.classify(reply, refused: .signedOut) {
            case .failure(let reason): return .failure(reason)
            case .success(let data):
                guard let jwt = signedList(in: String(decoding: data, as: UTF8.self)) else { return .failure(.unreadableReply) }
                return .success(jwt)
            }
        }
    }

    static func signedList(in text: String) -> String? {
        guard let pattern = try? Regex(#"[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+"#),
              let match = text.firstMatch(of: pattern)
        else { return nil }
        return String(text[match.range])
    }

    /// A seat's token: the organisation, the workspace and the signed list.
    /// Refused, it is asked once more without the organisation, because the
    /// IDE asks with only the workspace (headroom's `readSeatWindow`).
    private static func readSeat(
        workspace: String,
        organisation: String?,
        signedList: String,
        refreshToken: String,
        send: Send
    ) async -> Result<Quota?, ProviderUsage.Unavailability> {
        let seat = [("workspace_id", workspace), ("orgs_user_info", signedList)]
        var attempts = [seat]
        if let organisation { attempts.insert([("org_id", organisation)] + seat, at: 0) }
        var last: ProviderUsage.Unavailability = .signedOut
        for scope in attempts {
            switch await switchAudience("ai-access", refreshToken: refreshToken, scope: scope, send: send) {
            case .success(let token):
                let requests = seatQuotaRequests(seatToken: token)
                return await readQuota(requests.quota, refill: requests.refill, send: send)
            case .failure(let reason):
                last = reason
                guard reason == .signedOut else { return .failure(reason) }
            }
        }
        return .failure(last)
    }

    private static func json(_ request: URLRequest, send: Send) async -> Result<[String: Any], ProviderUsage.Unavailability> {
        switch await send(request) {
        case .failure(let reason): return .failure(reason)
        case .success(let reply):
            switch ProfileHTTP.classify(reply, refused: .signedOut) {
            case .failure(let reason): return .failure(reason)
            case .success(let data):
                guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    return .failure(.unreadableReply)
                }
                return .success(object)
            }
        }
    }

    /// The quota, then its refill. A refill that cannot be read leaves the
    /// reset and the length off and keeps the quota, as a file without
    /// `nextRefill` does.
    private static func readQuota(
        _ quota: URLRequest,
        refill: URLRequest,
        send: Send
    ) async -> Result<Quota?, ProviderUsage.Unavailability> {
        let figures: [String: Any]
        switch await json(quota, send: send) {
        case .failure(let reason): return .failure(reason)
        case .success(let reply): figures = reply
        }
        let schedule: [String: Any]? = switch await json(refill, send: send) {
        case .success(let reply): reply
        case .failure: nil
        }
        return .success(Self.quota(figures, refill: schedule))
    }

    // MARK: - Reply

    /// What one licence or seat stated, in the units the service counts in.
    struct Quota: Equatable, Sendable {
        let used: Double
        let maximum: Double
        let resetsAt: Date?
        /// The tariff's period, when the refill states one.
        let seconds: Int?
    }

    /// `{"current": {"current": {"amount": "12.5"}, "maximum": {"amount": "50"}, …}}`
    /// with `{"current": {"next": <ms>, "tariff": {"period": {"millis": …}}}}`
    /// beside it. Nil when either figure is missing, `current` is negative or
    /// `maximum` is not above zero — no percentage is made up.
    ///
    /// The amounts are 1/100,000 of an AI credit (the IDE's `UNITS_IN_CREDIT`,
    /// per headroom); a fraction of two of them needs no conversion.
    /// `current` and `maximum` are the whole quota, top-up included, as the
    /// file's `current` and `maximum` are; `tariffQuota` and `topUpQuota` are
    /// not drawn on their own, as the file's are not.
    static func quota(_ reply: [String: Any], refill: [String: Any]?) -> Quota? {
        guard let current = reply["current"] as? [String: Any],
              let used = amount(current["current"]), used >= 0,
              let maximum = amount(current["maximum"]), maximum > 0
        else { return nil }
        let schedule = refill?["current"] as? [String: Any]
        // The refill's `next`, not the quota's `until` — the same choice the
        // file route makes between `nextRefill.next` and `quotaInfo.until`.
        let next = (schedule?["next"] as? NSNumber)?.doubleValue
        let resetsAt = next.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        let millis = (((schedule?["tariff"] as? [String: Any])?["period"] as? [String: Any])?["millis"] as? NSNumber)?.doubleValue
        let seconds = millis.flatMap { value -> Int? in
            guard value.isFinite, value >= 1000, value / 1000 <= Double(UsageWindow.longestLength) else { return nil }
            return Int(value / 1000)
        }
        return Quota(used: used, maximum: maximum, resetsAt: resetsAt, seconds: seconds)
    }

    /// An amount as the service writes it, `{"amount": "12.5"}`, or a plain
    /// number or numeric string (headroom's `parseCredit`).
    static func amount(_ value: Any?) -> Double? {
        let inner = (value as? [String: Any])?["amount"] ?? value
        return JetBrainsAIUsageService.number(inner)
    }

    /// The window, as the file route draws one: stated length or none.
    static func window(_ quota: Quota, id: String, scope: String?) -> UsageWindow {
        let fraction = quota.used / quota.maximum
        return UsageWindow(
            id: id,
            kind: quota.seconds.map { .other(seconds: $0) } ?? .credits,
            scope: scope,
            usedFraction: fraction,
            windowSeconds: quota.seconds ?? 30 * 86_400,
            resetsAt: quota.resetsAt,
            reportsLength: quota.seconds != nil,
            isExhausted: fraction >= 1
        )
    }
}
