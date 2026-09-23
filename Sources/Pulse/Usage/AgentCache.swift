import CryptoKit
import Foundation

/// One agent's ledger, kept between launches.
///
/// **The whole ledger rather than its inputs.** `UsageLedgerReader` caches
/// per-file token counts and prices them afresh each time, because a price
/// change should not mean rescanning hundreds of megabytes. These stores are
/// read from several places rather than file-by-file, so the cache keeps the
/// finished ledger — and its validity is settled by the store's real inputs
/// and the price table, not by the store root's own size and date.
enum AgentCache {
    /// Also versions reader semantics: a valid old shape can contain totals
    /// from the old pricing, source-precedence or rewind rules.
    private static let version = 7

    /// Whether the stores' real inputs, and the money behind their cost, are
    /// the same as when the ledger was kept.
    ///
    /// **Not the store's own size and date.** Half these stores are
    /// directories — Grok's sessions and Kimi's — and appending a line to a
    /// log inside one leaves the directory's own stamp untouched, so a
    /// machine could go a week without noticing. The databases have the
    /// mirror-image problem: SQLite writes the WAL, and the `.db` file only
    /// moves when a checkpoint happens, so a restart read a stale disk cache
    /// too.
    struct Stamp: Codable, Equatable {
        /// A digest of every file the ledger was read out of, across every
        /// root. For a directory store that is a recursive walk of its logs
        /// and their title files, by path, size and modification date; for a
        /// database it is the `.db` plus the `-wal` and `-journal` beside it.
        let source: String
        /// A digest of the price table. Money is part of what is kept, so a
        /// table that changed has to invalidate it — including the empty
        /// table an offline first run would otherwise freeze at $0.00 for
        /// ever, since an unchanged store would never be read again.
        let prices: String
    }

    /// The stamp a **set of roots** and the price table produce *now*.
    ///
    /// An agent's records can live in more than one place — a database beside
    /// its logs, two product trees, a capture directory — and every root is
    /// part of its identity. The single-root form below is this one applied to
    /// a list of one.
    ///
    /// Internal rather than private so a test can hold it. The fingerprint is
    /// deliberately taken from the inputs and never from the contents the
    /// readers derive: reading a store must not change its own stamp, or
    /// every read would invalidate the cache it just filled.
    static func stamp(
        for inputs: [URL], prices: [String: ModelPrice], excludingRootDirectories: Set<String> = []
    ) -> Stamp {
        Stamp(source: sourceFingerprint(of: inputs, excludingRootDirectories: excludingRootDirectories),
              prices: priceFingerprint(prices))
    }

    static func stamp(for store: URL, prices: [String: ModelPrice]) -> Stamp {
        stamp(for: [store], prices: prices)
    }

    /// A digest of the files a store is read out of.
    static func sourceFingerprint(of store: URL) -> String {
        sourceFingerprint(of: [store])
    }

    /// A digest of every input across a store's roots.
    ///
    /// **The roots are normalized, ordered and deduplicated first.** Aliases
    /// of one path (`/a/b` and `/a/b/../b`) collapse to one input through
    /// `standardizedFileURL`, the same roots listed differently are the same
    /// store, and a root added or removed moves the digest.
    ///
    /// **Each root contributes its own identity line** as well as the
    /// fingerprint of its real inputs. Without that line two empty stores
    /// would digest alike, and adding a second empty root would change
    /// nothing — but the set of roots *is* part of what the store is.
    ///
    /// For a directory, every regular file beneath it, so **adding, removing
    /// or changing a log — or the `state.json` a title sits in — moves the
    /// digest**. `-shm` is left out on purpose: it is shared memory rather
    /// than data, and merely opening the store can touch it, which would make
    /// a read invalidate the cache it was about to validate. Hidden files and
    /// hidden log subdirectories are **included**: these stores are often
    /// dot-directories, and a log inside one is not optional.
    static func sourceFingerprint(of inputs: [URL], excludingRootDirectories: Set<String> = []) -> String {
        var seen: Set<String> = []
        let ordered = inputs
            .map { $0.standardizedFileURL }
            .sorted { $0.path < $1.path }
            .filter { seen.insert($0.path).inserted }

        var lines: [String] = []
        for store in ordered {
            guard !Task.isCancelled else { return "" }
            // The root itself, before anything inside it.
            lines.append("root\t\(store.path)")
            lines.append(contentsOf: Self.fingerprintLines(of: store, excludingRootDirectories: excludingRootDirectories))
        }

        // Sorted so the enumerator's order cannot make one unchanged store
        // look like two different ones.
        lines.sort()
        return digest(lines.joined(separator: "\n"))
    }

