import Foundation
import Testing
@testable import Pulse

/// Codex's last model call, timed for the card (#126). The records are shaped
/// like a Codex 0.9x rollout: a call's output items, its `token_usage_record`
/// as it ends, then the tool's result and a `token_count` once the tool ran.
@Suite("Codex last step speed")
struct CodexStepTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private static func line(_ seconds: TimeInterval, _ type: String, payload: [String: Any] = [:]) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let record: [String: Any] = [
            "timestamp": formatter.string(from: base.addingTimeInterval(seconds)),
            "type": type,
            "payload": payload,
        ]
        return try! JSONSerialization.data(withJSONObject: record)
    }

    private static func event(_ seconds: TimeInterval, _ kind: String) -> Data {
        line(seconds, kind == "custom_tool_call_output" || kind == "function_call_output" || kind == "custom_tool_call"
             ? "response_item" : "event_msg", payload: ["type": kind])
    }

    private static func usage(_ seconds: TimeInterval, output: Int) -> Data {
        line(seconds, "token_usage_record", payload: ["usage": ["output_tokens": output, "reasoning_output_tokens": 100]])
    }

    @Test("Timed from the tool result that handed the model its move to the usage record")
    func timedCall() throws {
        let step = try #require(AgentActivity.codexStep(in: [
            Self.event(0, "task_started"),
            Self.event(2, "custom_tool_call"),
            Self.usage(2.05, output: 120),
            Self.event(4, "custom_tool_call_output"),
            Self.event(4.001, "token_count"),
            Self.event(25.9, "custom_tool_call"),
            Self.usage(26, output: 1_100),
            Self.event(27, "custom_tool_call_output"),
        ]))
        #expect(step.outputTokens == 1_100)
        #expect(abs(step.duration - 21.999) < 0.01)
        #expect(step.finishedAt == Self.base.addingTimeInterval(26))
        #expect(Int(step.tokensPerSecond.rounded()) == 50)
    }

    @Test("A short call is passed over for the last one long enough to time")
    func shortCallSkipped() throws {
        let step = try #require(AgentActivity.codexStep(in: [
            Self.event(0, "task_started"),
            Self.usage(10, output: 400),
            Self.event(11, "function_call_output"),
            Self.usage(12, output: 30),
        ]))
        #expect(step.outputTokens == 400)
        #expect(step.finishedAt == Self.base.addingTimeInterval(10))
    }

    @Test("No call, or no start in the tail, is no step")
    func nothingToTime() {
        #expect(AgentActivity.codexStep(in: []) == nil)
        #expect(AgentActivity.codexStep(in: [Self.event(0, "task_started"), Self.event(1, "custom_tool_call")]) == nil)
        // The tail began mid-call: the record that started it is cut off.
        #expect(AgentActivity.codexStep(in: [Self.event(0, "custom_tool_call"), Self.usage(1, output: 900)]) == nil)
    }

    @Test("The newest step across sessions reaches the state, even from a file too old to be working")
    func stateCarriesStep() throws {
        let home = try EditorTestSupport.temporary("codex-step")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".codex/sessions/2026/11/27/rollout-a.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = Data()
        for line in [Self.event(0, "task_started"), Self.usage(20, output: 1_000)] { text += line + Data("\n".utf8) }
        try text.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Self.base.addingTimeInterval(20)], ofItemAtPath: file.path)

        let later = Self.base.addingTimeInterval(20 + 10 * 60)
        let state = try #require(AgentActivity.states(for: [.codex], now: later, home: home)[.codex])
        #expect(state.isWorking == false)
        #expect(state.lastStep?.outputTokens == 1_000)
        #expect(state.lastStep?.finishedAt == Self.base.addingTimeInterval(20))
    }

    @Test("An older session's step outlives five minutes when a newer one has none")
    func olderSessionKeepsItsStep() throws {
        let home = try EditorTestSupport.temporary("codex-step-two")
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: ".codex/sessions/2026/11/27")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ name: String, _ lines: [Data], modified: Date) throws {
            var text = Data()
            for line in lines { text += line + Data("\n".utf8) }
            let file = folder.appending(path: name)
            try text.write(to: file)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        }
        try write("rollout-old.jsonl", [Self.event(0, "task_started"), Self.usage(20, output: 1_000)],
                  modified: Self.base.addingTimeInterval(20))
        try write("rollout-new.jsonl", [Self.event(30, "task_started")], modified: Self.base.addingTimeInterval(30))

        for elapsed: TimeInterval in [299, 301, 50 * 60] {
            let state = AgentActivity.states(for: [.codex], now: Self.base.addingTimeInterval(20 + elapsed), home: home)[.codex]
            #expect(state?.lastStep?.outputTokens == 1_000, "at \(elapsed) s")
        }
    }
}
