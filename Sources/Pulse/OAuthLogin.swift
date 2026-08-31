import AppKit
import CryptoKit
import Foundation
import Network

/// Signing Pulse in to one account of a provider, so it can watch more than
/// one subscription at a time.
///
/// **Pulse cannot register an OAuth application of its own with either
/// provider** — neither offers that — so it drives the same public client the
/// provider's own CLI uses, with the same authorize and token endpoints. Two
/// consequences worth being clear about, both of them stated in Settings
/// before anyone signs in: the consent page names the CLI rather than Pulse,
/// and this is not an official integration, so either provider can change or
/// withdraw it.
///
/// What it is *not* is a way to disturb the CLI's own login. The tokens
/// obtained here are Pulse's, kept in `AccountCredentialStore` and renewed
/// from Pulse's own refresh token; nothing here reads or writes what the CLI
/// stored. That separation is the reason for signing in at all rather than
/// copying the credential the CLI already has — copied, it would expire in
/// hours with no way to renew it that did not risk invalidating the CLI's.
enum OAuthLogin {
    struct Configuration: Sendable {
        let authorize: URL
        let token: URL
        let clientID: String
        let scopes: [String]
        /// A port the provider's client is registered for, when it insists on
        /// one; nil takes any free port, which is what a public client that
        /// accepts arbitrary loopback redirects allows.
        let fixedPort: UInt16?
        let redirectPath: String
        let extraAuthorizeItems: [URLQueryItem]
        /// Anthropic's token endpoint takes JSON; OpenAI's takes a form, which
        /// is what the specification asks for. Neither accepts the other.
        let sendsJSON: Bool
        /// Anthropic's exchange carries the `state` back; OpenAI's is the four
        /// fields the specification names and nothing else. Sending one an
        /// extra field is not harmless — see the note on the scopes.
        let exchangeCarriesState: Bool
        /// Codex offers a device-code flow, and it is the better one to take:
        /// no local port to collide with the CLI's own sign-in, no redirect
        /// back to this Mac at all, and the provider generates the proof key
        /// itself. It is also the path that works — the redirect flow, matched
        /// field for field to the published client, still ended on OpenAI's
        /// own error page.
        let deviceCodeBase: URL?

        static func of(_ provider: Provider) -> Configuration? {
            switch provider {
            case .claudeCode:
                // Read out of the installed CLI rather than remembered: an
                // OAuth flow with one parameter wrong fails in a way that
                // looks like the user's fault.
                Configuration(
                    authorize: URL(string: "https://claude.com/cai/oauth/authorize")!,
                    token: URL(string: "https://platform.claude.com/v1/oauth/token")!,
                    clientID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
                    // The narrowest set that can read an account's limits. The
                    // CLI asks for inference and session scopes as well, which
                    // would let Pulse *spend* the plan it is only supposed to
                    // be reporting on.
                    scopes: ["user:profile"],
                    fixedPort: nil,
                    redirectPath: "/callback",
                    extraAuthorizeItems: [URLQueryItem(name: "code", value: "true")],
                    sendsJSON: true,
                    exchangeCarriesState: true,
                    deviceCodeBase: nil
                )
            case .codex:
                Configuration(
                    authorize: URL(string: "https://auth.openai.com/oauth/authorize")!,
                    token: URL(string: "https://auth.openai.com/oauth/token")!,
                    clientID: "app_EMoamEEZ73f0CkXaXp7hrann",
                    // The full set its own client asks for. A subset looked
                    // like good practice and is not on offer here: the sign-in
                    // ended on OpenAI's error page before the browser ever came
                    // back. Taken from codex-rs/login/src/server.rs.
                    scopes: ["openid", "profile", "email", "offline_access",
                             "api.connectors.read", "api.connectors.invoke"],
                    // Not negotiable: this client is registered for exactly
                    // this loopback address, so the port has to be free.
                    fixedPort: 1455,
                    redirectPath: "/auth/callback",
                    extraAuthorizeItems: [
                        URLQueryItem(name: "id_token_add_organizations", value: "true"),
                        URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
                        URLQueryItem(name: "originator", value: "codex_cli_rs"),
                    ],
                    sendsJSON: false,
                    exchangeCarriesState: false,
                    deviceCodeBase: URL(string: "https://auth.openai.com/api/accounts")!
                )
            case .antigravity, .cursor, .openCodeGo, .kimiCode:
                nil
            }
        }
    }

    /// How long to hold the callback open. Long enough to find a password and
    /// a second factor, short enough that a sign-in abandoned in the browser
    /// — or one the provider ended on an error page of its own, which never
    /// comes back here at all — releases the button instead of waiting for
    /// ever.
    static let patience: Duration = .seconds(300)

    enum Failure: Error, Equatable {
        /// This provider has no login Pulse can drive.
        case unsupported
        /// The one port the provider's client accepts is already in use —
        /// usually by the CLI's own sign-in, running at the same moment.
        case portBusy(UInt16)
        case cancelled
        /// The browser never came back. Usually the sign-in was abandoned, or
        /// it ended on the provider's own error page.
        case timedOut
        case refused(String)
        case unreadableReply

