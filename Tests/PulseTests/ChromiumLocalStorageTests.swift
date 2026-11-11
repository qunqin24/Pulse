import Foundation
import Testing
@testable import Pulse

/// The LevelDB reader, which is the one piece of Pulse that parses somebody
/// else's binary format rather than their JSON.
///
/// A real browser profile cannot be committed — it is somebody's storage, and
/// it is thirty megabytes — so the store here is built by hand in the format
/// Chromium writes: a log file of `WriteBatch` records, keys shaped
/// `_<origin>\0<encoded name>`, values carrying their own encoding byte.
@Suite("Chromium localStorage")
struct ChromiumLocalStorageTests {
    // MARK: - Building a store

    /// One log record: four bytes of checksum this reader does not verify, the
    /// payload length, and the fragment type — 1 being "a whole record".
    private static func record(_ payload: [UInt8], type: UInt8 = 1) -> [UInt8] {
        var bytes: [UInt8] = [0, 0, 0, 0]
        bytes.append(UInt8(payload.count & 0xff))
        bytes.append(UInt8((payload.count >> 8) & 0xff))
        bytes.append(type)
        return bytes + payload
    }

    /// A batch: the sequence the first record gets, the number of records, and
    /// then each one as a kind byte and length-prefixed strings.
    private static func batch(sequence: UInt64, _ entries: [(key: [UInt8], value: [UInt8]?)]) -> [UInt8] {
        var bytes: [UInt8] = []
        for shift in 0..<8 { bytes.append(UInt8((sequence >> (8 * UInt64(shift))) & 0xff)) }
        let count = UInt32(entries.count)
        for shift in 0..<4 { bytes.append(UInt8((count >> (8 * UInt32(shift))) & 0xff)) }

        for entry in entries {
            bytes.append(entry.value == nil ? 0 : 1)
            bytes += varint(entry.key.count) + entry.key
            if let value = entry.value { bytes += varint(value.count) + value }
        }
        return bytes
    }

    private static func varint(_ value: Int) -> [UInt8] {
        var remaining = UInt64(value)
        var bytes: [UInt8] = []
        while remaining >= 0x80 {
            bytes.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        bytes.append(UInt8(remaining))
        return bytes
    }

    /// Chromium's own key shape. The `1` is "one byte per character"; a `0`
    /// there would mean UTF-16.
    private static func key(origin: String, name: String) -> [UInt8] {
        Array("_\(origin)".utf8) + [0, 1] + Array(name.utf8)
    }

    private static func value(_ text: String) -> [UInt8] { [1] + Array(text.utf8) }

    private static func store(_ log: [UInt8]) throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "leveldb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(log).write(to: directory.appending(path: "000003.log"))
        return directory
    }

    // MARK: - Building a table, and lengths that do not fit

