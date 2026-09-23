import Foundation
import Testing
@testable import Pulse

/// Tencent's two agents: a JSONL transcript with per-request usage, an
/// extension log whose usage line a mirrored sink may write twice, and
/// WorkBuddy's aggregate database whose single `used` quantity is reported as
/// unclassified rather than as fresh input.
@Suite("Tencent buddy readers")
struct TencentBuddyReaderTests {
    private static func transcriptLine(
        id: String,
        messageID: String?,
        usage: [String: Any],
        at: Date,
        status: String? = "completed",
        type: String = "message"
    ) -> [String: Any] {
        var line: [String: Any] = [
            "id": id,
            "timestamp": EditorTestSupport.millis(at),
            "type": type,
            "sessionId": "sess-a",
            "cwd": "/work/pulse",
        ]
        if let status { line["status"] = status }
        var provider: [String: Any] = ["model": "gpt-5"]
        if let messageID { provider["messageId"] = messageID }
        if type == "message" {
            line["role"] = "assistant"
            line["message"] = ["model": "gpt-5", "usage": usage]
        } else {
            provider["usage"] = usage
        }
        line["providerData"] = provider
        return line
    }

    @Test("JSONL keeps the larger snapshot, skips failed rows, and reports a bare total as unclassified")
    func transcript() throws {
        let home = try EditorTestSupport.temporary("codebuddy")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".codebuddy/projects/slug/s.jsonl")

        try EditorTestSupport.jsonLines([
            Self.transcriptLine(
                id: "line-1", messageID: "msg-1",
                usage: ["input_tokens": 100, "output_tokens": 40,
                        "cache_read_input_tokens": 30, "cache_creation_input_tokens": 20],
                at: EditorTestSupport.at(hour: 9)
            ),
            // Same message, a more complete snapshot.
            Self.transcriptLine(
                id: "line-2", messageID: "msg-1",
                usage: ["input_tokens": 150, "output_tokens": 50,
                        "cache_read_input_tokens": 40, "cache_creation_input_tokens": 25],
                at: EditorTestSupport.at(hour: 9)
            ),
            // A row the product itself calls incomplete.
            Self.transcriptLine(
                id: "line-3", messageID: "msg-3",
                usage: ["input_tokens": 999, "output_tokens": 999],
                at: EditorTestSupport.at(hour: 9), status: "failed"
            ),
            // A function call with its own identity.
            Self.transcriptLine(
                id: "line-4", messageID: "fn-1",
                usage: ["input_tokens": 1, "output_tokens": 2, "cache_read_input_tokens": 3,
                        "cache_creation_input_tokens": 4],
                at: EditorTestSupport.at(hour: 10), type: "function_call"
            ),
            // A bare total with no split.
            Self.transcriptLine(
                id: "line-5", messageID: "msg-5",
                usage: ["total_tokens": 500],
                at: EditorTestSupport.at(hour: 11)
            ),
            // A total equal to input + output proves input still contains the
            // cache counts.
            Self.transcriptLine(
                id: "line-6", messageID: "msg-6",
                usage: ["input_tokens": 100, "output_tokens": 30,
                        "cache_read_input_tokens": 20, "cache_creation_input_tokens": 5,
                        "total_tokens": 130],
                at: EditorTestSupport.at(hour: 12)
            ),
            // No timestamp: skipped rather than dated from the file.
            [
                "id": "line-7", "type": "message", "role": "assistant", "sessionId": "sess-a",
                "providerData": ["model": "gpt-5", "messageId": "msg-7"],
                "message": ["usage": ["input_tokens": 77, "output_tokens": 7]],
            ],
        ], to: file)

        let records = EditorLogReaders.records(
            client: "codebuddy",
            roots: EditorLogReaders.inputs(client: "codebuddy", home: home)
        )

        #expect(records.count == 4)
        // The two lines carrying the explicit `msg-1` id are one message.
        #expect(records.filter { $0.deduplicationID == "codebuddy:sess-a:msg-1" }.count == 1)
        let merged = try #require(records.first { $0.deduplicationID == "codebuddy:sess-a:msg-1" })
        #expect(merged.tally == TokenTally(input: 150, cacheWrite: 25, cacheRead: 40, output: 50))
        #expect(merged.project == "/work/pulse")

