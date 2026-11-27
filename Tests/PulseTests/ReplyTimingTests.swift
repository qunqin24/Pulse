import Foundation
import Testing
@testable import Pulse

/// Output speed and first-token wait, read from transcripts built by hand —
/// never from the user's own `~/.claude` or `~/.codex`.
@Suite("Reply timing")
struct ReplyTimingTests {
    private static func claudeLine(_ type: String, _ time: String, id: String? = nil, output: Int = 0) -> String {
        guard type == "assistant", let id else {
            return #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"{\"type\":\"user\",\"timestamp\":\"2000-01-01T00:00:00Z\"}"}]},"timestamp":"\#(time)"}"#
        }
        return #"{"type":"assistant","message":{"id":"\#(id)","model":"claude-test","usage":{"input_tokens":10,"cache_read_input_tokens":90,"output_tokens":\#(output)}},"timestamp":"\#(time)"}"#
    }

    @Test("A reply over several lines counts its last line's output, timed from the request to its last line")
    func claudeCodeReply() async {
        let lines = [
            Self.claudeLine("user", "2026-09-20T10:00:00.000Z"),
            Self.claudeLine("assistant", "2026-09-20T10:00:04.000Z", id: "a", output: 12),
            Self.claudeLine("assistant", "2026-09-20T10:00:10.000Z", id: "a", output: 500),
            // A tool result between two lines of the next reply's request does
            // not start the clock before this reply ended.
            Self.claudeLine("user", "2026-09-20T10:00:09.000Z"),
            Self.claudeLine("assistant", "2026-09-20T10:00:20.000Z", id: "b", output: 300),
            // Too short to stand for a speed, still counted as tokens.
            Self.claudeLine("user", "2026-09-20T10:00:21.000Z"),
            Self.claudeLine("assistant", "2026-09-20T10:00:23.000Z", id: "c", output: 40),
        ]
        let scanned = await UsageLedgerReader(cacheDirectory: URL.temporaryDirectory)
            .parseClaudeCode(Data(lines.joined(separator: "\n").utf8))

        let output = scanned.allDays.values.flatMap(\.values).reduce(0) { $0 + $1.output }
        #expect(output == 500 + 300 + 40)
        let timing = scanned.allTimings.values.flatMap(\.values).reduce(ReplyTiming(), +)
        #expect(timing.replies == 2)
        #expect(timing.outputTokens == 800)
        #expect(abs(timing.seconds - (10 + 10)) < 0.001)
        #expect(timing.firstTokenTurns == 0)
    }