        var message: String {
            switch self {
            case .unsupported: .localized("This provider can't be signed in to from Pulse.")
            case .portBusy: .localized("Finish or close the sign-in already running, then try again.")
            case .cancelled: .localized("Sign-in was cancelled.")
            case .timedOut: .localized("The browser didn't come back. If it showed an error, try again.")
            case .refused(let why): why
            case .unreadableReply: .localized("Couldn't read the reply.")
            }
        }
    }

    /// What to put in front of the user while a device-code sign-in is
    /// waiting: a short code, and where to type it.
    struct DevicePrompt: Sendable, Equatable {
        let userCode: String
        let verificationURL: URL
        let deviceAuthID: String
        let interval: Duration
    }

    // MARK: - Device code

    /// Asks the provider for a code to show the user.
    static func startDevice(_ provider: Provider) async throws -> DevicePrompt {
        guard
            let configuration = Configuration.of(provider),
            let base = configuration.deviceCodeBase
        else { throw Failure.unsupported }

        let reply = try await postJSON(
            ["client_id": configuration.clientID],
            to: base.appending(path: "deviceauth/usercode")
        )

        guard
            let code = (reply["user_code"] as? String) ?? (reply["usercode"] as? String),
            let id = reply["device_auth_id"] as? String
        else { throw Failure.unreadableReply }

        // The reply states how often to ask; a provider that says nothing gets
        // the five seconds its own client falls back to.
        let seconds = (reply["interval"] as? Double)
            ?? (reply["interval"] as? String).flatMap(Double.init)
            ?? 5

        return DevicePrompt(
            userCode: code,
            verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
            deviceAuthID: id,
            interval: .seconds(max(seconds, 1))
        )
    }

    /// Waits for the user to enter that code, then turns what comes back into
    /// tokens.
    ///
    /// The provider generates the proof key for this flow and hands both
    /// halves back with the authorization code, so there is none to make here
    /// — which is also why the redirect address is one of *theirs*.
    static func awaitDevice(_ prompt: DevicePrompt, for provider: Provider) async throws -> AccountCredentials {
        guard
            let configuration = Configuration.of(provider),
            let base = configuration.deviceCodeBase
        else { throw Failure.unsupported }

        let deadline = Date().addingTimeInterval(15 * 60)
        let url = base.appending(path: "deviceauth/token")

        while Date() < deadline {
            try Task.checkCancellation()
            let body = ["device_auth_id": prompt.deviceAuthID, "user_code": prompt.userCode]
            if let granted = try await pollDevice(body, at: url) {
                return try await post([
                    "grant_type": "authorization_code",
                    "code": granted.code,
                    "redirect_uri": "https://auth.openai.com/deviceauth/callback",
                    "client_id": configuration.clientID,
                    "code_verifier": granted.verifier,
                ], to: configuration)
            }
            try await Task.sleep(for: prompt.interval)
        }

        throw Failure.timedOut
    }

    /// Nil while the user has not finished; the code and its verifier once
    /// they have. Still-waiting is a 403 or a 404 here, which is the provider's
    /// own convention rather than the specification's `authorization_pending`.
    private static func pollDevice(_ body: [String: String], at url: URL) async throws -> (code: String, verifier: String)? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            throw Failure.refused(String.localized("The service didn't respond."))
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || status == 404 { return nil }
        guard status == 200 else { throw Failure.refused(described(status, data, step: "deviceauth/token")) }

        guard
            let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = reply["authorization_code"] as? String,
            let verifier = reply["code_verifier"] as? String
        else { throw Failure.unreadableReply }

