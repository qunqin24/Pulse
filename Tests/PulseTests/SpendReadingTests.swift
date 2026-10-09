import Foundation
import Testing
@testable import Pulse

@Suite("Spend reading and cancellation")
struct SpendReadingTests {
    private func temporary() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulseSpendReading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func buddyRow(input: Int = 100) -> String {
        """
        {"id":"m1","type":"message","role":"assistant","timestamp":1780000000000,"sessionId":"s1","message":{"model":"gpt-5","usage":{"input_tokens":\(input),"output_tokens":20}}}
        """
    }

    @Test("New installs and upgrades leave the pane off until its choice is saved")
    func preference() {
        let (defaults, cleanup) = TestDefaults.make("readsTokenSpend")
        defer { cleanup() }
        #expect(!AppSettings.storedReadsTokenSpend(in: defaults))
        #expect(!AppSettings().readsTokenSpend)
        defaults.set(true, forKey: ProviderSelection.hasRunKey)
        AppSettings.storeSpendSpan(.today, in: defaults)
        #expect(!AppSettings.storedReadsTokenSpend(in: defaults))
        for enabled in [true, false, true] {
            AppSettings.storeReadsTokenSpend(enabled, in: defaults)
            let restored = AppSettings(readsTokenSpend: AppSettings.storedReadsTokenSpend(in: defaults))
            #expect(restored.readsTokenSpend == enabled)
            #expect(AppSettings.storedSpendSpan(in: defaults) == .today)
        }
    }

