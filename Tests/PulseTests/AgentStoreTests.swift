import Foundation
import SQLite3
import Testing
@testable import Pulse

/// The readers for the agents that keep their work somewhere other than a
/// Claude-shaped transcript.
///
/// Every store here is built by hand in the shape the real one was measured
/// to have — nobody's transcripts are committed, and a fixture captured from a
/// live machine would carry their conversations with it.
@Suite("Agent stores")
struct AgentStoreTests {
    /// A private root this test owns, created fresh under the system temporary
    /// directory. Fixtures live inside it; cleanup removes only what is handed
    /// back here and never walks up from a path inside it.
    private static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(
            path: "PulseAgentStoreTests-\(name)-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static let prices: [String: ModelPrice] = [
        "priced": ModelPrice(input: 1, output: 10, cacheRead: 0.1, cacheWrite: 1, name: "Priced")
    ]

    // MARK: - OpenCode and Kilo CLI

    @Test("An assistant message's counts become a day and a session")
    func openCodeIsRead() throws {
        let root = try Self.temporary("opencode")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "opencode.db")

        var handle: OpaquePointer?
        #expect(sqlite3_open(file.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }

        let created = Int(Date(timeIntervalSince1970: 1_789_372_800).timeIntervalSince1970) * 1000
        let assistant = """
        {"role":"assistant","modelID":"priced","time":{"created":\(created)},\
        "tokens":{"total":0,"input":100,"output":10,"reasoning":5,"cache":{"write":20,"read":300}}}
        """
        // A user's message carries no counts and must not be read as a zero.
        let user = #"{"role":"user","time":{"created":1},"tokens":{}}"#

        for sql in [
            "CREATE TABLE session (id TEXT, project_id TEXT, slug TEXT, directory TEXT, title TEXT)",
            "CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, data TEXT)",
            "INSERT INTO session VALUES ('s1','p','slug-one','/Users/me/Code/Pulse','Fix the ring')",
            "INSERT INTO message VALUES ('m1','s1',1,'\(assistant)')",
            "INSERT INTO message VALUES ('m2','s1',2,'\(user)')",
        ] {
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }

        let ledger = OpenCodeStore.ledger(at: file, prices: Self.prices)
        let day = try #require(ledger.days.first { $0.tokens > 0 })

        // Reasoning counts as output, which is where every price list bills it.
        #expect(day.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 300, output: 15))
        // Priced from `ModelPrices`, never from the store's own `cost` column.
        #expect(abs(day.cost - (100 + 20 + 30 + 150) / 1_000_000) < 1e-9)

        let session = try #require(ledger.sessions.first)
        #expect(session.title == "Fix the ring")
        // The directory's last component, not the whole path.
        #expect(session.project?.name == "Pulse")
    }

    // MARK: - Grok Build

    @Test("A turn's usage is read per model, and the folder names the project")
    func grokIsRead() throws {
        let root = try Self.temporary("grok")
        defer { try? FileManager.default.removeItem(at: root) }
        // The folder is the working directory, percent-encoded.
        let run = root
            .appending(path: "%2FUsers%2Fme%2FCode%2FPulse")
            .appending(path: "01a01492")
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)

        let lines = [
            #"{"timestamp":1789372800,"params":{"update":{"sessionUpdate":"user_message_chunk","content":"Fix the ring"}}}"#,
            """
            {"timestamp":1789372800,"params":{"update":{"sessionUpdate":"turn_completed","usage":{\
            "inputTokens":999,"outputTokens":999,"modelUsage":{"priced":{"inputTokens":100,"outputTokens":10,\
            "reasoningTokens":5,"cachedReadTokens":300,"cacheCreationTokens":20}}}}}}
            """,
        ]
        try lines.joined(separator: "\n").write(
            to: run.appending(path: "updates.jsonl"), atomically: true, encoding: .utf8
        )

        let ledger = GrokStore.ledger(at: root, prices: Self.prices)
        let day = try #require(ledger.days.first { $0.tokens > 0 })
        // `modelUsage` wins over the flat totals beside it — reading both would
        // count the turn twice.
        #expect(day.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 300, output: 15))

        let session = try #require(ledger.sessions.first)
        #expect(session.project?.name == "Pulse")
        #expect(session.title == "Fix the ring")
    }

    // MARK: - Kimi CLI

    @Test("`input_other` is fresh input, counted beside the cache")
    func kimiIsRead() throws {
        let root = try Self.temporary("kimi")
        defer { try? FileManager.default.removeItem(at: root) }
        let run = root.appending(path: "hash/session")
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)

        let line = """
        {"timestamp":1789372800,"message":{"payload":{"model":"priced","token_usage":{\
        "input_other":100,"output":15,"input_cache_read":300,"input_cache_creation":20}}}}
        """
        try line.write(to: run.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)

        let ledger = KimiCLIStore.ledger(at: root, prices: Self.prices)
        let day = try #require(ledger.days.first { $0.tokens > 0 })
        #expect(day.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 300, output: 15))
    }

    // MARK: - Nothing to read

    @Test("A store that is not there is not an empty account")
    func missingStoresAreAbsent() throws {
        let root = try Self.temporary("nowhere")
        defer { try? FileManager.default.removeItem(at: root) }
        let nowhere = root.appending(path: "absent")
        #expect(OpenCodeStore.ledger(at: nowhere, prices: [:]).days.isEmpty)
        #expect(GrokStore.ledger(at: nowhere, prices: [:]).days.isEmpty)
        #expect(KimiCLIStore.ledger(at: nowhere, prices: [:]).days.isEmpty)
        #expect(DevinCLIStore.ledger(at: nowhere, prices: [:]).days.isEmpty)
    }
}
