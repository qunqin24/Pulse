// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import SQLite3

/// OpenClaw's two stores and its legacy names.
///
/// The current store is a SQLite database, `<agentId>/agent/openclaw-agent.sqlite`,
/// whose `transcript_events` rows hold the event JSON; the older store is a
/// directory of `*.jsonl` files (with `deleted`/`reset` archives) indexed by
/// `sessions.json`. Both use the same event shape, and `openclaw doctor --fix`
/// imports the logs into the database while leaving the originals behind — so
/// the same call can be present in both. The record identity is therefore
/// **cross-store**: event id, timestamp and the input/output counts, which the
/// SQLite row, the retained JSONL line and a `/fork` copy all share. That is
/// what keeps one call from being counted twice.
///
/// A `reasoningTokens` value is documented as a subset of `output`, so it is
/// not a bucket of its own and never added a second time. Rows that describe
/// transcript plumbing rather than model output (`openclaw-transcript`,
/// `delivery-mirror`, `gateway-injected`) are skipped: they are all-zero
/// bookkeeping, not a real zero-usage call.
///
/// **Not read here:** the Codex app-server rollouts mirrored under an agent
/// (`agent/codex-home`, `agent/cli-auth`) are a different format, and the
/// format facts for them are owned by another group; parsing them as OpenClaw
/// events would mis-read them. Zstandard archives (`.zst`) are skipped too —
/// there is no decoder here, and a byte ceiling on a format we cannot decode
/// would be a claim we cannot support.
enum OpenClawSessionReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let sqlite = sqliteRecords(roots: roots)
        let jsonl = jsonlRecords(roots: roots)
        let all = sqlite.records + jsonl.records
        return (sqlite.incomplete || jsonl.incomplete) ? all.map(markedPartial) : all
    }

    // MARK: - SQLite store

    static func sqliteRecords(roots: [URL]) -> (records: [AgentUsageRecord], incomplete: Bool) {
        let databases = AgentLogIO.files(in: roots, extensions: ["sqlite"])
            .filter { $0.lastPathComponent == "openclaw-agent.sqlite" }

        var records: [AgentUsageRecord] = []
        var incomplete = false
        for database in databases {
            let found: (records: [AgentUsageRecord], incomplete: Bool)? = AgentSQLite.read(at: database) { handle in
                let metadata = sessionMetadata(handle)
                var carried: [String: (model: String?, provider: String?)] = [:]
                var output: [AgentUsageRecord] = []
                var incomplete = false

                AgentSQLite.each(
                    handle,
                    sql: "SELECT session_id, seq, event_json FROM transcript_events "
                        + "WHERE event_json LIKE '%\"usage\"%' OR event_json LIKE '%\"model_change\"%' "
                        + "OR event_json LIKE '%model-snapshot%' ORDER BY session_id, seq"
                ) { statement in
                    guard
                        let session = AgentSQLite.text(statement, column: 0),
                        let json = AgentSQLite.text(statement, column: 2),
                        let data = json.data(using: .utf8),
                        let object = try? JSONSerialization.jsonObject(with: data),
                        let row = object as? [String: Any]
                    else { return }

                    let seq = AgentLogIO.count(AgentSQLite.text(statement, column: 1)) ?? 0
                    if let update = modelBookkeeping(row) { carried[session] = update }
                    guard let event = messageEvent(row) else { return }

                    let meta = metadata[session]
                    guard
                        let model = AgentLogIO.text(
                            event.model ?? carried[session]?.model ?? meta?.model
                        ),
                        let timestamp = event.timestamp
                    else {
                        // Real usage with no model or no locatable time.
                        incomplete = true
                        return
                    }

                    output.append(
                        record(
                            session: session,
                            eventID: event.eventID ?? "seq-\(seq)",
                            timestamp: timestamp,
                            model: model,
                            event: event
                        )
                    )
                }
                return (output, incomplete)
            }
            if let found {
                records.append(contentsOf: found.records)
                incomplete = incomplete || found.incomplete
            }
        }
        return (records, incomplete)
    }

    /// `session_windows` is the current join; the older `sessions` table is
    /// used when the former does not exist, and null metadata is accepted when
    /// neither does.
    private struct SessionMeta {
        var model: String?
        var provider: String?
    }

    private static func sessionMetadata(_ handle: OpaquePointer) -> [String: SessionMeta] {
        var map: [String: SessionMeta] = [:]
        AgentSQLite.each(handle, sql: "SELECT session_id, model_provider, model FROM session_windows") { statement in
            guard let id = AgentSQLite.text(statement, column: 0) else { return }
            map[id] = SessionMeta(
                model: AgentSQLite.text(statement, column: 2),
                provider: AgentSQLite.text(statement, column: 1)
            )
        }
        if map.isEmpty {
            AgentSQLite.each(handle, sql: "SELECT session_id, model_provider, model FROM sessions") { statement in
                guard let id = AgentSQLite.text(statement, column: 0) else { return }
                map[id] = SessionMeta(
                    model: AgentSQLite.text(statement, column: 2),
                    provider: AgentSQLite.text(statement, column: 1)
                )
            }
        }
        return map
    }

    // MARK: - JSONL store

    static func jsonlRecords(roots: [URL]) -> (records: [AgentUsageRecord], incomplete: Bool) {
        let registry = sessionRegistry(in: roots)
        var records: [AgentUsageRecord] = []
        var incomplete = false

        for file in AgentLogIO.files(in: roots).filter(isOpenClawJSONL) {
            let session = registry[file.lastPathComponent] ?? urlSessionID(file)
            var carried: (model: String?, provider: String?) = (nil, nil)

            for (index, row) in AgentLogIO.jsonLines(at: file).enumerated() {
                if let update = modelBookkeeping(row) { carried = update }
                guard let event = messageEvent(row) else { continue }
                guard
                    let model = AgentLogIO.text(event.model ?? carried.model),
                    let timestamp = event.timestamp
                else {
                    incomplete = true
                    continue
                }

                records.append(
                    record(
                        session: session,
                        eventID: event.eventID ?? "line-\(index)",
                        timestamp: timestamp,
                        model: model,
                        event: event
                    )
                )
            }
        }
        return (records, incomplete)
    }

    private static func markedPartial(_ record: AgentUsageRecord) -> AgentUsageRecord {
        var copy = record
        copy.isPartial = true
        return copy
    }

    /// The legacy `sessions.json` registry: `sessionFile` name to `sessionId`.
    static func sessionRegistry(in roots: [URL]) -> [String: String] {
        var map: [String: String] = [:]
        for file in AgentLogIO.files(in: roots, names: ["sessions.json"]) {
            guard let root = AgentLogIO.object(AgentLogIO.json(at: file)) else { continue }
            for value in root.values {
                guard
                    let entry = value as? [String: Any],
                    let sessionID = AgentLogIO.text(entry["sessionId"]),
                    let sessionFile = AgentLogIO.text(entry["sessionFile"])
                else { continue }
                map[URL(fileURLWithPath: sessionFile).lastPathComponent] = sessionID
            }
        }
        return map
    }

    /// A legacy transcript. A `deleted`/`reset` archive still names `.jsonl`,
    /// and the imported originals under `session-sqlite-import-archive` are
    /// read too — the cross-store identity folds them onto the database row.
    static func isOpenClawJSONL(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.contains(".jsonl") else { return false }
        guard !name.hasSuffix(".zst") else { return false }
        let path = url.path
        guard path.contains("/sessions/") || path.contains("/session-sqlite-import-archive/") else {
            return false
        }
        guard !path.contains("/codex-home/"), !path.contains("/cli-auth/") else { return false }
        return true
    }

    private static func urlSessionID(_ url: URL) -> String {
        let name = url.lastPathComponent
        if let range = name.range(of: ".jsonl") { return String(name[..<range.lowerBound]) }
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Events

    struct MessageEvent {
        var eventID: String?
        var model: String?
        var provider: String?
        var timestamp: Date?
        var tally: TokenTally
        var unclassified: Int
    }

    static func messageEvent(_ row: [String: Any]) -> MessageEvent? {
        guard row["type"] as? String == "message" else { return nil }
        guard let message = row["message"] as? [String: Any] else { return nil }
        guard message["role"] as? String == "assistant" else { return nil }
        guard !isArtifact(row: row, message: message) else { return nil }
        guard let usageObject = message["usage"] as? [String: Any] else { return nil }

        let counts = usage(usageObject)
        guard counts.tally.total > 0 || counts.unclassified > 0 else { return nil }

        return MessageEvent(
            eventID: AgentLogIO.text(row["id"]),
            model: AgentLogIO.text(message["model"]),
            provider: AgentLogIO.text(message["provider"]),
            timestamp: AgentLogIO.timestamp(message["timestamp"], milliseconds: true)
                ?? AgentLogIO.timestamp(row["timestamp"], milliseconds: true),
            tally: counts.tally,
            unclassified: counts.unclassified
        )
    }

    /// Rows that describe the mirror rather than a call the model made.
    static func isArtifact(row: [String: Any], message: [String: Any]) -> Bool {
        if AgentLogIO.text(row["api"]) == "openclaw-transcript" { return true }
        if AgentLogIO.text(message["api"]) == "openclaw-transcript" { return true }
        let provider = AgentLogIO.text(message["provider"]) ?? AgentLogIO.text(row["provider"])
        let model = AgentLogIO.text(message["model"]) ?? AgentLogIO.text(row["model"])
        return provider == "openclaw" && (model == "delivery-mirror" || model == "gateway-injected")
    }

    /// The model bookkeeping an event carries, if any.
    static func modelBookkeeping(_ row: [String: Any]) -> (model: String?, provider: String?)? {
        switch row["type"] as? String {
        case "model_change":
            return (AgentLogIO.text(row["modelId"]), AgentLogIO.text(row["provider"]))
        case "custom":
            guard
                row["customType"] as? String == "model-snapshot",
                let data = row["data"] as? [String: Any]
            else { return nil }
            return (AgentLogIO.text(data["modelId"]), AgentLogIO.text(data["provider"]))
        default:
            return nil
        }
    }

    /// The camelCase usage object. A bare `totalTokens` with no named kind is
    /// carried as unclassified, never poured into input.
    static func usage(_ object: [String: Any]) -> (tally: TokenTally, unclassified: Int) {
        let input = AgentLogIO.count(object["input"])
        let output = AgentLogIO.count(object["output"])
        let cacheRead = AgentLogIO.count(object["cacheRead"])
        let cacheWrite = AgentLogIO.count(object["cacheWrite"])
        let reasoning = AgentLogIO.count(object["reasoningTokens"]) ?? 0
        let total = AgentLogIO.count(object["totalTokens"])

        let anyKnown = input != nil || output != nil || cacheRead != nil || cacheWrite != nil
        let tally = TokenTally(
            input: input ?? 0,
            cacheWrite: cacheWrite ?? 0,
            cacheRead: cacheRead ?? 0,
            output: output ?? reasoning
        )
        guard let total else { return (tally, 0) }
        if !anyKnown { return (TokenTally(), total) }
        let remainder = total - tally.total
        return (tally, remainder > 0 ? remainder : 0)
    }

    private static func record(
        session: String?,
        eventID: String,
        timestamp: Date,
        model: String,
        event: MessageEvent
    ) -> AgentUsageRecord {
        AgentUsageRecord(
            timestamp: timestamp, model: model, tally: event.tally,
            sessionID: session,
            deduplicationID: deduplicationID(eventID: eventID, timestamp: timestamp, tally: event.tally),
            unclassifiedTokens: event.unclassified
        )
    }

    static func deduplicationID(eventID: String, timestamp: Date, tally: TokenTally) -> String {
        let milliseconds = Int((timestamp.timeIntervalSince1970 * 1000).rounded())
        return "openclaw:\(eventID):\(milliseconds):\(tally.input):\(tally.output)"
    }
}
