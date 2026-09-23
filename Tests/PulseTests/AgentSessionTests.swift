import Foundation
import SQLite3
import Testing
@testable import Pulse

/// The chain that #6 depends on: a production reader must actually fill a
/// session's own priced buckets, and `SpendSummary` must then count only the
/// part of that session inside the span.
///
/// Every store here is built by hand under a unique temporary root — nobody's
/// real transcripts are read, and `URL.temporaryDirectory` itself is never
/// removed.
@Suite("Agent session buckets")
struct AgentSessionTests {
    private static let prices: [String: ModelPrice] = [
        "priced": ModelPrice(input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "Priced")
    ]

    private static let now = Date()
    private static var today: Date { Calendar.current.startOfDay(for: now) }

    private static func at(daysAgo: Int, hour: Int = 12) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today)!
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private static func temporary(_ name: String) -> URL {
        URL.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
    }

    /// What the session's buckets add up to, which must be the session's own
    /// totals — otherwise a span would be summing a different number than the
    /// one the row shows.
    private static func slotSums(_ session: UsageLedger.Session) -> (tokens: Int, cost: Double) {
        session.slots.reduce(into: (tokens: 0, cost: 0.0)) { running, slot in
            running.tokens += slot.tokens
            running.cost += slot.cost
        }
    }

    private static func expectBucketsMatch(_ session: UsageLedger.Session) {
        #expect(session.slots.count == 2)
        #expect(session.slots.reduce(0) { $0 + $1.unpricedTokens } == session.unpricedTokens)
        let sums = Self.slotSums(session)
        #expect(sums.tokens == session.tokens)
        #expect(abs(sums.cost - session.cost) < 1e-9)
    }

    // MARK: - OpenCode / Kilo

    @Test("OpenCode's reader fills a session's buckets and Today counts only today")
    func openCodeSessionSlotsReachToday() throws {
        let directory = Self.temporary("opencode-session")
        let file = directory.appending(path: "opencode.db")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var handle: OpaquePointer?
        #expect(sqlite3_open(file.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }

        let todayMs = Int(Self.at(daysAgo: 0).timeIntervalSince1970 * 1000)
        let yesterdayMs = Int(Self.at(daysAgo: 1).timeIntervalSince1970 * 1000)
        let today = #"{"role":"assistant","modelID":"priced","time":{"created":\#(todayMs)},"tokens":{"input":100,"output":0}}"#
        let yesterday = #"{"role":"assistant","modelID":"priced","time":{"created":\#(yesterdayMs)},"tokens":{"input":900,"output":0}}"#

        for sql in [
            "CREATE TABLE session (id TEXT, project_id TEXT, slug TEXT, directory TEXT, title TEXT)",
            "CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, data TEXT)",
            "INSERT INTO session VALUES ('s1','p','slug','/Users/me/Code/Pulse','Fix the ring')",
            "INSERT INTO message VALUES ('m1','s1',1,'\(today)')",
            "INSERT INTO message VALUES ('m2','s1',2,'\(yesterday)')",
        ] {
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }

        let unpriced = OpenCodeStore.ledger(at: file, prices: [:])
        Self.expectBucketsMatch(try #require(unpriced.sessions.first))
        let unknownToday = SpendSummary.of([.openCode: unpriced], overLast: 1, now: Self.now)
        #expect(unknownToday.sessions.first?.session.unpricedTokens == 100)
        #expect(unknownToday.sessions.first?.session.estimatedCost == nil)
        #expect(unknownToday.projects.first?.unpricedTokens == 100)

        let ledger = OpenCodeStore.ledger(at: file, prices: Self.prices)
        let session = try #require(ledger.sessions.first)
        Self.expectBucketsMatch(session)
        // The day keys and the session buckets are the same work.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == session.tokens)

        let summary = SpendSummary.of([.openCode: ledger], overLast: 1, now: Self.now)
        #expect(summary.tokens == 100)
        #expect(abs(summary.cost - 0.1) < 1e-9)
        #expect(summary.projects.first?.cost == summary.cost)
        #expect(summary.sessions.first?.session.cost == summary.cost)
        #expect(summary.projects.first?.tokens == 100)
        #expect(summary.sessions.first?.session.tokens == 100)
    }

    // MARK: - Grok Build

    @Test("Grok's reader fills a session's buckets and Today counts only today")
    func grokSessionSlotsReachToday() throws {
        let root = Self.temporary("grok-session")
        let run = root.appending(path: "%2FUsers%2Fme%2FCode%2FPulse").appending(path: "01a0")
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let todaySec = Int(Self.at(daysAgo: 0).timeIntervalSince1970)
        let yesterdaySec = Int(Self.at(daysAgo: 1).timeIntervalSince1970)
        let lines = [
            #"{"timestamp":\#(todaySec),"params":{"update":{"sessionUpdate":"turn_completed","usage":{"modelUsage":{"priced":{"inputTokens":100,"outputTokens":0}}}}}}"#,
            #"{"timestamp":\#(yesterdaySec),"params":{"update":{"sessionUpdate":"turn_completed","usage":{"modelUsage":{"priced":{"inputTokens":900,"outputTokens":0}}}}}}"#,
        ]
        try lines.joined(separator: "\n").write(
            to: run.appending(path: "updates.jsonl"), atomically: true, encoding: .utf8
        )

        let unpriced = GrokStore.ledger(at: root, prices: [:])
        Self.expectBucketsMatch(try #require(unpriced.sessions.first))
        let unknownToday = SpendSummary.of([.grok: unpriced], overLast: 1, now: Self.now)
        #expect(unknownToday.sessions.first?.session.unpricedTokens == 100)
        #expect(unknownToday.sessions.first?.session.estimatedCost == nil)
        #expect(unknownToday.projects.first?.unpricedTokens == 100)

        let ledger = GrokStore.ledger(at: root, prices: Self.prices)
        let session = try #require(ledger.sessions.first)
        Self.expectBucketsMatch(session)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == session.tokens)

        let summary = SpendSummary.of([.grok: ledger], overLast: 1, now: Self.now)
        #expect(summary.tokens == 100)
        #expect(abs(summary.cost - 0.1) < 1e-9)
        #expect(summary.projects.first?.cost == summary.cost)
        #expect(summary.sessions.first?.session.cost == summary.cost)
        #expect(summary.projects.first?.tokens == 100)
        #expect(summary.sessions.first?.session.tokens == 100)
    }

    // MARK: - Devin CLI

    @Test("Devin's reader fills a session's buckets and Today counts only today")
    func devinSessionSlotsReachToday() throws {
        let directory = Self.temporary("devin-session")
        let file = directory.appending(path: "sessions.db")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var handle: OpaquePointer?
        #expect(sqlite3_open(file.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }

        let todaySec = Int(Self.at(daysAgo: 0).timeIntervalSince1970)
        let yesterdaySec = Int(Self.at(daysAgo: 1).timeIntervalSince1970)
        let today = #"{"role":"assistant","metadata":{"generation_model":"priced","metrics":{"input_tokens":100,"output_tokens":0}}}"#
        let yesterday = #"{"role":"assistant","metadata":{"generation_model":"priced","metrics":{"input_tokens":900,"output_tokens":0}}}"#

        for sql in [
            "CREATE TABLE sessions (id TEXT, working_directory TEXT, title TEXT)",
            "CREATE TABLE message_nodes (session_id TEXT, chat_message TEXT, created_at INTEGER)",
            "INSERT INTO sessions VALUES ('s1','/Users/me/Code/Pulse','Fix the ring')",
            "INSERT INTO message_nodes VALUES ('s1','\(today)',\(todaySec))",
            "INSERT INTO message_nodes VALUES ('s1','\(yesterday)',\(yesterdaySec))",
        ] {
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }

        let unpriced = DevinCLIStore.ledger(at: file, prices: [:])
        Self.expectBucketsMatch(try #require(unpriced.sessions.first))
        let unknownToday = SpendSummary.of([.devinCLI: unpriced], overLast: 1, now: Self.now)
        #expect(unknownToday.sessions.first?.session.unpricedTokens == 100)
        #expect(unknownToday.sessions.first?.session.estimatedCost == nil)
        #expect(unknownToday.projects.first?.unpricedTokens == 100)

        let ledger = DevinCLIStore.ledger(at: file, prices: Self.prices)
        let session = try #require(ledger.sessions.first)
        Self.expectBucketsMatch(session)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == session.tokens)

        let summary = SpendSummary.of([.devinCLI: ledger], overLast: 1, now: Self.now)
        #expect(summary.tokens == 100)
        #expect(abs(summary.cost - 0.1) < 1e-9)
        #expect(summary.projects.first?.cost == summary.cost)
        #expect(summary.sessions.first?.session.cost == summary.cost)
        #expect(summary.projects.first?.tokens == 100)
        #expect(summary.sessions.first?.session.tokens == 100)
    }

    // MARK: - Kimi CLI

    @Test("Kimi's reader fills a session's buckets; its unnamed model is counted, not costed")
    func kimiSessionSlotsReachToday() throws {
        let root = Self.temporary("kimi-session")
        let sessionDirectory = root.appending(path: "hash/session")
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let todaySec = Int(Self.at(daysAgo: 0).timeIntervalSince1970)
        let yesterdaySec = Int(Self.at(daysAgo: 1).timeIntervalSince1970)
        let lines = [
            #"{"timestamp":\#(todaySec),"message":{"payload":{"token_usage":{"input_other":100,"output":0,"input_cache_read":0,"input_cache_creation":0}}}}"#,
            #"{"timestamp":\#(yesterdaySec),"message":{"payload":{"token_usage":{"input_other":900,"output":0,"input_cache_read":0,"input_cache_creation":0}}}}"#,
        ]
        try lines.joined(separator: "\n").write(
            to: sessionDirectory.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8
        )
        try #"{"custom_title":"Fix the ring"}"#.write(
            to: sessionDirectory.appending(path: "state.json"), atomically: true, encoding: .utf8
        )

        let ledger = KimiCLIStore.ledger(at: root, prices: Self.prices)
        let session = try #require(ledger.sessions.first)
        Self.expectBucketsMatch(session)
        #expect(session.title == "Fix the ring")
        // Kimi names no model, so nothing is priceable and the cost is exactly
        // zero rather than a guessed rate.
        #expect(session.cost == 0)
        #expect(session.unpricedTokens == 1_000)
        #expect(session.estimatedCost == nil)
        #expect(Self.slotSums(session).cost == 0)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == session.tokens)

        let summary = SpendSummary.of([.kimiCLI: ledger], overLast: 1, now: Self.now)
        #expect(summary.tokens == 100)
        // No working directory is stated, so it is in the total and not on the
        // project list.
        #expect(summary.projects.isEmpty)
        #expect(summary.sessions.first?.session.unpricedTokens == 100)
        #expect(summary.sessions.first?.session.estimatedCost == nil)
        #expect(summary.sessions.first?.session.tokens == 100)
    }
}
