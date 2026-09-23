import Foundation

/// Copilot's desktop SQLite database and its session-state sidecar.
///
/// ```sql
/// sessions(id, title, model, total_input_tokens, total_output_tokens,
///          total_cached_tokens, total_reasoning_tokens, total_nano_aiu,
///          created_at)
/// ```
///
/// **The database row is lifetime, the sidecar is a running total.** A row's
/// token columns are cumulative against its immutable `created_at`; the sidecar
/// event log (`session-state/<id>/events.jsonl`) writes a `session.shutdown`
/// snapshot every time a run ends, each one the same rising tracker total. The
/// snapshots are differenced per model into increments before a record is made,
/// and the database row is then the authority: a per-row budget caps what the
/// sidecar may contribute, and whatever the increments leave unexplained is
/// emitted once at `created_at` so the row's lifetime figure is never lost.
///
/// **A missing head is not an increment.** When the event log does not open
/// with `session.start`, its earliest snapshot is an unknown baseline rather
/// than that run's work; the first snapshot is used only to difference the
/// ones after it, and its tokens fall to the `created_at` remainder.
///
/// **cache_write lives only here.** The database has no cache-write column, so
/// that bucket is always sidecar-authoritative and is never part of the budget
/// or the remainder. The four buckets the database does store are read from it.
///
/// **Reasoning is not added to output.** The sidecar and the row report
/// `outputTokens` and `reasoningTokens` side by side and neither says whether
/// the reasoning is already inside the output. The GenAI convention makes it a
/// subset, but the Copilot SDK's own schema — checked for the shutdown metric —
/// states only that each is "total … produced across all requests" and does not
/// declare containment. So the reported output is kept whole and the ambiguous
/// reasoning count is not placed in any bucket: adding it would double count a
/// subset, and carrying it in `unclassifiedTokens` would add it to the grand
/// total just the same. A run or a row that stated reasoning is instead marked
/// `isPartial`, so the shortfall is visible rather than silently complete.
///
/// Every record from this lane is aggregate: a shutdown snapshot is
/// session-level timing, not the instant the tokens were spent.
enum CopilotDesktopReader {
    static func records(database: URL) -> [AgentUsageRecord] {
        let sidecar = database.deletingLastPathComponent()
            .appending(path: "session-state", directoryHint: .isDirectory)

        return AgentSQLite.read(at: database) { connection -> [AgentUsageRecord] in
            guard !DatabaseReaderSupport.columns(connection, of: "sessions").isEmpty else { return [] }

            var output: [AgentUsageRecord] = []
            AgentSQLite.each(connection, sql: select(connection)) { statement in
                guard let row = self.row(statement) else { return }
                output.append(contentsOf: read(row, sidecarRoot: sidecar))
            }
            return output
        } ?? []
    }

    // MARK: - One session

    private struct Row {
        let id: String
        let title: String?
        let model: String?
        let input: Int
        let output: Int
        let cached: Int
        let reasoning: Int
        let createdAt: Date?
    }

    private struct Counts {
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var reasoning = 0

        /// The four kinds Pulse actually counts. `reasoning` is deliberately
        /// **not** part of it: the store never states that reasoning is inside
        /// `output`, so it is never added to a bucket. A run that stated
        /// reasoning is marked partial instead.
        var counted: Int { input + output + cacheRead + cacheWrite }
        /// True when the source stated a reasoning count Pulse did not place.
        var omittedReasoning: Bool { reasoning > 0 }

        mutating func add(_ other: Counts) {
            input += other.input
            output += other.output
            cacheRead += other.cacheRead
            cacheWrite += other.cacheWrite
            reasoning += other.reasoning
        }
    }

