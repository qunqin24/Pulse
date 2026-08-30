import Foundation

/// The last good reading from each provider, so a failed fetch shows numbers
/// with a date on them instead of an error with nothing.
///
/// Everything Pulse talks to can say no for a while — the endpoint is
/// undocumented and rate limits, a saved token expires, a VPN drops a
/// connection. The figures behind those calls move in percent over hours, so
/// the last answer is very nearly the right one and a card reading "82%, as of
/// four minutes ago" is worth more than one reading "checking too often".
///
/// Two rules keep that honest:
///
/// - Only `.live` readings are ever stored, and they come back marked
///   `.stale`, which is what puts the "as of" line on the card. A cached
///   reading is never passed off as current.
/// - A window whose reset time has **passed** is dropped rather than shown.
///   It hasn't aged, it has *reset* — whatever it says now is not a stale
///   version of the truth, it is a number about a window that no longer
///   exists.
actor UsageCache {
    static let shared = UsageCache()

    /// A backstop for windows that never say when they reset. Past this, an
    /// old reading stops being "nearly right" and starts being a fiction with
    /// a date attached.
    static let maximumAge: TimeInterval = 24 * 3600

    /// Injectable so the rules can be exercised against a scratch file rather
    /// than the one the running app depends on.
    private let file: URL
    private var readings: [Provider: Stored]?

    init(file: URL = PulseStorage.directory.appending(path: "last-readings.json")) {
        self.file = file
    }

    private struct Stored: Codable {
        let windows: [UsageWindow]
        let observedAt: Date
        let plan: String?
        let creditBalance: String?
    }

    /// Returns the reading worth showing: the fetched one when it carries
    /// anything, otherwise whatever was last banked — and, when both have
    /// something, whichever was actually taken later.
    func reconciled(_ fetched: ProviderUsage) -> ProviderUsage {
        if case .live = fetched.state, !fetched.windows.isEmpty {
            store(fetched)
            return fetched
        }

        guard let cached = reading(for: fetched.provider) else { return fetched }

        // A fetch that came back with something no older than the cache wins;
        // this only fills gaps, it never overrules a real answer.
        if let fetchedAt = fetched.observedAt,
           let cachedAt = cached.observedAt,
           fetchedAt >= cachedAt,
           !fetched.windows.isEmpty {
            return fetched
        }

        return cached
    }

    private func store(_ usage: ProviderUsage) {
        var all = load()
        all[usage.provider] = Stored(
            windows: usage.windows,
            observedAt: usage.observedAt ?? Date(),
            plan: usage.plan,
            creditBalance: usage.creditBalance
        )
        readings = all
        write(all)
    }

    private func reading(for provider: Provider) -> ProviderUsage? {
        guard let stored = load()[provider] else { return nil }

        let now = Date()
        guard now.timeIntervalSince(stored.observedAt) <= Self.maximumAge else { return nil }

        // Drop what has since reset — see the note above.
        let windows = stored.windows.filter { ($0.resetsAt ?? .distantFuture) > now }
        guard !windows.isEmpty else { return nil }

        return ProviderUsage(
            provider: provider,
            windows: windows,
            observedAt: stored.observedAt,
            state: .stale,
            plan: stored.plan,
            creditBalance: stored.creditBalance
        )
    }

    // MARK: - Disk

    private func load() -> [Provider: Stored] {
        if let readings { return readings }

        guard
            let data = try? Data(contentsOf: file),
            let decoded = try? JSONDecoder().decode([String: Stored].self, from: data)
        else {
            readings = [:]
            return [:]
        }

        var all: [Provider: Stored] = [:]
        for (key, value) in decoded {
            if let provider = Provider(rawValue: key) { all[provider] = value }
        }
        readings = all
        return all
    }

    private func write(_ all: [Provider: Stored]) {
        PulseStorage.prepare()
        let keyed = Dictionary(uniqueKeysWithValues: all.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(keyed) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
