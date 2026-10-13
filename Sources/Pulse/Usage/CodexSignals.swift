// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Signs, in this Mac's Codex sessions, that the work was quietly given less
/// than was asked for. **Signs, not proof** — and only what Codex writes down.
///
/// The one fact that would settle it — which model the server actually ran —
/// is never saved: Codex reads it from a response header and keeps the
/// warning it raises on a mismatch out of the session file (`ModelReroute` is
/// transient in `codex-rs/rollout/src/policy.rs`). Finding it means sending a
/// probe or sitting in the traffic, and Pulse does neither: it reads.
/// What *is* written leaves two kinds of trace, and this reads both.
///
/// **Reasoning cut short.** Every response's `token_count` event carries
/// `last_token_usage.reasoning_output_tokens`. Reasoning that stops on its own
/// lands on any count; reasoning that is cut lands on 516, 1034, 1552… —
/// `518·n − 2`, a lattice found in openai/codex#30364 over 390k responses and
/// reproduced on this Mac (gpt-5.5: 41.6% of responses that reached 516
/// stopped exactly on it; the codex models, none). By chance about one in
/// 518 would. The step and the offset are empirical; nobody has published a
/// cause. Counted per model, as a share of the responses that got that far.
///
/// **Settings changed under the session.** From Codex 0.144 every change the
/// user makes is written as `thread_settings_applied`, and takes effect at the
/// next `task_started`. A turn whose `turn_context` runs a different model or
/// a lower reasoning effort than the settings in force when it started was
/// changed by something other than the user. The context window is not read:
/// `token_count`'s `model_context_window` is Codex's own sum — the configured
/// window (`model_context_window` in `config.toml`, else the model's default)
/// times the model's effective percentage — so a smaller one is a config edit,
/// never what the server ran.
/// Sessions written before 0.144 record no such event — a `/model` there is
/// indistinguishable from a silent switch — so they are not judged at all;
/// nor is a newer one with none applied, nor Codex's own helpers (sessions
/// with a `source` or `parent_thread_id`, turns whose `root_turn_id` is
/// another's, the `auto-review` model).
///
/// **A fork copies its parent first**, every copied line stamped with the
/// moment of the fork; those lines are skipped, or a month-old response would
/// be counted twice and dated today.
/// All of it is request-side: what Codex asked for, not what the server ran.
struct CodexSignals: Sendable, Equatable {
    /// One model's responses over the span.
    struct Truncation: Identifiable, Sendable, Equatable {
        let model: String
        /// Responses with any reasoning at all.
        var responses = 0
        /// Responses whose reasoning reached 516, the first lattice point.
        var reachedLattice = 0
        /// Of those, the ones that stopped exactly on a lattice point.
        var onLattice = 0

        var id: String { model }

        var share: Double? { reachedLattice > 0 ? Double(onLattice) / Double(reachedLattice) : nil }

        /// Enough responses reached the lattice to say anything about it.
        var isMeasurable: Bool { reachedLattice >= CodexSignals.fewestReached }

        /// Many times what chance would put there, and not a stray hit or two.
        var isSuspicious: Bool {
            isMeasurable && onLattice >= CodexSignals.fewestHits && (share ?? 0) >= CodexSignals.suspiciousShare
        }
    }

    /// A turn that ran on less than the settings in force when it started.
    struct Change: Identifiable, Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case model(asked: String, ran: String)
            case effort(asked: String, ran: String)
        }

        let kind: Kind
        let date: Date
        let session: String
        /// Its place in the session, so two changes written in the same
        /// instant are still two rows.
        var order = 0

        var id: String { "\(session)|\(order)" }
    }

    var truncation: [Truncation] = []
    var changes: [Change] = []
    /// Sessions in the span, and how many of them were new enough to judge
    /// for changed settings.
    var sessions = 0
    var judgedSessions = 0

    static let fewestReached = 20
    static let fewestHits = 5
    /// Twenty-five times chance (1 in 518).
    static let suspiciousShare = 0.05
    /// The first Codex that writes the user's own changes down.
    static let firstJudgedVersion = (0, 144, 0)

    /// `518·n − 2` for some n ≥ 1.
    static func isOnLattice(_ reasoning: Int) -> Bool {
        reasoning >= 516 && (reasoning + 2) % 518 == 0
    }
}

// MARK: - Reading

