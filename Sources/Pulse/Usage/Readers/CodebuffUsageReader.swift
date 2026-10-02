// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Codebuff's chat logs, under its `manicode*` product trees.
///
/// `<root>/projects/<project>/chats/<chatId>/chat-messages.json` is a top-level
/// array of messages. The chat id is the chat's ISO start with the time colons
/// written as dashes; the project and channel come from the path, so a session
/// is `<channel>/<project>/<chatId>`.
///
/// **Usage is merged, not summed.** The same provider numbers are copied into
/// several places — `metadata.usage`, `metadata.codebuff.usage`, and the last
/// assistant row's `providerOptions` in the run-state history. Each field is
/// taken from the first source that reported a **non-zero** value, so a zero in
/// a higher-priority copy cannot mask the real count below it, and a field
/// written twice is counted once.
///
/// **Credits are not tokens.** `credits` is a cost the product keeps beside the
/// counts; a dollar figure is not a token kind and is left for Pulse's own
/// price table rather than read as usage.
///
/// Freebuff chats share this directory and are read by `FreebuffUsageReader`.
/// A chat whose assistant rows carry authoritative usage belongs here whatever
/// its agent type; a `base2-free` chat with none contributes no record from
/// either reader, so the same batch is never counted twice.
enum CodebuffUsageReader {
    static let inputAliases = ["inputTokens", "input_tokens", "promptTokens", "prompt_tokens"]
    static let outputAliases = ["outputTokens", "output_tokens", "completionTokens", "completion_tokens"]
    static let cacheReadAliases = [
        "cacheReadInputTokens", "cache_read_input_tokens",
        "cachedTokensCreated", "cached_tokens_created",
    ]
    static let cacheWriteAliases = [
        "cacheCreationInputTokens", "cache_creation_input_tokens",
        "cacheCreationTokens", "cache_creation_tokens",
    ]

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []

        for file in AgentLogIO.files(in: roots, names: ["chat-messages.json"]) {
            guard let messages = AgentLogIO.json(at: file) as? [[String: Any]] else { continue }

            let location = location(of: file)
            let sessionID = "\(location.channel)/\(location.project)/\(location.chatId)"

            for (index, message) in messages.enumerated() {
                guard isAssistant(message) else { continue }
                let sources = usageSources(message)
                guard !sources.isEmpty else { continue }

                let tally = TokenTally(
                    input: StructuredLogSupport.merged(sources, inputAliases),
                    cacheWrite: StructuredLogSupport.merged(sources, cacheWriteAliases),
                    cacheRead: cacheRead(sources),
                    output: StructuredLogSupport.merged(sources, outputAliases)
                )
                guard tally.total > 0 else { continue }

                guard let model = model(message, sources: sources) else { continue }
                guard let timestamp = timestamp(message, chatId: location.chatId) else { continue }

                let identity = AgentLogIO.text(message["id"])
                    ?? "\(sessionID):\(index):\(timestamp.timeIntervalSince1970):\(model):"
                        + "\(tally.input):\(tally.cacheWrite):\(tally.cacheRead):\(tally.output)"

                guard
                    let record = StructuredLogSupport.record(
                        timestamp: timestamp,
                        model: model,
                        tally: tally,
                        sessionID: sessionID,
                        sessionName: location.chatId,
                        deduplicationID: "codebuff:\(sessionID):\(identity)"
                    )
                else { continue }
                records.append(record)
            }
        }

