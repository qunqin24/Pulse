// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The catalog of agents that keep a **structured** local store — JSON, JSONL,
/// SQLite or a log — rather than a transcript of the kind `UsageLedgerReader`
/// already reads.
///
/// Every client here answers the same two questions. `inputs` says which files
/// (or directories) Pulse would actually read, so the multi-root cache can
/// watch exactly those and no wider tree. `records` decodes them into
/// increments. A client is in `supportedClients` exactly when both are real:
/// an entry that only guessed at a path is worse than no entry.
///
/// **One client, one reader, split by format.** Mux, Codebuff/Freebuff, Jcode,
/// Augment, Gajae Code, Junie, DeepSeek Harness, Fx, LM Studio and Reasonix each
/// have their own file below, because the formats share almost nothing beyond
/// the boundary type. This file is only the dispatch.
enum StructuredLogReaders {
    /// Every client string this family can be asked for.
    static let supportedClients: Set<String> = [
        "mux",
        "codebuff",
        "freebuff",
        "jcode",
        "augment",
        "gjc",
        "junie",
        "dsh",
        "fx",
        "lmstudio",
        "reasonix",
    ]

    /// The files and directories a client's records are read out of.
    ///
    /// A directory is returned rather than each file inside it when the reader
    /// walks the tree anyway; `AgentLogIO.files` and `AgentCache` recurse, so a
    /// new or removed log inside the directory still moves the cache stamp.
    /// Sidecars (Fx's `index.json`, an LM Studio log) live under the returned
    /// roots, so nothing read is left unwatched.
    ///
    /// An environment variable the client honours replaces the default base,
    /// exactly as the client itself does on macOS.
    static func inputs(
        client: String,
        home: URL,
        environment: [String: String] = [:]
    ) -> [URL] {
        switch client {
        case "mux":
            return StructuredLogSupport.unique([home.appending(path: ".mux/sessions")])
        case "codebuff":
            return StructuredLogSupport.unique(codebuffRoots(home: home, environment: environment))
        case "freebuff":
            return StructuredLogSupport.unique(freebuffRoots(home: home, environment: environment))
        case "jcode":
            return StructuredLogSupport.unique(jcodeRoots(home: home, environment: environment))
        case "augment":
            return StructuredLogSupport.unique([home.appending(path: ".augment/sessions")])
        case "gjc":
            return StructuredLogSupport.unique(gjcRoots(home: home, environment: environment))
        case "junie":
            return StructuredLogSupport.unique([home.appending(path: ".junie/sessions")])
        case "dsh":
            return StructuredLogSupport.unique(dshRoots(home: home, environment: environment))
        case "fx":
            return StructuredLogSupport.unique([home.appending(path: ".fx/sessions")])
        case "lmstudio":
            return StructuredLogSupport.unique(lmstudioRoots(home: home, environment: environment))
        case "reasonix":
            return StructuredLogSupport.unique(reasonixRoots(home: home, environment: environment))
        default:
            return []
        }
    }

