import Foundation

/// Devin Desktop's ACP event captures, `*.ndjson` under the app's
/// `User/acp-events` directory, with the CLI's session database read only as a
/// **lookup** and, when its usage is counted separately, a source-precedence check.
///
/// **Two shapes, told apart by evidence, not a version marker.** The canonical
/// ACP `usage_update` carries its figures under `notification._meta`:
/// `inputTokens` is the complete prompt **including** `cachedReadTokens`,
/// output accumulates per step, and the cached buckets overwrite. One
/// aggregate record is emitted per file: fresh input is
/// `inputTokens − cachedReadTokens`, output is the summed output, cache read
/// and write are the last reported values. A capture with no `_meta` fields —
/// an older or mislabelled event — falls back to a usage object under the
/// metadata locations, and emits **one record per metric-bearing event**.
///
/// **The database supplies identity, not additional tokens on this route.** Its
/// `sessions.title` maps to `{id, model, working_directory}` so a Desktop file
/// whose name is an unrelated UUID recovers a stable session id, model and
/// workspace. A title two database sessions share is ambiguous and is ignored.
/// Most Desktop captures carry no usage at all; the CLI database is usually
/// where the authoritative figures are, and this reader never invents the
/// difference.
/// When the catalogue counts that database's messages separately, a capture
/// matched to one of its counted sessions is excluded as a mirror.
///
/// `reasoning` is never reported here, so it stays zero. A missing timestamp
/// is skipped rather than filled from the file's modification date, and
/// `adaptive` — a routing mode, not a model — is never a model name.
enum DevinDesktopReader {
    static func inputs(home: URL, environment: [String: String]) -> [URL] {
        var roots: [URL] = [
            DatabaseReaderSupport.applicationSupport(home: home)
                .appending(path: "Devin/User/acp-events", directoryHint: .isDirectory),
            home.appending(path: ".config/devin/User/acp-events", directoryHint: .isDirectory),
        ]
        // The lookup database. Read, never written.
        roots.append(home.appending(path: ".local/share/devin/cli/sessions.db"))
        if let appData = DatabaseReaderSupport.appData(environment: environment) {
            roots.append(appData.appending(path: "devin/cli/sessions.db"))
        }
        return roots
    }

    /// When the spend catalogue also reads a database as Devin's native
    /// ledger, that database owns its counted sessions. Captures for an
    /// unambiguously matched session are a mirror, not another agent's work.
    /// Other lookup databases are metadata only and cannot suppress a record.
    static func records(roots: [URL], authoritativeDatabases: [URL] = []) -> [AgentUsageRecord] {
        let authoritative = Set(authoritativeDatabases.map { $0.resolvingSymlinksInPath().path })
        let lookup = sessions(roots, authoritative: authoritative)
        return AgentLogIO.files(in: roots, extensions: ["ndjson"]).flatMap {
            read($0, lookup: lookup)
        }
    }

    // MARK: - The CLI lookup

    private struct Session {
        let id: String
        let model: String?
        let directory: String?
        let hasCountedUsage: Bool
    }

    /// `sessions.title` to the sessions that carry it. A title held by more
    /// than one session is ambiguous and resolved to nil by throwing it away.
    private static func sessions(_ roots: [URL], authoritative: Set<String>) -> [String: [Session]] {
        var table: [String: [Session]] = [:]
        for file in AgentLogIO.files(in: roots, names: ["sessions.db"]) {
            _ = AgentSQLite.read(at: file) { database in
                let columns = DatabaseReaderSupport.columns(database, of: "sessions")
                guard columns.contains("id"), columns.contains("title") else { return }
                let model = columns.contains("model") ? "model" : "NULL"
                let directory = columns.contains("working_directory") ? "working_directory" : "NULL"
                let counted = authoritative.contains(file.resolvingSymlinksInPath().path)
                    ? DevinCLIStore.countedSessionIDs(in: database) : []
                AgentSQLite.each(
                    database, sql: "SELECT id, title, \(model), \(directory) FROM sessions"
                ) { statement in
                    guard
                        let id = AgentSQLite.text(statement, column: 0),
                        let title = AgentLogIO.text(AgentSQLite.text(statement, column: 1))
                    else { return }
                    table[title, default: []].append(
                        Session(
                            id: id,
                            model: AgentLogIO.text(AgentSQLite.text(statement, column: 2)),
                            directory: AgentLogIO.text(AgentSQLite.text(statement, column: 3)),
                            hasCountedUsage: counted.contains(id)
                        )
                    )
                }
            }
        }
        return table
    }

    // MARK: - One capture

    private static func read(_ file: URL, lookup: [String: [Session]]) -> [AgentUsageRecord] {
        let lines = AgentLogIO.jsonLines(at: file)
        var title: String?
        var records: [AgentUsageRecord] = []

        // The canonical aggregate across the file.
        var latestInput: Int?
        var latestRead = 0
        var latestWrite = 0
        var summedOutput = 0
        var model: String?
        var timestamp: Date?

        for (index, line) in lines.enumerated() {
            guard let notification = line["notification"] as? [String: Any] else { continue }

            if notification["sessionUpdate"] as? String == "session_info_update",
               let stated = AgentLogIO.text(notification["title"]) {
                title = stated
            }

            if let canonical = canonical(notification) {
                // `inputTokens` is the complete prompt, so it overwrites; the
                // cached buckets overwrite too; output is summed per step.
                if let input = canonical.input { latestInput = input }
                if let read = canonical.cacheRead { latestRead = read }
                if let write = canonical.cacheWrite { latestWrite = write }
                summedOutput += canonical.output
                model = Self.model(in: notification, meta: canonical.meta) ?? model
                timestamp = canonical.timestamp ?? timestamp
                continue
            }

            // A non-canonical event: an older capture that kept its usage
            // under the metadata locations. One record per event.
            guard let legacy = legacy(notification, index: index, file: file, title: title, lookup: lookup)
            else { continue }
            records.append(legacy)
        }

        if let input = latestInput {
            let fresh = max(0, input - latestRead)
            let tally = TokenTally(input: fresh, cacheWrite: latestWrite, cacheRead: latestRead, output: summedOutput)
            if let timestamp, tally.total > 0 {
                let resolved = resolve(title: title, lookup: lookup)
                if resolved?.hasCountedUsage == true { return records }
                records.append(
                    DatabaseReaderSupport.record(
                        at: timestamp,
                        model: modelName(model ?? resolved?.model),
                        tally: tally,
                        sessionID: resolved?.id ?? DatabaseReaderSupport.stem(file),
                        project: resolved?.directory,
                        deduplicationID: "devin-desktop:\(file.path):usage",
                        isAggregate: true
                    )
                )
            }
        }
        return records
    }

