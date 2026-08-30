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
///   result coming back — means it is the model's move.
/// - Codex brackets each turn with `task_started` and `task_complete` events.
///
/// So only the tail of the newest transcripts is read, and the answer is exact
/// rather than a guess with a timer attached.
enum AgentActivity {
    struct State: Sendable, Equatable {
        var lastWrite: Date?
        var isWorking: Bool
    }

    /// A turn claiming to be in flight for longer than this is taken as a
    /// session that died — force-quit, crashed, or a machine put to sleep —
    /// rather than one still thinking. Without it a killed session spins for
    /// ever.
    static let sessionTimeout: TimeInterval = 5 * 60

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
            // and the newest file is not necessarily the busy one. Anything
            // untouched for longer than the timeout belongs to a session that
            // is over, one way or another.
            for file in files where now.timeIntervalSince(file.modified) <= sessionTimeout {
                switch verdict(for: file.url, provider: provider) {
                case .working:
                    state.isWorking = true
                case .finished:
                    continue
                case .unknown:
                    state.isWorking = state.isWorking
                        || now.timeIntervalSince(file.modified) <= unknownFormatWindow
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
    enum Verdict: String, Equatable {
        case working
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
                    // A turn still streaming has no stop reason yet.
                    guard let stop else { return .working }
                    return stop == "tool_use" ? .working : .finished
                case "user":
                    // Either a fresh prompt or a tool's result coming back —
                    // both leave the next move with the model.
                    return .working
                default:
                    // Bookkeeping records (queued operations, attachments, the
                    // window title) say nothing about the turn.
                    continue
                }

            case .codex:
                switch (record["payload"] as? [String: Any])?["type"] as? String {
                case "task_started": return .working
                case "task_complete", "turn_aborted": return .finished
                default: continue
                }

            case .antigravity, .openCodeGo, .kimiCode:
                // None of these leaves transcripts Pulse reads, so nothing
                // ever gets this far.
                return .finished
            }
        }

        return .unknown
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
        case .antigravity, .openCodeGo, .kimiCode: nil
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
