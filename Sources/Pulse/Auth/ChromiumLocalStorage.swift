// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Reading one site's `localStorage` out of a Chromium browser.
///
/// **This is not `BrowserCookies` with a different table name.** Cookies live
/// in SQLite and their values are encrypted with a key from the login
/// keychain; `localStorage` lives in a LevelDB and is not encrypted at all. So
/// this route asks for no keychain access and raises no "Pulse wants to use
/// your confidential information" prompt — it only needs to be able to read
/// the files, which are the user's own.
///
/// It exists because Devin's session token is kept there and nowhere else. The
/// four values its API needs are in the browser's `localStorage` for
/// `https://app.devin.ai`; the desktop app does not carry them (checked), and
/// the alternative was asking people to paste a token out of developer tools.
///
/// ## What a LevelDB actually is
///
/// A directory of immutable sorted files plus an append-only log:
///
/// - **`*.log`** — the write-ahead log, holding everything not yet compacted.
///   Uncompressed, framed into 32KB blocks, each record a `WriteBatch`.
/// - **`*.ldb`** — sorted string tables, written once and never edited. Each
///   is a series of blocks, usually Snappy-compressed, with an index block at
///   the end saying where each one starts.
///
/// Every entry carries a **sequence number**, and a key written twice appears
/// twice with the later sequence winning. A deletion is an entry too. So the
/// read here is: collect every entry from every file, keep the highest
/// sequence per key, and drop the ones that turned out to be deletions.
///
/// **The `MANIFEST` is deliberately not read.** It is the file that says which
/// tables are live, and skipping it means an obsolete table left behind by a
/// compaction is read as well. Sequence numbers already settle that — an old
/// table's entries lose to the log's — and a manifest parser is a second
/// format to get wrong for a case the ordering already handles.
///
/// **CRCs are not checked.** Bounds checks reject malformed framing and
/// lengths; the origin filter restricts which keys may be returned. These
/// checks are not a checksum validation of the record's contents.
///
/// **The browser is not asked to stop.** LevelDB files are append-only or
/// immutable, so reading one under a running browser gets a consistent
/// prefix — the same reason `BrowserCookies` opens a cookie store in place
/// rather than copying it aside. The `LOCK` file is left alone; taking it
/// would mean asking Chrome to close.
enum ChromiumLocalStorage {
    /// One browser's answer, so the UI can say where the session came from.
    struct Found: Sendable {
        let browser: BrowserCookies.Browser
        let values: [String: String]
    }

    /// The first browser that has anything for this origin, **the default one
    /// first** — the same rule `BrowserCookies.present` follows and for the
    /// same reason: the browser the user opens links with is where they are
    /// actually signed in.
    ///
    /// `accept` decides what counts as "anything", because a site can leave a
    /// `localStorage` entry behind long after the session in it went stale;
    /// finding that and stopping would hide a good session in the next
    /// browser along.
    static func find(
        origin: String,
        in browsers: [BrowserCookies.Browser] = present(),
        accept: ([String: String]) -> Bool = { !$0.isEmpty }
    ) -> Found? {
        for browser in browsers {
            for store in stores(browser) {
                let values = entries(origin: origin, in: store)
                if accept(values) { return Found(browser: browser, values: values) }
            }
        }
        return nil
    }

    /// Chromium browsers with a `localStorage` directory, default first.
    /// Firefox and Safari are **not** here: neither keeps `localStorage` in a
    /// LevelDB, so offering them would be a choice that cannot work.
    static func present(_ browsers: [BrowserCookies.Browser] = BrowserCookies.Browser.allCases) -> [BrowserCookies.Browser] {
        let installed = browsers.filter { !stores($0).isEmpty }
        guard let preferred = BrowserCookies.preferred(), installed.contains(preferred) else { return installed }
        return [preferred] + installed.filter { $0 != preferred }
    }