        return records
    }

    // MARK: - Message shape

    /// Whether a row is the assistant's own. `variant` is the newer marker and
    /// `role` the older one; either is enough.
    static func isAssistant(_ message: [String: Any]) -> Bool {
        let markers = [AgentLogIO.text(message["variant"]), AgentLogIO.text(message["role"])]
        return markers.compactMap { $0?.lowercased() }
            .contains { $0 == "ai" || $0 == "agent" || $0 == "assistant" }
    }

    /// Every usage object the message carries, highest priority first.
    static func usageSources(_ message: [String: Any]) -> [[String: Any]] {
        var sources: [[String: Any]] = []
        guard let metadata = AgentLogIO.object(message["metadata"]) else { return sources }

        if let usage = AgentLogIO.object(metadata["usage"]) { sources.append(usage) }
        if let codebuff = AgentLogIO.object(metadata["codebuff"]),
           let usage = AgentLogIO.object(codebuff["usage"]) {
            sources.append(usage)
        }

        let mainAgent = AgentLogIO.object(metadata["runState"])
            .flatMap { AgentLogIO.object($0["sessionState"]) }
            .flatMap { AgentLogIO.object($0["mainAgentState"]) }
        if let history = mainAgent?["messageHistory"] as? [[String: Any]] {
            for row in history.reversed() {
                guard let providers = AgentLogIO.object(row["providerOptions"]) else { continue }
                if let usage = AgentLogIO.object(providers["usage"]) { sources.append(usage) }
                if let codebuff = AgentLogIO.object(providers["codebuff"]),
                   let usage = AgentLogIO.object(codebuff["usage"]) {
                    sources.append(usage)
                }
            }
        }
        return sources
    }

    /// Cache-read tokens, including the two nested detail spellings.
    private static func cacheRead(_ sources: [[String: Any]]) -> Int {
        let flat = StructuredLogSupport.merged(sources, cacheReadAliases)
        if flat > 0 { return flat }

        for source in sources {
            for key in ["promptTokensDetails", "prompt_tokens_details"] {
                guard let details = AgentLogIO.object(source[key]) else { continue }
                if let value = AgentLogIO.count(details["cachedTokens"]) { return value }
                if let value = AgentLogIO.count(details["cached_tokens"]) { return value }
            }
        }
        return 0
    }

    /// `metadata.model` → the last history row's `providerOptions.codebuff.model`
    /// → the usage object's own `model`.
    static func model(_ message: [String: Any], sources: [[String: Any]]) -> String? {
        if let metadata = AgentLogIO.object(message["metadata"]) {
            if let named = AgentLogIO.text(metadata["model"]) { return named }
            let mainAgent = AgentLogIO.object(metadata["runState"])
                .flatMap { AgentLogIO.object($0["sessionState"]) }
                .flatMap { AgentLogIO.object($0["mainAgentState"]) }
            if let history = mainAgent?["messageHistory"] as? [[String: Any]] {
                for row in history.reversed() {
                    if let name = AgentLogIO.text(
                        AgentLogIO.object(row["providerOptions"])
                            .flatMap { AgentLogIO.object($0["codebuff"]) }?["model"]
                    ) {
                        return name
                    }
                }
            }
        }
        for source in sources {
            if let name = AgentLogIO.text(source["model"]) { return name }
        }
        return nil
    }

    /// Message shape: the message's own timestamp, else its `createdAt`, else
    /// the metadata's, else the chat id restored to ISO 8601.
    static func timestamp(_ message: [String: Any], chatId: String) -> Date? {
        // Zero is "unset", not 1970, so it falls through to the next real field.
        if let value = StructuredLogSupport.eventTime(message["timestamp"]) { return value }
        if let value = StructuredLogSupport.eventTime(message["createdAt"]) { return value }
        if let metadata = AgentLogIO.object(message["metadata"]),
           let value = StructuredLogSupport.eventTime(metadata["timestamp"]) {
            return value
        }
        return StructuredLogSupport.isoFromChatID(chatId)
    }

    // MARK: - Path

    /// Channel, project and chat id from `…/projects/<project>/chats/<chatId>/`.
    static func location(of file: URL) -> (channel: String, project: String, chatId: String) {
        let parts = file.standardizedFileURL.pathComponents
        let chatId = file.deletingLastPathComponent().lastPathComponent

        if let index = parts.lastIndex(of: "projects"), index > 0, index + 1 < parts.count {
            let channel = parts[index - 1]
            let project = parts[index + 1]
            return (channel, project, chatId)
        }
        // A tree that was renamed or moved: the directory above `chats` is the
        // project, and the config directory above it names the channel.
        let chats = file.deletingLastPathComponent().deletingLastPathComponent()
        return (chats.deletingLastPathComponent().lastPathComponent,
                chats.lastPathComponent,
                chatId)
    }
}
