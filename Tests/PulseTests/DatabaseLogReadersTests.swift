import Foundation
import SQLite3
import Testing
@testable import Pulse

/// The database and event-log readers: Hermes, Goose, Zed, Kiro, Crush,
/// Unsloth, Antigravity CLI, MiMo Code and Devin Desktop.
///
/// Every store is built by hand in the shape the format facts describe, inside
/// a private temporary root this test owns. Nobody's real database is opened,
/// no network is touched, and cleanup removes only the root that was handed
/// back — never a parent directory.
@Suite("Database log readers")
struct DatabaseLogReadersTests {
    // MARK: - Fixtures

    private static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(
            path: "PulseDatabaseLogReaders-\(name)-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    /// A SQLite file built from raw statements. The test's own writer, closed
    /// before any reader opens the file read-only.
    private static func sqlite(at url: URL, _ statements: [String]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        for statement in statements {
            let result = sqlite3_exec(handle, statement, nil, nil, nil)
            #expect(result == SQLITE_OK, "statement failed: \(statement)")
        }
    }

    private static func iso(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private static let prices: [String: ModelPrice] = [
        "priced": ModelPrice(input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "Priced")
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Catalogue

    @Test("The catalogue is exactly the ten clients this family answers for")
    func catalogue() {
        #expect(
            DatabaseLogReaders.supportedClients == Set([
                "hermes", "goose", "zed", "kiro", "crush", "unsloth",
                "antigravity-cli", "antigravity-ide", "micode", "devin-desktop",
            ])
        )
        // An unknown client has no inputs and no records, not an empty account.
        let nowhere = URL(fileURLWithPath: "/nonexistent")
        #expect(DatabaseLogReaders.inputs(client: "nope", home: nowhere, environment: [:]).isEmpty)
        #expect(DatabaseLogReaders.records(client: "nope", roots: [nowhere]).isEmpty)
    }

    // MARK: - Hermes

    @Test("Hermes reads a per-model sum once and never re-emits that session's total")
    func hermesPerModelAndSessionTotals() throws {
        let home = try Self.temporary("hermes")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".hermes/state.db")
        try Self.sqlite(at: database, [
            """
            CREATE TABLE sessions (id TEXT, model TEXT, billing_provider TEXT,
            started_at REAL, message_count INT, input_tokens INT, output_tokens INT,
            cache_read_tokens INT, cache_write_tokens INT, reasoning_tokens INT)
            """,
            """
            CREATE TABLE session_model_usage (session_id TEXT, model TEXT,
            billing_provider TEXT, input_tokens INT, output_tokens INT,
            cache_read_tokens INT, cache_write_tokens INT, reasoning_tokens INT)
            """,
            // Covered by the per-model pass: the session row must not also emit.
            "INSERT INTO sessions VALUES ('s1','m1',NULL,1789372800,3,100,10,5,3,7)",
            // Not covered, and its start is stated in milliseconds.
            "INSERT INTO sessions VALUES ('s2','m2','openai',1789372800000,2,40,4,0,0,0)",
            "INSERT INTO session_model_usage VALUES ('s1','m1',NULL,100,10,5,3,7)",
        ])

        let roots = DatabaseLogReaders.inputs(client: "hermes", home: home, environment: [:])
        let records = DatabaseLogReaders.records(client: "hermes", roots: roots)

        #expect(records.count == 2)
        let perModel = try #require(records.first { $0.sessionID == "s1" })
        #expect(perModel.deduplicationID == "hermes:s1:m1:<null>")
        // A non-zero cache means the input/cache relationship is unproven:
        // the input is real work but unattributable, and the cache is not
        // summed beside it. Reasoning is not added to output either, since it
        // may already be inside it.
        #expect(perModel.tally == TokenTally(output: 10))
        #expect(perModel.tally.input == 0)
        #expect(perModel.tally.cacheRead == 0)
        #expect(perModel.tally.cacheWrite == 0)
        #expect(perModel.unclassifiedTokens == 100)
        #expect(perModel.isAggregate)
        // A positive cache leaves the total a known subset, not a complete one.
        #expect(perModel.isPartial)
        #expect(perModel.timestamp == Date(timeIntervalSince1970: 1_789_372_800))

        // No cache reported: the input is unambiguous and stays classified,
        // and the four kinds are complete reported data.
        let totals = try #require(records.first { $0.sessionID == "s2" })
        #expect(totals.deduplicationID == "s2")
        #expect(totals.tally == TokenTally(input: 40, output: 4))
        #expect(totals.unclassifiedTokens == 0)
        #expect(!totals.isPartial)
        #expect(totals.timestamp == Date(timeIntervalSince1970: 1_789_372_800))
    }

    @Test("Hermes never sums input and cache while their inclusion is unproven")
    func hermesInputCacheRelationship() throws {
        let home = try Self.temporary("hermes-cache")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".hermes/state.db")
        try Self.sqlite(at: database, [
            "CREATE TABLE sessions (id TEXT, model TEXT, started_at REAL, input_tokens INT, output_tokens INT)",
            """
            CREATE TABLE session_model_usage (session_id TEXT, model TEXT,
            billing_provider TEXT, input_tokens INT, output_tokens INT,
            cache_read_tokens INT, cache_write_tokens INT, reasoning_tokens INT)
            """,
            "INSERT INTO sessions VALUES ('a','m',1789372800,0,0)",
            "INSERT INTO sessions VALUES ('b','m',1789372800,0,0)",
            "INSERT INTO sessions VALUES ('c','m',1789372800,0,0)",
            "INSERT INTO sessions VALUES ('d','m',1789372800,0,0)",
            // Cache reported: input must not be added to it.
            "INSERT INTO session_model_usage VALUES ('a','m',NULL,100,10,30,10,5)",
            // No cache: input is classified normally.
            "INSERT INTO session_model_usage VALUES ('b','m',NULL,40,4,0,0,0)",
            // Cache only, no input counter: no evidence for an input count.
            "INSERT INTO session_model_usage VALUES ('c','m',NULL,NULL,0,7,0,0)",
            // Reasoning alone is ambiguous too, so the record is partial.
            "INSERT INTO session_model_usage VALUES ('d','m',NULL,30,5,0,0,3)",
        ])

        let records = DatabaseLogReaders.records(
            client: "hermes",
            roots: DatabaseLogReaders.inputs(client: "hermes", home: home, environment: [:])
        )

        let a = try #require(records.first { $0.deduplicationID?.hasPrefix("hermes:a:") == true })
        #expect(a.tally == TokenTally(output: 10))
        #expect(a.unclassifiedTokens == 100)
        // 100 input + 30 read + 10 write must not appear as a 140-token total
        // under any name, and the reported output is not inflated by reasoning.
        #expect(a.tally.total + a.unclassifiedTokens == 110)
        #expect(a.isPartial)

        let b = try #require(records.first { $0.deduplicationID?.hasPrefix("hermes:b:") == true })
        #expect(b.tally == TokenTally(input: 40, output: 4))
        #expect(b.unclassifiedTokens == 0)
        #expect(!b.isPartial)

        let d = try #require(records.first { $0.deduplicationID?.hasPrefix("hermes:d:") == true })
        #expect(d.tally == TokenTally(input: 30, output: 5))
        #expect(d.isPartial)

        // The cache-only row invents no input and adds no cache.
        #expect(!records.contains { $0.deduplicationID?.hasPrefix("hermes:c:") == true })

        // Partial propagates: any partial record marks the ledger and summary.
        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "hermes", calendar: Self.calendar
        )
        #expect(ledger.hasPartialCounts)
        let summary = SpendSummary.of(
            [.openCode: ledger], overLast: nil,
            now: Date(timeIntervalSince1970: 1_789_372_800), calendar: Self.calendar
        )
        #expect(summary.hasPartialCounts)
    }

    @Test("Hermes groups a NULL provider apart from an empty one, and skips a dateless session")
    func hermesIdentityAndMissingTime() throws {
        let home = try Self.temporary("hermes-id")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".hermes/state.db")
        try Self.sqlite(at: database, [
            "CREATE TABLE sessions (id TEXT, model TEXT, started_at REAL, input_tokens INT, output_tokens INT)",
            """
            CREATE TABLE session_model_usage (session_id TEXT, model TEXT,
            billing_provider TEXT, input_tokens INT, output_tokens INT)
            """,
            "INSERT INTO sessions VALUES ('s1','m1',1789372800,10,1)",
            // No started_at: nothing may be bucketed on a guessed date.
            "INSERT INTO sessions VALUES ('s9','m9',NULL,99,9)",
            "INSERT INTO session_model_usage VALUES ('s1','m1',NULL,10,1)",
            "INSERT INTO session_model_usage VALUES ('s1','m1','',20,2)",
        ])

        let records = DatabaseLogReaders.records(
            client: "hermes",
            roots: DatabaseLogReaders.inputs(client: "hermes", home: home, environment: [:])
        )

        // NULL and empty providers are different groups; the dateless session
        // contributes nothing.
        #expect(
            Set(records.compactMap(\.deduplicationID))
                == Set(["hermes:s1:m1:", "hermes:s1:m1:<null>"])
        )
        #expect(records.allSatisfy({ $0.isAggregate }))
    }

    // MARK: - Goose

    @Test("Goose prefers the accumulated columns and keeps the total remainder unclassified")
    func gooseAccumulatedAndUnclassified() throws {
        let home = try Self.temporary("goose")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(
            path: "Library/Application Support/goose/sessions/sessions.db"
        )
        try Self.sqlite(at: database, [
            """
            CREATE TABLE sessions (id TEXT, model_config_json TEXT, provider_name TEXT,
            created_at TEXT, total_tokens INT, input_tokens INT, output_tokens INT,
            accumulated_total_tokens INT, accumulated_input_tokens INT,
            accumulated_output_tokens INT)
            """,
            """
            INSERT INTO sessions VALUES ('g1','{"model_name":"priced"}','openai',
            '2026-09-15 12:00:00',500,999,999,500,100,20)
            """,
            // All zero: no record.
            """
            INSERT INTO sessions VALUES ('g2','{"model_name":"priced"}','openai',
            '2026-09-15 12:00:00',0,0,0,0,0,0)
            """,
            // No readable timestamp: skipped, never dated 1970.
            """
            INSERT INTO sessions VALUES ('g3','{"model_name":"priced"}','openai',
            'not a date',10,5,5,10,5,5)
            """,
            // Blank model name: skipped.
            """
            INSERT INTO sessions VALUES ('g4','{"model_name":"  "}','openai',
            '2026-09-15 12:00:00',10,5,5,10,5,5)
            """,
            // A bare total with no kind at all: kept, never split into input.
            """
            INSERT INTO sessions VALUES ('g5','{"model_name":"priced"}','openai',
            '2026-09-15 12:00:00',70,0,0,70,0,0)
            """,
        ])

        let roots = DatabaseLogReaders.inputs(client: "goose", home: home, environment: [:])
        let records = DatabaseLogReaders.records(client: "goose", roots: roots)
        #expect(records.count == 2)

        let record = try #require(records.first { $0.deduplicationID == "g1" })
        // Accumulated wins over the plain columns.
        #expect(record.tally == TokenTally(input: 100, output: 20))
        // 500 total − 120 known is the part nobody attributed; it is neither
        // reasoning nor any kind.
        #expect(record.unclassifiedTokens == 380)
        #expect(record.isAggregate)
        // The reported total is counted in full, so this is not partial.
        #expect(!record.isPartial)
        #expect(record.timestamp == Self.iso("2026-09-15T12:00:00Z"))

        let bare = try #require(records.first { $0.deduplicationID == "g5" })
        #expect(bare.tally == TokenTally())
        #expect(bare.unclassifiedTokens == 70)

        // Through the builder: the bare total is counted and left unpriced.
        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "goose", calendar: Self.calendar
        )
        let summary = SpendSummary.of(
            [.openCode: ledger], overLast: nil,
            now: Date(timeIntervalSince1970: 1_789_372_800), calendar: Self.calendar
        )
        #expect(summary.tokens == 570)
        #expect(summary.unpricedTokens == 450)
        #expect(abs(summary.cost - 0.3) < 1e-9)
        let day = try #require(ledger.days.first)
        #expect(day.modelUnclassifiedTokens["priced"] == 450)
    }

    // MARK: - Zed

    @Test("Zed sums request entries, falls back to the cumulative one, and filters by provider")
    func zedThreads() throws {
        let home = try Self.temporary("zed")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(
            path: "Library/Application Support/Zed/threads/threads.db"
        )

        let requests = """
        {"imported":false,"model":{"provider":"zed.dev","model":"priced"},
        "request_token_usage":{
        "a":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":30,"cache_creation_input_tokens":20},
        "b":{"input_tokens":0,"output_tokens":0},
        "c":{"input_tokens":"50","output_tokens":"1","cache_read_input_tokens":-7}},
        "updated_at":"2026-09-15T13:00:00Z"}
        """
        let cumulative = """
        {"imported":false,"model":{"provider":"zed.dev","model":"priced"},
        "request_token_usage":{},"cumulative_token_usage":{"input_tokens":5,"output_tokens":6}}
        """
        let imported = """
        {"imported":true,"model":{"provider":"zed.dev","model":"priced"},
        "request_token_usage":{"a":{"input_tokens":999}}}
        """
        let external = """
        {"model":{"provider":"other","model":"priced"},
        "request_token_usage":{"a":{"input_tokens":999}}}
        """

        try Self.sqlite(at: database, [
            """
            CREATE TABLE threads (id TEXT, summary TEXT, updated_at TEXT, data_type TEXT,
            data BLOB, parent_id TEXT, folder_paths TEXT, folder_paths_order TEXT, created_at TEXT)
            """,
            "INSERT INTO threads VALUES ('z1','',NULL,'json','\(requests)','','a/One\nb/Two','1,0','2026-09-15T12:00:00Z')",
            "INSERT INTO threads VALUES ('z2','',NULL,'json','\(cumulative)','',NULL,NULL,'2026-09-15T12:00:00Z')",
            "INSERT INTO threads VALUES ('z3','',NULL,'json','\(imported)','','','','2026-09-15T12:00:00Z')",
            "INSERT INTO threads VALUES ('z4','',NULL,'json','\(external)','','','','2026-09-15T12:00:00Z')",
            "INSERT INTO threads VALUES ('z5','',NULL,'zstd','\(requests)','','','','2026-09-15T12:00:00Z')",
        ])

        let roots = DatabaseLogReaders.inputs(client: "zed", home: home, environment: [:])
        let records = DatabaseLogReaders.records(client: "zed", roots: roots)

        #expect(records.count == 2)
        let z1 = try #require(records.first { $0.sessionID == "z1" })
        // Entry a (100/10/read 30/write 20), entry b skipped as empty, entry c
        // as numeric strings with a negative cache read clamped to zero.
        #expect(z1.tally == TokenTally(input: 150, cacheWrite: 20, cacheRead: 30, output: 11))
        #expect(z1.project == "b/Two")
        #expect(z1.deduplicationID == "zed:z1")

        let z2 = try #require(records.first { $0.sessionID == "z2" })
        #expect(z2.tally == TokenTally(input: 5, output: 6))
    }

    @Test("Zed reads a zstd thread through the system decoder, or reports the limitation")
    func zedZstd() throws {
        let home = try Self.temporary("zed-zstd")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(
            path: "Library/Application Support/Zed/threads/threads.db"
        )

        let thread = """
        {"model":{"provider":"zed.dev","model":"priced"},
        "request_token_usage":{"a":{"input_tokens":100,"output_tokens":10}},
        "created_at":"2026-09-15T12:00:00Z"}
        """
        let plain = Array(thread.utf8)
        let compressed = Array(Self.zstdFrame(Data(plain)))

        try Self.sqlite(at: database, [
            """
            CREATE TABLE threads (id TEXT, summary TEXT, updated_at TEXT, data_type TEXT,
            data BLOB, parent_id TEXT, folder_paths TEXT, folder_paths_order TEXT, created_at TEXT)
            """,
            "INSERT INTO threads VALUES ('zjson','',NULL,'json',\(Self.hex(plain)),'','','','2026-09-15T12:00:00Z')",
            "INSERT INTO threads VALUES ('zzstd','',NULL,'zstd',\(Self.hex(compressed)),'','','','2026-09-15T12:00:00Z')",
        ])

        let roots = DatabaseLogReaders.inputs(client: "zed", home: home, environment: [:])
        let records = DatabaseLogReaders.records(client: "zed", roots: roots)
        let json = try #require(records.first { $0.sessionID == "zjson" })

        if let limitation = DSHZstdDecoder.limitation {
            // No decoder on this Mac: the compressed thread yields nothing and
            // the limitation is reported rather than read as a zero.
            #expect(!records.contains { $0.sessionID == "zzstd" })
            #expect(DatabaseLogReaders.notes(client: "zed", roots: roots) == [limitation])
        } else {
            let zstd = try #require(records.first { $0.sessionID == "zzstd" })
            #expect(zstd.tally == json.tally)
            #expect(zstd.timestamp == json.timestamp)
            #expect(zstd.project == json.project)
            #expect(zstd.deduplicationID == "zed:zzstd")
            #expect(DatabaseLogReaders.notes(client: "zed", roots: roots).isEmpty)
        }
    }

    @Test("Zed notes name an unreadable compressed thread and stay quiet for plain JSON")
    func zedZstdLimitations() throws {
        let createThreads = """
        CREATE TABLE threads (id TEXT, summary TEXT, updated_at TEXT, data_type TEXT,
        data BLOB, parent_id TEXT, folder_paths TEXT, folder_paths_order TEXT, created_at TEXT)
        """
        let thread = #"{"model":{"provider":"zed.dev","model":"priced"},"request_token_usage":{"a":{"input_tokens":100,"output_tokens":10}},"created_at":"2026-09-15T12:00:00Z"}"#
        let plain = Array(thread.utf8)

        // A store of plain JSON threads: records flow, no limitation reported.
        let plainHome = try Self.temporary("zed-json-only")
        defer { try? FileManager.default.removeItem(at: plainHome) }
        let plainDB = plainHome.appending(
            path: "Library/Application Support/Zed/threads/threads.db"
        )
        try Self.sqlite(at: plainDB, [
            createThreads,
            "INSERT INTO threads VALUES ('j1','',NULL,'json',\(Self.hex(plain)),'','','','2026-09-15T12:00:00Z')",
        ])
        let plainRoots = DatabaseLogReaders.inputs(client: "zed", home: plainHome, environment: [:])
        #expect(DatabaseLogReaders.records(client: "zed", roots: plainRoots).count == 1)
        #expect(DatabaseLogReaders.notes(client: "zed", roots: plainRoots).isEmpty)

        // A compressed row recognized by magic but corrupt: the readable JSON
        // thread still yields its record, the frame yields nothing, and the
        // failure is named. This holds whether or not the system library loads.
        let badHome = try Self.temporary("zed-bad-zstd")
        defer { try? FileManager.default.removeItem(at: badHome) }
        let badDB = badHome.appending(path: "Library/Application Support/Zed/threads/threads.db")
        let corrupt = Array(DSHZstdDecoder.magic) + Array("not a zstd frame".utf8)
        try Self.sqlite(at: badDB, [
            createThreads,
            "INSERT INTO threads VALUES ('j1','',NULL,'json',\(Self.hex(plain)),'','','','2026-09-15T12:00:00Z')",
            "INSERT INTO threads VALUES ('bad','',NULL,'zstd',\(Self.hex(corrupt)),'','','','2026-09-15T12:00:00Z')",
        ])
        let badRoots = DatabaseLogReaders.inputs(client: "zed", home: badHome, environment: [:])
        #expect(DatabaseLogReaders.records(client: "zed", roots: badRoots).count == 1)
        #expect(!DatabaseLogReaders.notes(client: "zed", roots: badRoots).isEmpty)

        // The size ceiling is the same failure class; the limit is injected so
        // the test need not build a 32 MiB buffer. `tooLarge` is thrown before
        // the library is consulted, so this holds on any Mac.
        let oversized = Data(DSHZstdDecoder.magic) + Data(repeating: 0, count: 8)
        let overLimit: Bool
        if case .unreadableZstd = ZedReader.payload(
            dataType: "zstd", blob: oversized, rawLimit: 4, decodedLimit: 4
        ) {
            overLimit = true
        } else {
            overLimit = false
        }
        #expect(overLimit)
    }

    // MARK: - Kiro

    @Test("Kiro counts only explicit counters; an estimated turn produces no record")
    func kiroOnlyRealCounters() throws {
        let home = try Self.temporary("kiro")
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appending(path: ".kiro/sessions/cli")

        let header = """
        {"session_id":"s1","cwd":"/Users/me/Code/Pulse",
        "session_state":{"rts_model_state":{"model_info":{"model_id":"priced"}},
        "conversation_metadata":{"user_turn_metadatas":[
        {"input_token_count":100,"output_token_count":10,"end_timestamp":1789372800,"message_ids":["p1"]},
        {"input_token_count":0,"output_token_count":0,"end_timestamp":1789372900,"message_ids":["p2"]}]}}}
        """
        try Self.write(header, to: directory.appending(path: "s1.json"))
        try Self.write(
            "{\"kind\":\"Prompt\",\"data\":{\"message_id\":\"p1\",\"meta\":{\"timestamp\":1789372800}}}\n",
            to: directory.appending(path: "s1.jsonl")
        )
        // An IDE tree exists but is entirely estimated, so it is not read.
        try Self.write(
            "{\"id\":\"s1\",\"modelId\":\"priced\",\"workspacePaths\":[\"/Users/me/Code/Pulse\"]}",
            to: home.appending(path: ".kiro/sessions/ws/sess_abc/session.json")
        )

        let roots = DatabaseLogReaders.inputs(client: "kiro", home: home, environment: [:])
        #expect(roots.map(\.path) == [directory.path])

        let records = DatabaseLogReaders.records(client: "kiro", roots: roots)
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.tally == TokenTally(input: 100, output: 10))
        #expect(record.model == "priced")
        #expect(record.sessionID == "s1")
        #expect(record.project == "/Users/me/Code/Pulse")
        #expect(record.deduplicationID == "s1:0")
        #expect(record.timestamp == Date(timeIntervalSince1970: 1_789_372_800))
        #expect(!record.isAggregate)
        // Kiro's explicit counters carry no cache or reasoning doubt.
        #expect(!record.isPartial)
    }

    // MARK: - Crush

    @Test("Crush declares its registry and project databases but reports no token records")
    func crushIsInputsOnly() throws {
        let home = try Self.temporary("crush")
        defer { try? FileManager.default.removeItem(at: home) }
        let registry = home.appending(path: ".local/share/crush/projects.json")
        try Self.write(
            #"{"projects":[{"path":"\#(home.path)/work","data_dir":"data"}]}"#,
            to: registry
        )

        let roots = DatabaseLogReaders.inputs(client: "crush", home: home, environment: [:])
        #expect(roots.contains(registry))
        #expect(roots.contains(where: { $0.path.hasSuffix("/work/data/crush.db") }))

        // Cost-only: no token count exists, so there is no record to invent.
        #expect(DatabaseLogReaders.records(client: "crush", roots: roots).isEmpty)
    }

    // MARK: - Unsloth

    @Test("Unsloth normalizes both measured tables so their buckets add to the total")
    func unslothNormalization() throws {
        let home = try Self.temporary("unsloth")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".unsloth/studio/studio.db")

        let metadata = """
        {"contextUsage":{"promptTokens":100,"completionTokens":20,"totalTokens":130,
        "cachedTokens":30,"cacheWriteTokens":10,"reasoningTokens":5,"modelId":"ctx-model"},
        "responseDetails":{"responseModelId":"priced","providerType":"openai"}}
        """
        try Self.sqlite(at: database, [
            "CREATE TABLE chat_threads (id TEXT, model_id TEXT)",
            "CREATE TABLE chat_messages (id TEXT, thread_id TEXT, role TEXT, metadata_json TEXT, created_at INTEGER)",
            "CREATE TABLE api_usage_events (id TEXT, endpoint TEXT, model TEXT, prompt_tokens INT, completion_tokens INT, total_tokens INT, created_at INTEGER)",
            "INSERT INTO chat_threads VALUES ('t1','thread-model')",
            "INSERT INTO chat_messages VALUES ('m1','t1','assistant','\(metadata)',1789372800)",
            "INSERT INTO api_usage_events VALUES ('e1','/v1/chat','priced',50,5,60,1789372800)",
        ])

        let roots = DatabaseLogReaders.inputs(client: "unsloth", home: home, environment: [:])
        let records = DatabaseLogReaders.records(client: "unsloth", roots: roots)
        #expect(records.count == 2)

        let chat = try #require(records.first { $0.sessionID == "t1" })
        // fresh 70 + read 30 + write 10 + output 20 = the reported total 130.
        #expect(chat.tally == TokenTally(input: 70, cacheWrite: 10, cacheRead: 30, output: 20))
        #expect(chat.tally.total == 130)
        #expect(chat.model == "priced")
        #expect(chat.deduplicationID == "unsloth:chat:m1")

        let api = try #require(records.first { $0.sessionID == "unsloth:api" })
        #expect(api.tally == TokenTally(input: 55, output: 5))
        #expect(api.title == "/v1/chat")
        #expect(api.deduplicationID == "unsloth:api:e1")
    }

    // MARK: - Antigravity CLI

    @Test("The protobuf wire decoder refuses malformed input and keeps unknown fields")
    func wireDecoderBoundaries() {
        let valid = Self.fieldVarint(1, 5)
            + Self.fieldString(2, "hi")
            + Self.fieldFixed64(3, 0x0102_0304_0506_0708)
        let message = AntigravityWire.decode(valid)
        #expect(message?[1]?.varint == 5)
        #expect(message?.string(2) == "hi")
        #expect(message?[3]?.fixed64 == 0x0102_0304_0506_0708)

        // A varint that ends mid-continuation.
        #expect(AntigravityWire.decode([0x08, 0x80]) == nil)
        // An overlong varint (more than ten bytes).
        #expect(AntigravityWire.decode([0x08] + Array(repeating: UInt8(0x80), count: 11) + [0x01]) == nil)
        // A length that runs past the buffer.
        #expect(AntigravityWire.decode(Self.tagBytes(1, 2) + [0x0A, 0x01]) == nil)
        // The deprecated group wire types are unsupported.
        #expect(AntigravityWire.decode(Self.tagBytes(1, 3)) == nil)
        // Field zero is not a field.
        #expect(AntigravityWire.decode([0x00]) == nil)
        // Unknown field numbers are kept rather than dropped.
        #expect(AntigravityWire.decode(Self.fieldVarint(500, 9))?[500]?.varint == 9)
    }

    @Test("Antigravity CLI reads reported counters, dedups by response id and anchors its time")
    func antigravityGeneration() throws {
        let home = try Self.temporary("antigravity")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".gemini/antigravity-cli/conversations/conv-a.db")

        let trajectory = Self.fieldLength(2, Self.timestampBytes(seconds: 1_789_372_800))
            + Self.fieldLength(1, Self.fieldLength(1, Array("file:///Users/me/Code/Pulse".utf8)))

        // `#1` is present but is not an established count: it must not appear
        // in the tally at all.
        let usage = Self.fieldVarint(1, 1_132)
            + Self.fieldVarint(2, 100)
            + Self.fieldVarint(5, 30)
            + Self.fieldVarint(9, 10)
            + Self.fieldVarint(10, 5)
            + Self.fieldString(11, "resp-1")
        let wall = Self.fieldLength(4, Self.timestampBytes(seconds: 1_789_372_900))
        let chat = Self.fieldString(19, "priced")
            + Self.fieldLength(4, usage)
            + Self.fieldLength(9, wall)
        let generation = Self.fieldLength(1, chat)

        try Self.sqlite(at: database, [
            "CREATE TABLE trajectory_metadata_blob (data BLOB)",
            "CREATE TABLE gen_metadata (idx INTEGER, data BLOB)",
            "CREATE TABLE steps (metadata BLOB, step_type INTEGER)",
            "INSERT INTO trajectory_metadata_blob VALUES (\(Self.hex(trajectory)))",
            "INSERT INTO gen_metadata VALUES (0, \(Self.hex(generation)))",
        ])

        let roots = DatabaseLogReaders.inputs(
            client: "antigravity-cli", home: home, environment: [:]
        )
        let records = DatabaseLogReaders.records(client: "antigravity-cli", roots: roots)
        #expect(records.count == 1)
        let record = try #require(records.first)
        // input = #2 only (#1 is not a proven count), output = #9 + #10
        // (reasoning folded once), cache = #5.
        #expect(record.tally == TokenTally(input: 100, cacheRead: 30, output: 15))
        #expect(record.tally.total == 145)
        #expect(record.model == "priced")
        #expect(record.sessionID == "conv-a")
        #expect(record.project == "/Users/me/Code/Pulse")
        #expect(record.timestamp == Date(timeIntervalSince1970: 1_789_372_900))
        #expect(record.deduplicationID == "antigravity:conv-a:resp-1")
        // An explicit per-generation timestamp is an exact event time.
        #expect(!record.isAggregate)
        // `#1` is excluded and no whole-usage total exists, so the read is a
        // proven subset.
        #expect(record.isPartial)
    }

    @Test("Antigravity ignores field numbers with no established meaning")
    func antigravityUnknownFields() throws {
        let home = try Self.temporary("antigravity-unknown")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".gemini/antigravity-cli/conversations/conv-c.db")

        // Only a created-at; the usage carries #1 and a large unknown field
        // number, neither of which may become tokens or money.
        let trajectory = Self.fieldLength(2, Self.timestampBytes(seconds: 1_789_372_800))
        func usage(fresh: UInt64, response: String) -> [UInt8] {
            Self.fieldVarint(1, 1_132)
                + Self.fieldVarint(20, 999_999)
                + Self.fieldVarint(2, fresh)
                + Self.fieldString(11, response)
        }
        let empty = Self.fieldLength(
            1, Self.fieldString(19, "priced") + Self.fieldLength(4, usage(fresh: 0, response: "resp-3"))
        )
        let real = Self.fieldLength(
            1, Self.fieldString(19, "priced") + Self.fieldLength(4, usage(fresh: 100, response: "resp-4"))
        )

        try Self.sqlite(at: database, [
            "CREATE TABLE trajectory_metadata_blob (data BLOB)",
            "CREATE TABLE gen_metadata (idx INTEGER, data BLOB)",
            "CREATE TABLE steps (metadata BLOB, step_type INTEGER)",
            "INSERT INTO trajectory_metadata_blob VALUES (\(Self.hex(trajectory)))",
            "INSERT INTO gen_metadata VALUES (0, \(Self.hex(empty)))",
            "INSERT INTO gen_metadata VALUES (1, \(Self.hex(real)))",
        ])

        let records = DatabaseLogReaders.records(
            client: "antigravity-cli",
            roots: DatabaseLogReaders.inputs(client: "antigravity-cli", home: home, environment: [:])
        )
        // The first generation's real counters are all zero, so #1 and the
        // unknown field emit nothing; the second counts only its real #2, not
        // 1,132 or 999,999 more.
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.tally == TokenTally(input: 100))
        #expect(record.tally.total == 100)
    }

    @Test("Antigravity with no exact event time falls back to the session anchor, marked aggregate")
    func antigravityTimestampFallback() throws {
        let home = try Self.temporary("antigravity-time")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".gemini/antigravity-cli/conversations/conv-b.db")

        let trajectory = Self.fieldLength(2, Self.timestampBytes(seconds: 1_789_372_800))
        // No #9.#4 event timestamp and no steps row. The unknown #9.#10 bytes
        // are never decoded into a turn time, so the session's created-at is
        // the only time there is — and it is an anchor, so the record is an
        // aggregate rather than an exact event time.
        let usage = Self.fieldVarint(2, 100) + Self.fieldString(11, "resp-2")
        let chat = Self.fieldString(19, "priced") + Self.fieldLength(4, usage)
        let generation = Self.fieldLength(1, chat)

        try Self.sqlite(at: database, [
            "CREATE TABLE trajectory_metadata_blob (data BLOB)",
            "CREATE TABLE gen_metadata (idx INTEGER, data BLOB)",
            "CREATE TABLE steps (metadata BLOB, step_type INTEGER)",
            "INSERT INTO trajectory_metadata_blob VALUES (\(Self.hex(trajectory)))",
            "INSERT INTO gen_metadata VALUES (0, \(Self.hex(generation)))",
        ])

        let records = DatabaseLogReaders.records(
            client: "antigravity-cli",
            roots: DatabaseLogReaders.inputs(client: "antigravity-cli", home: home, environment: [:])
        )
        let record = try #require(records.first)
        #expect(record.timestamp == Date(timeIntervalSince1970: 1_789_372_800))
        #expect(record.tally == TokenTally(input: 100))
        #expect(record.isAggregate)
    }

    // MARK: - MiMo Code

    @Test("MiMo Code folds one embedded message across channel databases")
    func micodeUnionAndDedup() throws {
        let home = try Self.temporary("micode")
        defer { try? FileManager.default.removeItem(at: home) }
        let primary = home.appending(path: ".local/share/mimocode/mimocode.db")
        let orca = home.appending(
            path: "Library/Application Support/orca/mimocode-hooks/shared/data/mimocode-beta.db"
        )

        let create = [
            "CREATE TABLE message (id TEXT, session_id TEXT, data TEXT)",
            "CREATE TABLE session (id TEXT, directory TEXT)",
        ]
        let shared = #"{"id":"msg-1","role":"assistant","modelID":"priced","tokens":{"input":100,"output":10,"reasoning":5,"cache":{"read":30,"write":20}},"time":{"created":1789372800000},"sessionID":"s1"}"#
        let second = #"{"id":"msg-2","role":"assistant","modelID":"priced","tokens":{"input":50,"output":5},"time":{"created":1789372900},"sessionID":"s2"}"#

        try Self.sqlite(at: primary, create + [
            "INSERT INTO session VALUES ('s1','/Users/me/Code/Pulse')",
            "INSERT INTO message VALUES ('row-1','s1','\(shared)')",
        ])
        try Self.sqlite(at: orca, create + [
            "INSERT INTO session VALUES ('s2','/Users/me/Code/Other')",
            "INSERT INTO message VALUES ('row-x','s1','\(shared)')",
            "INSERT INTO message VALUES ('row-2','s2','\(second)')",
        ])

        let roots = DatabaseLogReaders.inputs(client: "micode", home: home, environment: [:])
        let records = DatabaseLogReaders.records(client: "micode", roots: roots)
        // The same embedded id appears in both databases; folding is the
        // builder's job, and both copies carry the same identity.
        #expect(records.filter({ $0.deduplicationID == "msg-1" }).count == 2)
        // Every kind is reported, so none of these records is partial.
        #expect(records.allSatisfy({ !$0.isPartial }))

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "micode", calendar: Self.calendar
        )
        // msg-1 once (165) plus msg-2 (55), with the seconds epoch normalized.
        #expect(ledger.days.reduce(0, { $0 + $1.tokens }) == 220)
        #expect(ledger.sessions.count == 2)
        let session = try #require(ledger.sessions.first { $0.id == "micode#s1" })
        #expect(session.tokens == 165)
        #expect(session.project?.name == "Pulse")

        // One raw model across two sessions is one model row.
        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "Priced", overLast: nil,
            now: Date(timeIntervalSince1970: 1_789_372_800), calendar: Self.calendar
        )
        #expect(model.tokens == 220)
    }

    // MARK: - Devin Desktop

    @Test("Devin Desktop aggregates ACP usage and reads legacy events individually")
    func devinDesktopShapes() throws {
        let home = try Self.temporary("devin-desktop")
        defer { try? FileManager.default.removeItem(at: home) }
        let events = home.appending(
            path: "Library/Application Support/Devin/User/acp-events"
        )
        let lookup = home.appending(path: ".local/share/devin/cli/sessions.db")
        try Self.sqlite(at: lookup, [
            "CREATE TABLE sessions (id TEXT, title TEXT, model TEXT, working_directory TEXT)",
            "INSERT INTO sessions VALUES ('d1','Fix the ring','priced','/Users/me/Code/Pulse')",
        ])

        let canonical = [
            #"{"notification":{"sessionUpdate":"session_info_update","title":"Fix the ring"}}"#,
            #"{"notification":{"sessionUpdate":"usage_update","created_at":"2026-09-15T12:00:00Z","notification_model":"priced","_meta":{"cognition.ai/inputTokens":100,"cognition.ai/cachedReadTokens":30,"cognition.ai/cachedWriteTokens":20,"cognition.ai/outputTokens":10}}}"#,
            #"{"notification":{"sessionUpdate":"usage_update","created_at":"2026-09-15T12:01:00Z","notification_model":"priced","_meta":{"cognition.ai/inputTokens":150,"cognition.ai/cachedReadTokens":40,"cognition.ai/cachedWriteTokens":25,"cognition.ai/outputTokens":5}}}"#,
        ].joined(separator: "\n")
        try Self.write(canonical, to: events.appending(path: "event.ndjson"))

        let legacy = #"{"notification":{"content":{"metadata":{"metrics":{"input_tokens":100,"output_tokens":10,"cache_read_tokens":5,"cache_creation_tokens":2},"generation_model":"priced","created_at":"2026-09-15T12:00:00Z"}}}}"#
        try Self.write(legacy, to: events.appending(path: "legacy.ndjson"))

        let roots = DatabaseLogReaders.inputs(client: "devin-desktop", home: home, environment: [:])
        let records = DatabaseLogReaders.records(client: "devin-desktop", roots: roots)

        let aggregate = try #require(records.first { $0.deduplicationID == "devin-desktop:\(events.appending(path: "event.ndjson").path):usage" })
        // latest input 150 − read 40 = 110 fresh; summed output 10 + 5 = 15.
        #expect(aggregate.tally == TokenTally(input: 110, cacheWrite: 25, cacheRead: 40, output: 15))
        #expect(aggregate.sessionID == "d1")
        #expect(aggregate.project == "/Users/me/Code/Pulse")
        #expect(aggregate.isAggregate)
        #expect(aggregate.timestamp == Self.iso("2026-09-15T12:01:00Z"))

        let event = try #require(records.first { $0.deduplicationID == "devin-desktop:\(events.appending(path: "legacy.ndjson").path):0" })
        #expect(event.tally == TokenTally(input: 100, cacheWrite: 2, cacheRead: 5, output: 10))
    }

    @Test("Devin Desktop does not credit a cloud event with no local usage, and never mixes an ambiguous title")
    func devinDesktopNoUsageAndAmbiguity() throws {
        let home = try Self.temporary("devin-desktop-2")
        defer { try? FileManager.default.removeItem(at: home) }
        let events = home.appending(path: ".config/devin/User/acp-events")
        let lookup = home.appending(path: ".local/share/devin/cli/sessions.db")
        try Self.sqlite(at: lookup, [
            "CREATE TABLE sessions (id TEXT, title TEXT, model TEXT, working_directory TEXT)",
            // One title, two sessions: ambiguous, so it resolves to nothing.
            "INSERT INTO sessions VALUES ('d1','Fix the ring','priced','/a')",
            "INSERT INTO sessions VALUES ('d2','Fix the ring','priced','/b')",
        ])

        let lines = [
            #"{"notification":{"sessionUpdate":"session_info_update","title":"Fix the ring"}}"#,
            // A devin-cloud event with no usage at all.
            #"{"notification":{"sessionUpdate":"usage_update","created_at":"2026-09-15T12:00:00Z"}}"#,
            // The model is a routing mode, never a model name.
            #"{"notification":{"sessionUpdate":"usage_update","created_at":"2026-09-15T12:00:00Z","notification_model":"adaptive","_meta":{"cognition.ai/inputTokens":50,"cognition.ai/outputTokens":3}}}"#,
        ].joined(separator: "\n")
        try Self.write(lines, to: events.appending(path: "cloudy.ndjson"))

        let roots = DatabaseLogReaders.inputs(client: "devin-desktop", home: home, environment: [:])
        let records = DatabaseLogReaders.records(client: "devin-desktop", roots: roots)

        #expect(records.count == 1)
        let record = try #require(records.first)
        // No recoverable model, and `adaptive` is a routing mode: the record
        // gets an unpriced `unknown` rather than an invented product model.
        #expect(record.model == "unknown")
        // The ambiguous title is not used as a session id; the file stem is.
        #expect(record.sessionID == "cloudy")
        #expect(record.tally == TokenTally(input: 50, output: 3))
    }

    // MARK: - Through the production chain

    @Test("A reader's records reach SpendSummary and ModelSpendSummary with the same totals")
    func productionChain() throws {
        let home = try Self.temporary("chain")
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appending(path: ".kiro/sessions/cli")
        let header = """
        {"session_id":"s1","cwd":"/Users/me/Code/Pulse",
        "session_state":{"rts_model_state":{"model_info":{"model_id":"priced"}},
        "conversation_metadata":{"user_turn_metadatas":[
        {"input_token_count":100,"output_token_count":10,"end_timestamp":1789372800,
        "message_ids":["p1"]}]}}}
        """
        try Self.write(header, to: directory.appending(path: "s1.json"))

        let records = DatabaseLogReaders.records(
            client: "kiro",
            roots: DatabaseLogReaders.inputs(client: "kiro", home: home, environment: [:])
        )
        let now = Date(timeIntervalSince1970: 1_789_372_800)
        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: SpendAgent.openCode.rawValue,
            calendar: Self.calendar
        )

        let summary = SpendSummary.of(
            [.openCode: ledger], overLast: nil, now: now, calendar: Self.calendar
        )
        #expect(summary.tokens == 110)
        // 100 input at 1000/M + 10 output at 10000/M = 0.1 + 0.1.
        #expect(abs(summary.cost - 0.2) < 1e-9)
        #expect(summary.tally == TokenTally(input: 100, output: 10))
        // Complete counters do not mark the ledger or the summary partial.
        #expect(!ledger.hasPartialCounts)
        #expect(!summary.hasPartialCounts)

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "Priced", overLast: nil, now: now, calendar: Self.calendar
        )
        #expect(model.tokens == 110)
        #expect(abs((model.cost ?? -1) - 0.2) < 1e-9)
    }

    // MARK: - Wire helpers

    private static func varintBytes(_ value: UInt64) -> [UInt8] {
        var value = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    private static func tagBytes(_ field: Int, _ wire: Int) -> [UInt8] {
        varintBytes(UInt64((field << 3) | wire))
    }

    private static func fieldVarint(_ field: Int, _ value: UInt64) -> [UInt8] {
        tagBytes(field, 0) + varintBytes(value)
    }

    private static func fieldLength(_ field: Int, _ bytes: [UInt8]) -> [UInt8] {
        tagBytes(field, 2) + varintBytes(UInt64(bytes.count)) + bytes
    }

    private static func fieldString(_ field: Int, _ text: String) -> [UInt8] {
        fieldLength(field, Array(text.utf8))
    }

    private static func fieldFixed64(_ field: Int, _ value: UInt64) -> [UInt8] {
        tagBytes(field, 1) + (0..<8).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) }
    }

    private static func timestampBytes(seconds: UInt64, nanos: UInt64 = 0) -> [UInt8] {
        fieldVarint(1, seconds) + fieldVarint(2, nanos)
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        "X'" + bytes.map { String(format: "%02x", $0) }.joined() + "'"
    }

    /// A zstd frame with a single uncompressed (raw) block, built from the
    /// published frame format so the test carries no third-party bytes.
    private static func zstdFrame(_ payload: Data) -> Data {
        var frame = Data([0x28, 0xB5, 0x2F, 0xFD])
        let count = payload.count
        if count < 256 {
            frame.append(0x20)
            frame.append(UInt8(count))
        } else {
            // Single segment, two-byte frame content size.
            frame.append(0x60)
            frame.append(UInt8(count & 0xFF))
            frame.append(UInt8((count >> 8) & 0xFF))
        }
        let header = UInt32(1) | (UInt32(count) << 3)
        frame.append(UInt8(header & 0xFF))
        frame.append(UInt8((header >> 8) & 0xFF))
        frame.append(UInt8((header >> 16) & 0xFF))
        frame.append(payload)
        return frame
    }
}

