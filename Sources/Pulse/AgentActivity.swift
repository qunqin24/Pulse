import Foundation
import Observation

/// Whether Claude Code and Codex are working, read from the transcripts their
/// CLIs write as they go.
///
/// The obvious approach — "written to in the last N seconds" — is wrong in
/// both directions at once, and no value of N fixes it. A turn that is running
/// a slow tool writes nothing for minutes, so a short N stops the spinner
/// while the agent is still busy; a finished turn goes on spinning for the
/// rest of N. What is actually wanted is *is this turn still in flight*, and
/// both tools happen to say so outright:
///
/// - Claude Code stamps every assistant record with a `stop_reason`.
///   `tool_use` means it is handing off to a tool and will be back; `end_turn`
///   means the turn is over. A trailing `user` record — a prompt, or a tool's
///   result coming back — means it is the model's move, unless it is the one
///   Claude Code writes when the turn is interrupted.
/// - Codex brackets each turn with `task_started` and `task_complete` events,
///   and its tool calls and their results say which half of a turn is in
///   flight.
///
/// So only the tail of the newest transcripts is read, and the answer is exact
/// rather than a guess with a timer attached.
///
/// A timer is still needed for one case — a session that *died* mid-turn, from
/// a force quit, a crash, or a lid closed — because the transcript's last word
/// then claims a turn that will never finish. What that timer is worth
/// depends on what the turn was waiting for, which is why `Wait` exists.
enum AgentActivity {
    struct State: Sendable, Equatable {
        var lastWrite: Date?
        var isWorking: Bool
    }

    /// What a turn in flight is waiting for, which is what decides how long
    /// its claim to be working may outlive the record that made it. A single
    /// timeout cannot serve both: it has to be long enough for the slowest
    /// tool, and that is far longer than a dead session should go on spinning.
    ///
    /// Measured over this machine's own transcripts, 3,110 turns of one and
    /// 2,783 of the other:
    ///
    /// - **the model's move** — median 7s, 99% inside 70s, 10 of 3,110 over
    ///   two minutes. So a turn that has been the model's move for a minute
    ///   and a half is a session that ended without saying so.
    /// - **a tool** — median 2s, but shells, builds and test runs write
    ///   nothing while they run and the longest here was 15 minutes. This is
    ///   the case the old single timeout was sized for, and it keeps it.
    enum Wait: Equatable {
        case tool
        case model

        var grace: TimeInterval {
            switch self {
            case .tool: 5 * 60
            case .model: 90
            }
        }
    }

    /// Used only when the tail says nothing recognisable: a format that has
    /// changed under us, or a transcript too new to have a decisive record
    /// yet. Falls back to the crude "written to just now".
    static let unknownFormatWindow: TimeInterval = 30

    static func states(now: Date = Date()) -> [Provider: State] {
        var states: [Provider: State] = [:]

        for provider in Provider.allCases {
            let files = transcripts(for: provider)
            var state = State(lastWrite: files.first?.modified, isWorking: false)

            // Any live session counts: two terminals can be running at once,
            // and the newest file is not necessarily the busy one. The filter
            // is the longest grace any verdict can claim, so nothing older is
            // worth opening.
            for file in files where now.timeIntervalSince(file.modified) <= Wait.tool.grace {
                switch verdict(for: file.url, provider: provider) {
                case .working(let wait, let at):
                    // Timed from the record's *own* stamp, not the file's.
                    // Claude Code goes on writing bookkeeping into a transcript
                    // long after the turn it belongs to ended — titles, modes,
                    // background monitors — so a file's modification date says
                    // when something last touched it, not when the agent last
                    // did anything. Timing the grace off that let a session
                    // that died mid-turn look freshly written for ever, and the
                    // ring turned for as long as the file kept being poked.
                    state.isWorking = now.timeIntervalSince(at ?? file.modified) <= wait.grace
                case .finished:
                    continue
                case .unknown:
                    state.isWorking = now.timeIntervalSince(file.modified) <= unknownFormatWindow
                }
                if state.isWorking { break }
            }

            states[provider] = state
        }

        return states
    }

    // MARK: - Reading the tail

    /// Internal rather than private so the rule can be driven directly against
    /// real and synthetic transcripts — it is the whole feature, and "the
    /// spinner looked right for a moment" is not a check.
    enum Verdict: Equatable {
        /// A turn is in flight, waiting on `wait`, as of the moment the record
        /// that says so was written. That stamp is nil only for a record which
        /// carries none, which in practice means a format we half-recognise.
        case working(Wait, at: Date?)
        case finished
        case unknown
    }

