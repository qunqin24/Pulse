import Foundation
import SQLite3

/// ZCode's transcripts and its v2 usage database.
///
/// Two sources are read: JSONL under `projects/`, and the `model_usage` table
/// of `cli/db/db.sqlite`.
///
/// **JSONL:** a reported `total` settles whether input and output already
/// contain the cache and reasoning counts. The cache overlap is removed from
/// input only when the total says input includes it, and reasoning is folded
/// into output only when the total counts it separately — so output containing
/// reasoning is never double-counted. A total that fits neither shape is kept
/// whole as unclassified rather than guessed at.
///
/// **Database:** the schema documents `input_tokens` as cache-inclusive and
/// `output_tokens` as reasoning-inclusive, so the cache overlap is always
/// removed from input and `reasoning_tokens` is never added a second time. A
/// `computed_total_tokens` beyond `input + output` is kept as unclassified.
///
/// **A total with no split is not input.** Where a line reports only a total,
/// the record carries `unclassifiedTokens` and an empty tally. A legacy line
/// with no usage block at all contributes nothing: the old format's counts
/// would have to be estimated from string lengths, which is not a reported
/// token and is not done here.
enum ZCodeReader {
    static let supportedClients: Set<String> = ["zcode"]

    static func inputs(home: URL) -> [URL] {
        [
            home.appending(path: ".zcode/projects"),
            home.appending(path: ".zcode/cli/db/db.sqlite"),
        ]
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["jsonl"], names: ["db.sqlite"])
        var records: [AgentUsageRecord] = []
        for file in files {
            if file.pathExtension == "jsonl" {
                records += jsonl(file)
            } else if file.lastPathComponent == "db.sqlite" {
                records += database(file)
            }
        }
        return records.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - JSONL transcripts

    private static func jsonl(_ file: URL) -> [AgentUsageRecord] {
        let stem = file.deletingPathExtension().lastPathComponent
        var records: [AgentUsageRecord] = []

        for (index, row) in AgentLogIO.jsonLines(at: file).enumerated() {
            guard
                let timestamp = AgentLogIO.timestamp(row["timestamp"], milliseconds: true),
                let model = EditorLog.modelID(AgentLogIO.text(row["model"]))
            else { continue }

            // The `usage` object wins when it yields a split; otherwise the
            // alternate `token_usage` spelling is tried.
            var parts = usage(AgentLogIO.object(row["usage"]) ?? [:])
            if parts.tally.total + parts.unclassified == 0 {
                parts = usage(AgentLogIO.object(row["token_usage"]) ?? [:])
            }
            guard parts.tally.total + parts.unclassified > 0 else { continue }

            let session = EditorLog.nonBlank(AgentLogIO.text(row["sessionId"])) ?? stem
            records.append(
                EditorLog.record(
                    timestamp: timestamp,
                    model: model,
                    tally: parts.tally,
                    sessionID: session,
                    deduplicationID: "zcode:\(file.path):\(index):\(session):\(timestamp.timeIntervalSince1970)",
                    unclassifiedTokens: parts.unclassified
                )
            )
        }
        return records
    }

    private static func usage(_ object: [String: Any]) -> EditorLog.UsageParts {
        EditorLog.combine(
            input: EditorLog.firstCount(object, ["input_tokens", "prompt_tokens", "inputTokens"]),
            output: EditorLog.firstCount(object, ["output_tokens", "completion_tokens", "outputTokens"]),
            cacheRead: EditorLog.firstCount(object, [
                "input_cache_read", "cache_read_tokens", "cacheReadTokens",
            ]),
            cacheWrite: EditorLog.firstCount(object, [
                "input_cache_creation", "cache_write_tokens", "cacheCreationTokens",
            ]),
            reasoning: EditorLog.firstCount(object, ["reasoningTokens", "reasoning_tokens"]),
            total: EditorLog.firstCount(object, ["totalTokens", "total_tokens"]),
            inputMayIncludeCache: true
        )
    }

    // MARK: - The v2 database

