import Foundation
import SQLite3
import Testing
@testable import Pulse

/// Whether the disk cache that keeps an agent's finished ledger is valid:
/// settled by the store's real inputs and the price table, never by the store
/// root's own size and date.
@Suite("Agent cache")
struct AgentCacheTests {
    private static func temporary(_ name: String) -> URL {
        URL.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
    }

    private static func append(_ text: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    @Test("A log appended to inside a store moves the fingerprint, though the directory's stamp does not")
    func nestedAppendsAreSeen() throws {
        let root = Self.temporary("grok-store")
        let run = root.appending(path: "%2FUsers%2Fme%2FCode").appending(path: "01a0")
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let log = run.appending(path: "updates.jsonl")
        try "{\"timestamp\":1}\n".write(to: log, atomically: true, encoding: .utf8)

        let before = AgentCache.sourceFingerprint(of: root)
        let rootBefore = try root.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        // A plain append: the file grows, the directory entry does not change.
        try Self.append("{\"timestamp\":2}\n", to: log)
        let after = AgentCache.sourceFingerprint(of: root)
        let rootAfter = try root.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        #expect(before != after)
        // The store root's own values, which the old stamp was built from,
        // need not have moved at all — which is exactly why it missed this.
        #expect(rootBefore.contentModificationDate == rootAfter.contentModificationDate)
    }

    @Test("Adding and removing a session file moves the fingerprint")
    func additionsAndRemovalsAreSeen() throws {
        let root = Self.temporary("kimi-store")
        let first = root.appending(path: "hash/one")
        let second = root.appending(path: "hash/two")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "{}".write(to: first.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        let one = AgentCache.sourceFingerprint(of: root)

        try "{}".write(to: second.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        let two = AgentCache.sourceFingerprint(of: root)
        #expect(one != two)

        try FileManager.default.removeItem(at: second)
        #expect(AgentCache.sourceFingerprint(of: root) == one)
    }

    @Test("A session's title file is part of the store")
    func titleFilesArePartOfTheStore() throws {
        let root = Self.temporary("kimi-title")
        let session = root.appending(path: "hash/session")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "{}".write(to: session.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        let before = AgentCache.sourceFingerprint(of: root)

        // The title lives in `state.json` beside the wire log; a rename must
        // invalidate a ledger whose session row carries the old one.
        try #"{"custom_title":"A new name"}"#.write(
            to: session.appending(path: "state.json"), atomically: true, encoding: .utf8
        )
        #expect(before != AgentCache.sourceFingerprint(of: root))
    }

    @Test("Reading a store does not change its own fingerprint")
    func readingDoesNotInvalidateTheCache() throws {
        let root = Self.temporary("kimi-read")
        let session = root.appending(path: "hash/session")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let wire = session.appending(path: "wire.jsonl")
        try #"{"timestamp":1}"#.write(to: wire, atomically: true, encoding: .utf8)

        let before = AgentCache.sourceFingerprint(of: root)
        _ = try Data(contentsOf: wire)
        #expect(before == AgentCache.sourceFingerprint(of: root))
    }

    @Test("A database's write-ahead log counts; its shared-memory index does not")
    func databaseSidecars() throws {
        let directory = Self.temporary("db-store")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let db = directory.appending(path: "opencode.db")
        try Data([0x01]).write(to: db)
        let main = AgentCache.sourceFingerprint(of: db)

        // SQLite commits into the WAL first; the `.db` can sit unchanged
        // across a restart while the work is all in the log beside it.
        try Data([0x02, 0x03]).write(to: URL(fileURLWithPath: db.path + "-wal"))
        let withWAL = AgentCache.sourceFingerprint(of: db)
        #expect(main != withWAL)

        // `-shm` is shared memory the act of opening the store touches, so it
        // must not count — otherwise every read would invalidate the cache it
        // just filled.
        try Data([0x04]).write(to: URL(fileURLWithPath: db.path + "-shm"))
        #expect(AgentCache.sourceFingerprint(of: db) == withWAL)
    }

    @Test("A real WAL commit moves the fingerprint while the open database's own stamp sits still")
    func aRealWALCommitIsSeen() throws {
        let directory = Self.temporary("real-wal")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let db = directory.appending(path: "sessions.db")
        var writer: OpaquePointer?
        #expect(sqlite3_open(db.path, &writer) == SQLITE_OK)
        // Left open for the whole test: *closing* a WAL database is what
        // checkpoints it into the `.db`, which is exactly the event that
        // would hide the window this covers.
        defer { sqlite3_close(writer) }

        for sql in [
            "PRAGMA journal_mode=WAL;",
            "PRAGMA wal_autocheckpoint=0;",
            "CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT);",
            "INSERT INTO t (v) VALUES ('one');",
        ] {
            #expect(sqlite3_exec(writer, sql, nil, nil, nil) == SQLITE_OK)
        }

        // WAL mode is established and the first row is committed into the WAL,
        // so the `.db` has settled at its size for the statements that follow.
        let dbBefore = try URL(fileURLWithPath: db.path)
            .resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fingerprintBefore = AgentCache.sourceFingerprint(of: db)

        #expect(sqlite3_exec(writer, "INSERT INTO t (v) VALUES ('two');", nil, nil, nil) == SQLITE_OK)

        let dbAfter = try URL(fileURLWithPath: db.path)
            .resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fingerprintAfter = AgentCache.sourceFingerprint(of: db)

        // The writer is still open: the commit went to the WAL, not the `.db`.
        #expect(dbBefore.fileSize == dbAfter.fileSize)
        #expect(dbBefore.contentModificationDate == dbAfter.contentModificationDate)
        // Which is exactly why the fingerprint has to include the WAL.
        #expect(fingerprintBefore != fingerprintAfter)

        // The shared-memory index really is there, and is not part of the
        // digest: moving its date must not read as a data change.
        let shm = URL(fileURLWithPath: db.path + "-shm")
        #expect(FileManager.default.fileExists(atPath: shm.path))
        let settled = AgentCache.sourceFingerprint(of: db)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: shm.path
        )
        #expect(AgentCache.sourceFingerprint(of: db) == settled)
    }

    @Test("An empty price table is its own stamp, and one changed rate is a different one")
    func pricesArePartOfTheStamp() {
        #expect(AgentCache.priceFingerprint([:]) == "empty")

        let table = ["m": ModelPrice(input: 1, output: 2, cacheRead: nil, cacheWrite: nil, name: nil)]
        let digest = AgentCache.priceFingerprint(table)
        #expect(digest != "empty")
        // The same table is the same digest, so a daily refresh that fetched
        // nothing new does not throw every cached ledger away.
        #expect(AgentCache.priceFingerprint(table) == digest)
        // A changed rate is a different digest.
        let raised = ["m": ModelPrice(input: 9, output: 2, cacheRead: nil, cacheWrite: nil, name: nil)]
        #expect(AgentCache.priceFingerprint(raised) != digest)
    }

    @Test("A ledger cached offline at $0.00 is invalidated when prices arrive")
    func anEmptyPriceTableDoesNotStick() throws {
        let store = Self.temporary("offline-store")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: store) }

        let offline = AgentCache.stamp(for: store, prices: [:])
        let online = AgentCache.stamp(
            for: store,
            prices: ["m": ModelPrice(input: 1, output: 2, cacheRead: nil, cacheWrite: nil, name: nil)]
        )
        // The store is untouched; only the price table changed. Without the
        // table in the stamp the first offline run would be cached at $0.00
        // for ever, because an unchanged store is never read again.
        #expect(offline.source == online.source)
        #expect(offline != online)
    }

