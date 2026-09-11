import Foundation

/// How the DeepSeek ring gets a denominator, and where that denominator comes
/// from.
///
/// DeepSeek sells prepaid credit. `GET /user/balance` says how much money is
/// left and **nothing else** — no allowance, no window, no reset, and no spend
/// history anywhere in the API. It is the first provider Pulse carries with no
/// percentage in it at all, and a ring needs a denominator.
///
/// There are only three places one can come from, which is why there are
/// exactly three modes and no more.
enum DeepSeekBasis: String, CaseIterable, Identifiable, Sendable {
    /// The highest balance Pulse has seen since it last went up. Nobody has to
    /// type anything, and the number is one Pulse **watched**, not one it made
    /// up — which is why it is the default.
    case sinceTopUp
    /// No denominator at all: the rail shows the money, not a fraction.
    case balanceOnly
    /// A figure the user considers a full tank.
    case budget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sinceTopUp: .localized("Since top-up")
        case .balanceOnly: .localized("Balance only")
        case .budget: .localized("My budget")
        }
    }

    static let `default`: DeepSeekBasis = .sinceTopUp
}

/// The highest balance Pulse has seen since it last rose.
///
/// This is the denominator behind `DeepSeekBasis.sinceTopUp`, and the whole of
/// its honesty rests on one distinction: it is **measured, not inferred**. Pulse
/// reads the balance every refresh — 2 to 30 minutes — and remembers the peak.
/// A balance that goes *up* can only be a top-up, so that resets the mark and
/// the ring starts again from full. Nothing here is a guess about DeepSeek's
/// pricing, a table of plans, or a number typed by anyone.
///
/// What it costs is the first run: on a Mac that has never watched this account
/// there is no mark, so the first reading becomes one and the ring reads 0%
/// until money is actually spent. That is a true statement about what Pulse has
/// seen, and the card says which date it has been watching since.
///
/// One mark per currency, because DeepSeek reports an array of them and a CNY
/// peak is not a denominator for a USD balance.
enum DeepSeekBaseline {
    struct Mark: Codable, Equatable, Sendable {
        /// The highest balance seen in this currency since it last rose.
        var peak: Double
        /// When that peak was seen — which is when the top-up landed, not when
        /// it was last read.
        var setAt: Date
    }

    /// What the mark becomes after seeing `balance`.
    ///
    /// Pure, so the rule can be tested without a disk: a first sight and a
    /// top-up both set the mark, and everything else leaves it alone.
    static func advanced(_ mark: Mark?, seeing balance: Double, at now: Date) -> Mark {
        guard let mark, balance <= mark.peak else {
            return Mark(peak: max(balance, 0), setAt: now)
        }
        return mark
    }

    /// How much of that peak is gone, or nil where there is no denominator.
    ///
    /// A peak of zero is an account that has never had any credit to spend,
    /// which is not the same as one that has spent all of it.
    static func usedFraction(balance: Double, peak: Double) -> Double? {
        guard peak > 0 else { return nil }
        return min(max((peak - balance) / peak, 0), 1)
    }

    // MARK: - Disk

    /// Marks by currency code. Small, and rewritten every refresh, so it is
    /// read and written whole.
    static func marks() -> [String: Mark] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: Mark].self, from: data)) ?? [:]
    }

    static func store(_ marks: [String: Mark]) {
        let destination = file
        disk.async {
            PulseStorage.prepare()
            guard let data = try? JSONEncoder().encode(marks) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }

    /// Off the main thread, and serial so two refreshes cannot land out of
    /// order — the same arrangement `UsageAlerts` writes its memory with, and
    /// for the same reason: this is written on every pass.
    private static let disk = DispatchQueue(label: "Pulse.deepseek", qos: .utility)

    private static var file: URL {
        PulseStorage.directory.appending(path: "deepseek-baseline.json")
    }
}
