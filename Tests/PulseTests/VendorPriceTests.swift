import Foundation
import SQLite3
import Testing
@testable import Pulse

/// Pricing a model no first-party provider publishes, at the rate the plan it
/// was bought on charges.
///
/// The case this exists for: `deepseek-v4.1-flash` is real, OpenCode Go sells
/// it, and DeepSeek's own models.dev entry does not list it — so a machine
/// that had spent 150k tokens on it showed no figure at all.
@Suite("Vendor prices")
struct VendorPriceTests {
    private static let table: [String: ModelPrice] = [
        "deepseek-v4-flash": ModelPrice(input: 0.15, output: 0.6, cacheRead: 0.003, cacheWrite: nil, name: "DeepSeek V4 Flash"),
        ModelPrices.vendorKey("opencode-go", "deepseek-v4.1-flash"):
            ModelPrice(input: 0.15, output: 0.6, cacheRead: 0.003, cacheWrite: nil, name: "DeepSeek V4.1 Flash"),
        ModelPrices.vendorKey("opencode-go", "deepseek-v4-flash"):
            ModelPrice(input: 99, output: 99, cacheRead: nil, cacheWrite: nil, name: "Wrong"),
    ]

    @Test("A model only the plan vendor publishes is priced by that vendor")
    func vendorFallback() {
        let price = ModelPrices.price(for: "deepseek-v4.1-flash", in: Self.table, vendor: "opencode-go")
        #expect(price?.input == 0.15)
        #expect(price?.output == 0.6)
    }

    /// The whole reason vendor rates are namespaced: a caller that did not ask
    /// for a vendor must never be handed one's price.
    @Test("Without a vendor the same model stays unpriced")
    func noVendorNoPrice() {
        #expect(ModelPrices.price(for: "deepseek-v4.1-flash", in: Self.table) == nil)
    }

    /// A vendor re-listing a model the model's own maker publishes must not
    /// shadow it — the first-party rate is the answer, the plan's is not a
    /// second opinion on it.
    @Test("A first-party price always wins over the plan vendor's")
    func firstPartyWins() {
        let price = ModelPrices.price(for: "deepseek-v4-flash", in: Self.table, vendor: "opencode-go")
        #expect(price?.input == 0.15, "the vendor's 99 must not be reachable")
    }

    @Test("A vendor that sells nothing for the model is still nil")
    func unknownStaysUnpriced() {
        #expect(ModelPrices.price(for: "no-such-model", in: Self.table, vendor: "opencode-go") == nil)
    }

    /// Only the agents whose plan is a reseller carry one; an agent that calls
    /// the model vendors directly must not get a second answer.
    @Test("Only plan-based agents name a vendor")
    func whoHasAVendor() {
        #expect(SpendAgent.openCode.priceVendor == "opencode-go")
        #expect(SpendAgent.kiloCLI.priceVendor == "kilo")
        #expect(SpendAgent.cline.priceVendor == "cline-pass")
        #expect(SpendAgent.claudeCode.priceVendor == nil)
        #expect(SpendAgent.codex.priceVendor == nil)
    }

    @Test("Plan prices survive the record, day, model and session pricing chain")
    func recordPricingChain() throws {
        let at = Date(timeIntervalSince1970: 1_789_560_000)
        let tally = TokenTally(input: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000, output: 1_000_000)
        let prices = [ModelPrices.vendorKey("cline-pass", "plan-only"):
            ModelPrice(input: 2, output: 3, cacheRead: 0.5, cacheWrite: 1, name: "Plan model")]
        let ledger = AgentUsageLedger.build(
            [AgentUsageRecord(timestamp: at, model: "plan-only", tally: tally, sessionID: "s")],
            prices: prices, namespace: "cline", vendor: SpendAgent.cline.priceVendor
        )
        let summary = SpendSummary.of([.cline: ledger], overLast: 1, now: at)
        let detail = ModelSpendSummary.of([.cline: ledger], named: "Plan model", overLast: 1, now: at)
        #expect(summary.cost == 6.5)
        #expect(summary.unpricedTokens == 0)
        #expect(ledger.unpricedModels.isEmpty)
        #expect(ledger.slots.first?.cost == 6.5)
        #expect(ledger.sessions.first?.cost == 6.5)
        #expect(ledger.sessions.first?.slots.first?.cost == 6.5)
        #expect(detail.costBreakdown == TokenCost(input: 2, cacheWrite: 1, cacheRead: 0.5, output: 3))

        let withoutVendor = AgentUsageLedger.build(
            [AgentUsageRecord(timestamp: at, model: "plan-only", tally: tally)],
            prices: prices, namespace: "pi"
        )
        #expect(withoutVendor.days.first?.unpricedTokens == tally.total)
    }

