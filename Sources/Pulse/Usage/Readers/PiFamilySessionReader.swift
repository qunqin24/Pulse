// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The Pi transcript, shared by Pi, omp, Senpi and Kimchi.
///
/// One JSONL file per session: an optional `title` record, a `session` header
/// carrying the session id and working directory, then `message` records whose
/// `message.usage` holds four independent token buckets. A branch or fork
/// copies prior assistant records into a new file verbatim, which is why the
/// record identity is session-independent — a copy has to fold onto its
/// original.
///
/// **Reasoning is inside output.** The format documents `reasoning` as a
/// subset of `output`, so it is never a bucket of its own and never added to
/// output a second time.
///
/// This type is the parser only: it produces messages and attributions and
/// leaves every decision about identity, reconciliation and emission to the
/// family reader that owns it.
enum PiTranscript {
    struct Header {
        var id: String?
        var cwd: String?
        var parentSession: String?
        var rlmDepth: Int?
    }

    struct Message {
        var id: String?
        var responseId: String?
        var timestamp: Date?
        var provider: String?
        var model: String?
        var tally: TokenTally
        var unclassified: Int
    }

    struct Attribution {
        var id: String?
        var targetId: String?
        var childUsage: TokenTally
        var aggregateUsage: TokenTally
    }

    struct File {
        var url: URL
        var path: String
        var header: Header
        var sessionInfoName: String?
        var messages: [Message]
        var attributions: [Attribution]
        var isValid: Bool
    }

    /// Parses one file. A malformed session header is fatal to the **whole**
    /// file: without a header there is no session id or working directory, and
    /// a record built from the remainder would be attributed to nobody.
    static func parse(_ url: URL) -> File {
        let rows = AgentLogIO.jsonLines(at: url)
        var header: Header?
        var sessionInfoName: String?
        var messages: [Message] = []
        var attributions: [Attribution] = []
        var malformed = false

        for row in rows {
            let type = row["type"] as? String

            guard header != nil else {
                // A descendant may open with title metadata; anything else is
                // the session header or the file is malformed.
                if type == "title" { continue }
                guard type == "session", let id = AgentLogIO.text(row["id"]) else {
                    malformed = true
                    break
                }
                header = Header(
                    id: id,
                    cwd: AgentLogIO.text(row["cwd"]),
                    parentSession: AgentLogIO.text(row["parentSession"]),
                    rlmDepth: AgentLogIO.count(row["rlmDepth"])
                )
                continue
            }

            switch type {
            case "session_info":
                if let name = AgentLogIO.text(row["name"]) { sessionInfoName = name }
            case "message":
                if let message = parseMessage(row) { messages.append(message) }
            case "child_usage_attributed":
                if let attribution = parseAttribution(row) { attributions.append(attribution) }
            default:
                break
            }
        }

        return File(
            url: url,
            path: url.standardizedFileURL.path,
            header: header ?? Header(),
            sessionInfoName: sessionInfoName,
            messages: messages,
            attributions: attributions,
            isValid: !malformed && header != nil
        )
    }

    /// The working directories recorded by the session headers under `roots`.
    static func cwdValues(in roots: [URL]) -> [String] {
        AgentLogIO.files(in: roots, extensions: ["jsonl"])
            .compactMap { file in
                // Discovery needs the header alone, not every conversation in
                // every session (this is also called while stamping inputs).
                for row in AgentLogIO.jsonLines(at: file) {
                    if row["type"] as? String == "title" { continue }
                    guard row["type"] as? String == "session", AgentLogIO.text(row["id"]) != nil else { return nil }
                    return AgentLogIO.text(row["cwd"])
                }
                return nil
            }
    }

    // MARK: - Usage

    /// The four buckets, plus any reported total that is not explained by them.
    ///
    /// A total the four known buckets already account for yields nothing
    /// unclassified; a total standing in for a kind nobody named is carried as
    /// `unclassified` rather than poured into input, because a fabricated kind
    /// is a number nobody can check.
    static func usage(_ object: [String: Any]) -> (tally: TokenTally, unclassified: Int) {
        let input = AgentLogIO.count(object["input"])
        let output = AgentLogIO.count(object["output"])
        let cacheRead = AgentLogIO.count(object["cacheRead"])
        let cacheWrite = AgentLogIO.count(object["cacheWrite"])
        let total = AgentLogIO.count(object["totalTokens"])

        let tally = TokenTally(
            input: input ?? 0,
            cacheWrite: cacheWrite ?? 0,
            cacheRead: cacheRead ?? 0,
            output: output ?? 0
        )
        let anyKnown = input != nil || output != nil || cacheRead != nil || cacheWrite != nil
        guard let total else { return (tally, 0) }

        if !anyKnown { return (TokenTally(), total) }
        let remainder = total - tally.total
        return (tally, remainder > 0 ? remainder : 0)
    }

    private static func parseMessage(_ row: [String: Any]) -> Message? {
        guard
            let message = row["message"] as? [String: Any],
            message["role"] as? String == "assistant",
            let usageObject = message["usage"] as? [String: Any]
        else { return nil }

        let counts = usage(usageObject)
        guard counts.tally.total > 0 || counts.unclassified > 0 else { return nil }

        return Message(
            id: AgentLogIO.text(row["id"]),
            responseId: AgentLogIO.text(message["responseId"]),
            timestamp: AgentLogIO.timestamp(row["timestamp"]) ?? AgentLogIO.timestamp(message["timestamp"]),
            provider: AgentLogIO.text(message["provider"]),
            model: AgentLogIO.text(message["model"]),
            tally: counts.tally,
            unclassified: counts.unclassified
        )
    }

