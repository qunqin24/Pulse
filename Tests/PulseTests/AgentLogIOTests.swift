import Foundation
import SQLite3
import Testing
@testable import Pulse

/// The shared read-only helpers: files, JSON, numbers, time and SQLite.
///
/// Every store here is a private temporary root — no user data is read, and
/// cleanup removes only the root the test created.
@Suite("Agent log IO")
struct AgentLogIOTests {
    private static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulseAgentLogIO-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    // MARK: - Counts

    @Test("A count is a whole, finite, in-range number — never a boolean, fraction or overflow")
    func countsRejectBooleansFractionsAndOverflow() {
        #expect(AgentLogIO.count(NSNumber(value: 42)) == 42)
        #expect(AgentLogIO.count(NSNumber(value: 2.0)) == 2)
        #expect(AgentLogIO.count(NSNumber(value: true)) == nil)
        #expect(AgentLogIO.count(NSNumber(value: 2.5)) == nil)
        #expect(AgentLogIO.count(NSNumber(value: -1)) == nil)
        #expect(AgentLogIO.count(NSNumber(value: UInt64.max)) == nil)
        #expect(AgentLogIO.count(NSNumber(value: Double.greatestFiniteMagnitude)) == nil)
        #expect(AgentLogIO.count(NSNumber(value: Double.nan)) == nil)

        // A numeric string is a count only as a whole number.
        #expect(AgentLogIO.count("42") == 42)
        #expect(AgentLogIO.count("-1") == nil)
        #expect(AgentLogIO.count("2.5") == nil)
        #expect(AgentLogIO.count("nope") == nil)

        // Missing is not zero.
        #expect(AgentLogIO.count(nil) == nil)
    }

    // MARK: - Time

    @Test("ISO timestamps read fractions and offsets; numbers take the unit the caller states")
    func timestamps() throws {
        #expect(AgentLogIO.timestamp("1970-01-01T00:00:00Z")?.timeIntervalSince1970 == 0)
        #expect(AgentLogIO.timestamp("1970-01-01T00:00:00.500Z")?.timeIntervalSince1970 == 0.5)
        // A stated offset is honoured, not ignored.
        #expect(AgentLogIO.timestamp("1970-01-01T08:00:00+08:00")?.timeIntervalSince1970 == 0)

        // Seconds by default, milliseconds only when asked.
        #expect(AgentLogIO.timestamp(NSNumber(value: 1000))?.timeIntervalSince1970 == 1000)
        #expect(AgentLogIO.timestamp(NSNumber(value: 1000), milliseconds: true)?.timeIntervalSince1970 == 1)
        #expect(AgentLogIO.timestamp("1000")?.timeIntervalSince1970 == 1000)

        #expect(AgentLogIO.timestamp(NSNumber(value: true)) == nil)
        #expect(AgentLogIO.timestamp(NSNumber(value: Double.nan)) == nil)
        #expect(AgentLogIO.timestamp(NSNumber(value: Double.infinity)) == nil)
        #expect(AgentLogIO.timestamp("not a date") == nil)
        #expect(AgentLogIO.timestamp(nil) == nil)
    }

    // MARK: - JSON

