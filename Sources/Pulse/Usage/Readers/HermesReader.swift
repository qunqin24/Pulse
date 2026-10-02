// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Hermes Agent's SQLite state, at `$HERMES_HOME/state.db` and one
/// `state.db` per named profile under `profiles/`.
///
/// ```sql
/// sessions(id, model, billing_provider, started_at, message_count,
///          input_tokens, output_tokens, cache_read_tokens,
///          cache_write_tokens, reasoning_tokens, …)
/// session_model_usage(session_id, model, billing_provider, …same columns…)
/// ```
///
/// **A session is a cumulative deployment, not a request.** The per-model
/// `SUM` and the session row both run over the session's whole life, so a
/// rescan of a growing session yields a larger figure under the same identity.
/// Two passes keep that from being counted twice: a session the optional
/// per-model table explains is emitted per model and **never** re-emitted from
/// the session row; every other session is emitted once from its own totals.
///
/// **Input is only split when there is no cache to collide with.** Hermes
/// writes input, output, cache-read, cache-write and reasoning as separate
/// integer columns, but the schema does **not** establish whether
/// `input_tokens` already contains the cache read. Summing them would assume a
/// disjointness nobody proved, and moving the cache to `unclassifiedTokens`
/// while also counting the full input would double it just the same.
///
/// So: with no cache reported the input is unambiguous and is classified as
/// fresh input; with a non-zero cache the reported input is carried as
/// **unclassified real work** and the cache columns are not added at all. That
/// total is never double counted, even though it may leave out tokens the
/// schema does not relate.
///
/// **Reasoning is not added to output either.** The schema does not establish
/// whether `reasoning_tokens` is already part of `output_tokens` (the usual
/// arrangement), so folding it in could double it; the reported output column
/// is taken as the output and reasoning is left out rather than summed.
/// There is no total column, so there is no remainder to reconcile.
///
/// A positive cache or reasoning figure means the record is a **known subset**
/// and is marked `isPartial`; a session with neither reports all four kinds and
/// is not marked. The flag adds and changes nothing.
///
/// **Nothing here is invented.** `billing_provider`, `message_count`, titles
/// and workspaces are read by no field of the record or are irrelevant to
/// Pulse's own pricing; the raw provider string is kept only as part of the
/// deduplication identity so two provider groups of one session stay distinct.
enum HermesReader {
    /// The default database, every profile database, and the Windows
    /// candidates. `profiles/` itself is watched while it holds no profiles,
    /// so a profile created later moves the fingerprint.
    static func inputs(home: URL, environment: [String: String]) -> [URL] {
        let root: URL
        if let value = DatabaseReaderSupport.environment("HERMES_HOME", environment) {
            root = DatabaseReaderSupport.directory(value)
        } else {
            root = home.appending(path: ".hermes", directoryHint: .isDirectory)
        }

        var roots: [URL] = [root.appending(path: "state.db")]

        let profiles = root.appending(path: "profiles", directoryHint: .isDirectory)
        let databases = DatabaseReaderSupport.subdirectories(of: profiles)
            .map { $0.appending(path: "state.db") }
        if databases.isEmpty {
            roots.append(profiles)
        } else {
            roots.append(contentsOf: databases)
        }

        if let local = DatabaseReaderSupport.localAppData(environment: environment) {
            roots.append(local.appending(path: "hermes/state.db"))
        }
        roots.append(home.appending(path: "AppData/Local/hermes/state.db"))
        return roots
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        AgentLogIO.files(in: roots, names: ["state.db"])
            .flatMap(read)
            .sorted { lhs, rhs in
                lhs.timestamp == rhs.timestamp
                    ? (lhs.deduplicationID ?? "") < (rhs.deduplicationID ?? "")
                    : lhs.timestamp < rhs.timestamp
            }
    }

    // MARK: - One database

    private static func read(_ file: URL) -> [AgentUsageRecord] {
        AgentSQLite.read(at: file) { database in
            guard !DatabaseReaderSupport.columns(database, of: "sessions").isEmpty else { return [] }

            let sessions = Self.sessions(database)
            var records = Self.perModel(database, sessions: sessions)
            let covered = Set(records.compactMap(\.sessionID))
            records.append(contentsOf: Self.sessionTotals(database, sessions: sessions, covered: covered))
            return records
        } ?? []
    }

    private struct Session {
        var model: String?
        var startedAt: Date?
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        /// Read only to mark a record partial; it is never added to a tally.
        var reasoning = 0
    }

    private static func sessions(_ database: OpaquePointer) -> [String: Session] {
        var rows: [String: Session] = [:]
        let sql = select(
            database, table: "sessions",
            columns: [
                "id", "model", "started_at", "input_tokens", "output_tokens",
                "cache_read_tokens", "cache_write_tokens", "reasoning_tokens",
            ]
        )
        AgentSQLite.each(database, sql: sql) { statement in
            guard let id = AgentSQLite.text(statement, column: 0) else { return }
            rows[id] = Session(
                model: AgentSQLite.text(statement, column: 1),
                startedAt: DatabaseReaderSupport.epoch(DatabaseReaderSupport.numberColumn(statement, 2) ?? 0),
                input: DatabaseReaderSupport.intColumn(statement, 3) ?? 0,
                output: DatabaseReaderSupport.intColumn(statement, 4) ?? 0,
                cacheRead: DatabaseReaderSupport.intColumn(statement, 5) ?? 0,
                cacheWrite: DatabaseReaderSupport.intColumn(statement, 6) ?? 0,
                reasoning: DatabaseReaderSupport.intColumn(statement, 7) ?? 0
            )
        }
        return rows
    }

