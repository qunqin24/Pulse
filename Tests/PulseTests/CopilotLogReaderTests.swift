import Foundation
import SQLite3
import Testing
@testable import Pulse

/// Copilot's three stores: the OTEL JSONL export, the desktop SQLite database
/// with its session-state sidecar, and VS Code's chatSessions log.
///
/// Every store here is built by hand under a private temporary home; cleanup
/// removes only what this test created and no user store is read. Dates are
/// fixed, prices are explicit, and the chain test drives the same
/// `AgentUsageLedger.build` → `SpendSummary` → `ModelSpendSummary` path the app
/// uses.
@Suite("Copilot log readers")
struct CopilotLogReaderTests {
    private static let prices: [String: ModelPrice] = [
        "gpt-4o": ModelPrice(input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "GPT-4o")
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Store helpers

    private static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulseCopilot-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private static func writeLines(_ objects: [[String: Any]], to url: URL) throws {
        let lines = objects.compactMap { object -> String? in
            guard
                let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            else { return nil }
            return String(data: data, encoding: .utf8)
        }
        try Self.write(lines.joined(separator: "\n") + "\n", to: url)
    }

    private static func otel(_ home: URL, _ rows: [[String: Any]]) throws {
        try Self.writeLines(rows, to: home.appending(path: ".copilot/otel/monitoring.jsonl"))
    }

    private static func records(_ home: URL) -> [AgentUsageRecord] {
        CopilotLogReader.records(
            client: "copilot",
            roots: CopilotLogReader.inputs(client: "copilot", home: home, environment: [:])
        )
    }

    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private static func find(_ records: [AgentUsageRecord], _ dedup: String) -> AgentUsageRecord? {
        records.first { $0.deduplicationID == dedup }
    }

    /// One desktop database with the `sessions` schema and whatever rows the
    /// test hands it, plus a sidecar event log per session that names one.
    private static func desktopDatabase(
        _ home: URL,
        rows: [(id: String, title: String?, model: String?, input: Int, output: Int, cached: Int, reasoning: Int, created: String)],
        events: [String: [[String: Any]]]
    ) throws {
        let database = home.appending(path: ".copilot/data.db")
        try FileManager.default.createDirectory(
            at: database.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        try #require(sqlite3_open(database.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }

        try #require(sqlite3_exec(handle, """
        CREATE TABLE sessions (id TEXT, title TEXT, model TEXT, \
        total_input_tokens INTEGER, total_output_tokens INTEGER, \
        total_cached_tokens INTEGER, total_reasoning_tokens INTEGER, \
        total_nano_aiu INTEGER, created_at TEXT)
        """, nil, nil, nil) == SQLITE_OK)

        for row in rows {
            let title = row.title.map { "'\($0)'" } ?? "NULL"
            let model = row.model.map { "'\($0)'" } ?? "NULL"
            let sql = """
            INSERT INTO sessions VALUES ('\(row.id)', \(title), \(model), \
            \(row.input), \(row.output), \(row.cached), \(row.reasoning), 0, '\(row.created)')
            """
            try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }

        for (id, lines) in events {
            try Self.writeLines(
                lines, to: home.appending(path: ".copilot/session-state/\(id)/events.jsonl")
            )
        }
    }

    // MARK: - Dispatch and inputs

    @Test("Only copilot is supported, and inputs name the documented stores")
    func supportedClientsAndInputs() {
        #expect(CopilotLogReader.supportedClients == ["copilot"])
        #expect(CopilotLogReader.inputs(client: "nope", home: URL(fileURLWithPath: "/t")).isEmpty)
        #expect(CopilotLogReader.records(client: "nope", roots: []).isEmpty)

        let home = URL(fileURLWithPath: "/Users/test")
        let paths = CopilotLogReader.inputs(client: "copilot", home: home).map(\.path)
        #expect(paths.contains("/Users/test/.copilot/otel"))
        #expect(paths.contains("/Users/test/.copilot/data.db"))
        #expect(paths.contains("/Users/test/.copilot/session-state"))
        #expect(paths.contains("/Users/test/Library/Application Support/Code/User/workspaceStorage"))
        #expect(paths.contains("/Users/test/.config/Code/User/workspaceStorage"))
        #expect(paths.contains("/Users/test/AppData/Roaming/Code/User/workspaceStorage"))

        // The Windows profile is honoured when the environment names it.
        let windows = CopilotLogReader.inputs(
            client: "copilot", home: home, environment: ["APPDATA": "/win/roaming"]
        ).map(\.path)
        #expect(windows.contains("/win/roaming/Code/User/workspaceStorage"))
    }

    // MARK: - OTEL

    @Test("OTEL counts a chat span once, drops lower lanes, and keeps a bare total unclassified")
    func otel() throws {
        let home = try Self.temporary("otel")
        defer { try? FileManager.default.removeItem(at: home) }

        let chat: [String: Any] = [
            "type": "span", "name": "chat gpt-4o", "traceId": "T1", "spanId": "S1",
            "startTime": "2026-09-01T10:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.response.id": "R1",
                "gen_ai.conversation.id": "C1",
                "gen_ai.agent.id": "github.copilot.default",
                "gen_ai.usage.input_tokens": 1000,
                "gen_ai.usage.output_tokens": 200,
                "gen_ai.usage.cache_read.input_tokens": 400,
                "gen_ai.usage.cache_write.input_tokens": 50,
            ],
        ]
        // The same span written twice is one span.
        let inference: [String: Any] = [
            "time": "2026-09-01T10:00:00Z",
            "attributes": [
                "event.name": "gen_ai.client.inference.operation.details",
                "gen_ai.response.id": "R1",
                "gen_ai.conversation.id": "C1",
                "gen_ai.usage.input_tokens": 1000,
                "gen_ai.usage.output_tokens": 200,
            ],
        ]
        // An agent summary sharing a trace with a chat span is suppressed.
        let summary: [String: Any] = [
            "type": "span", "name": "invoke_agent gpt-4o", "traceId": "T2", "spanId": "S2",
            "startTime": "2026-09-01T11:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "invoke_agent",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.conversation.id": "C2",
                "gen_ai.usage.input_tokens": 500,
                "gen_ai.usage.output_tokens": 100,
            ],
        ]
        let chatT2: [String: Any] = [
            "type": "span", "name": "chat gpt-4o", "traceId": "T2", "spanId": "S3",
            "startTime": "2026-09-01T11:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.conversation.id": "C2",
                "gen_ai.usage.input_tokens": 300,
                "gen_ai.usage.output_tokens": 50,
            ],
        ]
        let bare: [String: Any] = [
            "type": "span", "name": "chat x", "traceId": "T3", "spanId": "S4",
            "startTime": "2026-09-01T12:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.conversation.id": "C3",
                "gen_ai.usage.total_tokens": 777,
            ],
        ]
        // No usable time and a negative count: skipped without trapping.
        let invalid: [String: Any] = [
            "type": "span", "name": "chat gpt-4o", "traceId": "T4", "spanId": "S5",
            "startTime": "not-a-date",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.usage.input_tokens": -5,
                "gen_ai.usage.output_tokens": 10,
            ],
        ]
        // A span with no token metadata at all is not a record.
        let tokenless: [String: Any] = [
            "type": "span", "name": "chat gpt-4o", "traceId": "T7", "spanId": "S7",
            "startTime": "2026-09-01T14:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.conversation.id": "C7",
            ],
        ]

        try Self.otel(home, [chat, chat, inference, summary, chatT2, bare, invalid, tokenless])
        let records = Self.records(home)
        #expect(records.count == 3)

        let span = try #require(Self.find(records, "copilot-otel:T1:S1"))
        #expect(span.model == "gpt-4o")
        #expect(span.timestamp == Self.date("2026-09-01T10:00:00Z"))
        #expect(span.sessionID == "C1")
        // The OTEL agent handle is carried as the session's stated name.
        #expect(span.sessionName == "GitHub Copilot")
        #expect(span.isAggregate == false)
        // Input counted the cache read; it is removed once. Reasoning, if any,
        // stays inside output.
        #expect(span.tally == TokenTally(input: 600, cacheWrite: 50, cacheRead: 400, output: 200))

        let second = try #require(Self.find(records, "copilot-otel:T2:S3"))
        #expect(second.tally == TokenTally(input: 300, output: 50))
        #expect(second.sessionID == "C2")

        let total = try #require(Self.find(records, "copilot-otel:T3:S4"))
        #expect(total.tally == TokenTally())
        #expect(total.unclassifiedTokens == 777)

        // The inference log, the agent summary and the token-less span
        // produced nothing.
        #expect(Self.find(records, "copilot-otel:T2:S2") == nil)
        #expect(!records.contains { ($0.deduplicationID ?? "").contains(":log:") })
        #expect(!records.contains { $0.sessionID == "C7" })
    }

    @Test("OTEL never folds two unnamed records by their shared instant, but folds an explicit replay")
    func otelIdentity() throws {
        let home = try Self.temporary("otel-identity")
        defer { try? FileManager.default.removeItem(at: home) }

        // No trace, span, response or session: the only thing the two files
        // share is the instant and the token figures. They are still two
        // distinct requests and both are counted.
        func unnamedSpan(_ model: String) -> [String: Any] {
            [
                "type": "span", "name": "chat \(model)",
                "startTime": "2026-09-01T10:00:00Z",
                "attributes": [
                    "gen_ai.operation.name": "chat",
                    "gen_ai.response.model": model,
                    "gen_ai.usage.input_tokens": 100,
                    "gen_ai.usage.output_tokens": 10,
                ],
            ]
        }
        try Self.writeLines(
            [unnamedSpan("gpt-4o")], to: home.appending(path: ".copilot/otel/a.jsonl")
        )
        try Self.writeLines(
            [unnamedSpan("gpt-4o")], to: home.appending(path: ".copilot/otel/b.jsonl")
        )

        let records = Self.records(home)
        let unnamed = records.filter { ($0.deduplicationID ?? "").contains("span-unnamed") }
        #expect(unnamed.count == 2)
        #expect(unnamed.reduce(0) { $0 + $1.tally.input } == 200)
        #expect(unnamed.allSatisfy { $0.isPartial })

        // An explicit trace + span written into two files is one event, so the
        // replay collapses.
        let replay: [String: Any] = [
            "type": "span", "name": "chat gpt-4o", "traceId": "TR", "spanId": "SP",
            "startTime": "2026-09-01T11:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.usage.input_tokens": 40,
                "gen_ai.usage.output_tokens": 4,
            ],
        ]
        try Self.writeLines(
            [replay], to: home.appending(path: ".copilot/otel/c.jsonl")
        )
        try Self.writeLines(
            [replay], to: home.appending(path: ".copilot/otel/d.jsonl")
        )

        let replayed = Self.records(home)
        #expect(replayed.filter { $0.deduplicationID == "copilot-otel:TR:SP" }.count == 1)
    }

    // MARK: - Desktop

    @Test("Desktop snapshots become per-run increments; a missing head is a baseline, not a day's work")
    func desktop() throws {
        let home = try Self.temporary("desktop")
        defer { try? FileManager.default.removeItem(at: home) }

        let desk1: [[String: Any]] = [
            ["type": "session.start", "timestamp": "2026-09-02T08:00:00Z",
             "data": ["context": ["cwd": "/Users/me/Code/Pulse"]]],
            ["type": "session.model_change", "timestamp": "2026-09-02T08:05:00Z",
             "data": ["newModel": "gpt-4o"]],
            ["type": "session.shutdown", "id": "e1", "timestamp": "2026-09-02T09:00:00Z",
             "data": ["currentModel": "gpt-4o", "modelMetrics": [
                "": ["usage": ["inputTokens": 400, "outputTokens": 80, "cacheReadTokens": 120,
                               "cacheWriteTokens": 10, "reasoningTokens": 20]],
             ]]],
            ["type": "session.shutdown", "id": "e2", "timestamp": "2026-09-03T10:00:00Z",
             "data": ["currentModel": "gpt-4o", "modelMetrics": [
                "gpt-4o": ["usage": ["inputTokens": 1000, "outputTokens": 200, "cacheReadTokens": 300,
                                     "cacheWriteTokens": 25, "reasoningTokens": 50]],
             ]]],
        ]
        // No session.start: the first snapshot is an unknown baseline.
        let desk2: [[String: Any]] = [
            ["type": "session.model_change", "timestamp": "2026-09-03T08:05:00Z",
             "data": ["newModel": "gpt-4o"]],
            ["type": "session.shutdown", "id": "f1", "timestamp": "2026-09-03T09:00:00Z",
             "data": ["currentModel": "gpt-4o", "modelMetrics": [
                "gpt-4o": ["usage": ["inputTokens": 500, "outputTokens": 60,
                                     "cacheReadTokens": 0, "cacheWriteTokens": 0, "reasoningTokens": 0]],
             ]]],
            ["type": "session.shutdown", "id": "f2", "timestamp": "2026-09-03T10:00:00Z",
             "data": ["currentModel": "gpt-4o", "modelMetrics": [
                "gpt-4o": ["usage": ["inputTokens": 800, "outputTokens": 100,
                                     "cacheReadTokens": 0, "cacheWriteTokens": 0, "reasoningTokens": 0]],
             ]]],
        ]

        try Self.desktopDatabase(
            home,
            rows: [
                ("desk1", "Ring", "gpt-4o", 1000, 200, 300, 50, "2026-09-02T08:00:00Z"),
                ("desk2", nil, "gpt-4o", 800, 100, 0, 0, "2026-09-03T08:00:00Z"),
                // Recorded by the CLI: a row with no sidecar at all.
                ("desk3", nil, "gpt-4o", 250, 25, 0, 0, "2026-09-04T08:00:00Z"),
                ("desk4", nil, nil, 0, 0, 0, 0, "2026-09-05T08:00:00Z"),
            ],
            events: ["desk1": desk1, "desk2": desk2]
        )

        let records = Self.records(home)
        #expect(records.count == 5)

        let run1 = try #require(Self.find(records, "copilot-desktop:desk1:shutdown:e1:gpt-4o"))
        #expect(run1.timestamp == Self.date("2026-09-02T09:00:00Z"))
        // The reported output is kept whole; the run's reasoning is not added
        // to it, and the run is marked partial instead.
        #expect(run1.tally == TokenTally(input: 400, cacheWrite: 10, cacheRead: 120, output: 80))
        #expect(run1.unclassifiedTokens == 0)
        #expect(run1.isPartial)
        #expect(run1.isAggregate)
        #expect(run1.sessionID == "desk1")
        #expect(run1.title == "Ring")
        #expect(run1.project == "/Users/me/Code/Pulse")

        // The second snapshot is the first minus the baseline; it lands on its
        // own calendar day. Output stays as reported (120, not 150): the 30
        // reasoning tokens are a possible subset and are not added.
        let run2 = try #require(Self.find(records, "copilot-desktop:desk1:shutdown:e2:gpt-4o"))
        #expect(run2.timestamp == Self.date("2026-09-03T10:00:00Z"))
        #expect(run2.tally == TokenTally(input: 600, cacheWrite: 15, cacheRead: 180, output: 120))
        #expect(run2.isPartial)

        // The headless session's first snapshot is not an increment; its tokens
        // fall to the row remainder at created_at.
        #expect(Self.find(records, "copilot-desktop:desk2:shutdown:f1:gpt-4o") == nil)
        let baseline = try #require(Self.find(records, "copilot-desktop:desk2:row"))
        #expect(baseline.timestamp == Self.date("2026-09-03T08:00:00Z"))
        #expect(baseline.tally == TokenTally(input: 500, output: 60))
        #expect(baseline.isAggregate)

        let after = try #require(Self.find(records, "copilot-desktop:desk2:shutdown:f2:gpt-4o"))
        #expect(after.tally == TokenTally(input: 300, output: 40))

        // A session with no sidecar is its row's lifetime total, once.
        let cli = try #require(Self.find(records, "copilot-desktop:desk3:row"))
        #expect(cli.timestamp == Self.date("2026-09-04T08:00:00Z"))
        #expect(cli.tally == TokenTally(input: 250, output: 25))

        #expect(!records.contains { $0.sessionID == "desk4" })
        #expect(records.filter { $0.deduplicationID?.contains(":desk1:") == true }
            .reduce(0) { $0 + $1.tally.cacheWrite } == 25)

        // The doubt reaches the ledger rather than being swallowed: a desktop
        // session that stated reasoning is reported partial.
        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "copilot", calendar: Self.calendar
        )
        #expect(ledger.hasPartialCounts)
    }

    @Test("Desktop reasoning the row cannot confirm is kept out of output and flagged, not added")
    func desktopReasoningIsAmbiguous() throws {
        let home = try Self.temporary("desktop-reasoning")
        defer { try? FileManager.default.removeItem(at: home) }

        // An older row with no reasoning column; the sidecar still reports it.
        // The flag must read the sidecar's own snapshot, not the zero the row
        // would have budgeted it down to.
        try Self.desktopDatabase(
            home,
            rows: [("s", nil, "gpt-4o", 300, 60, 0, 0, "2026-09-03T08:00:00Z")],
            events: ["s": [
                ["type": "session.start", "timestamp": "2026-09-03T08:00:00Z",
                 "data": ["context": ["cwd": "/work"]]],
                ["type": "session.shutdown", "id": "e1", "timestamp": "2026-09-03T09:00:00Z",
                 "data": ["currentModel": "gpt-4o", "modelMetrics": [
                     "gpt-4o": ["usage": ["inputTokens": 300, "outputTokens": 60,
                                          "cacheReadTokens": 0, "cacheWriteTokens": 0,
                                          "reasoningTokens": 25]],
                 ]]],
            ]]
        )

        let records = Self.records(home)
        let run = try #require(Self.find(records, "copilot-desktop:s:shutdown:e1:gpt-4o"))
        // 60, not 85: the 25 reasoning tokens are not added to output.
        #expect(run.tally == TokenTally(input: 300, output: 60))
        #expect(run.unclassifiedTokens == 0)
        #expect(run.isPartial)
    }

    // MARK: - VS Code

    @Test("VS Code replays the append log, folds thinking into output, and skips a request with no time")
    func vscode() throws {
        let home = try Self.temporary("vscode")
        defer { try? FileManager.default.removeItem(at: home) }

        let hashDirectory = home.appending(
            path: "Library/Application Support/Code/User/workspaceStorage/hash1"
        )
        try Self.write(
            #"{"folder":"file:///Users/me/Code/Pulse"}"#,
            to: hashDirectory.appending(path: "workspace.json")
        )

        let first: [String: Any] = [
            "promptTokens": 100, "completionTokens": 20, "timestamp": 1_788_267_600_000,
            "modelId": "copilot/gpt-4o",
            "result": ["metadata": ["toolCallRounds": [["thinking": ["tokens": 5]]]]],
        ]
        let second: [String: Any] = [
            "promptTokens": 200, "completionTokens": 40, "timestamp": 1_788_267_700_000,
            "modelId": "copilot/gpt-4o",
        ]
        // No timestamp: real Copilot work the format cannot date. There is no
        // session or report date to borrow, so it is skipped — never placed at
        // the epoch and never folded onto another untimed request.
        let untimed: [String: Any] = [
            "promptTokens": 30, "completionTokens": 4, "modelId": "copilot/gpt-4o",
        ]
        let untimedTwo: [String: Any] = [
            "promptTokens": 70, "completionTokens": 8, "modelId": "copilot/gpt-4o",
        ]
        let foreign: [String: Any] = [
            "promptTokens": 999, "completionTokens": 999, "timestamp": 1_788_267_800_000,
            "modelId": "other/model",
        ]
        // Copilot-originated but carries no token metadata: not a record.
        let tokenless: [String: Any] = [
            "timestamp": 1_788_267_900_000, "modelId": "copilot/gpt-4o",
        ]

        try Self.writeLines(
            [
                ["kind": 0, "v": ["requests": [first]]],
                // A streamed patch fills the resolved model in; a nested write
                // is not a new request.
                ["kind": 1, "k": ["requests", 0, "result", "metadata", "resolvedModel"], "v": "gpt-4o"],
                ["kind": 1, "k": ["requests", 0, "response"], "v": ["text": "streamed"]],
                ["kind": 2, "k": ["requests"], "v": [second, untimed, untimedTwo, foreign, tokenless]],
                // Out of range: dropped.
                ["kind": 1, "k": ["requests", 5, "x"], "v": 1],
            ],
            to: hashDirectory.appending(path: "chatSessions/vscode-session-1.jsonl")
        )

        let records = Self.records(home)
        // The two timed Copilot requests are kept; the two untimed ones are not.
        #expect(records.count == 2)

        let firstRecord = try #require(
            Self.find(records, "copilot-vscode:vscode-session-1:1788267600000")
        )
        #expect(firstRecord.model == "gpt-4o")
        #expect(firstRecord.tally == TokenTally(input: 100, output: 25))
        #expect(firstRecord.sessionID == "vscode-session-1")
        #expect(firstRecord.project == "/Users/me/Code/Pulse")
        #expect(firstRecord.isAggregate == false)
        #expect(firstRecord.timestamp == Date(timeIntervalSince1970: 1_788_267_600))

        let secondRecord = try #require(
            Self.find(records, "copilot-vscode:vscode-session-1:1788267700000")
        )
        #expect(secondRecord.tally == TokenTally(input: 200, output: 40))

        // No request was dated at the epoch, and neither untimed request's
        // tokens were counted anywhere.
        #expect(!records.contains { $0.timestamp == Date(timeIntervalSince1970: 0) })
        #expect(!records.contains { $0.tally.input == 30 || $0.tally.input == 70 })
        #expect(!records.contains { $0.tally.input == 999 })
    }

    @Test("Two VS Code requests that share a session and an instant are both kept")
    func vscodeSameInstantDistinctRequests() throws {
        let home = try Self.temporary("vscode-same-instant")
        defer { try? FileManager.default.removeItem(at: home) }

        let hashDirectory = home.appending(
            path: "Library/Application Support/Code/User/workspaceStorage/hash1"
        )
        // Same values, same millisecond: two requests, not one.
        let request: [String: Any] = [
            "promptTokens": 100, "completionTokens": 10, "timestamp": 1_788_267_600_000,
            "modelId": "copilot/gpt-4o",
        ]
        try Self.writeLines(
            [["kind": 0, "v": ["requests": [request, request]]]],
            to: hashDirectory.appending(path: "chatSessions/same.jsonl")
        )

        let records = Self.records(home)
        #expect(records.count == 2)
        #expect(records.reduce(0) { $0 + $1.tally.input } == 200)
        #expect(records.reduce(0) { $0 + $1.tally.output } == 20)
        // The two identities are distinct even though the format's own key
        // collides.
        #expect(Set(records.compactMap(\.deduplicationID)).count == 2)
    }

    // MARK: - Cross-source dedup

    @Test("A session OTEL saw is dropped from the desktop lane, and a matching VS Code instant is dropped")
    func crossSourceDedup() throws {
        let home = try Self.temporary("cross")
        defer { try? FileManager.default.removeItem(at: home) }

        let shared: [String: Any] = [
            "type": "span", "name": "chat gpt-4o", "traceId": "T9", "spanId": "S9",
            "startTime": "2026-09-01T10:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "copilot_chat.session_id": "desk-shared",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.usage.input_tokens": 100,
                "gen_ai.usage.output_tokens": 10,
            ],
        ]
        let editor: [String: Any] = [
            "type": "span", "name": "chat gpt-4o", "traceId": "T6", "spanId": "S6",
            "startTime": "2026-09-01T13:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "copilot_chat.session_id": "vscode-session-1",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.usage.input_tokens": 111,
                "gen_ai.usage.output_tokens": 22,
            ],
        ]
        try Self.otel(home, [shared, editor])

        try Self.desktopDatabase(
            home,
            rows: [
                ("desk-shared", nil, "gpt-4o", 500, 50, 0, 0, "2026-09-01T09:00:00Z"),
                ("desk-alone", nil, "gpt-4o", 200, 20, 0, 0, "2026-09-02T09:00:00Z"),
            ],
            events: [:]
        )

        let hashDirectory = home.appending(
            path: "Library/Application Support/Code/User/workspaceStorage/hash1"
        )
        let editorRequest: [String: Any] = [
            "promptTokens": 111, "completionTokens": 22, "timestamp": 1_788_267_600_000,
            "modelId": "copilot/gpt-4o",
        ]
        let laterRequest: [String: Any] = [
            "promptTokens": 200, "completionTokens": 40, "timestamp": 1_788_267_700_000,
            "modelId": "copilot/gpt-4o",
        ]
        try Self.writeLines(
            [["kind": 0, "v": ["requests": [editorRequest, laterRequest]]]],
            to: hashDirectory.appending(path: "chatSessions/vscode-session-1.jsonl")
        )

        let records = Self.records(home)
        // The desktop lane's copy of the session OTEL named is gone; the other
        // is kept. OTEL keeps its own record for that same session, which is
        // why this is asserted against the desktop provenance and not the
        // session id.
        #expect(!records.contains {
            ($0.deduplicationID ?? "").hasPrefix("copilot-desktop:desk-shared")
        })
        let alone = try #require(Self.find(records, "copilot-desktop:desk-alone:row"))
        #expect(!alone.isPartial)
        // The VS Code request at the OTEL instant is gone; the later one stays.
        #expect(Self.find(records, "copilot-vscode:vscode-session-1:1788267600000") == nil)
        #expect(Self.find(records, "copilot-vscode:vscode-session-1:1788267700000") != nil)
        // Both OTEL spans survive. The shared session's desktop row totals 550
        // while OTEL recorded only 110, so the dropped desktop remainder is not
        // silently zeroed: the OTEL records for that session are partial. The
        // other session has no desktop row and stays complete.
        let sharedOTEL = try #require(Self.find(records, "copilot-otel:T9:S9"))
        #expect(sharedOTEL.isPartial)
        let editorOTEL = try #require(Self.find(records, "copilot-otel:T6:S6"))
        #expect(!editorOTEL.isPartial)
    }

    @Test("Partial OTEL coverage leaves the desktop remainder flagged, never silently zeroed")
    func partialOTELCoverage() throws {
        let home = try Self.temporary("partial-otel")
        defer { try? FileManager.default.removeItem(at: home) }

        // OTEL recorded one 110-token span of the session.
        let span: [String: Any] = [
            "type": "span", "name": "chat gpt-4o", "traceId": "T1", "spanId": "S1",
            "startTime": "2026-09-01T10:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "copilot_chat.session_id": "shared",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.usage.input_tokens": 100,
                "gen_ai.usage.output_tokens": 10,
            ],
        ]
        try Self.otel(home, [span])

        // The desktop row is the same session's lifetime total: 550, larger
        // than OTEL's 110.
        try Self.desktopDatabase(
            home,
            rows: [("shared", nil, "gpt-4o", 500, 50, 0, 0, "2026-09-01T09:00:00Z")],
            events: [:]
        )

        let records = Self.records(home)
        let otel = try #require(Self.find(records, "copilot-otel:T1:S1"))
        // The desktop lane is subordinate and dropped, but the session is not
        // presented as a complete 110: the OTEL read is marked partial.
        #expect(otel.isPartial)
        #expect(!records.contains {
            ($0.deduplicationID ?? "").hasPrefix("copilot-desktop:shared")
        })

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "copilot", calendar: Self.calendar
        )
        #expect(ledger.hasPartialCounts)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 110)
    }

    // MARK: - Through the production chain

    @Test("Records reconcile through the ledger, SpendSummary and ModelSpendSummary")
    func productionChainReconciles() throws {
        let home = try Self.temporary("chain")
        defer { try? FileManager.default.removeItem(at: home) }

        let chat: [String: Any] = [
            "type": "span", "name": "chat gpt-4o", "traceId": "T1", "spanId": "S1",
            "startTime": "2026-09-01T10:00:00Z",
            "attributes": [
                "gen_ai.operation.name": "chat",
                "copilot_chat.session_id": "s1",
                "gen_ai.response.model": "gpt-4o",
                "gen_ai.usage.input_tokens": 100,
                "gen_ai.usage.output_tokens": 20,
                "gen_ai.usage.cache_read.input_tokens": 30,
                "gen_ai.usage.cache_write.input_tokens": 5,
            ],
        ]
        try Self.otel(home, [chat])

        let hashDirectory = home.appending(
            path: "Library/Application Support/Code/User/workspaceStorage/hash1"
        )
        let editorRequest: [String: Any] = [
            "promptTokens": 200, "completionTokens": 40, "timestamp": 1_788_267_600_000,
            "modelId": "copilot/gpt-4o",
            "result": ["metadata": ["toolCallRounds": [["thinking": ["tokens": 10]]]]],
        ]
        try Self.writeLines(
            [["kind": 0, "v": ["requests": [editorRequest]]]],
            to: hashDirectory.appending(path: "chatSessions/s2.jsonl")
        )

        try Self.desktopDatabase(
            home,
            rows: [("s3", nil, "gpt-4o", 300, 60, 90, 0, "2026-09-03T08:00:00Z")],
            events: ["s3": [
                ["type": "session.start", "timestamp": "2026-09-03T08:00:00Z",
                 "data": ["context": ["cwd": "/work"]]],
                ["type": "session.shutdown", "id": "e1", "timestamp": "2026-09-03T09:00:00Z",
                 "data": ["currentModel": "gpt-4o", "modelMetrics": [
                    "gpt-4o": ["usage": ["inputTokens": 300, "outputTokens": 60, "cacheReadTokens": 90,
                                         "cacheWriteTokens": 15, "reasoningTokens": 0]],
                 ]]],
            ]]
        )

        let records = Self.records(home)
        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "copilot", calendar: Self.calendar
        )

        // 125 (OTEL) + 250 (VS Code) + 465 (desktop) = 840.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 840)
        #expect(ledger.hasAggregateTiming)

        let now = Self.date("2026-09-10T00:00:00Z")
        let summary = SpendSummary.of(
            [.openCode: ledger], overLast: nil, now: now, calendar: Self.calendar
        )
        #expect(summary.tokens == 840)
        #expect(summary.hasAggregateTiming)
        #expect(summary.sessions.count == 3)
        #expect(abs(summary.cost - 1.902) < 1e-9)
        #expect(summary.agents.first?.tokens == 840)

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "GPT-4o", overLast: nil, now: now, calendar: Self.calendar
        )
        #expect(model.tokens == 840)
        #expect(model.tally == TokenTally(input: 570, cacheWrite: 20, cacheRead: 120, output: 130))
        #expect(abs((model.cost ?? -1) - 1.902) < 1e-9)
    }
}
