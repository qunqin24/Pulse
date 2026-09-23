import Foundation

/// The small arithmetic every structured-log reader shares: turning a decoded
/// usage object into one `AgentUsageRecord`, and the handful of number and
/// string helpers the formats disagree about.
///
/// **Nothing here invents a count.** A key that is missing or zero stays zero,
/// an unreadable line is skipped, and the only timestamp a record gets is one
/// the store actually wrote. A reader that cannot answer says so by emitting no
/// record rather than a zero.
enum StructuredLogSupport {
    /// Builds a record, or nil when it would say nothing.
    ///
    /// A blank model names nothing. A record whose tally and unclassified count
    /// are both empty has no tokens to report — neither is turned into a zero
    /// row. `unclassified` is the product's own reported tokens that Pulse's
    /// four kinds cannot hold (a bare total, or a reasoning count the format
    /// keeps apart); they are carried so the total is right without inventing a
    /// kind.
    static func record(
        timestamp: Date,
        model: String?,
        tally: TokenTally,
        unclassified: Int = 0,
        isAggregate: Bool = false,
        isPartial: Bool = false,
        sessionID: String? = nil,
        sessionName: String? = nil,
        title: String? = nil,
        project: String? = nil,
        deduplicationID: String? = nil
    ) -> AgentUsageRecord? {
        guard let model = nonBlank(model) else { return nil }
        guard tally.total > 0 || unclassified > 0 else { return nil }
        // A real event time is strictly after the epoch. A zero here is a
        // store's "not set" that slipped through as 1970-01-01; it is not a
        // date anyone measured.
        guard timestamp.timeIntervalSince1970 > 0, timestamp.timeIntervalSince1970.isFinite else {
            return nil
        }
        return AgentUsageRecord(
            timestamp: timestamp,
            model: model,
            tally: tally,
            sessionID: nonBlank(sessionID),
            sessionName: nonBlank(sessionName),
            title: nonBlank(title),
            project: nonBlank(project),
            deduplicationID: nonBlank(deduplicationID),
            unclassifiedTokens: max(0, unclassified),
            isAggregate: isAggregate,
            isPartial: isPartial
        )
    }

    /// Trims, and reports whitespace-only as absent rather than as a value.
    static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A timestamp that is a **real event time**, or nil.
    ///
    /// These stores write an unset timestamp as `0` — Junie's `timestampMs`,
    /// Fx's `updated_at_ms`, a transcript's `time`, a message's `0` epoch — and
    /// reading that as 1970-01-01 would put work on a day no one did it. A
    /// value at or before the epoch, or one a `Date` cannot hold, is treated
    /// exactly like a missing key, so the caller's next real fallback field is
    /// tried. The clock and a file's modification date are never used to fill a
    /// gap.
    static func eventTime(_ value: Any?, milliseconds: Bool = false) -> Date? {
        guard let date = AgentLogIO.timestamp(value, milliseconds: milliseconds) else { return nil }
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds > 0 else { return nil }
        return date
    }

