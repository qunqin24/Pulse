import Foundation
import Testing
@testable import Pulse

/// The ZCode JSONL transcript and its v2 usage database. A reported total
/// settles whether the input already contains the cache counts; without one
/// the values are kept as written, and a bare total is unclassified.
@Suite("ZCode reader")
struct ZCodeReaderTests {
    @Test("A total equal to input+output subtracts the cache overlap; a disjoint total does not")
    func reportedTotalSettlesInclusion() throws {
        let home = try EditorTestSupport.temporary("zcode-jsonl")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".zcode/projects/slug/session-a.jsonl")

        func stamp(_ hour: Int) -> String { EditorTestSupport.iso(EditorTestSupport.at(hour: hour)) }

        try EditorTestSupport.jsonLines([
            ["role": "assistant", "sessionId": "z1", "model": "claude-sonnet", "timestamp": stamp(9),
             "usage": ["input_tokens": 100, "output_tokens": 50, "cache_read_tokens": 20,
                       "cache_write_tokens": 5, "totalTokens": 150]],
            ["role": "assistant", "sessionId": "z1", "model": "claude-sonnet", "timestamp": stamp(10),
             "usage": ["input_tokens": 100, "output_tokens": 50, "cache_read_tokens": 20,
                       "cache_write_tokens": 5, "reasoningTokens": 7, "totalTokens": 182]],
            ["role": "assistant", "sessionId": "z1", "model": "gpt-5", "timestamp": stamp(11),
             "usage": ["totalTokens": 500]],
            ["role": "assistant", "sessionId": "z1", "model": "gpt-5", "timestamp": stamp(12),
             "token_usage": ["input_tokens": 3, "output_tokens": 4,
                             "cache_read_tokens": 0, "cache_write_tokens": 0]],
            ["role": "assistant", "sessionId": "z1", "model": "gpt-5", "timestamp": stamp(13)],
        ], to: file)

        let roots = EditorLogReaders.inputs(client: "zcode", home: home)
        let records = EditorLogReaders.records(client: "zcode", roots: roots)
        #expect(records.count == 4)