    @Test("Malformed JSON is nil or a skipped line, never a partial value")
    func malformedJSONIsSkipped() throws {
        let root = try Self.temporary("json")
        defer { try? FileManager.default.removeItem(at: root) }

        let good = root.appending(path: "good.json")
        try Self.write(#"{"model":"x","count":3}"#, to: good)
        #expect(AgentLogIO.object(AgentLogIO.json(at: good))?["model"] as? String == "x")

        let bad = root.appending(path: "bad.json")
        try Self.write("{not json", to: bad)
        #expect(AgentLogIO.json(at: bad) == nil)
        #expect(AgentLogIO.json(at: root.appending(path: "missing.json")) == nil)

        let lines = root.appending(path: "lines.jsonl")
        try Self.write(
            "{\"a\":1}\n" +
            "this is not json\n" +
            "{\"b\":2}\n" +
            "[1,2,3]\n" +
            "\n" +
            "{\"c\":3}\n",
            to: lines
        )
        let rows = Array(AgentLogIO.jsonLines(at: lines))
        #expect(rows.count == 3)
        #expect(rows.compactMap { $0["a"] as? Int ?? $0["b"] as? Int ?? $0["c"] as? Int } == [1, 2, 3])
        #expect(Array(AgentLogIO.jsonLines(at: root.appending(path: "missing.jsonl"))).isEmpty)

        #expect(AgentLogIO.text("  hi  ") == "hi")
        #expect(AgentLogIO.text("   ") == nil)
        #expect(AgentLogIO.text(5) == nil)
    }

    // MARK: - Files

    @Test("Files include hidden logs, survive duplicate roots, and exclude `-shm`")
    func filesWalkHiddenLogsWithoutDuplicates() throws {
        let root = try Self.temporary("files")
        defer { try? FileManager.default.removeItem(at: root) }

        let hidden = root.appending(path: ".logs")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Self.write("{}\n", to: hidden.appending(path: "capture.jsonl"))
        try Self.write("{}\n", to: root.appending(path: "state.json"))
        try Self.write("shared", to: root.appending(path: "x.db-shm"))

        // Both the hidden log and the visible state file are found; the shared
        // memory index is not a source.
        let all = AgentLogIO.files(in: [root])
        #expect(all.map(\.lastPathComponent).sorted() == ["capture.jsonl", "state.json"])

        // A duplicate root is walked once.
        #expect(AgentLogIO.files(in: [root, root]).count == all.count)

        // Filters: either match when both are given.
        #expect(AgentLogIO.files(in: [root], extensions: ["jsonl"]).map(\.lastPathComponent) == ["capture.jsonl"])
        #expect(
            AgentLogIO.files(in: [root], extensions: ["jsonl"], names: ["state.json"])
                .map(\.lastPathComponent).sorted() == ["capture.jsonl", "state.json"]
        )
        #expect(AgentLogIO.files(in: [root], names: ["state.json"]).map(\.lastPathComponent) == ["state.json"])

        // A single file root is honoured directly.
        #expect(
            AgentLogIO.files(in: [root.appending(path: "state.json")]).map(\.lastPathComponent)
                == ["state.json"]
        )
    }

    // MARK: - SQLite

    @Test("Reading a missing database read-only reports nothing and creates no file")
    func missingDatabaseIsNotCreated() throws {
        let root = try Self.temporary("missing-db")
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appending(path: "sessions.db")

        let value = AgentSQLite.read(at: db) { database in
            AgentSQLite.each(database, sql: "SELECT 1") { _ in }
            return true
        }

        #expect(value == nil)
        #expect(!FileManager.default.fileExists(atPath: db.path))
    }

    @Test("A valid query reads its rows read-only")
    func validQueryReadsRows() throws {
        let root = try Self.temporary("valid-db")
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appending(path: "sessions.db")

        var writer: OpaquePointer?
        #expect(sqlite3_open(db.path, &writer) == SQLITE_OK)
        for sql in [
            "CREATE TABLE sessions (id TEXT, tokens INTEGER, blob BLOB)",
            "INSERT INTO sessions VALUES ('s1', 10, X'0102')",
            "INSERT INTO sessions VALUES ('s2', 20, NULL)",
        ] {
            #expect(sqlite3_exec(writer, sql, nil, nil, nil) == SQLITE_OK)
        }
        sqlite3_close(writer)

        let rows = AgentSQLite.read(at: db) { database -> [(String, Int?)] in
            var found: [(String, Int?)] = []
            AgentSQLite.each(database, sql: "SELECT id, tokens FROM sessions ORDER BY id") { statement in
                found.append((AgentSQLite.text(statement, column: 0) ?? "", AgentLogIO.count(AgentSQLite.text(statement, column: 1))))
            }
            return found
        }

        // `text` on an integer column still reads; the count comes out whole.
        #expect(rows?.count == 2)
        #expect(rows?.first?.0 == "s1")
        #expect(rows?.first?.1 == 10)

        // A schema that does not match yields no rows rather than failing.
        let missing = AgentSQLite.read(at: db) { database -> Int in
            var count = 0
            AgentSQLite.each(database, sql: "SELECT * FROM nope") { _ in count += 1 }
            return count
        }
        #expect(missing == 0)

        // A blob column is data; NULL is nil.
        let blobs = AgentSQLite.read(at: db) { database -> [Data?] in
            var found: [Data?] = []
            AgentSQLite.each(database, sql: "SELECT blob FROM sessions ORDER BY id") { statement in
                found.append(AgentSQLite.data(statement, column: 0))
            }
            return found
        }
        #expect(blobs?.count == 2)
        if let blobs {
            #expect(blobs[0] == Data([0x01, 0x02]))
            #expect(blobs[1] == nil)
        }
    }

    @Test("A WAL database its owner has closed still reads, and nothing is created beside it")
    func closedWALDatabaseReads() throws {
        let root = try Self.temporary("closed-wal")
        defer { try? FileManager.default.removeItem(at: root) }
        // A space and a `#` in the name: the immutable open goes through a URI.
        let db = root.appending(path: "conversation #1.db")

        var writer: OpaquePointer?
        #expect(sqlite3_open(db.path, &writer) == SQLITE_OK)
        for sql in [
            "PRAGMA journal_mode=WAL",
            "CREATE TABLE steps (idx INTEGER, step_type INTEGER)",
            "INSERT INTO steps VALUES (1, 15)",
            "INSERT INTO steps VALUES (2, 15)",
        ] {
            #expect(sqlite3_exec(writer, sql, nil, nil, nil) == SQLITE_OK)
        }
        // Apple's SQLite keeps `-wal` and `-shm` after the last close by
        // default; Antigravity's does not. Turned off to behave like it.
        var persist: Int32 = 0
        #expect(sqlite3_file_control(writer, "main", SQLITE_FCNTL_PERSIST_WAL, &persist) == SQLITE_OK)
        sqlite3_close(writer)

        // Closing the last connection checkpoints and removes both files —
        // the state a plain read-only open cannot read (#117).
        let manager = FileManager.default
        #expect(!manager.fileExists(atPath: db.path + "-wal"))
        #expect(!manager.fileExists(atPath: db.path + "-shm"))
        #expect(AgentSQLite.isClosedWAL(db))

        let count = AgentSQLite.read(at: db) { database -> Int in
            var rows = 0
            AgentSQLite.each(database, sql: "SELECT idx FROM steps") { _ in rows += 1 }
            return rows
        }
        #expect(count == 2)
        #expect(!manager.fileExists(atPath: db.path + "-wal"))
        #expect(!manager.fileExists(atPath: db.path + "-shm"))
    }

    @Test("A rollback-journal database is never opened as immutable")
    func rollbackDatabaseIsNotImmutable() throws {
        let root = try Self.temporary("rollback")
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appending(path: "store.db")

        var writer: OpaquePointer?
        #expect(sqlite3_open(db.path, &writer) == SQLITE_OK)
        #expect(sqlite3_exec(writer, "CREATE TABLE t (x)", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(writer)

        #expect(!AgentSQLite.isClosedWAL(db))
        #expect(!AgentSQLite.isClosedWAL(root.appending(path: "missing.db")))
    }
}
