import Foundation

/// VS Code's Copilot chat-session logs.
///
/// `<workspaceStorage>/<hash>/chatSessions/<uuid>.jsonl`, with the workspace
/// named by the sibling `<hash>/workspace.json`. The file is not a list of
/// requests but an **append/patch log**: an early line carries the request
/// array, later lines append to it, and still later lines fill in a streamed
/// response at a nested path. The requests are reconstructed in order before
/// anything is read from them.
///
/// **Only Copilot's own requests count.** A request is Copilot-originated when
/// it resolved a model or its `modelId` is a `copilot/` id; anything else the
/// editor wrote is skipped. Prompt tokens are fresh input and there is no cache
/// figure beside them, so cache read and write are zero. The thinking tokens a
/// tool-call round reports are output work and are folded into output once.
///
/// **A request with no timestamp is skipped, not dated at the epoch.** The
/// format carries no session- or report-level date to fall back to, so there is
/// no real instant to attach an untimed request to. Inventing the epoch would
/// place real work at 1970 and — because the key is the instant — fold two
/// different untimed requests into one. Neither the clock nor the file's
/// modification time is used, and no record is emitted.
///
/// **Two requests are two requests, even at the same instant.** The format's
/// own key is `session:timestamp`; when two distinct requests in one session
/// share it, the later copy takes a `#n` suffix so real work is not folded
/// away. The key is kept exactly as written whenever it is already unique.
enum CopilotVSCodeReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["jsonl"])
            .filter { $0.deletingLastPathComponent().lastPathComponent == "chatSessions" }

        var records: [AgentUsageRecord] = []
        for file in files {
            records.append(contentsOf: self.records(from: file))
        }
        return records
    }

    // MARK: - One session file

    private static func records(from file: URL) -> [AgentUsageRecord] {
        let session = file.deletingPathExtension().lastPathComponent
        let workspace = Self.workspace(for: file)
        let requests = reconstruct(AgentLogIO.jsonLines(at: file))

        var records: [AgentUsageRecord] = []
        var used: Set<String> = []
        for request in requests {
            guard var built = record(request, session: session, workspace: workspace) else {
                continue
            }
            built.deduplicationID = uniqueID(built.deduplicationID, used: &used)
            records.append(built)
        }
        return records
    }

    /// Keeps the format's own key when it is unique and separates a genuine
    /// collision with a `#n` suffix, so two distinct requests that share a
    /// session and a millisecond are both counted.
    private static func uniqueID(_ base: String?, used: inout Set<String>) -> String? {
        guard let base else { return nil }
        guard used.contains(base) else {
            used.insert(base)
            return base
        }
        var suffix = 2
        while used.contains("\(base)#\(suffix)") { suffix += 1 }
        let id = "\(base)#\(suffix)"
        used.insert(id)
        return id
    }

    private static func record(
        _ request: [String: Any],
        session: String,
        workspace: String?
    ) -> AgentUsageRecord? {
        let metadata = (request["result"] as? [String: Any])?["metadata"] as? [String: Any]
        let resolved = AgentLogIO.text(metadata?["resolvedModel"])
        let modelID = AgentLogIO.text(request["modelId"])

        // Not a Copilot request: an editor-served model with neither a resolved
        // model nor the product's own id prefix.
        guard resolved != nil || (modelID?.hasPrefix("copilot/") ?? false) else { return nil }
        let model = resolved ?? stripped(modelID) ?? "auto"

        let prompt = AgentLogIO.count(request["promptTokens"])
            ?? AgentLogIO.count(metadata?["promptTokens"])
            ?? 0
        let completion = AgentLogIO.count(request["completionTokens"])
            ?? AgentLogIO.count(metadata?["outputTokens"])
            ?? 0
        let thinking = thinkingTokens(metadata)

        // Missing time is not a date. The format names no session or report
        // date to borrow, so an untimed request is skipped rather than placed
        // at the epoch or on the clock.
        guard
            let timestamp = AgentLogIO.timestamp(request["timestamp"], milliseconds: true)
                ?? AgentLogIO.timestamp(metadata?["timestamp"], milliseconds: true)
        else { return nil }

        let tally = TokenTally(input: prompt, output: completion + thinking)
        guard tally.total > 0 else { return nil }

        return StructuredLogSupport.record(
            timestamp: timestamp,
            model: model,
            tally: tally,
            sessionID: session,
            sessionName: session,
            project: workspace,
            deduplicationID: "copilot-vscode:\(session):\(CopilotLogReader.milliseconds(timestamp))"
        )
    }

    private static func stripped(_ modelID: String?) -> String? {
        guard let modelID, modelID.hasPrefix("copilot/") else { return nil }
        let tail = String(modelID.dropFirst("copilot/".count))
        return tail.isEmpty ? nil : tail
    }

    private static func thinkingTokens(_ metadata: [String: Any]?) -> Int {
        guard let rounds = metadata?["toolCallRounds"] as? [Any] else { return 0 }
        return rounds.reduce(0) { total, round in
            guard
                let round = round as? [String: Any],
                let thinking = round["thinking"] as? [String: Any]
            else { return total }
            return total + (AgentLogIO.count(thinking["tokens"]) ?? 0)
        }
    }

    private static func workspace(for file: URL) -> String? {
        let hashDirectory = file.deletingLastPathComponent().deletingLastPathComponent()
        let object = AgentLogIO.object(AgentLogIO.json(at: hashDirectory.appending(path: "workspace.json")))
        let uri = AgentLogIO.text(object?["folder"]) ?? AgentLogIO.text(object?["workspace"])
        guard let uri else { return nil }
        if let url = URL(string: uri), url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" {
            return url.path
        }
        return uri
    }

    // MARK: - Reconstructing the append/patch log

    /// Replays the file's lines into the request array they describe.
    private static func reconstruct(_ rows: some Sequence<[String: Any]>) -> [[String: Any]] {
        var requests: [Any] = []

        for row in rows {
            guard let kind = AgentLogIO.count(row["kind"]) else { continue }

            switch kind {
            case 0:
                guard
                    let value = row["v"] as? [String: Any],
                    let appended = value["requests"] as? [Any]
                else { continue }
                requests.append(contentsOf: appended)

            case 1:
                // A patch addresses one path; only one into `requests` is a
                // usage-bearing write. An out-of-range index is dropped.
                guard let path = row["k"] as? [Any], path.count >= 2,
                      let head = path[0] as? String, head == "requests",
                      let index = AgentLogIO.count(path[1]), index < requests.count
                else { continue }

                if path.count == 2 {
                    requests[index] = row["v"] ?? NSNull()
                } else {
                    var entry = requests[index]
                    mutate(&entry, path: Array(path.dropFirst(2)), value: row["v"] ?? NSNull())
                    requests[index] = entry
                }

            case 2:
                guard
                    let path = row["k"] as? [Any], path.count == 1,
                    let head = path[0] as? String, head == "requests",
                    let appended = row["v"] as? [Any]
                else { continue }
                requests.append(contentsOf: appended)

            default:
                break
            }
        }

        return requests.compactMap { $0 as? [String: Any] }
    }

    /// Writes `value` at a nested path, creating the containers the path names.
    /// A scalar, a missing key or an out-of-range index is not a path into
    /// anything, so the write is dropped.
    private static func mutate(_ container: inout Any, path: [Any], value: Any) {
        guard let head = path.first else {
            container = value
            return
        }
        let rest = Array(path.dropFirst())

        if var array = container as? [Any] {
            guard let index = AgentLogIO.count(head), index < array.count else { return }
            if rest.isEmpty {
                array[index] = value
            } else {
                mutate(&array[index], path: rest, value: value)
            }
            container = array
        } else if var dictionary = container as? [String: Any] {
            guard let key = head as? String else { return }
            if rest.isEmpty {
                dictionary[key] = value
            } else {
                let child: Any = dictionary[key] ?? (AgentLogIO.count(rest[0]) != nil ? [Any]() : [String: Any]())
                var writable = child
                mutate(&writable, path: rest, value: value)
                dictionary[key] = writable
            }
            container = dictionary
        }
    }
}
