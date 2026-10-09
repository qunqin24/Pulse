// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// One ledger per agent, however that agent keeps its records.
///
/// `UsageLedgerReader` reads the two CLIs that write JSONL transcripts and is
/// keyed by `Provider`, because what it was built for is the per-provider
/// history card. This is the other axis: every agent that has spent tokens on
/// this Mac, whether or not Pulse draws a ring for it.
///
/// **The two it already reads are delegated, not re-read.** Claude Code and
/// Codex go through the same reader and the same cache as before. The five
/// other legacy agents keep their own store readers (`OpenCodeStore`,
/// `GrokStore`, `KimiCLIStore`, `DevinCLIStore`). Everything added since is
/// handed to `AgentRecordReaders` and built by `AgentUsageLedger.build`, so
/// there is one pricing path for all of them. Devin Desktop additionally
/// receives the native databases being counted, to exclude matched mirrors.
///
/// **An agent can have more than one root.** Its inputs are resolved to the
/// ones that exist, the cache stamp is taken over that whole set, and the set
/// is resolved *again* after the read: a root appended to — or one that
/// disappeared — while Pulse was reading produces a ledger the before stamp no
/// longer describes, so it is kept for this view only and never written as
/// a stable disk cache.
///
/// **A partially decoded read is never a stable cache.** A reader can meet
/// history it cannot decode — a compressed transcript, say — and return fewer
/// records than the store holds. That ledger is still shown, but it is not
/// written to disk: a later build that *can* decode the same, unchanged files
/// would otherwise be blocked by the old partial cache. Only a read that had
/// no such limit and left the stores where it found them is persisted.
actor AgentLedgers {
    static let shared = AgentLedgers()

    struct Progress: Sendable {
        let agent: SpendAgent
        let index: Int
        let total: Int
    }

    struct Snapshot: Sendable {
        var ledgers: [SpendAgent: UsageLedger] = [:]
        var notes: [SpendAgent: [String]] = [:]
    }

    /// The last finished scan, kept while Token spend is on so the pane opens
    /// on figures instead of a spinner (`SpendWarmer` keeps it current).
    ///
    /// **One snapshot, replaced, never a second copy.** The memory work on the
    /// readers was about peaks during a read; a finished snapshot is ledgers,
    /// not transcripts, and the floating panel's cards already hold the same
    /// kind of thing. Dropped the moment Token spend is switched off.
    private var kept: (snapshot: Snapshot, at: Date)?

    private let home: URL
    private let environment: [String: String]
    private let cacheDirectory: URL?
    private let transcriptReader: UsageLedgerReader
    private let prices: @Sendable () async -> [String: ModelPrice]

    /// Injected locations/prices let cancellation tests run the real scan and
    /// cache boundary without opening a user's stores or contacting models.dev.
    init(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cacheDirectory: URL? = nil,
        prices: @escaping @Sendable () async -> [String: ModelPrice] = { await ModelPrices.shared.prices() }
    ) {
        self.home = home
        self.environment = environment
        self.cacheDirectory = cacheDirectory
        self.prices = prices
        transcriptReader = cacheDirectory == nil && home == URL(fileURLWithPath: NSHomeDirectory())
            ? .shared : UsageLedgerReader(home: home, cacheDirectory: cacheDirectory)
    }

    /// The last finished scan and when it finished, if Token spend is on and
    /// one has.
    func keptSnapshot() -> (snapshot: Snapshot, at: Date)? { kept }

    /// Lets the kept scan go — Token spend was switched off.
    func forget() { kept = nil }

    /// Runs in the caller's task: cancelling the pane propagates into the
    /// synchronous file/row loops. No detached worker can outlive that task.
    /// A scan that finishes replaces the kept one (`keptSnapshot()`).
    func scan(
        refresh: Bool = false,
        progress: @MainActor @Sendable (Progress) -> Void = { _ in }
    ) async throws -> Snapshot {
        try Task.checkCancellation()
        let prices = await prices()
        try Task.checkCancellation()
        let present = SpendAgent.present(home: home, environment: environment)
        var result = Snapshot()
        for (index, agent) in present.enumerated() {
            try Task.checkCancellation()
            await progress(Progress(agent: agent, index: index, total: present.count))
            try Task.checkCancellation()

            if let provider = agent.provider {
                // Revalidate per-file stamps on each visit; unchanged transcripts
                // are still served by that reader's disk cache.
                result.ledgers[agent] = await transcriptReader.ledger(for: provider, refresh: true, prices: prices)
            } else {
                let read = try autoreleasepool {
                    try readCached(agent, prices: prices, refresh: refresh)
                }
                result.ledgers[agent] = read.ledger
                if !read.notes.isEmpty { result.notes[agent] = read.notes }
            }
            try Task.checkCancellation()
        }
        kept = (result, Date())
        return result
    }

    /// One agent's ledger, for the detailed hover card of the provider whose
    /// mark it borrows. The same readers and the same cache as `scan`, so the
    /// card and the Token spend pane cannot count one store two ways.
    func ledger(for agent: SpendAgent) async -> UsageLedger {
        let prices = await prices()
        guard !Task.isCancelled else { return .empty }
        if let provider = agent.provider {
            return await transcriptReader.ledger(for: provider, refresh: true, prices: prices)
        }
        let read = try? autoreleasepool {
            try readCached(agent, prices: prices, refresh: false)
        }
        return read?.ledger ?? .empty
    }

    private func readCached(_ agent: SpendAgent, prices: [String: ModelPrice], refresh: Bool) throws -> ReadResult {
        let before = Self.stamp(agent, home: home, environment: environment, prices: prices)
        try Task.checkCancellation()
        let file = cacheDirectory.map { AgentCache.file(for: agent, directory: $0) }
        let saved = AgentCache.load(agent, at: file)
        if !refresh, let before, let saved, saved.stamp == before {
            try Task.checkCancellation()
            return ReadResult(ledger: kept(saved.ledger, stable: true, agent: agent, prices: prices), notes: [])
        }

        let outcome = Self.read(agent, prices: prices, home: home, environment: environment)
        try Task.checkCancellation()
        let after = Self.stamp(agent, home: home, environment: environment, prices: prices)
        try Task.checkCancellation()
        let stable = Self.canPersist(notes: outcome.notes, before: before, after: after)
        if stable, let before {
            AgentCache.save(outcome.ledger, stamp: before, for: agent, at: file)
        }
        // The cache this read replaces was itself a stable read: what it held
        // and this one does not is what the store has deleted since.
        let ledger = kept(outcome.ledger, previous: saved?.ledger, stable: stable, agent: agent, prices: prices)
        return ReadResult(ledger: ledger, notes: outcome.notes)
    }

    /// Where an agent's kept history lives (`AgentArchive`): the cache folder
    /// handed in, or Pulse's own when this reads the real home. **Nowhere
    /// otherwise** — a reader pointed at another home must not mark its
    /// records into this Mac's history.
    private var archiveDirectory: URL? {
        cacheDirectory ?? (home.standardizedFileURL == URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
            ? PulseStorage.directory : nil)
    }

    /// A live ledger with the agent's kept history added in, after a stable
    /// read has raised the marks (`AgentArchive`). An archive that cannot be
    /// read leaves the ledger as read and is not written over.
    private func kept(
        _ live: UsageLedger, previous: UsageLedger? = nil, stable: Bool,
        agent: SpendAgent, prices: [String: ModelPrice]
    ) -> UsageLedger {
        guard !Task.isCancelled, AgentArchive.keeps(agent), let directory = archiveDirectory,
              var archive = AgentArchive.load(for: agent, directory: directory) else { return live }
        if stable, archive.absorb(live, previous: previous) { archive.save(for: agent, directory: directory) }
        return archive.merged(into: live, prices: prices, vendor: agent.priceVendor)
    }

    /// Whether a read may be written to the disk cache.
    ///
    /// Three conditions, and all three are required: the reader reported no
    /// limit (a partial ledger would hide history a fixed reader could later
    /// recover), the stores existed before the read, and they are unchanged
    /// after it. Kept as a pure rule so the guard itself is testable without an
    /// actor or a store.
    static func canPersist(
        notes: [String],
        before: AgentCache.Stamp?,
        after: AgentCache.Stamp?
    ) -> Bool {
        guard notes.isEmpty, let before, let after else { return false }
        return after == before
    }

    /// The stamp for an agent's existing roots, or nil when it has none.
    private static func stamp(
        _ agent: SpendAgent,
        home: URL,
        environment: [String: String],
        prices: [String: ModelPrice]
    ) -> AgentCache.Stamp? {
        let stores = agent.stores(home: home, environment: environment)
        guard !stores.isEmpty else { return nil }
        return AgentCache.stamp(
            for: stores, prices: prices,
            excludingRootDirectories: [.codeBuddy, .workBuddy].contains(agent) ? ["binaries"] : []
        )
    }

    /// One agent's read: the ledger it produced, and any limit the reader met.
    struct ReadResult: Sendable {
        let ledger: UsageLedger
        let notes: [String]
    }

    // Internal so fixture tests exercise the production dispatch, including
    // which plan vendor each agent passes to its shared store reader.
    static func read(
        _ agent: SpendAgent,
        prices: [String: ModelPrice],
        home: URL,
        environment: [String: String]
    ) -> ReadResult {
        guard !Task.isCancelled else { return ReadResult(ledger: .empty, notes: []) }
        let stores = agent.stores(home: home, environment: environment)

        switch agent {
        // The legacy store readers, each with the one store it was built for,
        // and no reader-level limits to report.
        case .openCode, .kiloCLI:
            guard let store = stores.first else { return ReadResult(ledger: .empty, notes: []) }
            return ReadResult(
                ledger: OpenCodeStore.ledger(at: store, prices: prices, vendor: agent.priceVendor), notes: []
            )
        case .grok:
            guard let store = stores.first else { return ReadResult(ledger: .empty, notes: []) }
            return ReadResult(ledger: GrokStore.ledger(at: store, prices: prices), notes: [])
        case .kimiCLI:
            guard let store = stores.first else { return ReadResult(ledger: .empty, notes: []) }
            return ReadResult(ledger: KimiCLIStore.ledger(at: store, prices: prices), notes: [])
        case .devinCLI:
            guard let store = stores.first else { return ReadResult(ledger: .empty, notes: []) }
            return ReadResult(ledger: DevinCLIStore.ledger(at: store, prices: prices), notes: [])
        case .devinDesktop:
            let records = DevinDesktopReader.records(
                roots: stores,
                authoritativeDatabases: SpendAgent.devinCLI.stores(home: home, environment: environment)
            )
            return ReadResult(
                ledger: AgentUsageLedger.build(records, prices: prices, namespace: agent.rawValue), notes: []
            )
        // Read by `UsageLedgerReader`, and never routed here.
        case .claudeCode, .codex:
            return ReadResult(ledger: .empty, notes: [])
        // Every catalog client, from its family's normalized records.
        default:
            guard !stores.isEmpty else { return ReadResult(ledger: .empty, notes: []) }
            let read = AgentRecordReaders.read(client: agent.sourceID, roots: stores)
            let ledger = AgentUsageLedger.build(
                read.records,
                prices: prices,
                namespace: agent.rawValue,
                vendor: agent.priceVendor,
                // An export or capture is the account's movement, not
                // necessarily this Mac's own transcript; it can still be
                // priced, but it is not claimed as a local transcript.
                origin: agent.requiresUsageExport ? .importedRecords : .localTranscripts
            )
            // A source that reports no token counters has nothing to be a
            // *partial* read of; its note is a permanent "no counters" string
            // and is left to the zero-record list instead. Only a source that
            // does report counts can have a decode limit worth stating.
            let notes = agent.reportsTokenCounts
                ? read.notes
                : []
            return ReadResult(ledger: ledger, notes: notes)
        }
    }
}
