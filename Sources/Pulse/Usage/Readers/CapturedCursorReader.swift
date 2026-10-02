// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Cursor's usage cache: a dashboard export of `get-filtered-usage-events`,
/// plus the older CSV shape it replaced.
///
/// This is **not a native Cursor file**. The cache is written by an export step
/// that needs the user's Cursor authentication; Pulse only reads it from the
/// standard cache folder or its own import folder.
///
/// **Shape is proved, not assumed from the name.** Native caches keep their
/// `usage[.account]` names, but a file a user drops into
/// `UsageImports/cursor` may be called anything: a JSON file is read when its
/// root holds a `usageEventsDisplay` array, and a CSV when its header names the
/// date, model and four counter columns. Anything else is left alone.
///
/// **A session only exists where the export names one** — a JSON
/// `conversationId`, or a CSV `Cloud Agent ID`. An event with neither counts
/// its tokens and creates no session row, rather than being given a synthetic
/// per-day id nobody's store ever wrote.
///
/// **Equal rows are not merged, but overlapping exports are.** The export has
/// no per-event id, so two rows with the same conversation, second, model and
/// counts inside one file are left as two records — they may be genuinely two
/// requests. Across files **of one scope** the same row is reconciled by
/// content multiset: `{A}` and `{A, B}` give `A` and `B`, never two `A`s, and an
/// unconfirmed increment inside the shared region is reported as `isPartial`
/// rather than added. A byte-identical file is folded outright. Files are scoped
/// by a declared account (`usage.<account>`), and files that declare none share
/// one import scope rather than being split by their names.
///
/// **No cost is carried into a record.** Cursor reports `chargedCents` and a
/// per-event `totalCents`; both are the product's own money and are ignored,
/// because the one pricing path is `ModelPrices`.
enum CapturedCursorReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["json", "csv"])
            .filter { isCandidate($0.lastPathComponent) }

        // Grouped by **scope**, not by folder and not by arbitrary file stem.
        // A native `usage.<account>` name states a real account; anything else
        // names no account and shares one import scope, so two differently
        // named exports of one account are reconciled rather than treated as
        // two accounts.
        var jsonByScope: [String: [URL]] = [:]
        var csvByScope: [String: [URL]] = [:]
        for file in files {
            let key = scope(for: file.lastPathComponent)
            if file.pathExtension.lowercased() == "json" {
                jsonByScope[key, default: []].append(file)
            } else {
                csvByScope[key, default: []].append(file)
            }
        }

        var records: [AgentUsageRecord] = []
        let scopes = Set(jsonByScope.keys).union(csvByScope.keys).sorted()
        for key in scopes {
            records.append(contentsOf: Self.records(
                account: account(fromScope: key),
                json: jsonByScope[key] ?? [],
                csv: csvByScope[key] ?? []
            ))
        }
        return records
    }

    /// The account a scope key declares, or nil for the shared import scope.
    private static func account(fromScope key: String) -> String? {
        guard key.hasPrefix("account:") else { return nil }
        return String(key.dropFirst("account:".count))
    }

    // MARK: - One scope

    private static func records(
        account: String?,
        json: [URL],
        csv: [URL]
    ) -> [AgentUsageRecord] {
        // A byte-identical file dropped twice is one export; the JSON and CSV
        // lanes are deduplicated separately so one cannot hide the other.
        let jsonFiles = replayDistinct(json)
        let csvFiles = replayDistinct(csv)
        let label = account ?? "unscoped"

        var jsonPerFile: [[AgentUsageRecord]] = []
        for file in jsonFiles {
            guard let parsed = Self.jsonRecords(at: file, account: label) else { continue }
            jsonPerFile.append(parsed)
        }
        var csvPerFile: [[AgentUsageRecord]] = []
        for file in csvFiles {
            guard let parsed = Self.csvRecords(at: file, account: label) else { continue }
            csvPerFile.append(parsed)
        }

        // Overlapping exports of one scope are reconciled by content multiset,
        // not concatenated.
        let jsonLane = CapturedSupport.reconcile(jsonPerFile, signature: signature)
        let csvLane = CapturedSupport.reconcile(csvPerFile, signature: signature)

        var chosen: [AgentUsageRecord] = []
        var partial = jsonLane.overlapped || csvLane.overlapped

        if !jsonLane.records.isEmpty {
            chosen.append(contentsOf: jsonLane.records)
            // JSON is the authoritative lane. A CSV row inside its date range
            // is unverifiable overlap, so it is not added; a row outside is
            // kept. Either way the account is marked incomplete rather than
            // silently reconciled.
            if let jsonRange = range(jsonLane.records) {
                var inside = 0
                for record in csvLane.records {
                    if record.timestamp < jsonRange.0 || record.timestamp > jsonRange.1 {
                        chosen.append(record)
                    } else {
                        inside += 1
                    }
                }
                if inside > 0 { partial = true }
            }
        } else {
            // No usable JSON events — an empty or unreadable file must not
            // suppress a valid CSV. The CSV is the only lane.
            chosen.append(contentsOf: csvLane.records)
        }

        // A file that declared no account cannot be scoped, so its totals are
        // not claimed complete.
        if account == nil { partial = true }

        return partial ? chosen.map(markedPartial) : chosen
    }

    private static func markedPartial(_ record: AgentUsageRecord) -> AgentUsageRecord {
        var copy = record
        copy.isPartial = true
        return copy
    }

    /// A row's content identity, used only to reconcile overlapping exports.
    private static func signature(_ record: AgentUsageRecord) -> String {
        let milliseconds = Int((record.timestamp.timeIntervalSince1970 * 1000).rounded())
        return "\(record.sessionID ?? ""):\(milliseconds):\(record.model):"
            + "\(record.tally.input):\(record.tally.cacheWrite):\(record.tally.cacheRead):\(record.tally.output)"
    }

    /// Files whose bytes are identical are one export; everything else is kept.
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

    private static func range(_ records: [AgentUsageRecord]) -> (Date, Date)? {
        guard let first = records.map(\.timestamp).min(), let last = records.map(\.timestamp).max()
        else { return nil }
        return (first, last)
    }

    // MARK: - JSON

    /// `nil` when the file is not a Cursor JSON at all; `[]` when it is one that
    /// happens to hold no usable events.
    private static func jsonRecords(at url: URL, account: String) -> [AgentUsageRecord]? {
        guard
            let root = AgentLogIO.object(AgentLogIO.json(at: url)),
            let events = root["usageEventsDisplay"] as? [[String: Any]]
        else { return nil }

        var records: [AgentUsageRecord] = []
        for event in events {
            guard !Task.isCancelled else { return nil }
            // A blank model names nothing, and no time means the event cannot
            // be placed on a day; both are skipped, never guessed.
            guard
                let model = AgentLogIO.text(event["model"]),
                let at = AgentLogIO.timestamp(event["timestamp"], milliseconds: true),
                at.timeIntervalSince1970 > 0
            else { continue }

            let usage = AgentLogIO.object(event["tokenUsage"]) ?? [:]
            let tally = TokenTally(
                input: AgentLogIO.count(usage["inputTokens"]) ?? 0,
                cacheWrite: AgentLogIO.count(usage["cacheWriteTokens"]) ?? 0,
                cacheRead: AgentLogIO.count(usage["cacheReadTokens"]) ?? 0,
                output: AgentLogIO.count(usage["outputTokens"]) ?? 0
            )
            guard tally.total > 0 else { continue }

            var record = AgentUsageRecord(timestamp: at, model: model, tally: tally)
            // Only an export-stated conversation is a session. The account is
            // folded in so two accounts' identical ids do not collide.
            if let conversation = AgentLogIO.text(event["conversationId"]) {
                record.sessionID = "cursor:\(account):\(conversation)"
            }
            records.append(record)
        }
        return records
    }

    // MARK: - CSV

    /// `nil` when the header is not a Cursor CSV; otherwise the rows it holds.
    private static func csvRecords(at url: URL, account: String) -> [AgentUsageRecord]? {
        guard !Task.isCancelled else { return nil }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let rows = CapturedCSV.rows(in: String(decoding: data, as: UTF8.self))
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }

        guard
            let headerIndex = rows.firstIndex(where: { row in
                let names = row.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                return names.contains("date") && names.contains("model")
            })
        else { return nil }

        let header = rows[headerIndex].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }

        // Column *names*, not positions: the header moved through three shapes
        // (with and without `Kind`, and with two cloud ids), and reading by
        // name keeps a v1 export from being read as a v3 one. A header that
        // lacks any counter is not this schema.
        guard
            let dateColumn = column("date"),
            let modelColumn = column("model"),
            let inputColumn = column("input (w/o cache write)"),
            let cacheWriteColumn = column("input (w/ cache write)"),
            let cacheReadColumn = column("cache read"),
            let outputColumn = column("output tokens")
        else { return nil }

        // Only a stated cloud agent id is a session; a plain chat row has none.
        let cloudColumn = column("cloud agent id")

        let widest = max(dateColumn, modelColumn, inputColumn, cacheWriteColumn, cacheReadColumn, outputColumn)
        var records: [AgentUsageRecord] = []

        for row in rows[(headerIndex + 1)...] {
            // A short row is a broken record, not a row of zeroes.
            guard row.count > widest else { continue }
            let rawDate = row[dateColumn].trimmingCharacters(in: .whitespaces)
            guard
                let at = csvDate(rawDate), at.timeIntervalSince1970 > 0,
                let model = AgentLogIO.text(row[modelColumn])
            else { continue }

            // The columns are independent buckets, as Cursor's own comment
            // says: `w/o cache write` is fresh input, `w/ cache write` is the
            // cache-write bucket, and neither is the other subtracted from a
            // total. `Total Tokens` is deliberately not read.
            let tally = TokenTally(
                input: csvCount(row[inputColumn]),
                cacheWrite: csvCount(row[cacheWriteColumn]),
                cacheRead: csvCount(row[cacheReadColumn]),
                output: csvCount(row[outputColumn])
            )
            guard tally.total > 0 else { continue }

            var record = AgentUsageRecord(timestamp: at, model: model, tally: tally)
            if let cloudColumn, cloudColumn < row.count,
               let cloud = AgentLogIO.text(row[cloudColumn]) {
                record.sessionID = "cursor:\(account):cloud:\(cloud)"
            }
            // A legacy usage report states a day (or a date-time), not the
            // quarter-hour a request started in, so its timing is aggregate.
            record.isAggregate = true
            records.append(record)
        }
        return records
    }

    // MARK: - Names and time

    /// Any `.json`/`.csv` is a candidate; the schema decides. A native backup
    /// is the one name-based exclusion, because a stale copy of the same
    /// account's cache would otherwise be read as live.
    private static func isCandidate(_ name: String) -> Bool {
        let extensionName = (name as NSString).pathExtension.lowercased()
        guard extensionName == "json" || extensionName == "csv" else { return false }
        let stem = (name as NSString).deletingPathExtension.lowercased()
        return !stem.hasPrefix("usage.backup")
    }

    /// The scope a file belongs to.
    ///
    /// A native name states a real account (`usage.<account>.<ext>`, or
    /// `usage.<ext>` for the active one). An arbitrary import file declares no
    /// account, so it goes into one shared import scope — its own name is not
    /// turned into an account Entity. That is what keeps two differently named
    /// exports of one account from bypassing reconciliation and being counted
    /// twice.
    private static func scope(for name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        let parts = stem.split(separator: ".", omittingEmptySubsequences: false)
        if parts.first?.lowercased() == "usage" {
            if parts.count >= 2, let account = CapturedSupport.slug(String(parts[1])) {
                return "account:\(account)"
            }
            return "account:active"
        }
        return "import"
    }

    /// A counter in a CSV cell. A quoted thousands separator (`"1,000"`) is a
    /// formatting artefact, not a second column, so the comma is dropped before
    /// the shared count reader sees it.
    private static func csvCount(_ raw: String) -> Int {
        AgentLogIO.count(raw.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    /// The CSV's date-time is written in several ISO-ish spellings. A bare
    /// `yyyy-MM-dd` is midnight in the local zone, so its calendar day is the
    /// day the report states. Nothing here falls back to the clock or a file's
    /// modification date.
    private static func csvDate(_ raw: String) -> Date? {
        if let iso = AgentLogIO.timestamp(raw) { return iso }
        for format in ["yyyy-MM-dd HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
