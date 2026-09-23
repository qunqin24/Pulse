import Foundation

/// MiMo Code's OpenCode-shaped database, `mimocode*.db` under the XDG data
/// directory, unioned with the Orca hook's shared copy.
///
/// ```sql
/// message(id TEXT, session_id TEXT, data TEXT)   -- data is JSON
/// session(id, directory)                          -- optional, on older DBs
/// ```
///
/// The assistant message's JSON is the same shape OpenCode and Kilo write:
/// `modelID`, `providerID`, `tokens.{input,output,reasoning,cache{read,write}}`
/// and `time.{created,completed}`. **Both epochs are tolerated**: the created
/// time is milliseconds on current builds and seconds on older ones, and both
/// normalize to a `Date` preserving sub-second precision. Each message is an
/// increment, not a snapshot; reasoning is a real field and is folded into
/// output once, as OpenCode's own reader does here.
///
/// **The store's own cost is ignored.** Pulse prices each model from
/// `ModelPrices`; a cost the store wrote under its own route would put a
/// second, differently-sourced figure in the total.
///
/// A message's deduplication id is the JSON's own `id` when present, **not
/// namespaced by database**, so the same message in both the XDG and Orca
/// copies folds to one. Without one, the SQLite row id namespaced by the
/// database path is the fallback.
enum MicodeReader {
    static func inputs(home: URL, environment: [String: String]) -> [URL] {
        [
            DatabaseReaderSupport.xdgDataHome(home: home, environment: environment)
                .appending(path: "mimocode", directoryHint: .isDirectory),
            DatabaseReaderSupport.applicationSupport(home: home)
                .appending(path: "orca/mimocode-hooks/shared/data", directoryHint: .isDirectory),
        ]
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        AgentLogIO.files(in: roots, extensions: ["db"])
            .filter {
                let name = $0.lastPathComponent
                return name.hasPrefix("mimocode") && name.hasSuffix(".db")
            }
            .flatMap(read)
    }

    // MARK: - One database

    private static func read(_ file: URL) -> [AgentUsageRecord] {
        AgentSQLite.read(at: file) { database -> [AgentUsageRecord] in
            guard !DatabaseReaderSupport.columns(database, of: "message").isEmpty else { return [] }

            let directories = Self.directories(database)
            var records: [AgentUsageRecord] = []
            AgentSQLite.each(database, sql: "SELECT id, session_id, data FROM message") { statement in
                guard
                    let rowID = AgentSQLite.text(statement, column: 0),
                    let sessionColumn = AgentSQLite.text(statement, column: 1),
                    let data = AgentSQLite.text(statement, column: 2),
                    let root = try? JSONSerialization.jsonObject(with: Data(data.utf8)),
                    let payload = root as? [String: Any],
                    payload["role"] as? String == "assistant",
                    let model = AgentLogIO.text(payload["modelID"])
                else { return }

                guard
                    let time = payload["time"] as? [String: Any],
                    let created = DatabaseReaderSupport.number(time["created"]),
                    let timestamp = DatabaseReaderSupport.epoch(created)
                else { return }

                let counts = payload["tokens"] as? [String: Any] ?? [:]
                let cache = counts["cache"] as? [String: Any] ?? [:]
                let tally = TokenTally(
                    input: DatabaseReaderSupport.clampedCount(counts["input"]),
                    cacheWrite: DatabaseReaderSupport.clampedCount(cache["write"]),
                    cacheRead: DatabaseReaderSupport.clampedCount(cache["read"]),
                    // Reasoning is a real field and is billed as output.
                    output: DatabaseReaderSupport.clampedCount(counts["output"])
                        + DatabaseReaderSupport.clampedCount(counts["reasoning"])
                )
                guard tally.total > 0 else { return }

                let session = AgentLogIO.text(payload["sessionID"])
                    ?? AgentLogIO.text(payload["session_id"])
                    ?? sessionColumn
                let directory = directories[sessionColumn]
                let workspace = (payload["path"] as? [String: Any])
                    .flatMap { AgentLogIO.text($0["root"]) } ?? directory

                // An embedded id is the product's own identity and is not
                // namespaced, so a message written to two channel databases is
                // one message. A row id has no such identity and is namespaced.
                let embedded = AgentLogIO.text(payload["id"])
                records.append(
                    DatabaseReaderSupport.record(
                        at: timestamp,
                        model: model,
                        tally: tally,
                        sessionID: session,
                        project: workspace,
                        deduplicationID: embedded ?? "micode:\(file.path):\(rowID)"
                    )
                )
            }
            return records
        } ?? []
    }

    /// `session.id` to its `directory`, where the older schema keeps it.
    private static func directories(_ database: OpaquePointer) -> [String: String] {
        guard
            !DatabaseReaderSupport.columns(database, of: "session").isEmpty,
            DatabaseReaderSupport.columns(database, of: "session").contains("directory")
        else { return [:] }

        var rows: [String: String] = [:]
        AgentSQLite.each(database, sql: "SELECT id, directory FROM session") { statement in
            guard
                let id = AgentSQLite.text(statement, column: 0),
                let directory = AgentSQLite.text(statement, column: 1)
            else { return }
            rows[id] = directory
        }
        return rows
    }
}