    private static func read(_ row: Row, sidecarRoot: URL) -> [AgentUsageRecord] {
        let events = AgentLogIO.jsonLines(at: sidecarRoot.appending(path: row.id).appending(path: "events.jsonl"))

        var running: [String: Counts] = [:]
        var applied = Counts()
        var trackedModel = row.model
        var workspace: String?
        var openedWithStart = false
        var sawFirst = false
        var records: [AgentUsageRecord] = []

        for (index, event) in events.enumerated() {
            let type = AgentLogIO.text(event["type"])
            if !sawFirst {
                sawFirst = true
                openedWithStart = (type == "session.start")
            }

            switch type ?? "" {
            case "session.start":
                if let cwd = self.workspace(event) { workspace = cwd }

            case "session.model_change":
                if let next = AgentLogIO.text((event["data"] as? [String: Any])?["newModel"]),
                   next != "auto" {
                    trackedModel = next
                }

            case "session.shutdown":
                // A snapshot with no stated time cannot be placed; its tokens
                // fall to the remainder at `created_at` instead.
                guard let timestamp = eventTimestamp(event) else { continue }
                let data = event["data"] as? [String: Any]
                let metrics = data?["modelMetrics"] as? [String: Any] ?? [:]
                let identity = eventIdentity(event, index: index)

                for (tracker, entry) in metrics.sorted(by: { $0.key < $1.key }) {
                    guard let current = usage(entry) else { continue }
                    let model = resolvedModel(
                        tracker: tracker, data: data, tracked: trackedModel, row: row.model
                    )
                    let previous = running[model]
                    let delta = subtract(current, previous)
                    running[model] = current

                    // The log did not open with a start, so its earliest
                    // snapshot is an unknown baseline rather than a delta.
                    if previous == nil, !openedWithStart { continue }

                    let budgeted = budget(delta, applied: applied, row: row)
                    applied.add(budgeted)
                    guard budgeted.counted > 0 else { continue }

                    guard
                        let record = StructuredLogSupport.record(
                            timestamp: timestamp,
                            model: model,
                            tally: tally(budgeted),
                            isAggregate: true,
                            // The **run itself** stated reasoning Pulse could
                            // not place, so this record is a known subset. The
                            // flag reads the run's delta, not the row-budgeted
                            // copy: an older row with no reasoning column must
                            // not hide the reasoning the sidecar wrote.
                            isPartial: delta.omittedReasoning,
                            sessionID: row.id,
                            title: row.title,
                            project: workspace,
                            deduplicationID: "copilot-desktop:\(row.id):shutdown:\(identity):\(model)"
                        )
                    else { continue }
                    records.append(record)
                }

            default:
                break
            }
        }

        // Whatever the snapshots did not account for — a run that died before
        // shutdown, a session the CLI wrote, or a missing head — is emitted
        // once at the row's immutable creation time.
        let remainder = residual(applied, row: row)
        if remainder.counted > 0, let createdAt = row.createdAt {
            if let record = StructuredLogSupport.record(
                timestamp: createdAt,
                model: row.model ?? trackedModel ?? "auto",
                tally: tally(remainder),
                isAggregate: true,
                isPartial: remainder.omittedReasoning,
                sessionID: row.id,
                title: row.title,
                project: workspace,
                deduplicationID: "copilot-desktop:\(row.id):row"
            ) {
                records.append(record)
            }
        }

        return records
    }

    /// The tally for a run or remainder. The reported output is kept as is and
    /// the ambiguous reasoning is never added: see the file's header.
    private static func tally(_ counts: Counts) -> TokenTally {
        TokenTally(
            input: counts.input,
            cacheWrite: counts.cacheWrite,
            cacheRead: counts.cacheRead,
            output: StructuredLogSupport.output(
                reported: counts.output,
                reasoning: counts.reasoning,
                relationship: .unknown
            )
        )
    }

    // MARK: - Budget and remainder

    /// The sidecar's next increment, capped so it can never carry a row past
    /// its own lifetime total. cache_write has no row to compare against.
    private static func budget(_ delta: Counts, applied: Counts, row: Row) -> Counts {
        Counts(
            input: min(delta.input, max(row.input - applied.input, 0)),
            output: min(delta.output, max(row.output - applied.output, 0)),
            cacheRead: min(delta.cacheRead, max(row.cached - applied.cacheRead, 0)),
            cacheWrite: delta.cacheWrite,
            reasoning: min(delta.reasoning, max(row.reasoning - applied.reasoning, 0))
        )
    }

    private static func residual(_ applied: Counts, row: Row) -> Counts {
        Counts(
            input: max(row.input - applied.input, 0),
            output: max(row.output - applied.output, 0),
            cacheRead: max(row.cached - applied.cacheRead, 0),
            cacheWrite: 0,
            reasoning: max(row.reasoning - applied.reasoning, 0)
        )
    }