    @Test("A price cache without tiers is only an offline fallback after upgrade")
    func previousTableDoesNotBlockUpgrade() throws {
        let root = URL.temporaryDirectory.appending(path: "PulsePriceUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = ModelPrices.Cache(fetchedAt: Date(), prices: ["direct": Self.table["deepseek-v4-flash"]!])
        try JSONEncoder().encode(previous).write(to: root.appending(path: "model-prices-4.json"))
        #expect(ModelPrices.readCache(in: root) == nil)
        #expect(ModelPrices.readCache(in: root, allowPreviousVersion: true)?.prices == previous.prices)
        let current = ModelPrices.Cache(fetchedAt: Date(), prices: Self.table)
        try JSONEncoder().encode(current).write(to: root.appending(path: "model-prices-5.json"))
        #expect(ModelPrices.readCache(in: root)?.prices == current.prices)
        #expect(ModelPrices.readCache(in: root, allowPreviousVersion: true)?.prices == current.prices)
    }

    @Test("The shared database reader uses each agent's vendor", arguments: [SpendAgent.openCode, .kiloCLI])
    func databasePricingChain(agent: SpendAgent) throws {
        let root = URL.temporaryDirectory.appending(path: "PulseVendorPrices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try #require(agent.inputs(home: root, environment: [:]).first)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        try #require(sqlite3_open(file.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let at = Date(timeIntervalSince1970: 1_789_560_000)
        let message = """
        {"role":"assistant","modelID":"plan-only","time":{"created":\(Int(at.timeIntervalSince1970 * 1000))},"tokens":{"input":1000000,"output":0}}
        """
        for sql in [
            "CREATE TABLE session (id TEXT, slug TEXT, directory TEXT, title TEXT)",
            "CREATE TABLE message (session_id TEXT, data TEXT)",
            "INSERT INTO session VALUES ('s','s','/work/review','Test')",
            "INSERT INTO message VALUES ('s','\(message)')",
        ] {
            try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        let prices = [
            ModelPrices.vendorKey("kilo", "plan-only"):
                ModelPrice(input: 2, output: 3, cacheRead: nil, cacheWrite: nil, name: "Plan model"),
            ModelPrices.vendorKey("opencode-go", "plan-only"):
                ModelPrice(input: 9, output: 9, cacheRead: nil, cacheWrite: nil, name: "Plan model"),
        ]
        let ledger = AgentLedgers.read(agent, prices: prices, home: root, environment: [:]).ledger
        let expected = agent == .kiloCLI ? 2.0 : 9.0
        #expect(ledger.allTime.cost == expected)
        #expect(ledger.sessions.first?.cost == expected)
        #expect(ledger.slots.first?.cost == expected)
        #expect(ledger.unpricedModels.isEmpty)
        let detail = ModelSpendSummary.of([agent: ledger], named: "Plan model", overLast: 1, now: at)
        #expect(detail.cost == expected)

        var firstParty = prices
        firstParty["plan-only"] = ModelPrice(input: 1, output: 1, cacheRead: nil, cacheWrite: nil, name: nil)
        let direct = AgentLedgers.read(agent, prices: firstParty, home: root, environment: [:]).ledger
        #expect(direct.allTime.cost == 1)
        #expect(direct.sessions.first?.cost == 1)
    }
}

/// Command Code's records name `deepseek-v4.1-flash`, which DeepSeek does not
/// list and Command Code's own price list sells as
/// `deepseek/deepseek-v4.1-flash`.
struct CommandCodeVendorPriceTests {
    private static var document: [String: Any] { [
        "deepseek": ["models": ["deepseek-v4-flash": ["cost": ["input": 0.27, "output": 1.1]]]],
        "commandcode": ["models": [
            "deepseek/deepseek-v4.1-flash": ["cost": ["input": 0.15, "output": 0.6, "cache_read": 0.003]],
            "deepseek/deepseek-v4-flash": ["cost": ["input": 9, "output": 9]],
        ]],
    ] }

    @Test("Command Code's own list prices a model DeepSeek does not, by its bare name")
    func barePrice() throws {
        let table = try #require(ModelPrices.table(from: Self.document))
        let price = ModelPrices.price(for: "deepseek-v4.1-flash", in: table, vendor: SpendAgent.commandCode.priceVendor)
        #expect(price?.input == 0.15)
        #expect(price?.cacheRead == 0.003)
        // Never for anyone who did not ask for Command Code's list.
        #expect(ModelPrices.price(for: "deepseek-v4.1-flash", in: table) == nil)
        // And never over the maker's own rate.
        #expect(ModelPrices.price(for: "deepseek-v4-flash", in: table, vendor: "commandcode")?.input == 0.27)
    }
}
