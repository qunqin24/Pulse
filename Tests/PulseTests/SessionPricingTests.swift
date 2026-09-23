import Foundation
import Testing
@testable import Pulse

@Suite("Session pricing coverage")
struct SessionPricingTests {
    private static let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00Z")!
    private static let prices = ["paid": ModelPrice(input: 1_000, output: 1_000, cacheRead: nil, cacheWrite: nil, name: nil),
                                 "free": ModelPrice(input: 0, output: 0, cacheRead: nil, cacheWrite: nil, name: nil)]

    @Test("Unknown, mixed and published zero prices survive caching and calendar windows", arguments: [false, true])
    func normalizedChain(aggregate: Bool) throws {
        let yesterday = Self.now.addingTimeInterval(-86_400)
        func record(_ model: String, _ count: Int, _ session: String, at date: Date,
                    extra: Int = 0) -> AgentUsageRecord {
            .init(timestamp: date, model: model, tally: .init(input: count),
                  sessionID: session, project: session, unclassifiedTokens: extra, isAggregate: aggregate)
        }
        let ledger = AgentUsageLedger.build([
            record("unknown", 90, "resumed", at: yesterday),
            record("paid", 10, "resumed", at: Self.now),
            record("unknown", 30, "unknown", at: Self.now),
            record("free", 20, "free", at: Self.now),
            record("paid", 40, "mixed", at: Self.now, extra: 5),
            record("unknown", 15, "mixed", at: Self.now),
            record("paid", 0, "unclassified", at: Self.now, extra: 7),
        ], prices: Self.prices, namespace: "fixture")
        let file = URL.temporaryDirectory.appending(path: "PulsePricing-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        AgentCache.save(ledger, stamp: .init(source: "fixture", prices: "fixture"), for: .cursor, at: file)
        let restored = try #require(AgentCache.load(.cursor, at: file)?.ledger)
        #expect(restored == ledger)
        for input in [ledger, restored] {
            let all = SpendSummary.of([.cursor: input], overLast: nil, now: Self.now)
            let today = SpendSummary.of([.cursor: input], overLast: 1, now: Self.now)
            let rows = Dictionary(uniqueKeysWithValues: today.sessions.map { ($0.session.name, $0.session) })
            #expect(all.sessions.first { $0.session.name == "resumed" }?.session.unpricedTokens == 90)
            #expect(rows["resumed"]?.tokens == 10)
            #expect(rows["resumed"]?.unpricedTokens == 0)
            #expect(rows["resumed"]?.estimatedCost == 0.01)
            #expect(rows["unknown"]?.unpricedTokens == 30)
            #expect(rows["unknown"]?.estimatedCost == nil)
            #expect(rows["free"]?.unpricedTokens == 0)
            #expect(rows["free"]?.estimatedCost == 0)
            #expect(rows["mixed"]?.unpricedTokens == 20)
            #expect(rows["mixed"]?.estimatedCost == 0.04)
            #expect(rows["unclassified"]?.unpricedTokens == 7)
            #expect(rows["unclassified"]?.estimatedCost == nil)
            #expect(today.unpricedTokens == 57)
            #expect(today.projects.reduce(0) { $0 + $1.unpricedTokens } == today.unpricedTokens)
            for project in today.projects {
                #expect(project.unpricedTokens == rows[project.name]?.unpricedTokens)
                #expect(project.estimatedCost == rows[project.name]?.estimatedCost)
            }
        }
    }

    @Test("Claude and Codex sessions retain unpriced buckets", arguments: [Provider.claudeCode, .codex])
    func transcripts(provider: Provider) async throws {
        let root = URL.temporaryDirectory.appending(path: "PulseTranscriptPricing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: provider == .claudeCode ? ".claude/projects/fixture" : ".codex/sessions")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lines: [String]
        if provider == .claudeCode {
            lines = [
                #"{"type":"assistant","timestamp":"2026-09-19T10:00:00Z","cwd":"/work/api","message":{"id":"m1","model":"unknown","usage":{"input_tokens":90}}}"#,
                #"{"type":"assistant","timestamp":"2026-09-20T10:00:00Z","cwd":"/work/api","message":{"id":"m2","model":"paid","usage":{"input_tokens":10}}}"#,
            ]
        } else {
            lines = [
                #"{"payload":{"cwd":"/work/api","model":"unknown"}}"#,
                #"{"timestamp":"2026-09-19T10:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":90,"output_tokens":0}}}}"#,
                #"{"payload":{"model":"paid"}}"#,
                #"{"timestamp":"2026-09-20T10:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":0}}}}"#,
            ]
        }
        try lines.joined(separator: "\n").write(to: folder.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)
        let ledger = await UsageLedgerReader(home: root, cacheDirectory: root.appending(path: "cache"))
            .ledger(for: provider, prices: Self.prices)
        let session = try #require(ledger.sessions.first)
        #expect(session.tokens == 100)
        #expect(session.unpricedTokens == 90)
        #expect(session.slots.reduce(0) { $0 + $1.unpricedTokens } == 90)
        let agent: SpendAgent = provider == .claudeCode ? .claudeCode : .codex
        let today = SpendSummary.of([agent: ledger], overLast: 1, now: Self.now)
        #expect(today.sessions.first?.session.unpricedTokens == 0)
        #expect(today.sessions.first?.session.estimatedCost == 0.01)
        #expect(today.projects.first?.unpricedTokens == 0)
    }

    @Test("A cache missing session pricing coverage must be rebuilt")
    func missingMetadataIsRejected() throws {
        let ledger = AgentUsageLedger.build([
            .init(timestamp: Self.now, model: "unknown", tally: .init(input: 10), sessionID: "s")
        ], prices: [:], namespace: "fixture")
        let file = URL.temporaryDirectory.appending(path: "PulsePricingCache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        AgentCache.save(ledger, stamp: .init(source: "fixture", prices: "empty"), for: .cursor, at: file)
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        for key in ["session", "slots", "days"] {
            var changed = saved
            var stored = try #require(changed["ledger"] as? [String: Any])
            var sessions = try #require(stored["sessions"] as? [[String: Any]])
            if key == "session" {
                sessions[0].removeValue(forKey: "unpricedTokens")
            } else {
                var buckets = try #require(sessions[0][key] as? [[String: Any]])
                buckets[0].removeValue(forKey: "unpricedTokens")
                sessions[0][key] = buckets
            }
            stored["sessions"] = sessions
            changed["ledger"] = stored
            try JSONSerialization.data(withJSONObject: changed).write(to: file)
            #expect(AgentCache.load(.cursor, at: file) == nil)
        }
    }
}
