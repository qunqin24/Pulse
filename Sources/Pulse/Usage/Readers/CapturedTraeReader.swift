// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Trae's usage cache: a raw JSON **array** dumped from the Trae usage API.
///
/// There is no native local file; the array is an export that needs an
/// authenticated sync. Pulse reads the dumped array, whatever the file is
/// called, as soon as the root parses as an array.
///
/// `model_name` is empty when the system picked a model per turn (Auto mode),
/// in which case the row is placed under `trae-<mode>` and the true per-turn
/// model is not recoverable. `extra_info` carries the four real counters.
/// Anything else in `extra_info` is left alone rather than folded into a
/// bucket — a counter with no stated meaning is not a cache-read count.
///
/// **Equal rows are not merged, but overlapping pages are.** The dump has no
/// per-row id, so two rows for one session in the same second inside one page
/// are left as two rows: they can be two requests. Across pages the same row is
/// reconciled by content multiset: `{A}` and `{A, B}` give `A` and `B`, never
/// two `A`s. An unconfirmed increment inside a shared region is reported as
/// `isPartial` rather than added, and a byte-identical page is folded outright.
enum CapturedTraeReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = replayDistinct(AgentLogIO.files(in: roots, extensions: ["json"]))
        // A non-array root yields an empty list and changes nothing.
        let reconcilable = files.map { Self.records(at: $0) }
        let reconciled = CapturedSupport.reconcile(reconcilable, signature: signature)
        return reconciled.overlapped ? reconciled.records.map(markedPartial) : reconciled.records
    }

    private static func markedPartial(_ record: AgentUsageRecord) -> AgentUsageRecord {
        var copy = record
        copy.isPartial = true
        return copy
    }

    /// A row's content identity, used only to reconcile overlapping pages —
    /// never to fold two rows of one page together.
    private static func signature(_ record: AgentUsageRecord) -> String {
        "\(record.sessionID ?? ""):\(record.timestamp.timeIntervalSince1970):\(record.model):"
            + "\(record.tally.input):\(record.tally.cacheWrite):\(record.tally.cacheRead):\(record.tally.output)"
    }

    /// Files whose bytes are the same are one dumped page; a re-dump does not
    /// count twice, while two rows inside one page still do.
    private static func replayDistinct(_ files: [URL]) -> [URL] {
        var seen: Set<String> = []
        var distinct: [URL] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            guard !Task.isCancelled else { return [] }
            guard let digest = AgentLogIO.digest(at: file) else { continue }
            if seen.insert(digest).inserted { distinct.append(file) }
        }
        return distinct
    }

    private static func records(at url: URL) -> [AgentUsageRecord] {
        // A non-array root is not this format and yields nothing.
        guard let sessions = AgentLogIO.json(at: url) as? [[String: Any]] else { return [] }

        var records: [AgentUsageRecord] = []
        for session in sessions {
            guard !Task.isCancelled else { return [] }
            guard let sessionID = AgentLogIO.text(session["session_id"]) else { continue }
            // `usage_time` is epoch seconds by this schema. A non-positive
            // value is not a usable time.
            guard
                let at = AgentLogIO.timestamp(session["usage_time"]),
                at.timeIntervalSince1970 > 0
            else { continue }

            let extra = AgentLogIO.object(session["extra_info"]) ?? [:]
            let tally = TokenTally(
                input: AgentLogIO.count(extra["input_token"]) ?? 0,
                cacheWrite: AgentLogIO.count(extra["cache_write_token"]) ?? 0,
                cacheRead: AgentLogIO.count(extra["cache_read_token"]) ?? 0,
                output: AgentLogIO.count(extra["output_token"]) ?? 0
            )
            // All-zero totals assert no usage.
            guard tally.total > 0 else { continue }

            var record = AgentUsageRecord(
                timestamp: at, model: normalized(Self.modelName(session)), tally: tally
            )
            // The session id names the session; it is **not** a row identity,
            // so it never becomes a deduplication id.
            record.sessionID = sessionID
            records.append(record)
        }
        return records
    }

    private static func modelName(_ session: [String: Any]) -> String {
        if let name = AgentLogIO.text(session["model_name"]) { return name }
        if let mode = AgentLogIO.text(session["mode"]) { return "trae-\(mode)" }
        return "trae-unknown"
    }

    /// A small, fixed display-name table. Ids are the provider's own where a
    /// known name maps to one; an unrecognised name passes through unchanged so
    /// it can be counted and reported as unpriced rather than disguised.
    private static func normalized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("gpt-5") {
            return spaced(lower)
        }
        if lower.hasPrefix("gemini 3.1") || lower.hasPrefix("gemini-3.1") {
            return spaced(lower)
        }
        if lower == "glm 5.1" || lower == "glm-5.1" {
            return "glm-5.1"
        }
        // Anthropic spells the version with dashes, so `Claude Sonnet 4.5`
        // becomes `claude-sonnet-4-5`.
        if lower.hasPrefix("claude sonnet 4.5") {
            return spaced(lower.replacingOccurrences(of: "4.5", with: "4-5"))
        }
        if lower.hasPrefix("claude sonnet 4.6") {
            return spaced(lower.replacingOccurrences(of: "4.6", with: "4-6"))
        }
        return trimmed
    }

    private static func spaced(_ value: String) -> String {
        value.split(whereSeparator: { $0 == " " || $0 == "_" }).joined(separator: "-")
    }
}