    @Test("Lines cross chunk boundaries without losing UTF-8, CRLF or a final unterminated line")
    func chunkBoundaries() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "lines.jsonl")
        let large = String(repeating: "数🙂", count: 20_000)
        let text = "\n{\"title\":\"\(large)\"}\r\n\n{\"last\":true}"
        try write(text, to: file)
        let lines = LogLines(at: file, chunkSize: 7)
        let decoded = lines.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(decoded.count == 2)
        #expect(decoded.first?["title"] as? String == large)
        #expect(decoded.last?["last"] as? Bool == true)
        // A sequence is replayable; its iterator, not the sequence, owns a file.
        #expect(Array(lines).count == 2)
    }

    @Test("A file digest includes every byte, including EOF and empty files")
    func streamingDigest() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "fragment.jsonl")
        for text in ["", String(repeating: "\nbytes\r\n数", count: 10_000)] {
            try write(text, to: file)
            #expect(AgentLogIO.digest(at: file) == EditorLog.digest(Data(text.utf8)))
        }
    }

    @Test("Cancelling during a JSONL loop stops on the next line")
    func cancelsLines() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "lines.jsonl")
        try write(String(repeating: "{\"count\":1}\n", count: 10_000), to: file)
        let read = Task.detached {
            var count = 0
            for _ in AgentLogIO.jsonLines(at: file) {
                count += 1
                if count == 3 { withUnsafeCurrentTask { $0?.cancel() } }
            }
            return count
        }
        #expect(await read.value == 3)
        // Cancellation belongs to the reader task, not to the file or a global
        // flag; another page's read can still use the same source.
        #expect(Array(AgentLogIO.jsonLines(at: file)).count == 10_000)
    }

    @Test("Cancelling during a SQLite result stops stepping its remaining rows")
    func cancelsSQLite() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "rows.db")
        try EditorTestSupport.makeDatabase(at: file, statements: ["CREATE TABLE marker (id INTEGER)"])
        let read = Task.detached {
            AgentSQLite.read(at: file) { db in
                var count = 0
                AgentSQLite.each(db, sql: "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<100000) SELECT x FROM n") { _ in
                    count += 1
                    if count == 4 { withUnsafeCurrentTask { $0?.cancel() } }
                }
                return count
            }
        }
        #expect(await read.value == 4)
    }

    @Test("A cancelled scan publishes no result and creates no agent cache")
    func cancelsScan() async throws {
        let home = try temporary()
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try write(buddyRow(), to: home.appending(path: ".workbuddy/projects/s.jsonl"))
        let reader = AgentLedgers(home: home, environment: [:], cacheDirectory: cache, prices: { [:] })
        let read = Task.detached {
            try await reader.scan { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)

        let next = try await reader.scan()
        #expect(next.ledgers[.workBuddy]?.allTime.tokens == 120)
        #expect(AgentCache.load(.workBuddy, at: AgentCache.file(for: .workBuddy, directory: cache)) != nil)
    }

    @Test("Cancellation before scanning does not even load prices")
    func cancelledBeforeStart() async throws {
        let home = try temporary()
        defer { try? FileManager.default.removeItem(at: home) }
        let reader = AgentLedgers(home: home, environment: [:], prices: {
            Issue.record("A cancelled scan requested prices")
            return [:]
        })
        let read = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.scan()
        }
        await #expect(throws: CancellationError.self) { try await read.value }
    }

    @Test("A cancelled writer cannot replace a complete cache with partial totals")
    func cancelledCacheWrite() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "cache.json")
        try write("previous complete cache", to: file)
        let write = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            AgentCache.save(.empty, stamp: .init(source: "s", prices: "p"), for: .workBuddy, at: file)
        }
        await write.value
        #expect(try String(contentsOf: file, encoding: .utf8) == "previous complete cache")
    }

    @Test("WorkBuddy binaries affect neither records nor cache validity; new logs still do")
    func skipsBinaries() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(buddyRow(), to: root.appending(path: "projects/s.jsonl"))
        let before = AgentCache.stamp(for: [root], prices: [:], excludingRootDirectories: ["binaries"])
        try write(buddyRow(input: 9_000), to: root.appending(path: "binaries/runtime/noise.jsonl"))
        let after = AgentCache.stamp(for: [root], prices: [:], excludingRootDirectories: ["binaries"])
        #expect(before == after)
        #expect(TencentBuddyReader.records(client: "workbuddy", roots: [root]).reduce(0) { $0 + $1.tally.total } == 120)
        try write(buddyRow(input: 200), to: root.appending(path: "projects/new.jsonl"))
        #expect(before != AgentCache.stamp(for: [root], prices: [:], excludingRootDirectories: ["binaries"]))
    }

    @Test("Re-entering uses a valid disk cache, while Rescan and changed inputs re-read")
    func cacheRevalidation() async throws {
        let home = try temporary()
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let source = home.appending(path: ".workbuddy/projects/s.jsonl")
        try write(buddyRow(), to: source)
        let reader = AgentLedgers(home: home, environment: [:], cacheDirectory: cache, prices: { [:] })
        let first = try await reader.scan()
        #expect(first.ledgers[.workBuddy]?.allTime.tokens == 120)
        let file = AgentCache.file(for: .workBuddy, directory: cache)
        let saved = try #require(AgentCache.load(.workBuddy, at: file))
        // A distinctive valid cached ledger proves the second visit used the
        // cache rather than decoding the source again. The kept history
        // (`AgentArchive`) would add the first read back over it, so it goes.
        AgentCache.save(.empty, stamp: saved.stamp, for: .workBuddy, at: file)
        try FileManager.default.removeItem(at: AgentArchive.file(for: .workBuddy, directory: cache))
        #expect(try await reader.scan().ledgers[.workBuddy]?.allTime.tokens == 0)
        #expect(try await reader.scan(refresh: true).ledgers[.workBuddy]?.allTime.tokens == 120)
        try write(buddyRow(input: 1_000), to: source)
        #expect(try await reader.scan().ledgers[.workBuddy]?.allTime.tokens == 1_020)
    }

    @Test("The streamed Codex parser keeps cumulative deltas and remains independent of the pane switch")
    func codexHistory() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: ".codex/sessions/session.jsonl")
        let count = #"{"timestamp":"2026-01-02T09:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}"#
        try write(
            #"{"payload":{"cwd":"/work/project","model":"gpt-5"}}"# + "\n" + count + "\n" + count,
            to: file
        )
        #expect(!AppSettings().readsTokenSpend)
        let scanned = await UsageLedgerReader().parse(file, provider: .codex)
        #expect(scanned.cwd == "/work/project")
        #expect(scanned.allDays.values.flatMap { $0.values }.reduce(TokenTally(), +)
            == TokenTally(input: 80, cacheRead: 20, output: 10))
        let cache = root.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let reader = AgentLedgers(home: root, environment: [:], cacheDirectory: cache, prices: { [:] })
        #expect(try await reader.scan().ledgers[.codex]?.allTime.tokens == 110)
        #expect(FileManager.default.fileExists(atPath: cache.appending(path: "ledger-9-codex.json").path))
    }

    private func codexCount(_ time: String, input: Int, output: Int, last: (input: Int, output: Int)) -> String {
        #"{"timestamp":"2026-01-02T\#(time)Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":\#(output),"total_tokens":\#(input + output)},"last_token_usage":{"input_tokens":\#(last.input),"cached_input_tokens":0,"output_tokens":\#(last.output),"total_tokens":\#(last.input + last.output)}}}}"#
    }

    private func codexTurn(_ id: String) -> String {
        #"{"timestamp":"2026-01-02T09:10:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"\#(id)"}}"#
    }

    private let codexModel = #"{"timestamp":"2026-01-02T09:00:00Z","type":"turn_context","payload":{"model":"gpt-5"}}"#

    /// A Codex Desktop sub-agent's rollout: it opens on the parent's running
    /// total, replays the parent's last reading in a `rollout-N` turn, then
    /// does 550 tokens of its own work.
    private func codexFork(replayTurn: String) -> String {
        [
            #"{"timestamp":"2026-01-02T09:10:00Z","type":"session_meta","payload":{"id":"child","forked_from_id":"parent"}}"#,
            codexModel,
            codexCount("09:10:00", input: 1_000, output: 100, last: (0, 0)),
            codexTurn(replayTurn),
            codexCount("09:10:00", input: 2_000, output: 200, last: (1_000, 100)),
            codexTurn("019f8f37-eb69-7e62-8fa8-e3d19fec5ade"),
            codexCount("09:10:00", input: 2_500, output: 250, last: (500, 50)),
        ].joined(separator: "\n")
    }

    @Test("A Codex fork counts only its own work, archived or not, with or without its parent on disk")
    func codexForks() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = [
            #"{"timestamp":"2026-01-02T09:00:00Z","type":"session_meta","payload":{"id":"parent"}}"#,
            codexModel,
            codexCount("09:00:00", input: 1_000, output: 100, last: (1_000, 100)),
            codexCount("09:05:00", input: 2_000, output: 200, last: (1_000, 100)),
        ].joined(separator: "\n")
        try write(parent, to: root.appending(path: ".codex/sessions/2026/01/02/rollout-parent.jsonl"))
        // Archived, and its replayed reading in an ordinary turn: the copy is
        // known by the running total it repeats.
        try write(codexFork(replayTurn: "019f8f06-dfd5-7cd2-a871-b31a926f92b7"),
                  to: root.appending(path: ".codex/archived_sessions/rollout-child.jsonl"))

        let cache = root.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let reader = AgentLedgers(home: root, environment: [:], cacheDirectory: cache, prices: { [:] })
        let scannedTokens = try await reader.scan().ledgers[.codex]?.allTime.tokens
        #expect(scannedTokens == 2_200 + 550)

        // The parent gone, the replayed turn is still known by its `rollout-`
        // id, and the opening total is still the parent's.
        let alone = await UsageLedgerReader().parse(
            {
                let file = root.appending(path: "alone.jsonl")
                try? write(codexFork(replayTurn: "rollout-4"), to: file)
                return file
            }(),
            provider: .codex
        )
        #expect(alone.allDays.values.flatMap { $0.values }.reduce(TokenTally(), +).total == 550)
    }
}