/// Reads the signs out of `~/.codex/sessions` and `~/.codex/archived_sessions`.
///
/// Each file's facts are kept in memory against its size and modification
/// time, so opening the pane again — or widening the span — reads only what
/// changed. A few hundred megabytes of sessions is a few seconds the first
/// time, because only the lines that can matter are decoded.
actor CodexSignalReader {
    static let shared = CodexSignalReader()

    private let roots: [URL]
    private var cache: [String: (stamp: Stamp, facts: FileFacts)] = [:]

    init(home: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        roots = [home.appending(path: ".codex/sessions"), home.appending(path: ".codex/archived_sessions")]
    }

    init(roots: [URL]) { self.roots = roots }

    private struct Stamp: Equatable {
        let size: Int
        let modified: Date
    }

    /// One response, as much as the counts need.
    struct Response: Sendable, Equatable {
        let date: Date
        let model: String
        let reasoning: Int
    }

    struct FileFacts: Sendable, Equatable {
        var responses: [Response] = []
        var changes: [CodexSignals.Change] = []
        var lastDate: Date?
        var isJudged = false
    }

    /// The signs since `since` (everything when nil).
    func read(since: Date?) -> CodexSignals {
        var signals = CodexSignals()
        var byModel: [String: CodexSignals.Truncation] = [:]

        for file in files(modifiedSince: since) {
            if Task.isCancelled { break }
            guard let facts = facts(for: file) else { continue }
            if let since, let last = facts.lastDate, last < since { continue }
            signals.sessions += 1
            if facts.isJudged { signals.judgedSessions += 1 }
            for response in facts.responses where since.map({ response.date >= $0 }) ?? true {
                guard !Self.isCodexsOwn(response.model) else { continue }
                var entry = byModel[response.model] ?? .init(model: response.model)
                entry.responses += 1
                if response.reasoning >= 516 { entry.reachedLattice += 1 }
                if CodexSignals.isOnLattice(response.reasoning) { entry.onLattice += 1 }
                byModel[response.model] = entry
            }
            signals.changes += facts.changes.filter { change in since.map { change.date >= $0 } ?? true }
        }

        signals.truncation = byModel.values.sorted {
            ($0.isSuspicious ? 1 : 0, $0.responses) > ($1.isSuspicious ? 1 : 0, $1.responses)
        }
        signals.changes.sort { $0.date > $1.date }
        return signals
    }

    /// Codex's reviewer, which runs sessions of its own by design: not a
    /// model anybody picked, and not one to report on.
    static func isCodexsOwn(_ model: String) -> Bool { model.contains("auto-review") }

    private func files(modifiedSince since: Date?) -> [URL] {
        var found: [URL] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        for root in roots {
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { continue }
            for case let url as URL in walk {
                let name = url.lastPathComponent
                guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
                if let since,
                   let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modified < since { continue }
                found.append(url)
            }
        }
        return found
    }

    private func facts(for file: URL) -> FileFacts? {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate
        else { return nil }
        let stamp = Stamp(size: size, modified: modified)
        if let kept = cache[file.path], kept.stamp == stamp { return kept.facts }
        let facts = Self.parse(LogLines(at: file), session: file.lastPathComponent)
        // A cancelled read stops yielding lines, so what came back is a part
        // of the file — kept, it would stand for the whole until it changed.
        guard !Task.isCancelled else { return nil }
        cache[file.path] = (stamp, facts)
        return facts
    }

    // MARK: - One file

    private static let wanted = ["\"session_meta\"", "\"turn_context\"", "\"thread_settings_applied\"",
                                 "\"task_started\"", "\"token_count\""].map { Data($0.utf8) }

    /// Lowest to highest, as Codex ranks them (`supported_reasoning_levels` in
    /// `~/.codex/models_cache.json`). A level missing here is never compared.
    private static let efforts = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]

    static func parse(_ lines: LogLines, session: String) -> FileFacts {
        var facts = FileFacts()
        var version: (Int, Int, Int)?
        var model: String?
        var lastTotals: [Int]?

        // Settings: the latest the user applied, the ones in force when the
        // running turn started, and the previous turn's own.
        var applied: (model: String?, effort: String?) = (nil, nil)
        var atStart: (model: String?, effort: String?) = (nil, nil)
        var previous: (model: String?, effort: String?) = (nil, nil)
        var subTurns: Set<String> = []
        var appliedAny = false
        var isOwnSession = false
        /// A fork starts by copying the session it came from, every copied
        /// line stamped with the moment of the fork; those are the parent's
        /// responses and settings, counted in the parent's own file.
        var replayUntil: Date?

        lines.forEachLine { line in
            guard wanted.contains(where: { line.range(of: $0) != nil }),
                  let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { return }
            let payload = root["payload"] as? [String: Any] ?? [:]
            let date = (root["timestamp"] as? String).flatMap(Self.date)
            if let date { facts.lastDate = max(facts.lastDate ?? date, date) }
            let type = root["type"] as? String
            if type != "session_meta", let replayUntil, let date, date <= replayUntil { return }

            switch type {
            case "session_meta":
                // A resumed session writes its header again; only the first
                // says what the session is.
                guard version == nil else { return }
                version = (payload["cli_version"] as? String).flatMap(Self.version)
                facts.isJudged = version.map { $0 >= CodexSignals.firstJudgedVersion } ?? false
                // Codex's own helpers (a guardian, a sub-agent) run on models
                // Codex picks, not the user.
                if payload["source"] is [String: Any] || payload["parent_thread_id"] is String { isOwnSession = true }
                if payload["forked_from_id"] is String, let date {
                    replayUntil = date.addingTimeInterval(Self.replayWindow)
                }

            case "turn_context":
                let ran = payload["model"] as? String
                if let ran { model = ran }
                guard facts.isJudged, let date else { return }
                if let turn = payload["turn_id"] as? String, subTurns.contains(turn) { return }
                let effort = payload["effort"] as? String
                    ?? ((payload["collaboration_mode"] as? [String: Any])?["settings"] as? [String: Any])?["reasoning_effort"] as? String
                let asked = (model: atStart.model ?? previous.model, effort: atStart.effort ?? previous.effort)
                let ownModel = ran.map(isCodexsOwn) ?? false
                if let ran, let wanted = asked.model, ran != wanted, !ownModel, !isCodexsOwn(wanted) {
                    facts.changes.append(.init(kind: .model(asked: wanted, ran: ran), date: date, session: session))
                }
                if let effort, let wanted = asked.effort, !ownModel,
                   let have = efforts.firstIndex(of: effort), let want = efforts.firstIndex(of: wanted), have < want {
                    facts.changes.append(.init(kind: .effort(asked: wanted, ran: effort), date: date, session: session))
                }
                previous = (ran ?? previous.model, effort ?? previous.effort)

            case "event_msg":
                switch payload["type"] as? String {
                case "task_started":
                    if let turn = payload["turn_id"] as? String,
                       let origin = payload["root_turn_id"] as? String, !origin.isEmpty, origin != turn {
                        subTurns.insert(turn)
                    }
                    atStart = applied
                case "thread_settings_applied":
                    appliedAny = true
                    let settings = payload["thread_settings"] as? [String: Any] ?? [:]
                    applied = (settings["model"] as? String ?? applied.model,
                               settings["reasoning_effort"] as? String ?? applied.effort)
                case "token_count":
                    guard let info = payload["info"] as? [String: Any] else { return }
                    // The same count is written more than once; a repeat of
                    // the running totals is not another response.
                    let totals = (info["total_token_usage"] as? [String: Any]).map { usage in
                        ["input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"].map { int(usage[$0]) ?? 0 }
                    }
                    if let totals {
                        guard totals != lastTotals else { return }
                        lastTotals = totals
                    }
                    guard let last = info["last_token_usage"] as? [String: Any],
                          let reasoning = int(last["reasoning_output_tokens"]), reasoning > 0,
                          let model, let date
                    else { return }
                    facts.responses.append(.init(date: date, model: model, reasoning: reasoning))
                default:
                    return
                }
            default:
                return
            }
        }

        // Judged only where the user's own changes are on record: a session
        // with none applied is compared turn to turn alone, and could not
        // tell a `/model` from a swap. Codex's helpers are not the user's.
        facts.isJudged = facts.isJudged && appliedAny && !isOwnSession
        if facts.isJudged {
            for index in facts.changes.indices { facts.changes[index].order = index }
        } else {
            facts.changes = []
        }
        return facts
    }

    /// How long after a fork's header its copied history is still being
    /// written: measured, every copied line carries the fork's own moment.
    static let replayWindow: TimeInterval = 2

    private static func int(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? NSNumber)?.intValue
    }

    static func version(_ text: String) -> (Int, Int, Int)? {
        let parts = text.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        guard parts.count >= 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    static func date(_ text: String) -> Date? {
        (try? fractional.parse(text)) ?? (try? whole.parse(text))
    }
}