    /// Pass one: group `session_model_usage` by session, model and provider,
    /// sum each column, and keep a group with any tokens. A session covered
    /// here is never read from its own row.
    private static func perModel(
        _ database: OpaquePointer,
        sessions: [String: Session]
    ) -> [AgentUsageRecord] {
        guard !DatabaseReaderSupport.columns(database, of: "session_model_usage").isEmpty else { return [] }

        struct Key: Hashable {
            let session: String
            let model: String
            let provider: String?
        }
        struct Sums {
            var input = 0
            var cacheWrite = 0
            var cacheRead = 0
            var output = 0
            var reasoning = 0
            var total: Int { input + cacheWrite + cacheRead + output + reasoning }
        }

        var groups: [Key: Sums] = [:]
        let sql = select(
            database, table: "session_model_usage",
            columns: [
                "session_id", "model", "billing_provider", "input_tokens",
                "output_tokens", "cache_read_tokens", "cache_write_tokens",
                "reasoning_tokens",
            ]
        )
        AgentSQLite.each(database, sql: sql) { statement in
            guard
                let session = AgentSQLite.text(statement, column: 0),
                let model = AgentLogIO.text(AgentSQLite.text(statement, column: 1))
            else { return }

            let key = Key(
                session: session,
                model: model,
                provider: AgentSQLite.text(statement, column: 2)
            )
            var sums = groups[key] ?? Sums()
            sums.input += DatabaseReaderSupport.intColumn(statement, 3) ?? 0
            sums.output += DatabaseReaderSupport.intColumn(statement, 4) ?? 0
            sums.cacheRead += DatabaseReaderSupport.intColumn(statement, 5) ?? 0
            sums.cacheWrite += DatabaseReaderSupport.intColumn(statement, 6) ?? 0
            sums.reasoning += DatabaseReaderSupport.intColumn(statement, 7) ?? 0
            groups[key] = sums
        }

        return groups.compactMap { key, sums in
            guard sums.total > 0, let started = sessions[key.session]?.startedAt else { return nil }
            // The literal `<null>` keeps a NULL provider a distinct key from an
            // empty string, and the two shapes cannot collide with pass two's
            // bare session id.
            let provider = key.provider ?? "<null>"
            return Self.record(
                at: started,
                model: key.model,
                input: sums.input,
                output: sums.output,
                reasoning: sums.reasoning,
                cacheRead: sums.cacheRead,
                cacheWrite: sums.cacheWrite,
                sessionID: key.session,
                deduplicationID: "hermes:\(key.session):\(key.model):\(provider)"
            )
        }
    }

    /// Pass two: the session's own row, for a session the per-model table did
    /// not cover. One record at most.
    private static func sessionTotals(
        _ database: OpaquePointer,
        sessions: [String: Session],
        covered: Set<String>
    ) -> [AgentUsageRecord] {
        sessions.compactMap { id, session in
            guard !covered.contains(id) else { return nil }
            guard let started = session.startedAt, let model = AgentLogIO.text(session.model) else {
                // No stated start and no stated model: nothing to bucket the
                // tokens under, and no timestamp or model is fabricated.
                return nil
            }
            return Self.record(
                at: started,
                model: model,
                input: session.input,
                output: session.output,
                reasoning: session.reasoning,
                cacheRead: session.cacheRead,
                cacheWrite: session.cacheWrite,
                sessionID: id,
                deduplicationID: id
            )
        }
    }

    /// One aggregate record from the reported columns.
    ///
    /// **The input/cache relationship is unproven, so it is never summed.**
    /// With no cache reported the input is the only input counter and is
    /// classified as fresh input. With a non-zero cache the reported input is
    /// carried as `unclassifiedTokens` and the cache columns are dropped:
    /// adding them beside the input would count them twice if the input
    /// already holds them, and moving them to unclassified and *also* keeping
    /// the full input is the same double count. A cache-only reading with no
    /// input counter carries no input evidence, so nothing is emitted for it.
    private static func record(
        at date: Date,
        model: String,
        input: Int,
        output: Int,
        reasoning: Int,
        cacheRead: Int,
        cacheWrite: Int,
        sessionID: String,
        deduplicationID: String
    ) -> AgentUsageRecord? {
        // `output` is the reported output column; a separate reasoning column
        // is not added to it, because it may already be inside it.
        let hasCache = cacheRead > 0 || cacheWrite > 0
        let tally = hasCache
            ? TokenTally(output: output)
            : TokenTally(input: input, output: output)
        let unclassified = hasCache ? input : 0
        guard tally.total + unclassified > 0 else { return nil }
        // A positive cache or reasoning figure is the ambiguity: the cache is
        // not added beside an input that may already hold it, and reasoning is
        // not added beside an output that may already hold it. The record is
        // therefore a known subset, marked so the summary can say so. With no
        // cache and no reasoning the four kinds are complete reported data.
        let isPartial = hasCache || reasoning > 0
        return DatabaseReaderSupport.record(
            at: date,
            model: model,
            tally: tally,
            unclassifiedTokens: unclassified,
            sessionID: sessionID,
            deduplicationID: deduplicationID,
            isAggregate: true,
            isPartial: isPartial
        )
    }

    /// A `SELECT` with a fixed column order, substituting `NULL` for a column
    /// an older schema does not have. A missing table still fails to prepare,
    /// which reads as no rows.
    private static func select(
        _ database: OpaquePointer,
        table: String,
        columns: [String]
    ) -> String {
        let present = DatabaseReaderSupport.columns(database, of: table)
        let list = columns.map { present.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        return "SELECT \(list) FROM \(table)"
    }
}
