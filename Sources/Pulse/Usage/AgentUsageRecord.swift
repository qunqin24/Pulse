import Foundation

/// One **incremental** piece of work an agent's store recorded.
///
/// **Incremental, not cumulative.** A parser that reads a running total or a
/// snapshot is responsible for differencing it against the previous reading
/// before handing records over — the builder adds every record up as written
/// and does no product-specific arithmetic.
///
/// **A record's tokens have two parts.** `tally` is the work split into the
/// four kinds a price list can bill. `unclassifiedTokens` is real work the
/// source did not break down — a bare total, or a session total — which is
/// counted and never priced. A bare total is `tally()` with all of its count
/// here; it is **never** put into the input bucket, because that would report
/// fresh input nobody measured.
///
/// **Aggregate timing is declared.** `isAggregate` marks a record whose only
/// time is session- or report-level. It still lands on its real calendar day,
/// but its hour is unknown, so it never enters an hour profile.
///
/// The optional metadata is **explicit**: a session only exists where the
/// store named one, and a title or project is only ever what the store
/// stated, never something guessed from a path. `deduplicationID` is the
/// product's own identity for a message, used to fold one message that two
/// roots both contain down to one.
struct AgentUsageRecord: Sendable {
    let timestamp: Date
    let model: String
    /// The work that was split into the four priced kinds. Empty when nothing
    /// was classified — the bare-total case carries its count in
    /// `unclassifiedTokens` instead.
    let tally: TokenTally
    var sessionID: String? = nil
    var sessionName: String? = nil
    var title: String? = nil
    var project: String? = nil
    var deduplicationID: String? = nil
    /// Real tokens that could not be placed in any of the four kinds.
    ///
    /// **Not a second copy of the reported total.** The caller passes only the
    /// remainder after subtracting every kind it could identify. This is added
    /// to the four kinds to make the record's total; it is never placed inside
    /// `tally` and it never produces a cost. A negative value — in this field
    /// or in any kind — makes the record broken data, and the builder **skips
    /// the record** rather than clamping it to zero.
    var unclassifiedTokens: Int = 0
    /// True when only session- or report-level timing is known.
    ///
    /// An aggregate record cannot be placed in a quarter-hour bucket, so it is
    /// excluded from the hour profile. Its session retains calendar-day
    /// buckets for span filtering, but no quarter-hour series.
    var isAggregate: Bool = false
    /// True when the source could not prove the report was complete.
    ///
    /// Some stores cannot say whether reasoning or cache tokens are already
    /// folded into another figure they report, so the counts Pulse can read are
    /// kept exactly but may be short of the real work. This marks that doubt so
    /// a summary can say "partial" instead of under-reporting silently. It is
    /// **never** used to invent a remainder: no tokens are added or guessed
    /// from it, and it changes no price.
    var isPartial: Bool = false
}

