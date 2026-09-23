import Foundation
import Testing
@testable import Pulse

/// What a transcript says about itself: what the conversation was called, and
/// where it ran.
@Suite("Session titles")
struct SessionTitleTests {
    @Test("A title is one line of the opening prompt")
    func titlesAreCutToOneLine() {
        #expect(UsageLedgerReader.title(from: "  Fix the ring  ") == "Fix the ring")
        // Newlines would turn a row into a paragraph.
        #expect(UsageLedgerReader.title(from: "Fix the ring\nand the card") == "Fix the ring and the card")

        let long = String(repeating: "长", count: 200)
        let cut = UsageLedgerReader.title(from: long)
        #expect(cut?.count == 70)
        #expect(cut?.hasSuffix("…") == true)
    }

    @Test("An envelope is not a title")
    func envelopesAreRefused() {
        // Claude Code opens plenty of sessions with a command envelope or the
        // sandbox caveat. Either would title every session the same thing.
        #expect(UsageLedgerReader.title(from: "<command-name>/init</command-name>") == nil)
        #expect(UsageLedgerReader.title(from: "Caveat: The messages below were generated…") == nil)
        #expect(UsageLedgerReader.title(from: "   ") == nil)
        #expect(UsageLedgerReader.title(from: "") == nil)
    }

    @Test("A message body is a string, or a list of typed parts")
    func bodiesComeInTwoShapes() {
        #expect(UsageLedgerReader.text(in: "plain") == "plain")
        #expect(UsageLedgerReader.text(in: [["type": "text", "text": "rich"]]) == "rich")
        // A tool result carries no text of its own and must not stop the
        // search at the first part.
        #expect(UsageLedgerReader.text(in: [["type": "tool_result"], ["type": "text", "text": "after"]]) == "after")
        #expect(UsageLedgerReader.text(in: [["type": "tool_result"]]) == nil)
        #expect(UsageLedgerReader.text(in: nil) == nil)
    }

    @Test("The folder name is only the fallback for a missing directory")
    func folderNamesAreTheLastResort() {
        // Claude Code replaces every separator with a dash, so the folder name
        // cannot be turned back into a path — the stated `cwd` is preferred
        // wherever a transcript has one, and this is what is left when it does
        // not.
        let claude = URL(fileURLWithPath: "/Users/me/.claude/projects/-Users-me-Code-Pulse/abc.jsonl")
        #expect(UsageLedgerReader.project(of: claude, provider: .claudeCode)?.name == "Pulse")

        let codex = URL(fileURLWithPath: "/Users/me/.codex/sessions/2026/09/14/rollout-x.jsonl")
        #expect(UsageLedgerReader.project(of: codex, provider: .codex) == nil)
    }

    // MARK: - The title the user set

    /// These drive the real `parseClaudeCode` over a transcript built by hand,
    /// never the user's `~/.claude`, and never the `title(from:)` string helper
    /// alone — the bug this covers lived in the line loop's own gating, which
    /// a helper test cannot see.
    private static func transcript(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").utf8)
    }

    private static let opening =
        #"{"type":"user","cwd":"/Users/me/Code/Pulse","message":{"role":"user","content":"fix the ring"}}"#

    @Test("A title set after the opening prompt is not ignored")
    func aCustomTitleAfterThePromptIsRead() async {
        // Claude Code writes `customTitle` on its own line when a conversation
        // is renamed, long after `cwd` and the opening prompt were read. The
        // old parser stopped looking once both were set, so every rename was
        // lost.
        let scanned = await UsageLedgerReader.shared.parseClaudeCode(
            Self.transcript([
                Self.opening,
                #"{"type":"custom-title","customTitle":"Renamed by hand"}"#,
            ])
        )
        #expect(scanned.title == "Renamed by hand")
        #expect(scanned.cwd == "/Users/me/Code/Pulse")
    }

    @Test("The last valid custom title wins")
    func theLastCustomTitleWins() async {
        let scanned = await UsageLedgerReader.shared.parseClaudeCode(
            Self.transcript([
                Self.opening,
                #"{"customTitle":"First name"}"#,
                #"{"customTitle":"Second name"}"#,
            ])
        )
        #expect(scanned.title == "Second name")
    }

    @Test("An unreadable custom title leaves the valid one alone")
    func anInvalidCustomTitleDoesNotClear() async {
        // A rename to an empty string is not a reason to forget the name that
        // was set a moment ago.
        let scanned = await UsageLedgerReader.shared.parseClaudeCode(
            Self.transcript([
                Self.opening,
                #"{"customTitle":"A real name"}"#,
                #"{"customTitle":""}"#,
            ])
        )
        #expect(scanned.title == "A real name")
    }

    @Test("A custom title still outranks an opening prompt that comes after it")
    func aCustomTitleOutranksALaterPrompt() async {
        let scanned = await UsageLedgerReader.shared.parseClaudeCode(
            Self.transcript([
                #"{"type":"custom-title","customTitle":"Chosen first"}"#,
                Self.opening,
            ])
        )
        #expect(scanned.title == "Chosen first")
    }

    @Test("Reading a custom title does not change the token counts")
    func aCustomTitleLeavesTheCountsAlone() async {
        // The rename handling shares the loop with the usage parsing; this is
        // the guard that it does not disturb it.
        let scanned = await UsageLedgerReader.shared.parseClaudeCode(
            Self.transcript([
                Self.opening,
                #"{"type":"assistant","timestamp":"2026-09-14T10:00:00Z","message":{"id":"m1","model":"claude-sonnet-4-5","usage":{"input_tokens":100,"output_tokens":10}}}"#,
                #"{"customTitle":"Renamed"}"#,
            ])
        )
        #expect(scanned.title == "Renamed")
        // Aggregate every bucket rather than trusting a random `.first`, so
        // the assertion is about the whole transcript's counts.
        let tallies = scanned.days.values.flatMap { $0.values }
        #expect(tallies.reduce(0) { $0 + $1.input } == 100)
        #expect(tallies.reduce(0) { $0 + $1.output } == 10)
        #expect(tallies.reduce(0) { $0 + $1.total } == 110)
    }
}