    /// The first named key that is present as a real count.
    static func count(_ container: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let value = AgentLogIO.count(container[key]) { return value }
        }
        return nil
    }

    /// The first named key that carries a **non-zero** count.
    ///
    /// Used where a format lists the same figure under several spellings and
    /// the first non-zero one is the reported value.
    static func positive(_ container: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let value = AgentLogIO.count(container[key]), value > 0 { return value }
        }
        return nil
    }

    /// The first non-zero value for `aliases` across `sources`, in order.
    ///
    /// This is the merge rule for stores that nest the same usage object under
    /// several names: each field is taken from the first source that recorded a
    /// non-zero value, so a zero in a higher-priority copy does not mask the
    /// real count in a lower one.
    static func merged(
        _ sources: [[String: Any]],
        _ aliases: [String]
    ) -> Int {
        for source in sources {
            for alias in aliases {
                if let value = AgentLogIO.count(source[alias]), value > 0 { return value }
            }
        }
        return 0
    }

    /// A nested object, e.g. `promptTokensDetails`.
    static func object(_ container: [String: Any], _ key: String) -> [String: Any]? {
        AgentLogIO.object(container[key])
    }

    /// A stable, non-cryptographic digest of a string, used only to name a
    /// record whose store left it anonymous. It is a fallback identity, not a
    /// checksum: two different strings colliding here would fold two records,
    /// which is why it is only used where no real id was written.
    static func hash(_ value: String) -> String {
        hash(Data(value.utf8))
    }

    /// The same digest over raw bytes, for a whole file compared against a
    /// mirror of itself.
    static func hash(_ data: Data) -> String {
        var digest: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            digest ^= UInt64(byte)
            digest &*= 0x0000_0100_0000_01b3
        }
        return String(digest, radix: 16)
    }

    /// A file's path, resolved so two spellings of one file share an identity.
    static func path(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    /// Keep the stated path or label intact until project identity is built.
    static func project(_ value: String?) -> String? {
        nonBlank(value)
    }

    /// The base directory an environment variable names, or nil.
    ///
    /// An empty or whitespace-only value is absent, not the current directory.
    static func directory(_ environment: [String: String], _ key: String) -> URL? {
        guard let raw = nonBlank(environment[key]) else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    /// An ISO 8601 chat id whose time separators were written as `-`, restored
    /// to a date.
    ///
    /// Only the `HH-MM-SS` after the `T` becomes `:`, so the date's own dashes
    /// are left alone. Nil when there is no `T` or the text is not a date.
    static func isoFromChatID(_ chatID: String) -> Date? {
        guard let marker = chatID.firstIndex(of: "T") else { return nil }
        let head = String(chatID[..<marker])
        let tail = chatID[chatID.index(after: marker)...].replacingOccurrences(of: "-", with: ":")
        return AgentLogIO.timestamp("\(head)T\(tail)")
    }

    /// Deduplicates a list of roots and URLs by resolved path, keeping order.
    static func unique(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    // MARK: - Reasoning against Pulse's output bucket

    /// How a store's separately reported reasoning count relates to its
    /// reported output.
    ///
    /// Pulse's `TokenTally.output` **already counts reasoning once**, so a
    /// reasoning figure is never simply added. The relationship has to be
    /// known before it is placed anywhere.
    enum Reasoning: Sendable {
        /// The store says reasoning is part of its output (a `completion` that
        /// carries `reasoning_tokens`, or a spec that calls it a subset). The
        /// reported output is already the right bucket.
        case includedInOutput
        /// The store reports reasoning as its own output that its output figure
        /// does not contain. Only this case may be added.
        case independent
        /// The store gives no total and no statement of containment. The
        /// reported output is kept and the reasoning count is left out: adding
        /// it would be a guess, and if it is already inside output the guess
        /// would double count it.
        case unknown
    }

    /// Pulse's output bucket from a reported output and a reasoning count.
    ///
    /// - `includedInOutput`: the reported output is kept as is. **`I + O` must
    ///   never become `I + O + R`** when `R ⊆ O`; that is the double count this
    ///   exists to prevent.
    /// - `independent`: reasoning is not in the reported output, so it is added
    ///   once to keep Pulse's "output includes reasoning once" contract.
    /// - `unknown`: the reported output is kept and reasoning is **not** added
    ///   anywhere. An unknown relationship is not a licence to add.
    static func output(reported: Int, reasoning: Int, relationship: Reasoning) -> Int {
        let base = max(0, reported)
        switch relationship {
        case .includedInOutput, .unknown: return base
        case .independent: return base + max(0, reasoning)
        }
    }

    /// The **remainder** a trustworthy reported total leaves after every
    /// classified kind, for a store whose category relationship is unclear.
    ///
    /// Only a stated total can place the ambiguous part: the classified kinds
    /// stay as reported and the difference becomes unclassified, so the
    /// record's grand total equals the total the product reported. With no
    /// total this is zero — a guess is not a total.
    static func unclassifiedRemainder(reportedTotal: Int?, classified: Int) -> Int {
        guard let reportedTotal else { return 0 }
        return max(0, reportedTotal - max(0, classified))
    }
}
