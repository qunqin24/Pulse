import Foundation

/// Kiro's CLI session tree, `~/.kiro/sessions/cli/`, where each `*.json`
/// header is a session and the same stem's `.jsonl` is its conversation.
///
/// **Only real counters are read.** The header's per-turn
/// `input_token_count` / `output_token_count` are the one measured source in
/// Kiro's formats. Every other branch the compatibility target uses —
/// `context_window_tokens × context_usage_percentage / 100`, a character
/// count divided by four, the whole IDE `session.json` tree and the
/// `kiro-cli` SQLite — is an **estimate**, not a reported counter, and is
/// deliberately not read here. A turn whose explicit counters are both zero
/// therefore produces **no record**: a zero is not a measurement, and
/// estimating one from text would be inventing it.
///
/// The IDE, globalStorage and SQLite stores are consequently not in `inputs`:
/// nothing is read out of them, so watching them would invalidate the cache
/// for no reading. No cache or reasoning counter exists anywhere in Kiro.
enum KiroReader {
    /// The CLI tree only. It holds both the header and the conversation
    /// sidecar, so one root covers every file actually read.
    static func inputs(home: URL, environment: [String: String]) -> [URL] {
        [home.appending(path: ".kiro/sessions/cli", directoryHint: .isDirectory)]
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        AgentLogIO.files(in: roots, extensions: ["json"]).flatMap(read)
    }

    // MARK: - One session

    private static func read(_ headerFile: URL) -> [AgentUsageRecord] {
        guard
            let json = AgentLogIO.json(at: headerFile),
            let header = AgentLogIO.object(json)
        else { return [] }

        let session = AgentLogIO.text(header["session_id"]) ?? DatabaseReaderSupport.stem(headerFile)
        let model = Self.modelID(header) ?? "auto"
        let project = AgentLogIO.text(header["cwd"])
        let prompts = promptTimestamps(beside: headerFile)

        guard
            let state = header["session_state"] as? [String: Any],
            let conversation = state["conversation_metadata"] as? [String: Any],
            let turns = conversation["user_turn_metadatas"] as? [[String: Any]]
        else { return [] }

        var records: [AgentUsageRecord] = []
        for (index, turn) in turns.enumerated() {
            let input = DatabaseReaderSupport.clampedCount(turn["input_token_count"])
            let output = DatabaseReaderSupport.clampedCount(turn["output_token_count"])
            // Both zero: the only real counters Kiro has say there is nothing
            // measured here, so nothing is emitted.
            guard input > 0 || output > 0 else { continue }

            let messageIDs = turn["message_ids"] as? [String] ?? []
            let prompt = messageIDs.compactMap { prompts[$0] }.min()
            let end = DatabaseReaderSupport.epoch(DatabaseReaderSupport.number(turn["end_timestamp"]) ?? 0)
            guard let timestamp = prompt ?? end else { continue }

            records.append(
                DatabaseReaderSupport.record(
                    at: timestamp,
                    model: model,
                    tally: TokenTally(input: input, output: output),
                    sessionID: session,
                    project: project,
                    deduplicationID: "\(session):\(index)"
                )
            )
        }
        return records
    }

    /// Which model the header names, if any. The routing fallback `"auto"` is
    /// applied by the caller.
    private static func modelID(_ header: [String: Any]) -> String? {
        guard
            let state = header["session_state"] as? [String: Any],
            let rts = state["rts_model_state"] as? [String: Any],
            let info = rts["model_info"] as? [String: Any]
        else { return nil }
        return AgentLogIO.text(info["model_id"])
    }

    /// The conversation sidecar's prompt timestamps by message id. A prompt's
    /// own `.jsonl` time is the accurate one; `end_timestamp` is the fallback
    /// for a turn whose prompt line is missing.
    private static func promptTimestamps(beside headerFile: URL) -> [String: Date] {
        let sidecar = headerFile.deletingPathExtension().appendingPathExtension("jsonl")
        var times: [String: Date] = [:]
        for line in AgentLogIO.jsonLines(at: sidecar) {
            guard
                line["kind"] as? String == "Prompt",
                let data = line["data"] as? [String: Any],
                let message = AgentLogIO.text(data["message_id"]),
                let meta = data["meta"] as? [String: Any],
                let seconds = DatabaseReaderSupport.number(meta["timestamp"]),
                let timestamp = DatabaseReaderSupport.epoch(seconds)
            else { continue }
            times[message] = timestamp
        }
        return times
    }
}