        return (code, verifier)
    }

    private static func postJSON(_ body: [String: String], to url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            throw Failure.refused(String.localized("The service didn't respond."))
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.refused(described(status, data, step: url.lastPathComponent)) }
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadableReply
        }
        return reply
    }

    /// A refusal in enough detail to act on: which step, what status, and the
    /// provider's own words when it gave any.
    ///
    /// "The service returned an error" is true of every failure and tells
    /// nobody anything — two sign-in attempts were spent on the strength of it.
    private static func described(_ status: Int, _ data: Data, step: String) -> String {
        var said = ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            said = (json["error_description"] as? String)
                ?? (json["detail"] as? String)
                ?? (json["message"] as? String)
                ?? (json["error"] as? String)
                ?? ""
        }
        if said.isEmpty, let text = String(data: data, encoding: .utf8) {
            said = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).description
        }

        return said.isEmpty ? "\(step): HTTP \(status)" : "\(step): HTTP \(status) — \(said)"
    }

    /// Whether this provider is signed in to by showing a code rather than by
    /// sending the browser back here.
    static func usesDeviceCode(_ provider: Provider) -> Bool {
        Configuration.of(provider)?.deviceCodeBase != nil
    }

    // MARK: - Signing in

    /// Opens the provider's consent page and waits for the browser to come
    /// back. Returns the tokens; storing them is the caller's business.
    static func signIn(to provider: Provider) async throws -> AccountCredentials {
        guard let configuration = Configuration.of(provider) else { throw Failure.unsupported }

        let verifier = randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = randomToken()

        let listener = try LoopbackCallback(port: configuration.fixedPort, path: configuration.redirectPath)
        defer { listener.stop() }

        // Bound first: the port is part of the redirect address, and the
        // redirect address is part of the request the browser is about to be
        // sent to. Both halves of the exchange have to name the same one.
        try await listener.start()
        let redirect = "http://localhost:\(listener.port)\(configuration.redirectPath)"
        guard let url = authorizeURL(configuration, redirect: redirect, challenge: challenge, state: state) else {
            throw Failure.unsupported
        }

        _ = await MainActor.run { NSWorkspace.shared.open(url) }

        let code = try await listener.awaitCode(matching: state, giveUpAfter: Self.patience)
        return try await exchange(code, configuration: configuration, verifier: verifier, redirect: redirect, state: state)
    }

    /// Internal rather than private so the request can be driven directly in
    /// a probe — an OAuth flow with one parameter wrong fails in a way that
    /// looks like the user's fault, so the request is worth being able to read
    /// without performing a sign-in to see it.
    static func authorizeURL(
        _ configuration: Configuration,
        redirect: String,
        challenge: String,
        state: String
    ) -> URL? {
        guard var components = URLComponents(url: configuration.authorize, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.queryItems = configuration.extraAuthorizeItems + [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url
    }

    // MARK: - Tokens

    private static func exchange(
        _ code: String,
        configuration: Configuration,
        verifier: String,
        redirect: String,
        state: String
    ) async throws -> AccountCredentials {
        var body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect,
            "client_id": configuration.clientID,
            "code_verifier": verifier,
        ]
        if configuration.exchangeCarriesState { body["state"] = state }

        return try await post(body, to: configuration)
    }

    /// Renews an account's access token.
    ///
    /// The provider may hand back a new refresh token; when it doesn't, the
    /// old one stays valid and is carried forward. Nothing here touches the
    /// CLI's own stored login, so a renewal cannot sign the user out of it.
    static func refresh(_ credentials: AccountCredentials, for provider: Provider) async throws -> AccountCredentials {
        guard let configuration = Configuration.of(provider) else { throw Failure.unsupported }

        var renewed = try await post([
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id": configuration.clientID,
            "scope": configuration.scopes.joined(separator: " "),
        ], to: configuration)

        if renewed.refreshToken.isEmpty { renewed.refreshToken = credentials.refreshToken }
        renewed.accountName = renewed.accountName ?? credentials.accountName
        renewed.accountID = renewed.accountID ?? credentials.accountID
        return renewed
    }

    private static func post(_ body: [String: String], to configuration: Configuration) async throws -> AccountCredentials {
        var request = URLRequest(url: configuration.token)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        if configuration.sendsJSON {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            // Encoded strictly — `URLComponents` leaves ":" and "/" alone in a
            // query value, which is legal in a URL and wrong in a form body,
            // and it would pass a "+" through to be read back as a space.
            request.httpBody = Data(body.map { "\($0.key)=\(Self.formEncoded($0.value))" }
                .joined(separator: "&").utf8)
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            throw Failure.refused(String.localized("The service didn't respond."))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadableReply
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // The provider's own words when it has them: "invalid_scope" says
            // something a generic failure cannot.
            let said = (json["error_description"] as? String) ?? (json["error"] as? String)
            throw Failure.refused(said.map { "oauth/token: HTTP \(status) — \($0)" } ?? "oauth/token: HTTP \(status)")
        }

        guard
            let access = json["access_token"] as? String,
            let lifetime = json["expires_in"] as? Double
        else { throw Failure.unreadableReply }

        return AccountCredentials(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String ?? "",
            expiresAt: Date().addingTimeInterval(lifetime),
            accountName: accountName(in: json),
            accountID: accountID(in: access)
        )
    }

    /// Everything but the unreserved set, which is what a form body wants and
    /// what the published client does.
    private static func formEncoded(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Whatever the reply says about who this is, so two subscriptions are not
    /// both offered to the user as "Codex". OpenAI returns an id token with an
    /// email in it; Anthropic names the plan.
    private static func accountName(in json: [String: Any]) -> String? {
        if let claims = (json["id_token"] as? String).flatMap(claims(inJWT:)) {
            if let email = claims["email"] as? String, !email.isEmpty { return email }
        }
        if let account = json["account"] as? [String: Any] {
            if let email = account["email_address"] as? String, !email.isEmpty { return email }
        }
        return nil
    }

    /// The account the token was issued for, which Codex's usage endpoint
    /// wants in a header. It is nested in a namespaced claim rather than at
    /// the top level, and only the access token carries it.
    private static func accountID(in accessToken: String) -> String? {
        guard
            let claims = claims(inJWT: accessToken),
            let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        else { return nil }

        return auth["chatgpt_account_id"] as? String
    }

    private static func claims(inJWT token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var encoded = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)

        return (try? Data(base64Encoded: encoded).flatMap {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }) ?? nil
    }

    /// 32 bytes, base64url — comfortably inside the 43…128 characters PKCE
    /// asks of a verifier, and the same generator serves the state.
    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

private extension Data {
    /// Base64 as OAuth wants it: URL-safe, unpadded.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
