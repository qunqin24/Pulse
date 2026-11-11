// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// How Anthropic splits the account's week between its products: Claude Code,
/// Chats, Cowork and so on.
///
/// **Why it is read at all.** Token spend counts the transcripts Claude Code
/// leaves on this Mac, and nothing else. The same subscription also pays for
/// chats, Cowork and other Claude products, none of which leave a record here,
/// so the Claude Code figure is the whole bill only for someone who uses
/// nothing else. The usage reply (`api/oauth/usage`) says how the week's usage
/// divides between those products, and dividing the measured Claude Code
/// amount by Claude Code's part gives an estimate for all of them.
///
/// **Not public API, and not a measurement.** `seven_day_breakdown` is not
/// documented; it is what the reply carries today, as other usage monitors
/// also read it: `{ as_of, window_started_at, rows: [{ key, display_name,
/// percent }] }`, `percent` from 0 to 100. Everything here is optional, and a
/// missing or odd field means no estimate rather than a guessed one. The
/// percentages are shares of the weekly limit, not of tokens, and rounded to
/// whole numbers, so the estimate is approximate and is labelled as such.
struct ClaudeProductShare: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable {
        /// Anthropic's own key, such as `claude_code` or `chat`.
        let key: String
        /// The name Anthropic shows for it, such as "Chats".
        let name: String
        /// 0 to 100, as reported.
        let percent: Double
    }

    let rows: [Row]
    /// When Pulse read it.
    let observedAt: Date

    static let claudeCodeKey = "claude_code"

    /// The rows the reply carries, in its own order, or nil when it carries
    /// none that can be read. A row without a key or a finite percentage
    /// between 0 and 100 is skipped, not repaired.
    static func parse(_ root: [String: Any], at now: Date = Date()) -> ClaudeProductShare? {
        guard
            let breakdown = root["seven_day_breakdown"] as? [String: Any],
            let raw = breakdown["rows"] as? [[String: Any]]
        else { return nil }

        let rows = raw.compactMap { row -> Row? in
            guard
                let key = row["key"] as? String, !key.isEmpty,
                let percent = number(row["percent"]), percent.isFinite, (0...100).contains(percent)
            else { return nil }
            let name = (row["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
            return Row(key: key, name: name, percent: percent)
        }
        guard !rows.isEmpty else { return nil }
        return ClaudeProductShare(rows: rows, observedAt: now)
    }

    /// Claude Code's part of the week, from 0 to 1.
    ///
    /// Taken against the sum of the rows rather than against 100: each row is
    /// rounded on its own, so the rows can add up to 99 or 101, and the parts
    /// should still add up to the whole. Nil when there is no Claude Code row
    /// or it is zero, because dividing by nothing is not an estimate.
    var claudeCodeFraction: Double? {
        let total = rows.reduce(0) { $0 + $1.percent }
        guard total > 0,
              let code = rows.first(where: { $0.key == Self.claudeCodeKey })?.percent,
              code > 0
        else { return nil }
        return code / total
    }

    /// One product's row with its part of the week, from 0 to 1.
    struct Part: Identifiable, Equatable, Sendable {
        let row: Row
        let fraction: Double

        var id: String { row.key }
    }

    /// Every product's part, against the same sum as `claudeCodeFraction`.
    var parts: [Part] {
        let total = rows.reduce(0) { $0 + $1.percent }
        guard total > 0 else { return [] }
        return rows.map { Part(row: $0, fraction: $0.percent / total) }
    }

    /// The Claude Code amount scaled up to every product:
    /// `claudeCode / claudeCodeFraction`. Nil when there is no share to divide
    /// by, or nothing measured to scale.
    func estimatedTotal(fromClaudeCode amount: Double) -> Double? {
        guard amount.isFinite, amount > 0, let fraction = claudeCodeFraction else { return nil }
        return amount / fraction
    }

    private static func number(_ value: Any?) -> Double? {
        return (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }

    // MARK: - Kept between launches

    /// The last split read for the account whose transcripts Token spend counts.
    ///
    /// Stored rather than handed through `ProviderUsage`: it describes the
    /// account's week, not a limit, so it has no ring and no place in the
    /// usage cache, and the Settings pane that reads it opens long after the
    /// reading was taken. Takes the store as an argument so the round trip
    /// can be pinned against an isolated suite.
    static let defaultsKey = "claude.productShare"

    static func stored(in defaults: UserDefaults = .standard) -> ClaudeProductShare? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ClaudeProductShare.self, from: data)
    }

    static func store(_ share: ClaudeProductShare, in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(share) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
