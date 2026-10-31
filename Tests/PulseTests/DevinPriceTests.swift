import Foundation
import Testing
@testable import Pulse

/// `swe-2` is Cognition's own model and the only vendor that serves it,
/// Devin, is not on models.dev at all — so the fetched table can never price
/// it. The supplement holds Devin's published list rate ($3.00/1M input,
/// $15.00/1M output, $0.30/1M cache input, per
/// https://docs.devin.ai/desktop/models) namespaced under `devin|`, and the
/// card's footnote says what the rate is the API-equivalent cost, not what a
/// promotional plan happened to bill.
@Suite("Devin prices")
struct DevinPriceTests {
    @Test("The supplement prices swe-2 at Devin's list rate, and only for a devin lookup")
    func supplementPricesSWE2() {
        let table = ModelPrices.supplemented([:])
        let price = ModelPrices.price(for: "swe-2", in: table, vendor: "devin")
        #expect(price?.input == 3)
        #expect(price?.output == 15)
        #expect(price?.cacheRead == 0.3)

        // Namespaced like a plan vendor: a lookup that did not ask for the
        // devin vendor must never see it.
        #expect(ModelPrices.price(for: "swe-2", in: table) == nil)
    }

    @Test("A first-party rate wins over the supplement, as it does over any vendor")
    func firstPartyWinsOverSupplement() {
        let table = ModelPrices.supplemented([
            "swe-2": ModelPrice(input: 9, output: 9, cacheRead: nil, cacheWrite: nil, name: "First-party"),
        ])
        let price = ModelPrices.price(for: "swe-2", in: table, vendor: "devin")
        #expect(price?.input == 9, "the supplement's 3 must not shadow a first-party rate")
    }

    /// Both Devin agents read models bought from Devin; the agents calling
    /// model vendors directly keep having no vendor.
    @Test("Devin's agents name the devin vendor")
    func devinAgentsCarryTheVendor() {
        #expect(SpendAgent.devinCLI.priceVendor == "devin")
        #expect(SpendAgent.devinDesktop.priceVendor == "devin")
        #expect(SpendAgent.omp.priceVendor == nil)
    }

    @Test("An omp record's own recorded cost is the slice's figure, the table only its fallback")
    func recordedCostPricesOmpRecords() throws {
        let home = try Self.temporary("devin-slice-price")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "omp", home: home)
        let root = try #require(roots.first)
        try Self.write(
            """
            {"type":"session","id":"s","timestamp":"2026-01-02T03:05:00Z","cwd":"/work/pulse"}
            {"type":"message","id":"d","timestamp":"2026-01-02T03:05:01Z","message":{"role":"assistant","model":"swe-2","provider":"devin","usage":{"input":1000000,"output":10000,"cost":{"input":0.75,"output":0.0375,"cacheRead":0,"cacheWrite":0,"total":0.7875}}}}
            {"type":"message","id":"f","timestamp":"2026-01-02T03:06:01Z","message":{"role":"assistant","model":"swe-2","provider":"devin","usage":{"input":1000000,"output":10000,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}}}}
            {"type":"message","id":"t","timestamp":"2026-01-02T03:07:01Z","message":{"role":"assistant","model":"gemini-3-1-pro","provider":"devin","usage":{"input":1000000,"output":10000}}}
            """,
            to: root.appending(path: "cwd/session.jsonl")
        )

        // The Devin card's slice costs each omp record at the dollar figure
        // omp itself wrote — omp's rate, not Devin's list rate, and not the
        // supplement the slice no longer asks for.
        let prices = ModelPrices.supplemented([:])
        let slice = AgentLedgers.read(
            .omp, prices: prices, home: home, environment: [:], provider: "devin"
        ).ledger
        #expect(abs(slice.allTime.cost - 0.7875) < 0.0001)
        // A recorded cost of zero is a real price, not an unpriced record:
        // only the cost-free record's million tokens stay unpriced.
        #expect(slice.unpricedModels == ["gemini-3-1-pro"])

        // The whole-store read prices the same way: recorded cost first.
        let whole = AgentLedgers.read(.omp, prices: prices, home: home, environment: [:]).ledger
        #expect(abs(whole.allTime.cost - 0.7875) < 0.0001)
        #expect(whole.unpricedModels == ["gemini-3-1-pro"])
    }

    // MARK: - Store helpers

    private static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulseDevinPrices-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