    /// The bytes of a varint, for values that do not fit an `Int`.
    private static func varint64(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var bytes: [UInt8] = []
        while remaining >= 0x80 {
            bytes.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        bytes.append(UInt8(remaining))
        return bytes
    }

    /// A batch's eight-byte sequence and four-byte count, so a record can be
    /// assembled by hand around a length nobody would ever write.
    private static func sequenceAndCount(_ count: UInt32, sequence: UInt64 = 1) -> [UInt8] {
        var bytes: [UInt8] = []
        for shift in 0..<8 { bytes.append(UInt8((sequence >> (8 * UInt64(shift))) & 0xff)) }
        for shift in 0..<4 { bytes.append(UInt8((count >> (8 * UInt32(shift))) & 0xff)) }
        return bytes
    }

    /// A data block's contents in LevelDB's prefix-compressed form: the first
    /// key whole, the rest as "how many leading bytes are shared, then the new
    /// bytes", then a single restart point. The reader needs only the restart
    /// count to find where the entries stop, so one restart is enough.
    private static func rawBlock(_ entries: [(key: [UInt8], value: [UInt8])]) -> [UInt8] {
        var bytes: [UInt8] = []
        var previous: [UInt8] = []
        for (key, value) in entries {
            var shared = 0
            while shared < previous.count, shared < key.count, previous[shared] == key[shared] { shared += 1 }
            bytes += varint(shared)
            bytes += varint(key.count - shared)
            bytes += varint(value.count)
            bytes += Array(key[shared...])
            bytes += value
            previous = key
        }
        bytes += [0, 0, 0, 0]   // restart point at offset zero
        bytes += [1, 0, 0, 0]   // one restart
        return bytes
    }

    /// A table's key as stored: the user key, then the eight-byte trailer
    /// carrying the sequence and the kind (1 is a value, 0 a deletion).
    private static func internalKey(_ key: [UInt8], sequence: UInt64 = 1, kind: UInt8 = 1) -> [UInt8] {
        var bytes = key
        let trailer = (sequence << 8) | UInt64(kind)
        for shift in 0..<8 { bytes.append(UInt8((trailer >> (8 * UInt64(shift))) & 0xff)) }
        return bytes
    }

    private static let tableMagic: [UInt8] = [0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb]

    /// A footer of exactly the 48 bytes a table ends with: the metaindex
    /// handle (unused), the index handle, padding, and the magic.
    private static func tableFooter(indexOffset: [UInt8], indexSize: [UInt8]) -> [UInt8] {
        var bytes = varint(0) + varint(0) + indexOffset + indexSize
        bytes += [UInt8](repeating: 0, count: 40 - bytes.count)
        bytes += tableMagic
        return bytes
    }

    /// A whole table: each data block as given, an index block naming every
    /// one, and the footer.
    private static func tableFile(_ blocks: [[(key: [UInt8], value: [UInt8])]]) -> Data {
        var file: [UInt8] = []
        var indexEntries: [(key: [UInt8], value: [UInt8])] = []
        for block in blocks {
            let contents = rawBlock(block)
            let offset = file.count
            file += contents
            file += [0, 0, 0, 0, 0]   // uncompressed, plus a checksum Pulse ignores
            indexEntries.append((block.last!.key, varint(offset) + varint(contents.count)))
        }
        let index = rawBlock(indexEntries)
        let indexOffset = file.count
        file += index
        file += [0, 0, 0, 0, 0]
        file += tableFooter(indexOffset: varint(indexOffset), indexSize: varint(index.count))
        return Data(file)
    }

    /// A table whose index block carries one entry with the given raw handle
    /// value — used to hand the reader a data handle it must refuse.
    private static func tableWithIndexHandle(_ handle: [UInt8]) -> Data {
        let index = rawBlock([(internalKey(Array("_https://a.test\0z".utf8)), handle)])
        var file = index
        file += [0, 0, 0, 0, 0]
        file += tableFooter(indexOffset: varint(0), indexSize: varint(index.count))
        return Data(file)
    }

    /// A table whose one data block is the given bytes, so a malformed entry
    /// can be handed straight to the item parser.
    private static func tableWithDataBlock(_ dataBlock: [UInt8]) -> Data {
        var file = dataBlock + [0, 0, 0, 0, 0]
        let handle = varint(0) + varint(dataBlock.count)
        let index = rawBlock([(internalKey(Array("_https://a.test\0z".utf8)), handle)])
        let indexOffset = file.count
        file += index
        file += [0, 0, 0, 0, 0]
        file += tableFooter(indexOffset: varint(indexOffset), indexSize: varint(index.count))
        return Data(file)
    }

    // MARK: - The log

    @Test("One origin's entries, and nobody else's")
    func readsOneOrigin() throws {
        let log = Self.record(Self.batch(sequence: 1, [
            (Self.key(origin: "https://app.devin.ai", name: "auth1_session"), Self.value("{\"token\":\"auth1_x\"}")),
            (Self.key(origin: "https://elsewhere.test", name: "auth1_session"), Self.value("not ours")),
            (Array("META:https://app.devin.ai".utf8), Self.value("bookkeeping")),
        ]))

        let directory = try Self.store(log)
        defer { try? FileManager.default.removeItem(at: directory) }

        let values = ChromiumLocalStorage.entries(origin: "https://app.devin.ai", in: directory)
        // The `META:` row is the area's own bookkeeping, not a script key, and
        // another site's storage is not this site's.
        #expect(values == ["auth1_session": "{\"token\":\"auth1_x\"}"])
    }

    @Test("The later write wins, and a deletion is a write")
    func sequenceDecides() throws {
        var log = Self.record(Self.batch(sequence: 10, [
            (Self.key(origin: "https://a.test", name: "token"), Self.value("old")),
            (Self.key(origin: "https://a.test", name: "gone"), Self.value("here")),
        ]))
        log += Self.record(Self.batch(sequence: 20, [
            (Self.key(origin: "https://a.test", name: "token"), Self.value("new")),
            // A deletion carries no value and has to beat the write it cancels
            // rather than being ignored as "nothing to read".
            (Self.key(origin: "https://a.test", name: "gone"), nil),
        ]))

        let directory = try Self.store(log)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(ChromiumLocalStorage.entries(origin: "https://a.test", in: directory) == ["token": "new"])
    }

    @Test("A record split across blocks is put back together")
    func fragmentsAreReassembled() throws {
        // Long enough that the record cannot sit inside one 32KB block, which
        // is the case the fragment types exist for.
        let long = String(repeating: "x", count: 40_000)
        let payload = Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "big"), Self.value(long)),
        ])

        // Chromium fills to the block boundary and continues in the next one.
        let firstRoom = 32_768 - 7
        var log = Self.record(Array(payload.prefix(firstRoom)), type: 2)
        log += Self.record(Array(payload.dropFirst(firstRoom)), type: 4)

        let directory = try Self.store(log)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(ChromiumLocalStorage.entries(origin: "https://a.test", in: directory)["big"]?.count == 40_000)
    }

    @Test("Padding at the end of a block is not read as a record")
    func paddingIsSkipped() throws {
        var log = Self.record(Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "first"), Self.value("1")),
        ]))
        // Fewer than seven bytes left in a block cannot hold a header, so
        // Chromium leaves them zeroed and starts the next block.
        log += [UInt8](repeating: 0, count: 32_768 - log.count)
        log += Self.record(Self.batch(sequence: 2, [
            (Self.key(origin: "https://a.test", name: "second"), Self.value("2")),
        ]))

        let directory = try Self.store(log)
        defer { try? FileManager.default.removeItem(at: directory) }

        let values = ChromiumLocalStorage.entries(origin: "https://a.test", in: directory)
        #expect(values == ["first": "1", "second": "2"])
    }

    // MARK: - How text is stored

    @Test("One byte per character, or UTF-16")
    func bothEncodingsAreRead() {
        #expect(ChromiumLocalStorage.text([1] + Array("plain".utf8)) == "plain")
        #expect(ChromiumLocalStorage.text([0, 0x4B, 0x00, 0x7D, 0x59]) == "K好")

        // An odd number of bytes is not UTF-16, and decoding it anyway drops
        // the last one — a value half-read is worse than one not read.
        #expect(ChromiumLocalStorage.text([0, 0x4B]) == nil)
        #expect(ChromiumLocalStorage.text([]) == nil)
        // A marker this reader does not know is a format that has moved on.
        #expect(ChromiumLocalStorage.text([9, 0x41]) == nil)
    }

    // MARK: - Skipping what cannot match

    @Test("The end of a prefix's range")
    func upperBoundIsTheNextKey() {
        #expect(LevelDB.upperBound([0x61, 0x62]) == [0x61, 0x63])
        // A trailing 0xff has no successor of its own, so the carry moves left.
        #expect(LevelDB.upperBound([0x61, 0xff]) == [0x62])
        // Nothing but 0xff has no upper bound at all: everything sorts below.
        #expect(LevelDB.upperBound([0xff, 0xff]) == nil)
    }

    @Test("Varints stop, even when the bytes do not")
    func varintsAreBounded() {
        var offset = 0
        #expect(LevelDB.varint([0xac, 0x02], &offset) == 300)
        #expect(offset == 2)

        // Without a cap a run of continuation bytes walks the whole file.
        var runaway = 0
        #expect(LevelDB.varint([UInt8](repeating: 0xff, count: 32), &runaway) == nil)
    }

    // MARK: - Snappy

    @Test("A literal, then a copy that overlaps itself")
    func snappyRepeatsARun() {
        // Eight bytes out: one literal 'a', then a copy of seven reaching back
        // one — which is the format's way of saying "repeat that". The source
        // has to include what the copy is still writing.
        let compressed: [UInt8] = [0x08, 0x00, 0x61, 0x0d, 0x01]
        #expect(Snappy.decompress(compressed).map { String(decoding: $0, as: UTF8.self) } == "aaaaaaaa")
    }

    @Test("A literal long enough to need its own length")
    func snappyReadsLongLiterals() {
        let text = String(repeating: "ab", count: 40)
        var compressed = [UInt8(text.utf8.count)]
        // Sixty and above, the tag says how many bytes the length takes rather
        // than carrying it.
        compressed += [60 << 2, UInt8(text.utf8.count - 1)]
        compressed += Array(text.utf8)

        #expect(Snappy.decompress(compressed).map { String(decoding: $0, as: UTF8.self) } == text)
    }

    @Test("A stream that promises more than it delivers is refused")
    func snappyRefusesShortOutput() {
        // Says ten bytes, produces one. Returning the one would hand a caller
        // half a block and let it parse the remains as entries.
        #expect(Snappy.decompress([0x0a, 0x00, 0x61]) == nil)
        // A copy reaching back further than anything written.
        #expect(Snappy.decompress([0x04, 0x0d, 0x01]) == nil)
    }

    // MARK: - Malformed input the parser must refuse rather than trap

    @Test("A varint may not overflow 64 bits")
    func varintsRejectOverflow() {
        var offset = 0
        // Ten bytes, the tenth carrying more than the one bit a UInt64 has
        // left. Shifting it anyway would silently read a small, wrong number.
        #expect(LevelDB.varint([UInt8](repeating: 0xff, count: 9) + [0x7f], &offset) == nil)

        // The largest value that does fit still decodes.
        var maxOffset = 0
        #expect(LevelDB.varint([UInt8](repeating: 0xff, count: 9) + [0x01], &maxOffset) == UInt64.max)
    }

    @Test("A WriteBatch length that cannot be an Int is refused, not trapped")
    func malformedBatchLengthsDoNotTrap() {
        let origin = "_https://a.test\0token"

        // A key length of UInt64.max, then a plausible key. The old reader
        // trapped converting this to Int before it ever compared ranges.
        var payload = Self.sequenceAndCount(1)
        payload += [1] + Self.varint64(UInt64.max) + Array(origin.utf8) + [1, 0x41]
        #expect(LevelDB.log(Self.record(payload)).isEmpty)

        // Int.max fits the conversion but not the bytes that remain.
        payload = Self.sequenceAndCount(1)
        payload += [1] + Self.varint64(UInt64(Int.max)) + Array(origin.utf8) + [1, 0x41]
        #expect(LevelDB.log(Self.record(payload)).isEmpty)

        // A value length the same way, past a key that did parse.
        payload = Self.sequenceAndCount(1)
        payload += [1] + Self.varint(origin.utf8.count) + Array(origin.utf8)
        payload += Self.varint64(UInt64(Int.max)) + [0x41]
        #expect(LevelDB.log(Self.record(payload)).isEmpty)

        // A varint that never ends is not a length either.
        payload = Self.sequenceAndCount(1)
        payload += [1] + [UInt8](repeating: 0xff, count: 11) + [1, 0x41]
        #expect(LevelDB.log(Self.record(payload)).isEmpty)
    }

    @Test("A truncated WriteBatch is dropped whole")
    func truncatedBatchIsNotHalfRead() {
        var payload = Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "token"), Self.value("secret")),
        ])
        // The count says two records; the payload carries one. The first one
        // parsing cleanly must not make it a credential on its own.
        payload[8] = 2
        #expect(LevelDB.log(Self.record(payload)).isEmpty)
    }

    @Test("A WriteBatch whose count undercounts its records is refused")
    func batchCountMustMatchPayload() {
        var payload = Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "one"), Self.value("1")),
            (Self.key(origin: "https://a.test", name: "two"), Self.value("2")),
        ])
        // The count says one; the payload carries two. Ignoring the tail would
        // accept a write whose remainder is truncated or repurposed.
        payload[8] = 1
        #expect(LevelDB.log(Self.record(payload)).isEmpty)
    }

    @Test("An orphaned or unfinished fragment is not a record")
    func fragmentStateIsRefused() {
        let payload = Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "token"), Self.value("secret")),
        ])
        // A middle with no beginning, then an end with no beginning.
        #expect(LevelDB.log(Self.record(payload, type: 3) + Self.record(payload, type: 4)).isEmpty)
        // A beginning that never ends is a half-write and is not emitted.
        #expect(LevelDB.log(Self.record(payload, type: 2)).isEmpty)
    }

    @Test("A whole record discards a fragment chain that never ended")
    func fullRecordDiscardsPending() {
        let chain = Self.record(Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "half"), Self.value("secret")),
        ]), type: 2)
        let whole = Self.record(Self.batch(sequence: 2, [
            (Self.key(origin: "https://a.test", name: "whole"), Self.value("real")),
        ]))
        let entries = LevelDB.log(chain + whole)
        // The raw key still carries Chromium's encoding byte; compare the bytes
        // the store was built with rather than re-interpreting the key here.
        #expect(entries.map(\.key) == [Self.key(origin: "https://a.test", name: "whole")])
    }

    @Test("A middle fragment is joined to its beginning")
    func middleFragmentIsJoined() {
        let payload = Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "split"), Self.value("value")),
        ])
        let third = payload.count / 3
        let log = Self.record(Array(payload.prefix(third)), type: 2)
            + Self.record(Array(payload[third..<(third * 2)]), type: 3)
            + Self.record(Array(payload[(third * 2)...]), type: 4)
        #expect(LevelDB.log(log).map(\.key) == [Self.key(origin: "https://a.test", name: "split")])
    }

    @Test("A zero-length first fragment begins a chain the next block ends")
    func zeroLengthFirstFragmentIsAChain() {
        // Fill block zero to its last seven bytes, so the next header is
        // exactly the block's tail and its payload has no room at all: Chromium
        // writes a zero-length FIRST there and the batch in the next block.
        let filler = Self.record(Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "pad"), Self.value(String(repeating: "x", count: 32_716))),
        ]))
        #expect(filler.count == 32_761)

        let target = Self.batch(sequence: 2, [
            (Self.key(origin: "https://a.test", name: "token"), Self.value("secret")),
        ])
        var log = filler
        log += [0, 0, 0, 0, 0, 0, 2]        // zero-length FIRST in block zero
        log += Self.record(target, type: 4) // its LAST and payload, in block one

        #expect(LevelDB.log(log).map(\.key) == [
            Self.key(origin: "https://a.test", name: "pad"),
            Self.key(origin: "https://a.test", name: "token"),
        ])
    }

    @Test("A record that claims to cross a 32KB block is not followed")
    func logRecordMayNotCrossBlock() {
        // One more than a block can hold after its seven-byte header: 32762.
        let victim = Self.record(Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "later"), Self.value("real")),
        ]))
        var log: [UInt8] = [0, 0, 0, 0, 0xfa, 0x7f, 1]
        log += [UInt8](repeating: 0x41, count: 32_762)
        log += victim
        // If the crossing header were followed it would land exactly on the
        // real record and return it. Refusing the crossing yields nothing.
        #expect(LevelDB.log(log).isEmpty)
    }

    @Test("A log record whose length runs past the file is refused")
    func truncatedLogRecordIsRefused() {
        var log: [UInt8] = [0, 0, 0, 0, 100, 0, 1]
        log += [UInt8](repeating: 0x41, count: 10)
        #expect(LevelDB.log(log).isEmpty)
    }

    // MARK: - The table, and what it must not walk into

    @Test("A table reads through its index and rebuilds shared prefixes")
    func tableReadsThroughTheIndex() {
        let data = Self.tableFile([[
            (Self.internalKey(Array("_https://a.test\0bar".utf8)), Array("one".utf8)),
            (Self.internalKey(Array("_https://a.test\0foo".utf8)), Array("two".utf8)),
            (Self.internalKey(Array("_https://b.test\0token".utf8)), Array("three".utf8)),
        ]])
        let entries = LevelDB.table(data)
        #expect(entries.map { String(decoding: $0.key, as: UTF8.self) } == [
            "_https://a.test\u{0}bar", "_https://a.test\u{0}foo", "_https://b.test\u{0}token",
        ])
        #expect(entries.map { String(decoding: $0.value ?? [], as: UTF8.self) } == ["one", "two", "three"])
    }

    @Test("The prefix never reads a block whose separator sorts below it")
    func prefixSkipsBlocks() {
        let data = Self.tableFile([
            [(Self.internalKey(Array("_https://a.test\0token".utf8)), Array("a".utf8))],
            [(Self.internalKey(Array("_https://z.test\0token".utf8)), Array("z".utf8))],
        ])
        let entries = LevelDB.table(data, keyPrefix: Array("_https://z.test\0".utf8))
        #expect(entries.map { String(decoding: $0.key, as: UTF8.self) } == ["_https://z.test\u{0}token"])
    }

    @Test("A file too short for a footer, or with the wrong magic, is not a table")
    func badFooterIsRefused() {
        #expect(LevelDB.table(Data()).isEmpty)
        #expect(LevelDB.table(Data(repeating: 0, count: 47)).isEmpty)

        var wrong = Self.varint(0) + Self.varint(0) + Self.varint(0) + Self.varint(0)
        wrong += [UInt8](repeating: 0, count: 40 - wrong.count)
        wrong += [0, 1, 2, 3, 4, 5, 6, 7]
        #expect(LevelDB.table(Data(wrong)).isEmpty)
    }

    @Test("An index handle that cannot be an Int is refused, not trapped")
    func indexHandleOverflowsInt() {
        #expect(LevelDB.table(Data(Self.tableFooter(
            indexOffset: Self.varint64(UInt64.max), indexSize: Self.varint(20)))).isEmpty)
        #expect(LevelDB.table(Data(Self.tableFooter(
            indexOffset: Self.varint(0), indexSize: Self.varint64(UInt64.max)))).isEmpty)

        // A varint that never ends is not a handle either.
        let runaway = [UInt8](repeating: 0xff, count: 10) + [0x01]
        #expect(LevelDB.table(Data(Self.tableFooter(
            indexOffset: runaway, indexSize: Self.varint(20)))).isEmpty)
    }

    @Test("A data handle that points outside the file is refused")
    func dataHandleOutOfRange() {
        // Offsets that do not fit an Int at all.
        #expect(LevelDB.table(Self.tableWithIndexHandle(Self.varint64(UInt64.max) + Self.varint(4))).isEmpty)
        #expect(LevelDB.table(Self.tableWithIndexHandle(Self.varint(0) + Self.varint64(UInt64.max))).isEmpty)

        // Both fit an Int but the range still lands past the file; the old
        // `offset + size + 5` sum would have overflowed for these.
        let nearMax = Self.varint64(UInt64(Int.max))
        #expect(LevelDB.table(Self.tableWithIndexHandle(nearMax + nearMax)).isEmpty)
    }

    @Test("A data block whose entry lengths do not fit is dropped whole")
    func malformedItemsDoNotTrap() {
        // An unshared count past UInt64's Int range.
        var block = Self.varint(0) + Self.varint64(UInt64.max)
        block += [0, 0, 0, 0, 1, 0, 0, 0]
        #expect(LevelDB.table(Self.tableWithDataBlock(block)).isEmpty)

        // A value length the same way, after a key that did parse.
        block = Self.varint(0) + Self.varint(2) + Self.varint64(UInt64.max)
        block += Array("ab".utf8) + [0, 0, 0, 0, 1, 0, 0, 0]
        #expect(LevelDB.table(Self.tableWithDataBlock(block)).isEmpty)

        // A shared count that fits an Int but claims more than was rebuilt.
        block = Self.varint64(UInt64(Int.max)) + Self.varint(2) + Self.varint(1)
        block += Array("ab".utf8) + [1, 0, 0, 0, 1, 0, 0, 0]
        #expect(LevelDB.table(Self.tableWithDataBlock(block)).isEmpty)
    }

    @Test("A value that would borrow the restart array is refused")
    func itemValueMayNotUseTheRestartArray() {
        // A whole key, then a value length that runs past the entries into the
        // restart array. Bounding against the block's length rather than the
        // entries' would read the array as value bytes and accept the record.
        var block = Self.varint(0) + Self.varint(2) + Self.varint(6)
        block += Array("ab".utf8) + Array("XY".utf8)
        block += [0, 0, 0, 0, 1, 0, 0, 0]
        #expect(LevelDB.table(Self.tableWithDataBlock(block)).isEmpty)
    }

    // MARK: - The browser catalogue

    @Test("Default browser offers this Mac's default and nothing else, and nothing when it can't be read")
    func defaultBrowserOnly() {
        #expect(BrowserCookies.defaultOnly(among: []).isEmpty)
        let all = BrowserCookies.Browser.allCases
        let chosen = BrowserCookies.defaultOnly(among: all)
        #expect(chosen.count <= 1)
        #expect(chosen == BrowserCookies.preferred().map { [$0] } ?? [])
        if let only = chosen.first {
            #expect(BrowserCookies.defaultOnly(among: all.filter { $0 != only }).isEmpty)
        }
    }

    @Test("ego lite is a Chromium store like any other, under its own names")
    func egoLiteIsCatalogued() throws {
        let browser = try #require(BrowserCookies.Browser(rawValue: "egoLite"))
        #expect(browser == .egoLite)

        // The product's own lowercase spellings: the display name and the
        // keychain service are not built from each other. Measured 2026-11-09
        // on ego lite 0.6.2.9.
        #expect(browser.name == "ego lite")
        #expect(browser.keychainService == "ego safe storage")
        #expect(browser.promptsForKeychain)

        let root = try #require(BrowserCookies.chromiumRoot(.egoLite))
        #expect(root.path.hasSuffix("Library/Application Support/Citro Labs/ego lite"))
    }
}
