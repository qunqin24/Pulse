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

    @Test("OpenCode 2's tables are read, with the copied history counted once")
    func openCodeTwoIsRead() throws {
        let root = try Self.temporary("opencode2")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "opencode.db")

        var handle: OpaquePointer?
        #expect(sqlite3_open(file.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }

        let created = Int(Date(timeIntervalSince1970: 1_789_372_800).timeIntervalSince1970) * 1000
        // OpenCode 1's shape, as the upgrade left it in both tables.
        let old = """
        {"role":"assistant","modelID":"priced","time":{"created":\(created)},\
        "tokens":{"input":100,"output":10,"reasoning":0,"cache":{"write":0,"read":0}}}
        """
        // OpenCode 2's: no role, the model an object.
        let new = """
        {"time":{"created":\(created + 1000)},"model":{"id":"priced","providerID":"openai"},\
        "tokens":{"input":200,"output":20,"reasoning":5,"cache":{"write":0,"read":0}}}
        """
        let user = #"{"time":{"created":1},"tokens":{"input":999}}"#

        for sql in [
            "CREATE TABLE session (id TEXT, project_id TEXT, slug TEXT, directory TEXT, title TEXT)",
            "CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, data TEXT)",
            "CREATE TABLE session_v2 (id TEXT, slug TEXT, title TEXT, directory TEXT)",
            "CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER, data TEXT)",
            "INSERT INTO session_v2 VALUES ('s1','slug-one','Fix the ring','/Users/me/Code/Pulse')",
            // Copied by the upgrade: in both tables under one id.
            "INSERT INTO message VALUES ('m1','s1',1,'\(old)')",
            "INSERT INTO session_message VALUES ('m1','s1','assistant',1,'\(old)')",
            // Written since: only the new table.
            "INSERT INTO session_message VALUES ('m2','s1','assistant',2,'\(new)')",
            // A user turn with a count in it is still not a reply.
            "INSERT INTO session_message VALUES ('m3','s1','user',3,'\(user)')",
        ] {
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }

        let ledger = OpenCodeStore.ledger(at: file, prices: Self.prices)
        let tally = ledger.days.reduce(TokenTally()) { $0 + $1.tally }
        #expect(tally == TokenTally(input: 300, cacheWrite: 0, cacheRead: 0, output: 35))
        #expect(ledger.sessions.first?.title == "Fix the ring")
    }

    @Test("Mixed OpenCode stores select by update time, including zero usage", arguments: [
        ("2000", "1000", 70, 0, 70),
        ("2000", "1000", 70, 30, 70),
        ("1000", "2000", 70, 30, 30),
        ("1000", "2000", 70, 0, 0),
        ("2000", "1000", 0, 30, 0),
        ("2000", "2000", 70, 30, 30),
        ("2000", "2000", 70, 0, 0),
        ("NULL", "1000", 70, 30, 30),
        ("2000", "NULL", 70, 30, 30),
        ("NULL", "NULL", 70, 30, 30),
        ("'invalid'", "1000", 70, 30, 30),
        ("2000", "'invalid'", 70, 30, 30),
        ("0", "1000", 70, 30, 30),
        ("2000", "-1", 70, 30, 30),
        ("2000.5", "2000", 70, 30, 70),
    ])
    func openCodeLatestCopy(v1Time: String, v2Time: String, v1: Int, v2: Int, expected: Int) throws {
        let ledger = try Self.mixedOpenCode(v1Time: v1Time, v2Time: v2Time,
                                           v1: Self.openCodeMessage(v1), v2: Self.openCodeMessage(v2, v2: true))
        // The two unique rows remain, regardless of which duplicate wins.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == expected + 18)
        let selected = ledger.sessions.first { $0.id.hasSuffix("#shared") }
        #expect((selected?.tokens ?? 0) == expected)
        #expect(abs((selected?.cost ?? 0) - Double(expected) / 1_000_000) < 1e-9)
        // Session metadata retains its existing V2 precedence, independently
        // of which message wins. Usage stays on time.created, not time_updated.
        if expected > 0 {
            #expect(selected?.title == "V2 title")
            #expect(selected?.project?.path == "/synthetic/project")
            #expect(selected?.start == Date(timeIntervalSince1970: 1_789_372_800))
        }
    }

    @Test("Unreadable copies do not hide readable usage", arguments: [
        "not json", "{}",
        #"{"role":"assistant","modelID":"priced","time":{"created":1789372800000},"tokens":{}}"#,
        #"{"role":"assistant","modelID":"priced","time":{"created":1789372800000},"tokens":{"input":"bad","output":0}}"#,
        #"{"role":"assistant","modelID":"priced","time":{"created":1789372800000},"tokens":{"input":-1,"output":0}}"#,
        #"{"role":"assistant","modelID":"priced","time":{"created":1789372800000},"tokens":{"input":true,"output":0}}"#,
        #"{"role":"assistant","modelID":"priced","time":{"created":1789372800000}}"#,
        #"{"role":"assistant","modelID":"priced","time":{"created":1789372800000},"tokens":"invalid"}"#,
    ])
    func openCodeInvalidCopy(invalid: String) throws {
        for invalidV2 in [true, false] {
            let ledger = try Self.mixedOpenCode(
                v1Time: "2000", v2Time: "3000",
                v1: invalidV2 ? Self.openCodeMessage(70) : invalid,
                v2: invalidV2 ? invalid : Self.openCodeMessage(30, v2: true)
            )
            #expect(ledger.days.reduce(0) { $0 + $1.tokens } == (invalidV2 ? 70 : 30) + 18)
        }
    }

    @Test("Legacy columns keep V2 precedence and id-less rows remain distinct", arguments: [0, 1, 2, 3])
    func openCodeLegacyLayouts(layout: Int) throws {
        let ledger = try Self.mixedOpenCode(v1Time: "2000", v2Time: "1000",
                                           v1: Self.openCodeMessage(70), v2: Self.openCodeMessage(30, v2: true),
                                           layout: layout)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == (layout == 3 ? 100 : 30) + 18)
    }

    @Test("Either OpenCode table can stand alone", arguments: ["message", "session_message"])
    func openCodeSingleLayout(table: String) throws {
        let ledger = try Self.mixedOpenCode(v1Time: "2000", v2Time: "1000",
                                           v1: Self.openCodeMessage(70), v2: Self.openCodeMessage(30, v2: true),
                                           dropTable: table)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == (table == "message" ? 41 : 77))
    }

    @Test("The selected copy supplies the model and creation-time bucket")
    func openCodeSelectedAttribution() throws {
        let newer = Self.openCodeMessage(70)
            .replacingOccurrences(of: "priced", with: "unknown")
            .replacingOccurrences(of: "1789372800000", with: "1789459200000")
        let ledger = try Self.mixedOpenCode(v1Time: "2000", v2Time: "1000",
                                           v1: newer, v2: Self.openCodeMessage(30, v2: true))
        let session = try #require(ledger.sessions.first { $0.id.hasSuffix("#shared") })
        #expect(session.tokens == 70)
        #expect(session.unpricedTokens == 70)
        #expect(session.cost == 0)
        #expect(session.start == Date(timeIntervalSince1970: 1_789_459_200))
        #expect(session.slots.reduce(0) { $0 + $1.tokens } == 70)
    }

    private static func openCodeMessage(_ input: Int, v2: Bool = false) -> String {
        let model = v2 ? #""model":{"id":"priced","providerID":"openai"}"# : #""role":"assistant","modelID":"priced""#
        return """
        {\(model),"time":{"created":1789372800000},"tokens":{"input":\(input),"output":0,"reasoning":0,"cache":{"read":0,"write":0}}}
        """
    }

    /// layout: 0 = neither update column, 1 = V1 lacks it, 2 = V2 lacks it,
    /// 3 = V1 also lacks ids. All fixtures are synthetic and private to a test.
    private static func mixedOpenCode(
        v1Time: String, v2Time: String, v1: String, v2: String, layout: Int = 4, dropTable: String? = nil
    ) throws -> UsageLedger {
        let root = try temporary("opencode-recency")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "opencode.db")
        var handle: OpaquePointer?
        #expect(sqlite3_open(file.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        let v1ID = layout == 3 ? "" : "id TEXT,"
        let v1Update = layout == 0 || layout == 1 || layout == 3 ? "" : "time_updated INTEGER,"
        let v2Update = layout == 0 || layout == 2 || layout == 3 ? "" : "time_updated INTEGER,"
        for sql in [
            "CREATE TABLE message (\(v1ID) session_id TEXT, \(v1Update) data TEXT)",
            "CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, \(v2Update) data TEXT)",
            "CREATE TABLE session (id TEXT, slug TEXT, title TEXT, directory TEXT)",
            "CREATE TABLE session_v2 (id TEXT, slug TEXT, title TEXT, directory TEXT)",
            "INSERT INTO session VALUES ('shared','old','V1 title','/synthetic/old')",
            "INSERT INTO session_v2 VALUES ('shared','new','V2 title','/synthetic/project')",
        ] {
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }
        for (id, session, old, new) in [
            ("duplicate", "shared", v1, v2),
            ("v1-only", "one", openCodeMessage(7), ""),
            ("v2-only", "two", "", openCodeMessage(11, v2: true)),
            ("user", "user", #"{"role":"user","modelID":"priced","time":{"created":1789372800000},"tokens":{"input":999}}"#,
             openCodeMessage(999, v2: true)),
        ] {
            if !old.isEmpty {
                let identity = layout == 3 ? "" : "'\(id)',"
                let time = v1Update.isEmpty ? "" : "\(v1Time),"
                let json = old.replacingOccurrences(of: "'", with: "''")
                #expect(sqlite3_exec(handle, "INSERT INTO message VALUES (\(identity)'\(session)',\(time)'\(json)')", nil, nil, nil) == SQLITE_OK)
            }
            if !new.isEmpty {
                let time = v2Update.isEmpty ? "" : "\(v2Time),"
                let role = id == "user" ? "user" : "assistant"
                let json = new.replacingOccurrences(of: "'", with: "''")
                #expect(sqlite3_exec(handle, "INSERT INTO session_message VALUES ('\(id)','\(session)','\(role)',\(time)'\(json)')", nil, nil, nil) == SQLITE_OK)
            }
        }
        // V2 requires its type column; a JSON role cannot rescue a NULL type.
        #expect(sqlite3_exec(handle, "INSERT INTO session_message (id, session_id, type, data) VALUES ('null-role','user',NULL,'\(openCodeMessage(999))')", nil, nil, nil) == SQLITE_OK)
        if let dropTable {
            #expect(sqlite3_exec(handle, "DROP TABLE \(dropTable)", nil, nil, nil) == SQLITE_OK)
        }
        return OpenCodeStore.ledger(at: file, prices: prices)
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
            "inputTokens":999,"outputTokens":999,"modelUsage":{"priced":{"inputTokens":33379,"outputTokens":91,\
            "reasoningTokens":42,"cachedReadTokens":22272,"cacheCreationTokens":0,"totalTokens":33470}}}}}}
            """,
        ]
        try lines.joined(separator: "\n").write(
            to: run.appending(path: "updates.jsonl"), atomically: true, encoding: .utf8
        )

        let ledger = GrokStore.ledger(at: root, prices: Self.prices)
        let day = try #require(ledger.days.first { $0.tokens > 0 })
        // `modelUsage` wins over the flat totals beside it — reading both would
        // count the turn twice. Its input already holds the cached read and
        // its output the reasoning, so the tally adds up to Grok Build's own
        // `totalTokens` (#91).
        #expect(day.tally == TokenTally(input: 11107, cacheWrite: 0, cacheRead: 22272, output: 91))
        #expect(day.tally.total == 33470)

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

    /// One Kimi Code request in all three places its log writes it.
    private static func kimiCodeRequest(ms: Int, model: String, agent: String, fresh: Int) -> String {
        let usage = #"{"inputOther":\#(fresh),"output":15,"inputCacheRead":300,"inputCacheCreation":20}"#
        return [
            #"{"type":"usage.record","time":\#(ms),"agentId":"\#(agent)","model":"\#(model)","usageScope":"turn","usage":\#(usage)}"#,
            #"{"type":"context.append_loop_event","time":\#(ms),"agentId":"\#(agent)","event":{"type":"step.end","step":1,"usage":\#(usage)}}"#,
            #"{"type":"agent.message.appended","time":\#(ms),"kind":"event","message":{"meta":{"model":{"model":"agent-loop"},"usage":\#(usage)}}}"#,
        ].joined(separator: "\n")
    }

    @Test("Kimi Code's request is counted once, by the model its usage record names")
    func kimiCodeIsRead() throws {
        let root = try Self.temporary("kimi-code")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "sessions")
        let session = sessions.appending(path: "wd_pulse_0123456789ab/session_0001")
        for agent in ["main", "agent-1"] {
            try FileManager.default.createDirectory(
                at: session.appending(path: "agents/\(agent)"), withIntermediateDirectories: true
            )
        }
        try Self.kimiCodeRequest(ms: 1_789_372_800_000, model: "work-endpoint/priced", agent: "main", fresh: 100)
            .write(to: session.appending(path: "agents/main/wire.jsonl"), atomically: true, encoding: .utf8)
        try Self.kimiCodeRequest(ms: 1_789_372_860_000, model: "kimi-code/kimi-for-coding", agent: "agent-1", fresh: 200)
            .write(to: session.appending(path: "agents/agent-1/wire.jsonl"), atomically: true, encoding: .utf8)
        try #"{"title":"Fix the ring","cwd":"/Users/someone/Pulse"}"#
            .write(to: session.appending(path: "state.json"), atomically: true, encoding: .utf8)

        let ledger = KimiCLIStore.ledger(at: [sessions], prices: Self.prices)
        let tally = ledger.days.reduce(TokenTally()) { $0 + $1.tally }
        #expect(tally == TokenTally(input: 300, cacheWrite: 40, cacheRead: 600, output: 30))

        // The endpoint prefix is dropped, so `priced` is priced; the plan's
        // moving alias is counted and never given a rate.
        #expect(ledger.sessions.count == 1)
        let run = try #require(ledger.sessions.first)
        #expect(run.tokens == 970)
        #expect(run.unpricedTokens == 535)
        #expect(run.cost > 0)
        #expect(run.title == "Fix the ring")
        #expect(run.project?.path == "/Users/someone/Pulse")
        #expect(run.name == "session_0001")
    }

    @Test("A request in both Kimi stores is counted once, from Kimi Code's copy")
    func kimiStoresDoNotDoubleCount() throws {
        let root = try Self.temporary("kimi-both")
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appending(path: "kimi/sessions")
        let code = root.appending(path: "kimi-code/sessions")
        let legacyRun = legacy.appending(path: "hash/uuid")
        let codeRun = code.appending(path: "wd_pulse_0123456789ab/session_uuid/agents/main")
        for directory in [legacyRun, codeRun] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // The same request, migrated: seconds with a fraction in the legacy
        // log, milliseconds in Kimi Code's. A second, different request stays
        // only in the legacy store.
        let legacyLines = [
            #"{"timestamp":1789372800.25,"message":{"payload":{"token_usage":{"input_other":100,"output":15,"input_cache_read":300,"input_cache_creation":20}}}}"#,
            #"{"timestamp":1789372900.5,"message":{"payload":{"token_usage":{"input_other":7,"output":1,"input_cache_read":0,"input_cache_creation":0}}}}"#,
        ]
        try legacyLines.joined(separator: "\n")
            .write(to: legacyRun.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        try Self.kimiCodeRequest(ms: 1_789_372_800_250, model: "kimi-code/priced", agent: "main", fresh: 100)
            .write(to: codeRun.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)

        let ledger = KimiCLIStore.ledger(at: [legacy, code], prices: Self.prices)
        let tally = ledger.days.reduce(TokenTally()) { $0 + $1.tally }
        #expect(tally == TokenTally(input: 107, cacheWrite: 20, cacheRead: 300, output: 16))
        #expect(ledger.sessions.map(\.tokens).sorted() == [8, 435])
        // The shared request is priced from Kimi Code's model, and only the
        // legacy-only request is unpriced.
        #expect(ledger.sessions.reduce(0) { $0 + $1.unpricedTokens } == 8)
    }

    @Test("Kimi's roots are the legacy store and Kimi Code's, which `KIMI_CODE_HOME` moves")
    func kimiRoots() {
        let home = URL(fileURLWithPath: "/tmp/pulse-home")
        #expect(SpendAgent.kimiCLI.inputs(home: home, environment: ["KIMI_CODE_HOME": "/custom/kimi"])
            == [home.appending(path: ".kimi/sessions"), URL(fileURLWithPath: "/custom/kimi/sessions")])
        #expect(SpendAgent.kimiCLI.inputs(home: home, environment: ["KIMI_CODE_HOME": "  "])
            == [home.appending(path: ".kimi/sessions"), home.appending(path: ".kimi-code/sessions")])
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
