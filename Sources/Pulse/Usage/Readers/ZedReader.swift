import Foundation

/// Zed's thread database, `threads.db`, under its XDG, macOS or Windows data
/// directory.
///
/// Each row's `data` blob is a thread as JSON, or a zstd frame that decodes to
/// the same JSON. A compressed row is decoded through the shared
/// system-library decoder (`DSHZstdDecoder`) and then parsed exactly as the
/// plain form is; a payload larger than 32 MiB is refused either way. A row is
/// treated as compressed when its `data_type` says `zstd` **or** its raw bytes
/// carry the zstd magic, so a mislabelled frame is still read.
///
/// **A compressed row that cannot be read is reported, not forgotten.**
/// `records` emits nothing for it, and `notes(roots:)` names it — whether the
/// system library is missing, the frame is corrupt, or it is over a bound.
/// The two share one pure decode result, so they cannot disagree about which
/// rows were readable, and a store of plain JSON threads reports nothing.
///
/// Only threads whose `model.provider` is `zed.dev` count; a thread driven by
/// an external ACP agent is skipped so the provider behind it is not counted
/// twice. The token counts are real reported counters, and a thread is
/// cumulative over its life — one aggregate record per thread keyed
/// `zed:{id}`. `request_token_usage` is summed entry by entry (the entries
/// with work in them); `cumulative_token_usage` is used only when the request
/// entries are empty. **No reasoning field exists**, so none is derived.
enum ZedReader {
    static func inputs(home: URL, environment: [String: String]) -> [URL] {
        var roots: [URL] = [
            DatabaseReaderSupport.xdgDataHome(home: home, environment: environment)
                .appending(path: "zed/threads/threads.db"),
            DatabaseReaderSupport.applicationSupport(home: home)
                .appending(path: "Zed/threads/threads.db"),
        ]
        if let local = DatabaseReaderSupport.localAppData(environment: environment) {
            roots.append(local.appending(path: "Zed/threads/threads.db"))
        }
        return roots
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        AgentLogIO.files(in: roots, names: ["threads.db"]).flatMap(read)
    }

    /// The bound on either side of a compressed decode, and on a plain JSON
    /// blob. Internal rather than private because it is a default argument.
    static let maximumPayload = 32 * 1024 * 1024

    // MARK: - One database

    private static func read(_ file: URL) -> [AgentUsageRecord] {
        AgentSQLite.read(at: file) { database -> [AgentUsageRecord] in
            guard !DatabaseReaderSupport.columns(database, of: "threads").isEmpty else { return [] }

            var records: [AgentUsageRecord] = []
            let sql = select(database)
            AgentSQLite.each(database, sql: sql) { statement in
                guard
                    let id = AgentSQLite.text(statement, column: 0),
                    let blob = AgentSQLite.data(statement, column: 3),
                    case let .json(value) = Self.payload(
                        dataType: AgentSQLite.text(statement, column: 2) ?? "", blob: blob
                    ),
                    let thread = value as? [String: Any]
                else { return }

                // An imported thread is another product's, already counted
                // where it came from.
                if thread["imported"] as? Bool == true { return }

                guard
                    let model = thread["model"] as? [String: Any],
                    model["provider"] as? String == "zed.dev",
                    let name = AgentLogIO.text(model["model"])
                else { return }

                let request = usage(of: thread["request_token_usage"])
                let cumulative = singleUsage(thread["cumulative_token_usage"])
                let tally = request.total > 0 ? request : cumulative
                guard tally.total > 0 else { return }

                guard
                    let timestamp = Self.timestamp(statement: statement, thread: thread)
                else { return }

                records.append(
                    DatabaseReaderSupport.record(
                        at: timestamp,
                        model: name,
                        tally: tally,
                        sessionID: id,
                        project: project(
                            paths: AgentSQLite.text(statement, column: 5),
                            order: AgentSQLite.text(statement, column: 6)
                        ),
                        deduplicationID: "zed:\(id)",
                        isAggregate: true
                    )
                )
            }
            return records
        } ?? []
    }

    /// `created_at` first, else `updated_at`, else the payload's own
    /// `updated_at`. An ISO 8601 string or a numeric epoch.
    private static func timestamp(statement: OpaquePointer, thread: [String: Any]) -> Date? {
        if let text = AgentSQLite.text(statement, column: 4), let date = DatabaseReaderSupport.flexible(text) {
            return date
        }
        if let text = AgentSQLite.text(statement, column: 1), let date = DatabaseReaderSupport.flexible(text) {
            return date
        }
        return DatabaseReaderSupport.flexible(thread["updated_at"])
    }

    /// A `request_token_usage` (an object of usages, or an array of them)
    /// summed over the entries that carry work. A `cumulative_token_usage` is
    /// a single usage object.
    private static func usage(of value: Any?) -> TokenTally {
        if let array = value as? [[String: Any]] {
            return array.reduce(TokenTally()) { $0 + entry($1) }
        }
        if let object = value as? [String: Any] {
            return object.values.reduce(TokenTally()) { total, element in
                guard let part = element as? [String: Any] else { return total }
                return total + entry(part)
            }
        }
        return TokenTally()
    }

    /// A `cumulative_token_usage` — one usage object, not a map of them.
    private static func singleUsage(_ value: Any?) -> TokenTally {
        guard let object = value as? [String: Any] else { return TokenTally() }
        return entry(object)
    }