    @Test("Claude Code's first token is dated by how long a reply's opening thinking or tool call streamed")
    func claudeCodeFirstToken() async {
        func opening(_ time: String, id: String, field: String?, ms: Int, output: Int) -> String {
            let extra = field.map { #","\#($0)":\#(ms)"# } ?? ""
            return #"{"type":"assistant","message":{"id":"\#(id)","model":"claude-test","usage":{"input_tokens":10,"output_tokens":\#(output)}},"timestamp":"\#(time)"\#(extra)}"#
        }
        let lines = [
            Self.claudeLine("user", "2026-09-20T10:00:00.000Z"),
            // Thought for 4 s, done at 5.5 s: the first token came at 1.5 s.
            opening("2026-09-20T10:00:05.500Z", id: "a", field: "thinkingDurationMs", ms: 4_000, output: 20),
            Self.claudeLine("assistant", "2026-09-20T10:00:10.000Z", id: "a", output: 500),
            Self.claudeLine("user", "2026-09-20T10:00:11.000Z"),
            // A tool call that streamed 2 s, done at 14 s: first token at 1 s.
            opening("2026-09-20T10:00:14.000Z", id: "b", field: "toolInputStreamMs", ms: 2_000, output: 50),
            Self.claudeLine("user", "2026-09-20T10:00:15.000Z"),
            // Opens with text: no figure, no wait.
            opening("2026-09-20T10:00:18.000Z", id: "c", field: nil, ms: 0, output: 300),
            Self.claudeLine("user", "2026-09-20T10:00:19.000Z"),
            // A streaming time longer than the gap: not this reply's request.
            opening("2026-09-20T10:00:20.000Z", id: "d", field: "thinkingDurationMs", ms: 9_000, output: 10),
        ]
        let scanned = await UsageLedgerReader(cacheDirectory: URL.temporaryDirectory)
            .parseClaudeCode(Data(lines.joined(separator: "\n").utf8))
        let timing = scanned.allTimings.values.flatMap(\.values).reduce(ReplyTiming(), +)
        #expect(timing.firstTokenTurns == 2)
        #expect(abs(timing.firstTokenSeconds - (1.5 + 1)) < 0.001)
        // The speed is unchanged: "a" and "c" were long enough to time.
        #expect(timing.replies == 2)
    }

    @Test("A reply copied into a resumed session's transcript is counted once, for the original")
    func resumedCopiesCountOnce() async throws {
        let root = URL.temporaryDirectory.appending(path: "PulseResumed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: ".claude/projects/-Users-me-Code-Pulse")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let history = [
            Self.claudeLine("user", "2026-09-20T10:00:00.000Z"),
            Self.claudeLine("assistant", "2026-09-20T10:00:10.000Z", id: "a", output: 500),
        ]
        // The original, then a resumed session: the same history, then its own reply.
        try history.joined(separator: "\n").write(to: folder.appending(path: "original.jsonl"), atomically: true, encoding: .utf8)
        try (history + [
            Self.claudeLine("user", "2026-09-21T09:00:00.000Z"),
            Self.claudeLine("assistant", "2026-09-21T09:00:05.000Z", id: "b", output: 300),
        ]).joined(separator: "\n").write(to: folder.appending(path: "resumed.jsonl"), atomically: true, encoding: .utf8)

        let cache = root.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let ledger = await UsageLedgerReader(home: root, cacheDirectory: cache)
            .ledger(for: .claudeCode, refresh: true, prices: [:])
        let output = ledger.days.reduce(0) { $0 + $1.tally.output }
        #expect(output == 500 + 300)
        let sessions = Dictionary(uniqueKeysWithValues: ledger.sessions.map { ($0.name, $0.tokens) })
        #expect(sessions["original"] == 10 + 90 + 500)
        #expect(sessions["resumed"] == 10 + 90 + 300)
    }

    @Test("Codex pairs a late count with the reply before the request that preceded it, and keeps its first-token wait")
    func codexReply() async throws {
        func line(_ time: String, _ payload: String, type: String = "response_item") -> String {
            #"{"timestamp":"\#(time)","type":"\#(type)","payload":\#(payload)}"#
        }
        let lines = [
            line("2026-09-20T10:00:00.000Z", #"{"model":"gpt-test"}"#, type: "turn_context"),
            line("2026-09-20T10:00:00.000Z", #"{"type":"message","role":"user","content":[{"type":"input_text","text":"hi"}]}"#),
            line("2026-09-20T10:00:03.000Z", #"{"type":"reasoning"}"#),
            line("2026-09-20T10:00:05.000Z", #"{"type":"function_call","name":"shell"}"#),
            // The tool runs, its output goes back — and only then the count.
            line("2026-09-20T10:00:30.000Z", #"{"type":"function_call_output","output":"x"}"#),
            line("2026-09-20T10:00:30.001Z", #"{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":900,"output_tokens":400}}}"#, type: "event_msg"),
            line("2026-09-20T10:00:34.000Z", #"{"type":"message","role":"assistant","content":[]}"#),
            line("2026-09-20T10:00:34.001Z", #"{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"cached_input_tokens":1900,"output_tokens":600}}}"#, type: "event_msg"),
            line("2026-09-20T10:00:34.002Z", #"{"type":"task_complete","duration_ms":34000,"time_to_first_token_ms":2500}"#, type: "event_msg"),
        ]
        let file = URL.temporaryDirectory.appending(path: "PulseReplyTiming-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let scanned = await UsageLedgerReader(cacheDirectory: URL.temporaryDirectory).parse(file, provider: .codex)
        let timing = scanned.timings.values.flatMap(\.values).reduce(ReplyTiming(), +)
        // 400 over 0:00 → 0:05, 200 over 0:30 → 0:34.
        #expect(timing.replies == 2)
        #expect(timing.outputTokens == 600)
        #expect(abs(timing.seconds - 9) < 0.001)
        #expect(timing.firstTokenTurns == 1)
        #expect(timing.firstTokenSeconds == 2.5)
    }

    @Test("Speeds and waits need five timed replies or turns per model, within the last day")
    func perModel() {
        let now = Date()
        func slot(_ ago: TimeInterval, _ timings: [String: ReplyTiming]) -> UsageLedger.Slot {
            UsageLedger.Slot(start: now.addingTimeInterval(-ago), tokens: 1, cost: 0, timings: timings)
        }
        let ledger = UsageLedger(
            days: [], earliest: nil, unpricedModels: [], modelNames: ["fast": "Fast"],
            slots: [
                // Two days old: a speed for a server that has moved on.
                slot(2 * 86_400, ["fast": ReplyTiming(outputTokens: 100_000, seconds: 10, replies: 50)]),
                slot(3_600, [
                    "fast": ReplyTiming(outputTokens: 1_000, seconds: 10, replies: 5),
                    "rare": ReplyTiming(outputTokens: 5_000, seconds: 10, replies: 4),
                    "codex": ReplyTiming(outputTokens: 600, seconds: 20, replies: 6, firstTokenSeconds: 15, firstTokenTurns: 5),
                ]),
            ]
        )
        let speeds = ledger.outputSpeedsByModel(since: now.addingTimeInterval(-UsageLedger.speedSpan))
        #expect(speeds.map(\.name) == ["Fast", "codex"])
        #expect(speeds[0].tokensPerSecond == 100)
        #expect(speeds[0].firstToken == nil)
        #expect(speeds[1].tokensPerSecond == 30)
        #expect(speeds[1].firstToken == 3)
        #expect(ledger.outputSpeedsByModel(since: now).isEmpty)
    }

    @Test("A wait or reply outside the plausible range is not timed")
    func bounds() {
        let start = Date()
        #expect(ReplyTiming(output: 99, from: start, to: start.addingTimeInterval(1)) == nil)
        #expect(ReplyTiming(output: 500, from: start, to: start) == nil)
        #expect(ReplyTiming(output: 500, from: start, to: start.addingTimeInterval(ReplyTiming.longest + 1)) == nil)
        #expect(ReplyTiming.firstToken(after: 0) == nil)
        #expect(ReplyTiming.firstToken(after: ReplyTiming.longestFirstToken + 1) == nil)
    }
}
