import Foundation

/// Signing in to GitHub for Copilot's quota, by device code.
///
/// **A sign-in rather than a pasted token, and that is a security decision.**
/// The endpoint accepts any GitHub OAuth token, so asking someone to paste the
/// one `gh` already holds would work — and that token carries `repo` and
/// `workflow`, which is the run of their source code, handed over to draw a
/// percentage. This asks for `read:user` and nothing else.
///
/// Pulse cannot register an OAuth application with GitHub, so it drives the
/// same public client the VS Code plugin uses — the same bargain the Codex and
/// Claude Code sign-ins make, with the same consequence: the consent page names
/// the editor rather than Pulse, and this is not an official integration.
/// Settings says so.
///
/// The flow is [RFC 8628](https://datatracker.ietf.org/doc/html/rfc8628), which
/// GitHub documents: ask for a code, show it, poll until the browser is done.
/// Nothing is redirected back to this Mac, so there is no local port and
/// nothing to collide with an editor's own sign-in.
enum GitHubDeviceLogin {
    /// The Copilot plugin's public client. Not a secret — it is in every copy
    /// of the extension — and the device flow is designed to be driven without
    /// one.
    private static let clientID = "Iv1.b507a08c87ecfe98"

    /// The narrowest scope the quota endpoint will answer for.
    private static let scope = "read:user"

    private static let codeURL = URL(string: "https://github.com/login/device/code")!
    private static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    /// How long to keep polling before giving up. GitHub's codes last fifteen
    /// minutes; stopping sooner would report a failure while the code on
    /// screen was still good.
    private static let patience: Duration = .seconds(900)

    struct Prompt: Sendable, Equatable {
        let userCode: String
        /// Where to send the browser. **The code is not in it, and must not be.**
        ///
        /// RFC 8628 has a field for a pre-filled address —
        /// `verification_uri_complete` — and GitHub deliberately does not send
        /// one. Its page says why, in as many words: *"Never use a code sent by
        /// someone else"*, and *"GitHub staff will never give you a code to
        /// enter on this page."* Pre-filling is the device-code phishing
        /// attack — an attacker sends a link carrying **their** code, the
        /// victim approves it, and the attacker holds an authorised token for
        /// the victim's account. Typing the code is what makes the person
        /// consent to *this* device rather than to a link they were handed.
        ///
        /// A `user_code` query parameter was tried and is ignored, which is the
        /// right behaviour. It is not put back: it would do nothing except make
        /// Pulse's link the same shape as the attack. The clipboard is the
        /// answer instead — one paste, and the consent still happens where it
        /// should.
        let verificationURL: URL
        let deviceCode: String
        let interval: Duration
    }

    enum Failure: LocalizedError, Equatable {
        case refused(String)
        case declined
        case timedOut

        var errorDescription: String? { message }

        var message: String {
            switch self {
            case .refused(let said): said
            case .declined: String.localized("Sign-in was cancelled.")
            case .timedOut: String.localized("The browser didn't come back.")
            }
        }
    }

    /// Asks GitHub for a code to put on screen.
    static func start() async throws -> Prompt {
        let reply = try await post(codeURL, body: ["client_id": clientID, "scope": scope])

        guard
            let userCode = reply["user_code"] as? String,
            let deviceCode = reply["device_code"] as? String,
            let verification = (reply["verification_uri"] as? String).flatMap(URL.init(string:))
        else { throw Failure.refused(described(reply, step: "login/device/code")) }

        // Their floor, not ours: polling faster than this earns a `slow_down`.
        let seconds = min(max((reply["interval"] as? Int) ?? 5, 1), 60)
        return Prompt(
            userCode: userCode,
            // Only if the service offers one itself. Building it here is the
            // thing the page warns about; being handed one is the service's own
            // decision to make.
            verificationURL: (reply["verification_uri_complete"] as? String).flatMap(URL.init(string:))
                ?? verification,
            deviceCode: deviceCode,
            interval: .seconds(seconds)
        )
    }

    /// Polls until the user has finished in the browser, and returns the token.
    ///
    /// Cancellation unwinds this immediately — `Task.sleep` is cancellable and
    /// the loop checks — so pressing Cancel stops the attempt rather than
    /// leaving it running to write over a later one.
    static func awaitToken(_ prompt: Prompt) async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: patience)
        var wait = prompt.interval

        while ContinuousClock.now < deadline {
            try await Task.sleep(for: wait)
            try Task.checkCancellation()

            let reply = try await post(tokenURL, body: [
                "client_id": clientID,
                "device_code": prompt.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])

            if let token = reply["access_token"] as? String, !token.isEmpty { return token }

            // The specification's own words, which GitHub does use here —
            // unlike the Codex flow, where 403 and 404 stand in for "still
            // waiting".
            switch reply["error"] as? String {
            case "authorization_pending", nil:
                continue
            case "slow_down":
                // Their instruction, and ignoring it gets the attempt refused.
                // Their instruction, within reason: the deadline is only
                // tested at the top of the loop, so an interval taken on trust
                // could park this in a single sleep for longer than the code
                // it is waiting on will live.
                wait = .seconds(min(max((reply["interval"] as? Int) ?? 10, 1), 60))
            case "access_denied":
                throw Failure.declined
            case "expired_token":
                throw Failure.timedOut
            case .some(let error):
                throw Failure.refused(described(reply, step: "login/oauth/access_token", error: error))
            }
        }

        throw Failure.timedOut
    }

    // MARK: - Requests

    private static func post(_ url: URL, body: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Without this GitHub answers form-encoded, which parses as nothing.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Cancelling is not the service failing to answer.
            if error is CancellationError { throw error }
            try Task.checkCancellation()
            throw Failure.refused(String.localized("The service didn't respond."))
        }

        // The status is read before the body: a refusal served as an HTML
        // error page has plenty to say, and parsing first threw all of it away.
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        // A device flow answers 200 while it waits, so only a real failure
        // status is one — and even then the body usually names the reason.
        guard status < 400 else {
            throw Failure.refused(described(json ?? [:], step: url.lastPathComponent, status: status))
        }
        guard let json else { throw Failure.refused(String.localized("Couldn't read the reply.")) }
        return json
    }

    /// GitHub's own words where it has them: "device_flow_disabled" says
    /// something a generic failure cannot.
    private static func described(
        _ reply: [String: Any],
        step: String,
        status: Int? = nil,
        error: String? = nil
    ) -> String {
        let said = (reply["error_description"] as? String)
            ?? error
            ?? (reply["error"] as? String)
        let prefix = status.map { "\(step): HTTP \($0)" } ?? step
        return said.map { "\(prefix) — \($0)" } ?? prefix
    }
}
