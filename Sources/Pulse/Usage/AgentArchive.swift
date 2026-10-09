// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The most of each quarter-hour and day Pulse has seen an agent's store
/// hold, so a store that deletes its old records does not take them out of
/// Token spend and the recaps.
///
/// **Why a high-water mark and not a list of files.** `TranscriptArchive`
/// keeps Claude Code's and Codex's transcripts file by file, because their
/// reader counts file by file. The agents behind `AgentCache` are read from
/// whole stores into one ledger — fifty readers, half of them databases — and
/// nothing says which file a figure came from. What can be said is that a
/// past quarter-hour's work only ever grows while the readers are the same:
/// a record appended, a session written. When a later read holds less, the
/// store has lost records, and the difference is what Pulse keeps. So every
/// stable read raises the marks — per quarter-hour and raw model, per day for
/// what has no quarter-hour, kind by kind — and the ledger shown is the live
/// one plus whatever the marks hold beyond it.
///
/// **A copy is not counted twice.** A message the store holds in two places
/// is folded to one by the reader (`deduplicationID`), so deleting either
/// leaves the quarter-hour where it was and nothing is added.
///
/// **What it gets wrong, and which way.** Work added to a past quarter-hour
/// after other work there was deleted — an import of old records, say — is
/// hidden under the mark until the live figure passes it: short, never
/// double. A record whose time a store rewrites to another quarter-hour is
/// counted at both. A session still in the store with part of its work gone
/// keeps its row as read; the lost part is in the days but not in the row.
///
/// **Only a stable read raises the marks** (`AgentLedgers.canPersist`): a
/// store half-written while it was read, or one the reader could decode only
/// in part, shows the marks over it and changes none of them.
///
/// **The marks are only comparable under the same readers.** `readings` is
/// the `AgentCache.version` they were taken under; a new version means the
/// readers count differently — usually less, a fix, sometimes under another
/// model id — so marks from before it stand only for a day the new readers
/// see nothing at all on, the case of a store that has since deleted it.
///
/// **Quarter-hours are kept by instant, days by the zone they were cut in.**
/// A quarter-hour is a moment, so its key is its UTC quarter index and a
/// change of time zone moves nothing. A day is local: the day marks remember
/// their zone, and after a change each is moved to the new zone's day that
/// holds its noon and kept only where the live ledger has nothing on that day
/// or either neighbour — keyed by local strings, every mark would have been
/// added again on top of the same work read under the new zone.
///
/// **Its own file, unnumbered** (`archive-agent-<agent>.json`), never
/// superseded with the `agent-<n>-*` cache: that is rebuilt from the stores,
/// this from nothing.
struct AgentArchive: Codable, Equatable {
    static let currentFormat = 1

