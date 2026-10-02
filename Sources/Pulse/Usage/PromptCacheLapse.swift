// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// When the prompt cache behind Claude Code's latest session lapses.
///
/// **Read, not assumed.** Every reply Claude Code logs states which cache tier
/// it wrote to — `cache_creation.ephemeral_1h_input_tokens` or
/// `ephemeral_5m_input_tokens` — and when it was made. A cache lives its tier's
/// length from the last request that used it, since a hit renews it. So the
/// lapse is the last request plus the tier that session last wrote: both
/// figures from the log, nothing from a table.
///
/// **The request's time, not the reply's.** A reply is logged when it has
/// finished streaming, and the cache is counted from when the request was
/// made — so the reply's own timestamp runs late by however long the answer
/// took. Measured over 184 responses: a median of 2 s, 99% within 80 s, and
/// two minutes at most, always in the direction of promising a cache that had
/// already lapsed. The request is the message that prompted the reply — the
/// person's, or a tool's result — logged just before it is sent.
///
/// **Claude Code only.** Codex logs how many tokens were read from the cache
/// and written to it, and nothing about how long they are kept; a lifetime for
/// it would be a number no record states.
///
/// **The main session, not its subagents.** Subagents write their own files
/// under the session's folder, on the shorter tier; the session the person is
/// typing into is the one whose cache decides what the next message costs.
struct PromptCacheLapse: Equatable, Sendable {
    /// When the last request that read or wrote the cache was made.
    let lastRequest: Date
    /// The tier's length: an hour or five minutes.
    let lifetime: TimeInterval
    /// Whether `lifetime` is a floor the provider guarantees rather than the
    /// length it keeps a cache — OpenAI's "at least 30 minutes", after which
    /// the cache may still be there. Said as "at least" wherever it is shown,
    /// and its end as "may have lapsed", never "expired".
    var isMinimum = false

    var expiresAt: Date { lastRequest.addingTimeInterval(lifetime) }

    /// Past this, a lapsed cache is not worth a line: the session is over.
    static let staleAfter: TimeInterval = 24 * 3600

    static let hour: TimeInterval = 3600
    static let fiveMinutes: TimeInterval = 300

    /// "1 hr", "38 min" — whole minutes, rounded up, so the last minute
    /// still reads as one rather than nothing. Shared by the card and Settings.
    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        formatter.calendar = {
            var calendar = Calendar.current
            calendar.locale = LocalizationSource.locale
            return calendar
        }()
        let minutes = max((seconds / 60).rounded(.up), 1) * 60
        return formatter.string(from: minutes) ?? ""
    }
}

/// One conversation whose cache Pulse can time.
struct PromptCacheSession: Identifiable, Equatable, Sendable {
    /// The transcript's path.
    let id: String
    /// A rename, or the opening prompt cut to a line.
    let title: String?
    /// The directory it ran in, by its last folder.
    let project: String?
    let lapse: PromptCacheLapse
}

/// Every conversation still holding a cache, and what to say when none is.
struct PromptCacheReading: Equatable, Sendable {
    /// Soonest to lapse first.
    var live: [PromptCacheSession]
    /// The newest session's lapse, when no session's cache is alive.
    var lastLapsed: PromptCacheLapse?

    static let none = PromptCacheReading(live: [], lastLapsed: nil)

    /// The conversations whose cache is still alive at `now`, soonest first.
    /// Filtered again at read time, so one that lapses while a card is open
    /// drops out of the count before the next read finds it gone.
    func alive(at now: Date) -> [PromptCacheSession] {
        live.filter { $0.lapse.expiresAt > now }.sorted { $0.lapse.expiresAt < $1.lapse.expiresAt }
    }
}

extension PromptCacheSession {
    /// What to call this conversation on a line of its own: a rename or the
    /// opening prompt, else the project it ran in.
    var displayName: String? { title ?? project }
}

enum ClaudePromptCache {
    /// Enough of a session's end to hold its last few replies, and a cache
    /// write among them, without reading a long transcript whole.
    static let tailBytes = 512 * 1024

    /// Every main session whose cache is still alive, soonest to lapse first,
    /// and — when none is — the one that lapsed last.
    ///
    /// Main sessions sit one folder down (`projects/<project>/<id>.jsonl`);
    /// anything deeper is a subagent's, and is not looked at. Only files
    /// written in the last hour can hold a live cache — a request can be no
    /// later than the file's last write, and no tier outlives an hour — so
    /// only those, and the newest file for the lapsed case, are opened.
    static func read(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        now: Date = Date()
    ) -> PromptCacheReading {
        let files = mainSessions(home: home)
        let recent = files.filter { now.timeIntervalSince($0.modified) <= PromptCacheLapse.hour + 60 }

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

    private static func mainSessions(home: URL) -> [(url: URL, modified: Date)] {
        let root = home.appending(path: ".claude/projects")
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [(url: URL, modified: Date)] = []
        for project in projects {
            guard let files = try? manager.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true, let modified = values.contentModificationDate
                else { continue }
                found.append((file, modified))
            }
        }
        return found
    }

    /// One session's lapse, named: the tail gives the lapse, a rename and the
    /// directory; the head gives the opening prompt when there is no rename.
    private static func session(at file: URL) -> PromptCacheSession? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let tailData = try? handle.readToEnd() else { return nil }
        let tail = String(decoding: tailData, as: UTF8.self)
        guard let lapse = lapse(inTail: tail) else { return nil }

