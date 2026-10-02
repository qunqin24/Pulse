// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The Group A session-log family: one entry point that answers, for a client
/// id, where its stores are and what usage increments they contain.
///
/// **It reads, it does not add up.** `records` turns a client's own files into
/// `AgentUsageRecord` increments and stops there; pricing and windowing belong
/// to `AgentUsageLedger.build` and the spend summaries. That boundary is what
/// lets a reader be checked against a synthetic store without a price table,
/// and it is why no reader here invents a number: a client that reports no
/// tokens contributes no record rather than a zero.
///
/// **Two halves, deliberately separate.** `inputs` is the catalog of files a
/// client would be read from, returned even when they do not exist so a cache
/// can watch the real sources; `records` is handed exactly those roots back
/// and parses them. A client whose roots depend on its own contents (Senpi's
/// project children, Prime's honoured `sessionDir`) resolves them in `inputs`,
/// so the watch list and the parse list stay the same set.
enum SessionLogReaders {
    /// Every client this family can parse. A catalog dispatch test asserts it
    /// matches the readers below exactly, so a registered id can never be an
    /// empty implementation.
    static let supportedClients: Set<String> = [
        "pi", "omp", "senpi", "kimchi", "prime-agent",
        "gemini", "qwen", "amp", "droid", "openclaw",
    ]

    /// The roots a client's records are read from, in a stable order.
    ///
    /// A root that does not exist is still named — a client that is not
    /// installed is a catalog miss, not an error — and every file a reader
    /// actually opens is beneath one of these. `environment` is the process
    /// environment, passed in rather than read so a test can drive the
    /// documented overrides without touching the real one.
    static func inputs(
        client: String,
        home: URL,
        environment: [String: String] = [:]
    ) -> [URL] {
        guard supportedClients.contains(client) else { return [] }
        return SessionLogPaths.inputs(client: client, home: home, environment: environment)
    }

    /// The usage increments a client's roots contain.
    ///
    /// No totals, no money, no cumulative snapshots: a client whose persisted
    /// form is a running total (Prime's attributed aggregate, Droid's session
    /// totals) is reconciled or collapsed here, before the builder sees it.
    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        switch client {
        case "pi", "omp", "senpi", "kimchi":
            PiFamilySessionReader.records(client: client, roots: roots)
        case "prime-agent":
            PrimeAgentSessionReader.records(roots: roots)
        case "gemini":
            GeminiSessionReader.records(roots: roots)
        case "qwen":
            QwenSessionReader.records(roots: roots)
        case "amp":
            AmpSessionReader.records(roots: roots)
        case "droid":
            DroidSessionReader.records(roots: roots)
        case "openclaw":
            OpenClawSessionReader.records(roots: roots)
        default:
            []
        }
    }
}
