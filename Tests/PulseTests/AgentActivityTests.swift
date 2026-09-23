import Foundation
import Testing
@testable import Pulse

@Suite("Agent activity scope")
struct AgentActivityTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The scanner reads only the selected activity providers", arguments: [
        Set<Provider>(), [.deepSeek], [.claudeCode], [.codex], [.kiro], [.claudeCode, .codex]
    ])
    func selectedTranscripts(providers: Set<Provider>) throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let stamp = ISO8601DateFormatter().string(from: Self.now)
        let logs = [
            ".claude/projects/test/session.jsonl":
                "{\"type\":\"user\",\"timestamp\":\"\(stamp)\",\"message\":{\"content\":\"test\"}}\n",
            ".codex/sessions/test/session.jsonl":
                "{\"type\":\"event_msg\",\"timestamp\":\"\(stamp)\",\"payload\":{\"type\":\"task_started\"}}\n",
            ".kiro/sessions/cli/session.jsonl":
                "{\"version\":\"v1\",\"kind\":\"Prompt\",\"data\":{\"content\":\"test\"}}\n"
        ]
        for (path, text) in logs {
            let file = home.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Self.now], ofItemAtPath: file.path)
        }

        let states = AgentActivity.states(for: providers, now: Self.now, home: home)
        #expect(Set(states.keys) == providers.filter(\.supportsLocalActivity))
        #expect(states[.deepSeek] == nil)
        #expect(states.values.allSatisfy { $0.isWorking })
        #expect(states.values.allSatisfy { $0.lastWrite == Self.now })
    }

    @Test("Kiro CLI and ACP session records bracket model and tool work")
    func kiroVerdicts() throws {
        let home = try EditorTestSupport.temporary("kiro-activity")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: "session.jsonl")

        try EditorTestSupport.jsonLines([
            ["version": "v1", "kind": "Prompt", "data": ["content": "review"]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .kiro) == .working(.model, at: nil))

        try EditorTestSupport.jsonLines([
            ["version": "v1", "kind": "AssistantMessage", "data": [
                "content": [["kind": "toolUse", "name": "read"]],
            ]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .kiro) == .working(.tool, at: nil))

        try EditorTestSupport.jsonLines([
            ["version": "v1", "kind": "ToolResults", "data": ["content": []]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .kiro) == .working(.model, at: nil))

        try EditorTestSupport.jsonLines([
            ["version": "v1", "kind": "AssistantMessage", "data": [
                "content": [["kind": "text", "text": "done"]],
            ]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .kiro) == .finished)
    }

    @Test("Kiro Desktop and v2 ACP lifecycle records bracket a turn")
    func kiroV2Verdicts() throws {
        let home = try EditorTestSupport.temporary("kiro-v2-activity")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: "messages.jsonl")
        let stamp = ISO8601DateFormatter().string(from: Self.now)

        try EditorTestSupport.jsonLines([
            ["timestamp": stamp, "payload": ["type": "turn_start", "executionId": "exec-a"]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .kiro) == .working(.model, at: Self.now))

        try EditorTestSupport.jsonLines([
            ["timestamp": stamp, "payload": ["type": "tool_call", "executionId": "exec-a"]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .kiro) == .working(.tool, at: Self.now))

        try EditorTestSupport.jsonLines([
            ["timestamp": stamp, "payload": ["type": "tool_result", "executionId": "exec-a"]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .kiro) == .working(.model, at: Self.now))

        try EditorTestSupport.jsonLines([
            ["timestamp": stamp, "payload": ["type": "turn_end", "executionId": "exec-a"]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .kiro) == .finished)
    }

    @Test("Kiro v2 ignores sub-execution JSONL when the main turn is finished")
    func kiroV2IgnoresSubExecutions() throws {
        let home = try EditorTestSupport.temporary("kiro-v2-sub-execution")
        defer { try? FileManager.default.removeItem(at: home) }
        let session = home.appending(path: ".kiro/sessions/workspace/session")
        let stamp = ISO8601DateFormatter().string(from: Self.now)
        let messages = session.appending(path: "messages.jsonl")
        let sub = session.appending(path: "sub-executions/noise.jsonl")

        try EditorTestSupport.jsonLines([
            ["timestamp": stamp, "payload": ["type": "turn_end", "executionId": "exec-a"]],
        ], to: messages)
        try EditorTestSupport.jsonLines([["status": "complete"]], to: sub)
        for file in [messages, sub] {
            try FileManager.default.setAttributes([.modificationDate: Self.now], ofItemAtPath: file.path)
        }

        let state = try #require(AgentActivity.states(for: [.kiro], now: Self.now, home: home)[.kiro])
        #expect(!state.isWorking)
    }

    @Test("ZCode native and ACP telemetry follows each turn independently")
    func zcodeVerdicts() throws {
        let home = try EditorTestSupport.temporary("zcode-activity")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: "zcode.jsonl")
        let stamp = ISO8601DateFormatter().string(from: Self.now)

        try EditorTestSupport.jsonLines([
            ["event": "turn.started", "timestamp": stamp, "turnId": "turn-a"],
            ["event": "turn.started", "timestamp": stamp, "turnId": "turn-b"],
            ["event": "turn.completed", "timestamp": stamp, "turnId": "turn-b"],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .glmCoding) == .working(.model, at: Self.now))

        try EditorTestSupport.jsonLines([
            ["event": "turn.started", "timestamp": stamp, "turnId": "turn-a"],
            ["event": "tool.call.started", "timestamp": stamp, "turnId": "turn-a"],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .glmCoding) == .working(.tool, at: Self.now))

        try EditorTestSupport.jsonLines([
            ["event": "turn.started", "timestamp": stamp, "turnId": "turn-a"],
            ["event": "turn.completed", "timestamp": stamp, "turnId": "turn-a"],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .glmCoding) == .finished)
    }

    @Test("ZCode background telemetry alone does not mark the GLM ring as working")
    func zcodeHeartbeatIsIdle() throws {
        let home = try EditorTestSupport.temporary("zcode-heartbeat")
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".zcode/cli/config.json")
        let log = home.appending(path: ".zcode/cli/log/zcode-2026-09-23.jsonl")
        let stamp = ISO8601DateFormatter().string(from: Self.now)

        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":{"main":"bigmodel/GLM-5.3"},"provider":{"bigmodel":{"options":{"baseURL":"https://open.bigmodel.cn/api/anthropic"}}}}"#.utf8).write(to: config)
        try EditorTestSupport.jsonLines([
            ["event": "zcode_protocol.process.memory_sample", "timestamp": stamp],
        ], to: log)
        try FileManager.default.setAttributes([.modificationDate: Self.now], ofItemAtPath: log.path)

        #expect(AgentActivity.verdict(for: log, provider: .glmCoding) == .finished)
        #expect(AgentActivity.states(for: [.glmCoding], now: Self.now, home: home)[.glmCoding]?.isWorking == false)
    }

    @Test("ZCode activity is attributed only to the configured GLM storefront")
    func zcodeStorefront() throws {
        let home = try EditorTestSupport.temporary("zcode-storefront")
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".zcode/cli/config.json")
        let log = home.appending(path: ".zcode/cli/log/zcode-2026-09-22.jsonl")
        let stamp = ISO8601DateFormatter().string(from: Self.now)

        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":{"main":"bigmodel/GLM-5.3"},"provider":{"bigmodel":{"options":{"baseURL":"https://open.bigmodel.cn/api/anthropic"}}}}"#.utf8).write(to: config)
        try EditorTestSupport.jsonLines([
            ["event": "turn.started", "timestamp": stamp, "turnId": "turn-a"],
        ], to: log)
        try FileManager.default.setAttributes([.modificationDate: Self.now], ofItemAtPath: log.path)

        let states = AgentActivity.states(for: [.glmCoding, .zai], now: Self.now, home: home)
        #expect(states[.glmCoding]?.isWorking == true)
        #expect(states[.zai]?.isWorking == false)
    }

    private actor Reader {
        var calls: [Set<Provider>] = []
        var working = true

        func read(_ providers: Set<Provider>) -> [Provider: AgentActivity.State] {
            calls.append(providers)
            return Dictionary(uniqueKeysWithValues: providers.map {
                ($0, AgentActivity.State(lastWrite: AgentActivityTests.now, isWorking: working))
            })
        }

        func finishWorking() { working = false }
    }

    @Test("A store with no local provider selected does not start a scan", arguments: [
        Set<String>(), [Provider.deepSeek.rawValue]
    ])
    @MainActor
    func storeWithoutLocalProviders(enabled: Set<String>) async {
        let reader = Reader()
        let monitor = AgentActivityMonitor { await reader.read($0) }
        let settings = AppSettings(enabledAccounts: enabled, readsTokenSpend: false)
        let store = UsageStore(settings: settings, activity: monitor)
        defer { monitor.stop() }

        store.updateActivityMonitor()
        #expect(monitor.sample() == nil)
        #expect(await reader.calls.isEmpty)
        #expect(monitor.running.isEmpty)
        #expect(monitor.lastWrite == nil)
    }

    @Test("The store follows enabled accounts, including an added account")
    @MainActor
    func storeSelection() async {
        let reader = Reader()
        let monitor = AgentActivityMonitor { await reader.read($0) }
        let extra = ExtraAccount(provider: .codex, slot: "test", label: "Test")
        let settings = AppSettings(
            enabledAccounts: [Provider.claudeCode.rawValue, Provider.deepSeek.rawValue],
            extraAccounts: [extra], readsTokenSpend: false
        )
        let store = UsageStore(settings: settings, activity: monitor)
        defer { monitor.stop() }

        store.updateActivityMonitor()
        await monitor.sample()?.value
        #expect(monitor.running == [.claudeCode])

        // Updating an unrelated setting must not restart the monitor.
        store.updateActivityMonitor()
        #expect(Set(await reader.calls) == [[.claudeCode]])
        #expect(monitor.running == [.claudeCode])

        settings.enabledAccounts = [extra.id]
        store.updateActivityMonitor()
        #expect(monitor.running.isEmpty)
        #expect(monitor.lastWrite == nil)
        #expect(monitor.finishedAt.isEmpty)
        await monitor.sample()?.value
        #expect(monitor.running == [.codex])
        #expect(Set(await reader.calls) == [[.claudeCode], [.codex]])

        settings.enabledAccounts = [Provider.deepSeek.rawValue]
        store.updateActivityMonitor()
        #expect(monitor.sample() == nil)
        #expect(monitor.running.isEmpty)
        #expect(monitor.lastWrite == nil)
        #expect(monitor.finishedAt.isEmpty)
    }

    @Test("Hiding the panel stops activity and reopening starts a new observation")
    @MainActor
    func panelVisibility() async {
        let reader = Reader()
        let monitor = AgentActivityMonitor { await reader.read($0) }
        let settings = AppSettings(isPanelVisible: false, enabledAccounts: [Provider.codex.rawValue])
        let store = UsageStore(settings: settings, activity: monitor)
        defer { monitor.stop() }

        store.updateActivityMonitor()
        #expect(monitor.sample() == nil)
        settings.isPanelVisible = true
        store.updateActivityMonitor()
        await monitor.sample()?.value
        #expect(monitor.running == [.codex])

        await reader.finishWorking()
        await monitor.sample()?.value
        #expect(monitor.finishedAt[.codex] != nil)
        #expect(monitor.lastWrite == Self.now)

        settings.isPanelVisible = false
        store.updateActivityMonitor()
        #expect(monitor.sample() == nil)
        #expect(monitor.lastWrite == nil)
        #expect(monitor.finishedAt.isEmpty)
        settings.isPanelVisible = true
        store.updateActivityMonitor()
        await monitor.sample()?.value
        #expect(monitor.running.isEmpty)
        #expect(monitor.finishedAt.isEmpty)
    }

    /// Deliberately returns even after cancellation, like a file read that was
    /// already in progress. No sleeps: the test decides when each scan ends.
    private actor HeldRead {
        private var result: CheckedContinuation<[Provider: AgentActivity.State], Never>?
        private var started: CheckedContinuation<Void, Never>?
        private var completed: [Provider: AgentActivity.State]?
        private(set) var wasCancelled = false

        func read() async -> [Provider: AgentActivity.State] {
            if let completed { return completed }
            let states = await withCheckedContinuation { continuation in
                result = continuation
                started?.resume()
                started = nil
            }
            wasCancelled = Task.isCancelled
            return states
        }

        func waitUntilStarted() async {
            if result != nil { return }
            await withCheckedContinuation { started = $0 }
        }

        func finish(_ states: [Provider: AgentActivity.State]) {
            completed = states
            result?.resume(returning: states)
            result = nil
        }
    }

    @Test("Changing selection cancels the old scan without blocking or overwriting the new one")
    @MainActor
    func selectionDuringScan() async {
        let old = HeldRead()
        let new = HeldRead()
        let monitor = AgentActivityMonitor { providers in
            if providers == [.claudeCode] { return await old.read() }
            return await new.read()
        }
        defer { monitor.stop() }
        monitor.start(providers: [.claudeCode])
        let oldScan = monitor.sample()
        await old.waitUntilStarted()

        monitor.start(providers: [.codex])
        let newScan = monitor.sample()
        await new.waitUntilStarted()
        await old.finish([.claudeCode: .init(lastWrite: Self.now, isWorking: true)])
        await oldScan?.value
        #expect(await old.wasCancelled)
        #expect(monitor.running.isEmpty)
        #expect(monitor.lastWrite == nil)
        #expect(monitor.finishedAt.isEmpty)
        // The old completion must not clear the new scan's handle.
        #expect(monitor.sample() == newScan)

        await new.finish([.codex: .init(lastWrite: Self.now, isWorking: true)])
        await newScan?.value
        #expect(monitor.running == [.codex])
        #expect(monitor.lastWrite == Self.now)
        #expect(monitor.finishedAt.isEmpty)
    }

    @Test("Stopping discards a late result and does not record a finished turn")
    @MainActor
    func stopDuringScan() async {
        let reader = HeldRead()
        let monitor = AgentActivityMonitor { _ in await reader.read() }
        monitor.start(providers: [.codex])
        let scan = monitor.sample()
        await reader.waitUntilStarted()
        monitor.stop()
        await reader.finish([.codex: .init(lastWrite: Self.now, isWorking: true)])
        await scan?.value
        #expect(await reader.wasCancelled)
        #expect(monitor.sample() == nil)
        #expect(monitor.running.isEmpty)
        #expect(monitor.lastWrite == nil)
        #expect(monitor.finishedAt.isEmpty)
    }
}
