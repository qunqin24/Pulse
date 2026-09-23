import Foundation
import Testing
@testable import Pulse

@Suite("Project identity")
struct ProjectIdentityTests {
    private static let date = ISO8601DateFormatter().date(from: "2026-09-20T10:00:00Z")!

    @Test("Same-name directories stay separate after transcript and agent cache reloads",
          arguments: [Provider.claudeCode, .codex])
    func transcriptCacheChain(provider: Provider) async throws {
        let root = URL.temporaryDirectory.appending(path: "PulseProjects-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appending(path: provider == .claudeCode ? ".claude/projects/fixture" : ".codex/sessions")
        let agent: SpendAgent = provider == .claudeCode ? .claudeCode : .codex
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (index, cwd) in ["/work/client-a/api", "/work/client-b/api", "/work/client-a/api/"].enumerated() {
            let row: [String: Any] = [
                "type": "assistant", "timestamp": "2026-09-20T10:00:00Z", "cwd": cwd,
                "message": ["id": "m\(index)", "model": "unknown",
                            "usage": ["input_tokens": 100, "output_tokens": 10]],
            ]
            let rows: [[String: Any]] = provider == .claudeCode ? [row] : [
                ["payload": ["cwd": cwd, "model": "unknown"]],
                ["timestamp": "2026-09-20T10:00:00Z", "payload": ["type": "token_count",
                    "info": ["total_token_usage": ["input_tokens": 100, "output_tokens": 10]]]],
            ]
            let lines = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            let file = logs.appending(path: "s\(index).jsonl")
            try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Self.date], ofItemAtPath: file.path)
        }
        let cache = root.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for pass in 0..<2 {
            // New reader each time: the second pass restores the per-file cache.
            let ledger = await UsageLedgerReader(home: root, cacheDirectory: cache).ledger(for: provider, prices: [:])
            let file = root.appending(path: "agent.json")
            AgentCache.save(ledger, stamp: .init(source: "fixture", prices: "empty"), for: agent, at: file)
            let restored = try #require(AgentCache.load(agent, at: file)?.ledger)
            let summary = SpendSummary.of([agent: restored], overLast: nil, now: Self.date)
            #expect(summary.projects.count == 2)
            let counts = Dictionary(uniqueKeysWithValues: summary.projects.map { ($0.name, $0.tokens) })
            #expect(counts == ["client-a/api": 220, "client-b/api": 110])
            #expect(summary.projects.reduce(0) { $0 + $1.sessions } == 3)
            #expect(Set(summary.projects.map(\.id)).count == 2)
            #expect(summary.sessions.allSatisfy { summary.projectName(for: $0)?.contains("/api") == true })

            var saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            saved["version"] = 6
            try JSONSerialization.data(withJSONObject: saved).write(to: file)
            #expect(AgentCache.load(agent, at: file) == nil)
            #expect(FileManager.default.fileExists(atPath: cache.appending(path: "ledger-4-\(provider.rawValue).json").path))
            if pass == 0 {
                // Same size and mtime: only the per-file cache still knows the
                // original directory. This makes its reuse observable.
                let log = logs.appending(path: "s0.jsonl")
                let contents = try String(contentsOf: log, encoding: .utf8)
                try contents.replacingOccurrences(of: "client-a", with: "client-z").write(to: log, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.modificationDate: Self.date], ofItemAtPath: log.path)
            }
        }
    }

    @Test("Explicit paths merge across agents; labels do not claim a directory")
    func sourceIdentity() {
        func ledger(_ project: String, _ namespace: String) -> UsageLedger {
            AgentUsageLedger.build([
                .init(timestamp: Self.date, model: "unknown", tally: .init(input: 10),
                      sessionID: "s", project: project)
            ], prices: [:], namespace: namespace)
        }
        let merged = SpendSummary.of([
            .claudeCode: ledger("/work/api", "claude"), .codex: ledger("/work/api/", "codex")
        ], overLast: nil, now: Self.date)
        #expect(merged.projects.count == 1)
        #expect(merged.projects.first?.name == "api")
        #expect(merged.projects.first?.tokens == 20)
        let labels = SpendSummary.of([
            .claudeCode: ledger("api", "claude"), .codex: ledger("api", "codex"),
            .openCode: ledger("/work/api", "openCode")
        ], overLast: nil, now: Self.date)
        #expect(labels.projects.count == 3)
        #expect(Set(labels.projects.map(\.name)).count == 3)
    }

    @Test("Claude fallback folders retain identity without guessing a cwd")
    func fallbackFolders() throws {
        let first = try #require(UsageLedgerReader.project(
            of: URL(fileURLWithPath: "/logs/-work-client-a-api/a.jsonl"), provider: .claudeCode))
        let second = try #require(UsageLedgerReader.project(
            of: URL(fileURLWithPath: "/logs/-work-client-b-api/b.jsonl"), provider: .claudeCode))
        #expect(first.name == "api")
        #expect(first.path == nil)
        #expect(first.identity != second.identity)
        #expect(first != UsageProject("/work/client-a/api"))
        #expect(UsageProject(" \n") == nil)
        #expect(UsageProject("/Work/API") != UsageProject("/work/api"))
    }

    @Test("Directory suffixes grow until nested names are distinguishable")
    func labels() throws {
        let a = try #require(UsageProject("/client-a/service/api"))
        let b = try #require(UsageProject("/client-b/service/api"))
        #expect(UsageProject.displayName(for: a, among: [a, b]) == "client-a/service/api")
        #expect(UsageProject.displayName(for: b, among: [a, b]) == "client-b/service/api")
        #expect(UsageProject.displayName(for: a, among: [a]) == "api")
    }
}
