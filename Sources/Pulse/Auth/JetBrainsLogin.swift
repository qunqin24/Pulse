// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import CryptoKit
import Foundation

/// Signing Pulse in to a JetBrains Account, for JetBrains AI's quota when the
/// IDE no longer saves it on this Mac (IDEs from 2026.3 on, #122).
///
/// **The client is the Junie CLI's**, which JetBrains ships publicly:
/// `junie-cli`, its browser page `junie.jetbrains.com/cli-auth`, and the
/// JetBrains Account token endpoint. Pulse cannot register a client of its
/// own, so the consent page names Junie, not Pulse — the same bargain every
/// other sign-in here makes (`OAuthLogin`).
///
/// Every value below is taken from rock3r/headroom (Apache-2.0),
/// `core/auth/src/commonMain/kotlin/dev/sebastiano/headroom/auth/JetBrainsOAuth.kt`
/// at commit 9a2851d, which signs in the same way and says the values are the
/// Junie CLI's. None was read out of a JetBrains binary, and none has been
/// tried against a live account from Pulse.
///
/// - Authorize: `GET https://junie.jetbrains.com/cli-auth` with `client_id`,
///   `scope`, `state`, `code_challenge`, `code_challenge_method=S256` and
///   `redirect_uri`, in that order, and **no** `response_type`.
/// - Redirect: `http://localhost:<port>` with no path, on one of the ports
///   62345…62364 — the client is registered for those and no others.
/// - Exchange and renewal: a form post to
///   `https://oauth.account.jetbrains.com/oauth2/token`, the four
///   specification fields plus the verifier; a renewal sends `grant_type`,
///   `refresh_token` and `client_id` and nothing else.
///
/// Nothing here reads or writes the IDE's own login, the Keychain, or any
/// IDE file. The tokens are Pulse's, kept in `accounts.dat` under
/// `AccountKey(.jetBrainsAI)`.
enum JetBrainsLogin {
    static let clientID = "junie-cli"
    static let authorizeEndpoint = URL(string: "https://junie.jetbrains.com/cli-auth")!
    static let tokenEndpoint = URL(string: "https://oauth.account.jetbrains.com/oauth2/token")!
    /// `openid` for the ID token the licence route is asked with,
    /// `offline_access` for the refresh token the audience switches use,
    /// `jb-authn-service` as the Junie CLI asks. headroom's set, unchanged.
    static let scopes = "offline_access openid jb-authn-service"
    static let ports: ClosedRange<UInt16> = 62345...62364

    static var account: AccountKey { AccountKey(.jetBrainsAI) }

    /// The request a reply is fetched with. `ProfileHTTP.reply` in the app:
    /// the shared session, the proxy setting, redirects refused, and the
    /// reply kept for the diagnostics when a check is running.
    typealias Send = @Sendable (URLRequest) async -> Result<ProfileHTTP.Reply, ProviderUsage.Unavailability>

    static let liveSend: Send = { await ProfileHTTP.reply(for: $0) }

    static func redirect(port: UInt16) -> String { "http://localhost:\(port)" }

    static func authorizeURL(redirect: String, challenge: String, state: String) -> URL? {
        guard var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "redirect_uri", value: redirect),
        ]
        return components.url
    }

    /// A form post to the token endpoint, fields in the order given.
    static func tokenRequest(_ form: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(form.map { "\($0.0)=\(OAuthLogin.formEncoded($0.1))" }.joined(separator: "&").utf8)
        return request
    }

    // MARK: - Signing in

    /// Opens the Junie CLI's sign-in page and waits for the browser to come
    /// back to this Mac. Storing the login is the caller's business.
    static func signIn(send: Send = liveSend) async throws -> AccountCredentials {
        let verifier = OAuthLogin.randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = OAuthLogin.randomToken()

        let (listener, port) = try await bind(expecting: state)
        defer { listener.stop() }

        let redirect = redirect(port: port)
        guard let url = authorizeURL(redirect: redirect, challenge: challenge, state: state) else {
            throw OAuthLogin.Failure.unsupported
        }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }

        let code = try await listener.awaitCode(giveUpAfter: OAuthLogin.patience)
        return try await tokens([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirect),
            ("client_id", clientID),
            ("code_verifier", verifier),
        ], previous: nil, send: send)
    }

    /// The first free port of the twenty the client accepts. One taken —
    /// by the Junie CLI's own sign-in, say — moves on to the next; all of
    /// them taken is the same "finish the other sign-in" as a fixed port.
    private static func bind(expecting state: String) async throws -> (LoopbackCallback, UInt16) {
        for port in ports {
            try Task.checkCancellation()
            guard let listener = try? LoopbackCallback(port: port, path: "/") else { continue }
            do {
                try await listener.start(expecting: state)
                return (listener, port)
            } catch is CancellationError {
                listener.stop()
                throw CancellationError()
            } catch {
                listener.stop()
            }
        }
        throw OAuthLogin.Failure.portBusy(ports.lowerBound)
    }

    // MARK: - Renewal

    /// A fresh access token (and ID token, when the reply has one) from the
    /// refresh token. A refresh token or ID token the reply leaves out stays
    /// as it was, as headroom does.
    static func refresh(_ login: AccountCredentials, send: Send = liveSend) async throws -> AccountCredentials {
        let renewed = try await tokens([
            ("grant_type", "refresh_token"),
            ("refresh_token", login.refreshToken),
            ("client_id", clientID),
        ], previous: login, send: send)
        return login.renewalOf(renewed)
    }

    /// Posts `form` and reads the tokens. Fails with the cases
    /// `LiveUsageServices.renewalFailure` tells apart: no answer, a status
    /// other than 200, an unreadable reply.
    private static func tokens(
        _ form: [(String, String)],
        previous: AccountCredentials?,
        send: Send
    ) async throws -> AccountCredentials {
        let reply: ProfileHTTP.Reply
        switch await send(tokenRequest(form)) {
        case .failure: throw OAuthLogin.Failure.unreachable
        case .success(let answered): reply = answered
        }
        try Task.checkCancellation()
        let json = (try? JSONSerialization.jsonObject(with: reply.data)) as? [String: Any]
        guard reply.status == 200 else {
            let said = (json?["error_description"] as? String) ?? (json?["error"] as? String)
            throw OAuthLogin.Failure.rejected(
                status: reply.status,
                detail: said.map { "oauth2/token: HTTP \(reply.status) — \($0)" } ?? "oauth2/token: HTTP \(reply.status)"
            )
        }
        guard let json, let parsed = credentials(from: json, previous: previous) else {
            throw OAuthLogin.Failure.unreadableReply
        }
        return parsed
    }

    /// A token reply as a login, or nil when it is not one. A first sign-in
    /// must carry a refresh token; a renewal may leave it out.
    static func credentials(from json: [String: Any], previous: AccountCredentials?, now: Date = Date()) -> AccountCredentials? {
        guard let access = json["access_token"] as? String, !access.isEmpty,
              let lifetime = (json["expires_in"] as? NSNumber)?.doubleValue, lifetime > 0
        else { return nil }
        let refresh = (json["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? previous?.refreshToken
        guard let refresh else { return nil }
        let idToken = (json["id_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let email = idToken.flatMap(OAuthLogin.claims(inJWT:))?["email"] as? String
        var login = AccountCredentials(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: now.addingTimeInterval(lifetime),
            accountName: email ?? previous?.accountName,
            accountID: nil
        )
        login.idToken = idToken ?? previous?.idToken
        return login
    }
}