        let bare = try #require(records.first { $0.deduplicationID == "codebuddy:sess-a:msg-5" })
        #expect(bare.tally == TokenTally())
        #expect(bare.unclassifiedTokens == 500)
        #expect(!bare.isAggregate)

        let exclusive = try #require(records.first { $0.deduplicationID == "codebuddy:sess-a:msg-6" })
        #expect(exclusive.tally == TokenTally(input: 75, cacheWrite: 5, cacheRead: 20, output: 30))
        // No fallback was present, so the result is complete.
        #expect(records.allSatisfy { !$0.isPartial })
    }

    @Test("A transcript wins over an unreconcilable fallback and is marked partial")
    func transcriptWinsOverFallback() throws {
        let home = try EditorTestSupport.temporary("codebuddy-channels")
        defer { try? FileManager.default.removeItem(at: home) }

        // The same work is visible in both channels.
        try EditorTestSupport.jsonLines([
            Self.transcriptLine(
                id: "line-1", messageID: "m1",
                usage: ["input_tokens": 100, "output_tokens": 40,
                        "cache_read_input_tokens": 30, "cache_creation_input_tokens": 20],
                at: EditorTestSupport.at(hour: 9)
            ),
        ], to: home.appending(path: ".codebuddy/projects/slug/s.jsonl"))

        let usageJSON = EditorTestSupport.jsonString([
            "inputTokens": 100, "outputTokens": 40, "cacheTokens": 30, "cachedWriteTokens": 20,
        ])
        try EditorTestSupport.write(
            """
            2026/01/02 03:05:00.123 [CraftInvokableAgent] [agent-7] Model prepared: GPT Five (gpt-5)
            2026/01/02 03:05:04.000 [AgentReporter] [agent-7] Agent execution successful with usage: \(usageJSON)
            """,
            to: home.appending(path: ".codebuddy/logs/Pulse__2026.log")
        )

        let records = EditorLogReaders.records(
            client: "codebuddy",
            roots: EditorLogReaders.inputs(client: "codebuddy", home: home)
        )
        // Only the transcript is counted; appending the log would double count.
        try #require(records.count == 1)
        #expect(records[0].deduplicationID == "codebuddy:sess-a:m1")
        #expect(records[0].tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40))
        // The excluded fallback's scope is unknown, so the result is a subset.
        #expect(records[0].isPartial)
    }

    @Test("Reasoning is added to output only when the store's total proves it separate")
    func reasoningIsCountedOnce() throws {
        let home = try EditorTestSupport.temporary("codebuddy-reasoning")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".codebuddy/projects/slug/reasoning.jsonl")

        try EditorTestSupport.jsonLines([
            Self.transcriptLine(
                id: "r1", messageID: "r1",
                usage: ["input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 40,
                        "cache_creation_input_tokens": 5, "reasoningTokens": 7, "total_tokens": 202],
                at: EditorTestSupport.at(hour: 9)
            ),
            Self.transcriptLine(
                id: "r2", messageID: "r2",
                usage: ["input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 40,
                        "reasoningTokens": 7, "total_tokens": 150],
                at: EditorTestSupport.at(hour: 10)
            ),
            Self.transcriptLine(
                id: "r3", messageID: "r3",
                usage: ["input_tokens": 100, "output_tokens": 50, "reasoningTokens": 7],
                at: EditorTestSupport.at(hour: 11)
            ),
        ], to: file)

        let records = EditorLogReaders.records(
            client: "codebuddy",
            roots: EditorLogReaders.inputs(client: "codebuddy", home: home)
        )
        #expect(records.count == 3)

        let separate = try #require(records.first { $0.deduplicationID == "codebuddy:sess-a:r1" })
        #expect(separate.tally == TokenTally(input: 100, cacheWrite: 5, cacheRead: 40, output: 57))

        let inclusive = try #require(records.first { $0.deduplicationID == "codebuddy:sess-a:r2" })
        #expect(inclusive.tally == TokenTally(input: 60, cacheRead: 40, output: 50))
        #expect(inclusive.tally.output != 57)

        let noTotal = try #require(records.first { $0.deduplicationID == "codebuddy:sess-a:r3" })
        #expect(noTotal.tally == TokenTally(input: 100, output: 50))
    }

    @Test("The extension log counts same-second same-value lines separately rather than folding them")
    func extensionLog() throws {
        let home = try EditorTestSupport.temporary("workbuddy-log")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".workbuddy/logs/Pulse__2026.log")

        let usageJSON = EditorTestSupport.jsonString([
            "inputTokens": 100, "outputTokens": 40,
            "cacheTokens": 30, "cachedWriteTokens": 20, "totalTokens": 190,
        ])
        let text = """
        2026/01/02 03:05:00.123 [CraftInvokableAgent] [agent-7] Model prepared: GPT Five (gpt-5)
        2026/01/02 03:05:04.000 [AgentReporter] [agent-7] Agent execution successful with usage: \(usageJSON)
        2026/01/02 03:05:04.400 [AgentReporter] [agent-7] Agent execution successful with usage: \(usageJSON)
        2026/01/02 03:06:00.000 [AgentReporter] [agent-7] Agent execution successful with usage: {"totalTokens":500}
        """
        try EditorTestSupport.write(text, to: file)

        let roots = EditorLogReaders.inputs(client: "workbuddy", home: home)
        let records = EditorLogReaders.records(client: "workbuddy", roots: roots)
        // The two same-second, same-value lines are two real requests, so both
        // survive; the bare total is a third.
        #expect(records.count == 3)

        let usage = records.filter { $0.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40) }
        #expect(usage.count == 2)
        // No message id exists, so no business identity is invented.
        #expect(usage.allSatisfy { $0.deduplicationID == nil })
        // With only the fallback present, every independent line is kept and
        // nothing was excluded, so the result is complete.
        #expect(records.allSatisfy { !$0.isPartial })

        let record = try #require(usage.first)
        #expect(record.model == "gpt-5")
        #expect(record.sessionID == "agent-7")
        #expect(record.project == "Pulse")
        // The log writes a naive local wall-clock string, so its fields are
        // read back in the same calendar the parser used.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: record.timestamp
        )
        #expect(components.year == 2026)
        #expect(components.month == 1)
        #expect(components.day == 2)
        #expect(components.hour == 3)
        #expect(components.minute == 5)
        #expect(components.second == 4)

        let bare = try #require(records.first { $0.unclassifiedTokens == 500 })
        #expect(bare.tally == TokenTally())
    }

    @Test("The WorkBuddy database's single used quantity is aggregate and unclassified")
    func workbuddyDatabase() throws {
        let home = try EditorTestSupport.temporary("workbuddy-db")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".workbuddy/workbuddy.db")
        let updated = EditorTestSupport.millis(EditorTestSupport.at(hour: 9))

        try EditorTestSupport.makeDatabase(at: database, statements: [
            "CREATE TABLE sessions (id TEXT PRIMARY KEY, cwd TEXT, model TEXT)",
            "CREATE TABLE session_usage (session_id TEXT PRIMARY KEY, used INTEGER, size INTEGER, updated_at INTEGER, credit_json TEXT)",
            "INSERT INTO sessions VALUES ('s1', '/work/pulse', 'gpt-5')",
            "INSERT INTO session_usage VALUES ('s1', 1234, 0, \(updated), NULL)",
            // A row with no usable numbers is not a record.
            "INSERT INTO sessions VALUES ('s2', '/work/other', NULL)",
            "INSERT INTO session_usage VALUES ('s2', 0, 0, \(updated), NULL)",
        ])

        let records = EditorLogReaders.records(
            client: "workbuddy",
            roots: EditorLogReaders.inputs(client: "workbuddy", home: home)
        )

        try #require(records.count == 1)
        let record = records[0]
        #expect(record.model == "gpt-5")
        #expect(record.sessionID == "s1")
        #expect(record.project == "/work/pulse")
        #expect(record.tally == TokenTally())
        #expect(record.unclassifiedTokens == 1234)
        #expect(record.isAggregate)
        #expect(record.deduplicationID == "workbuddy:s1:\(updated)")
        // The database is the only channel here, so nothing was excluded.
        #expect(!record.isPartial)
    }
}