    private static func parseAttribution(_ row: [String: Any]) -> Attribution? {
        guard
            let child = row["childUsage"] as? [String: Any],
            let aggregate = row["aggregateUsage"] as? [String: Any]
        else { return nil }
        let childUsage = usage(child).tally
        let aggregateUsage = usage(aggregate).tally
        guard childUsage.total > 0 || aggregateUsage.total > 0 else { return nil }
        return Attribution(
            id: AgentLogIO.text(row["id"]),
            targetId: AgentLogIO.text(row["targetId"]),
            childUsage: childUsage,
            aggregateUsage: aggregateUsage
        )
    }
}

/// The Pi-shaped clients: one parser, four identities.
///
/// omp shares Pi's format; Senpi adds OmO project children and treats
/// `session_info.name` as a human title; Kimchi keeps a session-scoped cache
/// namespace instead of the cross-session one. Nothing else differs, so they
/// are configurations of one reader rather than four copies.
enum PiFamilySessionReader {
    struct Configuration {
        enum Dedup {
            /// A fork copy of a message folds onto its original by response id,
            /// or by a composite of the message's own fields.
            case crossSession
            /// Kimchi's older scheme keeps each session's namespace separate.
            case sessionScoped
        }

        var dedup: Dedup
        var discoversProjectChildren: Bool
        var sessionInfoNameIsTitle: Bool
        var providerFallback: String?
    }

    static func configuration(for client: String) -> Configuration? {
        switch client {
        case "pi":
            Configuration(dedup: .crossSession, discoversProjectChildren: false,
                          sessionInfoNameIsTitle: false, providerFallback: nil)
        case "omp":
            Configuration(dedup: .crossSession, discoversProjectChildren: false,
                          sessionInfoNameIsTitle: false, providerFallback: "omp")
        case "senpi":
            Configuration(dedup: .crossSession, discoversProjectChildren: true,
                          sessionInfoNameIsTitle: true, providerFallback: nil)
        case "kimchi":
            Configuration(dedup: .sessionScoped, discoversProjectChildren: false,
                          sessionInfoNameIsTitle: false, providerFallback: nil)
        default:
            nil
        }
    }

    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        guard let configuration = configuration(for: client) else { return [] }

        var files = AgentLogIO.files(in: roots, extensions: ["jsonl"]).map { PiTranscript.parse($0) }

        // Senpi's OmO children live outside its sessions tree, under the
        // working directory each header names.
        if configuration.discoversProjectChildren {
            let known = Set(files.map(\.path))
            let extra = AgentLogIO.files(in: SessionLogPaths.senpiChildren(in: roots), extensions: ["jsonl"])
                .filter { !known.contains($0.standardizedFileURL.path) }
            files.append(contentsOf: extra.map { PiTranscript.parse($0) })
        }

        var records: [AgentUsageRecord] = []
        var incomplete = false
        for file in files {
            let sessionID = file.isValid ? file.header.id : nil
            for message in file.messages {
                guard message.tally.total > 0 || message.unclassified > 0 else { continue }
                guard
                    let sessionID,
                    let timestamp = message.timestamp,
                    let model = message.model
                else {
                    // Real usage in a file with no usable header, time or model:
                    // a readable subset, not the whole story.
                    incomplete = true
                    continue
                }

                records.append(
                    AgentUsageRecord(
                        timestamp: timestamp,
                        model: model,
                        tally: message.tally,
                        sessionID: sessionID,
                        sessionName: nil,
                        title: configuration.sessionInfoNameIsTitle ? file.sessionInfoName : nil,
                        project: file.header.cwd,
                        deduplicationID: deduplicationID(
                            client: client, configuration: configuration,
                            sessionID: sessionID, message: message
                        ),
                        unclassifiedTokens: message.unclassified
                    )
                )
            }
        }
        return incomplete ? records.map(markedPartial) : records
    }

    private static func markedPartial(_ record: AgentUsageRecord) -> AgentUsageRecord {
        var copy = record
        copy.isPartial = true
        return copy
    }

    private static func deduplicationID(
        client: String,
        configuration: Configuration,
        sessionID: String,
        message: PiTranscript.Message
    ) -> String? {
        switch configuration.dedup {
        case .sessionScoped:
            // No message identity means no stable key; each occurrence stands
            // on its own rather than being folded by a guessed one.
            guard let id = message.id else { return nil }
            return "\(client):\(sessionID):\(id)"
        case .crossSession:
            if let responseId = message.responseId {
                return "\(client):response:\(responseId)"
            }
            guard let timestamp = message.timestamp else { return nil }
            let milliseconds = Int((timestamp.timeIntervalSince1970 * 1000).rounded())
            let provider = message.provider ?? configuration.providerFallback ?? ""
            let tally = message.tally
            return "\(client):message:\(message.id ?? ""):\(milliseconds):\(provider):"
                + "\(message.model ?? ""):\(tally.input):\(tally.output):\(tally.cacheRead):\(tally.cacheWrite)"
        }
    }
}
