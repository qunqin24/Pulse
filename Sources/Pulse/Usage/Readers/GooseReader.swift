// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Goose's session database, `sessions.db`, under its XDG, macOS or legacy
/// Block data directory — the first candidate that exists wins.
///
/// ```sql
/// sessions(id, model_config_json, provider_name, created_at, total_tokens,
///          input_tokens, output_tokens, accumulated_total_tokens,
///          accumulated_input_tokens, accumulated_output_tokens)
/// ```
///
/// **The accumulated columns are cumulative and are preferred.** A session
/// that grows between reads changes its figures under the same id, so this is
/// one record per session — an aggregate, not a turn. The non-accumulated
/// columns are the fallback for a build that wrote no accumulated ones.
///
/// **The difference is unclassified, never reasoning.** Goose carries no
/// reasoning counter and no cache columns. Its `total_tokens` may or may not
/// include reasoning, and deriving `max(0, total − input − output)` as
/// reasoning — as the compatibility target does — is a claim about a schema
/// that does not state it. Pulse keeps that remainder as **unclassified**:
/// counted, never priced, never shown as a kind. Cache read and cache write
/// are genuinely absent and stay zero.
///
/// A session whose `created_at` cannot be read is skipped rather than dated
/// 1970: a record must not be bucketed on a date nobody wrote.
enum GooseReader {
    /// Every candidate, in priority order, so the fingerprint watches each
    /// while the reader takes the first that exists.
    static func inputs(home: URL, environment: [String: String]) -> [URL] {
        var candidates: [URL] = []
        if let root = DatabaseReaderSupport.environment("GOOSE_PATH_ROOT", environment) {
            candidates.append(
                DatabaseReaderSupport.directory(root).appending(path: "data/sessions/sessions.db")
            )
        }
        candidates.append(
            DatabaseReaderSupport.applicationSupport(home: home).appending(path: "goose/sessions/sessions.db")
        )
        candidates.append(
            DatabaseReaderSupport.xdgDataHome(home: home, environment: environment)
                .appending(path: "goose/sessions/sessions.db")
        )
        candidates.append(
            DatabaseReaderSupport.applicationSupport(home: home)
                .appending(path: "Block/goose/sessions/sessions.db")
        )
        candidates.append(
            home.appending(path: ".local/share/Block/goose/sessions/sessions.db")
        )
        return candidates
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let candidates = roots.filter { $0.lastPathComponent == "sessions.db" }
        guard let database = DatabaseReaderSupport.firstExisting(candidates) else { return [] }
        return Self.read(database)
    }

    // MARK: - One database

    private static func read(_ file: URL) -> [AgentUsageRecord] {
        AgentSQLite.read(at: file) { database -> [AgentUsageRecord] in
            let present = DatabaseReaderSupport.columns(database, of: "sessions")
            guard !present.isEmpty else { return [] }

            var records: [AgentUsageRecord] = []
            let sql = select(database, present: present)
            AgentSQLite.each(database, sql: sql) { statement in
                guard let id = AgentSQLite.text(statement, column: 0) else { return }
                guard
                    let config = AgentSQLite.text(statement, column: 1),
                    let model = Self.model(in: config),
                    let createdAt = AgentSQLite.text(statement, column: 2),
                    let timestamp = DatabaseReaderSupport.utc(
                        createdAt, formats: ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"]
                    )
                else { return }

                // The accumulated columns are cumulative and preferred; the
                // plain ones are the fallback for a build that wrote none.
                let input = DatabaseReaderSupport.intColumn(statement, 6)
                    ?? DatabaseReaderSupport.intColumn(statement, 3)
                    ?? 0
                let output = DatabaseReaderSupport.intColumn(statement, 7)
                    ?? DatabaseReaderSupport.intColumn(statement, 4)
                    ?? 0
                let total = DatabaseReaderSupport.intColumn(statement, 8)
                    ?? DatabaseReaderSupport.intColumn(statement, 5)
                    ?? 0

                guard input > 0 || output > 0 || total > 0 else { return }

                let known = input + output
                records.append(
                    DatabaseReaderSupport.record(
                        at: timestamp,
                        model: model,
                        tally: TokenTally(input: input, output: output),
                        // A total larger than the kinds it names: the part
                        // that cannot be attributed is kept as such.
                        unclassifiedTokens: max(0, total - known),
                        sessionID: id,
                        deduplicationID: id,
                        isAggregate: true
                    )
                )
            }
            return records
        } ?? []
    }

    /// `model_config_json.model_name`, or nil for a NULL/blank config, a
    /// config that is not an object, or a blank model name. Other keys are
    /// ignored.
    private static func model(in config: String) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(config.utf8)),
            let object = root as? [String: Any]
        else { return nil }
        return AgentLogIO.text(object["model_name"])
    }

    /// The declared columns in a fixed order, with `NULL` for any an older
    /// schema lacks. `model_config_json` is parsed rather than read plain.
    private static func select(_ database: OpaquePointer, present: Set<String>) -> String {
        let columns = [
            "id", "model_config_json", "created_at", "input_tokens", "output_tokens",
            "total_tokens", "accumulated_input_tokens", "accumulated_output_tokens",
            "accumulated_total_tokens",
        ]
        let list = columns.map { present.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        return "SELECT \(list) FROM sessions"
    }
}