        let inclusive = try #require(
            records.first { $0.model == "claude-sonnet" && $0.tally.output == 50 && $0.tally.cacheRead == 20 }
        )
        #expect(inclusive.tally == TokenTally(input: 75, cacheWrite: 5, cacheRead: 20, output: 50))
        #expect(inclusive.unclassifiedTokens == 0)

        let disjoint = try #require(records.first { $0.model == "claude-sonnet" && $0.tally.output == 57 })
        #expect(disjoint.tally == TokenTally(input: 100, cacheWrite: 5, cacheRead: 20, output: 57))

        let bare = try #require(records.first { $0.unclassifiedTokens == 500 })
        #expect(bare.tally == TokenTally())

        #expect(records.contains { $0.tally == TokenTally(input: 3, output: 4) })
    }

    @Test("Reasoning is added to output only when the total proves it separate")
    func reasoningIsCountedOnce() throws {
        let home = try EditorTestSupport.temporary("zcode-reasoning")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".zcode/projects/slug/session-a.jsonl")

        func stamp(_ hour: Int) -> String { EditorTestSupport.iso(EditorTestSupport.at(hour: hour)) }

        try EditorTestSupport.jsonLines([
            // total == input + output, so reasoning is already inside output.
            ["role": "assistant", "sessionId": "z1", "model": "gpt-5", "timestamp": stamp(14),
             "usage": ["input_tokens": 100, "output_tokens": 50, "cache_read_tokens": 20,
                       "cache_write_tokens": 5, "reasoningTokens": 7, "totalTokens": 150]],
            // No total to prove it separate: keep the reported output whole.
            ["role": "assistant", "sessionId": "z1", "model": "gpt-5", "timestamp": stamp(15),
             "usage": ["input_tokens": 100, "output_tokens": 50, "reasoningTokens": 7]],
            // total names every kind, so reasoning is a bucket of its own.
            ["role": "assistant", "sessionId": "z1", "model": "gpt-5", "timestamp": stamp(16),
             "usage": ["input_tokens": 100, "output_tokens": 50, "reasoningTokens": 7,
                       "totalTokens": 157]],
        ], to: file)

        let records = EditorLogReaders.records(
            client: "zcode",
            roots: EditorLogReaders.inputs(client: "zcode", home: home)
        )
        #expect(records.count == 3)

        let inclusive = try #require(records.first { $0.tally.cacheRead == 20 })
        #expect(inclusive.tally == TokenTally(input: 75, cacheWrite: 5, cacheRead: 20, output: 50))
        #expect(inclusive.tally.output != 57)

        let noTotal = try #require(records.first { $0.timestamp == EditorTestSupport.at(hour: 15) })
        #expect(noTotal.tally == TokenTally(input: 100, output: 50))

        let separate = try #require(records.first { $0.timestamp == EditorTestSupport.at(hour: 16) })
        #expect(separate.tally == TokenTally(input: 100, output: 57))
    }

    @Test("The modern database subtracts the cache overlap and reads the session directory")
    func modernDatabase() throws {
        let home = try EditorTestSupport.temporary("zcode-db")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".zcode/cli/db/db.sqlite")
        let at = EditorTestSupport.millis(EditorTestSupport.at(hour: 9))

        try EditorTestSupport.makeDatabase(at: database, statements: [
            "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, path TEXT)",
            """
            CREATE TABLE model_usage (id TEXT, session_id TEXT, model_id TEXT, started_at INTEGER,
            completed_at INTEGER, input_tokens INTEGER, output_tokens INTEGER, reasoning_tokens INTEGER,
            cache_read_input_tokens INTEGER, cache_creation_input_tokens INTEGER, computed_total_tokens INTEGER)
            """,
            "INSERT INTO session VALUES ('s1', '/work/pulse', '/work/pulse')",
            // computed total equals input+output: the input still contains the cache counts.
            "INSERT INTO model_usage VALUES ('r1', 's1', 'claude-sonnet', \(at), NULL, 100, 50, 7, 20, 5, 150)",
            // computed total above every named kind: the remainder is unclassified.
            "INSERT INTO model_usage VALUES ('r2', 's1', 'gpt-5', \(at), NULL, 100, 50, 7, 20, 5, 500)",
        ])

        let records = EditorLogReaders.records(
            client: "zcode",
            roots: EditorLogReaders.inputs(client: "zcode", home: home)
        )
        #expect(records.count == 2)

        let first = try #require(records.first { $0.deduplicationID?.hasSuffix(":r1") == true })
        #expect(first.model == "claude-sonnet")
        #expect(first.tally == TokenTally(input: 75, cacheWrite: 5, cacheRead: 20, output: 50))
        #expect(first.unclassifiedTokens == 0)
        #expect(first.sessionID == "s1")
        #expect(first.project == "/work/pulse")
        #expect(!first.isAggregate)

        let second = try #require(records.first { $0.deduplicationID?.hasSuffix(":r2") == true })
        // The schema's output already contains reasoning, so the union is
        // input + output = 150, and the rest of the 500 is unclassified.
        #expect(second.tally == TokenTally(input: 75, cacheWrite: 5, cacheRead: 20, output: 50))
        #expect(second.unclassifiedTokens == 350)
    }

    @Test("A legacy schema without the total column or session table still reads")
    func legacySchema() throws {
        let home = try EditorTestSupport.temporary("zcode-legacy")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".zcode/cli/db/db.sqlite")
        let at = EditorTestSupport.millis(EditorTestSupport.at(hour: 9))

        try EditorTestSupport.makeDatabase(at: database, statements: [
            """
            CREATE TABLE model_usage (id TEXT, session_id TEXT, model_id TEXT, started_at INTEGER,
            completed_at INTEGER, input_tokens INTEGER, output_tokens INTEGER, reasoning_tokens INTEGER,
            cache_read_input_tokens INTEGER, cache_creation_input_tokens INTEGER)
            """,
            "INSERT INTO model_usage VALUES ('r1', 's1', 'claude-sonnet', \(at), NULL, 100, 50, 7, 20, 5)",
        ])

        let records = EditorLogReaders.records(
            client: "zcode",
            roots: EditorLogReaders.inputs(client: "zcode", home: home)
        )
        try #require(records.count == 1)
        let record = records[0]
        // The legacy schema is documented cache-inclusive, so the overlap goes.
        #expect(record.tally == TokenTally(input: 75, cacheWrite: 5, cacheRead: 20, output: 50))
        #expect(record.unclassifiedTokens == 0)
        #expect(record.sessionID == "s1")
        #expect(record.project == nil)
    }
}