/// Turns decoded records into the same `UsageLedger` every other reader makes.
///
/// **One pricing path, not another.** The classified kinds are bucketed with
/// the shared `UsageLedgerReader.slotKey` and priced by `UsageLedgerReader.price`,
/// and a session's cost and quarter-hours go through `TokenTally.cost` and
/// `UsageLedgerReader.sessionSlots` exactly as a transcript's do. Two ways of
/// turning tokens into dollars in one app is two figures that eventually
/// disagree.
enum AgentUsageLedger {
    /// Adds records up over a namespace.
    ///
    /// `namespace` prefixes every session id (`agent.rawValue`, say) so the
    /// same session id written by two agents cannot collide. Records with an
    /// explicit `deduplicationID` are counted **once globally**, which is what
    /// folds a message present in more than one of an agent's roots; a record
    /// with none is kept every time. Records are never deduplicated by equal
    /// timestamp, model or tally — two identical requests are two requests.
    ///
    /// A record's total is its four kinds plus `unclassifiedTokens`, added
    /// with checked arithmetic, and it is kept when that is positive. A record
    /// whose kinds or remainder are negative, or whose total does not fit an
    /// `Int`, is broken and is skipped whole; a total that would overflow the
    /// ledger's own running sum excludes that record too, so no bucket or
    /// session is ever saturated to a fabricated `Int.max`. Unclassified
    /// tokens count in the day, the model, the session and the unpriced figure,
    /// and are listed per raw id so a summary can tell them from a broken
    /// split; they are never turned into a kind and never costed. An empty
    /// model is skipped, and a record with no `sessionID` creates no session
    /// row rather than a fabricated one.
    ///
    /// `origin` says where the records came from; `.importedRecords` for a
    /// capture or another tool's store, the default for a built-in reader.
    static func build(
        _ records: [AgentUsageRecord],
        prices: [String: ModelPrice],
        namespace: String,
        /// The plan vendor to fall back to for a model no first-party provider
        /// publishes. See `SpendAgent.priceVendor`.
        vendor: String? = nil,
        calendar: Calendar = .current,
        origin: UsageLedger.Origin = .localTranscripts
    ) -> UsageLedger {
        // Classified kinds of every record: what the shared pricing pass turns
        // into days, names and money.
        var knownBuckets: [String: [String: TokenTally]] = [:]
        // Classified kinds of non-aggregate records only: the only ones that
        // may become quarter-hour slots.
        var eventBuckets: [String: [String: TokenTally]] = [:]
        var eventUnknown: [String: [String: Int]] = [:]
        var dayUnknown: [Date: [String: Int]] = [:]

        var seen: Set<String> = []
        var sessions: [String: Running] = [:]
        var hasAggregateTiming = false
        // Set only by an **accepted** record: a record that was skipped whole
        // contributes nothing, so it cannot make the ledger look partial.
        var hasPartialCounts = false
        // Every raw id that was accepted, so a name or an "unpriced" note can
        // be attached to one that never reached the pricing pass.
        var acceptedModels: Set<String> = []
        // The running total of every accepted record. Checked, so a hostile
        // count cannot carry it past `Int.max` — and because every bucket and
        // session below is a subset of this bounded total, none of that
        // arithmetic needs a saturating guard of its own.
        var acceptedTotal = 0

        for record in records {
            guard !Task.isCancelled else { return .empty }
            guard let model = Self.nonBlank(record.model) else { continue }

            // **Every count is a real, non-negative one that fits an `Int`.**
            // The four kinds and the unclassified remainder are added with
            // checked arithmetic *before* anything else looks at them, so a
            // negative kind, a negative remainder or an overflowing record
            // total is broken data: the record is skipped whole and the rest
            // of the run is kept. A negative remainder is not clamped to zero
            // and an overflow is not saturated to `Int.max` — either would
            // fabricate a reading.
            let tally = record.tally
            let known = Self.checkedTotal([
                tally.input, tally.cacheWrite, tally.cacheRead, tally.output
            ])
            let total = known.flatMap { Self.checkedTotal([$0, record.unclassifiedTokens]) }
            guard let known, let total, total > 0 else { continue }

            // Only an explicit identity folds a message; everything else is a
            // separate request even when it looks identical. A blank id is no
            // identity, so a run of them is not folded into one.
            if let deduplicationID = Self.nonBlank(record.deduplicationID) {
                guard seen.insert(deduplicationID).inserted else { continue }
            }

            // A record that would push the ledger's own total past what an
            // `Int` can hold is not added, so no later group sum can trap.
            guard let runningTotal = Self.checkedTotal([acceptedTotal, total]) else { continue }
            acceptedTotal = runningTotal
            acceptedModels.insert(model)

            let extra = record.unclassifiedTokens
            let key = UsageLedgerReader.slotKey(for: record.timestamp)
            guard let day = Self.day(for: key, calendar: calendar) else { continue }
            if known > 0 {
                knownBuckets[key, default: [:]][model] =
                    (knownBuckets[key]?[model] ?? TokenTally()) + tally
                if !record.isAggregate {
                    eventBuckets[key, default: [:]][model] =
                        (eventBuckets[key]?[model] ?? TokenTally()) + tally
                }
            }
            if extra > 0 {
                dayUnknown[day, default: [:]][model, default: 0] += extra
                if !record.isAggregate {
                    eventUnknown[key, default: [:]][model, default: 0] += extra
                }
            }

            if record.isAggregate { hasAggregateTiming = true }
            if record.isPartial { hasPartialCounts = true }

            // A blank session id names no session, but the record's tokens
            // still count toward the totals and the models.
            guard let sessionID = Self.nonBlank(record.sessionID) else { continue }

            let money = known > 0
                ? (ModelPrices.price(for: model, in: prices, vendor: vendor).map { record.tally.cost(at: $0) } ?? 0)
                : 0
            let name = Self.nonBlank(record.sessionName)
            let title = Self.nonBlank(record.title)
            let project = UsageProject(record.project)

            if var running = sessions[sessionID] {
                running.tokens = running.tokens + total
                running.cost += money
                running.start = min(running.start, record.timestamp)
                running.end = max(running.end, record.timestamp)
                if running.name == nil { running.name = name }
                if running.title == nil { running.title = title }
                if running.project == nil { running.project = project }
                running.addDay(tokens: total, cost: money, on: day)
                if record.isAggregate {
                    running.hasAggregate = true
                } else {
                    running.add(tokens: total, cost: money, at: key)
                }
                sessions[sessionID] = running
            } else {
                var running = Running(
                    tokens: total,
                    cost: money,
                    start: record.timestamp,
                    end: record.timestamp,
                    name: name,
                    title: title,
                    project: project,
                    hasAggregate: record.isAggregate
                )
                running.addDay(tokens: total, cost: money, on: day)
                if !record.isAggregate { running.add(tokens: total, cost: money, at: key) }
                sessions[sessionID] = running
            }
        }

        // Nothing written at all is `.empty`, not a zero-shaped ledger.
        // Unclassified-only records still count, so both maps are checked.
        guard !knownBuckets.isEmpty || !dayUnknown.isEmpty else { return .empty }

        var ledger = UsageLedgerReader.price(knownBuckets, with: prices, calendar: calendar, vendor: vendor)

        // **A raw id seen only as unclassified tokens still has a published
        // name.** It never reaches the pricing pass, so without this its
        // display name is lost and the same model splits into two rows — one
        // under its name from a record that did classify, one under its raw id
        // from a record that did not. Looking up the name is not pricing it: an
        // unknown-only id keeps `nil` money, and an id with no rate at all is
        // named as unpriced. A raw id that *has* a price and only unclassified
        // tokens must never be listed as having "no published price".
        var unpriced = Set(ledger.unpricedModels)
        for model in acceptedModels {
            if let price = ModelPrices.price(for: model, in: prices, vendor: vendor) {
                if let name = price.name { ledger.modelNames[model] = name }
            } else {
                unpriced.insert(model)
            }
        }
        ledger.unpricedModels = unpriced.sorted()

        // Slots: events only, with their unclassified tokens added to the
        // bucket they landed in — never to a model's known tally, so a model's
        // hours stop reconciling and go nil rather than borrowing the count.
        var slotByStart: [Date: UsageLedger.Slot] = [:]
        for slot in UsageLedgerReader.price(eventBuckets, with: prices, calendar: calendar, vendor: vendor).slots {
            slotByStart[slot.start] = slot
        }
        for (key, models) in eventUnknown {
            guard let start = UsageLedgerReader.sharedSlotFormatter.date(from: key) else { continue }
            let extra = models.values.reduce(0, +)
            let slot = slotByStart[start] ?? UsageLedger.Slot(start: start, tokens: 0, cost: 0)
            slotByStart[start] = UsageLedger.Slot(
                start: slot.start, tokens: slot.tokens + extra, cost: slot.cost, models: slot.models
            )
        }
        ledger.slots = slotByStart.values.sorted { $0.start < $1.start }

        // Days: the classified rollup, then unclassified tokens layered on. A
        // day that only has unclassified tokens is created rather than dropped.
        var dayByDate: [Date: LedgerDay] = [:]
        for day in ledger.days { dayByDate[day.date] = day }
        for (date, models) in dayUnknown {
            let base = dayByDate[date]
                ?? LedgerDay(date: date, tokens: 0, cost: 0, unpricedTokens: 0, models: [:])
            var mergedModels = base.models
            var mergedUnclassified = base.modelUnclassifiedTokens
            var extra = 0
            for (model, count) in models {
                mergedModels[model] = (mergedModels[model] ?? 0) + count
                mergedUnclassified[model] = (mergedUnclassified[model] ?? 0) + count
                extra += count
            }
            dayByDate[date] = LedgerDay(
                date: base.date,
                tokens: base.tokens + extra,
                cost: base.cost,
                unpricedTokens: base.unpricedTokens + extra,
                models: mergedModels,
                tally: base.tally,
                modelTallies: base.modelTallies,
                modelCosts: base.modelCosts,
                modelUnclassifiedTokens: mergedUnclassified
            )
        }

        guard let first = dayByDate.keys.min(), let last = dayByDate.keys.max() else { return .empty }
        var days: [LedgerDay] = []
        var cursor = first
        while cursor <= last {
            days.append(
                dayByDate[cursor]
                    ?? LedgerDay(date: cursor, tokens: 0, cost: 0, unpricedTokens: 0, models: [:])
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        ledger.days = days
        ledger.earliest = first
        ledger.hasAggregateTiming = hasAggregateTiming
        ledger.hasPartialCounts = hasPartialCounts
        ledger.origin = origin
        ledger.sessions = sessions
            .map { id, running in
                UsageLedger.Session(
                    // Prefixed, so the same id two agents both wrote is still
                    // two sessions.
                    id: "\(namespace)#\(id)",
                    // The id is an identity, not invented metadata; it is the
                    // same fallback the readers that know a slug use.
                    name: running.name ?? id,
                    title: running.title,
                    project: running.project,
                    start: running.start,
                    end: running.end,
                    tokens: running.tokens,
                    cost: running.cost,
                    // Aggregate timing withholds hours, not known dates. Day
                    // buckets keep a resumed session inside the selected span.
                    slots: running.hasAggregate ? [] : UsageLedgerReader.sessionSlots(running.slots),
                    days: running.days.map { date, totals in
                        .init(date: date, tokens: totals.tokens, cost: totals.cost)
                    }.sorted { $0.date < $1.date }
                )
            }
            .sorted { $0.end > $1.end }

        return ledger
    }

    /// A string that is only whitespace is absent, not a shared key.
    ///
    /// A non-blank value is returned unchanged, so an explicit identity still
    /// folds exactly as written and no two distinct ids are quietly merged.
    private static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    /// The calendar day a slot key falls on, exactly as the shared pricing
    /// pass would group it.
    private static func day(for key: String, calendar: Calendar) -> Date? {
        guard let start = UsageLedgerReader.sharedSlotFormatter.date(from: key) else { return nil }
        return calendar.startOfDay(for: start)
    }

    /// The checked sum of a record's counts, or nil when any is negative or
    /// the total would overflow.
    ///
    /// **The only place a count is checked.** Once a record is accepted its
    /// total is part of a running total bounded by `Int.max`, so every bucket,
    /// session and day below is a sum of non-negative pieces no larger than
    /// that and cannot overflow. That is why the grouping arithmetic uses
    /// plain `+`: there is no invariant to assert, only a proof.
    private static func checkedTotal(_ values: [Int]) -> Int? {
        var total = 0
        for value in values {
            guard value >= 0 else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }

    /// One session as it is accumulated.
    private struct Running {
        var tokens: Int
        var cost: Double
        var start: Date
        var end: Date
        var name: String?
        var title: String?
        var project: UsageProject?
        var hasAggregate: Bool
        var slots: [String: (tokens: Int, cost: Double)] = [:]
        var days: [Date: (tokens: Int, cost: Double)] = [:]

        mutating func addDay(tokens count: Int, cost money: Double, on day: Date) {
            var total = days[day] ?? (tokens: 0, cost: 0)
            total.tokens += count
            total.cost += money
            days[day] = total
        }

        mutating func add(tokens count: Int, cost money: Double, at key: String) {
            var slot = slots[key] ?? (tokens: 0, cost: 0)
            slot.tokens = slot.tokens + count
            slot.cost += money
            slots[key] = slot
        }
    }
}
