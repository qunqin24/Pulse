import Foundation
import SQLite3
import Testing
@testable import Pulse

/// Antigravity's activity mark: the newest step of each recently written
/// conversation database. The step numbers are the ones `agy` 1.5 writes;
/// the databases here are built by the test, holding only the two columns
/// the reader asks for.
@Suite("Antigravity activity")
struct AntigravityActivityTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static let userInput = 14, response = 15, tool = 132
    private static let running = 2, done = 3, canceled = 6, error = 7, generating = 8, waiting = 9

    @Test("Each step status says whose move it is")
    func verdicts() {
        let verdict = AgentActivity.antigravityVerdict(type:status:)
        #expect(verdict(Self.response, Self.generating) == .working(.model, at: nil))
        #expect(verdict(Self.tool, Self.running) == .working(.tool, at: nil))
        // A finished prompt or tool hands the turn back to the model.
        #expect(verdict(Self.userInput, Self.done) == .working(.model, at: nil))
        #expect(verdict(Self.tool, Self.done) == .working(.model, at: nil))
        // Every turn ends on a finished model response.
        #expect(verdict(Self.response, Self.done) == .finished)
        // Waiting for a person, or a step that failed, is not work.
        #expect(verdict(Self.tool, Self.waiting) == .finished)
        #expect(verdict(Self.tool, Self.error) == .finished)
        #expect(verdict(Self.tool, Self.canceled) == .finished)
        #expect(verdict(Self.tool, 0) == .finished)
    }

    @Test("A conversation in flight turns the ring, and its last response stops it")
    func conversationLifecycle() throws {
        let home = try EditorTestSupport.temporary("antigravity-activity")
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appending(path: ".gemini/antigravity/conversations/one.db")
        var cache = AgentActivity.Cache()
        func state(_ elapsed: TimeInterval = 0) -> AgentActivity.State? {
            AgentActivity.states(for: [.antigravity], now: Self.now.addingTimeInterval(elapsed),
                                 home: home, cache: &cache)[.antigravity]
        }

        try Self.write(database, steps: [(Self.userInput, Self.done), (Self.response, Self.generating)])
        #expect(state()?.isWorking == true)
        #expect(state()?.lastWrite == Self.now)
        // A model step left generating by a session that died stops after the
        // model's grace, timed from the database's last write.
        #expect(state(89)?.isWorking == true)
        #expect(state(91)?.isWorking == false)

        // Each rewrite below keeps the same stamp and page count, which a real
        // write never does; a fresh cache stands in for the changed stamp.
        cache = AgentActivity.Cache()
        try Self.write(database, steps: [(Self.userInput, Self.done), (Self.response, Self.done),
                                         (Self.tool, Self.running)])
        #expect(state()?.isWorking == true)
        #expect(state(4 * 60)?.isWorking == true, "A running tool keeps the tool's longer grace")

        cache = AgentActivity.Cache()
        try Self.write(database, steps: [(Self.userInput, Self.done), (Self.response, Self.done),
                                         (Self.tool, Self.done), (Self.response, Self.done)])
        #expect(state()?.isWorking == false)
    }

    @Test("Older agy's folder counts, the journal's write counts, and unreadable files do not")
    func rootsAndFiles() throws {
        let home = try EditorTestSupport.temporary("antigravity-roots")
        defer { try? FileManager.default.removeItem(at: home) }
        func working() -> Bool? {
            AgentActivity.states(for: [.antigravity], now: Self.now, home: home)[.antigravity]?.isWorking
        }

        // Not a database, and a database with no steps table: neither is work,
        // however freshly written.
        let notes = home.appending(path: ".gemini/antigravity/conversations/notes.txt")
        try FileManager.default.createDirectory(at: notes.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("generating".utf8).write(to: notes)
        try Self.sqlite(at: home.appending(path: ".gemini/antigravity/conversations/other.db"),
                        ["CREATE TABLE unrelated (x INTEGER)"])
        try Self.touch(home.appending(path: ".gemini/antigravity/conversations/other.db"), at: Self.now)
        #expect(working() == false)

        // An old database whose journal was just written is a live one.
        let cli = home.appending(path: ".gemini/antigravity-cli/conversations/two.db")
        try Self.write(cli, steps: [(Self.response, Self.generating)], at: Self.now.addingTimeInterval(-3_600))
        let journal = URL(fileURLWithPath: cli.path + "-wal")
        try Data([0]).write(to: journal)
        try Self.touch(journal, at: Self.now)
        #expect(working() == true)
    }

    // MARK: - Building databases

    private static func write(_ url: URL, steps: [(type: Int, status: Int)], at date: Date = now) throws {
        try? FileManager.default.removeItem(at: url)
        try sqlite(at: url, ["CREATE TABLE steps (idx INTEGER PRIMARY KEY, step_type INTEGER NOT NULL, status INTEGER NOT NULL)"]
            + steps.enumerated().map { "INSERT INTO steps VALUES (\($0.offset), \($0.element.type), \($0.element.status))" })
        try touch(url, at: date)
    }

    private static func touch(_ url: URL, at date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private static func sqlite(at url: URL, _ statements: [String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        for statement in statements {
            #expect(sqlite3_exec(handle, statement, nil, nil, nil) == SQLITE_OK, "statement failed: \(statement)")
        }
    }
}
