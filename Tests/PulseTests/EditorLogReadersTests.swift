import Foundation
import SQLite3
import Testing
@testable import Pulse

/// Fixtures shared by the Group B reader tests.
///
/// Every store is built by hand under a private temporary root and read back
/// through the readers' own entry points, so no test touches this machine's
/// real logs. Dates are fixed and the calendar is UTC, so day keys cannot drift
/// with the timezone of the machine running the tests.
enum EditorTestSupport {
    static let prices: [String: ModelPrice] = [
        "gpt-5": ModelPrice(input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "GPT-5"),
        "claude-sonnet": ModelPrice(
            input: 3_000, output: 15_000, cacheRead: 300, cacheWrite: 3_750, name: "Claude Sonnet"
        ),
    ]

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static let now = Date(timeIntervalSince1970: 1_789_372_800)

    static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulseEditorReaders-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    static func write(_ object: Any, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
    }

    static func jsonLines(_ objects: [[String: Any]], to url: URL) throws {
        var text = ""
        for object in objects {
            // Sorted keys so two identical objects serialise to identical
            // bytes — a whole-file mirror must hash the same.
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            text += String(data: data, encoding: .utf8) ?? ""
            text += "\n"
        }
        try write(text, to: url)
    }

    static func jsonString(_ object: Any) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    static func at(hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: now))!
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter.string(from: date)
    }

    static func millis(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

    static func ledger(_ records: [AgentUsageRecord], namespace: String = "editor") -> UsageLedger {
        AgentUsageLedger.build(records, prices: prices, namespace: namespace, calendar: calendar)
    }

    static func makeDatabase(at url: URL, statements: [String]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        let opened = sqlite3_open(url.path, &handle)
        defer { sqlite3_close(handle) }
        try #require(opened == SQLITE_OK)
        for sql in statements {
            let executed = sqlite3_exec(handle, sql, nil, nil, nil)
            try #require(executed == SQLITE_OK)
        }
    }
}

/// The Group B catalog: exactly nine clients, each with real inputs and a real
/// parser, dispatched to the right family.
@Suite("Editor log readers")
struct EditorLogReadersCatalogTests {
    private static let expectedClients: Set<String> = [
        "roocode", "kilocode", "cline", "codebuddy", "workbuddy",
        "cherrystudio", "commandcode", "opencodereview", "zcode",
    ]

    @Test("The supported set is exactly the clients that parse, and nothing else")
    func supportedClientsMatchReaders() {
        #expect(EditorLogReaders.supportedClients == Self.expectedClients)
        #expect(EditorLogReaders.records(client: "nope", roots: []).isEmpty)
        #expect(EditorLogReaders.inputs(client: "nope", home: URL(fileURLWithPath: "/tmp")).isEmpty)
    }

    @Test("Inputs name the macOS Application Support root as well as the .config spelling")
    func vsCodeInputs() {
        let home = URL(fileURLWithPath: "/Users/test")
        for (client, extensionID) in [
            ("roocode", "rooveterinaryinc.roo-cline"),
            ("kilocode", "kilocode.kilo-code"),
            ("cline", "saoudrizwan.claude-dev"),
        ] {
            let roots = EditorLogReaders.inputs(client: client, home: home).map(\.path)
            #expect(
                roots.contains(
                    "/Users/test/Library/Application Support/Code/User/globalStorage/\(extensionID)/tasks"
                )
            )
            #expect(
                roots.contains("/Users/test/.config/Code/User/globalStorage/\(extensionID)/tasks")
            )
            #expect(
                roots.contains(
                    "/Users/test/.vscode-server/data/User/globalStorage/\(extensionID)/tasks"
                )
            )
        }
    }

    @Test("Cline also names its CLI fallback, and the environment overrides win")
    func clineCLIInputs() {
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(EditorLogReaders.inputs(client: "cline", home: home).map(\.path).contains("/Users/test/.cline/data/sessions"))

        let session = EditorLogReaders.inputs(
            client: "cline", home: home,
            environment: ["CLINE_SESSION_DATA_DIR": "/data/cline-sessions"]
        )
        #expect(session.map(\.path).contains("/data/cline-sessions"))

        let data = EditorLogReaders.inputs(
            client: "cline", home: home, environment: ["CLINE_DATA_DIR": "/data/cline"]
        )
        #expect(data.map(\.path).contains("/data/cline/sessions"))

        let base = EditorLogReaders.inputs(
            client: "cline", home: home, environment: ["CLINE_DIR": "/data/cline-dir"]
        )
        #expect(base.map(\.path).contains("/data/cline-dir/data/sessions"))

        // A blank override is absent, not the current directory.
        let blank = EditorLogReaders.inputs(
            client: "cline", home: home, environment: ["CLINE_SESSION_DATA_DIR": "   "]
        )
        #expect(blank.map(\.path).contains("/Users/test/.cline/data/sessions"))
    }

    @Test("The standalone clients name their product tree and referenced database")
    func standaloneInputs() {
        let home = URL(fileURLWithPath: "/Users/test")

        #expect(EditorLogReaders.inputs(client: "codebuddy", home: home).map(\.path) == ["/Users/test/.codebuddy"])
        #expect(
            EditorLogReaders.inputs(client: "workbuddy", home: home).map(\.path)
                == ["/Users/test/.workbuddy", "/Users/test/.workbuddy-ai"]
        )

        let cherry = EditorLogReaders.inputs(client: "cherrystudio", home: home).map(\.path)
        #expect(
            cherry.first
                == "/Users/test/Library/Application Support/CherryStudio/Data/Agents/.claude/projects"
        )
        #expect(
            cherry.contains("/Users/test/Library/Application Support/CherryStudio/.claude/projects")
        )

        let commandCode = EditorLogReaders.inputs(client: "commandcode", home: home).map(\.path)
        #expect(commandCode.contains("/Users/test/.commandcode/projects"))
        #expect(commandCode.contains("/Users/test/.commandcode/config.json"))

        #expect(
            EditorLogReaders.inputs(client: "opencodereview", home: home).map(\.path)
                == ["/Users/test/.opencodereview/sessions"]
        )

        let zcode = EditorLogReaders.inputs(client: "zcode", home: home).map(\.path)
        #expect(zcode.contains("/Users/test/.zcode/projects"))
        #expect(zcode.contains("/Users/test/.zcode/cli/db/db.sqlite"))
    }
}

