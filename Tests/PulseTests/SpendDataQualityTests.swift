import Foundation
import Testing
@testable import Pulse

/// What the Token spend pane lists: one row for a conversation however many
/// files it is, a title in the user's words, no project made of a scratch
/// folder, and no stale cache left in Application Support. Every fixture is
/// built in a temporary directory, never read from the user's own agents.
@Suite("Token spend data quality")
struct SpendDataQualityTests {
    private static func temporary(_ name: String) -> URL {
        URL.temporaryDirectory.appending(path: "PulseQuality-\(name)-\(UUID().uuidString)")
    }

    private static func write(_ lines: [String], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - Subagent transcripts

    private static func reply(_ id: String, at time: String, input: Int, output: Int, sidechain: Bool = false) -> String {
        #"{"type":"assistant","isSidechain":\#(sidechain),"timestamp":"2026-09-20T\#(time):00Z","message":{"id":"\#(id)","model":"m","usage":{"input_tokens":\#(input),"output_tokens":\#(output)}}}"#
    }

    @Test("A subagent's transcript is part of its parent's session, and still counted")
    func subagentsFoldIntoTheirParent() async throws {
        let home = Self.temporary("subagents")
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let project = home.appending(path: ".claude/projects/-Users-me-Code-Pulse")
        let uuid = "c71d6cd6-71fd-4ffa-9896-1ed30f025090"

        try Self.write([
            #"{"type":"user","cwd":"/Users/me/Code/Pulse","message":{"role":"user","content":"fix the ring"}}"#,
            Self.reply("p1", at: "10:00", input: 100, output: 10),
        ], to: project.appending(path: "\(uuid).jsonl"))
        // A subagent's lines are sidechain, so none could be a title. Its
        // second reply is a copy of one in the parent (the same message id):
        // counted once, in the file whose work came first.
        try Self.write([
            #"{"type":"user","isSidechain":true,"cwd":"/Users/me/Code/Pulse","message":{"role":"user","content":"explore the card"}}"#,
            Self.reply("a1", at: "10:20", input: 200, output: 20, sidechain: true),
            Self.reply("p1", at: "10:00", input: 100, output: 10, sidechain: true),
        ], to: project.appending(path: "\(uuid)/subagents/agent-a1.jsonl"))
        try Self.write([
            Self.reply("b1", at: "11:05", input: 300, output: 30, sidechain: true),
        ], to: project.appending(path: "\(uuid)/subagents/agent-b1.jsonl"))
        // Another conversation in the same project stays its own row.
        try Self.write([
            #"{"type":"user","cwd":"/Users/me/Code/Pulse","message":{"role":"user","content":"second chat"}}"#,
            Self.reply("o1", at: "12:00", input: 5, output: 5),
        ], to: project.appending(path: "other.jsonl"))

        for pass in 0..<2 {
            // The second pass reads the per-file cache, stamps and all.
            let ledger = await UsageLedgerReader(home: home, cacheDirectory: cache).ledger(for: .claudeCode, prices: [:])
            #expect(ledger.allTime.tokens == 110 + 220 + 330 + 10, "pass \(pass)")

            #expect(ledger.sessions.count == 2)
            let merged = try #require(ledger.sessions.first { $0.name == uuid })
            #expect(merged.id.hasSuffix("/\(uuid).jsonl"))
            #expect(merged.title == "fix the ring")
            #expect(merged.project?.name == "Pulse")
            #expect(merged.tokens == 110 + 220 + 330)
            #expect(merged.slots.count == 3)
            #expect(merged.slots.reduce(0) { $0 + $1.tokens } == merged.tokens)
            // Widened to the earliest and the latest file.
            let span = merged.end.timeIntervalSince(merged.start)
            #expect(span == 60 * 60)
            #expect(ledger.sessions.first { $0.name == "other" }?.tokens == 10)
        }
    }

    @Test("Subagents whose parent file is gone still make one session, named for the project folder")
    func subagentsWithoutAParent() async throws {
        let home = Self.temporary("orphans")
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appending(path: ".claude/projects/-Users-me-Code-Pulse")
        let uuid = "11111111-2222-3333-4444-555555555555"
        try Self.write([Self.reply("a", at: "10:00", input: 10, output: 1, sidechain: true)],
                       to: project.appending(path: "\(uuid)/subagents/agent-a.jsonl"))
        try Self.write([Self.reply("b", at: "10:30", input: 20, output: 2, sidechain: true)],
                       to: project.appending(path: "\(uuid)/subagents/agent-b.jsonl"))

        let ledger = await UsageLedgerReader(home: home, cacheDirectory: home.appending(path: "cache"))
            .ledger(for: .claudeCode, prices: [:])
        #expect(ledger.sessions.count == 1)
        #expect(ledger.sessions.first?.tokens == 33)
        #expect(ledger.sessions.first?.name == uuid)
        // The folder of the project, not the `subagents` folder.
        #expect(ledger.sessions.first?.project?.name == "Pulse")
    }

    @Test("Only a Claude Code subagent path is folded")
    func theGroupingRule() {
        #expect(UsageLedgerReader.sessionFile(of: "/h/.claude/projects/-p/abc/subagents/agent-1.jsonl")
            == "/h/.claude/projects/-p/abc.jsonl")
        #expect(UsageLedgerReader.sessionFile(of: "/h/.claude/projects/-p/abc/subagents/workflows/agent-1.jsonl")
            == "/h/.claude/projects/-p/abc.jsonl")
        #expect(UsageLedgerReader.sessionFile(of: "/h/.claude/projects/-p/abc.jsonl") == "/h/.claude/projects/-p/abc.jsonl")
        #expect(UsageLedgerReader.sessionFile(of: "/h/.claude/projects/-p/subagents-notes.jsonl")
            == "/h/.claude/projects/-p/subagents-notes.jsonl")
    }

    // MARK: - Codex titles

    @Test("Context Codex injects is not a title; the user's first words are")
    func codexTitlesSkipInjectedContext() {
        func title(_ text: String) -> String? {
            UsageLedgerReader.codexTitle(in: [["type": "input_text", "text": text]])
        }
        #expect(title("# AGENTS.md instructions for /Users/me/Code/Pulse\n\n<INSTRUCTIONS>\nBe brief.\n</INSTRUCTIONS>") == nil)
        #expect(title("<environment_context>\n  <cwd>/Users/me</cwd>\n</environment_context>") == nil)
        #expect(title("<user_instructions>be brief</user_instructions>") == nil)
        #expect(title("<turn_aborted>The user interrupted</turn_aborted>") == nil)
        #expect(title("<recommended_plugins> Here are some") == nil)
        #expect(title("The following is the Codex agent history whose request action you are assessing.") == nil)
        #expect(title("# Files mentioned by the user:\n## a.png: /tmp/a.png") == nil)
        #expect(title("fix the ring") == "fix the ring")
        // The IDE extension puts its context first; the request follows it.
        #expect(title("# Context from my IDE setup:\n\n## Active file: a.swift\n\n## Open tabs:\n- a.swift\n\n## My request for Codex:\nfix the ring")
            == "fix the ring")
        #expect(title("# Context from my IDE setup:\n\n## Open tabs:\n- a.swift") == nil)
        // Only the first part is read: the rest of a review prompt is a transcript.
        #expect(UsageLedgerReader.codexTitle(in: [
            ["type": "input_text", "text": "# AGENTS.md instructions for /x"],
            ["type": "input_text", "text": "something else"],
        ]) == nil)
    }

    @Test("A rollout's title is its first real user message")
    func codexRolloutTitle() async throws {
        func message(_ role: String, _ text: String) throws -> String {
            let object: [String: Any] = [
                "timestamp": "2026-09-20T10:00:00Z", "type": "response_item",
                "payload": ["type": "message", "role": role, "content": [["type": "input_text", "text": text]]],
            ]
            return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        }
        let header = #"{"timestamp":"2026-09-20T10:00:00Z","type":"session_meta","payload":{"id":"s1","cwd":"/work/api"}}"#
        let count = #"{"timestamp":"2026-09-20T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#
        let root = Self.temporary("codex-title")
        defer { try? FileManager.default.removeItem(at: root) }

        let real = root.appending(path: "real.jsonl")
        try Self.write([
            header,
            try message("developer", "<permissions instructions>"),
            try message("user", "# AGENTS.md instructions for /work/api\n\n<INSTRUCTIONS>\nBe brief.\n</INSTRUCTIONS>"),
            try message("user", "<environment_context>\n<cwd>/work/api</cwd>\n</environment_context>"),
            try message("user", "add a retry to the client"),
            try message("user", "and a test"),
            count,
        ], to: real)
        let only = root.appending(path: "only-context.jsonl")
        try Self.write([
            header,
            try message("user", "# AGENTS.md instructions for /work/api"),
            try message("user", "<environment_context></environment_context>"),
            count,
        ], to: only)

        let reader = UsageLedgerReader(home: root, cacheDirectory: root.appending(path: "cache"))
        #expect(await reader.parse(real, provider: .codex).title == "add a retry to the client")
        #expect(await reader.parse(only, provider: .codex).title == nil)
    }

    // MARK: - Scratch folders

    @Test("A tool's scratch folder is no project; a real one under similar names is")
    func scratchFolders() {
        let scratch = [
            "/Users/me/Documents/Codex/2026-10-04/https-gist-githubusercontent-com-me-fe4d",
            "/Users/me/Documents/Codex/2026-10-04/make-a-poster/assets",
            "/Users/me/Documents/deepseek-harness/default-workspace",
            "/Users/me/.dsh/deepseek-harness/default-workspace/",
        ]
        for path in scratch {
            #expect(UsageProject.isScratchDirectory(path), "\(path)")
            #expect(UsageProject(path) == nil, "\(path)")
        }
        let real = [
            "/Users/me/Documents/Codex",
            "/Users/me/Documents/Codex/2026-10-04",
            "/Users/me/Documents/Codex/notes/slug",
            "/Users/me/Documents/Codex/2026-1-04/slug",
            "/Users/me/Documents/Codex/20261004xx/slug",
            "/Users/me/Code/Codex/2026-10-04/slug",
            "/Users/me/Documents/deepseek-harness",
            "/Users/me/Documents/deepseek-harness/my-project",
            "/Users/me/Code/default-workspace",
        ]
        for path in real {
            #expect(!UsageProject.isScratchDirectory(path), "\(path)")
            #expect(UsageProject(path) != nil, "\(path)")
        }
    }

    @Test("A Codex chat in a scratch folder has no project, and neither does one read from an old cache")
    func scratchSessionsHaveNoProject() async throws {
        let home = Self.temporary("scratch")
        defer { try? FileManager.default.removeItem(at: home) }
        let scratch = "/Users/me/Documents/Codex/2026-10-04/some-prompt"
        let rollout = [
            #"{"timestamp":"2026-09-20T10:00:00Z","type":"session_meta","payload":{"id":"s","cwd":"\#(scratch)"}}"#,
            #"{"timestamp":"2026-09-20T10:00:00Z","type":"turn_context","payload":{"model":"m"}}"#,
            #"{"timestamp":"2026-09-20T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#,
        ]
        try Self.write(rollout, to: home.appending(path: ".codex/sessions/2026/09/20/rollout-a.jsonl"))
        let ledger = await UsageLedgerReader(home: home, cacheDirectory: home.appending(path: "cache"))
            .ledger(for: .codex, prices: [:])
        #expect(ledger.sessions.count == 1)
        #expect(ledger.sessions.first?.project == nil)

        // A store kept before the rule: the project is there in the file.
        let ledgerWithProject = AgentUsageLedger.build(
            [AgentUsageRecord(timestamp: Date(timeIntervalSince1970: 1_789_372_800), model: "m",
                              tally: TokenTally(input: 100), sessionID: "s", project: "/work/api")],
            prices: [:], namespace: "dsh"
        )
        #expect(ledgerWithProject.sessions.first?.project?.name == "api")
        let file = home.appending(path: "agent.json")
        AgentCache.save(ledgerWithProject, stamp: .init(source: "s", prices: "p"), for: .dsh, at: file)
        let old = try String(contentsOf: file, encoding: .utf8)
            // JSONEncoder escapes the slashes.
            .replacingOccurrences(of: #"\/work\/api"#, with: #"\/Users\/me\/Documents\/deepseek-harness\/default-workspace"#)
        #expect(old.contains("default-workspace"))
        try old.write(to: file, atomically: true, encoding: .utf8)
        let restored = try #require(AgentCache.load(.dsh, at: file)?.ledger)
        #expect(restored.sessions.count == 1)
        #expect(restored.sessions.first?.project == nil)
    }

    // MARK: - Superseded caches

    @Test("Older numbered caches are superseded; the current ones and everything else are not")
    func supersededFiles() {
        func gone(_ name: String) -> Bool {
            PulseStorage.isSuperseded(name, agentVersion: 10, ledgerVersion: 8)
        }
        for name in [
            "agent-6-dsh.json", "agent-8-antigravityIDE.json", "agent-9-gemini.json",
            "ledger-2-claudeCode.json", "ledger-4-cursor.json", "ledger-7-codex.json",
            "ledger-claudeCode.json", "model-prices-3.json",
        ] {
            #expect(gone(name), "\(name)")
        }
        for name in [
            "agent-10-dsh.json", "agent-11-dsh.json", "ledger-8-claudeCode.json", "ledger-9-codex.json",
            "model-prices-4.json", "model-prices-5.json", "keys.dat", "accounts.dat", "alerts.json",
            "agent-dsh.json", "agent-x-dsh.json", "agent-6-dsh.txt", "Window starter", "Extensions",
        ] {
            #expect(!gone(name), "\(name)")
        }
        // The real versions: nothing the running build writes is ever cleaned.
        #expect(!PulseStorage.isSuperseded("agent-\(AgentCache.version)-dsh.json"))
        #expect(!PulseStorage.isSuperseded("ledger-\(UsageLedgerReader.cacheVersion)-codex.json"))
        #expect(!PulseStorage.isSuperseded("ledger-\(UsageLedgerReader.cacheVersion)-codex.bin"))
        #expect(PulseStorage.isSuperseded("ledger-\(UsageLedgerReader.cacheVersion - 1)-codex.bin"))
        #expect(PulseStorage.isSuperseded("agent-\(AgentCache.version - 1)-dsh.json"))
        // Entries gained the review flag in 9; an 8 never holds it.
        #expect(PulseStorage.isSuperseded("ledger-8-codex.json"))
    }

    // MARK: - Titles that are links

    @Test("A link on the first line is not the title when words follow it")
    func linkOnlyFirstLine() {
        #expect(UsageLedgerReader.title(from: "[https://example.com/a/b/c](https://example.com/a/b/c)\ncheck the proxy rules")
            == "check the proxy rules")
        #expect(UsageLedgerReader.title(from: "[https://example.com/a/b/c]\n\ncheck the proxy rules\nand the logs")
            == "check the proxy rules")
        #expect(UsageLedgerReader.title(from: "https://example.com/a/b/c\n帮我检查一下规则") == "帮我检查一下规则")
        #expect(UsageLedgerReader.title(from: "<https://example.com/a>\nread this") == "read this")
        // A first line of words keeps the whole message on one line, as before.
        #expect(UsageLedgerReader.title(from: "read\nhttps://example.com/a") == "read https://example.com/a")
    }

    @Test("A message that is only a link reads as host/first-segment/…")
    func linkOnlyMessage() {
        #expect(UsageLedgerReader.title(from: "https://gist.example.org/someone/0123456789abcdef0123456789abcdef")
            == "gist.example.org/someone/…")
        #expect(UsageLedgerReader.title(from: "[https://gist.example.org/someone/0123456789abcdef](https://gist.example.org/someone/0123456789abcdef)")
            == "gist.example.org/someone/…")
        #expect(UsageLedgerReader.title(from: "[https://example.com/docs?q=1#top]") == "example.com/docs")
        #expect(UsageLedgerReader.title(from: "https://example.com/docs/") == "example.com/docs")
        #expect(UsageLedgerReader.title(from: "https://example.com") == "example.com")
        #expect(UsageLedgerReader.title(from: "  https://example.com/a/b \n https://example.com/c ") == "example.com/a/…")
    }

    @Test("Markdown links read as their text, and whitespace is collapsed")
    func markdownLinks() {
        #expect(UsageLedgerReader.title(from: "see [the docs](https://example.com/docs) for  details")
            == "see the docs for details")
        #expect(UsageLedgerReader.title(from: "open [https://example.com/x] now") == "open https://example.com/x now")
        #expect(UsageLedgerReader.title(from: "fix\t\tthe   ring\r\nand the card") == "fix the ring and the card")
        #expect(UsageLedgerReader.title(from: "[](https://example.com/x)") == "example.com/x")
        // A link is not an envelope, but a command envelope still is.
        #expect(UsageLedgerReader.title(from: "<command-name>/init</command-name>") == nil)
        // The length limit is the same after cleaning.
        let long = UsageLedgerReader.title(from: "[" + String(repeating: "word ", count: 40) + "](https://example.com)")
        #expect(long?.count == 70)
        #expect(long?.hasSuffix("…") == true)
    }

    // MARK: - Codex review sessions

    private static let reviewOpening = "The following is the Codex agent history whose request action you are assessing."

    private static func codexMessage(_ text: String) throws -> String {
        let object: [String: Any] = [
            "timestamp": "2026-09-20T10:00:00Z", "type": "response_item",
            "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]],
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static let codexCount = #"{"timestamp":"2026-09-20T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#
    private static let codexModel = #"{"timestamp":"2026-09-20T10:00:00Z","type":"turn_context","payload":{"model":"m"}}"#

    @Test("A Codex session that opens with a review request is marked, and keeps no title")
    func codexReviewSessionIsMarked() async throws {
        #expect(UsageLedgerReader.isCodexReview(in: [["type": "input_text", "text": Self.reviewOpening]]))
        #expect(!UsageLedgerReader.isCodexReview(in: [["type": "input_text", "text": "fix the ring"]]))
        #expect(!UsageLedgerReader.isCodexReview(in: "# AGENTS.md instructions for /x"))

        let home = Self.temporary("review")
        defer { try? FileManager.default.removeItem(at: home) }
        let scratch = "/Users/me/Documents/Codex/2026-10-04/some-prompt"
        let header = #"{"timestamp":"2026-09-20T10:00:00Z","type":"session_meta","payload":{"id":"r1","cwd":"\#(scratch)"}}"#
        try Self.write([
            header, Self.codexModel,
            try Self.codexMessage("# AGENTS.md instructions for /work/api"),
            try Self.codexMessage(Self.reviewOpening),
            // Anything after the request is the transcript under review.
            try Self.codexMessage("fix the ring"),
            Self.codexCount,
        ], to: home.appending(path: ".codex/sessions/2026/09/20/rollout-2026-09-20T10-00-00-r1.jsonl"))
        try Self.write([
            #"{"timestamp":"2026-09-20T11:00:00Z","type":"session_meta","payload":{"id":"n1","cwd":"/work/api"}}"#,
            Self.codexModel,
            try Self.codexMessage("add a retry"),
            Self.codexCount.replacingOccurrences(of: "10:00:00", with: "11:00:00"),
        ], to: home.appending(path: ".codex/sessions/2026/09/20/rollout-2026-09-20T11-00-00-n1.jsonl"))

        let cache = home.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        // Read fresh, and again from the cache it wrote: the flag travels.
        for pass in 0..<2 {
            let ledger = await UsageLedgerReader(home: home, cacheDirectory: cache).ledger(for: .codex, prices: [:])
            let review = try #require(ledger.sessions.first { $0.name.hasSuffix("r1") }, "pass \(pass)")
            #expect(review.isReview)
            #expect(review.title == nil)
            #expect(review.project == nil)
            let ordinary = try #require(ledger.sessions.first { $0.name.hasSuffix("n1") })
            #expect(!ordinary.isReview)
            #expect(ordinary.title == "add a retry")
        }
        #expect(FileManager.default.fileExists(atPath: cache.appending(path: "ledger-9-codex.bin").path))
    }

    // MARK: - What a row says

    @Test("A session is never named for its file")
    func sessionLabels() {
        #expect(SessionLabel.text(title: "Fix the ring", isReview: false, project: "Pulse") == "Fix the ring")
        #expect(SessionLabel.text(title: nil, isReview: false, project: "Pulse") == "Pulse")
        #expect(SessionLabel.text(title: nil, isReview: true, project: nil) == String.localized("Codex review"))
        #expect(SessionLabel.text(title: nil, isReview: false, project: nil) == String.localized("Untitled conversation"))

        let untitled = UsageLedger.Session(
            id: "/h/.codex/sessions/rollout-2026-10-04T20-42-25-01a106ef.jsonl",
            name: "rollout-2026-10-04T20-42-25-01a106ef", title: nil, project: nil,
            start: Date(timeIntervalSince1970: 1_789_372_800), end: Date(timeIntervalSince1970: 1_789_372_900),
            tokens: 10, cost: 0
        )
        #expect(untitled.label(projectName: nil) == String.localized("Untitled conversation"))
        #expect(!untitled.label(projectName: nil).contains("rollout"))
        #expect(!untitled.namesItself())
        // The project is the label here, so a subtitle must not repeat it.
        #expect(untitled.label(projectName: "Pulse") == "Pulse")

        var review = untitled
        review = UsageLedger.Session(
            id: untitled.id, name: untitled.name, title: nil, isReview: true, project: nil,
            start: untitled.start, end: untitled.end, tokens: 10, cost: 0
        )
        #expect(review.label(projectName: nil) == String.localized("Codex review"))
        #expect(review.namesItself())

        // The prompt-cache lists read through the same rule.
        let lapse = PromptCacheLapse(lastRequest: .now, lifetime: PromptCacheLapse.hour)
        #expect(PromptCacheSession(id: "a", title: nil, project: nil, lapse: lapse).displayName
            == String.localized("Untitled conversation"))
    }

    @Test("The summary's session rows keep the review flag")
    func summaryKeepsReviewFlag() {
        let day = Date(timeIntervalSince1970: 1_789_372_800)
        var ledger = UsageLedger.empty
        ledger.sessions = [UsageLedger.Session(
            id: "a", name: "rollout-a", title: nil, isReview: true, project: nil,
            start: day, end: day, tokens: 10, cost: 0
        )]
        let kept = SpendSummary.Session(agent: .codex, session: ledger.sessions[0])
        #expect(kept.session.isReview)
    }
}