    /// Reads backwards from the end of a transcript for the first record that
    /// settles the question, so a 20MB file costs a few kilobytes to consult.
    static func verdict(for url: URL, provider: Provider) -> Verdict {
        for line in tail(of: url).reversed() {
            guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }

            switch provider {
            case .claudeCode:
                switch record["type"] as? String {
                case "assistant":
                    let stop = (record["message"] as? [String: Any])?["stop_reason"] as? String
                    guard let stop else {
                        // No stop reason at all is what a subagent's records
                        // look like: they are written into the same transcript
                        // inline, and one of them is the file's last word
                        // whenever a background agent outlives the turn that
                        // started it. Counting that as a turn still streaming
                        // gave it the full tool grace — five minutes of ring
                        // for an agent that had already answered.
                        return .working(.model, at: stamp(of: record))
                    }
                    return stop == "tool_use"
                        ? .working(.tool, at: stamp(of: record))
                        : .finished
                case "user":
                    // Pressing escape ends the turn and says so in the record
                    // it leaves behind. Read as an ordinary prompt it means the
                    // exact opposite — that the model is about to answer — so
                    // the ring went on turning after every interrupt for as
                    // long as the timeout allowed.
                    if isInterruption(record) { return .finished }
                    // Otherwise a prompt, or a tool's result coming back: both
                    // leave the next move with the model.
                    return .working(.model, at: stamp(of: record))
                default:
                    // Bookkeeping records (queued operations, attachments, the
                    // window title) say nothing about the turn.
                    continue
                }

            case .codex:
                switch (record["payload"] as? [String: Any])?["type"] as? String {
                case "task_complete", "turn_aborted":
                    return .finished
                case "task_started":
                    return .working(.model, at: stamp(of: record))
                // Codex writes the call, then the result, as two records. Which
                // of them the tail ends on is which half of the turn is running
                // — and they are the only way to tell, since a turn is bounded
                // by `task_started` alone until it completes.
                case "function_call", "custom_tool_call", "local_shell_call",
                     "web_search_call", "tool_search_call":
                    return .working(.tool, at: stamp(of: record))
                case "function_call_output", "custom_tool_call_output", "tool_search_output":
                    return .working(.model, at: stamp(of: record))
                default:
                    continue
                }

            case .antigravity, .cursor, .openCodeGo, .kimiCode:
                // None of these leaves transcripts Pulse reads, so nothing
                // ever gets this far.
                return .finished
            }
        }

        return .unknown
    }

    /// Claude Code records an interrupted turn as a user message saying so,
    /// which is the only thing in the file that marks the difference between a
    /// turn the user stopped and one about to be answered.
    private static func isInterruption(_ record: [String: Any]) -> Bool {
        let content = (record["message"] as? [String: Any])?["content"]

        let text: String
        switch content {
        case let plain as String:
            text = plain
        case let blocks as [[String: Any]]:
            text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        default:
            return false
        }

        return text.contains("[Request interrupted by user")
    }

    /// When the record was written, by its own account. Both CLIs stamp every
    /// record that means anything; the bookkeeping ones carry no stamp, which
    /// is part of what marks them out as bookkeeping.
    ///
    /// Built per call rather than kept: `ISO8601DateFormatter` is not
    /// `Sendable`, and this runs at most once per file consulted.
    private static func stamp(of record: [String: Any]) -> Date? {
        guard let text = record["timestamp"] as? String else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// The last stretch of a file, split into whole lines.
    private static func tail(of url: URL, limit: Int = 128 * 1024) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(limit) ? size - UInt64(limit) : 0
        try? handle.seek(toOffset: start)

        guard let data = try? handle.readToEnd() else { return [] }
        var lines: [Data] = data
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .map { Data($0) }

        // The first line is only half a line unless we started at the top.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    // MARK: - Finding the files

    /// Every transcript for a provider with its modification date, newest
    /// first. Only file metadata is read here; measured at about 2ms across
    /// both trees on a machine holding a few hundred megabytes of them.
    private static func transcripts(for provider: Provider) -> [(url: URL, modified: Date)] {
        guard let root = root(for: provider) else { return [] }

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [(url: URL, modified: Date)] = []
        for case let url as URL in walker {
            guard
                url.pathExtension == "jsonl",
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
            else { continue }

            found.append((url, modified))
        }

        return found.sorted { $0.modified > $1.modified }
    }

    /// Nil for an agent that leaves no transcripts, which is what keeps this
    /// from walking a directory that was never going to exist.
    static func root(for provider: Provider) -> URL? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return switch provider {
        case .claudeCode: home.appending(path: ".claude/projects")
        case .codex: home.appending(path: ".codex/sessions")
        case .antigravity, .cursor, .openCodeGo, .kimiCode: nil
        }
    }
}

/// Watches for a provider's CLI being busy *right now*, so the rail can say so.
///
/// Deliberately a separate clock from the usage refresh. Usage is someone
/// else's server and moves in percent; this is a local read and has to keep up
/// with a turn that starts and finishes in seconds, or the spinner it drives
/// would be a lie in one direction or the other.
@MainActor
@Observable
final class AgentActivityMonitor {
    /// Providers whose CLI is in the middle of a turn.
    private(set) var running: Set<Provider> = []
    /// The most recent write from any provider, which is also what paces the
    /// adaptive refresh interval.
    private(set) var lastWrite: Date?

    /// Fast enough that the spinner starts and stops with the turn rather than
    /// lagging it noticeably, slow enough to be free.
    private static let interval: TimeInterval = 2

    private var timer: Timer?
    private var isScanning = false

    func start() {
        guard timer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard !running.isEmpty else { return }
        running = []
    }

    private func sample() {
        guard !isScanning else { return }
        isScanning = true

        Task {
            let states = await Task.detached(priority: .utility) { AgentActivity.states() }.value
            self.isScanning = false

            let active = Set(states.filter(\.value.isWorking).keys)
            // Assign only on a change: this runs every couple of seconds, and
            // `@Observable` would otherwise redraw the rail each time for
            // nothing.
            if active != running { running = active }

            let newest = states.values.compactMap(\.lastWrite).max()
            if newest != lastWrite { lastWrite = newest }
        }
    }
}
