import Foundation
import Testing
@testable import Pulse

/// JetBrains AI's sign-in and online quota.
///
/// **Every token, id and reply here is synthetic**, shaped like rock3r/headroom's
/// tests and fixtures (Apache-2.0, `core/quota/src/jvmTest/resources/jetbrains/`
/// at 9a2851d). They pin the requests Pulse builds and how it reads those
/// shapes; they do not prove JetBrains answers that way. No live account was
/// asked.
@Suite("JetBrains AI online")
struct JetBrainsAIOnlineTests {
    private let context = ProfileContext(provider: .jetBrainsAI, credential: nil, serverAddress: nil)
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - A server that answers like headroom's fixtures

    final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [URLRequest] = []
        var answer: @Sendable (URLRequest) -> ProfileHTTP.Reply?

        init(answer: @escaping @Sendable (URLRequest) -> ProfileHTTP.Reply?) { self.answer = answer }

        var requests: [URLRequest] { lock.withLock { seen } }

        var send: JetBrainsLogin.Send {
            { request in
                self.lock.withLock { self.seen.append(request) }
                guard let reply = self.answer(request) else { return .failure(.unreachable) }
                return .success(reply)
            }
        }
    }

    static func reply(_ json: String, status: Int = 200) -> ProfileHTTP.Reply {
        ProfileHTTP.Reply(data: Data(json.utf8), status: status)
    }

    static func form(_ request: URLRequest) -> [(String, String)] {
        String(decoding: request.httpBody ?? Data(), as: UTF8.self).split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts[0], parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : "")
        }
    }

    static func formValue(_ request: URLRequest, _ name: String) -> String? {
        form(request).first { $0.0 == name }?.1
    }

    static let options = """
    {"aiAccessOptions": [
      {"type": "license", "aiAccessEnabled": true, "name": "AIP", "licenseId": "test-license-id",
       "licensedTo": "sam@example.com"},
      {"type": "workspace", "aiAccessEnabled": true, "orgId": "test-org-id", "orgName": "Example Org",
       "workspaceId": "test-workspace-id", "workspaceName": "Example Workspace"},
      {"type": "license", "aiAccessEnabled": false, "name": "AIU", "licenseId": "test-disabled-license-id"}
    ]}
    """
    static let licenseOnly = """
    {"aiAccessOptions": [{"type": "license", "aiAccessEnabled": true, "name": "AIP", "licenseId": "test-license-id"}]}
    """

    static func quota(current: String, maximum: String) -> String {
        """
        {"current": {"license": "x", "current": {"amount": "\(current)"}, "maximum": {"amount": "\(maximum)"},
         "until": 1777550400000,
         "tariffQuota": {"current": {"amount": "\(current)"}, "maximum": {"amount": "\(maximum)"}},
         "topUpQuota": {"current": {"amount": "0"}, "maximum": {"amount": "0"}}}}
        """
    }

    static let refill = #"{"current": {"tariff": {"amount": {"amount": "50"}, "period": {"millis": 2592000000}}, "next": 1777593600000, "last": 1775001600000}}"#

    /// headroom's routes: a token per audience, a quota per token.
    static func server(
        options: String = Self.options,
        licenseQuota: String = Self.quota(current: "1187.525", maximum: "1000000.0"),
        seatQuota: String = Self.quota(current: "5000000", maximum: "20000000"),
        refill: ProfileHTTP.Reply = reply(Self.refill),
        userManagement: ProfileHTTP.Reply = reply(#"{"access_token":"test-jcp-token","expires_in":300,"refresh_token":"test-new-refresh"}"#),
        seatAccepts: @escaping @Sendable ([(String, String)]) -> Bool = { _ in true }
    ) -> Server {
        Server { request in
            let path = request.url?.path ?? ""
            switch (request.url?.host ?? "", path) {
            case ("oauth.account.jetbrains.com", "/oauth2/token"):
                switch formValue(request, "grant_type") {
                case "refresh_token":
                    return reply(#"{"access_token":"renewed-access","expires_in":3600,"id_token":"renewed-id"}"#)
                default: break
                }
                switch formValue(request, "audience") {
                case "jcp-user-management": return userManagement
                case "org-service": return reply(#"{"access_token":"test-org-service-token"}"#)
                case "ai-access":
                    return seatAccepts(form(request))
                        ? reply(#"{"access_token":"test-seat-token","expires_in":300}"#)
                        : reply(#"{"error":"invalid_request"}"#, status: 400)
                default: return reply("{}", status: 400)
                }
            case ("api.jetbrains.cloud", "/user-management/api/ai-access-options"): return reply(options)
            case ("api.jetbrains.cloud", "/org/orgsuserinfo"):
                return reply(#"{"jwt":"test-orgs-header.test-orgs-payload.test-orgs-signature"}"#)
            case ("api.jetbrains.ai", "/auth/jetbrains-jwt/provide-access/license/v2"):
                return reply(#"{"token":"test-grazie-jwt"}"#)
            case ("api.jetbrains.ai", "/user/v5/quota/get"): return reply(licenseQuota)
            case ("api.jetbrains.ai", "/quota/api/quota/get"): return reply(seatQuota)
            case ("api.jetbrains.ai", "/user/v5/quota/metadata/refill"), ("api.jetbrains.ai", "/quota/api/quota/refill"):
                return refill
            default: return reply("", status: 404)
            }
        }
    }

    static func login(expiresIn seconds: TimeInterval = 3600) -> AccountCredentials {
        var login = AccountCredentials(accessToken: "test-access", refreshToken: "test-refresh",
                                       expiresAt: now.addingTimeInterval(seconds), accountName: nil, accountID: nil)
        login.idToken = "test-id-token"
        return login
    }

    private func read(_ server: Server, login: AccountCredentials = login(),
                      keep: @escaping @Sendable (AccountCredentials) -> Void = { _ in }) async -> ProviderUsage {
        await JetBrainsAIOnlineQuota.usage(login: login, context: context, now: Self.now, send: server.send, keep: keep)
    }

    // MARK: - Sign-in requests

    @Test("The authorize URL is the Junie CLI's, with PKCE and a path-less loopback redirect")
    func authorizeURL() throws {
        let url = try #require(JetBrainsLogin.authorizeURL(
            redirect: JetBrainsLogin.redirect(port: 62345), challenge: "test-challenge", state: "test-state"))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "junie.jetbrains.com")
        #expect(parts.path == "/cli-auth")
        let items = parts.queryItems ?? []
        #expect(items.map(\.name) == ["client_id", "scope", "state", "code_challenge", "code_challenge_method", "redirect_uri"])
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(values["client_id"] == "junie-cli")
        #expect(values["scope"] == "offline_access openid jb-authn-service")
        #expect(values["code_challenge_method"] == "S256")
        #expect(values["redirect_uri"] == "http://localhost:62345")
        #expect(JetBrainsLogin.ports == 62345...62364)
    }

    @Test("A token request is a form post to the JetBrains Account token endpoint")
    func tokenRequest() {
        let request = JetBrainsLogin.tokenRequest([("grant_type", "authorization_code"), ("redirect_uri", "http://localhost:62345")])
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://oauth.account.jetbrains.com/oauth2/token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            == "grant_type=authorization_code&redirect_uri=http%3A%2F%2Flocalhost%3A62345")
    }

    @Test("A token reply keeps the ID token and names the account by its email")
    func tokenReply() throws {
        let payload = Data(#"{"sub":"jb-user","email":"sam@example.com"}"#.utf8).base64URLEncoded
        let idToken = "eyJhbGciOiJub25lIn0.\(payload).sig"
        let json: [String: Any] = ["access_token": "ja", "refresh_token": "jr", "expires_in": 3600, "id_token": idToken]
        let login = try #require(JetBrainsLogin.credentials(from: json, previous: nil, now: Self.now))
        #expect(login.accessToken == "ja")
        #expect(login.refreshToken == "jr")
        #expect(login.idToken == idToken)
        #expect(login.accountName == "sam@example.com")
        #expect(login.expiresAt == Self.now.addingTimeInterval(3600))
        // A first sign-in without a refresh token, or without a lifetime, is no login.
        #expect(JetBrainsLogin.credentials(from: ["access_token": "ja", "expires_in": 3600], previous: nil) == nil)
        #expect(JetBrainsLogin.credentials(from: ["access_token": "ja", "refresh_token": "jr"], previous: nil) == nil)
    }

    @Test("A renewal sends three fields and keeps what the reply leaves out")
    func renewal() async throws {
        let server = Self.server()
        let old = Self.login(expiresIn: -10)
        let renewed = try await JetBrainsLogin.refresh(old, send: server.send)
        let request = try #require(server.requests.first)
        #expect(Self.form(request).map(\.0) == ["grant_type", "refresh_token", "client_id"])
        #expect(Self.formValue(request, "client_id") == "junie-cli")
        #expect(renewed.accessToken == "renewed-access")
        #expect(renewed.refreshToken == "test-refresh")
        #expect(renewed.idToken == "renewed-id")
        #expect(renewed.signIn == old.signIn)
    }

    // MARK: - Reading

    @Test("One window per enabled licence and seat, the fullest first")
    func licenseAndSeat() async throws {
        let server = Self.server()
        let usage = await read(server)

        #expect(usage.state == .live)
        #expect(usage.windows.map(\.usedFraction) == [0.25, 1187.525 / 1_000_000.0])
        #expect(usage.windows.map(\.scope) == ["Example Workspace", "JetBrains AI Pro"])
        #expect(usage.windows.allSatisfy { $0.id.hasPrefix("jetbrains.quota.") && !$0.id.contains("test-") })
        #expect(usage.plan == nil)
    }

    @Test("Each step is asked as the Junie CLI and the IDE ask")
    func requests() async throws {
        let server = Self.server()
        _ = await read(server)
        let requests = server.requests

        let switched = try #require(requests.first)
        #expect(Self.form(switched).map(\.0) == ["grant_type", "refresh_token", "audience", "client_id"])
        #expect(Self.formValue(switched, "grant_type") == "switch_audience")
        #expect(Self.formValue(switched, "audience") == "jcp-user-management")

        let options = try #require(requests.first { $0.url?.path == "/user-management/api/ai-access-options" })
        #expect(options.value(forHTTPHeaderField: "Authorization") == "Bearer test-jcp-token")

        let access = try #require(requests.first { $0.url?.path == "/auth/jetbrains-jwt/provide-access/license/v2" })
        #expect(access.httpMethod == "POST")
        #expect(access.value(forHTTPHeaderField: "Authorization") == "Bearer test-id-token")
        #expect(String(decoding: access.httpBody ?? Data(), as: UTF8.self) == #"{"licenseId":"test-license-id"}"#)
        #expect(!requests.contains { String(decoding: $0.httpBody ?? Data(), as: UTF8.self).contains("test-disabled-license-id") })

        for path in ["/user/v5/quota/get", "/user/v5/quota/metadata/refill"] {
            let quota = try #require(requests.first { $0.url?.path == path })
            #expect(quota.httpMethod == "POST")
            #expect(quota.value(forHTTPHeaderField: "Grazie-Authenticate-JWT") == "test-grazie-jwt")
            #expect(quota.value(forHTTPHeaderField: "Grazie-Agent") != nil)
            #expect(quota.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(String(decoding: quota.httpBody ?? Data(), as: UTF8.self) == "{}")
        }

        let seat = try #require(requests.first { Self.formValue($0, "audience") == "ai-access" })
        #expect(Self.formValue(seat, "org_id") == "test-org-id")
        #expect(Self.formValue(seat, "workspace_id") == "test-workspace-id")
        #expect(Self.formValue(seat, "orgs_user_info") == "test-orgs-header.test-orgs-payload.test-orgs-signature")
        for path in ["/quota/api/quota/get", "/quota/api/quota/refill"] {
            let quota = try #require(requests.first { $0.url?.path == path })
            #expect(quota.httpMethod == "GET")
            #expect(quota.value(forHTTPHeaderField: "Authorization") == "Bearer test-seat-token")
        }
    }

    @Test("A refused seat token is asked once more without the organisation")
    func seatRetry() async {
        let server = Self.server(seatAccepts: { form in !form.contains { $0.0 == "org_id" } })
        let usage = await read(server)
        let seats = server.requests.filter { Self.formValue($0, "audience") == "ai-access" }
        #expect(seats.map { Self.formValue($0, "org_id") != nil } == [true, false])
        #expect(usage.windows.count == 2)
    }

    @Test("A single licence is read as the file is: its refill, its stated period, its product")
    func singleLicense() async throws {
        let usage = await read(Self.server(options: Self.licenseOnly))
        let window = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(window.id == "jetbrains.quota")
        #expect(window.scope == nil)
        #expect(window.kind == .other(seconds: 2_592_000))
        #expect(window.reportsLength)
        // The refill's `next`, not the quota's `until`.
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_777_593_600))
        #expect(usage.plan == "JetBrains AI Pro")
    }

    @Test("A quota without a usable maximum or amount draws nothing", arguments: [
        #"{"current": {"current": {"amount": "5"}, "maximum": {"amount": "0"}}}"#,
        #"{"current": {"current": {"amount": "5"}}}"#,
        #"{"current": {"maximum": {"amount": "100"}}}"#,
        #"{"current": {"current": {"amount": "-1"}, "maximum": {"amount": "100"}}}"#,
        #"{}"#,
    ])
    func missingFigures(quota: String) async {
        let usage = await read(Self.server(options: Self.licenseOnly, licenseQuota: quota))
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("Without a refill the quota stays, with no reset and no length claimed")
    func noRefill() async throws {
        let usage = await read(Self.server(options: Self.licenseOnly, refill: Self.reply("", status: 500)))
        let window = try #require(usage.windows.first)
        #expect(window.resetsAt == nil)
        #expect(window.kind == .credits)
        #expect(!window.reportsLength)
    }

    @Test("Top-up credits count in the whole quota, as the file's figures do")
    func topUpOnly() async throws {
        let quota = """
        {"current": {"current": {"amount": "100000"}, "maximum": {"amount": "500000"},
         "tariffQuota": {"current": {"amount": "0"}, "maximum": {"amount": "0"}},
         "topUpQuota": {"current": {"amount": "100000"}, "maximum": {"amount": "500000"}}}}
        """
        let usage = await read(Self.server(options: Self.licenseOnly, licenseQuota: quota))
        #expect(usage.windows.map(\.usedFraction) == [0.2])
        #expect(JetBrainsAIOnlineQuota.amount(["amount": "1187.525"]) == 1187.525)
        #expect(JetBrainsAIOnlineQuota.amount(12.5) == 12.5)
    }

    @Test("No enabled licence or seat is an account without a plan")
    func noOptions() async {
        let options = #"{"aiAccessOptions": [{"type": "license", "aiAccessEnabled": false, "licenseId": "x"}]}"#
        #expect(await read(Self.server(options: options)).state == .unavailable(.noPlan))
        #expect(await read(Self.server(options: #"{"other": []}"#)).state == .unavailable(.unreadableReply))
    }

    @Test("A refused login is signed out, and the network failing is not")
    func refusals() async {
        let refused = Self.server(userManagement: Self.reply(#"{"error":"invalid_grant"}"#, status: 400))
        #expect(await read(refused).state == .unavailable(.signedOut))
        let down = Self.server(userManagement: Self.reply("", status: 503))
        #expect(await read(down).state == .unavailable(.serverError))
    }

    @Test("A login close to expiry is renewed first, and the renewal kept")
    func renewsFirst() async {
        let server = Self.server(options: Self.licenseOnly)
        let kept = Kept()
        let usage = await read(server, login: Self.login(expiresIn: 30), keep: { kept.set($0) })
        #expect(Self.formValue(server.requests[0], "grant_type") == "refresh_token")
        #expect(kept.value?.accessToken == "renewed-access")
        #expect(usage.state == .live)
        // The licence is asked with the renewed ID token.
        let access = server.requests.first { $0.url?.path == "/auth/jetbrains-jwt/provide-access/license/v2" }
        #expect(access?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-id")
    }

    @Test("A renewal the token endpoint refuses is signed out and keeps nothing")
    func renewalRefused() async {
        let server = Self.server()
        server.answer = { _ in Self.reply(#"{"error":"invalid_grant"}"#, status: 400) }
        let kept = Kept()
        let usage = await read(server, login: Self.login(expiresIn: -1), keep: { kept.set($0) })
        #expect(usage.state == .unavailable(.signedOut))
        #expect(kept.value == nil)
    }

    final class Kept: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: AccountCredentials?
        func set(_ value: AccountCredentials) { lock.withLock { stored = value } }
        var value: AccountCredentials? { lock.withLock { stored } }
    }

    // MARK: - Route order

    private func local(_ usage: ProviderUsage.State) -> ProviderUsage {
        switch usage {
        case .unavailable(let reason): return context.unavailable(reason)
        default:
            let window = JetBrainsAIOnlineQuota.window(.init(used: 1, maximum: 10, resetsAt: nil, seconds: nil),
                                                       id: "jetbrains.quota", scope: nil)
            return context.reading([window])
        }
    }

    private func route(local: ProviderUsage, stored: AccountCredentialStore.StoredLogin) async -> (ProviderUsage, Bool) {
        let asked = Kept()
        let usage = await JetBrainsAIUsageService.choose(local: local, storedLogin: stored, context: context) { login, context in
            asked.set(login)
            return context.unavailable(.signedOut)
        }
        return (usage, asked.value != nil)
    }

    @Test("A real quota in the IDE's file wins, and nothing is sent")
    func fileWins() async {
        let (usage, asked) = await route(local: local(.live), stored: .login(Self.login()))
        #expect(usage.state == .live)
        #expect(!asked)
    }

    @Test("A file whose quota has already reset does not keep a signed-in account off the network")
    func staleFileAsksOnline() async {
        let past = JetBrainsAIOnlineQuota.window(.init(used: 1, maximum: 10, resetsAt: Date(timeIntervalSinceNow: -3_600), seconds: nil),
                                                 id: "jetbrains.quota", scope: nil)
        let stale = context.reading([past])
        let (signedIn, asked) = await route(local: stale, stored: .login(Self.login()))
        #expect(asked)
        #expect(signedIn.state == .unavailable(.signedOut))
        // Signed out, the file is still all there is.
        let (alone, askedAlone) = await route(local: stale, stored: .none)
        #expect(!askedAlone)
        #expect(alone.state == .live)
    }

    @Test("An unsaved file with a login asks JetBrains, and its refusal is not papered over")
    func unsavedAsksOnline() async {
        let (usage, asked) = await route(local: local(.unavailable(.localQuotaUnsaved)), stored: .login(Self.login()))
        #expect(asked)
        #expect(usage.state == .unavailable(.signedOut))
    }

    @Test("Without a login the file's own reason stands; an unreadable store is signed out")
    func withoutLogin() async {
        let (none, asked) = await route(local: local(.unavailable(.localQuotaUnsaved)), stored: .none)
        #expect(none.state == .unavailable(.localQuotaUnsaved))
        #expect(!asked)
        let (unreadable, _) = await route(local: local(.unavailable(.localAppMissing)), stored: .unreadable)
        #expect(unreadable.state == .unavailable(.signedOut))
    }

    @Test("The IDE saving no quota offers the sign-in; other providers keep setup help")
    func remedy() {
        #expect(ConnectionRemedy.forReason(.localQuotaUnsaved, account: AccountKey(.jetBrainsAI)) == .firstSignIn)
        #expect(ConnectionRemedy.forReason(.signedOut, account: AccountKey(.jetBrainsAI)) == .signIn)
        #expect(ConnectionRemedy.forReason(.localQuotaUnsaved, account: AccountKey(.gemini)) == .help)
        #expect(ProviderSignInModel.primarySignIns.contains(.jetBrainsAI))
    }

    // MARK: - Storage and redaction

    @Test("The login is kept under the provider's own key, and older logins decode without an ID token")
    func storage() throws {
        #expect(JetBrainsLogin.account == AccountKey(.jetBrainsAI))
        let old = #"{"accessToken":"a","refreshToken":"r","expiresAt":0}"#
        let decoded = try JSONDecoder().decode(AccountCredentials.self, from: Data(old.utf8))
        #expect(decoded.idToken == nil)
        let roundTrip = try JSONDecoder().decode(AccountCredentials.self, from: JSONEncoder().encode(Self.login()))
        #expect(roundTrip.idToken == "test-id-token")
        // A renewal never lands in an emptied slot, so signing out stays signed out.
        #expect(!AccountCredentialStore.acceptsRenewal(Self.login(), over: nil))
    }

    @Test("The diagnostics mask the JetBrains AI token wherever a reply repeats it")
    func diagnosticsMask() {
        let request = JetBrainsAIOnlineQuota.licenseQuotaRequests(grazieToken: "test-grazie-jwt-value").quota
        #expect(ResponseLog.credentials(in: request).contains("test-grazie-jwt-value"))
    }

    @Test("The signed list of organisations is the first JWT-shaped text in the reply")
    func signedList() {
        #expect(JetBrainsAIOnlineQuota.signedList(in: #"{"jwt":"aaaaaaaa.bbbbbbbb.cc"}"#) == "aaaaaaaa.bbbbbbbb.cc")
        #expect(JetBrainsAIOnlineQuota.signedList(in: #"{"jwt":null}"#) == nil)
    }
}