        let whole = size <= UInt64(tailBytes)
        var names = SessionNames.from(tail, startsAtBeginning: whole)
        if names.title == nil || names.cwd == nil, !whole {
            try? handle.seek(toOffset: 0)
            if let head = try? handle.read(upToCount: headBytes) {
                let opening = SessionNames.from(String(decoding: head, as: UTF8.self), startsAtBeginning: true)
                names.title = names.title ?? opening.title
                names.cwd = names.cwd ?? opening.cwd
            }
        }
        let project = UsageProject(names.cwd) ?? UsageLedgerReader.project(of: file, provider: .claudeCode)
        return PromptCacheSession(id: file.path, title: names.title, project: project?.name, lapse: lapse)
    }

    /// Where a conversation's opening prompt is, in all but the longest pastes.
    static let headBytes = 64 * 1024

    /// What a session is called and where it ran, the way the Token spend
    /// pane names it: a rename (the last one) over the opening prompt.
    private struct SessionNames {
        var title: String?
        var cwd: String?

        /// `startsAtBeginning`: whether the text is the file's start, where
        /// the first user line is the opening prompt. In a tail it is only
        /// the latest turn's, which names nothing.
        static func from(_ text: String, startsAtBeginning: Bool) -> SessionNames {
            var names = SessionNames()
            var opening: String?
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                if names.cwd == nil, let cwd = root["cwd"] as? String, !cwd.isEmpty { names.cwd = cwd }
                if let custom = root["customTitle"] as? String,
                   let title = UsageLedgerReader.title(from: custom) {
                    names.title = title
                }
                if opening == nil, root["type"] as? String == "user", root["isSidechain"] as? Bool != true,
                   let message = root["message"] as? [String: Any],
                   let text = UsageLedgerReader.text(in: message["content"]),
                   let title = UsageLedgerReader.title(from: text) {
                    opening = title
                }
            }
            if names.title == nil, startsAtBeginning { names.title = opening }
            return names
        }
    }

    /// A response can take this long to arrive and no longer, in what is
    /// believed about the log. A longer gap between a reply and the message
    /// that prompted it means the two are not the pair they look like — a
    /// resumed session, a compaction — and the reply's own time is used.
    static let longestResponse: TimeInterval = 20 * 60

    /// From the end of a session backwards: the latest reply that touched the
    /// cache gives the time, and the latest one that wrote to it gives the
    /// tier — often the same reply, not always, since a hit writes nothing.
    ///
    /// The time is the **request's**: the message that prompted that reply,
    /// found by walking back through the reply's own blocks (one response is
    /// logged as several lines) to the first entry that is not one. Where that
    /// entry is not in reach of the tail, or is implausibly far back, the
    /// reply's own time stands — later than the request, so never the earlier
    /// lapse by mistake.
    ///
    /// Nil when no reply touched the cache, or none in reach says which tier
    /// it wrote — a tier Pulse would otherwise have to assume. The first line
    /// of a tail that starts mid-file does not parse and is skipped with the
    /// rest of what is not a reply.
    static func lapse(inTail text: String) -> PromptCacheLapse? {
        let lines = text.split(separator: "\n")
        var lastRequest: Date?
        for line in lines.reversed() where line.contains("\"usage\"") {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data),
                  entry.type == "assistant", entry.isSidechain != true,
                  let usage = entry.message?.usage
            else { continue }

            let wrote = usage.cacheCreation
            let touched = (usage.cacheRead ?? 0) > 0 || (usage.cacheWritten ?? 0) > 0
            if lastRequest == nil {
                guard touched, let repliedAt = entry.timestamp.flatMap(Self.date) else { continue }
                lastRequest = requestTime(of: entry, repliedAt: repliedAt, in: lines) ?? repliedAt
            }
            if let lastRequest, let wrote {
                if (wrote.hour ?? 0) > 0 {
                    return PromptCacheLapse(lastRequest: lastRequest, lifetime: PromptCacheLapse.hour)
                }
                if (wrote.fiveMinutes ?? 0) > 0 {
                    return PromptCacheLapse(lastRequest: lastRequest, lifetime: PromptCacheLapse.fiveMinutes)
                }
            }
        }
        return nil
    }

    /// The time of the message that prompted `reply`, when it is in the tail
    /// and the gap is one a response can have.
    private static func requestTime(of reply: Entry, repliedAt: Date, in lines: [Substring]) -> Date? {
        var parent = reply.parentUuid
        // One response is a handful of lines; a longer chain is not one.
        for _ in 0..<64 {
            guard let id = parent, let entry = entry(withUUID: id, in: lines) else { return nil }
            if entry.type != "assistant" {
                guard let at = entry.timestamp.flatMap(Self.date) else { return nil }
                let gap = repliedAt.timeIntervalSince(at)
                return gap >= 0 && gap <= longestResponse ? at : nil
            }
            parent = entry.parentUuid
        }
        return nil
    }

    /// Found by its own `"uuid"` field, which a `parentUuid` elsewhere cannot
    /// match — the key is spelled with a capital there.
    private static func entry(withUUID id: String, in lines: [Substring]) -> Entry? {
        let needle = "\"uuid\":\"\(id)\""
        for line in lines.reversed() where line.contains(needle) {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data),
                  entry.uuid == id
            else { continue }
            return entry
        }
        return nil
    }

    static func date(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private struct Entry: Decodable {
        let uuid: String?
        let parentUuid: String?
        let type: String?
        let timestamp: String?
        let isSidechain: Bool?
        let message: Message?
    }

    private struct Message: Decodable {
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let cacheRead: Int?
        let cacheWritten: Int?
        let cacheCreation: Creation?

        enum CodingKeys: String, CodingKey {
            case cacheRead = "cache_read_input_tokens"
            case cacheWritten = "cache_creation_input_tokens"
            case cacheCreation = "cache_creation"
        }
    }

    private struct Creation: Decodable {
        let hour: Int?
        let fiveMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case hour = "ephemeral_1h_input_tokens"
            case fiveMinutes = "ephemeral_5m_input_tokens"
        }
    }
}