    /// The canonical ACP usage under `notification._meta`, or nil when the
    /// event does not carry it.
    private struct Canonical {
        var input: Int?
        var cacheRead: Int?
        var cacheWrite: Int?
        var output = 0
        var timestamp: Date?
        var meta: [String: Any]
    }

    private static func canonical(_ notification: [String: Any]) -> Canonical? {
        guard update(notification) == "usage_update",
              let meta = notification["_meta"] as? [String: Any]
        else { return nil }

        let prefix = "cognition.ai/"
        let input = AgentLogIO.count(meta["\(prefix)inputTokens"])
        let read = AgentLogIO.count(meta["\(prefix)cachedReadTokens"])
        let write = AgentLogIO.count(meta["\(prefix)cachedWriteTokens"])
        let output = AgentLogIO.count(meta["\(prefix)outputTokens"])
        guard input != nil || read != nil || write != nil || output != nil else { return nil }

        return Canonical(
            input: input,
            cacheRead: read,
            cacheWrite: write,
            output: output ?? 0,
            timestamp: DatabaseReaderSupport.flexible(notification["created_at"]),
            meta: meta
        )
    }

    /// The legacy shape: a usage object under one of the metadata locations,
    /// with fields named with underscores. One record per event, keyed by the
    /// event's line index because no other identity exists.
    private static func legacy(
        _ notification: [String: Any],
        index: Int,
        file: URL,
        title: String?,
        lookup: [String: [Session]]
    ) -> AgentUsageRecord? {
        let content = notification["content"] as? [String: Any]
        let contentMetadata = content?["metadata"] as? [String: Any]
        let metadata = notification["metadata"] as? [String: Any]

        let candidates: [[String: Any]] = [
            contentMetadata?["metrics"] as? [String: Any],
            metadata?["metrics"] as? [String: Any],
            notification["metrics"] as? [String: Any],
            contentMetadata,
            metadata,
        ].compactMap { $0 }

        for usage in candidates {
            let hasTokens = ["input_tokens", "output_tokens", "cache_read_tokens", "cache_creation_tokens"]
                .contains { AgentLogIO.count(usage[$0]) != nil }
            guard hasTokens else { continue }

            let tally = TokenTally(
                input: AgentLogIO.count(usage["input_tokens"]) ?? 0,
                cacheWrite: AgentLogIO.count(usage["cache_creation_tokens"]) ?? 0,
                cacheRead: AgentLogIO.count(usage["cache_read_tokens"]) ?? 0,
                output: AgentLogIO.count(usage["output_tokens"]) ?? 0
            )
            guard tally.total > 0 else { continue }

            let timestamp = DatabaseReaderSupport.flexible(contentMetadata?["created_at"])
                ?? DatabaseReaderSupport.flexible(metadata?["created_at"])
                ?? DatabaseReaderSupport.flexible(notification["created_at"])
                ?? DatabaseReaderSupport.flexible(notification["timestamp"])
            guard let timestamp else { continue }

            let hinted = AgentLogIO.text(contentMetadata?["generation_model"])
                ?? AgentLogIO.text(metadata?["generation_model"])
                ?? (notification["_meta"] as? [String: Any])
                    .flatMap { AgentLogIO.text($0["cognition.ai/model"]) }
            let resolved = resolve(title: title, lookup: lookup)
            if resolved?.hasCountedUsage == true { return nil }

            return DatabaseReaderSupport.record(
                at: timestamp,
                model: modelName(hinted ?? resolved?.model),
                tally: tally,
                sessionID: resolved?.id ?? DatabaseReaderSupport.stem(file),
                project: resolved?.directory,
                deduplicationID: "devin-desktop:\(file.path):\(index)"
            )
        }
        return nil
    }

    private static func update(_ notification: [String: Any]) -> String? {
        notification["sessionUpdate"] as? String
    }

    /// The model hint priority for the canonical shape.
    private static func model(in notification: [String: Any], meta: [String: Any]) -> String? {
        AgentLogIO.text(notification["notification_model"])
            ?? AgentLogIO.text(meta["cognition.ai/model"])
    }

    /// `adaptive` is a routing mode, not a model, and an unresolved file gets
    /// `unknown` — an unpriced name — rather than a concrete model invented
    /// for the product, which would be priced at the wrong rate.
    private static func modelName(_ value: String?) -> String {
        guard let value, value != "adaptive" else { return "unknown" }
        return value
    }

    /// The CLI session whose title is this file's, when exactly one matches.
    private static func resolve(
        title: String?,
        lookup: [String: [Session]]
    ) -> Session? {
        guard let title, let matches = lookup[title], matches.count == 1 else { return nil }
        return matches[0]
    }
}
