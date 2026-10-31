import Foundation
import Testing
@testable import Pulse

/// The Group A family entry point: which clients it supports, where each one's
/// roots are, and how the shared Pi-shaped parser and Prime's reconciliation
/// turn synthetic transcripts into incremental records.
///
/// Every store is built by hand under a private temporary root; cleanup removes
/// only the root the test created. Dates are fixed.
@Suite("Session log readers")
struct SessionLogReadersTests {
    private static let expectedClients: Set<String> = [
        "pi", "omp", "senpi", "kimchi", "prime-agent",
        "gemini", "qwen", "amp", "droid", "openclaw",
    ]

    private static let prices: [String: ModelPrice] = [
        "gpt-5": ModelPrice(input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "GPT-5"),
        "helper": ModelPrice(input: 2_000, output: 4_000, cacheRead: 50, cacheWrite: 500, name: "Helper"),
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let now = Date(timeIntervalSince1970: 1_789_372_800)

    // MARK: - Store helpers

    private static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulseSessionReaders-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// One Pi-shaped session file with a single assistant message.
    private static func piFile(
        id: String,
        cwd: String = "/work/pulse",
        messageID: String = "m1",
        responseID: String? = nil,
        model: String = "gpt-5",
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheWrite: Int,
        reasoning: Int? = nil,
        at: String = "2026-01-02T03:05:00Z"
    ) -> String {
        var usage = #"{"input":\#(input),"output":\#(output),"cacheRead":\#(cacheRead),"cacheWrite":\#(cacheWrite),"totalTokens":\#(input + output + cacheRead + cacheWrite)"#
        if let reasoning { usage += ",\"reasoning\":\(reasoning)" }
        usage += "}"
        let response = responseID.map { ",\"responseId\":\"\($0)\"" } ?? ""
        return """
        {"type":"session","id":"\(id)","timestamp":"\(at)","cwd":"\(cwd)"}
        {"type":"message","id":"\(messageID)","timestamp":"\(at)","message":{"role":"assistant","model":"\(model)","provider":"openai"\(response),"usage":\(usage)}}
        """
    }

    private static func totals(_ records: [AgentUsageRecord], namespace: String) -> UsageLedger {
        AgentUsageLedger.build(records, prices: prices, namespace: namespace, calendar: calendar)
    }

    private static func at(hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: now))!
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter.string(from: date)
    }

    // MARK: - Dispatch and inputs

    @Test("The supported set is exactly the clients that parse, and nothing else")
    func supportedClientsMatchReaders() {
        #expect(SessionLogReaders.supportedClients == Self.expectedClients)
        #expect(SessionLogReaders.records(client: "nope", roots: []).isEmpty)
        #expect(SessionLogReaders.inputs(client: "nope", home: URL(fileURLWithPath: "/tmp")).isEmpty)
    }

    @Test("Inputs name the documented roots and honour the non-colliding overrides")
    func inputsNameDocumentedRoots() {
        let home = URL(fileURLWithPath: "/Users/test")

        #expect(SessionLogReaders.inputs(client: "pi", home: home).first?.path == "/Users/test/.pi/agent/sessions")
        #expect(SessionLogReaders.inputs(client: "omp", home: home).first?.path == "/Users/test/.omp/agent/sessions")
        #expect(SessionLogReaders.inputs(client: "qwen", home: home).first?.path == "/Users/test/.qwen/projects")
        #expect(SessionLogReaders.inputs(client: "amp", home: home).first?.path == "/Users/test/.local/share/amp/threads")
        #expect(SessionLogReaders.inputs(client: "droid", home: home).first?.path == "/Users/test/.factory/sessions")

        // None of Pi or omp honours a shared PI_CODING_AGENT_DIR: one tree read
        // twice would double-count.
        let piEnv = ["PI_CODING_AGENT_DIR": "/data/pi"]
        #expect(SessionLogReaders.inputs(client: "pi", home: home, environment: piEnv).first?.path == "/Users/test/.pi/agent/sessions")
        #expect(SessionLogReaders.inputs(client: "omp", home: home, environment: piEnv).first?.path == "/Users/test/.omp/agent/sessions")

        #expect(SessionLogReaders.inputs(client: "senpi", home: home, environment: ["SENPI_CODING_AGENT_DIR": "/data/senpi"]).first?.path == "/data/senpi/sessions")
        #expect(SessionLogReaders.inputs(client: "kimchi", home: home, environment: ["KIMCHI_CODING_AGENT_DIR": "/data/kimchi"]).first?.path == "/data/kimchi/sessions")
        #expect(SessionLogReaders.inputs(client: "gemini", home: home, environment: ["GEMINI_CLI_HOME": "/data/gemini"]).first?.path == "/data/gemini/tmp")

        let prime = SessionLogReaders.inputs(client: "prime-agent", home: home, environment: ["PRIME_AGENT_CODING_AGENT_DIR": "/data/prime"]).map(\.path)
        #expect(prime.contains("/data/prime/sessions"))
        #expect(prime.contains("/data/prime/session-artifacts"))

        let openclaw = SessionLogReaders.inputs(client: "openclaw", home: home).map(\.path)
        #expect(openclaw.contains("/Users/test/.openclaw/agents"))
        #expect(openclaw.contains("/Users/test/.clawdbot"))
        #expect(openclaw.contains("/Users/test/.moltbot"))
        #expect(openclaw.contains("/Users/test/.moldbot"))
    }

    // MARK: - The shared Pi format

    @Test("Pi reads the four buckets and leaves reasoning inside output")
    func piReadsBuckets() throws {
        let home = try Self.temporary("pi-buckets")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "pi", home: home)
        let root = try #require(roots.first)
        try Self.write(
            Self.piFile(id: "sess-a", messageID: "m1", responseID: "resp-1",
                        input: 100, output: 40, cacheRead: 30, cacheWrite: 20, reasoning: 12),
            to: root.appending(path: "encoded-cwd/session.jsonl")
        )

        let records = SessionLogReaders.records(client: "pi", roots: roots)
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40))
        #expect(record.model == "gpt-5")
        #expect(record.sessionID == "sess-a")
        #expect(record.project == "/work/pulse")
        #expect(record.deduplicationID == "pi:response:resp-1")
        #expect(record.unclassifiedTokens == 0)
    }

    @Test("A bare total is unclassified, never poured into input")
    func bareTotalIsUnclassified() throws {
        let home = try Self.temporary("pi-total")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "pi", home: home)
        let root = try #require(roots.first)
        try Self.write(
            """
            {"type":"session","id":"s","timestamp":"2026-01-02T03:05:00Z","cwd":"/work/x"}
            {"type":"message","id":"m","timestamp":"2026-01-02T03:05:01Z","message":{"role":"assistant","model":"gpt-5","usage":{"totalTokens":77}}}
            """,
            to: root.appending(path: "s.jsonl")
        )

        let record = try #require(SessionLogReaders.records(client: "pi", roots: roots).first)
        #expect(record.tally == TokenTally())
        #expect(record.unclassifiedTokens == 77)
    }

    @Test("A malformed header discards the whole file; only title metadata may precede it")
    func malformedHeaderDiscardsFile() throws {
        let home = try Self.temporary("pi-malformed")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "pi", home: home)
        let root = try #require(roots.first)

        // A message before any session header is not a session.
        try Self.write(
            #"{"type":"message","id":"m","timestamp":"2026-01-02T03:05:00Z","message":{"role":"assistant","model":"gpt-5","usage":{"input":5}}}"#,
            to: root.appending(path: "no-header.jsonl")
        )
        #expect(SessionLogReaders.records(client: "pi", roots: roots).isEmpty)

        // A title record ahead of a real header is ordinary and kept.
        try Self.write(
            """
            {"type":"title","title":"The ring"}
            {"type":"session","id":"ok","timestamp":"2026-01-02T03:05:00Z","cwd":"/w"}
            {"type":"message","id":"m","timestamp":"2026-01-02T03:05:01Z","message":{"role":"assistant","model":"gpt-5","usage":{"input":5}}}
            """,
            to: root.appending(path: "with-title.jsonl")
        )
        #expect(SessionLogReaders.records(client: "pi", roots: roots).count == 1)
    }

    @Test("A fork copy of one message folds onto its original by response id")
    func forkCopiesFoldByResponseID() throws {
        let home = try Self.temporary("pi-fork")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "pi", home: home)
        let root = try #require(roots.first)
        try Self.write(Self.piFile(id: "a", responseID: "resp-shared", input: 100, output: 10, cacheRead: 0, cacheWrite: 0),
                       to: root.appending(path: "a.jsonl"))
        try Self.write(Self.piFile(id: "b", messageID: "m-other", responseID: "resp-shared", input: 100, output: 10, cacheRead: 0, cacheWrite: 0),
                       to: root.appending(path: "b.jsonl"))

        let records = SessionLogReaders.records(client: "pi", roots: roots)
        #expect(records.count == 2)
        #expect(Self.totals(records, namespace: "pi").days.reduce(0) { $0 + $1.tokens } == 110)
    }

    @Test("The shared Pi format routes under each family id from its own root", arguments: ["pi", "omp", "senpi", "kimchi", "prime-agent"])
    func familyRoutesEachID(client: String) throws {
        let home = try Self.temporary("family-\(client)")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: client, home: home)
        let root = try #require(roots.first)
        try Self.write(
            Self.piFile(id: "s", messageID: "m1", input: 100, output: 40, cacheRead: 30, cacheWrite: 20),
            to: root.appending(path: "cwd/session.jsonl")
        )

        let records = SessionLogReaders.records(client: client, roots: roots)
        #expect(records.count == 1)
        #expect(records.first?.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40))
    }

    @Test("omp keeps the message's provider, and a provider view reads only that provider's records")
    func ompProviderView() throws {
        let home = try Self.temporary("omp-provider")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "omp", home: home)
        let root = try #require(roots.first)
        try Self.write(
            """
            {"type":"session","id":"s","timestamp":"2026-01-02T03:05:00Z","cwd":"/work/pulse"}
            {"type":"message","id":"d","timestamp":"2026-01-02T03:05:01Z","message":{"role":"assistant","model":"swe-2","provider":"devin","usage":{"input":100,"output":10}}}
            {"type":"message","id":"x","timestamp":"2026-01-02T03:05:02Z","message":{"role":"assistant","model":"grok-4","provider":"xai-oauth","usage":{"input":200,"output":20}}}
            """,
            to: root.appending(path: "cwd/session.jsonl")
        )

        // The whole store keeps both, each under the provider the message
        // named; a message with none falls back to the client's own id.
        let records = SessionLogReaders.records(client: "omp", roots: roots)
        #expect(records.map(\.provider) == ["devin", "xai-oauth"])

        // The Devin card's view of the same store is only the Devin records.
        let devin = AgentLedgers.read(
            .omp, prices: Self.prices, home: home, environment: [:], provider: "devin"
        ).ledger
        #expect(devin.days.reduce(0) { $0 + $1.tokens } == 110)
        #expect(devin.days.first?.models == ["swe-2": 110])

        // The unfiltered read through the same dispatch keeps everything.
        let whole = AgentLedgers.read(.omp, prices: Self.prices, home: home, environment: [:]).ledger
        #expect(whole.days.reduce(0) { $0 + $1.tokens } == 330)
    }

    @Test("Senpi reads OmO project children named by a session header")
    func senpiDiscoversProjectChildren() throws {
        let home = try Self.temporary("senpi-children")
        defer { try? FileManager.default.removeItem(at: home) }
        let project = try Self.temporary("senpi-project")
        defer { try? FileManager.default.removeItem(at: project) }

        let base = home.appending(path: ".senpi/agent/sessions")
        try Self.write(
            Self.piFile(id: "parent", cwd: project.path, messageID: "p1", input: 10, output: 1, cacheRead: 0, cacheWrite: 0),
            to: base.appending(path: "parent.jsonl")
        )
        try Self.write(
            Self.piFile(id: "child", cwd: project.path, messageID: "c1", responseID: "child-1", input: 20, output: 2, cacheRead: 0, cacheWrite: 0),
            to: project.appending(path: ".omo/senpi-task/children/child.jsonl")
        )

        let roots = SessionLogReaders.inputs(client: "senpi", home: home)
        #expect(roots.map(\.path).contains(project.appending(path: ".omo/senpi-task/children").path))

        let records = SessionLogReaders.records(client: "senpi", roots: roots)
        #expect(records.count == 2)
        #expect(records.contains { $0.sessionID == "child" })
    }

    @Test("Kimchi's session-scoped key keeps two sessions' equal message ids apart")
    func kimchiDedupIsSessionScoped() throws {
        let home = try Self.temporary("kimchi-scope")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "kimchi", home: home)
        let root = try #require(roots.first)

        // The same message id in two sessions is two records.
        try Self.write(Self.piFile(id: "s1", messageID: "shared", input: 100, output: 0, cacheRead: 0, cacheWrite: 0),
                       to: root.appending(path: "one.jsonl"))
        try Self.write(Self.piFile(id: "s2", messageID: "shared", input: 100, output: 0, cacheRead: 0, cacheWrite: 0),
                       to: root.appending(path: "two.jsonl"))
        let records = SessionLogReaders.records(client: "kimchi", roots: roots)
        #expect(records.count == 2)
        #expect(Self.totals(records, namespace: "kimchi").days.reduce(0) { $0 + $1.tokens } == 200)

        // The same id repeated inside one session is one record after folding.
        try Self.write(
            Self.piFile(id: "s3", messageID: "dup", input: 100, output: 0, cacheRead: 0, cacheWrite: 0)
                + "\n"
                + Self.piFile(id: "s3", messageID: "dup", input: 100, output: 0, cacheRead: 0, cacheWrite: 0),
            to: root.appending(path: "three.jsonl")
        )
        let records3 = SessionLogReaders.records(client: "kimchi", roots: [root.appending(path: "three.jsonl")])
        #expect(records3.count == 2)
        #expect(Self.totals(records3, namespace: "kimchi").days.reduce(0) { $0 + $1.tokens } == 100)
    }

    // MARK: - Prime reconciliation

    @Test("A parent aggregate is reduced by the child's own usage, once")
    func primeReconcilesParentAndChild() throws {
        let home = try Self.temporary("prime-reconcile")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appending(path: ".prime/agent/sessions")
        let artifacts = home.appending(path: ".prime/agent/session-artifacts")
        let parentPath = sessions.appending(path: "parent.jsonl").path

        try Self.write(
            """
            {"type":"session","id":"parent","timestamp":"2026-01-02T03:00:00Z","cwd":"/work/pulse"}
            {"type":"message","id":"pm1","timestamp":"2026-01-02T03:05:00Z","message":{"role":"assistant","model":"gpt-5","responseId":"parent-reply","usage":{"input":200,"output":100,"cacheRead":0,"cacheWrite":0,"totalTokens":300}}}
            {"type":"child_usage_attributed","id":"ab12cd34","targetId":"pm1","childUsage":{"input":30,"output":10,"cacheRead":0,"cacheWrite":0},"aggregateUsage":{"input":200,"output":100,"cacheRead":0,"cacheWrite":0},"origin":"child"}
            """,
            to: sessions.appending(path: "parent.jsonl")
        )
        try Self.write(
            """
            {"type":"session","id":"child","timestamp":"2026-01-02T03:04:00Z","cwd":"/work/pulse","parentSession":"\(parentPath)","rlmDepth":1}
            {"type":"message","id":"cm1","timestamp":"2026-01-02T03:04:30Z","message":{"role":"assistant","model":"helper","responseId":"child-reply","usage":{"input":30,"output":10,"cacheRead":0,"cacheWrite":0,"totalTokens":40}}}
            """,
            to: artifacts.appending(path: "run/sub-1/child.jsonl")
        )

        let records = SessionLogReaders.records(client: "prime-agent", roots: [sessions, artifacts])
        #expect(records.count == 2)

        let parent = try #require(records.first { $0.sessionID == "parent" })
        #expect(parent.tally == TokenTally(input: 170, cacheWrite: 0, cacheRead: 0, output: 90))
        let child = try #require(records.first { $0.sessionID == "child" })
        #expect(child.tally == TokenTally(input: 30, cacheWrite: 0, cacheRead: 0, output: 10))

        // Without reconciliation this would be 340, not the reported 300.
        #expect(Self.totals(records, namespace: "prime-agent").days.reduce(0) { $0 + $1.tokens } == 300)
    }

    @Test("An unavailable child leaves the parent's aggregate untouched")
    func primeKeepsAggregateWhenChildMissing() throws {
        let home = try Self.temporary("prime-missing-child")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appending(path: ".prime/agent/sessions")

        try Self.write(
            """
            {"type":"session","id":"parent","timestamp":"2026-01-02T03:00:00Z","cwd":"/work/pulse"}
            {"type":"message","id":"pm1","timestamp":"2026-01-02T03:05:00Z","message":{"role":"assistant","model":"gpt-5","responseId":"parent-reply","usage":{"input":200,"output":100,"cacheRead":0,"cacheWrite":0,"totalTokens":300}}}
            {"type":"child_usage_attributed","id":"ab12cd34","targetId":"pm1","childUsage":{"input":30,"output":10,"cacheRead":0,"cacheWrite":0},"aggregateUsage":{"input":200,"output":100,"cacheRead":0,"cacheWrite":0}}
            """,
            to: sessions.appending(path: "parent.jsonl")
        )

        let records = SessionLogReaders.records(client: "prime-agent", roots: [sessions])
        #expect(records.count == 1)
        #expect(records.first?.tally == TokenTally(input: 200, cacheWrite: 0, cacheRead: 0, output: 100))
    }

    @Test("A fork copy's attribution is not applied twice")
    func primeAttributionCollapsesAcrossForks() throws {
        let home = try Self.temporary("prime-fork")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appending(path: ".prime/agent/sessions")
        let artifacts = home.appending(path: ".prime/agent/session-artifacts")
        let firstPath = sessions.appending(path: "parent.jsonl").path

        let body =
            """
            {"type":"message","id":"pm1","timestamp":"2026-01-02T03:05:00Z","message":{"role":"assistant","model":"gpt-5","responseId":"parent-reply","usage":{"input":200,"output":100,"cacheRead":0,"cacheWrite":0,"totalTokens":300}}}
            {"type":"child_usage_attributed","id":"deadbeef","targetId":"pm1","childUsage":{"input":30,"output":10,"cacheRead":0,"cacheWrite":0},"aggregateUsage":{"input":200,"output":100,"cacheRead":0,"cacheWrite":0}}
            """
        try Self.write(
            """
            {"type":"session","id":"parent","timestamp":"2026-01-02T03:00:00Z","cwd":"/work/pulse"}
            \(body)
            """,
            to: sessions.appending(path: "parent.jsonl")
        )
        try Self.write(
            """
            {"type":"session","id":"fork","timestamp":"2026-01-02T03:00:00Z","cwd":"/work/pulse","parentSession":"\(firstPath)"}
            \(body)
            """,
            to: sessions.appending(path: "fork.jsonl")
        )
        try Self.write(
            """
            {"type":"session","id":"child","timestamp":"2026-01-02T03:04:00Z","cwd":"/work/pulse","parentSession":"\(firstPath)","rlmDepth":1}
            {"type":"message","id":"cm1","timestamp":"2026-01-02T03:04:30Z","message":{"role":"assistant","model":"helper","responseId":"child-reply","usage":{"input":30,"output":10,"cacheRead":0,"cacheWrite":0,"totalTokens":40}}}
            """,
            to: artifacts.appending(path: "run/sub-1/child.jsonl")
        )

        let records = SessionLogReaders.records(client: "prime-agent", roots: [sessions, artifacts])
        // The two parent copies fold by response id, the child stands alone.
        #expect(Self.totals(records, namespace: "prime-agent").days.reduce(0) { $0 + $1.tokens } == 300)
    }

    @Test("Attributions sharing an id in unrelated sessions stay separate")
    func primeAttributionCollisionsStaySeparate() throws {
        let home = try Self.temporary("prime-collision")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appending(path: ".prime/agent/sessions")
        let artifacts = home.appending(path: ".prime/agent/session-artifacts")

        for name in ["one", "two"] {
            let parentPath = sessions.appending(path: "\(name).jsonl").path
            try Self.write(
                """
                {"type":"session","id":"p-\(name)","timestamp":"2026-01-02T03:00:00Z","cwd":"/work/\(name)"}
                {"type":"message","id":"pm-\(name)","timestamp":"2026-01-02T03:05:00Z","message":{"role":"assistant","model":"gpt-5","responseId":"reply-\(name)","usage":{"input":100,"output":50,"cacheRead":0,"cacheWrite":0,"totalTokens":150}}}
                {"type":"child_usage_attributed","id":"cafebabe","targetId":"pm-\(name)","childUsage":{"input":10,"output":5,"cacheRead":0,"cacheWrite":0},"aggregateUsage":{"input":100,"output":50,"cacheRead":0,"cacheWrite":0}}
                """,
                to: sessions.appending(path: "\(name).jsonl")
            )
            try Self.write(
                """
                {"type":"session","id":"c-\(name)","timestamp":"2026-01-02T03:04:00Z","cwd":"/work/\(name)","parentSession":"\(parentPath)","rlmDepth":1}
                {"type":"message","id":"cm-\(name)","timestamp":"2026-01-02T03:04:30Z","message":{"role":"assistant","model":"helper","responseId":"child-\(name)","usage":{"input":10,"output":5,"cacheRead":0,"cacheWrite":0,"totalTokens":15}}}
                """,
                to: artifacts.appending(path: "\(name)/sub/child.jsonl")
            )
        }

        let records = SessionLogReaders.records(client: "prime-agent", roots: [sessions, artifacts])
        #expect(records.count == 4)
        #expect(records.filter { $0.sessionID?.hasPrefix("p-") == true }.allSatisfy {
            $0.tally == TokenTally(input: 90, cacheWrite: 0, cacheRead: 0, output: 45)
        })
        #expect(Self.totals(records, namespace: "prime-agent").days.reduce(0) { $0 + $1.tokens } == 300)
    }

    // MARK: - Through the production chain
    @Test("Pi records price through SpendSummary and ModelSpendSummary")
    func productionChain() throws {
        let home = try Self.temporary("pi-chain")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "pi", home: home)
        let root = try #require(roots.first)

        try Self.write(
            """
            {"type":"session","id":"s1","timestamp":"\(Self.iso(Self.at(hour: 9)))","cwd":"/work/pulse"}
            {"type":"message","id":"m1","timestamp":"\(Self.iso(Self.at(hour: 9)))","message":{"role":"assistant","model":"gpt-5","responseId":"r1","usage":{"input":100,"output":40,"cacheRead":30,"cacheWrite":20,"totalTokens":190}}}
            {"type":"message","id":"m2","timestamp":"\(Self.iso(Self.at(hour: 10)))","message":{"role":"assistant","model":"helper","responseId":"r2","usage":{"input":50,"output":10,"cacheRead":0,"cacheWrite":0,"totalTokens":60}}}
            """,
            to: root.appending(path: "day.jsonl")
        )

        let records = SessionLogReaders.records(client: "pi", roots: roots)
        let ledger = AgentUsageLedger.build(records, prices: Self.prices, namespace: "pi", calendar: Self.calendar)

        let summary = SpendSummary.of([.openCode: ledger], overLast: nil, now: Self.now, calendar: Self.calendar)
        #expect(summary.tokens == 250)
        #expect(summary.tally == TokenTally(input: 150, cacheWrite: 20, cacheRead: 30, output: 50))
        // gpt-5: 100*.001 + 20*.001 + 30*.0001 + 40*.01 = 0.523
        // helper: 50*.002 + 10*.004 = 0.14
        #expect(abs(summary.cost - 0.663) < 1e-9)
        #expect(summary.sessions.count == 1)

        let model = ModelSpendSummary.of([.openCode: ledger], named: "GPT-5", overLast: nil, now: Self.now, calendar: Self.calendar)
        #expect(model.tokens == 190)
        #expect(model.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40))
        #expect(abs((model.cost ?? -1) - 0.523) < 1e-9)
        let hours = try #require(model.hours)
        #expect(hours == [9: 190])
    }
}