    /// Decodes a client's roots into incremental records.
    ///
    /// An unknown client yields nothing rather than a guess. A client whose
    /// store is absent yields nothing too: no reader fabricates a record from a
    /// missing file.
    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        guard supportedClients.contains(client) else { return [] }
        return switch client {
        case "mux": MuxUsageReader.records(roots: roots)
        case "codebuff": CodebuffUsageReader.records(roots: roots)
        case "freebuff": FreebuffUsageReader.records(roots: roots)
        case "jcode": JcodeUsageReader.records(roots: roots)
        case "augment": AugmentUsageReader.records(roots: roots)
        case "gjc": GJCUsageReader.records(roots: roots)
        case "junie": JunieUsageReader.records(roots: roots)
        case "dsh": DSHUsageReader.records(roots: roots)
        case "fx": FxUsageReader.records(roots: roots)
        case "lmstudio": LMStudioUsageReader.records(roots: roots)
        case "reasonix": ReasonixUsageReader.records(roots: roots)
        default: []
        }
    }

    /// Human-readable limits of a client's store that a caller should surface
    /// rather than mistake for a zero.
    ///
    /// Today this is Freebuff's estimated-only store and a DSH transcript whose
    /// compression this Mac cannot decode. Empty when there is nothing to warn
    /// about.
    static func notes(client: String, roots: [URL]) -> [String] {
        switch client {
        case "freebuff":
            return [FreebuffUsageReader.limitation]
        case "dsh":
            return DSHUsageReader.notes(roots: roots)
        default:
            return []
        }
    }

    // MARK: - macOS roots

    /// Codebuff's product trees. `CODEBUFF_DATA_DIR` replaces all three.
    private static func codebuffRoots(home: URL, environment: [String: String]) -> [URL] {
        if let override = StructuredLogSupport.directory(environment, "CODEBUFF_DATA_DIR") {
            return [override]
        }
        return [
            home.appending(path: ".config/manicode"),
            home.appending(path: ".config/manicode-dev"),
            home.appending(path: ".config/manicode-staging"),
        ]
    }

    /// Freebuff shares Codebuff's trees; its own env var replaces the base.
    private static func freebuffRoots(home: URL, environment: [String: String]) -> [URL] {
        if let override = StructuredLogSupport.directory(environment, "FREEBUFF_DATA_DIR") {
            return [override]
        }
        return [
            home.appending(path: ".config/manicode"),
            home.appending(path: ".config/manicode-dev"),
            home.appending(path: ".config/manicode-staging"),
        ]
    }

    /// `JCODE_HOME` replaces `~/.jcode`; sessions and their journals live under
    /// `sessions`.
    private static func jcodeRoots(home: URL, environment: [String: String]) -> [URL] {
        let base = StructuredLogSupport.directory(environment, "JCODE_HOME")
            ?? home.appending(path: ".jcode")
        return [base.appending(path: "sessions")]
    }

    /// Gajae Code's session roots, including the config- and data-home
    /// spellings its installers write.
    private static func gjcRoots(home: URL, environment: [String: String]) -> [URL] {
        var roots: [URL] = []
        let agent = StructuredLogSupport.directory(environment, "GJC_CODING_AGENT_DIR")
            ?? home.appending(path: ".gjc/agent")
        roots.append(agent.appending(path: "sessions"))

        for key in ["GJC_CONFIG_DIR", "PI_CONFIG_DIR"] {
            if let base = StructuredLogSupport.directory(environment, key) {
                roots.append(base.appending(path: "agent/sessions"))
            }
        }
        // `$XDG_DATA_HOME/gjc/sessions`, and its default `~/.local/share`
        // spelling when the variable is unset — the same tree on macOS.
        let dataHome = StructuredLogSupport.directory(environment, "XDG_DATA_HOME")
            ?? home.appending(path: ".local/share")
        roots.append(dataHome.appending(path: "gjc/sessions"))
        return roots
    }

    /// `DSH_HOME` replaces `~/.dsh`.
    private static func dshRoots(home: URL, environment: [String: String]) -> [URL] {
        let base = StructuredLogSupport.directory(environment, "DSH_HOME")
            ?? home.appending(path: ".dsh")
        return [base.appending(path: "sessions")]
    }

    /// `LM_STUDIO_HOME` replaces `~/.lmstudio`; server logs sit under it.
    private static func lmstudioRoots(home: URL, environment: [String: String]) -> [URL] {
        let base = StructuredLogSupport.directory(environment, "LM_STUDIO_HOME")
            ?? home.appending(path: ".lmstudio")
        return [base.appending(path: "server-logs")]
    }

    /// `REASONIX_STATE_HOME` names the state directory itself; `REASONIX_HOME`
    /// names its parent, with stats beneath it.
    private static func reasonixRoots(home: URL, environment: [String: String]) -> [URL] {
        if let state = StructuredLogSupport.directory(environment, "REASONIX_STATE_HOME") {
            return [state]
        }
        if let base = StructuredLogSupport.directory(environment, "REASONIX_HOME") {
            return [base.appending(path: "stats")]
        }
        return [home.appending(path: ".reasonix/stats")]
    }
}
