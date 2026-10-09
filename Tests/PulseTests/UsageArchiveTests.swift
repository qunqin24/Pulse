import Foundation
import Testing
@testable import Pulse

/// A tool deleting its old records must not take them out of Token spend or
/// the recaps (`TranscriptArchive`, `AgentArchive`).
@Suite("Kept history after a tool deletes its records")
struct UsageArchiveTests {
    private func temporary() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulseArchive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "cache"), withIntermediateDirectories: true)
        return root
    }

    private func write(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    private let prices = [
        "claude-test": ModelPrice(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75, name: "Claude Test"),
        "gpt-5": ModelPrice(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: nil, name: "GPT-5"),
    ]

    private func user(_ time: String, _ text: String) -> String {
        #"{"type":"user","timestamp":"\#(time)","cwd":"/work/pulse","message":{"role":"user","content":"\#(text)"}}"#
    }

    private func reply(_ id: String, _ time: String, input: Int = 100, output: Int = 300) -> String {
        #"{"type":"assistant","timestamp":"\#(time)","message":{"id":"\#(id)","model":"claude-test","usage":{"input_tokens":\#(input),"cache_read_input_tokens":2000,"cache_creation_input_tokens":500,"cache_creation":{"ephemeral_1h_input_tokens":200},"output_tokens":\#(output)}}}"#
    }

    @Test("A deleted Claude Code transcript keeps its days, money, hours and row, and its resumed copy is not counted again")
    func claudeCodeTranscriptDeleted() async throws {
        let home = try temporary()
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appending(path: "cache")
        let project = home.appending(path: ".claude/projects/-work-pulse")
        let original = project.appending(path: "a.jsonl")
        let resumed = project.appending(path: "b.jsonl")
        let opening = [
            user("2026-09-01T10:00:00Z", "Fix the build"),
            reply("m1", "2026-09-01T10:00:40Z"),
            user("2026-09-01T10:20:00Z", "And the tests"),
            reply("m2", "2026-09-01T10:21:00Z", input: 50, output: 150),
        ]
        try write(opening, to: original)
        // Resuming opens a new transcript with a copy of the old history —
        // the same ids at the same times — and goes on the next day.
        try write(opening + [user("2026-09-02T09:00:00Z", "Ship it"), reply("m3", "2026-09-02T09:00:30Z")], to: resumed)

        let reader = UsageLedgerReader(home: home, cacheDirectory: cache)
        let before = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        let replies = (100 + 2000 + 500 + 300) * 2 + (50 + 2000 + 500 + 150)
        #expect(before.allTime.tokens == replies)
        #expect(before.allTime.cost > 0)
        #expect(before.sessions.count == 2)
        #expect(before.slots.contains { !$0.timings.isEmpty })

        try FileManager.default.removeItem(at: original)
        let after = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        // Days, money, quarter-hours with their timings, and both rows.
        #expect(after == before)
        // The walker spells the temporary folder `/private/var`.
        #expect(after.sessions.first { $0.id.hasSuffix("/-work-pulse/a.jsonl") }?.title == "Fix the build")

        // Read again from disk by a new reader, and with the copy gone too.
        let reopened = await UsageLedgerReader(home: home, cacheDirectory: cache)
            .ledger(for: .claudeCode, prices: prices)
        #expect(reopened == before)
        try FileManager.default.removeItem(at: resumed)
        let bothGone = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        #expect(bothGone.days == before.days)
        #expect(bothGone.slots == before.slots)
        #expect(bothGone.sessions.count == 2)

        // The copy back — from a backup, or a folder that was away for a
        // scan: the kept original still claims its replies.
        try write(opening + [user("2026-09-02T09:00:00Z", "Ship it"), reply("m3", "2026-09-02T09:00:30Z")], to: resumed)
        let copyBack = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        #expect(copyBack.days == before.days)

        // A transcript put back where it was is read from the file, not kept
        // as well.
        try write(opening, to: original)
        let restored = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        #expect(restored.days == before.days)
    }

    @Test("Transcripts under a linked ~/.claude are kept when deleted")
    func linkedRoot() async throws {
        let home = try temporary()
        defer { try? FileManager.default.removeItem(at: home) }
        let elsewhere = home.appending(path: "elsewhere/.claude")
        let file = elsewhere.appending(path: "projects/p/s.jsonl")
        try write([user("2026-09-01T10:00:00Z", "Hi"), reply("l1", "2026-09-01T10:00:40Z")], to: file)
        try FileManager.default.createSymbolicLink(at: home.appending(path: ".claude"), withDestinationURL: elsewhere)
        let reader = UsageLedgerReader(home: home, cacheDirectory: home.appending(path: "cache"))
        let before = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        #expect(before.allTime.tokens == 2_900)
        try FileManager.default.removeItem(at: file)
        let after = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        #expect(after.days == before.days)
    }

    private func codexCount(_ time: String, input: Int, output: Int, last: (input: Int, output: Int)) -> String {
        #"{"timestamp":"2026-01-02T\#(time)Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":\#(output),"total_tokens":\#(input + output)},"last_token_usage":{"input_tokens":\#(last.input),"cached_input_tokens":0,"output_tokens":\#(last.output),"total_tokens":\#(last.input + last.output)}}}}"#
    }

    private let codexModel = #"{"timestamp":"2026-01-02T09:00:00Z","type":"turn_context","payload":{"model":"gpt-5"}}"#

    @Test("A deleted Codex parent still holds back its fork's replay, and a moved rollout is not counted twice")
    func codexParentDeletedAndRolloutMoved() async throws {
        let home = try temporary()
        defer { try? FileManager.default.removeItem(at: home) }
        let parent = home.appending(path: ".codex/sessions/2026/01/02/rollout-parent.jsonl")
        try write([
            #"{"timestamp":"2026-01-02T09:00:00Z","type":"session_meta","payload":{"id":"parent"}}"#,
            codexModel,
            codexCount("09:00:00", input: 1_000, output: 100, last: (1_000, 100)),
            codexCount("09:05:00", input: 2_000, output: 200, last: (1_000, 100)),
        ], to: parent)
        // An older fork: it replays the parent's reading in an ordinary turn,
        // known only by the running total it repeats.
        let fork = home.appending(path: ".codex/sessions/2026/01/02/rollout-child.jsonl")
        try write([
            #"{"timestamp":"2026-01-02T09:10:00Z","type":"session_meta","payload":{"id":"child","forked_from_id":"parent"}}"#,
            codexModel,
            codexCount("09:10:00", input: 1_000, output: 100, last: (0, 0)),
            #"{"timestamp":"2026-01-02T09:10:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"019f8f06-dfd5-7cd2-a871-b31a926f92b7"}}"#,
            codexCount("09:10:00", input: 2_000, output: 200, last: (1_000, 100)),
            codexCount("09:10:00", input: 2_500, output: 250, last: (500, 50)),
        ], to: fork)

        let reader = UsageLedgerReader(home: home, cacheDirectory: home.appending(path: "cache"))
        let before = await reader.ledger(for: .codex, refresh: true, prices: prices)
        #expect(before.allTime.tokens == 2_200 + 550)

        try FileManager.default.removeItem(at: parent)
        let deleted = await reader.ledger(for: .codex, refresh: true, prices: prices)
        #expect(deleted.days == before.days)
        #expect(deleted.allTime.tokens == 2_200 + 550)

        // Codex moves a session it archives; the same rollout under another
        // folder is the same work.
        let moved = home.appending(path: ".codex/archived_sessions/rollout-child.jsonl")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: fork, to: moved)
        let afterMove = await reader.ledger(for: .codex, refresh: true, prices: prices)
        #expect(afterMove.days == before.days)
        #expect(afterMove.allTime.tokens == 2_200 + 550)
    }

    @Test("A transcript cache written for another home is not kept into this one's archive")
    func foreignEntriesAreNotKept() async throws {
        let home = try temporary()
        let other = try temporary()
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: other)
        }
        let cache = home.appending(path: "cache")
        try write([user("2026-09-01T10:00:00Z", "Hi"), reply("x1", "2026-09-01T10:00:40Z")],
                  to: other.appending(path: ".claude/projects/p/s.jsonl"))
        _ = await UsageLedgerReader(home: other, cacheDirectory: cache).ledger(for: .claudeCode, prices: prices)
        let mine = await UsageLedgerReader(home: home, cacheDirectory: cache).ledger(for: .claudeCode, prices: prices)
        #expect(mine.allTime.tokens == 0)
        #expect(TranscriptArchive.load(for: .claudeCode, directory: cache)?.files.isEmpty == true)
    }

    private func buddy(_ id: String, session: String, at milliseconds: Int, input: Int = 1_000) -> String {
        #"{"id":"\#(id)","type":"message","role":"assistant","timestamp":\#(milliseconds),"sessionId":"\#(session)","message":{"model":"gpt-5","usage":{"input_tokens":\#(input),"output_tokens":200}}}"#
    }

    @Test("A store that deletes a session file keeps the day, money, hours and row; a copy elsewhere is counted once")
    func agentStoreFileDeleted() async throws {
        let home = try temporary()
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appending(path: "cache")
        let store = home.appending(path: ".workbuddy/projects")
        let day = 1_780_000_000_000
        // `s1` is written twice — a copy of its file in another folder of
        // the store — and the reader folds the copy by message id.
        try write([buddy("m1", session: "s1", at: day)], to: store.appending(path: "a/s1.jsonl"))
        try write([buddy("m1", session: "s1", at: day)], to: store.appending(path: "b/s1.jsonl"))
        try write([buddy("m2", session: "s2", at: day + 86_400_000 * 3, input: 400)], to: store.appending(path: "a/s2.jsonl"))

        let reader = AgentLedgers(home: home, environment: [:], cacheDirectory: cache, prices: { prices })
        let before = try #require(try await reader.scan().ledgers[.workBuddy])
        #expect(before.allTime.tokens == 1_200 + 600)
        #expect(before.allTime.cost > 0)

        // One copy gone: nothing was lost, so nothing is added.
        try FileManager.default.removeItem(at: store.appending(path: "a/s1.jsonl"))
        let copyGone = try #require(try await reader.scan().ledgers[.workBuddy])
        #expect(copyGone.days == before.days)
        #expect(copyGone.allTime.tokens == 1_200 + 600)

        // Both gone: the day is kept, priced, in its quarter-hour, with its row.
        try FileManager.default.removeItem(at: store.appending(path: "b/s1.jsonl"))
        let deleted = try #require(try await reader.scan().ledgers[.workBuddy])
        #expect(deleted.days == before.days)
        #expect(deleted.slots == before.slots)
        #expect(Set(deleted.sessions.map(\.id)) == Set(before.sessions.map(\.id)))
        #expect(deleted.earliest == before.earliest)

        // Read again by a new reader, from the cache and the archive alone.
        let reopened = AgentLedgers(home: home, environment: [:], cacheDirectory: cache, prices: { prices })
        let again = try #require(try await reopened.scan().ledgers[.workBuddy])
        #expect(again.days == before.days)
    }

    /// One session's work as a ledger, built by the shared builder.
    private func ledger(_ records: [AgentUsageRecord]) -> UsageLedger {
        AgentUsageLedger.build(records, prices: prices, namespace: "test")
    }

    private func record(_ session: String, _ id: String, at date: Date, input: Int = 1_000) -> AgentUsageRecord {
        AgentUsageRecord(
            timestamp: date, model: "gpt-5", tally: TokenTally(input: input, output: 100),
            sessionID: session, deduplicationID: id
        )
    }

    @Test("Marks: a deleted session is kept once, a re-filed one is not, and a partial read lowers nothing")
    func marks() {
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        let first = ledger([record("s1", "m1", at: day), record("s2", "m2", at: day.addingTimeInterval(3600))])
        var archive = AgentArchive()
        let raised = archive.absorb(first)
        #expect(raised)

        // `s1`'s message now filed under `s2`: the day is whole, and `s1`'s
        // old row would count it twice.
        let refiled = ledger([record("s2", "m1", at: day), record("s2", "m2", at: day.addingTimeInterval(3600))])
        _ = archive.absorb(refiled, previous: first)
        let shown = archive.merged(into: refiled, prices: prices)
        #expect(shown.days == refiled.days)
        #expect(shown.sessions.map(\.id) == ["test#s2"])

        // `s1` gone with its work: kept, and shown.
        var gone = AgentArchive()
        _ = gone.absorb(first)
        let without = ledger([record("s2", "m2", at: day.addingTimeInterval(3600))])
        _ = gone.absorb(without, previous: first)
        let kept = gone.merged(into: without, prices: prices)
        #expect(kept.days == first.days)
        #expect(kept.slots == first.slots)
        #expect(Set(kept.sessions.map(\.id)) == ["test#s1", "test#s2"])

        // Marks taken under other readers stand only where the current ones
        // see nothing: the later day is the new readers', the first is kept.
        var old = AgentArchive()
        _ = old.absorb(ledger([record("s1", "m1", at: day, input: 9_000), record("s3", "m3", at: day.addingTimeInterval(86_400 * 2))]))
        old.readings = AgentCache.version - 1
        let newer = ledger([record("s3", "m3", at: day.addingTimeInterval(86_400 * 2), input: 10)])
        _ = old.absorb(newer)
        let reread = old.merged(into: newer, prices: prices)
        #expect(reread.allTime.tokens == 9_100 + 110)
    }

    @Test("A change of time zone adds nothing: quarter-hours are kept by instant")
    func timeZoneChange() throws {
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        let live = ledger([record("s1", "m1", at: day), record("s2", "m2", at: day.addingTimeInterval(3600))])
        var archive = AgentArchive()
        _ = archive.absorb(live)
        // As if the marks had been cut half a world away.
        archive.timeZone = archive.timeZone == "Pacific/Kiritimati" ? "Pacific/Pago_Pago" : "Pacific/Kiritimati"
        let shown = archive.merged(into: live, prices: prices)
        #expect(shown.days == live.days)
        #expect(shown.slots == live.slots)
        // And an archive that went through JSON reads back the same.
        let decoded = try JSONDecoder().decode(AgentArchive.self, from: JSONEncoder().encode(archive))
        #expect(decoded == archive)
    }

    @Test("The archives are never taken for superseded caches")
    func archivesAreNotSuperseded() {
        for name in ["archive-ledger-claudeCode.json", "archive-ledger-codex.json", "archive-agent-workBuddy.json"] {
            #expect(!PulseStorage.isSuperseded(name, agentVersion: 99, ledgerVersion: 99))
        }
    }
}
