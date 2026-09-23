import Foundation
import os
import Testing
@testable import Pulse

@Suite("Model price cache lifecycle")
struct ModelPriceCacheTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let day: TimeInterval = 86_400
    private static let retry: TimeInterval = 300

    private static func table(_ input: Double) -> [String: ModelPrice] {
        ["probe-model": ModelPrice(input: input, output: 2, cacheRead: nil, cacheWrite: nil, name: "Probe")]
    }

    private static func directory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulsePriceCache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func save(_ prices: [String: ModelPrice], at date: Date, in root: URL,
                             version: Int = 4) throws {
        let cache = ModelPrices.Cache(fetchedAt: date, prices: prices)
        try JSONEncoder().encode(cache).write(to: root.appending(path: "model-prices-\(version).json"))
    }

    private final class Clock: Sendable {
        private let value = OSAllocatedUnfairLock(initialState: ModelPriceCacheTests.start)
        func now() -> Date { value.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { value.withLock { $0.addTimeInterval(seconds) } }
    }

    private actor Downloads {
        let replies: [[String: ModelPrice]?]
        private(set) var calls = 0
        init(_ replies: [[String: ModelPrice]?]) { self.replies = replies }
        func read() -> [String: ModelPrice]? {
            let index = calls
            calls += 1
            return index < replies.count ? replies[index] : nil
        }
    }

    @Test("A disk table expires at its original fetch time, including after loading into memory")
    func diskExpiry() async throws {
        let root = try Self.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock()
        let old = Self.table(1), new = Self.table(9)
        try Self.save(old, at: clock.now().addingTimeInterval(-23 * 3_600), in: root)
        let downloads = Downloads([new])
        let prices = ModelPrices(cacheDirectory: root, now: { clock.now() }, download: { await downloads.read() })

        #expect(await prices.prices() == old)
        clock.advance(3_599)
        #expect(await prices.prices() == old)
        #expect(await downloads.calls == 0)
        clock.advance(1)
        #expect(await prices.prices() == new)
        #expect(await downloads.calls == 1)
        #expect(ModelPrices.readCache(in: root)?.fetchedAt == clock.now())
        #expect(ModelPrices.readCache(in: root)?.prices == new)

        // Relaunching reuses the download without granting it another day.
        let relaunched = ModelPrices(cacheDirectory: root, now: { clock.now() }, download: { await downloads.read() })
        #expect(await relaunched.prices() == new)
        #expect(await downloads.calls == 1)
    }

    @Test("A downloaded table also expires while the same instance stays alive")
    func downloadedTableExpires() async throws {
        let root = try Self.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock()
        let old = Self.table(1), new = Self.table(9)
        let downloads = Downloads([old, new])
        let prices = ModelPrices(cacheDirectory: root, now: { clock.now() }, download: { await downloads.read() })
        #expect(await prices.prices() == old)
        clock.advance(Self.day - 1)
        #expect(await prices.prices() == old)
        #expect(await downloads.calls == 1)
        clock.advance(1)
        #expect(await prices.prices() == new)
        #expect(await downloads.calls == 2)
    }

    @Test("Offline fallback can recover without a relaunch, including a fresh pre-vendor table", arguments: [3, 4])
    func offlineFallbackRecovers(version: Int) async throws {
        let root = try Self.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock()
        let old = Self.table(1), new = Self.table(9)
        let originalDate = version == 3 ? clock.now() : clock.now().addingTimeInterval(-3 * Self.day)
        try Self.save(old, at: originalDate, in: root, version: version)
        let downloads = Downloads([nil, new])
        let prices = ModelPrices(cacheDirectory: root, now: { clock.now() }, download: { await downloads.read() })
        #expect(await prices.prices() == old)
        #expect(await downloads.calls == 1)
        #expect(ModelPrices.readCache(in: root, allowPreviousVersion: true)?.fetchedAt == originalDate)
        if version == 3 { #expect(ModelPrices.readCache(in: root) == nil) }
        clock.advance(Self.retry - 1)
        #expect(await prices.prices() == old)
        #expect(await downloads.calls == 1)
        clock.advance(1)
        #expect(await prices.prices() == new)
        #expect(await downloads.calls == 2)
        #expect(ModelPrices.readCache(in: root)?.fetchedAt == clock.now())
        #expect(ModelPrices.readCache(in: root)?.prices == new)
    }

    @Test("An offline first run retries without writing an empty price table")
    func missingCacheRecovers() async throws {
        let root = try Self.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock()
        let new = Self.table(9)
        let downloads = Downloads([nil, new])
        let prices = ModelPrices(cacheDirectory: root, now: { clock.now() }, download: { await downloads.read() })
        #expect(await prices.prices().isEmpty)
        #expect(ModelPrices.readCache(in: root) == nil)
        clock.advance(Self.retry - 1)
        #expect(await prices.prices().isEmpty)
        #expect(await downloads.calls == 1)
        clock.advance(1)
        #expect(await prices.prices() == new)
        #expect(await downloads.calls == 2)
    }

    @Test("A failed refresh keeps the last download and its timestamp")
    func failedRefreshPreservesSnapshot() async throws {
        let root = try Self.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock()
        let old = Self.table(1), new = Self.table(9)
        let downloads = Downloads([old, nil, nil, new])
        let prices = ModelPrices(cacheDirectory: root, now: { clock.now() }, download: { await downloads.read() })
        #expect(await prices.prices() == old)
        clock.advance(Self.day)
        #expect(await prices.prices() == old)
        #expect(await downloads.calls == 2)
        clock.advance(Self.retry)
        #expect(await prices.prices() == old)
        #expect(await downloads.calls == 3)
        #expect(ModelPrices.readCache(in: root)?.fetchedAt == Self.start)
        clock.advance(Self.retry)
        #expect(await prices.prices() == new)
        #expect(await downloads.calls == 4)
    }

    private actor PendingDownload {
        private(set) var calls = 0
        private var replies: [CheckedContinuation<[String: ModelPrice]?, Never>] = []
        private var result: [String: ModelPrice]?
        private var started: CheckedContinuation<Void, Never>?
        func read() async -> [String: ModelPrice]? {
            calls += 1
            if let result { return result }
            return await withCheckedContinuation { continuation in
                replies.append(continuation)
                started?.resume()
                started = nil
            }
        }
        func waitUntilStarted() async {
            if calls > 0 { return }
            await withCheckedContinuation { started = $0 }
        }
        func finish(_ prices: [String: ModelPrice]) {
            result = prices
            for reply in replies { reply.resume(returning: prices) }
            replies.removeAll()
        }
    }

    @Test("Concurrent readers share a refresh and date the result when it arrives")
    func concurrentRefresh() async throws {
        let root = try Self.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock()
        let old = Self.table(1), new = Self.table(9)
        try Self.save(old, at: clock.now().addingTimeInterval(-Self.day), in: root)
        let download = PendingDownload()
        let prices = ModelPrices(cacheDirectory: root, now: { clock.now() }, download: { await download.read() })
        let first = Task { await prices.prices() }
        await download.waitUntilStarted()
        let readers = (0..<12).map { _ in Task { await prices.prices() } }
        // Leaving one pane must not cancel the download another reader needs.
        first.cancel()
        clock.advance(30)
        await download.finish(new)
        #expect(await first.value == new)
        for reader in readers { #expect(await reader.value == new) }
        #expect(await download.calls == 1)
        #expect(ModelPrices.readCache(in: root)?.fetchedAt == clock.now())
    }
}