    /// The lines one root contributes to the digest.
    ///
    /// A missing root is a line of its own, so "root not there" is told apart
    /// from "different root" and from the same root with contents.
    private static func fingerprintLines(of store: URL, excludingRootDirectories: Set<String>) -> [String] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: store.path, isDirectory: &isDirectory) else {
            return ["missing\t\(store.path)"]
        }

        var lines: [String] = []

        if isDirectory.boolValue {
            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            if let walker = manager.enumerator(
                at: store,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants]
            ) {
                while let file = autoreleasepool(invoking: { walker.nextObject() as? URL }) {
                    guard !Task.isCancelled else { return [] }
                    if !excludingRootDirectories.isEmpty,
                       file.deletingLastPathComponent().standardizedFileURL == store.standardizedFileURL,
                       excludingRootDirectories.contains(file.lastPathComponent),
                       (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        walker.skipDescendants()
                        continue
                    }
                    // A database's shared-memory index, wherever the database
                    // sits. It is not data and a read touches it.
                    if file.lastPathComponent.hasSuffix("-shm") { continue }
                    let line: String? = autoreleasepool {
                        guard let values = try? file.resourceValues(forKeys: Set(keys)),
                              values.isRegularFile == true else { return nil }
                        return Self.line(file.path, values.fileSize ?? 0, values.contentModificationDate)
                    }
                    if let line { lines.append(line) }
                }
            }
        } else {
            // `""` is the database itself; the sidecars are where SQLite keeps
            // what it has not folded in yet. A missing one is simply absent.
            // The **full path** rather than the file's own name: two roots can
            // each hold a file called `opencode.db`, and they are not the same
            // store.
            for suffix in ["", "-wal", "-journal"] {
                let url = URL(fileURLWithPath: store.path + suffix)
                guard
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                    let size = values.fileSize
                else { continue }
                lines.append(Self.line(url.path, size, values.contentModificationDate))
            }
        }

        return lines
    }

    /// A digest of the price table's rates and names.
    ///
    /// Content, not the file's date: a daily refresh that fetched the same
    /// table must not throw away every agent's cached ledger, and a table
    /// with even one changed rate — or a renamed model — must.
    static func priceFingerprint(_ prices: [String: ModelPrice]) -> String {
        guard !prices.isEmpty else { return "empty" }

        let canonical = prices.keys.sorted().map { id -> String in
            let price = prices[id]!
            let cacheRead = price.cacheRead.map { String($0) } ?? "-"
            let cacheWrite = price.cacheWrite.map { String($0) } ?? "-"
            let name = price.name ?? "-"
            return "\(id)\t\(price.input)\t\(price.output)\t\(cacheRead)\t\(cacheWrite)\t\(name)"
        }
        return digest(canonical.joined(separator: "\n"))
    }

    private static func line(_ path: String, _ size: Int, _ modified: Date?) -> String {
        "\(path)\t\(size)\t\(modified?.timeIntervalSince1970 ?? 0)"
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", Int($0)) }
            .joined()
    }

    struct Saved: Codable {
        let version: Int
        let stamp: Stamp
        let ledger: StoredLedger
    }

    /// `UsageLedger` is not `Codable` and should not become so for this: it
    /// carries display concerns the cache has no business freezing. This is
    /// the part worth keeping.
    struct StoredLedger: Codable {
        /// **Required, not defaulted.** Where the figures came from, and
        /// whether any of their timing is aggregate. A ledger that cannot say
        /// either cannot be trusted to enter a priced total or to draw an hour
        /// series, so an older shape fails the decode and the store is read
        /// again.
        let origin: UsageLedger.Origin
        let hasAggregateTiming: Bool
        /// **Required when decoding, not defaulted there.** Whether any of the
        /// store's counts may be missing. A shape that cannot say would present
        /// a possibly short total as complete, so a cache written without this
        /// key fails the decode and the store is read again. It carries a Swift
        /// default so existing in-code constructions still build.
        var hasPartialCounts = false
        var days: [StoredDay] = []
        var sessions: [StoredSession] = []
        var unpricedModels: [String] = []
        var modelNames: [String: String] = [:]
        var slots: [StoredSlot] = []
    }

    struct StoredDay: Codable {
        let date: Date
        let tokens: Int
        let cost: Double
        let unpricedTokens: Int
        let models: [String: Int]
        let tally: TokenTally
        /// **Required, not defaulted.** Each raw model id's own split by kind.
        /// A cache written before the detail was kept would decode with every
        /// model's categories empty, and a per-model breakdown would then be
        /// unable to tell "this model had no output" from "nobody saved the
        /// output". Missing it has to fail the decode so the store is read
        /// again.
        let modelTallies: [String: TokenTally]
        /// **Required, not defaulted.** Each raw model id's own money,
        /// computed at scan time from its own rates. A cache without it would
        /// decode as an unpriced model rather than re-pricing one that was
        /// already priced, so the missing field has to fail the decode.
        let modelCosts: [String: TokenCost]
        /// **Required, not defaulted.** Each raw model id's own unclassified
        /// tokens. A cache without it would read a bare or session total as a
        /// broken split rather than as a known-unclassified one, and would
        /// then either invent categories or drop the tokens.
        let modelUnclassifiedTokens: [String: Int]
    }

    struct StoredSlot: Codable {
        let start: Date
        let tokens: Int
        let cost: Double
        /// **Required, not defaulted**, for the same reason as
        /// `StoredDay.modelTallies`: a model's own hours come only from here,
        /// and a slot that silently decoded with none would let a drill-down
        /// mistake "no detail" for "no work".
        let models: [String: TokenTally]
    }

    struct StoredSession: Codable {
        let id: String
        let name: String
        let title: String?
        let project: UsageProject?
        let start: Date
        let end: Date
        let tokens: Int
        let cost: Double
        /// **Required, not defaulted.** A cache written before sessions
        /// carried their buckets would otherwise decode with none, leaving
        /// project totals unable to respect the selected span. Missing it has to
        /// fail the decode so the store is read again.
        let slots: [StoredSlot]
        /// Required: aggregate sessions must keep their known calendar dates.
        let days: [StoredSessionDay]
    }

    struct StoredSessionDay: Codable {
        let date: Date
        let tokens: Int
        let cost: Double
    }

    /// Reads the kept ledger back.
    ///
    /// `at` is the file to read; nil means the real cache location. It exists
    /// so a test can drive the production mapping into a private temporary
    /// directory instead of the user's Application Support — a Codable
    /// round-trip of the stored structs alone would pass even if `save` or
    /// `load` forgot a field, which is exactly the fault that would lose
    /// per-model detail across a restart.
    static func load(
        _ agent: SpendAgent,
        at url: URL? = nil
    ) -> (stamp: Stamp, ledger: UsageLedger)? {
        guard
            !Task.isCancelled,
            let data = try? Data(contentsOf: url ?? file(for: agent)),
            let saved = try? JSONDecoder().decode(Saved.self, from: data),
            saved.version == version
        else { return nil }
        guard !Task.isCancelled else { return nil }

        var ledger = UsageLedger(
            origin: saved.ledger.origin,
            hasAggregateTiming: saved.ledger.hasAggregateTiming,
            hasPartialCounts: saved.ledger.hasPartialCounts,
            days: saved.ledger.days.map {
                LedgerDay(
                    date: $0.date, tokens: $0.tokens, cost: $0.cost,
                    unpricedTokens: $0.unpricedTokens, models: $0.models,
                    tally: $0.tally, modelTallies: $0.modelTallies,
                    modelCosts: $0.modelCosts,
                    modelUnclassifiedTokens: $0.modelUnclassifiedTokens
                )
            },
            earliest: saved.ledger.days.first?.date,
            unpricedModels: saved.ledger.unpricedModels,
            modelNames: saved.ledger.modelNames,
            slots: saved.ledger.slots.map {
                .init(start: $0.start, tokens: $0.tokens, cost: $0.cost, models: $0.models)
            }
        )
        ledger.sessions = saved.ledger.sessions.map {
            .init(
                id: $0.id, name: $0.name, title: $0.title, project: $0.project,
                start: $0.start, end: $0.end, tokens: $0.tokens, cost: $0.cost,
                slots: $0.slots.map {
                    .init(start: $0.start, tokens: $0.tokens, cost: $0.cost, models: $0.models)
                },
                days: $0.days.map {
                    .init(date: $0.date, tokens: $0.tokens, cost: $0.cost)
                }
            )
        }
        return (saved.stamp, ledger)
    }

    /// Writes the ledger out.
    ///
    /// `at` mirrors `load`: nil is the real cache location, and an injected URL
    /// lets a test exercise this exact mapping without touching that cache.
    static func save(
        _ ledger: UsageLedger,
        stamp: Stamp,
        for agent: SpendAgent,
        at url: URL? = nil
    ) {
        guard !Task.isCancelled else { return }
        let stored = StoredLedger(
            origin: ledger.origin,
            hasAggregateTiming: ledger.hasAggregateTiming,
            hasPartialCounts: ledger.hasPartialCounts,
            days: ledger.days.map {
                StoredDay(
                    date: $0.date, tokens: $0.tokens, cost: $0.cost,
                    unpricedTokens: $0.unpricedTokens, models: $0.models,
                    tally: $0.tally, modelTallies: $0.modelTallies,
                    modelCosts: $0.modelCosts,
                    modelUnclassifiedTokens: $0.modelUnclassifiedTokens
                )
            },
            sessions: ledger.sessions.map {
                StoredSession(
                    id: $0.id, name: $0.name, title: $0.title, project: $0.project,
                    start: $0.start, end: $0.end, tokens: $0.tokens, cost: $0.cost,
                    slots: $0.slots.map {
                        StoredSlot(start: $0.start, tokens: $0.tokens, cost: $0.cost, models: $0.models)
                    },
                    days: $0.days.map {
                        StoredSessionDay(date: $0.date, tokens: $0.tokens, cost: $0.cost)
                    }
                )
            },
            unpricedModels: ledger.unpricedModels,
            modelNames: ledger.modelNames,
            slots: ledger.slots.map {
                StoredSlot(start: $0.start, tokens: $0.tokens, cost: $0.cost, models: $0.models)
            }
        )

        guard let data = try? JSONEncoder().encode(Saved(version: version, stamp: stamp, ledger: stored)) else { return }
        guard !Task.isCancelled else { return }
        let destination = url ?? file(for: agent)
        if url == nil { PulseStorage.prepare() }
        try? data.write(to: destination, options: .atomic)
    }

    static func file(for agent: SpendAgent, directory: URL = PulseStorage.directory) -> URL {
        // **The number is the stored shape.** A `1` has a store-shaped stamp
        // and sessions without buckets; a `2` has the right stamp but no
        // per-model detail on its days or slots, so a model's categories and
        // hours cannot be told from "nothing was saved"; a `3` has that detail
        // but no per-model money, so a drill-down would read every model as
        // unpriced. A `4` computes its stamp from a single root and counts a
        // database's shared-memory sidecar inside a directory walk.
        //
        // All decode differently now, and a store left at any of them would
        // never be read again. Renaming forces the one rescan that fills the
        // detail in and recomputes the fingerprint over the roots that are
        // actually read. `agent-5` also **requires** the origin, the aggregate
        // flag, the partial-counts flag and each day's unclassified tokens: a
        // shape without them cannot say whether it may be priced, drawn per
        // hour, or trusted as a whole, so it must not decode.
        // Version 6 adds session calendar days and invalidates the former
        // vendor-pricing, Devin mirror and Command Code rewind totals.
        // Version 7 preserves project identity independently of its display name.
        directory.appending(path: "agent-\(version)-\(agent.rawValue).json")
    }
}
