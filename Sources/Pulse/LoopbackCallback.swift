import Foundation
import Network

/// The other half of a browser sign-in: a listener on this Mac that the
/// provider redirects back to, carrying the authorization code.
///
/// Loopback only, for one request, and gone the moment it has what it came
/// for. The redirect is the one place in the flow the code passes through
/// something Pulse controls, so it is held for as short a time as possible.
///
/// **Starting is a separate step from waiting, and has to be.** The port is
/// only known once the listener is ready, and the redirect address — which
/// goes into the authorize request, before the browser is even opened — is
/// built from it. Folding the two together produced a redirect to port 0.
final class LoopbackCallback: @unchecked Sendable {
    /// The port actually bound, once `start()` has returned. A provider whose
    /// client is registered for one specific loopback address gets that or
    /// nothing; the rest take whatever is free, which is what the CLIs
    /// themselves do.
    private(set) var port: UInt16 = 0

    private let path: String
    private let requestedPort: UInt16?
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.pulse.oauth-callback")

    private let lock = NSLock()
    private var ready: CheckedContinuation<Void, Error>?
    private var waiting: CheckedContinuation<String, Error>?
    private var expectedState = ""
    private var captured: Result<String, Error>?
    private var settled = false

    init(port fixed: UInt16?, path: String) throws {
        self.path = path
        self.requestedPort = fixed

        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let wanted = fixed.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        guard let listener = try? NWListener(using: parameters, on: wanted) else {
            throw OAuthLogin.Failure.portBusy(fixed ?? 0)
        }
        self.listener = listener
    }

    /// Binds, and returns once the port is known.
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            ready = continuation
            lock.unlock()

            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.port = self.listener.port?.rawValue ?? self.requestedPort ?? 0
                    self.resumeReady(.success(()))
                case .failed, .cancelled:
                    // The one address this provider accepts is taken, almost
                    // always by the CLI's own sign-in running right now.
                    let failure = OAuthLogin.Failure.portBusy(self.requestedPort ?? 0)
                    self.resumeReady(.failure(failure))
                    self.finish(.failure(failure))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Resolves once the browser comes back.
    ///
    /// The `state` is checked here rather than by the caller: a redirect that
    /// does not carry the value this sign-in generated did not come from this
    /// sign-in, and the code in it is not ours to use.
    func awaitCode(matching state: String, giveUpAfter patience: Duration) async throws -> String {
        // Nothing here can tell a sign-in still being typed from one that
        // ended on the provider's own error page — that page never reaches
        // this listener at all. So the wait is bounded, and giving up is
        // reported rather than left to look like a button that stopped working.
        let timeout = Task {
            try? await Task.sleep(for: patience)
            guard !Task.isCancelled else { return }
            self.finish(.failure(OAuthLogin.Failure.timedOut))
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            lock.lock()
            expectedState = state

            // The browser can beat this call — a redirect that has already
            // arrived is answered from what was kept rather than waited for.
            if let captured {
                lock.unlock()
                continuation.resume(with: captured)
                return
            }

            waiting = continuation
            lock.unlock()
        }
    }

    func stop() {
        listener.cancel()
    }

    // MARK: - One request, then done

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] chunk, _, done, _ in
            guard let self else { return }

            var buffer = accumulated
            if let chunk { buffer.append(chunk) }

            // The request line is all this needs and it arrives in the first
            // packet; the rest is read only so the browser isn't left writing
            // into a socket nobody is reading.
            guard
                let text = String(data: buffer, encoding: .utf8),
                text.contains("\r\n\r\n") || done,
                let line = text.split(separator: "\r\n").first
            else {
                if done {
                    connection.cancel()
                } else {
                    self.receive(on: connection, accumulated: buffer)
                }
                return
            }

            self.answer(connection, with: self.handle(requestLine: String(line)))
        }
    }

    /// Returns what to tell the browser, and settles the sign-in.
    private func handle(requestLine: String) -> String {
        let parts = requestLine.split(separator: " ")
        guard
            parts.count >= 2,
            let components = URLComponents(string: "http://localhost\(parts[1])"),
            components.path == path
        else { return String.localized("This page can be closed.") }

        // Read from the *encoded* items and decoded here, because a query
        // string spells a space as "+" and `URLComponents` will not undo that
        // — a provider's "User+declined" arrives verbatim otherwise. Doing it
        // before decoding rather than after is what keeps a literal plus in a
        // code (which arrives as "%2B") from being turned into a space.
        let items = components.percentEncodedQueryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
            return raw.replacingOccurrences(of: "+", with: "%20").removingPercentEncoding
        }

        if let error = value("error_description") ?? value("error") {
            finish(.failure(OAuthLogin.Failure.refused(error)))
            return String.localized("Sign-in failed. You can close this page.")
        }

        lock.lock()
        let expected = expectedState
        lock.unlock()

        guard let code = value("code"), value("state") == expected else {
            finish(.failure(OAuthLogin.Failure.cancelled))
            return String.localized("Sign-in failed. You can close this page.")
        }

        finish(.success(code))
        return String.localized("Signed in. You can close this page and go back to Pulse.")
    }

    private func answer(_ connection: NWConnection, with message: String) {
        let body = """
        <!doctype html><meta charset="utf-8"><title>Pulse</title>
        <body style="font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:90vh;margin:0">
        <p>\(message)</p>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func resumeReady(_ result: Result<Void, Error>) {
        lock.lock()
        guard let continuation = ready else { lock.unlock(); return }
        ready = nil
        lock.unlock()

        continuation.resume(with: result)
    }

    /// Settles once and once only: a browser that retries the redirect, or a
    /// listener failing after the code has already arrived, must not resume a
    /// continuation twice.
    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !settled else { lock.unlock(); return }
        settled = true

        guard let continuation = waiting else {
            // Nobody is waiting yet; keep it for whoever asks.
            captured = result
            lock.unlock()
            return
        }
        waiting = nil
        lock.unlock()

        continuation.resume(with: result)
    }
}
