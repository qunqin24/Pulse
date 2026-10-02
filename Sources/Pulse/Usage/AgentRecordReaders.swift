// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The single catalogue every agent reader is dispatched from.
///
/// **One router, six families.** Each family owns its products' formats and
/// identities: `SessionLogReaders` (Group A's ten session logs),
/// `EditorLogReaders` (Group B's nine editor stores), `DatabaseLogReaders`
/// (Group C's nine databases), `StructuredLogReaders` (Group D's eleven
/// structured stores), `CapturedUsageReaders` (Group E's six explicit
/// exports/captures) and `CopilotLogReader` (Group F's one client). This type
/// only answers *which family a canonical client belongs to* and forwards the
/// two questions a caller has — where its roots are (`inputs`) and what
/// increments they contain (`records`).
///
/// **The dispatch is exhaustive on purpose.** A client is routed by its
/// membership in a family's `supportedClients`, never by a `default` arm that
/// swallows a case nobody implemented. The catalogue test asserts the union is
/// exactly the forty-six non-legacy clients and that every one of them routes
/// to a family, so a client added to `SpendAgent` without a reader fails the
/// test instead of quietly reporting nothing.
///
/// **No client here becomes a `Provider`.** The families hand back
/// `AgentUsageRecord`s; there is no `Provider` case, no ring and no rail slot
/// anywhere on this path.
enum AgentRecordReaders {
    /// One entry per reader family, so routing can be named and tested without
    /// a second list of client ids.
    enum Family: String, CaseIterable, Sendable {
        case sessionLogs
        case editorLogs
        case databaseLogs
        case structuredLogs
        case capturedUsage
        case copilot

        /// The canonical clients this family answers for.
        var clients: Set<String> {
            switch self {
            case .sessionLogs: SessionLogReaders.supportedClients
            case .editorLogs: EditorLogReaders.supportedClients
            case .databaseLogs: DatabaseLogReaders.supportedClients
            case .structuredLogs: StructuredLogReaders.supportedClients
            case .capturedUsage: CapturedUsageReaders.supportedClients
            case .copilot: CopilotLogReader.supportedClients
            }
        }
    }

    /// Every canonical client the catalogue can read.
    static let supportedClients: Set<String> = Set(Family.allCases.flatMap(\.clients))

    /// The family a canonical client belongs to, or nil for one no reader
    /// handles — which includes the seven legacy clients, read elsewhere.
    static func family(for client: String) -> Family? {
        Family.allCases.first { $0.clients.contains(client) }
    }

    /// Every root a client's records are read from, whether or not the roots
    /// exist. Unknown clients have no inputs rather than a guessed path.
    static func inputs(client: String, home: URL, environment: [String: String]) -> [URL] {
        switch family(for: client) {
        case .sessionLogs:
            SessionLogReaders.inputs(client: client, home: home, environment: environment)
        case .editorLogs:
            EditorLogReaders.inputs(client: client, home: home, environment: environment)
        case .databaseLogs:
            DatabaseLogReaders.inputs(client: client, home: home, environment: environment)
        case .structuredLogs:
            StructuredLogReaders.inputs(client: client, home: home, environment: environment)
        case .capturedUsage:
            CapturedUsageReaders.inputs(client: client, home: home, environment: environment)
        case .copilot:
            CopilotLogReader.inputs(client: client, home: home, environment: environment)
        case nil:
            []
        }
    }

    /// The normalized increments a client's roots contain. Pricing, windows
    /// and origin are the caller's job; a reader here never invents a count.
    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        guard !Task.isCancelled else { return [] }
        return switch family(for: client) {
        case .sessionLogs:
            SessionLogReaders.records(client: client, roots: roots)
        case .editorLogs:
            EditorLogReaders.records(client: client, roots: roots)
        case .databaseLogs:
            DatabaseLogReaders.records(client: client, roots: roots)
        case .structuredLogs:
            StructuredLogReaders.records(client: client, roots: roots)
        case .capturedUsage:
            CapturedUsageReaders.records(client: client, roots: roots)
        case .copilot:
            CopilotLogReader.records(client: client, roots: roots)
        case nil:
            []
        }
    }

    /// Reader-level limitations for the roots that were actually read.
    ///
    /// **A short, non-fatal status, never an error.** The database and
    /// structured families can meet a store they can only partly decode — a
    /// zstd frame this Mac cannot open, a transcript whose compression is
    /// unknown — and return fewer records than the store holds. A caller that
    /// showed those records alone would present an incomplete history as the
    /// whole. A family may also state a store's own permanent limit, as
    /// Freebuff's store does; deciding which of those a pane should surface is
    /// the caller's business, not this function's. The other families have
    /// nothing to report and contribute no notes. The strings are the readers'
    /// own English diagnostics; a UI is expected to map their presence, not
    /// their text, to its own copy.
    static func notes(client: String, roots: [URL]) -> [String] {
        guard !Task.isCancelled else { return [] }
        return switch family(for: client) {
        case .databaseLogs:
            DatabaseLogReaders.notes(client: client, roots: roots)
        case .structuredLogs:
            StructuredLogReaders.notes(client: client, roots: roots)
        case .sessionLogs, .editorLogs, .capturedUsage, .copilot, nil:
            []
        }
    }
}
