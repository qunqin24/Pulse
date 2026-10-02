// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The catalog and dispatch for the editor/agent stores read here.
///
/// **One entry point, one family per file.** Each family below owns its own
/// roots, its own format and its own identity rules; this type only decides
/// which family a client belongs to and combines the two clients that have
/// more than one store (Cline's VS Code task log and its CLI). Keeping the
/// dispatch this thin is what stops the reader layer from growing into one
/// thousand-line switch.
///
/// `inputs` returns every root a client is actually read from — transcript
/// directories, metadata files and referenced databases — so the spend cache
/// watches the real sources. `records` takes those same roots back and returns
/// normalized **increments**; it never prices them itself. A client that
/// reports no usable counts yields no records and says so at its own boundary.
enum EditorLogReaders {
    /// Group B's nine canonical clients.
    static let supportedClients: Set<String> = [
        "roocode",
        "kilocode",
        "cline",
        "codebuddy",
        "workbuddy",
        "cherrystudio",
        "commandcode",
        "opencodereview",
        "zcode",
    ]

    /// Every root the named client is read from.
    ///
    /// A root is returned whether or not it exists yet: the caller's cache
    /// fingerprints a missing root as its own state, so a store that appears
    /// later invalidates exactly the agent it belongs to.
    static func inputs(
        client: String,
        home: URL,
        environment: [String: String] = [:]
    ) -> [URL] {
        switch client {
        case "roocode", "kilocode":
            return VSCodeTaskLogReader.inputs(client: client, home: home)
        case "cline":
            return VSCodeTaskLogReader.inputs(client: client, home: home)
                + ClineCLIReader.inputs(home: home, environment: environment)
        case "codebuddy", "workbuddy":
            return TencentBuddyReader.inputs(client: client, home: home)
        case "cherrystudio":
            return CherryStudioReader.inputs(home: home)
        case "commandcode":
            return CommandCodeReader.inputs(home: home)
        case "opencodereview":
            return OpenCodeReviewReader.inputs(home: home)
        case "zcode":
            return ZCodeReader.inputs(home: home)
        default:
            return []
        }
    }

    /// Normalized incremental records for the named client, from its roots.
    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        switch client {
        case "roocode", "kilocode":
            return VSCodeTaskLogReader.records(client: client, roots: roots)
        case "cline":
            return VSCodeTaskLogReader.records(client: client, roots: roots)
                + ClineCLIReader.records(roots: roots)
        case "codebuddy", "workbuddy":
            return TencentBuddyReader.records(client: client, roots: roots)
        case "cherrystudio":
            return CherryStudioReader.records(roots: roots)
        case "commandcode":
            return CommandCodeReader.records(roots: roots)
        case "opencodereview":
            return OpenCodeReviewReader.records(roots: roots)
        case "zcode":
            return ZCodeReader.records(roots: roots)
        default:
            return []
        }
    }
}
