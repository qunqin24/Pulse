// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// When the prompt cache behind each Codex conversation stops being guaranteed.
///
/// **Codex's log does not say how long a cache is kept** — it counts the
/// tokens read from the cache and written to it, nothing more. What makes this
/// readable anyway is OpenAI's own documentation: on GPT-5.6 and later "a
/// cached prefix remains eligible for reuse for 30 minutes after its most
/// recent write or reuse, though OpenAI may retain it longer", 30 minutes being
/// the only lifetime those models offer. The log does say which model each
/// turn used. So for those models the lapse is the last request plus the
/// documented thirty minutes — a floor, said as "at least".
///
/// **Earlier models are left out.** Their documented lifetimes are "typically"
/// five to ten minutes or around thirty, depending on a retention setting the
/// log does not record; there is no figure to state.
///
/// Even inside the thirty minutes a request can miss: OpenAI keeps caches per
/// machine, and heavy traffic is routed elsewhere. Settings says so.
extension PromptCacheReading {
    /// The providers whose logs let a cache be timed: Claude Code by the tier
    /// each reply records, Codex by the model each turn names.
    static func supports(_ provider: Provider) -> Bool {
        provider == .claudeCode || provider == .codex
    }

    /// A read for one of them; `.none` for any other.
    static func read(for provider: Provider) -> PromptCacheReading {
        switch provider {
        case .claudeCode: ClaudePromptCache.read()
        case .codex: CodexPromptCache.read()
        default: .none
        }
    }
}

enum CodexPromptCache {
    /// OpenAI's stated minimum on GPT-5.6 and later.
    static let guaranteed: TimeInterval = 30 * 60

    /// Enough of a session's end to hold its last turn's context line, its
    /// requests and their usage, without reading a long rollout whole.
    static let tailBytes = 512 * 1024
    static let headBytes = 64 * 1024

    /// Whether OpenAI states a cache lifetime for this model: `gpt-5.6` and
    /// every later version, whatever comes after the number (`gpt-6-sol`).
    /// Anything else — earlier GPTs, other families, Codex's own review model —
    /// has none, and is not timed.
    static func statesLifetime(forModel id: String) -> Bool {
        guard id.hasPrefix("gpt-") else { return false }
        let version = id.dropFirst(4).prefix { $0.isNumber || $0 == "." }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { return false }
        let minor = parts.count > 1 ? parts[1] : 0
        return major > 5 || (major == 5 && minor >= 6)
    }

    /// Every session whose guaranteed time is still running, soonest to end
    /// first, and — when none is — the one whose time ended last.
    ///
    /// Rollouts are filed under the day they **started**, so a long session
    /// can still be written to from an old folder; every rollout is listed and
    /// only those written in the last half hour are opened, plus the newest.
    static func read(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        now: Date = Date()
    ) -> PromptCacheReading {
        let files = rollouts(home: home)
        let recent = files.filter { now.timeIntervalSince($0.modified) <= guaranteed + 60 }

        var live: [PromptCacheSession] = []
        for file in recent {
            guard let session = session(at: file.url), session.lapse.expiresAt > now else { continue }
            live.append(session)
        }
        live.sort { $0.lapse.expiresAt < $1.lapse.expiresAt }
        guard live.isEmpty else { return PromptCacheReading(live: live, lastLapsed: nil) }

        let newest = files.max { $0.modified < $1.modified }
        return PromptCacheReading(live: [], lastLapsed: newest.flatMap { session(at: $0.url) }?.lapse)
    }

    private static func rollouts(home: URL) -> [(url: URL, modified: Date)] {
        let root = home.appending(path: ".codex/sessions")
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [(url: URL, modified: Date)] = []
        while let file = walker.nextObject() as? URL {
            guard file.pathExtension == "jsonl",
                  let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true, let modified = values.contentModificationDate
            else { continue }
            found.append((file, modified))
        }
        return found
    }

    private static func session(at file: URL) -> PromptCacheSession? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let tailData = try? handle.readToEnd() else { return nil }
        let tail = String(decoding: tailData, as: UTF8.self)
        guard let lapse = lapse(inTail: tail) else { return nil }