    var format = AgentArchive.currentFormat
    /// The `AgentCache.version` the marks were taken under.
    var readings = AgentCache.version
    /// The time zone the day marks were cut in.
    var timeZone = AgentArchive.zone
    /// Classified tokens by quarter-hour — its UTC quarter index since 1970 —
    /// and then raw model id.
    var slots: [String: [String: TokenTally]] = [:]
    /// Each quarter-hour's unclassified tokens, which a slot keeps without a
    /// model.
    var slotExtra: [String: Int] = [:]
    /// Classified tokens of a day and model that sit in no quarter-hour —
    /// aggregate records — by local day (`yyyy-MM-dd`, in `timeZone`).
    var dayRest: [String: [String: TokenTally]] = [:]
    /// Unclassified tokens by local day and raw model id.
    var dayUnclassified: [String: [String: Int]] = [:]
    var hasAggregateTiming = false
    var hasPartialCounts = false
    var origin: UsageLedger.Origin?
    /// Sessions a stable read had and a later one did not, as they last
    /// read. Their money is kept as it was priced then.
    var sessions: [String: AgentCache.StoredSession] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case format, readings, timeZone, slots, slotExtra, dayRest, dayUnclassified
        case hasAggregateTiming, hasPartialCounts, origin, sessions
    }

    /// Every field optional on the way in, so a field added later does not
    /// make the whole archive unreadable — which would drop the history.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(Int.self, forKey: .format) ?? Self.currentFormat
        readings = try container.decodeIfPresent(Int.self, forKey: .readings) ?? AgentCache.version
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone) ?? Self.zone
        slots = try container.decodeIfPresent([String: [String: TokenTally]].self, forKey: .slots) ?? [:]
        slotExtra = try container.decodeIfPresent([String: Int].self, forKey: .slotExtra) ?? [:]
        dayRest = try container.decodeIfPresent([String: [String: TokenTally]].self, forKey: .dayRest) ?? [:]
        dayUnclassified = try container.decodeIfPresent([String: [String: Int]].self, forKey: .dayUnclassified) ?? [:]
        hasAggregateTiming = try container.decodeIfPresent(Bool.self, forKey: .hasAggregateTiming) ?? false
        hasPartialCounts = try container.decodeIfPresent(Bool.self, forKey: .hasPartialCounts) ?? false
        origin = try container.decodeIfPresent(UsageLedger.Origin.self, forKey: .origin)
        sessions = try container.decodeIfPresent([String: AgentCache.StoredSession].self, forKey: .sessions) ?? [:]
    }

    /// Whether an agent's history is kept this way. **Not Devin Desktop**:
    /// its records are counted only where they do not mirror Devin CLI's
    /// databases, so rows the CLI deletes would come back under Desktop while
    /// the CLI's marks still held them — counted twice.
    static func keeps(_ agent: SpendAgent) -> Bool { agent != .devinDesktop }

    // MARK: - Storage

    /// The archive, an empty one when there is none yet, or **nil when a file
    /// is there and cannot be read** — damaged, or written by a later build —
    /// which must then be neither used nor overwritten.
    static func load(for agent: SpendAgent, directory: URL) -> AgentArchive? {
        let url = file(for: agent, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return AgentArchive() }
        guard
            let data = try? Data(contentsOf: url),
            let archive = try? JSONDecoder().decode(AgentArchive.self, from: data),
            archive.format <= currentFormat
        else { return nil }
        return archive
    }

    func save(for agent: SpendAgent, directory: URL) {
        guard !Task.isCancelled, let data = try? JSONEncoder().encode(self) else { return }
        if directory == PulseStorage.directory { PulseStorage.prepare() }
        try? data.write(to: Self.file(for: agent, directory: directory), options: .atomic)
    }

    static func file(for agent: SpendAgent, directory: URL) -> URL {
        directory.appending(path: "archive-agent-\(agent.rawValue).json")
    }

    // MARK: - Raising the marks

    /// Raises the marks to a stable read — and to the stable read before it,
    /// whose sessions missing now are kept. Returns whether anything moved.
    mutating func absorb(_ live: UsageLedger, previous: UsageLedger? = nil) -> Bool {
        let now = Marks(live)
        var next = aligned(to: now)
        if let previous { next.raise(to: Marks(previous)) }
        next.raise(to: now)
        if !live.days.isEmpty {
            next.origin = live.origin
            next.hasAggregateTiming = next.hasAggregateTiming || live.hasAggregateTiming
            next.hasPartialCounts = next.hasPartialCounts || live.hasPartialCounts
        }

        let liveIDs = Set(live.sessions.map(\.id))
        for session in previous?.sessions ?? [] where !liveIDs.contains(session.id) {
            next.sessions[session.id] = AgentCache.StoredSession(session)
        }
        for id in liveIDs { next.sessions[id] = nil }

        guard next != self else { return false }
        self = next
        return true
    }

    private mutating func raise(to marks: Marks) {
        for (key, models) in marks.slots {
            for (model, tally) in models { slots[key, default: [:]][model] = slots[key]?[model]?.highest(tally) ?? tally }
        }
        for (key, extra) in marks.slotExtra { slotExtra[key] = max(slotExtra[key] ?? 0, extra) }
        for (day, models) in marks.dayRest {
            for (model, tally) in models { dayRest[day, default: [:]][model] = dayRest[day]?[model]?.highest(tally) ?? tally }
        }
        for (day, models) in marks.dayUnclassified {
            for (model, count) in models { dayUnclassified[day, default: [:]][model] = max(dayUnclassified[day]?[model] ?? 0, count) }
        }
    }

    /// The marks made comparable with a live ledger read now: day marks moved
    /// into this zone, and marks from other readers cut to the days the live
    /// ledger has nothing on. Applied before raising **and** before showing,
    /// so a read too unsettled to raise anything shows no stale mark either.
    func aligned(to live: Marks) -> AgentArchive {
        var next = self
        let seen = live.days
        if next.timeZone != Self.zone {
            let old = TimeZone(identifier: next.timeZone) ?? .current
            let move = { (day: String) -> String? in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = old
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                return formatter.date(from: "\(day) 12:00").map(Self.dayKey(for:))
            }
            let quiet = { (day: String) -> Bool in
                guard let date = Self.date(ofDay: day, calendar: .current) else { return false }
                return [-1, 0, 1].allSatisfy { offset in
                    Calendar.current.date(byAdding: .day, value: offset, to: date).map { !seen.contains(Self.dayKey(for: $0)) } ?? true
                }
            }
            var rest: [String: [String: TokenTally]] = [:]
            for (day, models) in next.dayRest {
                guard let moved = move(day), quiet(moved) else { continue }
                for (model, tally) in models { rest[moved, default: [:]][model] = rest[moved]?[model]?.highest(tally) ?? tally }
            }
            var unclassified: [String: [String: Int]] = [:]
            for (day, models) in next.dayUnclassified {
                guard let moved = move(day), quiet(moved) else { continue }
                for (model, count) in models { unclassified[moved, default: [:]][model] = max(unclassified[moved]?[model] ?? 0, count) }
            }
            next.dayRest = rest
            next.dayUnclassified = unclassified
            next.timeZone = Self.zone
        }
        if next.readings != AgentCache.version {
            next.slots = next.slots.filter { !seen.contains(Self.day(ofSlot: $0.key)) }
            next.slotExtra = next.slotExtra.filter { !seen.contains(Self.day(ofSlot: $0.key)) }
            next.dayRest = next.dayRest.filter { !seen.contains($0.key) }
            next.dayUnclassified = next.dayUnclassified.filter { !seen.contains($0.key) }
            // What the old readers flagged is not the new ones' to answer for.
            next.hasAggregateTiming = false
            next.hasPartialCounts = false
            next.readings = AgentCache.version
        }
        return next
    }

    // MARK: - Showing what was kept

    /// The live ledger with what the marks hold beyond it added in — priced
    /// now, at today's rates — and the kept sessions that the added work can
    /// account for. The live ledger itself when the marks hold nothing more.
    func merged(
        into live: UsageLedger,
        prices: [String: ModelPrice],
        vendor: String? = nil,
        calendar: Calendar = .current
    ) -> UsageLedger {
        let now = Marks(live)
        let marks = aligned(to: now)

        var events: [String: [String: TokenTally]] = [:]
        for (key, models) in marks.slots {
            guard let start = Self.start(ofSlot: key) else { continue }
            for (model, high) in models {
                let more = high.beyond(now.slots[key]?[model] ?? TokenTally())
                if more.total > 0 { events[UsageLedgerReader.slotKey(for: start), default: [:]][model] = more }
            }
        }
        var extras: [Date: Int] = [:]
        for (key, high) in marks.slotExtra where high > now.slotExtra[key] ?? 0 {
            guard let start = Self.start(ofSlot: key) else { continue }
            extras[start] = high - (now.slotExtra[key] ?? 0)
        }
        // Priced as quarter-hours at the day's midnight, so the shared pricing
        // pass places them on their day; their slots are not used.
        var rest: [String: [String: TokenTally]] = [:]
        for (day, models) in marks.dayRest {
            for (model, high) in models {
                let more = high.beyond(now.dayRest[day]?[model] ?? TokenTally())
                if more.total > 0 { rest["\(day) 00:00", default: [:]][model] = more }
            }
        }
        var unclassified: [String: [String: Int]] = [:]
        for (day, models) in marks.dayUnclassified {
            for (model, high) in models where high > now.dayUnclassified[day]?[model] ?? 0 {
                unclassified[day, default: [:]][model] = high - (now.dayUnclassified[day]?[model] ?? 0)
            }
        }
        guard !events.isEmpty || !extras.isEmpty || !rest.isEmpty || !unclassified.isEmpty else { return live }

        let pricedEvents = UsageLedgerReader.price(events, with: prices, calendar: calendar, vendor: vendor)
        let pricedRest = UsageLedgerReader.price(rest, with: prices, calendar: calendar, vendor: vendor)

        var days: [Date: LedgerDay] = [:]
        for day in live.days { days[calendar.startOfDay(for: day.date)] = day }
        var room: [Date: Int] = [:]
        for day in pricedEvents.days + pricedRest.days where day.tokens > 0 {
            let date = calendar.startOfDay(for: day.date)
            days[date] = Self.combine(days[date], day)
            room[date, default: 0] += day.tokens
        }
        var names = live.modelNames.merging(pricedEvents.modelNames) { kept, _ in kept }
            .merging(pricedRest.modelNames) { kept, _ in kept }
        var unpriced = Set(live.unpricedModels).union(pricedEvents.unpricedModels).union(pricedRest.unpricedModels)
        var lookup = ModelPriceLookup(prices)
        for (key, models) in unclassified {
            guard let date = Self.date(ofDay: key, calendar: calendar) else { continue }
            let count = models.values.reduce(0, +)
            let added = LedgerDay(
                date: date, tokens: count, cost: 0, unpricedTokens: count, models: models,
                modelUnclassifiedTokens: models
            )
            days[date] = Self.combine(days[date], added)
            room[date, default: 0] += count
            // Named where the price list names it; never priced.
            for model in models.keys {
                if let price = lookup.price(for: model, vendor: vendor) {
                    if names[model] == nil, let name = price.name { names[model] = name }
                } else {
                    unpriced.insert(model)
                }
            }
        }

        var slotsByStart: [Date: UsageLedger.Slot] = [:]
        for slot in live.slots { slotsByStart[slot.start] = slot }
        for slot in pricedEvents.slots { slotsByStart[slot.start] = Self.combine(slotsByStart[slot.start], slot) }
        for (start, extra) in extras {
            let added = UsageLedger.Slot(start: start, tokens: extra, cost: 0, unpricedTokens: extra)
            slotsByStart[start] = Self.combine(slotsByStart[start], added)
        }

        var merged = live
        merged.days = Self.calendarDays(days, calendar: calendar)
        merged.earliest = merged.days.first?.date
        merged.slots = slotsByStart.values.sorted { $0.start < $1.start }
        merged.modelNames = names
        merged.unpricedModels = unpriced.sorted()
        // Hours are withheld only when what was added has no hour of its own.
        merged.hasAggregateTiming = live.hasAggregateTiming
            || marks.hasAggregateTiming && (!rest.isEmpty || !unclassified.isEmpty)
        merged.hasPartialCounts = live.hasPartialCounts || marks.hasPartialCounts
        if live.days.isEmpty, let origin = marks.origin { merged.origin = origin }
        merged.sessions = (live.sessions + marks.keptSessions(within: room, live: live, calendar: calendar))
            .sorted { $0.end > $1.end }
        return merged
    }

    /// The kept sessions whose work the added days can hold, oldest first.
    ///
    /// **A session is shown only if the tokens it lost are still lost.** When
    /// the store folded a deleted session's messages into another one that is
    /// still there, the days have nothing added for them, and showing the old
    /// row as well would count a project's work twice.
    private func keptSessions(within room: [Date: Int], live: UsageLedger, calendar: Calendar) -> [UsageLedger.Session] {
        var room = room
        let liveIDs = Set(live.sessions.map(\.id))
        var kept: [UsageLedger.Session] = []
        let ordered = sessions.values.sorted { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }
        for stored in ordered where !liveIDs.contains(stored.id) {
            let session = stored.session
            var byDay: [Date: Int] = [:]
            if !session.days.isEmpty {
                for day in session.days { byDay[calendar.startOfDay(for: day.date), default: 0] += day.tokens }
            } else if !session.slots.isEmpty {
                for slot in session.slots { byDay[calendar.startOfDay(for: slot.start), default: 0] += slot.tokens }
            } else {
                byDay[calendar.startOfDay(for: session.start)] = session.tokens
            }
            guard byDay.allSatisfy({ room[$0.key, default: 0] >= $0.value }) else { continue }
            for (day, tokens) in byDay { room[day, default: 0] -= tokens }
            kept.append(session)
        }
        return kept
    }

    // MARK: - Helpers

    /// One ledger in the archive's terms.
    struct Marks {
        var slots: [String: [String: TokenTally]] = [:]
        var slotExtra: [String: Int] = [:]
        var dayRest: [String: [String: TokenTally]] = [:]
        var dayUnclassified: [String: [String: Int]] = [:]

        init(_ ledger: UsageLedger) {
            var inSlots: [String: [String: TokenTally]] = [:]
            for slot in ledger.slots {
                let key = AgentArchive.slotKey(for: slot.start)
                let day = AgentArchive.dayKey(for: slot.start)
                var classified = 0
                for (model, tally) in slot.models {
                    slots[key, default: [:]][model] = (slots[key]?[model] ?? TokenTally()) + tally
                    inSlots[day, default: [:]][model] = (inSlots[day]?[model] ?? TokenTally()) + tally
                    classified += tally.total
                }
                if slot.tokens > classified { slotExtra[key, default: 0] += slot.tokens - classified }
            }
            for day in ledger.days {
                let key = AgentArchive.dayKey(for: day.date)
                for (model, tally) in day.modelTallies {
                    let rest = tally.beyond(inSlots[key]?[model] ?? TokenTally())
                    if rest.total > 0 { dayRest[key, default: [:]][model] = rest }
                }
                for (model, count) in day.modelUnclassifiedTokens where count > 0 {
                    dayUnclassified[key, default: [:]][model] = count
                }
            }
        }

        /// The local days with any work.
        var days: Set<String> {
            Set(slots.keys.map(AgentArchive.day(ofSlot:)))
                .union(slotExtra.keys.map(AgentArchive.day(ofSlot:)))
                .union(dayRest.keys).union(dayUnclassified.keys)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(for date: Date) -> String { dayFormatter.string(from: date) }

    /// The zone the day keys are cut in now.
    static var zone: String { dayFormatter.timeZone.identifier }

    /// A quarter-hour's key: its UTC quarter index since 1970.
    static func slotKey(for start: Date) -> String {
        String(Int((start.timeIntervalSince1970 / (15 * 60)).rounded(.down)))
    }

    static func start(ofSlot key: String) -> Date? {
        Int(key).map { Date(timeIntervalSince1970: Double($0) * 15 * 60) }
    }

    /// A quarter-hour's local day now.
    static func day(ofSlot key: String) -> String { start(ofSlot: key).map(dayKey(for:)) ?? key }

    private static func date(ofDay key: String, calendar: Calendar) -> Date? {
        UsageLedgerReader.sharedSlotFormatter.date(from: "\(key) 00:00").map { calendar.startOfDay(for: $0) }
    }

    private static func combine(_ base: LedgerDay?, _ added: LedgerDay) -> LedgerDay {
        guard let base else { return added }
        return LedgerDay(
            date: base.date,
            tokens: base.tokens + added.tokens,
            cost: base.cost + added.cost,
            unpricedTokens: base.unpricedTokens + added.unpricedTokens,
            models: base.models.merging(added.models, uniquingKeysWith: +),
            tally: base.tally + added.tally,
            modelTallies: base.modelTallies.merging(added.modelTallies, uniquingKeysWith: +),
            modelCosts: base.modelCosts.merging(added.modelCosts, uniquingKeysWith: +),
            modelUnclassifiedTokens: base.modelUnclassifiedTokens.merging(added.modelUnclassifiedTokens, uniquingKeysWith: +)
        )
    }

    private static func combine(_ base: UsageLedger.Slot?, _ added: UsageLedger.Slot) -> UsageLedger.Slot {
        guard let base else { return added }
        return UsageLedger.Slot(
            start: base.start,
            tokens: base.tokens + added.tokens,
            cost: base.cost + added.cost,
            unpricedTokens: base.unpricedTokens + added.unpricedTokens,
            models: base.models.merging(added.models, uniquingKeysWith: +),
            timings: base.timings
        )
    }

    /// Ascending, with the quiet days between filled in, as every ledger's
    /// days are.
    private static func calendarDays(_ days: [Date: LedgerDay], calendar: Calendar) -> [LedgerDay] {
        guard let first = days.keys.min(), let last = days.keys.max() else { return [] }
        var filled: [LedgerDay] = []
        var cursor = first
        while cursor <= last {
            filled.append(days[cursor] ?? LedgerDay(date: cursor, tokens: 0, cost: 0, unpricedTokens: 0, models: [:]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = calendar.startOfDay(for: next)
        }
        return filled
    }
}

extension TokenTally {
    /// Each kind at the larger of the two: the most of it either held.
    func highest(_ other: TokenTally) -> TokenTally {
        TokenTally(
            input: max(input, other.input),
            cacheWrite: max(cacheWrite, other.cacheWrite),
            cacheRead: max(cacheRead, other.cacheRead),
            output: max(output, other.output),
            cacheWrite1h: max(cacheWrite1h, other.cacheWrite1h),
            repliesWithoutCacheFields: max(repliesWithoutCacheFields, other.repliesWithoutCacheFields),
            contextBands: contextBands.merging(other.contextBands) { $0.highest($1) }
        )
    }

    /// What this holds beyond another tally, kind by kind and never below
    /// zero.
    func beyond(_ other: TokenTally) -> TokenTally {
        var bands: [Int: TokenTally] = [:]
        for (band, tally) in contextBands {
            let more = tally.beyond(other.contextBands[band] ?? TokenTally())
            if more.total > 0 { bands[band] = more }
        }
        return TokenTally(
            input: max(input - other.input, 0),
            cacheWrite: max(cacheWrite - other.cacheWrite, 0),
            cacheRead: max(cacheRead - other.cacheRead, 0),
            output: max(output - other.output, 0),
            cacheWrite1h: max(cacheWrite1h - other.cacheWrite1h, 0),
            repliesWithoutCacheFields: max(repliesWithoutCacheFields - other.repliesWithoutCacheFields, 0),
            contextBands: bands
        )
    }
}
