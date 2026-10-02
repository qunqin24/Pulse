// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Copilot's three independent stores, read as one client id.
///
/// Copilot leaves its work in three unrelated places, and all three are the
/// same product:
///
/// - a file-exported OpenTelemetry JSONL stream under `~/.copilot/otel/`, where
///   the CLI and monitoring builds write per-span token counts;
/// - the desktop app's SQLite database at `~/.copilot/data.db`, with a
///   `session-state/<id>/events.jsonl` sidecar carrying the cumulative
///   per-model run totals the database itself does not;
/// - VS Code's chat session logs under
///   `Code/User/workspaceStorage/<hash>/chatSessions/<uuid>.jsonl`.
///
/// **A session logged in more than one place is counted once.** The lanes are
/// collected in a fixed order — OTEL, then desktop, then VS Code — and each
/// later lane is filtered against the earlier ones: a desktop session already
/// seen in OTEL is dropped whole, and a VS Code request is dropped when its own
/// dedup key or its `(session, timestamp)` pair is already present. The three
/// lanes are never merged by a shared dedup key across sources; the session and
/// instant filtering is what prevents double counting.
///
/// **A dropped desktop session is not silently zeroed.** OTEL is per span
/// while the desktop row is a lifetime total, and the two scopes are not equal
/// enough to subtract. When a session's desktop lifetime total is larger than
/// what OTEL recorded, the OTEL records for that session are marked
/// `isPartial`, naming the uncovered desktop work instead of presenting a known
/// subset as the whole session.
///
/// **It reads, it does not add up.** `records` turns what it finds into
/// `AgentUsageRecord` increments and stops there; pricing and windowing belong
/// to `AgentUsageLedger.build`. Nothing here turns a cost, a duration, a text
/// length or a missing field into a token count.
enum CopilotLogReader {
    /// The one canonical id this family answers for.
    static let supportedClients: Set<String> = ["copilot"]

    /// Every root Copilot's records are read from.
    ///
    /// A root that does not exist is still named, so the spend cache's
    /// fingerprint sees a store that appears later. No Copilot store has a
    /// documented environment override, so `environment` is unused here; it
    /// stays in the signature because every reader family in this directory
    /// takes it, and a caller may drive it in a test without touching the real
    /// one. Nothing walks the home directory looking for a store that looks
    /// right.
    static func inputs(
        client: String,
        home: URL,
        environment: [String: String] = [:]
    ) -> [URL] {
        guard supportedClients.contains(client) else { return [] }

        var roots: [URL] = [
            // The OTEL JSONL export.
            home.appending(path: ".copilot/otel", directoryHint: .isDirectory),
            // The desktop database and its sidecar session directory.
            home.appending(path: ".copilot/data.db"),
            home.appending(path: ".copilot/session-state", directoryHint: .isDirectory),
            // VS Code's chatSessions trees: macOS, Linux, and the default
            // Windows layout below the home directory.
            DatabaseReaderSupport.applicationSupport(home: home)
                .appending(path: "Code/User/workspaceStorage", directoryHint: .isDirectory),
            home.appending(path: ".config/Code/User/workspaceStorage", directoryHint: .isDirectory),
            home.appending(path: "AppData/Roaming/Code/User/workspaceStorage", directoryHint: .isDirectory),
        ]

        // `%APPDATA%` is where Windows keeps the same tree when the profile is
        // relocated; the `AppData/Roaming` path above is the default profile.
        if let appData = DatabaseReaderSupport.appData(environment: environment) {
            roots.append(
                appData.appending(path: "Code/User/workspaceStorage", directoryHint: .isDirectory)
            )
        }
        return roots
    }

    /// The usage increments Copilot's roots contain, from all three lanes.
    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        guard supportedClients.contains(client) else { return [] }

        // Lane one: OTEL is the authority for every session it names.
        var otel = CopilotOTELReader.records(roots: roots.filter(Self.isOTELRoot))

        // Lane two: the desktop database is read before either lane is filtered,
        // because its rows are the lifetime authority for a session and say
        // whether OTEL covered all of it. Only afterwards is a session OTEL
        // named dropped from the desktop lane.
        let desktopRecords = roots
            .filter(Self.isDesktopDatabase)
            .flatMap { CopilotDesktopReader.records(database: $0) }

        // The desktop row is a **lifetime** total; OTEL is per span. When a
        // session appears in both and the desktop total is larger, OTEL is a
        // known subset of that session. The scopes are not equal enough to
        // subtract one from the other — the desktop row's input accounting
        // against OTEL's cache-inclusive input is not established, and OTEL
        // carries no bound on the desktop row's lifetime — so no remainder is
        // invented. The authority lane (OTEL) is kept and its records for that
        // session are marked partial: the specific uncovered part is the
        // desktop lifetime the reader already dropped, which is more than OTEL
        // recorded. When the desktop total is not larger and no dropped desktop
        // record was partial, there is nothing the drop can hide and the OTEL
        // records stay complete.
        let desktopTotals = Self.totals(desktopRecords)
        let otelTotals = Self.totals(otel)
        // A dropped desktop record that was itself partial (its reasoning could
        // not be placed) leaves a remainder the totals cannot show, because the
        // unplaceable count is not in any bucket. Carry its doubt onto the OTEL
        // records it displaced.
        let desktopPartial = Set(
            desktopRecords.compactMap { $0.isPartial ? $0.sessionID : nil }
        )
        let partlyCovered = Set(otelTotals.compactMap { entry -> String? in
            guard let lifetime = desktopTotals[entry.key], lifetime > entry.value else { return nil }
            return entry.key
        }).union(desktopPartial)
        if !partlyCovered.isEmpty {
            otel = otel.map { record in
                guard let session = record.sessionID, partlyCovered.contains(session) else {
                    return record
                }
                var copy = record
                copy.isPartial = true
                return copy
            }
        }

