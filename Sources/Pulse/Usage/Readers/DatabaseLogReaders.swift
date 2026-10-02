// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The entry point for the agents Pulse reads out of a database or an event
/// log rather than a Claude-shaped transcript.
///
/// **One catalogue, one dispatch.** `supportedClients` names every product
/// this family understands; `inputs` answers where a product's work lives so
/// the multi-root cache watches the real sources (a project registry and the
/// databases it references, a home directory and its named profiles); and
/// `records` turns what it finds into the same `AgentUsageRecord` every other
/// native reader produces.
///
/// **Independent, not ported.** These readers were written from the format
/// facts of a compatibility target — file locations, column meanings, units
/// and event identities — and from Pulse's own helpers. No upstream parser,
/// fixture or comment is reproduced, and nothing here is derived from a cost,
/// a text length, an elapsed time or a missing field.
enum DatabaseLogReaders {
    /// The canonical ids this family answers for. A catalogue test asserts the
    /// set is exactly the clients the app dispatches here.
    static let supportedClients: Set<String> = [
        "hermes", "goose", "zed", "kiro", "crush", "unsloth",
        "antigravity-cli", "antigravity-ide", "micode", "devin-desktop",
    ]

    /// Every root a client's records are read out of, **including metadata
    /// registries and referenced databases**, so the cache's fingerprint sees a
    /// change to any of them.
    ///
    /// `home` is the user's home directory and `environment` the process
    /// environment, both injected so a test never reads the machine it runs on.
    /// Unknown clients have no inputs.
    static func inputs(
        client: String,
        home: URL,
        environment: [String: String] = [:]
    ) -> [URL] {
        switch client {
        case "hermes": return HermesReader.inputs(home: home, environment: environment)
        case "goose": return GooseReader.inputs(home: home, environment: environment)
        case "zed": return ZedReader.inputs(home: home, environment: environment)
        case "kiro": return KiroReader.inputs(home: home, environment: environment)
        case "crush": return CrushReader.inputs(home: home, environment: environment)
        case "unsloth": return UnslothReader.inputs(home: home, environment: environment)
        case "antigravity-cli", "antigravity-ide":
            return AntigravityCLIReader.inputs(client: client, home: home, environment: environment)
        case "micode": return MicodeReader.inputs(home: home, environment: environment)
        case "devin-desktop":
            return DevinDesktopReader.inputs(home: home, environment: environment)
        default: return []
        }
    }

    /// A client's known reading limitation, when its store holds data this
    /// machine cannot decode — surfaces as a note rather than a silent zero.
    /// Today only Zed's compressed threads have one.
    static func notes(client: String, roots: [URL]) -> [String] {
        switch client {
        case "zed": return ZedReader.notes(roots: roots)
        default: return []
        }
    }

    /// The records a client's roots contain, already diffed into increments
    /// where the product reports cumulative snapshots.
    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        switch client {
        case "hermes": return HermesReader.records(roots: roots)
        case "goose": return GooseReader.records(roots: roots)
        case "zed": return ZedReader.records(roots: roots)
        case "kiro": return KiroReader.records(roots: roots)
        case "crush": return CrushReader.records(roots: roots)
        case "unsloth": return UnslothReader.records(roots: roots)
        case "antigravity-cli", "antigravity-ide": return AntigravityCLIReader.records(roots: roots)
        case "micode": return MicodeReader.records(roots: roots)
        case "devin-desktop": return DevinDesktopReader.records(roots: roots)
        default: return []
        }
    }
}
