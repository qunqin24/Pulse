import AppKit
import CryptoKit
import Foundation

/// Signing Pulse in to a second Cursor account, which is what a second Grok
/// Bot allowance is.
///
/// **This is not OAuth, and calling it that would set the wrong expectations.**
/// Cursor has no authorize/token pair for a third party to drive — it has a
/// login page that takes a challenge and a nonce, and a polling endpoint that
/// hands the tokens back once the browser has finished:
///
/// 1. `GET cursor.com/loginDeepControl?challenge=…&uuid=…&mode=login&…` opens
///    in the browser. Nothing comes back to this Mac, so there is no loopback
///    port to bind and none to collide with Cursor's own sign-in.
/// 2. `GET api2.cursor.sh/auth/poll?uuid=…&verifier=…` answers 404 while the
///    browser has not finished and 200 with `accessToken` / `refreshToken`
///    once it has.
///
/// The proof-key half *is* PKCE's: a random 32 bytes base64url-encoded is the
/// verifier, and the challenge is the base64url of its SHA-256 — of the
/// **encoded string**, not of the raw bytes. Read out of Cursor's own client
/// (`Grok Bot.app/Contents/Resources/app.asar`) rather than guessed, for the
/// reason `OAuthLogin` states: a flow with one parameter wrong fails in a way
/// that looks like the user's fault.
///
/// **Not public API**, the same caveat every other borrowed route carries.
enum CursorWebLogin {
    /// What the user is sent to, and what the poll needs afterwards.
    struct Attempt: Sendable, Equatable {
        let loginURL: URL
        let uuid: String
        let verifier: String
    }

    private static let website = URL(string: "https://cursor.com")!
    private static let backend = URL(string: "https://api2.cursor.sh")!

    /// How long to keep asking. Cursor's own client gives up after 150 tries;
    /// this is the same order and matches `OAuthLogin.patience`'s reasoning —
    /// long enough to find a password and a second factor, short enough that
    /// an abandoned sign-in releases the button.
    private static let patience: TimeInterval = 300
    private static let interval: Duration = .seconds(2)

    static func start() -> Attempt? {
        let verifier = OAuthLogin.randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let uuid = UUID().uuidString.lowercased()

        guard var components = URLComponents(
            url: website.appending(path: "loginDeepControl"),
            resolvingAgainstBaseURL: false
        ) else { return nil }

        components.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "mode", value: "login"),
            // What the page says it is signing in to. "sand" is Cursor's own
            // name for Grok Bot, and it is the one this account is for.
            URLQueryItem(name: "redirectTarget", value: "sand"),
            URLQueryItem(name: "supportsSelectedTeamLogin", value: "true"),
        ]

        guard let url = components.url else { return nil }
        return Attempt(loginURL: url, uuid: uuid, verifier: verifier)
    }

    /// Opens the page and waits for the browser to finish with it.
    static func signIn() async throws -> AccountCredentials {
        guard let attempt = start() else { throw OAuthLogin.Failure.unsupported }

        _ = await MainActor.run { NSWorkspace.shared.open(attempt.loginURL) }

        let deadline = Date().addingTimeInterval(patience)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: interval)

            if let credentials = try await poll(attempt) { return credentials }
        }

        throw OAuthLogin.Failure.timedOut
    }

    /// Nil while the browser has not finished.
    ///
    /// **404 is "not yet", not "wrong address"** — the nonce simply has nothing
    /// filed against it until the page completes, and Cursor's own client
    /// treats that status as a reason to ask again. A 403 carrying an error is
    /// the one refusal that ends the attempt; every other failure is a stumble
    /// and is retried, because this poll runs for minutes and one dropped
    /// connection is not a reason to send the user back to the start.
    private static func poll(_ attempt: Attempt) async throws -> AccountCredentials? {
        guard var components = URLComponents(
            url: backend.appending(path: "auth/poll"),
            resolvingAgainstBaseURL: false
        ) else { throw OAuthLogin.Failure.unsupported }

        components.queryItems = [
            URLQueryItem(name: "uuid", value: attempt.uuid),
            URLQueryItem(name: "verifier", value: attempt.verifier),
        ]
        guard let url = components.url else { throw OAuthLogin.Failure.unsupported }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Cancellation is not the service failing to answer — reported as
            // one, pressing Cancel writes an error into a pane the user has
            // just cleared on purpose.
            if error is CancellationError { throw error }
            try Task.checkCancellation()
            return nil
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if status == 403, let said = json?["error"] as? String {
            throw OAuthLogin.Failure.refused("auth/poll: \(said)")
        }
        guard status == 200 else { return nil }

        guard
            let access = json?["accessToken"] as? String,
            let refresh = json?["refreshToken"] as? String
        else { throw OAuthLogin.Failure.unreadableReply }

        // The reply states no lifetime, and does not need to: the token says
        // so itself, and Cursor issues these for sixty days.
        guard let expiry = CursorAppLogin.expiry(of: access) else {
            throw OAuthLogin.Failure.unreadableReply
        }

        return AccountCredentials(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiry,
            // The token carries no email, so there is nothing here to name the
            // account with — it gets a number, and the name is the user's to
            // change in Settings like any other.
            accountName: nil,
            accountID: nil
        )
    }
}
