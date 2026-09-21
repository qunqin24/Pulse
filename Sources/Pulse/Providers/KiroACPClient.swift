import Foundation

/// A short-lived connection to Kiro CLI's native Agent Client Protocol.
///
/// Authentication stays inside Kiro. Pulse starts the CLI, completes the ACP
/// handshake, asks for account usage, and then tears the helper down. Messages
/// are newline-delimited JSON; stderr is drained separately so a noisy helper
/// cannot fill its pipe and deadlock the request.
actor KiroACPClient {
    enum Failure: Error, Equatable {
        case executableNotFound
        case startFailed
        case timedOut
        case closed
        case server(String)
    }

    private var process: Process?
    private var stdin: FileHandle?
    private var reader: FileHandle?
    private var errorReader: FileHandle?
    // IDs belong to the client, not the child process: a timeout already
    // queued on this actor must never find a new request under its old ID.
    private var nextID = 1
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeout: Task<Void, Never>
    }
    private var pending: [Int: PendingRequest] = [:]
    private var buffer = Data()
    private let executable: URL?
    private let requestTimeout: Duration

    // Tests use an isolated helper without changing PATH or touching a login.
    init(executable: URL? = nil, requestTimeout: Duration = .seconds(20)) {
        self.executable = executable
        self.requestTimeout = requestTimeout
    }

    func usage() async throws -> Data {
        try start()
        defer { shutDown() }

        // Kiro installs its auth connection while handling initialize. Sending
        // getUsage before that response arrives races with setConnection().
        _ = try await send(
            method: "initialize",
            params: [
                "protocolVersion": 1,
                "clientCapabilities": [:],
                "clientInfo": ["name": "Pulse", "version": "0.1"]
            ]
        )
        return try await send(method: "_kiro/account/getUsage")
    }

    func shutDown() {
        reader?.readabilityHandler = nil
        errorReader?.readabilityHandler = nil
        reader = nil
        errorReader = nil
        process?.terminate()
        process = nil
        stdin = nil
        buffer.removeAll(keepingCapacity: false)
        failAllPending(with: .closed)
    }

    private func start() throws {
        guard let executable = executable ?? Self.locateKiro() else { throw Failure.executableNotFound }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["acp", "--agent-engine", "v3", "--auth-method", "cli"]
        process.environment = NetworkSession.subprocessEnvironment()

        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let reader = output.fileHandleForReading
        let errorReader = errors.fileHandleForReading
        startReading(reader)
        drain(errorReader)

        do {
            try process.run()
        } catch {
            shutDown()
            throw Failure.startFailed
        }

        self.process = process
        stdin = input.fileHandleForWriting
    }

    private static func locateKiro() -> URL? {
        let home = NSHomeDirectory()
        var candidates: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/kiro-cli" }
        }
        candidates += [
            "/opt/homebrew/bin/kiro-cli",
            "/usr/local/bin/kiro-cli",
            "\(home)/bin/kiro-cli",
            "\(home)/.local/bin/kiro-cli",
            "/Applications/Kiro CLI.app/Contents/MacOS/kiro-cli",
            "/Applications/Kiro.app/Contents/Resources/app/bin/kiro-cli"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private func send(method: String, params: [String: Any] = [:]) async throws -> Data {
        let id = nextID
        nextID += 1
        let message: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        ]
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: message)
        } catch {
            throw Failure.startFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            guard let stdin else {
                continuation.resume(throwing: Failure.closed)
                return
            }
            let timeout = Task { [self] in
                do { try await Task.sleep(for: requestTimeout) }
                catch { return }
                finish(id, with: .failure(Failure.timedOut))
            }
            pending[id] = PendingRequest(continuation: continuation, timeout: timeout)
            do {
                try stdin.write(contentsOf: data)
                try stdin.write(contentsOf: Data("\n".utf8))
            } catch {
                shutDown()
            }
        }
    }

    private func startReading(_ handle: FileHandle) {
        reader = handle
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                Task { await self?.readerClosed(handle) }
                return
            }
            Task { await self?.consume(chunk, from: handle) }
        }
    }

    private func drain(_ handle: FileHandle) {
        errorReader = handle
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                Task { await self?.errorReaderClosed(handle) }
                return
            }
        }
    }

    private func readerClosed(_ handle: FileHandle) {
        guard handle === reader else { return }
        shutDown()
    }

    private func errorReaderClosed(_ handle: FileHandle) {
        guard handle === errorReader else { return }
        errorReader = nil
    }

    private func consume(_ chunk: Data, from source: FileHandle) {
        guard source === reader else { return }
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
        guard let id = message["id"] as? Int, pending[id] != nil else { return }

        if let error = message["error"] as? [String: Any] {
            finish(id, with: .failure(Failure.server(error["message"] as? String ?? "unknown")))
            return
        }
        let result = message["result"] as? [String: Any] ?? [:]
        let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
        finish(id, with: .success(data))
    }

    private func finish(_ id: Int, with result: Result<Data, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    private func failAllPending(with failure: Failure) {
        for id in Array(pending.keys) { finish(id, with: .failure(failure)) }
    }
}