        let otelSessions = Set(otel.compactMap(\.sessionID))
        let desktop = desktopRecords.filter { record in
            guard let session = record.sessionID else { return true }
            return !otelSessions.contains(session)
        }

        // Lane three: VS Code is filtered against everything accumulated so
        // far, by dedup key or by the same session at the same instant.
        let accumulated = otel + desktop
        let identities = Set(accumulated.compactMap(\.deduplicationID))
        var instants: Set<CopilotSessionInstant> = []
        for record in accumulated {
            guard let session = record.sessionID else { continue }
            instants.insert(CopilotSessionInstant(session: session, instant: record.timestamp))
        }

        let vscode = CopilotVSCodeReader.records(roots: roots.filter(Self.isVSCodeRoot))
            .filter { record in
                if let id = record.deduplicationID, identities.contains(id) { return false }
                if let session = record.sessionID,
                   instants.contains(CopilotSessionInstant(session: session, instant: record.timestamp)) {
                    return false
                }
                return true
            }

        return (accumulated + vscode).sorted(by: Self.ordered)
    }

    /// Every record's counted total, grouped by the session it named. The
    /// counted total is the four kinds plus any bare unclassified remainder.
    ///
    /// The sum only decides whether a dropped desktop session left work behind,
    /// so a hostile count cannot be allowed to trap it: each addition is checked
    /// and saturates at `Int.max` rather than overflowing.
    private static func totals(_ records: [AgentUsageRecord]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for record in records {
            guard let session = record.sessionID else { continue }
            let tally = record.tally
            totals[session] = Self.summed([
                totals[session, default: 0],
                tally.input, tally.cacheWrite, tally.cacheRead, tally.output,
                record.unclassifiedTokens,
            ])
        }
        return totals
    }

    /// The checked sum of non-negative counts, saturating rather than trapping.
    private static func summed(_ values: [Int]) -> Int {
        var total = 0
        for value in values {
            let (sum, overflow) = total.addingReportingOverflow(max(value, 0))
            total = overflow ? Int.max : sum
        }
        return total
    }

    // MARK: - Shared identity

    /// One Copilot session at one instant, the coarse pair VS Code is filtered
    /// on. Only meaningful when a session was named.
    struct CopilotSessionInstant: Hashable {
        let session: String
        let instant: Date
    }

    /// A deterministic order, so two runs over the same stores agree.
    private static func ordered(_ lhs: AgentUsageRecord, _ rhs: AgentUsageRecord) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return (lhs.deduplicationID ?? "") < (rhs.deduplicationID ?? "")
    }

    // MARK: - Shared helpers

    /// A root's own name, which is how the entry point tells its three lanes
    /// apart. The roots come back exactly as `inputs` named them.
    private static func isOTELRoot(_ url: URL) -> Bool {
        url.lastPathComponent == "otel"
    }

    private static func isDesktopDatabase(_ url: URL) -> Bool {
        url.lastPathComponent == "data.db"
    }

    private static func isVSCodeRoot(_ url: URL) -> Bool {
        url.lastPathComponent == "workspaceStorage"
            && url.deletingLastPathComponent().lastPathComponent == "User"
    }

    /// Copilot's own name for the agent that ran a span, normalized.
    ///
    /// The record boundary has no dedicated agent field, so the label is
    /// carried as the session's name: it is stated metadata, not something
    /// guessed from a path. The forms are the product's own —
    /// `github.copilot.default` is the plain agent, `github.copilot.<rest>` is
    /// one of its presets, and a `Plugin:team:slug` handle is titlecased with
    /// its colons spaced out.
    static func agentLabel(_ raw: String?) -> String? {
        guard let label = AgentLogIO.text(raw) else { return nil }
        if label == "github.copilot.default" { return "GitHub Copilot" }

        if label.hasPrefix("github.copilot.") {
            let rest = String(label.dropFirst("github.copilot.".count))
            guard !rest.isEmpty else { return "GitHub Copilot" }
            return rest
                .split(separator: ".", omittingEmptySubsequences: true)
                .map(Self.titlecased)
                .joined(separator: "-")
        }

        if label.contains(":") {
            return label
                .split(separator: ":", omittingEmptySubsequences: false)
                .map(Self.titlecased)
                .joined(separator: ": ")
        }
        return label
    }

    private static func titlecased(_ part: Substring) -> String {
        guard let first = part.first else { return "" }
        return String(first).uppercased() + part.dropFirst()
    }

    /// A timestamp rounded to whole milliseconds, for a dedup key that must be
    /// stable across a re-read.
    static func milliseconds(_ date: Date) -> Int {
        let value = date.timeIntervalSince1970 * 1000
        guard value.isFinite, value >= Double(Int.min), value <= Double(Int.max) else { return 0 }
        return Int(value.rounded())
    }

    /// A stable 64-bit FNV-1a hash, hex-encoded.
    ///
    /// `Hasher` is seeded per process, so it cannot key a record that must fold
    /// with itself across launches; this can. Used only as the fallback
    /// identity for a sidecar event that carries no id of its own.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
