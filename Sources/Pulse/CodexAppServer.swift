import Foundation

/// A JSON-RPC client for `codex app-server`.
///
/// This is Codex's own documented protocol, and it is the reason Pulse doesn't
/// have to hold Codex credentials: the app server is already signed in, so
/// Pulse asks it for figures instead of reading `~/.codex/auth.json` and
/// calling an undocumented HTTP endpoint itself. It also pushes
/// `account/rateLimits/updated` when the numbers move, so the refresh loop is
/// a fallback rather than the main path.
///
/// The cost is a resident child process, started lazily on the first request
/// and restarted if it dies.
actor CodexAppServer {
    /// Called when the server reports that limits changed.
    private var onRateLimitsChanged: (@Sendable () -> Void)?

    private var process: Process?
    private var stdin: FileHandle?
    private var nextID = 1
    // Results cross an actor boundary, and a JSON dictionary isn't Sendable,
    // so they travel as raw bytes and are decoded on the far side.
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var buffer = Data()

    enum Failure: Error {
        /// Codex isn't installed, or isn't anywhere we thought to look.
        case executableNotFound
        case startFailed
        case timedOut
        case server(String)
    }

    func setRateLimitsChangedHandler(_ handler: @escaping @Sendable () -> Void) {
        onRateLimitsChanged = handler
    }

    /// The account's limits, as `account/rateLimits/read` reports them, still
    /// encoded as JSON.
    func rateLimits() async throws -> Data {
        try await ensureRunning()
        return try await send(method: "account/rateLimits/read")
    }

    /// The account's token history, as `account/usage/read` reports it, still
    /// encoded as JSON.
    func accountUsage() async throws -> Data {
        try await ensureRunning()
        return try await send(method: "account/usage/read")
    }

    func shutDown() {
        process?.terminate()
        process = nil
        stdin = nil
        for (_, continuation) in pending {
            continuation.resume(throwing: Failure.startFailed)
        }
        pending.removeAll()
    }

    // MARK: - Process

    private func ensureRunning() async throws {
        if let process, process.isRunning { return }

        guard let executable = Self.locateCodex() else { throw Failure.executableNotFound }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]

        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { await self?.consume(chunk) }
        }

        do {
            try process.run()
        } catch {
            throw Failure.startFailed
        }

        self.process = process
        self.stdin = input.fileHandleForWriting
        self.nextID = 1

        // The protocol opens with a handshake before anything else is accepted.
        _ = try await send(
            method: "initialize",
            params: ["clientInfo": ["name": "Pulse", "title": "Pulse", "version": "0.1"]]
        )
        notify(method: "initialized")
    }

    /// Where `codex` tends to live. A GUI app inherits almost no `PATH`, so
    /// the usual install locations have to be checked by hand rather than
    /// relying on the environment.
    private static func locateCodex() -> URL? {
        let home = NSHomeDirectory()
        var candidates: [String] = []

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/codex" }
        }

        candidates += [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.volta/bin/codex"
        ]

        // Node installs put it under a version directory, so glob those.
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            candidates += versions.map { "\(nvm)/\($0)/bin/codex" }
        }

        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Messaging

    private func send(method: String, params: [String: Any] = [:]) async throws -> Data {
        let id = nextID
        nextID += 1

        let message: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else {
            throw Failure.startFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Nothing to write to means nothing will ever answer, and a
            // continuation nobody answers suspends its caller for ever.
            guard let stdin else {
                continuation.resume(throwing: Failure.startFailed)
                return
            }

            pending[id] = continuation
            guard write(data, to: stdin) else {
                pending[id] = nil
                continuation.resume(throwing: Failure.startFailed)
                return
            }

            // Strongly held, deliberately. Weakly, this server going away
            // before the timeout fires leaves every request it was carrying
            // suspended with nobody left to resume them — which Swift reports
            // as a leaked continuation and the caller experiences as a hang.
            // A strong reference costs at most twenty seconds of lifetime and
            // makes that impossible.
            Task { [self] in
                try? await Task.sleep(for: .seconds(20))
                self.timeOut(id)
            }
        }
    }

    private func notify(method: String, params: [String: Any] = [:]) {
        let message: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        guard
            let data = try? JSONSerialization.data(withJSONObject: message),
            let stdin
        else { return }

        _ = write(data, to: stdin)
    }

    /// One line to the helper's standard input, or false if it has gone.
    ///
    /// **Writing to a pipe whose far end has closed raises SIGPIPE, and the
    /// default for SIGPIPE is to kill the process.** The helper exiting — it
    /// crashed, it was killed with the terminal it was started from, the user
    /// quit Codex — would take Pulse down with it, and from the outside that
    /// looks like the app crashing at random. `SIGPIPE` is ignored process-wide
    /// (see `AppDelegate`) so the write returns an error instead; this is the
    /// half that then treats the error as "the helper is gone" rather than
    /// carrying on writing into a dead pipe.
    private func write(_ data: Data, to handle: FileHandle) -> Bool {
        do {
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
            return true
        } catch {
            // Whatever is left of it is not usable, and the next call will
            // start a fresh one.
            process = nil
            stdin = nil
            return false
        }
    }

    private func timeOut(_ id: Int) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: Failure.timedOut)
    }

    /// Messages arrive as newline-delimited JSON, and a read can land
    /// mid-line, so hold the remainder until the next chunk completes it.
    private func consume(_ chunk: Data) {
        buffer.append(chunk)

        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            guard !line.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        if let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
            if let error = message["error"] as? [String: Any] {
                let text = error["message"] as? String ?? "unknown"
                continuation.resume(throwing: Failure.server(text))
            } else {
                let result = message["result"] as? [String: Any] ?? [:]
                let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
                continuation.resume(returning: data)
            }
            return
        }

        if message["method"] as? String == "account/rateLimits/updated" {
            onRateLimitsChanged?()
        }
    }
}