        // The header (directory) and the opening prompt are at the start.
        let whole = size <= UInt64(tailBytes)
        var head = tail
        if !whole {
            try? handle.seek(toOffset: 0)
            head = (try? handle.read(upToCount: headBytes)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        let names = names(inHead: head)
        return PromptCacheSession(
            id: file.path, title: names.title, project: UsageProject(names.cwd)?.name, lapse: lapse
        )
    }

    /// The directory from the session header, and the opening prompt: the
    /// first user message that is words rather than an envelope — the way the
    /// Token spend pane names a Codex session.
    private static func names(inHead text: String) -> (title: String?, cwd: String?) {
        var title: String?
        var cwd: String?
        for line in text.split(separator: "\n") where title == nil || cwd == nil {
            guard line.contains("\"cwd\"") || line.contains("\"role\":\"user\""),
                  let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["payload"] as? [String: Any]
            else { continue }
            if cwd == nil, let found = payload["cwd"] as? String, !found.isEmpty { cwd = found }
            if title == nil, payload["type"] as? String == "message", payload["role"] as? String == "user",
               let words = UsageLedgerReader.text(in: payload["content"]) {
                title = UsageLedgerReader.title(from: words)
            }
        }
        return (title, cwd)
    }

    /// From the end of a rollout backwards: the latest request that read or
    /// wrote the cache, the model its turn ran on, and when it was sent.
    ///
    /// The request's time is the input that prompted it — the person's
    /// message or a tool's output — not the usage line, which is written once
    /// the answer is in. Nil when no request touched the cache, when the
    /// model is not in reach of the tail, or when OpenAI states no lifetime
    /// for it.
    static func lapse(inTail text: String) -> PromptCacheLapse? {
        let lines = text.split(separator: "\n").compactMap(Line.init)
        guard let used = lines.lastIndex(where: \.touchedCache),
              let answeredAt = lines[used].timestamp
        else { return nil }

        let before = lines[..<used]
        guard let model = before.last(where: { $0.model != nil })?.model,
              statesLifetime(forModel: model)
        else { return nil }

        var sentAt = answeredAt
        if let input = before.last(where: \.isInput)?.timestamp {
            let gap = answeredAt.timeIntervalSince(input)
            if gap >= 0 && gap <= ClaudePromptCache.longestResponse { sentAt = input }
        }
        return PromptCacheLapse(lastRequest: sentAt, lifetime: guaranteed, isMinimum: true)
    }

    /// One line of a rollout, reduced to what the lapse needs.
    private struct Line {
        let timestamp: Date?
        /// A request's usage, with any of it read from or written to the cache.
        let touchedCache: Bool
        /// The model a turn ran on: its context line, or the session header.
        let model: String?
        /// Something sent to the model: the person's message or a tool's output.
        let isInput: Bool

        init?(_ line: Substring) {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let kind = root["type"] as? String
            let payload = root["payload"] as? [String: Any] ?? [:]
            let event = payload["type"] as? String
            timestamp = (root["timestamp"] as? String).flatMap(ClaudePromptCache.date)

            // A request's usage arrives twice — its own record and the running
            // count after it — and either says the same of the cache.
            let usage = kind == "token_usage_record"
                ? payload["usage"] as? [String: Any]
                : (event == "token_count" ? (payload["info"] as? [String: Any])?["last_token_usage"] as? [String: Any] : nil)
            touchedCache = usage.map {
                ($0["cached_input_tokens"] as? Int ?? 0) > 0 || ($0["cache_write_input_tokens"] as? Int ?? 0) > 0
            } ?? false

            switch kind {
            case "turn_context":
                model = payload["model"] as? String
            case "session_meta":
                model = ((payload["base_instructions"] as? [String: Any])?["provenance"] as? [String: Any])?["model"] as? String
            default:
                model = nil
            }

            isInput = (kind == "response_item"
                && (event == "function_call_output" || event == "custom_tool_call_output"
                    || (event == "message" && payload["role"] as? String == "user")))
                || (kind == "event_msg" && (event == "user_message" || event == "task_started"))
        }
    }
}
