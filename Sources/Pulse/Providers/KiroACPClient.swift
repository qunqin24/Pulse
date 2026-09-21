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
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var buffer = Data()

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
        guard let executable = Self.locateKiro() else { throw Failure.executableNotFound }

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
            reader.readabilityHandler = nil
            errorReader.readabilityHandler = nil
            throw Failure.startFailed
        }

        self.process = process
        stdin = input.fileHandleForWriting
        nextID = 1
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
            pending[id] = continuation
            do {
                try stdin.write(contentsOf: data)
                try stdin.write(contentsOf: Data("\n".utf8))
            } catch {
                pending[id] = nil
                continuation.resume(throwing: Failure.closed)
                return
            }

            Task { [self] in
                try? await Task.sleep(for: .seconds(20))
                timeOut(id)
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
            Task { await self?.consume(chunk) }
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
        reader = nil
        process?.terminate()
        process = nil
        stdin = nil
        failAllPending(with: .closed)
    }

    private func errorReaderClosed(_ handle: FileHandle) {
        guard handle === errorReader else { return }
        errorReader = nil
    }

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
        guard let id = message["id"] as? Int,
              let continuation = pending.removeValue(forKey: id)
        else { return }

        if let error = message["error"] as? [String: Any] {
            continuation.resume(throwing: Failure.server(error["message"] as? String ?? "unknown"))
            return
        }
        let result = message["result"] as? [String: Any] ?? [:]
        let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
        continuation.resume(returning: data)
    }

    private func timeOut(_ id: Int) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: Failure.timedOut)
    }

    private func failAllPending(with failure: Failure) {
        for continuation in pending.values { continuation.resume(throwing: failure) }
        pending.removeAll()
    }
}
