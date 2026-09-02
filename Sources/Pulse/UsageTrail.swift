import Foundation

/// The last few readings of each window, so how fast a limit is going can be
/// worked out from readings actually taken.
///
/// **This is measurement, not inference.** Every sample is a figure the
/// provider itself reported, stamped when it arrived; the rate is arithmetic
/// on two of them. That is a different thing from the money estimate, which
/// divides a reported percentage into a locally-counted spend — and it is why
/// this may say what it says. What it must still be careful about is the
/// *extrapolation*, which is `BurnRate`'s business rather than this file's.
///
/// Kept small on purpose. A window's whole point is that it resets, so history
/// older than the window is not evidence about it — and the refresh loop backs
/// off to half an hour when nothing is moving, so a long trail would mostly be
/// the same number written down repeatedly.
actor UsageTrail {
    static let shared = UsageTrail()

    /// Samples per window. At the refresh loop's fastest that is about an hour
    /// of history, and at its slowest a good deal more than one.
    static let depth = 24

    /// A sample this old is dropped whatever else is true: the loop can back
    /// off to thirty minutes, so two samples either side of a long idle stretch
    /// would otherwise average a burst against an afternoon of nothing.
    static let maximumAge: TimeInterval = 3 * 3600

    struct Sample: Codable, Equatable, Sendable {
        let at: Date
        let usedFraction: Double
        /// Carried so a reset can be seen rather than guessed at: when this
        /// moves, the window that was being measured has ended.
        let resetsAt: Date?
    }

    private let file: URL
    /// Keyed by `UsageWindow.id`, which is stable across refreshes and unique
    /// within a reading — the same key a pinned window is matched on.
    private var trails: [String: [Sample]]?

    init(file: URL = PulseStorage.directory.appending(path: "usage-trail.json")) {
        self.file = file
    }

    /// Records what a reading said, for every window in it.
    ///
    /// Only `.live` readings, for the same reason the cache stores only those:
    /// a stale reading re-served is not a new observation, and writing it down
    /// again would invent a stretch of zero usage that nobody measured.
    func record(_ usage: ProviderUsage) {
        guard case .live = usage.state, let observedAt = usage.observedAt else { return }

        var stored = load()
        for window in usage.windows {
            var samples = stored[window.id] ?? []

            // The same reading arriving twice — a refresh that beat the
            // provider's own update — is not a second observation.
            if let last = samples.last, last.at >= observedAt { continue }

            samples.append(Sample(
                at: observedAt,
                usedFraction: window.usedFraction,
                resetsAt: window.resetsAt
            ))
            stored[window.id] = Array(samples.suffix(Self.depth))
        }

        // Windows that stopped being reported stop being kept. A provider
        // switched off, or a model no longer scoped, would otherwise leave its
        // trail behind for ever.
        let seen = Set(usage.windows.map(\.id))
        let mine = Set(stored.keys).filter { $0.hasPrefix("\(usage.account.provider.rawValue).") }
        for orphan in mine.subtracting(seen) where !seen.isEmpty { stored[orphan] = nil }

        trails = stored
        save(stored)
    }

    /// The samples worth measuring a window by: recent, and all on **this**
    /// side of the last reset.
    ///
    /// A window that has reset drops from a high percentage to a low one, and
    /// differencing across that gives a negative rate — which reads as usage
    /// going backwards, or, worse, as a limit that will never be reached. The
    /// reset is visible in two ways and both are used: the stamp changing, and
    /// the figure falling.
    func samples(for window: UsageWindow, now: Date = Date()) -> [Sample] {
        let all = (load()[window.id] ?? []).filter { now.timeIntervalSince($0.at) <= Self.maximumAge }
        guard !all.isEmpty else { return [] }

        var kept: [Sample] = []
        for sample in all {
            if let last = kept.last {
                let windowChanged = last.resetsAt != sample.resetsAt
                // A fall of any size means the window turned over; usage does
                // not go down inside one.
                let fellBack = sample.usedFraction < last.usedFraction - 0.0001
                if windowChanged || fellBack { kept.removeAll() }
            }
            kept.append(sample)
        }
        return kept
    }

    /// Forgets everything. For the settings pane's own reset, and for probes.
    func forget() {
        trails = [:]
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Storage

    private func load() -> [String: [Sample]] {
        if let trails { return trails }
        let decoded = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([String: [Sample]].self, from: $0) } ?? [:]
        trails = decoded
        return decoded
    }

    private func save(_ trails: [String: [Sample]]) {
        guard let data = try? JSONEncoder().encode(trails) else { return }
        PulseStorage.prepare()
        try? data.write(to: file, options: .atomic)
    }
}
