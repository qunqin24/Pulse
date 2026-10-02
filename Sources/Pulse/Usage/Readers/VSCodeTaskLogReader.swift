// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Roo Code, Kilo Code and Cline's VS Code task logs.
///
/// Each task is a directory named for the session, holding a `ui_messages.json`
/// array and, usually, an `api_conversation_history.json` beside it. Only the
/// `api_req_started` entries in the message array count, and each is one real
/// request: the products write the four token kinds for it under a `text`
/// field that is itself JSON.
///
/// **The macOS root is added explicitly.** The historical discovery used
/// `~/.config/Code/...` even on macOS, where that usually does not exist; a
/// real install keeps its extension storage under
/// `~/Library/Application Support/Code/User/globalStorage`. Both spellings are
/// offered, along with the Insiders and VSCodium variants and the remote
/// `.vscode-server` tree, so more than one editor layout is found without
/// walking the whole home directory.
enum VSCodeTaskLogReader {
    static let supportedClients: Set<String> = ["roocode", "kilocode", "cline"]

    /// The VS Code extension id whose `globalStorage` holds each product.
    private static let extensionIDs: [String: String] = [
        "roocode": "rooveterinaryinc.roo-cline",
        "kilocode": "kilocode.kilo-code",
        "cline": "saoudrizwan.claude-dev",
    ]

    private static let desktopEditors = ["Code", "Code - Insiders", "VSCodium"]
    private static let remoteServers = [".vscode-server", ".vscode-server-insiders"]

    static func inputs(client: String, home: URL) -> [URL] {
        guard let extensionID = extensionIDs[client] else { return [] }

        var roots: [URL] = []
        for editor in desktopEditors {
            let storage = "User/globalStorage/\(extensionID)/tasks"
            roots.append(home.appending(path: "Library/Application Support/\(editor)/\(storage)"))
            roots.append(home.appending(path: ".config/\(editor)/\(storage)"))
        }
        for server in remoteServers {
            roots.append(
                home.appending(path: "\(server)/data/User/globalStorage/\(extensionID)/tasks")
            )
        }
        return roots
    }

    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(
            in: roots,
            names: ["ui_messages.json", "api_conversation_history.json"]
        )

        var tasks: [String: (messages: URL?, history: URL?)] = [:]
        for file in files {
            let directory = file.deletingLastPathComponent().path
            var task = tasks[directory] ?? (nil, nil)
            switch file.lastPathComponent {
            case "ui_messages.json": task.messages = file
            case "api_conversation_history.json": task.history = file
            default: break
            }
            tasks[directory] = task
        }

        var records: [AgentUsageRecord] = []
        for (directory, task) in tasks.sorted(by: { $0.key < $1.key }) {
            guard let messages = task.messages else { continue }
            let session = URL(fileURLWithPath: directory).lastPathComponent
            let details = task.history.flatMap { EnvironmentDetails(textFile: $0) }
            records += parse(messages: messages, session: session, details: details)
        }
        return records
    }

    // MARK: - One task

    private static func parse(
        messages: URL,
        session: String,
        details: EnvironmentDetails?
    ) -> [AgentUsageRecord] {
        guard let entries = AgentLogIO.json(at: messages) as? [[String: Any]] else { return [] }

        var records: [AgentUsageRecord] = []
        for entry in entries {
            guard
                AgentLogIO.text(entry["type"]) == "say",
                AgentLogIO.text(entry["say"]) == "api_req_started",
                // `ts` is milliseconds as a string or a number; ISO is read
                // the same way, and an unparseable one skips the entry.
                let timestamp = AgentLogIO.timestamp(entry["ts"], milliseconds: true),
                let text = AgentLogIO.text(entry["text"]),
                let usage = EditorLog.jsonObject(from: text)
            else { continue }

            let tally = TokenTally(
                input: EditorLog.int(usage["tokensIn"]),
                cacheWrite: EditorLog.int(usage["cacheWrites"]),
                cacheRead: EditorLog.int(usage["cacheReads"]),
                output: EditorLog.int(usage["tokensOut"])
            )
            guard tally.total > 0 else { continue }

            // The entry's own model wins; the conversation history's last
            // `<model>` tag is the fallback for a run that predates it.
            let modelInfo = AgentLogIO.object(entry["modelInfo"])
            guard
                let model = EditorLog.nonBlank(
                    AgentLogIO.text(modelInfo?["modelId"]) ?? details?.model
                )
            else { continue }

            records.append(
                EditorLog.record(
                    timestamp: timestamp,
                    model: model,
                    tally: tally,
                    sessionID: session,
                    sessionName: details?.agent
                )
            )
        }
        return records
    }

    // MARK: - The conversation history's environment block

    /// The `<model>`, `<slug>` and `<name>` tags the history writes inside its
    /// `<environment_details>` blocks. These are the only fallbacks used when
    /// an entry names no model.
    struct EnvironmentDetails {
        var model: String?
        var agent: String?

        init(model: String? = nil, agent: String? = nil) {
            self.model = model
            self.agent = agent
        }

        init?(textFile: URL) {
            guard
                !Task.isCancelled,
                let data = try? Data(contentsOf: textFile, options: .mappedIfSafe),
                let text = String(data: data, encoding: .utf8)
            else { return nil }
            self = EnvironmentDetails.parse(text)
        }

        static func parse(_ text: String) -> EnvironmentDetails {
            var details = EnvironmentDetails()
            for block in blocks(in: text) {
                if let model = lastTag("model", in: block) { details.model = model }
                // The slug is the product's own handle for the agent; the
                // human name is only a fallback for a run that wrote no slug.
                if let agent = lastTag("slug", in: block) ?? lastTag("name", in: block) {
                    details.agent = agent
                }
            }
            return details
        }

        private static func blocks(in text: String) -> [String] {
            var found: [String] = []
            var searchStart = text.startIndex
            while let open = text.range(of: "<environment_details>", range: searchStart..<text.endIndex) {
                guard !Task.isCancelled else { return [] }
                guard
                    let close = text.range(
                        of: "</environment_details>", range: open.upperBound..<text.endIndex
                    )
                else { break }
                found.append(String(text[open.upperBound..<close.lowerBound]))
                searchStart = close.upperBound
            }
            return found
        }

        private static func lastTag(_ tag: String, in text: String) -> String? {
            let open = "<\(tag)>"
            let close = "</\(tag)>"
            var value: String?
            var searchStart = text.startIndex
            while let start = text.range(of: open, range: searchStart..<text.endIndex) {
                guard let end = text.range(of: close, range: start.upperBound..<text.endIndex) else { break }
                let content = String(text[start.upperBound..<end.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty { value = content }
                searchStart = end.upperBound
            }
            return value
        }
    }
}