/// Roo Code, Kilo Code and Cline's VS Code task logs: one `api_req_started`
/// entry is one request, the model comes from the entry or the history, and an
/// entry with no parseable timestamp is skipped.
@Suite("VS Code task logs")
struct VSCodeTaskLogReaderTests {
    private static func usage(
        input: Int, output: Int, cacheRead: Int, cacheWrite: Int
    ) -> String {
        EditorTestSupport.jsonString([
            "cost": 0,
            "tokensIn": input,
            "tokensOut": output,
            "cacheReads": cacheRead,
            "cacheWrites": cacheWrite,
            "apiProtocol": "anthropic",
        ])
    }

    private static func task(_ root: URL, name: String = "task-a") throws -> URL {
        let task = root.appending(path: name)
        let nine = EditorTestSupport.iso(EditorTestSupport.at(hour: 9))
        let ten = EditorTestSupport.iso(EditorTestSupport.at(hour: 10))

        let entries: [[String: Any]] = [
            [
                "type": "say", "say": "api_req_started", "ts": nine,
                "text": usage(input: 100, output: 40, cacheRead: 30, cacheWrite: 20),
                "modelInfo": ["providerId": "anthropic", "modelId": "claude-sonnet"],
            ],
            // No `modelInfo`: the history's `<model>` tag is the fallback.
            [
                "type": "say", "say": "api_req_started", "ts": EditorTestSupport.millis(EditorTestSupport.at(hour: 10)),
                "text": usage(input: 5, output: 6, cacheRead: 7, cacheWrite: 8),
            ],
            // Other message kinds are not requests.
            ["type": "say", "say": "text", "ts": ten, "text": "hello"],
            [
                "type": "ask", "say": "api_req_started", "ts": ten,
                "text": usage(input: 1, output: 1, cacheRead: 1, cacheWrite: 1),
            ],
            // No timestamp: skipped, never stamped with the file's date.
            ["type": "say", "say": "api_req_started", "text": usage(input: 9, output: 9, cacheRead: 0, cacheWrite: 0)],
            // Unreadable usage text: skipped.
            ["type": "say", "say": "api_req_started", "ts": ten, "text": "not json"],
            // All-zero usage: no record.
            [
                "type": "say", "say": "api_req_started", "ts": ten,
                "text": usage(input: 0, output: 0, cacheRead: 0, cacheWrite: 0),
            ],
        ]
        try EditorTestSupport.write(entries, to: task.appending(path: "ui_messages.json"))

        let history = """
        [{"role":"user","content":"do the thing <environment_details>\\n<model>claude-sonnet</model>\\n<slug>roo</slug>\\n<name>Roo Code</name>\\n</environment_details>"}]
        """
        try EditorTestSupport.write(history, to: task.appending(path: "api_conversation_history.json"))
        return task
    }

    @Test("Only api_req_started entries count, with each bucket mapped independently")
    func readsRequests() throws {
        let root = try EditorTestSupport.temporary("vscode")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try Self.task(root)

        let records = EditorLogReaders.records(client: "roocode", roots: [root])
        try #require(records.count == 2)

        let first = records[0]
        #expect(first.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40))
        #expect(first.model == "claude-sonnet")
        #expect(first.sessionID == "task-a")
        #expect(first.sessionName == "roo")
        #expect(first.timestamp == EditorTestSupport.at(hour: 9))

        // The fallback model comes from the environment block.
        let second = records[1]
        #expect(second.tally == TokenTally(input: 5, cacheWrite: 8, cacheRead: 7, output: 6))
        #expect(second.model == "claude-sonnet")
        #expect(second.timestamp == EditorTestSupport.at(hour: 10))
    }

