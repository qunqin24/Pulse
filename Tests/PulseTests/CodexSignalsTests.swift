import Foundation
import Testing
@testable import Pulse

/// Signs of a weaker model in Codex's sessions: reasoning stopped on the
/// 518·n − 2 lattice, and settings that changed under a turn. Synthetic
/// sessions in the shape Codex writes — field names only, no transcript.
@Suite("Codex signs")
struct CodexSignalsTests {
    fileprivate static func line(_ type: String, _ payload: String, at seconds: Int = 0) -> String {
        let stamp = Date(timeIntervalSince1970: 1_790_000_000 + Double(seconds))
            .formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        return #"{"timestamp":"\#(stamp)","type":"\#(type)","payload":\#(payload)}"#
    }

    private static func meta(_ version: String) -> String {
        line("session_meta", #"{"id":"s","cli_version":"\#(version)"}"#)
    }

    private static func started(_ turn: String, root: String? = nil, at t: Int) -> String {
        line("event_msg", #"{"type":"task_started","turn_id":"\#(turn)","root_turn_id":"\#(root ?? turn)"}"#, at: t)
    }

    private static func context(_ turn: String, model: String, effort: String = "high", at t: Int) -> String {
        line("turn_context", #"{"turn_id":"\#(turn)","model":"\#(model)","effort":"\#(effort)"}"#, at: t)
    }

    private static func applied(model: String, effort: String = "high", at t: Int) -> String {
        line("event_msg", #"{"type":"thread_settings_applied","thread_settings":{"model":"\#(model)","reasoning_effort":"\#(effort)"}}"#, at: t)
    }

    /// A response's counts; `total` is the running total that tells repeats apart.
    private static func count(reasoning: Int, total: Int, window: Int = 272_000, at t: Int) -> String {
        line("event_msg", #"{"type":"token_count","info":{"model_context_window":\#(window),"last_token_usage":{"input_tokens":10,"output_tokens":\#(reasoning + 5),"reasoning_output_tokens":\#(reasoning)},"total_token_usage":{"input_tokens":\#(total),"output_tokens":\#(total),"reasoning_output_tokens":\#(total),"total_tokens":\#(total)}}}"#, at: t)
    }

    private static func parse(_ lines: [String]) -> CodexSignalReader.FileFacts {
        CodexSignalReader.parse(LogLines(data: Data(lines.joined(separator: "\n").utf8)), session: "s")
    }

    @Test("The lattice is 516, 1034, 1552 … and nothing between")
    func lattice() {
        #expect(CodexSignals.isOnLattice(516))
        #expect(CodexSignals.isOnLattice(1_034))
        #expect(CodexSignals.isOnLattice(1_552))
        #expect(!CodexSignals.isOnLattice(514))
        #expect(!CodexSignals.isOnLattice(517))
        #expect(!CodexSignals.isOnLattice(1_036))
    }

    @Test("Each response counted once, under the model in force; a repeated count is not another")
    func responses() {
        let facts = Self.parse([
            Self.meta("0.120.0"),
            Self.context("a", model: "gpt-5.5", at: 1),
            Self.count(reasoning: 516, total: 100, at: 2),
            Self.count(reasoning: 516, total: 100, at: 3),
            Self.count(reasoning: 0, total: 150, at: 4),
            Self.context("b", model: "gpt-5.3-codex", at: 5),
            Self.count(reasoning: 700, total: 200, at: 6),
        ])
        #expect(facts.responses.map(\.model) == ["gpt-5.5", "gpt-5.3-codex"])
        #expect(facts.responses.map(\.reasoning) == [516, 700])
        #expect(!facts.isJudged)
        #expect(facts.changes.isEmpty)
    }

    @Test("A turn that ran on another model or less effort than was set is a change; the user's own is not")
    func changes() {
        let facts = Self.parse([
            Self.meta("0.146.0-alpha.3"),
            Self.started("t1", at: 1), Self.context("t1", model: "gpt-6-astra", at: 1),
            Self.applied(model: "gpt-6-astra", at: 2),
            // Run on another model with nothing applied.
            Self.started("t2", at: 3), Self.context("t2", model: "gpt-5.6-luna", at: 3),
            // The user switches to sol and down to medium: not a change.
            Self.applied(model: "gpt-6-sol", effort: "medium", at: 4),
            Self.started("t3", at: 5), Self.context("t3", model: "gpt-6-sol", effort: "medium", at: 5),
            // Effort lowered under the turn.
            Self.started("t4", at: 6), Self.context("t4", model: "gpt-6-sol", effort: "low", at: 6),
            // A sub-agent's turn on its own model is Codex's business.
            Self.started("t5", root: "t4", at: 7), Self.context("t5", model: "gpt-5.6-luna", at: 7),
        ])
        #expect(facts.isJudged)
        #expect(facts.changes.map(\.kind) == [
            .model(asked: "gpt-6-astra", ran: "gpt-5.6-luna"),
            .effort(asked: "medium", ran: "low"),
        ])
    }

    @Test("A setting applied while a turn runs takes effect at the next turn, not that one")
    func appliedMidTurn() {
        let facts = Self.parse([
            Self.meta("0.146.0"),
            Self.started("t1", at: 1), Self.applied(model: "gpt-6-sol", effort: "medium", at: 1),
            Self.context("t1", model: "gpt-6-sol", effort: "medium", at: 1),
            Self.started("t2", at: 2), Self.applied(model: "gpt-6-sol", effort: "high", at: 3),
            Self.context("t2", model: "gpt-6-sol", effort: "medium", at: 3),
            Self.started("t3", at: 4), Self.context("t3", model: "gpt-6-sol", effort: "high", at: 4),
        ])
        #expect(facts.changes.isEmpty)
    }

    @Test("Codex before 0.144 writes no user changes, so its sessions are not judged")
    func olderSessions() {
        let facts = Self.parse([
            Self.meta("0.119.0-alpha.28"),
            Self.started("t1", at: 1), Self.context("t1", model: "gpt-5.4", at: 1),
            Self.started("t2", at: 2), Self.context("t2", model: "gpt-5.4-mini", at: 2),
        ])
        #expect(!facts.isJudged)
        #expect(facts.changes.isEmpty)
    }

    @Test("Effort is ranked through max and ultra; a level Codex added is compared, not skipped")
    func topEfforts() {
        let facts = Self.parse([
            Self.meta("0.162.1"),
            Self.started("t1", at: 1), Self.applied(model: "gpt-6-astra", effort: "ultra", at: 1),
            Self.context("t1", model: "gpt-6-astra", effort: "ultra", at: 1),
            // Lowered under the turn: ultra to max, then max to xhigh.
            Self.started("t2", at: 2), Self.context("t2", model: "gpt-6-astra", effort: "max", at: 2),
            Self.applied(model: "gpt-6-astra", effort: "max", at: 3),
            Self.started("t3", at: 4), Self.context("t3", model: "gpt-6-astra", effort: "xhigh", at: 4),
            // The user raises it to ultra: not a change.
            Self.applied(model: "gpt-6-astra", effort: "ultra", at: 5),
            Self.started("t4", at: 6), Self.context("t4", model: "gpt-6-astra", effort: "ultra", at: 6),
        ])
        #expect(facts.changes.map(\.kind) == [
            .effort(asked: "ultra", ran: "max"),
            .effort(asked: "max", ran: "xhigh"),
        ])
    }

    @Test("A smaller context window is Codex's own sum from config, not a change")
    func contextWindow() {
        let facts = Self.parse([
            Self.meta("0.146.0"),
            Self.started("t1", at: 1), Self.applied(model: "gpt-6-sol", at: 1),
            Self.context("t1", model: "gpt-6-sol", at: 1),
            // 872,000 × 95%, then 300,000 × 95% after `model_context_window` was edited.
            Self.count(reasoning: 10, total: 10, window: 828_400, at: 2),
            Self.count(reasoning: 10, total: 20, window: 285_000, at: 3),
        ])
        #expect(facts.isJudged)
        #expect(facts.changes.isEmpty)
    }

    @Test("Per model, the share of long replies on the lattice; a few is too few, many is a sign")
    func truncation() async throws {
        let root = URL.temporaryDirectory.appending(path: "PulseCodexSigns-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appending(path: "2026/10/01")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)

        var lines = [Self.meta("0.146.0"), Self.context("a", model: "gpt-5.5", at: 1)]
        var total = 0
        // 30 long replies, 12 of them on the lattice; plus short ones.
        for index in 0..<30 {
            total += 1_000
            lines.append(Self.count(reasoning: index < 12 ? 516 : 600 + index, total: total, at: 10 + index))
        }
        for index in 0..<5 {
            total += 1_000
            lines.append(Self.count(reasoning: 40, total: total, at: 100 + index))
        }
        lines.append(Self.context("b", model: "gpt-5.3-codex", at: 200))
        for index in 0..<3 {
            total += 1_000
            lines.append(Self.count(reasoning: 516, total: total, at: 201 + index))
        }
        try lines.joined(separator: "\n").write(to: day.appending(path: "rollout-x.jsonl"), atomically: true, encoding: .utf8)

        let signals = await CodexSignalReader(roots: [root]).read(since: nil)
        let five = try #require(signals.truncation.first { $0.model == "gpt-5.5" })
        #expect(five.responses == 35)
        #expect(five.reachedLattice == 30)
        #expect(five.onLattice == 12)
        #expect(five.isSuspicious)
        let codex = try #require(signals.truncation.first { $0.model == "gpt-5.3-codex" })
        #expect(!codex.isMeasurable)
        #expect(!codex.isSuspicious)
        #expect(signals.truncation.first?.model == "gpt-5.5")
        #expect(signals.sessions == 1)
    }

    @Test("A session with no settings on record, or one of Codex's helpers, is not judged")
    func unjudged() {
        let swap = [
            Self.started("t1", at: 1), Self.context("t1", model: "gpt-6-sol", at: 1),
            Self.started("t2", at: 2), Self.context("t2", model: "gpt-5.6-luna", at: 2),
        ]
        let none = Self.parse([Self.meta("0.146.0")] + swap)
        #expect(!none.isJudged)
        #expect(none.changes.isEmpty)
        let helper = Self.parse([
            Self.line("session_meta", #"{"id":"s","cli_version":"0.146.0","source":{"subagent":{"other":"guardian"}}}"#),
            Self.applied(model: "gpt-6-sol", at: 0),
        ] + swap)
        #expect(!helper.isJudged)
        #expect(helper.changes.isEmpty)
    }

    @Test("A fork's copy of its parent is skipped; its own work after the copy counts")
    func forkReplay() {
        let facts = Self.parse([
            Self.line("session_meta", #"{"id":"f","cli_version":"0.146.0","forked_from_id":"p"}"#, at: 100),
            // The parent's history, copied at the moment of the fork.
            Self.context("old", model: "gpt-5.5", at: 100),
            Self.count(reasoning: 516, total: 1_000, at: 100),
            Self.count(reasoning: 516, total: 2_000, at: 101),
            // The fork's own turn.
            Self.started("new", at: 160), Self.applied(model: "gpt-6-sol", at: 160),
            Self.context("new", model: "gpt-6-sol", at: 160),
            Self.count(reasoning: 700, total: 3_000, at: 170),
        ])
        #expect(facts.responses.map(\.model) == ["gpt-6-sol"])
        #expect(facts.responses.map(\.reasoning) == [700])
        #expect(facts.isJudged)
    }

    @Test("A cancelled read keeps nothing, so the next read sees the whole file")
    func cancelledRead() async throws {
        let root = URL.temporaryDirectory.appending(path: "PulseCodexCancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var lines = [Self.meta("0.120.0"), Self.context("a", model: "gpt-5.5", at: 1)]
        for index in 0..<50 { lines.append(Self.count(reasoning: 600, total: (index + 1) * 10, at: 2 + index)) }
        try lines.joined(separator: "\n").write(to: root.appending(path: "rollout-a.jsonl"), atomically: true, encoding: .utf8)

        let reader = CodexSignalReader(roots: [root])
        let cancelled = Task { await reader.read(since: nil) }
        cancelled.cancel()
        _ = await cancelled.value
        let whole = await reader.read(since: nil)
        #expect(whole.truncation.first?.responses == 50)
    }

    @Test("Versions read with or without a pre-release tag")
    func versions() {
        #expect(CodexSignalReader.version("0.146.0-alpha.3.1")! == (0, 146, 0))
        #expect(CodexSignalReader.version("0.58.0")! == (0, 58, 0))
        #expect(CodexSignalReader.version("dev") == nil)
    }
}