/// The folders Antigravity's conversations are looked for in, and that the CLI
/// and the IDE are never pooled.
///
/// Pinned for two failures, both silent. The spec named `antigravity-cli`
/// alone, so a Mac with the IDE installed showed no Antigravity spend at all
/// while holding a store the reader could read perfectly. And the first fix
/// handed all the folders to one client, which would have added two products'
/// usage into one figure.
@Suite("Antigravity conversation roots")
struct AntigravityRootsTests {
    private static func roots(_ client: String, _ environment: [String: String] = [:]) -> [String] {
        AntigravityCLIReader
            .inputs(client: client, home: URL(fileURLWithPath: "/home"), environment: environment)
            .map(\.path)
    }

    @Test("The CLI reads its own folder and only its own")
    func cli() {
        #expect(Self.roots("antigravity-cli") == ["/home/.gemini/antigravity-cli/conversations"])
    }

    @Test("The IDE reads both of its layouts, and not the CLI's")
    func ide() {
        let roots = Self.roots("antigravity-ide")
        #expect(roots.contains("/home/.gemini/antigravity/conversations"))
        #expect(roots.contains("/home/.gemini/antigravity-ide/conversations"))
        #expect(!roots.contains("/home/.gemini/antigravity-cli/conversations"))
    }

    /// The whole point of the split: nothing is read by both.
    @Test("The two clients share no root")
    func disjoint() {
        let cli = Set(Self.roots("antigravity-cli"))
        let ide = Set(Self.roots("antigravity-ide"))
        #expect(cli.intersection(ide).isEmpty)
    }

    @Test("GEMINI_CLI_HOME moves both clients' roots")
    func overriddenHome() {
        for client in ["antigravity-cli", "antigravity-ide"] {
            let roots = Self.roots(client, ["GEMINI_CLI_HOME": "/elsewhere"])
            #expect(!roots.isEmpty)
            #expect(roots.allSatisfy { $0.hasPrefix("/elsewhere/") }, "\(client)")
        }
    }
}