    /// One `TokenUsage`. Values may be numbers or numeric strings, and a
    /// negative clamps to zero. `input_tokens` is fresh input; the cache
    /// read/write counters are separate, exactly as Claude Code writes them.
    /// A zero-total entry contributes nothing, so it is not counted as work.
    private static func entry(_ object: [String: Any]) -> TokenTally {
        let tally = TokenTally(
            input: DatabaseReaderSupport.clampedCount(object["input_tokens"]),
            cacheWrite: DatabaseReaderSupport.clampedCount(object["cache_creation_input_tokens"]),
            cacheRead: DatabaseReaderSupport.clampedCount(object["cache_read_input_tokens"]),
            output: DatabaseReaderSupport.clampedCount(object["output_tokens"])
        )
        return tally.total > 0 ? tally : TokenTally()
    }

    /// The workspace's directory: `folder_paths` is newline-separated and
    /// `folder_paths_order` names the original index of the first one. The
    /// full path is retained for project identity.
    private static func project(paths: String?, order: String?) -> String? {
        guard let paths else { return nil }
        let list = paths
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !list.isEmpty else { return nil }

        var chosen = list[0]
        if let order,
           let first = order.split(separator: ",").first,
           let index = Int(first.trimmingCharacters(in: .whitespaces)),
           list.indices.contains(index) {
            chosen = list[index]
        }
        return chosen
    }

    // MARK: - Payloads

    /// What one thread row's blob turned out to be.
    ///
    /// Shared by `records` (which keeps the `.json` case) and `notes` (which
    /// reports the `.unreadableZstd` one), so the two cannot disagree about
    /// which rows were readable. Internal rather than private so a test can
    /// drive the decode rules directly.
    enum ThreadPayload {
        case json(Any)
        /// A row this reader does not handle — another data type, or a plain
        /// JSON row that is malformed or over the size ceiling. Nothing is
        /// reported for it.
        case ignored
        /// Raw bytes recognized as zstd that could not be read. The string is
        /// the diagnostic a note carries; the UI maps presence, not text.
        case unreadableZstd(String)
    }

    /// The thread's JSON, or why a compressed row could not be read.
    ///
    /// **One pure result, no stored state.** The bounds are parameters so a
    /// test can exercise the limit path without a large buffer; the readers
    /// call it at the real ceiling.
    static func payload(
        dataType: String,
        blob: Data,
        rawLimit: Int = maximumPayload,
        decodedLimit: Int = maximumPayload
    ) -> ThreadPayload {
        // Compressed when the column says so or the raw bytes carry the magic:
        // a mislabelled frame is still read.
        if dataType == "zstd" || DSHZstdDecoder.isZstd(blob) {
            do {
                let decoded = try DSHZstdDecoder.decode(
                    blob, rawLimit: rawLimit, decodedLimit: decodedLimit
                )
                guard let value = try? JSONSerialization.jsonObject(with: decoded) else {
                    return .unreadableZstd("zstd frame decoded but is not a thread")
                }
                return .json(value)
            } catch let failure as DSHZstdDecoder.Failure {
                return .unreadableZstd(failure.description)
            } catch {
                return .unreadableZstd("zstd frame could not be read")
            }
        }

        guard dataType == "json", blob.count <= maximumPayload,
              let value = try? JSONSerialization.jsonObject(with: blob) else {
            return .ignored
        }
        return .json(value)
    }

    /// The zstd magic as a SQL blob literal, kept in step with the decoder.
    private static let magicLiteral = "X'"
        + DSHZstdDecoder.magic.map { String(format: "%02X", $0) }.joined() + "'"

    /// A compressed thread that could not be read, or nothing.
    ///
    /// **Only rows that could be compressed are examined** — `data_type` of
    /// `zstd`, or raw bytes beginning with the zstd magic — so a store of
    /// plain JSON threads reports nothing and an uninstalled source is never
    /// named. Each such row goes through the same pure decode as `records`, so
    /// a missing library, a corrupt frame and an over-limit frame are all
    /// caught rather than only the first.
    static func notes(roots: [URL]) -> [String] {
        var diagnostics: Set<String> = []
        for file in AgentLogIO.files(in: roots, names: ["threads.db"]) {
            let columns = Self.present(file)
            guard !columns.isEmpty else { continue }

            let hasDataType = columns.contains("data_type")
            let selection = hasDataType ? "data_type, data" : "NULL, data"
            let predicate = hasDataType
                ? "data_type = 'zstd' OR substr(data, 1, 4) = \(magicLiteral)"
                : "substr(data, 1, 4) = \(magicLiteral)"

            _ = AgentSQLite.read(at: file) { database in
                AgentSQLite.each(
                    database, sql: "SELECT \(selection) FROM threads WHERE \(predicate)"
                ) { statement in
                    guard let blob = AgentSQLite.data(statement, column: 1) else { return }
                    let dataType = AgentSQLite.text(statement, column: 0) ?? ""
                    if case let .unreadableZstd(reason) = Self.payload(
                        dataType: dataType, blob: blob
                    ) {
                        diagnostics.insert(reason)
                    }
                }
            }
        }
        guard let diagnostic = diagnostics.sorted().first else { return [] }
        return [diagnostic]
    }

    private static func present(_ file: URL) -> Set<String> {
        var columns: Set<String> = []
        _ = AgentSQLite.read(at: file) { database in
            columns = DatabaseReaderSupport.columns(database, of: "threads")
        }
        return columns
    }

    /// `created_at` is optional on older schemas and selected as NULL there.
    private static func select(_ database: OpaquePointer) -> String {
        let present = DatabaseReaderSupport.columns(database, of: "threads")
        let columns = [
            "id", "updated_at", "data_type", "data", "created_at",
            "folder_paths", "folder_paths_order",
        ]
        let list = columns.map { present.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        return "SELECT \(list) FROM threads"
    }
}