    /// Every profile's store, for every browser that has one. A person signed
    /// in under "Profile 2" is not an edge case.
    static func stores(_ browser: BrowserCookies.Browser) -> [URL] {
        guard let root = BrowserCookies.chromiumRoot(browser) else { return [] }

        let profiles = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ") }

        return profiles
            .map { $0.appending(path: "Local Storage/leveldb") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - One origin's entries

    /// Chromium's own layout: a value's key is `_`, the origin, a zero byte,
    /// and then the script's key — with both the key and the value carrying a
    /// leading byte saying how the text was encoded. `META:<origin>` rows are
    /// the area's bookkeeping and are not script keys, so the zero byte is
    /// what tells the two apart rather than a second prefix test.
    static func entries(origin: String, in leveldb: URL) -> [String: String] {
        var prefix = Array("_\(origin)".utf8)
        prefix.append(0)

        var newest: [String: (sequence: UInt64, value: String?)] = [:]
        for entry in LevelDB.entries(in: leveldb, keyPrefix: prefix) {
            guard entry.key.count > prefix.count, Array(entry.key.prefix(prefix.count)) == prefix,
                  let name = text(Array(entry.key.dropFirst(prefix.count)))
            else { continue }

            if let existing = newest[name], existing.sequence > entry.sequence { continue }
            newest[name] = (entry.sequence, entry.value.flatMap(text))
        }

        return newest.compactMapValues(\.value)
    }

    /// Chromium stores a string as one byte saying which encoding, then the
    /// bytes: `1` is one byte per character, `0` is UTF-16 little-endian.
    ///
    /// An odd byte count under `0` is not a UTF-16 string, and `String(
    /// decoding:as: UTF16.self)` on one silently drops the last byte; a value
    /// half-read is worse than one not read at all, so it is refused.
    static func text(_ bytes: [UInt8]) -> String? {
        guard let marker = bytes.first else { return nil }
        let body = Array(bytes.dropFirst())

        switch marker {
        case 1:
            return String(decoding: body, as: UTF8.self)
        case 0:
            guard body.count.isMultiple(of: 2) else { return nil }
            var units: [UInt16] = []
            units.reserveCapacity(body.count / 2)
            for index in stride(from: 0, to: body.count, by: 2) {
                units.append(UInt16(body[index]) | (UInt16(body[index + 1]) << 8))
            }
            return String(decoding: units, as: UTF16.self)
        default:
            return nil
        }
    }
}

// MARK: - The store itself

/// A read-only LevelDB, enough of one to answer "what is in here".
///
/// No iterator, no seek, no compaction, nothing written. Every entry in every
/// file is decoded and handed back with its sequence number, and the caller
/// keeps what it wants — for a browser profile's `localStorage` that is a few
/// megabytes, read once when somebody presses a button in Settings.
enum LevelDB {
    struct Entry: Sendable {
        let key: [UInt8]
        /// Nil for a deletion, which is an entry like any other and has to
        /// beat the earlier write it cancels.
        let value: [UInt8]?
        let sequence: UInt64
    }

    /// Everything in the store, or — given a prefix — only what could start
    /// with it.
    ///
    /// **The prefix is not a filter applied afterwards.** A browser profile's
    /// `localStorage` is tens of megabytes across hundreds of sorted tables,
    /// and decompressing all of it to keep one site's dozen keys took 7.4
    /// seconds here, which is not something a refresh pass can do. Keys are
    /// sorted and each table's index says the last key in every block, so the
    /// blocks that cannot hold the prefix are never read at all.
    static func entries(in directory: URL, keyPrefix: [UInt8]? = nil) -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

        var entries: [Entry] = []
        for file in files {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            switch file.pathExtension {
            // The log is uncompressed and holds only what has not been
            // compacted yet, so it is read whole and sieved by the caller.
            case "log": entries += log(Array(data), keyPrefix: keyPrefix)
            case "ldb", "sst": entries += table(data, keyPrefix: keyPrefix)
            default: continue
            }
        }
        return entries
    }

    // MARK: - The write-ahead log

    private static let blockSize = 32_768
    /// 4 bytes of checksum, 2 of length, 1 of type.
    private static let headerSize = 7

    /// Records are framed into fixed blocks and a long one is split across
    /// them, so the payload is reassembled before it is read as a batch.
    ///
    /// Fragment types: 1 is a whole record, 2 starts one, 3 continues it, 4
    /// ends it. A zero-type header is the padding at the end of a block.
    static func log(_ bytes: [UInt8], keyPrefix: [UInt8]? = nil) -> [Entry] {
        var entries: [Entry] = []
        // Nil is "no chain has begun"; an empty array is "a first fragment
        // began with no bytes". The two are not the same — see case 2 below.
        var pending: [UInt8]?
        var offset = 0

        // `offset` can step past the end when a tail of a block is padding, so
        // the bound is written as a subtraction: `offset + headerSize` would
        // overflow for an offset an enormous file could plausibly reach.
        while offset <= bytes.count, bytes.count - offset >= headerSize {
            // Fewer than seven bytes left in this block is padding by
            // definition — there is no room for another header.
            let room = blockSize - (offset % blockSize)
            if room < headerSize {
                offset += room
                continue
            }

            let length = Int(bytes[offset + 4]) | (Int(bytes[offset + 5]) << 8)
            let type = bytes[offset + 6]
            let start = offset + headerSize

            // A zeroed header is the rest of the block left empty, which
            // happens whenever the next record would not fit. **Skip to the
            // next block, do not stop**: reading it as the end of the file
            // dropped everything written after the first padded block, which
            // in a live profile is most of the log.
            if type == 0 {
                offset += room
                continue
            }

            // **A record never crosses a 32KB block.** A length that reaches
            // past the block's end is a header read at the wrong place, and
            // following it would frame the rest of the file against a bad
            // offset. Both tests are remainders so a length near `Int.max`
            // fails here instead of overflowing the sum.
            guard length <= room - headerSize, length <= bytes.count - start else { break }

            let payload = Array(bytes[start..<(start + length)])
            offset = start + length

            switch type {
            case 1:
                // A whole record discards a fragment chain that never ended:
                // the half-write is not a record and must not be joined to it.
                pending = nil
                entries += batch(payload, keyPrefix: keyPrefix)
            case 2:
                // A first fragment may legitimately be empty. When a block has
                // exactly the seven bytes a header needs left, Chromium writes
                // a zero-length FIRST there and the batch in the next block, so
                // "started" cannot be tested as "has bytes yet".
                pending = payload
            case 3, 4:
                // A continuation with nothing to continue is not a record.
                // Append in place: unwrapping into a second mutable array
                // would copy the growing chain on every 32KB fragment.
                guard pending != nil else { break }
                pending?.append(contentsOf: payload)
                if type == 4, let complete = pending {
                    entries += batch(complete, keyPrefix: keyPrefix)
                    pending = nil
                }
            default:
                // A type this reader does not know is a format that has moved
                // on. Stopping is right: carrying on would frame the rest of
                // the file against an offset that is already wrong.
                return entries
            }
        }

        return entries
    }

    /// A batch is an 8-byte sequence, a 4-byte count, and then that many
    /// records. Each record's own sequence is the batch's plus its position,
    /// which is what makes two writes to one key orderable.
    ///
    /// **A batch is atomic.** Every length that comes off the wire is a
    /// `UInt64` that may not fit an `Int` (a corrupt one can be `UInt64.max`),
    /// and every range is bounded by the bytes that remain rather than by an
    /// offset-plus-length sum that a huge value would overflow. A record whose
    /// key or value will not parse drops the *whole* batch rather than the
    /// tail of it: a truncated write half-applied is not a credential, and
    /// reparsing the remains against a wrong offset could name another origin.
    private static func batch(_ bytes: [UInt8], keyPrefix: [UInt8]?) -> [Entry] {
        guard bytes.count >= 12 else { return [] }

        var sequence: UInt64 = 0
        for index in 0..<8 { sequence |= UInt64(bytes[index]) << (8 * index) }

        var count: UInt32 = 0
        for index in 0..<4 { count |= UInt32(bytes[8 + index]) << (8 * index) }

        var entries: [Entry] = []
        var offset = 12
        for index in 0..<Int(count) {
            guard offset < bytes.count else { return [] }
            let kind = bytes[offset]
            offset += 1

            // **Matched in place, and skipped without copying.** A profile's
            // log is megabytes of other sites' storage; building an array for
            // every key and every value on the way past was most of the time
            // this reader spent.
            guard let rawKeyLength = varint(bytes, &offset),
                  let keyLength = Int(exactly: rawKeyLength),
                  keyLength <= bytes.count - offset
            else { return [] }
            let keyStart = offset
            offset += keyLength

            let wanted = keyPrefix.map { prefix in
                keyLength >= prefix.count
                    && !prefix.indices.contains { bytes[keyStart + $0] != prefix[$0] }
            } ?? true

            switch kind {
            case 1:
                guard let rawValueLength = varint(bytes, &offset),
                      let valueLength = Int(exactly: rawValueLength),
                      valueLength <= bytes.count - offset
                else { return [] }
                let valueStart = offset
                offset += valueLength
                guard wanted else { continue }
                entries.append(Entry(
                    key: Array(bytes[keyStart..<(keyStart + keyLength)]),
                    value: Array(bytes[valueStart..<(valueStart + valueLength)]),
                    sequence: sequence &+ UInt64(index)
                ))
            case 0:
                guard wanted else { continue }
                entries.append(Entry(
                    key: Array(bytes[keyStart..<(keyStart + keyLength)]),
                    value: nil,
                    sequence: sequence &+ UInt64(index)
                ))
            default:
                return []
            }
        }
        // The count and the payload have to agree: bytes left after the last
        // claimed record are a write the header did not account for, and must
        // not be ignored as though the batch were complete.
        guard offset == bytes.count else { return [] }
        return entries
    }

    // MARK: - The sorted tables

    /// `0xdb4775248b80fb57`, the last eight bytes of every table.
    private static let magic: [UInt8] = [0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb]
    /// Two block handles of up to ten varint bytes each, padded, plus the magic.
    private static let footerSize = 48

    /// A table is read through its index: the footer says where the index
    /// block is, the index block says where every data block is, and each data
    /// block holds the entries.
    static func table(_ file: Data, keyPrefix: [UInt8]? = nil) -> [Entry] {
        guard file.count >= footerSize else { return [] }

        // **Only the footer is copied out of the mapping to begin with.** A
        // sorted table runs to megabytes and the blocks that matter are a few
        // kilobytes of it; materialising the whole file to reach them cost
        // more than decompressing them did.
        let bytes = slice(file, from: file.count - footerSize, count: footerSize)
        guard Array(bytes.suffix(8)) == magic else { return [] }

        var offset = 0
        // The metaindex handle comes first and is not needed: it points at the
        // filter block, which answers "might this key be here" — a question
        // with no meaning when every key is being read.
        //
        // A handle's numbers are varints off somebody else's disk; they may
        // not fit an `Int` at all. `Int(exactly:)` refuses that rather than
        // trapping, and `block` refuses one that runs past the file.
        guard varint(bytes, &offset) != nil, varint(bytes, &offset) != nil,
              let rawIndexOffset = varint(bytes, &offset),
              let rawIndexSize = varint(bytes, &offset),
              let indexOffset = Int(exactly: rawIndexOffset),
              let indexSize = Int(exactly: rawIndexSize),
              let index = block(file, offset: indexOffset, size: indexSize)
        else { return [] }

        let ceiling = keyPrefix.flatMap(upperBound)
        var entries: [Entry] = []
        var previous: [UInt8]?

        // An index entry's *value* is the handle of a data block; its key is a
        // separator — at or above every key inside that block, and below every
        // key in the next one. That is what makes skipping sound: a block
        // whose separator sorts below the prefix cannot hold it, and once the
        // *preceding* separator has passed the prefix's end, neither can any
        // block after it.
        for handle in items(index) {
            let separator = Array(handle.key.dropLast(8))
            if let ceiling, let previous, !precedes(previous, ceiling) { break }
            defer { previous = separator }
            if let keyPrefix, precedes(separator, keyPrefix) { continue }

            var cursor = 0
            guard let rawDataOffset = varint(handle.value, &cursor),
                  let rawDataSize = varint(handle.value, &cursor),
                  let dataOffset = Int(exactly: rawDataOffset),
                  let dataSize = Int(exactly: rawDataSize),
                  let data = block(file, offset: dataOffset, size: dataSize)
            else { continue }

            for item in items(data) {
                guard let entry = entry(internalKey: item.key, value: item.value) else { continue }
                entries.append(entry)
            }
        }
        return entries
    }

    /// A table's key carries its sequence and its kind in the last eight
    /// bytes: the top seven are the sequence, the bottom one says value or
    /// deletion. Strip them and what is left is the key that was written.
    private static func entry(internalKey: [UInt8], value: [UInt8]) -> Entry? {
        guard internalKey.count >= 8 else { return nil }

        var trailer: UInt64 = 0
        for (index, byte) in internalKey.suffix(8).enumerated() { trailer |= UInt64(byte) << (8 * index) }

        let kind = UInt8(trailer & 0xff)
        guard kind == 0 || kind == 1 else { return nil }

        return Entry(
            key: Array(internalKey.dropLast(8)),
            value: kind == 1 ? value : nil,
            sequence: trailer >> 8
        )
    }

    /// A block on disk is its contents, one byte saying how they were
    /// compressed, and four of checksum.
    ///
    /// Only "not compressed" and Snappy are handled. Chromium writes Snappy;
    /// zlib, bzip2 and Zstandard are in the format and are skipped rather than
    /// guessed at — a block that cannot be read drops its entries, which for
    /// this reader means one site's value goes missing rather than a wrong one
    /// being returned.
    private static func block(_ file: Data, offset: Int, size: Int) -> [UInt8]? {
        // A block handle read off disk can point anywhere, including at
        // `Int.max`. The bounds are written as remainders so a huge offset or
        // size fails instead of overflowing `offset + size + 5`, and the five
        // trailing bytes (compression marker plus checksum) are required to be
        // inside the file.
        guard offset >= 0, size >= 0, offset <= file.count, size <= file.count - offset else { return nil }
        guard file.count - offset - size >= 5 else { return nil }

        let contents = slice(file, from: offset, count: size)
        return switch slice(file, from: offset + size, count: 1)[0] {
        case 0: contents
        case 1: Snappy.decompress(contents)
        default: nil
        }
    }

    /// `Data` from a memory-mapped file is not indexed from zero, and reading
    /// it as though it were is an out-of-range crash on the second file of any
    /// directory.
    private static func slice(_ file: Data, from offset: Int, count: Int) -> [UInt8] {
        let start = file.index(file.startIndex, offsetBy: offset)
        return Array(file[start..<file.index(start, offsetBy: count)])
    }

    /// The entries in one block.
    ///
    /// Keys are stored as a difference from the one before — how many leading
    /// bytes are shared, then the rest — so they are rebuilt as the block is
    /// walked. The restart array at the end is what a real iterator binary
    /// searches; reading the whole block in order needs only its length, to
    /// know where the entries stop.
    private static func items(_ block: [UInt8]) -> [(key: [UInt8], value: [UInt8])] {
        guard block.count >= 4 else { return [] }

        var restarts: UInt32 = 0
        for (index, byte) in block.suffix(4).enumerated() { restarts |= UInt32(byte) << (8 * index) }

        // The entries stop where the restart array begins. Sizes are counted
        // against that boundary and not the block's own length: a key or value
        // that reaches into the restart array is borrowing bytes the writer
        // never put there as an entry, and reading them would accept a
        // truncated record as a whole one.
        let end = block.count - 4 - Int(restarts) * 4
        guard end >= 0, end <= block.count else { return [] }

        var items: [(key: [UInt8], value: [UInt8])] = []
        var previous: [UInt8] = []
        var offset = 0

        while offset < end {
            // Every one of these is a varint off disk and may exceed `Int`;
            // the shared-prefix count must also fit the key rebuilt so far.
            // A block that will not walk cleanly is dropped whole rather than
            // half-read, and each range is a remainder so `offset + length`
            // cannot overflow.
            guard let rawShared = varint(block, &offset), offset <= end,
                  let rawUnshared = varint(block, &offset), offset <= end,
                  let rawValueLength = varint(block, &offset), offset <= end,
                  let shared = Int(exactly: rawShared),
                  let unshared = Int(exactly: rawUnshared),
                  let valueLength = Int(exactly: rawValueLength),
                  shared <= previous.count,
                  unshared <= end - offset
            else { return [] }

            let keyStart = offset
            let keyEnd = keyStart + unshared
            guard valueLength <= end - keyEnd else { return [] }

            let key = Array(previous.prefix(shared)) + Array(block[keyStart..<keyEnd])
            let value = Array(block[keyEnd..<(keyEnd + valueLength)])
            offset = keyEnd + valueLength

            items.append((key, value))
            previous = key
        }

        // The walk has to land exactly on the boundary. Bytes left over mean
        // the lengths and the block disagree.
        return offset == end ? items : []
    }

    /// Bytewise, the order LevelDB itself sorts in.
    private static func precedes(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        lhs.lexicographicallyPrecedes(rhs)
    }

    /// The first key that cannot start with this prefix: the prefix with its
    /// last byte that is not `0xff` raised by one. Nil for a prefix of nothing
    /// but `0xff`, which has no such key — everything after it is in range.
    static func upperBound(_ prefix: [UInt8]) -> [UInt8]? {
        var bound = prefix
        while let last = bound.last {
            if last != 0xff {
                bound[bound.count - 1] = last + 1
                return bound
            }
            bound.removeLast()
        }
        return nil
    }

    // MARK: - Reading numbers

    /// LevelDB's varint: seven bits a byte, little end first, high bit set
    /// while more follow. Capped at ten bytes, which is as long as a 64-bit
    /// one can be — without the cap a run of `0xff` walks the whole file.
    ///
    /// The tenth byte (shift 63) is the only one that can overflow: it may
    /// carry a single bit, and a value above that would lose its high bits in
    /// a shift rather than fail — read as a small, wrong length. It is refused
    /// instead, as is an eleventh byte or a ten-byte run that never ends.
    static func varint(_ bytes: [UInt8], _ offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while offset < bytes.count, shift < 64 {
            let byte = bytes[offset]
            offset += 1
            if shift == 63, byte & 0x7f > 1 { return nil }
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

}

// MARK: - Snappy

/// Just enough Snappy to read a LevelDB block: the raw format, decompression
/// only.
///
/// Not the framed one with its stream header, and nothing that compresses.
/// The format is a length and then a run of elements, each either a literal to
/// copy out or a back-reference into what has been written already.
enum Snappy {
    /// **Written against pointers rather than `Array` subscripts**, which is
    /// not the usual preference here and is load-bearing. A browser's
    /// `localStorage` block is as large as the largest value in it, and some
    /// site on this machine keeps a four-megabyte one; the obvious version of
    /// this function — appending to an array, copying a byte at a time —
    /// spent half a second on that single block, which is most of what a
    /// refresh pass has. The output's exact size is the first thing the
    /// format states, so it is allocated once and filled.
    static func decompress(_ bytes: [UInt8]) -> [UInt8]? {
        var start = 0
        // 256MB is far past any block LevelDB writes; the cap is here so a
        // corrupt length cannot ask for an allocation that takes the machine
        // down with it.
        guard let expected = LevelDB.varint(bytes, &start), expected <= 256 << 20 else { return nil }
        let total = Int(expected)

        var ok = true
        let out = [UInt8](unsafeUninitializedCapacity: total) { buffer, produced in
            produced = 0
            guard let output = buffer.baseAddress else { ok = false; return }

            bytes.withUnsafeBufferPointer { input in
                guard let source = input.baseAddress else { ok = false; return }
                var cursor = start
                var written = 0

                while cursor < input.count {
                    let tag = source[cursor]
                    cursor += 1

                    if tag & 0x03 == 0 {
                        // A literal. Up to 60 the length is in the tag itself;
                        // above it the tag says how many bytes the length
                        // takes, little end first.
                        var length = Int(tag >> 2)
                        if length >= 60 {
                            let extra = length - 59
                            guard cursor + extra <= input.count else { ok = false; return }
                            length = 0
                            for index in 0..<extra { length |= Int(source[cursor + index]) << (8 * index) }
                            cursor += extra
                        }
                        length += 1

                        guard cursor + length <= input.count, written + length <= total else { ok = false; return }
                        output.advanced(by: written).update(from: source.advanced(by: cursor), count: length)
                        cursor += length
                        written += length
                        continue
                    }

                    // A copy. The three forms differ only in how many bytes
                    // the distance takes and where the length comes from.
                    let length: Int
                    let distance: Int
                    switch tag & 0x03 {
                    case 1:
                        guard cursor + 1 <= input.count else { ok = false; return }
                        length = 4 + Int((tag >> 2) & 0x07)
                        distance = (Int(tag >> 5) << 8) | Int(source[cursor])
                        cursor += 1
                    case 2:
                        guard cursor + 2 <= input.count else { ok = false; return }
                        length = Int(tag >> 2) + 1
                        distance = Int(source[cursor]) | (Int(source[cursor + 1]) << 8)
                        cursor += 2
                    default:
                        guard cursor + 4 <= input.count else { ok = false; return }
                        length = Int(tag >> 2) + 1
                        distance = Int(source[cursor]) | (Int(source[cursor + 1]) << 8)
                            | (Int(source[cursor + 2]) << 16) | (Int(source[cursor + 3]) << 24)
                        cursor += 4
                    }

                    guard distance > 0, distance <= written, written + length <= total else { ok = false; return }
                    let from = written - distance

                    if distance >= length {
                        // Disjoint, so it can go in one move.
                        output.advanced(by: written).update(from: output.advanced(by: from), count: length)
                    } else {
                        // **Overlapping on purpose.** A copy that reaches back
                        // fewer bytes than it writes is how the format says
                        // "repeat this run", so the source has to include what
                        // this same copy is still producing — which rules out
                        // a block move.
                        for index in 0..<length { output[written + index] = output[from + index] }
                    }
                    written += length
                }

                produced = written
            }
        }

        return ok && out.count == total ? out : nil
    }
}
