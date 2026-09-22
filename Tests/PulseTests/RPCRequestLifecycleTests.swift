import Foundation
import Testing
@testable import Pulse

/// Real pipes and isolated shell helpers; no installed CLI or account needed.
/// Serialized because every case starts child processes with short deadlines;
/// running the whole matrix at once can starve a helper and fake a timeout.
@Suite("RPC request lifecycle", .serialized)
struct RPCRequestLifecycleTests {
    enum Client: CaseIterable, Sendable {
        case codex, kiro

        func connect(to executable: URL) -> Connection {
            switch self {
            case .codex:
                let server = CodexAppServer(executable: executable, requestTimeout: .seconds(4))
                return Connection(read: { try await server.rateLimits() }, close: { await server.shutDown() })
            case .kiro:
                let client = KiroACPClient(executable: executable, requestTimeout: .seconds(4))
                return Connection(read: { try await client.usage() }, close: { await client.shutDown() })
            }
        }
    }

    struct Connection: Sendable {
        let read: @Sendable () async throws -> Data
        let close: @Sendable () async -> Void
    }

    enum FirstReply: String, CaseIterable, Sendable {
        case success, serverError, partialEOF
    }

    /// The second connection replies three seconds into its four-second
    /// deadline, after the first connection's old deadline has passed.
    @Test("A completed request cannot time out a later connection",
          arguments: Client.allCases, FirstReply.allCases)
    func reconnect(client: Client, first: FirstReply) async throws {
        let helper = try Helper(first: first.rawValue, secondDelay: "3")
        defer { helper.remove() }
        let connection = client.connect(to: helper.executable)

        do {
            _ = try await connection.read()
            #expect(first == .success, "the first helper should have failed")
        } catch CodexAppServer.Failure.server(let message) {
            #expect(client == .codex && first == .serverError && message == "fixture refusal")
        } catch KiroACPClient.Failure.server(let message) {
            #expect(client == .kiro && first == .serverError && message == "fixture refusal")
        } catch CodexAppServer.Failure.startFailed {
            #expect(client == .codex && first == .partialEOF)
        } catch KiroACPClient.Failure.closed {
            #expect(client == .kiro && first == .partialEOF)
        } catch {
            Issue.record("unexpected first request failure: \(error)")
        }
        await connection.close()
        try await Task.sleep(for: .seconds(2))

        do {
            let data = try await connection.read()
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            #expect(reply.attempt == 2)
        } catch {
            Issue.record("the new connection lost its own deadline: \(error)")
        }
        await connection.close()
    }

    @Test("An unanswered request still times out and permits a new connection", arguments: Client.allCases)
    func unansweredRequest(client: Client) async throws {
        let helper = try Helper(first: "silent", secondDelay: "0")
        defer { helper.remove() }
        let connection = client.connect(to: helper.executable)
        do {
            _ = try await connection.read()
            Issue.record("an unanswered request succeeded")
        } catch CodexAppServer.Failure.timedOut {
            #expect(client == .codex)
        } catch KiroACPClient.Failure.timedOut {
            #expect(client == .kiro)
        } catch {
            Issue.record("expected the request deadline, got \(error)")
        }
        await connection.close()
        do {
            let reply = try JSONDecoder().decode(Reply.self, from: await connection.read())
            #expect(reply.attempt == 2)
        } catch {
            Issue.record("could not read after a timeout: \(error)")
        }
        await connection.close()
    }

    @Test("Closing an in-flight request does not leave its timer on the next connection", arguments: Client.allCases)
    func closeWhileWaiting(client: Client) async throws {
        let helper = try Helper(first: "silent", secondDelay: "3")
        defer { helper.remove() }
        let connection = client.connect(to: helper.executable)
        let waiting = Task { try await connection.read() }
        // Helper startup can be delayed on a loaded test host. This bound is
        // only for readiness; the RPC keeps its own four-second deadline after
        // it is sent.
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !FileManager.default.fileExists(atPath: helper.ready.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let received = FileManager.default.fileExists(atPath: helper.ready.path)
        await connection.close()
        do {
            _ = try await waiting.value
            Issue.record("closing the connection did not fail its request")
        } catch CodexAppServer.Failure.startFailed {
            #expect(client == .codex)
        } catch KiroACPClient.Failure.closed {
            #expect(client == .kiro)
        } catch {
            Issue.record("expected connection closure, got \(error)")
        }
        try #require(received, "helper did not receive initialize")
        try await Task.sleep(for: .seconds(2))
        do {
            let reply = try JSONDecoder().decode(Reply.self, from: await connection.read())
            #expect(reply.attempt == 2)
        } catch {
            Issue.record("closed request interfered with the new connection: \(error)")
        }
        await connection.close()
    }

    @Test("Completed requests release the client before their deadlines", arguments: Client.allCases)
    @MainActor
    func completedRequestsReleaseClient(client: Client) async throws {
        let helper = try Helper(first: "success", secondDelay: "0")
        defer { helper.remove() }
        let isAlive = try await useAndRelease(client: client, executable: helper.executable)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while isAlive(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!isAlive(), "a completed request's timer still retains the client")
    }

    @MainActor
    private func useAndRelease(client: Client, executable: URL) async throws -> @MainActor () -> Bool {
        switch client {
        case .codex:
            let server = CodexAppServer(executable: executable, requestTimeout: .seconds(4))
            _ = try await server.rateLimits()
            await server.shutDown()
            return { [weak server] in server != nil }
        case .kiro:
            let client = KiroACPClient(executable: executable, requestTimeout: .seconds(4))
            _ = try await client.usage()
            await client.shutDown()
            return { [weak client] in client != nil }
        }
    }

    private struct Reply: Decodable { let attempt: Int }

    private struct Helper {
        let root: URL
        let executable: URL
        var ready: URL { URL(fileURLWithPath: executable.path + ".ready") }

        init(first: String, secondDelay: String) throws {
            root = FileManager.default.temporaryDirectory.appending(path: "PulseRPC-\(UUID().uuidString)")
            executable = root.appending(path: "helper")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let script = #"""
            #!/bin/sh
            attempt=$(/bin/cat "$0.count" 2>/dev/null || printf '0')
            attempt=$((attempt + 1))
            printf '%s' "$attempt" > "$0.count"
            first=1
            while IFS= read -r line; do
                id=$(printf '%s\n' "$line" | /usr/bin/sed -n 's/.*"id":[[:space:]]*\([0-9][0-9]*\).*/\1/p')
                [ -n "$id" ] || continue
                printf 'ready' > "$0.ready"
                if [ "$attempt" -eq 1 ]; then
                    case '\#(first)' in
                        silent) continue ;;
                        partialEOF) printf '{"id":'; exit 0 ;;
                        serverError)
                            printf '{"id":%s,"error":{"message":"fixture refusal"}}\n' "$id"
                            continue ;;
                    esac
                elif [ "$first" -eq 1 ]; then
                    /bin/sleep '\#(secondDelay)'
                fi
                first=0
                printf '{"id":%s,"result":{"attempt":%s}}\n' "$id" "$attempt"
            done
            """#
            try Data(script.utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