    @Test("Kilo and Cline read the same task shape under their own roots")
    func siblingsShareTheFormat() throws {
        let root = try EditorTestSupport.temporary("vscode-siblings")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try Self.task(root, name: "kilo-task")

        for client in ["kilocode", "cline"] {
            let records = EditorLogReaders.records(client: client, roots: [root])
            try #require(records.count == 2)
            #expect(records.first?.sessionID == "kilo-task")
        }
    }
}

/// The Cline CLI's newer session store: an assistant message with `metrics`,
/// whose `inputTokens` is cache-inclusive.
@Suite("Cline CLI sessions")
struct ClineCLIReaderTests {
    private static func session(root: URL, name: String = "sess-1") throws {
        let directory = root.appending(path: name)
        let at = EditorTestSupport.millis(EditorTestSupport.at(hour: 9))

        let messages: [String: Any] = [
            "sessionId": name,
            "agent": "cline",
            "messages": [
                [
                    "id": "m1", "role": "assistant", "ts": at,
                    "content": [["type": "text", "text": "done"]],
                    "modelInfo": ["id": "gpt-5", "provider": "openai"],
                    "metrics": [
                        "inputTokens": 100, "outputTokens": 40,
                        "cacheReadTokens": 30, "cacheWriteTokens": 20, "cost": 0,
                    ],
                ],
                // A user turn carries no metrics.
                ["id": "u1", "role": "user", "ts": at, "content": [["type": "text", "text": "go"]]],
                // Assistant with metrics but no ts: skipped.
                [
                    "id": "m2", "role": "assistant",
                    "metrics": ["inputTokens": 9, "outputTokens": 9, "cacheReadTokens": 0, "cacheWriteTokens": 0],
                ],
                // Assistant without metrics: not a record.
                ["id": "m3", "role": "assistant", "ts": at],
            ],
        ]
        try EditorTestSupport.write(messages, to: directory.appending(path: "\(name).messages.json"))

        let manifest: [String: Any] = [
            "sessionId": name,
            "provider": "openai",
            "model": "gpt-5",
            "cwd": "/work",
            "workspace_root": "/work/pulse",
            "metadata": ["title": "Fix the ring"],
        ]
        try EditorTestSupport.write(manifest, to: directory.appending(path: "\(name).json"))
    }

    @Test("Input is cache-exclusive, and the manifest supplies session metadata")
    func readsAssistantMetrics() throws {
        let root = try EditorTestSupport.temporary("cline-cli")
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.session(root: root)

        let records = EditorLogReaders.records(client: "cline", roots: [root])
        try #require(records.count == 1)

        let record = records[0]
        // 100 input less the two cache counts.
        #expect(record.tally == TokenTally(input: 50, cacheWrite: 20, cacheRead: 30, output: 40))
        #expect(record.model == "gpt-5")
        #expect(record.sessionID == "sess-1")
        #expect(record.project == "/work/pulse")
        #expect(record.title == "Fix the ring")
        #expect(record.deduplicationID == "cline:sess-1:m1")
    }

    @Test("An input smaller than the cache counts clamps at zero rather than going negative")
    func inputClampsAtZero() throws {
        let root = try EditorTestSupport.temporary("cline-clamp")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "s2")
        let at = EditorTestSupport.millis(EditorTestSupport.at(hour: 9))
        try EditorTestSupport.write(
            [
                "sessionId": "s2", "agent": "cline",
                "messages": [[
                    "id": "m1", "role": "assistant", "ts": at,
                    "modelInfo": ["id": "gpt-5"],
                    "metrics": [
                        "inputTokens": 10, "outputTokens": 4,
                        "cacheReadTokens": 6, "cacheWriteTokens": 8,
                    ],
                ]],
            ],
            to: directory.appending(path: "s2.messages.json")
        )

        let records = EditorLogReaders.records(client: "cline", roots: [root])
        try #require(records.count == 1)
        #expect(records[0].tally == TokenTally(input: 0, cacheWrite: 8, cacheRead: 6, output: 4))
        // No manifest, so the session id is the message file's own stem.
        #expect(records[0].sessionID == "s2")
    }

    @Test("A session id falls back from the messages file to the manifest to the stem")
    func sessionFallbacks() throws {
        let root = try EditorTestSupport.temporary("cline-fallback")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "s3")
        let at = EditorTestSupport.millis(EditorTestSupport.at(hour: 9))
        try EditorTestSupport.write(
            [
                "agent": "cline",
                "messages": [[
                    "id": "m1", "role": "assistant", "ts": at,
                    "modelInfo": ["id": "gpt-5"],
                    "metrics": ["inputTokens": 5, "outputTokens": 1, "cacheReadTokens": 0, "cacheWriteTokens": 0],
                ]],
            ],
            to: directory.appending(path: "s3.messages.json")
        )
        try EditorTestSupport.write(
            ["sessionId": "manifest-session", "model": "gpt-5"],
            to: directory.appending(path: "s3.json")
        )

        let records = EditorLogReaders.records(client: "cline", roots: [root])
        #expect(records.first?.sessionID == "manifest-session")
    }
}
