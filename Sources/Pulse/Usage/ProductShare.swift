// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// How a provider splits the week's usage between its products, as it reports
/// it: Claude Code's usage reply carries `seven_day_breakdown.rows`, one
/// percentage per product (Claude Code, Chats, Cowork, Claude Duet, Other)
/// (#113).
///
/// **Shares of the week's usage, not of the limit.** The rows add up to about
/// 100 whatever the weekly figure is: "Claude Code 94%" beside a weekly limit
/// at 45% means 94% of that 45%. So it is shown only where a caption can say
/// so — the account's Current usage in Settings — and never on the rail or the
/// panel's card, where a bare percentage beside a ring reads as a limit. Text
/// only: no ring, no bar, no amount (see `Docs/providers/grok.md` on why
/// shares of one limit are not drawn as windows).
///
/// The field is not documented and every part of it is optional; a reply
/// without it, or with no readable row, has no share.
struct ProductShare: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable {
        /// The provider's own name for the product, never translated.
        let name: String
        /// 0...100, as reported.
        let percent: Double
    }

    /// Products with a share above zero, largest first, four at most.
    let rows: [Row]
    /// When the provider worked the split out, where it said.
    let asOf: Date?

    static let rowLimit = 4

    /// Rows without a name or a finite percentage between 0 and 100 are
    /// skipped, not repaired; zero shares are left out. Nil when nothing is
    /// left.
    init?(rows raw: [[String: Any]], asOf: Date?) {
        let rows = raw.compactMap { row -> Row? in
            guard
                let name = (row["display_name"] as? String)?.trimmingCharacters(in: .whitespaces),
                !name.isEmpty,
                let percent = (row["percent"] as? NSNumber)?.doubleValue,
                percent.isFinite, percent > 0, percent <= 100
            else { return nil }
            return Row(name: name, percent: percent)
        }
        // Stable for equal shares: the reply's own order breaks the tie.
        let ordered = rows.enumerated()
            .sorted { ($1.element.percent, $0.offset) < ($0.element.percent, $1.offset) }
            .map(\.element)
        guard !ordered.isEmpty else { return nil }
        self.rows = Array(ordered.prefix(Self.rowLimit))
        self.asOf = asOf
    }
}