    private static func subtract(_ current: Counts, _ previous: Counts?) -> Counts {
        guard let previous else { return current }
        return Counts(
            input: max(current.input - previous.input, 0),
            output: max(current.output - previous.output, 0),
            cacheRead: max(current.cacheRead - previous.cacheRead, 0),
            cacheWrite: max(current.cacheWrite - previous.cacheWrite, 0),
            reasoning: max(current.reasoning - previous.reasoning, 0)
        )
    }

    // MARK: - Event fields

    private static func workspace(_ event: [String: Any]) -> String? {
        let data = event["data"] as? [String: Any]
        let context = data?["context"] as? [String: Any]
        return AgentLogIO.text(context?["cwd"])
    }

    private static func usage(_ entry: Any) -> Counts? {
        guard
            let entry = entry as? [String: Any],
            let usage = entry["usage"] as? [String: Any]
        else { return nil }
        return Counts(
            input: DatabaseReaderSupport.clampedCount(usage["inputTokens"]),
            output: DatabaseReaderSupport.clampedCount(usage["outputTokens"]),
            cacheRead: DatabaseReaderSupport.clampedCount(usage["cacheReadTokens"]),
            cacheWrite: DatabaseReaderSupport.clampedCount(usage["cacheWriteTokens"]),
            reasoning: DatabaseReaderSupport.clampedCount(usage["reasoningTokens"])
        )
    }

    /// A tracker key of `""` or `"auto"` defers to the run's current model,
    /// then to the last change, then to the row.
    private static func resolvedModel(
        tracker: String,
        data: [String: Any]?,
        tracked: String?,
        row: String?
    ) -> String {
        if !tracker.isEmpty, tracker != "auto" { return tracker }
        if let current = AgentLogIO.text(data?["currentModel"]) { return current }
        if let tracked { return tracked }
        if let row { return row }
        return "auto"
    }

    private static func eventTimestamp(_ event: [String: Any]) -> Date? {
        if let date = DatabaseReaderSupport.flexible(event["timestamp"]) { return date }
        if let data = event["data"] as? [String: Any],
           let date = DatabaseReaderSupport.flexible(data["timestamp"]) {
            return date
        }
        return nil
    }

    /// The envelope's own id, else a stable hash of the event JSON, else its
    /// position. The id is what keeps two runs' snapshots apart.
    private static func eventIdentity(_ event: [String: Any], index: Int) -> String {
        if let id = AgentLogIO.text(event["id"]) { return id }
        if
            let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        {
            return CopilotLogReader.stableHash(text)
        }
        return "idx-\(index)"
    }

    // MARK: - Database

    private static func row(_ statement: OpaquePointer) -> Row? {
        guard let id = AgentSQLite.text(statement, column: 0) else { return nil }
        let input = DatabaseReaderSupport.intColumn(statement, 3) ?? 0
        let output = DatabaseReaderSupport.intColumn(statement, 4) ?? 0
        let cached = DatabaseReaderSupport.intColumn(statement, 5) ?? 0
        let reasoning = DatabaseReaderSupport.intColumn(statement, 6) ?? 0

        // A row with no tokens at all is not work; every one of the four
        // buckets must be zero for it to be skipped.
        guard input > 0 || output > 0 || cached > 0 || reasoning > 0 else { return nil }

        return Row(
            id: id,
            title: AgentSQLite.text(statement, column: 1),
            model: AgentLogIO.text(AgentSQLite.text(statement, column: 2)),
            input: input,
            output: output,
            cached: cached,
            reasoning: reasoning,
            createdAt: DatabaseReaderSupport.flexible(AgentSQLite.text(statement, column: 7))
        )
    }

    /// A fixed column order, substituting `NULL` for a column an older schema
    /// lacks. A missing table fails to prepare and reads as no rows.
    private static func select(_ database: OpaquePointer) -> String {
        let present = DatabaseReaderSupport.columns(database, of: "sessions")
        let columns = [
            "id", "title", "model", "total_input_tokens", "total_output_tokens",
            "total_cached_tokens", "total_reasoning_tokens", "created_at",
        ]
        let list = columns.map { present.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        return "SELECT \(list) FROM sessions"
    }
}