    private static func database(_ file: URL) -> [AgentUsageRecord] {
        let rows: [AgentUsageRecord]? = AgentSQLite.read(at: file) { database in
            let columns = columnNames(database, table: "model_usage")
            guard !columns.isEmpty else { return [] }
            let hasSession = tableExists(database, "session")

            // Only the columns the schema actually has are selected, so a
            // legacy table without `computed_total_tokens` still reads.
            var labels: [String] = []
            var expressions: [String] = []
            let prefix = hasSession ? "mu." : ""
            for name in [
                "id", "session_id", "model_id", "started_at", "completed_at",
                "input_tokens", "output_tokens", "reasoning_tokens",
                "cache_read_input_tokens", "cache_creation_input_tokens",
                "computed_total_tokens",
            ] where columns.contains(name) {
                labels.append(name)
                expressions.append(prefix + name)
            }
            if hasSession {
                labels.append("directory")
                labels.append("path")
                expressions.append("s.directory")
                expressions.append("s.path")
            }

            var indices: [String: Int32] = [:]
            for (position, label) in labels.enumerated() { indices[label] = Int32(position) }

            var found: [AgentUsageRecord] = []
            let sql = "SELECT " + expressions.joined(separator: ", ")
                + " FROM model_usage" + (hasSession ? " mu LEFT JOIN session s ON s.id = mu.session_id" : "")

            AgentSQLite.each(database, sql: sql) { statement in
                func text(_ label: String) -> String? {
                    guard let index = indices[label] else { return nil }
                    return AgentSQLite.text(statement, column: index)
                }
                func count(_ label: String) -> Int? { AgentLogIO.count(text(label)) }

                let started = AgentLogIO.timestamp(text("started_at"), milliseconds: true)
                let completed = AgentLogIO.timestamp(text("completed_at"), milliseconds: true)
                guard
                    let timestamp = started ?? completed,
                    let sessionID = text("session_id")
                else { return }

                let rawInput = count("input_tokens") ?? 0
                let rawOutput = count("output_tokens") ?? 0
                let cacheRead = count("cache_read_input_tokens") ?? 0
                let cacheWrite = count("cache_creation_input_tokens") ?? 0
                let computed = count("computed_total_tokens")

                // This schema documents `input_tokens` as cache-inclusive and
                // `output_tokens` as reasoning-inclusive, so the cache overlap
                // is removed from input and `reasoning_tokens` is **not** added
                // to output a second time. The union is therefore
                // input + output, and the reported total can only add an
                // unclassified remainder beyond it.
                let freshInput = max(0, rawInput - cacheRead - cacheWrite)
                var unclassified = 0
                if let computed, computed > rawInput + rawOutput {
                    unclassified = computed - (rawInput + rawOutput)
                }

                let identifier = text("id") ?? "\(sessionID)#\(started?.timeIntervalSince1970 ?? 0)"
                let directory = text("directory") ?? text("path")
                found.append(
                    EditorLog.record(
                        timestamp: timestamp,
                        model: EditorLog.modelID(text("model_id")) ?? "auto",
                        // `output_tokens` already contains reasoning in this
                        // schema, so reasoning is not folded in a second time.
                        tally: TokenTally(
                            input: freshInput,
                            cacheWrite: cacheWrite,
                            cacheRead: cacheRead,
                            output: rawOutput
                        ),
                        sessionID: sessionID,
                        project: directory,
                        deduplicationID: "zcode:\(file.path):\(identifier)",
                        unclassifiedTokens: unclassified
                    )
                )
            }
            return found
        }
        return rows ?? []
    }

    private static func columnNames(_ database: OpaquePointer, table: String) -> Set<String> {
        var names: Set<String> = []
        AgentSQLite.each(database, sql: "PRAGMA table_info(\(table))") { statement in
            if let name = AgentSQLite.text(statement, column: 1) { names.insert(name) }
        }
        return names
    }

    private static func tableExists(_ database: OpaquePointer, _ table: String) -> Bool {
        var exists = false
        AgentSQLite.each(
            database,
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '\(table)'"
        ) { _ in exists = true }
        return exists
    }
}
