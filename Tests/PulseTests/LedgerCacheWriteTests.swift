import Foundation
import Testing
@testable import Pulse

@Suite("Transcript cache writes")
struct LedgerCacheWriteTests {
    @Test("Unchanged rescans reprice without rewriting; edits and deletions persist")
    func changedFilesOnly() async throws {
        let home = URL.temporaryDirectory.appending(path: "PulseCacheWrites-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let logs = home.appending(path: ".claude/projects/fixture")
        let cache = home.appending(path: "cache")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let log = logs.appending(path: "s.jsonl")
        let row = #"{"type":"assistant","timestamp":"2026-09-20T10:00:00Z","message":{"id":"one","model":"priced","usage":{"input_tokens":100,"output_tokens":10}}}"#
        try (row + "\n").write(to: log, atomically: true, encoding: .utf8)
        let reader = UsageLedgerReader(home: home, cacheDirectory: cache)
        let first = await reader.ledger(for: .claudeCode, prices: [:])
        #expect(first.allTime.tokens == 110)
        #expect(first.allTime.cost == 0)
        let saved = cache.appending(path: "ledger-9-\(Provider.claudeCode.rawValue).json")
        // An old timestamp makes a write observable without sleeps or timing thresholds.
        let sentinel = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: saved.path)
        let prices = ["priced": ModelPrice(input: 1, output: 2, cacheRead: nil, cacheWrite: nil, name: nil)]
        let repriced = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        #expect(repriced.allTime.tokens == 110)
        #expect(abs(repriced.allTime.cost - 0.00012) < 0.00000001)
        #expect(try FileManager.default.attributesOfItem(atPath: saved.path)[.modificationDate] as? Date == sentinel)

        try (row + "\n" + row.replacingOccurrences(of: "\"one\"", with: "\"two\"") + "\n")
            .write(to: log, atomically: true, encoding: .utf8)
        let changed = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        #expect(changed.allTime.tokens == 220)
        #expect(try FileManager.default.attributesOfItem(atPath: saved.path)[.modificationDate] as? Date != sentinel)
        let restored = await UsageLedgerReader(home: home, cacheDirectory: cache).ledger(for: .claudeCode, prices: prices)
        #expect(restored.allTime.tokens == 220)

        // A deleted transcript leaves the cache and is kept in the archive,
        // so its work is still counted.
        try FileManager.default.removeItem(at: log)
        let removed = await reader.ledger(for: .claudeCode, refresh: true, prices: prices)
        #expect(removed.allTime.tokens == 220)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: saved)) as? [String: Any])
        #expect((object["files"] as? [String: Any])?.isEmpty == true)
        #expect(TranscriptArchive.load(for: .claudeCode, directory: cache)?.files.keys.contains { $0.hasSuffix("/fixture/s.jsonl") } == true)
    }
}