    @Test("A cache written before sessions kept their buckets does not decode")
    func theOldShapeDoesNotDecode() throws {
        // The `agent-1` shape: a store-sized stamp, and a session with no
        // buckets. If this decoded, every project in it would total $0.00
        // rather than the store being read again.
        let old = """
        {"stamp":{"size":1,"modified":0},"ledger":{"days":[],"sessions":[\
        {"id":"s","name":"n","start":0,"end":0,"tokens":1,"cost":0.1}],\
        "unpricedModels":[],"modelNames":{},"slots":[]}}
        """
        var decoded = false
        do {
            _ = try JSONDecoder().decode(AgentCache.Saved.self, from: Data(old.utf8))
            decoded = true
        } catch {}
        #expect(!decoded)
    }

    @Test("A kept session's buckets survive the cache round-trip")
    func sessionSlotsRoundTrip() throws {
        let stored = AgentCache.StoredSession(
            id: "s", name: "n", title: "T", project: UsageProject("Pulse"),
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 200),
            tokens: 15, cost: 1.5, unpricedTokens: 0,
            slots: [AgentCache.StoredSlot(
                start: Date(timeIntervalSince1970: 100), tokens: 15, cost: 1.5, unpricedTokens: 0, models: [:]
            )], days: []
        )
        let back = try JSONDecoder().decode(
            AgentCache.StoredSession.self, from: JSONEncoder().encode(stored)
        )
        #expect(back.slots.count == 1)
        #expect(back.slots.first?.tokens == 15)
        #expect(back.slots.first?.cost == 1.5)
        #expect(back.slots.first?.start == Date(timeIntervalSince1970: 100))
    }

    @Test("Caches from earlier reader rules and sessions without day metadata are rejected")
    func readerVersionAndSessionDaysAreRequired() throws {
        let root = Self.temporary("cache-reader-version")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "agent.json")
        let ledger = AgentUsageLedger.build(
            [AgentUsageRecord(timestamp: Date(timeIntervalSince1970: 1_789_372_800), model: "m",
                              tally: TokenTally(input: 100), sessionID: "s", isAggregate: true)],
            prices: [:], namespace: "cursor"
        )
        AgentCache.save(ledger, stamp: .init(source: "s", prices: "p"), for: .cursor, at: file)
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        for version: Int? in [nil, 5, 6, 7, 9] {
            var changed = saved
            changed["version"] = version
            try JSONSerialization.data(withJSONObject: changed).write(to: file)
            #expect(AgentCache.load(.cursor, at: file) == nil)
        }

        var changed = saved
        var storedLedger = try #require(changed["ledger"] as? [String: Any])
        var sessions = try #require(storedLedger["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "days")
        storedLedger["sessions"] = sessions
        changed["ledger"] = storedLedger
        try JSONSerialization.data(withJSONObject: changed).write(to: file)
        #expect(AgentCache.load(.cursor, at: file) == nil)
    }

    @Test("Per-model money and detail survive a real save and load, including a partial name")
    func modelDetailSurvivesSaveAndLoad() throws {
        // Through the production mapping, not a hand-rolled Codable mirror: a
        // field `save` or `load` forgets would still round-trip a bare struct
        // in a test and lose the detail across a real restart.
        let root = Self.temporary("cache-roundtrip")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "agent.json")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_789_372_800)
        let at = calendar.date(
            bySettingHour: 10, minute: 0, second: 0, of: calendar.startOfDay(for: now)
        )!

        // A priced model with distinct rates; a model with no published price;
        // and a priced id whose published name collides with an unrelated
        // unpriced raw id, so one display name is genuinely part-priced.
        let prices: [String: ModelPrice] = [
            "priced": ModelPrice(input: 1_000, output: 2_000, cacheRead: 100, cacheWrite: 500, name: "Priced"),
            "half": ModelPrice(input: 1, output: 0, cacheRead: 0, cacheWrite: 0, name: "ghost"),
        ]
        let buckets: [String: [String: TokenTally]] = [
            UsageLedgerReader.slotKey(for: at): [
                "priced": TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40),
                "mystery": TokenTally(input: 7, output: 3),
                "half": TokenTally(input: 1_000_000),
                "ghost": TokenTally(input: 2_000_000),
            ]
        ]
        let ledger = UsageLedgerReader.price(buckets, with: prices, calendar: calendar)

        let stamp = AgentCache.Stamp(source: "test", prices: AgentCache.priceFingerprint(prices))
        AgentCache.save(ledger, stamp: stamp, for: .openCode, at: url)

        let loaded = try #require(AgentCache.load(.openCode, at: url))
        #expect(loaded.stamp == stamp)

        // The reloaded ledger answers exactly as the original did — totals,
        // per-model categories, hours and money, for every model.
        for name in ["Priced", "mystery", "ghost"] {
            let original = ModelSpendSummary.of(
                [.openCode: ledger], named: name, overLast: nil, now: now, calendar: calendar
            )
            let reloaded = ModelSpendSummary.of(
                [.openCode: loaded.ledger], named: name, overLast: nil, now: now, calendar: calendar
            )
            #expect(original == reloaded)
            #expect(original.tally != nil)
            #expect(original.hours != nil)
        }

        func summary(_ name: String) -> ModelSpendSummary {
            ModelSpendSummary.of(
                [.openCode: loaded.ledger], named: name, overLast: nil, now: now, calendar: calendar
            )
        }

        let priced = summary("Priced")
        #expect(priced.tokens == 190)
        #expect(priced.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40))
        #expect(priced.hours == [10: 190])
        // $0.10 + $0.01 + $0.003 + $0.08.
        #expect(abs((priced.cost ?? -1) - 0.193) < 1e-12)
        #expect(priced.unpricedTokens == 0)

        let mystery = summary("mystery")
        #expect(mystery.tokens == 10)
        #expect(mystery.tally == TokenTally(input: 7, output: 3))
        #expect(mystery.hours == [10: 10])
        #expect(mystery.cost == nil)
        #expect(mystery.unpricedTokens == 10)

        // The partial display name: $1 for the priced id, two million tokens
        // counted and not costed.
        let ghost = summary("ghost")
        #expect(ghost.tokens == 3_000_000)
        #expect(abs((ghost.cost ?? -1) - 1) < 1e-12)
        #expect(ghost.unpricedTokens == 2_000_000)
    }

    @Test("A cache written before per-model money does not decode")
    func theMoneyShapeDoesNotDecode() throws {
        // The `agent-3` shape: per-model tallies and slot models, but no
        // `modelCosts` on the day. If this decoded, every model would read as
        // unpriced instead of being re-priced when the store is read again.
        let old = """
        {"stamp":{"source":"s","prices":"p"},"ledger":{"days":[\
        {"date":0,"tokens":1,"cost":0.1,"unpricedTokens":0,"models":{"m":1},\
        "tally":{"input":1,"cacheWrite":0,"cacheRead":0,"output":0},\
        "modelTallies":{"m":{"input":1,"cacheWrite":0,"cacheRead":0,"output":0}}}],\
        "sessions":[],"unpricedModels":[],"modelNames":{},"slots":[\
        {"start":0,"tokens":1,"cost":0.1,\
        "models":{"m":{"input":1,"cacheWrite":0,"cacheRead":0,"output":0}}}]}}
        """
        var decoded = false
        do {
            _ = try JSONDecoder().decode(AgentCache.Saved.self, from: Data(old.utf8))
            decoded = true
        } catch {}
        #expect(!decoded)
    }

    @Test("A cache written before days and slots kept their models does not decode")
    func theModelDetailShapeDoesNotDecode() throws {
        // The `agent-2` shape: the right stamp, a day with model *totals* and a
        // single day tally, and a slot with nothing per model. If this decoded,
        // the drill-down could not tell a model's categories or hours from
        // "never saved" — so the decode has to fail and the store be read
        // again.
        let old = """
        {"stamp":{"source":"s","prices":"p"},"ledger":{"days":[\
        {"date":0,"tokens":1,"cost":0.1,"unpricedTokens":0,"models":{"m":1},\
        "tally":{"input":1,"cacheWrite":0,"cacheRead":0,"output":0}}],\
        "sessions":[],"unpricedModels":[],"modelNames":{},"slots":[\
        {"start":0,"tokens":1,"cost":0.1}]}}
        """
        var decoded = false
        do {
            _ = try JSONDecoder().decode(AgentCache.Saved.self, from: Data(old.utf8))
            decoded = true
        } catch {}
        #expect(!decoded)
    }

    // MARK: - Multiple roots

    @Test("A root list is ordered and deduplicated, so the same set is the same store")
    func rootListsAreOrderedAndDeduplicated() throws {
        let first = Self.temporary("roots-a")
        let second = Self.temporary("roots-b")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: first) }
        defer { try? FileManager.default.removeItem(at: second) }

        try "{}".write(to: first.appending(path: "one.jsonl"), atomically: true, encoding: .utf8)
        try "{}".write(to: second.appending(path: "two.jsonl"), atomically: true, encoding: .utf8)

        #expect(
            AgentCache.sourceFingerprint(of: [first, second])
                == AgentCache.sourceFingerprint(of: [second, first])
        )
        #expect(
            AgentCache.sourceFingerprint(of: [first, first])
                == AgentCache.sourceFingerprint(of: [first])
        )
        // A different set of roots is a different store.
        #expect(
            AgentCache.sourceFingerprint(of: [first, second])
                != AgentCache.sourceFingerprint(of: [first])
        )
    }

    @Test("Two roots that each hold the same file name are not one store")
    func sameFileNamesInDifferentRootsDiffer() throws {
        let first = Self.temporary("same-a")
        let second = Self.temporary("same-b")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: first) }
        defer { try? FileManager.default.removeItem(at: second) }

        let a = first.appending(path: "opencode.db")
        let b = second.appending(path: "opencode.db")
        try Data([0x01]).write(to: a)
        try Data([0x01]).write(to: b)

        #expect(AgentCache.sourceFingerprint(of: [a]) != AgentCache.sourceFingerprint(of: [b]))
        #expect(AgentCache.sourceFingerprint(of: [a, b]) != AgentCache.sourceFingerprint(of: [a]))
    }

    @Test("A hidden log in a hidden subdirectory is part of a directory store")
    func hiddenLogsArePartOfTheStore() throws {
        let root = Self.temporary("hidden-store")
        let hidden = root.appending(path: ".config/logs")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let log = hidden.appending(path: "capture.jsonl")
        try "{\"n\":1}\n".write(to: log, atomically: true, encoding: .utf8)
        let before = AgentCache.sourceFingerprint(of: root)

        // `skipsHiddenFiles` would have missed this whole tree, so an append
        // inside it would have gone unnoticed forever.
        try Self.append("{\"n\":2}\n", to: log)
        #expect(before != AgentCache.sourceFingerprint(of: root))
    }

    @Test("A directory walk counts a database's WAL but not its shared memory")
    func directoryWalkExcludesSharedMemory() throws {
        let root = Self.temporary("dir-db")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let db = root.appending(path: "sessions.db")
        try Data([0x01]).write(to: db)
        let withoutSidecars = AgentCache.sourceFingerprint(of: root)

        // `-shm` is shared memory that merely opening the store touches, so
        // even inside a directory it must not count.
        try Data([0x02]).write(to: URL(fileURLWithPath: db.path + "-shm"))
        #expect(AgentCache.sourceFingerprint(of: root) == withoutSidecars)

        // A WAL holds what was committed and must count.
        try Data([0x03]).write(to: URL(fileURLWithPath: db.path + "-wal"))
        #expect(AgentCache.sourceFingerprint(of: root) != withoutSidecars)
    }

    @Test("A WAL commit in either root moves the multi-root stamp while the database stands still")
    func multiRootWALCommitIsSeen() throws {
        let first = Self.temporary("multi-a")
        let second = Self.temporary("multi-b")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: first) }
        defer { try? FileManager.default.removeItem(at: second) }

        let db = second.appending(path: "sessions.db")
        var writer: OpaquePointer?
        #expect(sqlite3_open(db.path, &writer) == SQLITE_OK)
        // Left open: *closing* a WAL database checkpoints it into the `.db`,
        // which is exactly the event that would hide the window this covers.
        defer { sqlite3_close(writer) }

        for sql in [
            "PRAGMA journal_mode=WAL;",
            "PRAGMA wal_autocheckpoint=0;",
            "CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT);",
            "INSERT INTO t (v) VALUES ('one');",
        ] {
            #expect(sqlite3_exec(writer, sql, nil, nil, nil) == SQLITE_OK)
        }

        let inputs = [first, second]
        let before = AgentCache.stamp(for: inputs, prices: [:])
        let dbFile = URL(fileURLWithPath: db.path)
        let dbBefore = try dbFile.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        #expect(sqlite3_exec(writer, "INSERT INTO t (v) VALUES ('two');", nil, nil, nil) == SQLITE_OK)

        let dbAfter = try dbFile.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        // The writer is still open: the commit went to the WAL, not the `.db`.
        #expect(dbBefore.fileSize == dbAfter.fileSize)
        #expect(dbBefore.contentModificationDate == dbAfter.contentModificationDate)
        // Which is exactly why one root's WAL has to move the whole stamp.
        #expect(before != AgentCache.stamp(for: inputs, prices: [:]))
    }

    @Test("An empty root is part of the identity, so adding or removing one moves the digest")
    func emptyRootsArePartOfTheIdentity() throws {
        let store = Self.temporary("empty-root-store")
        let empty = Self.temporary("empty-root")
        let other = Self.temporary("empty-root-other")
        for root in [store, empty, other] {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        defer { for root in [store, empty, other] { try? FileManager.default.removeItem(at: root) } }

        let only = AgentCache.sourceFingerprint(of: [store])
        let withEmpty = AgentCache.sourceFingerprint(of: [store, empty])

        // An empty root is still a root: adding it is a different store, and
        // removing it returns the original digest.
        #expect(only != withEmpty)
        #expect(AgentCache.sourceFingerprint(of: [store]) == only)
        // Two different empty roots are not the same store.
        #expect(AgentCache.sourceFingerprint(of: [empty]) != AgentCache.sourceFingerprint(of: [other]))
    }

    @Test("Path aliases of one root are one input")
    func rootAliasesAreNormalized() throws {
        let root = Self.temporary("alias-root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "{}".write(to: root.appending(path: "log.jsonl"), atomically: true, encoding: .utf8)

        // `/a/b` and `/a/b/../b` are the same directory spelled two ways.
        let alias = URL(fileURLWithPath: root.path + "/../" + root.lastPathComponent)
        #expect(AgentCache.sourceFingerprint(of: [root]) == AgentCache.sourceFingerprint(of: [alias]))
        #expect(
            AgentCache.sourceFingerprint(of: [root, alias])
                == AgentCache.sourceFingerprint(of: [root])
        )
    }

    @Test("Origin, aggregate timing and unclassified tokens survive a real cache round-trip")
    func metadataSurvivesSaveAndLoad() throws {
        let root = Self.temporary("cache-metadata")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "agent.json")

        let prices: [String: ModelPrice] = [
            "priced": ModelPrice(
                input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "Priced"
            )
        ]
        // An imported, aggregate record with both classified and unclassified
        // tokens — every new metadata field at once.
        let ledger = AgentUsageLedger.build(
            [AgentUsageRecord(
                timestamp: Date(timeIntervalSince1970: 1_789_372_800),
                model: "priced", tally: TokenTally(input: 100), unclassifiedTokens: 400,
                isAggregate: true
            )],
            prices: prices, namespace: "a", origin: .importedRecords
        )

        let stamp = AgentCache.Stamp(source: "test", prices: AgentCache.priceFingerprint(prices))
        AgentCache.save(ledger, stamp: stamp, for: .openCode, at: url)

        let loaded = try #require(AgentCache.load(.openCode, at: url))
        #expect(loaded.stamp == stamp)
        #expect(loaded.ledger.origin == .importedRecords)
        #expect(loaded.ledger.hasAggregateTiming)
        let day = try #require(loaded.ledger.days.first { $0.tokens > 0 })
        #expect(day.modelUnclassifiedTokens["priced"] == 400)
        #expect(day.modelTallies["priced"] == TokenTally(input: 100))
        // The whole ledger, metadata included, is exactly what was saved.
        #expect(ledger == loaded.ledger)
    }

    @Test("A named-but-unknown-only raw id keeps its name and its not-unpriced note through the cache")
    func unknownOnlyNameSurvivesSaveAndLoad() throws {
        let root = Self.temporary("cache-unknown-name")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "agent.json")

        let prices: [String: ModelPrice] = [
            "gpt-5": ModelPrice(
                input: 1_000, output: 10_000, cacheRead: nil, cacheWrite: nil, name: "GPT-5"
            )
        ]
        let ledger = AgentUsageLedger.build(
            [AgentUsageRecord(
                timestamp: Date(timeIntervalSince1970: 1_789_372_800),
                model: "gpt-5", tally: TokenTally(), unclassifiedTokens: 900
            )],
            prices: prices, namespace: "a"
        )
        // The raw id took its published name without being priced, and is not
        // listed as having no public price.
        #expect(ledger.modelNames["gpt-5"] == "GPT-5")
        #expect(ledger.unpricedModels.isEmpty)

        let stamp = AgentCache.Stamp(source: "test", prices: AgentCache.priceFingerprint(prices))
        AgentCache.save(ledger, stamp: stamp, for: .openCode, at: url)
        let loaded = try #require(AgentCache.load(.openCode, at: url))

        // Neither the name nor the "priced, just unclassified" note is lost:
        // `modelNames` must survive alongside the newer session-day metadata.
        #expect(loaded.ledger == ledger)
        #expect(loaded.ledger.modelNames["gpt-5"] == "GPT-5")
        #expect(loaded.ledger.unpricedModels.isEmpty)
    }

    @Test("The partial-counts flag survives a real save and load")
    func partialFlagSurvivesSaveAndLoad() throws {
        let root = Self.temporary("cache-partial")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "agent.json")

        let prices: [String: ModelPrice] = [
            "priced": ModelPrice(
                input: 1_000, output: 10_000, cacheRead: nil, cacheWrite: nil, name: "Priced"
            )
        ]
        let ledger = AgentUsageLedger.build(
            [AgentUsageRecord(
                timestamp: Date(timeIntervalSince1970: 1_789_372_800),
                model: "priced", tally: TokenTally(input: 100), isPartial: true
            )],
            prices: prices, namespace: "a"
        )
        #expect(ledger.hasPartialCounts)

        let stamp = AgentCache.Stamp(source: "test", prices: AgentCache.priceFingerprint(prices))
        AgentCache.save(ledger, stamp: stamp, for: .openCode, at: url)
        let loaded = try #require(AgentCache.load(.openCode, at: url))

        // A cache that dropped the flag would present a possibly short total as
        // complete on the next launch.
        #expect(loaded.ledger.hasPartialCounts)
        #expect(loaded.ledger == ledger)
    }
}
