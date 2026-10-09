// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What Pulse keeps of a Claude Code or Codex transcript after the CLI has
/// deleted it.
///
/// **The transcripts are the only record, and the CLIs prune them.** Claude
/// Code deletes sessions older than `cleanupPeriodDays`; Codex users clear
/// `~/.codex/sessions`. `UsageLedgerReader` used to drop a file's cache entry
/// the scan it went missing, and its days left Token spend and the recaps
/// with it — a month's total could shrink a month later.
///
/// **One entry per transcript, kept the scan it disappears**, holding what that
/// file *counted* in that scan: its quarter-hours by model after the
/// cross-file dedupe, its reply timings, and what the session row needs (title,
/// directory, review mark). Nothing is kept for a file Pulse never scanned
/// while it existed.
///
/// **A kept file still claims its replies.** A resumed or forked conversation
/// opens with a copy of the old one's history (`ScannedReply`). The kept file
/// counted those replies, so the ids it counted — and, for Codex, the running
/// totals a fork replays — are kept beside its figures and are claimed before
/// any live file is read; the live copies are dropped as they were while both
/// files existed. **Claims are never let go**: a file holding the copies can
/// be away for a scan (a moved folder, a volume not mounted) or come back from
/// a backup, and a claim dropped meanwhile would count its copies again for
/// good. They are kept as 64-bit digests (`ClaimDigest`), eight bytes a reply.
///
/// **Its own file, unnumbered** (`archive-ledger-<provider>.json`). The
/// `ledger-<n>-*` cache is thrown away whenever its number goes up, and can
/// be, because it is rebuilt from the transcripts; this cannot be rebuilt from
/// anything, so it must never be superseded by renaming. A change of shape
/// bumps `format` and must read the older one, not discard it.
struct TranscriptArchive: Codable, Equatable {
    /// The shape this build writes and reads. A file written in a later shape
    /// is left untouched (`load` returns nil).
    static let currentFormat = 1

    var format = TranscriptArchive.currentFormat
    /// By the path the transcript had.
    var files: [String: Kept] = [:]

    struct Kept: Codable, Equatable {
        /// What the file counted, by quarter-hour key and then raw model id.
        var days: [String: [String: TokenTally]]
        var timings: [String: [String: ReplyTiming]]?
        var title: String?
        var cwd: String?
        var isReview: Bool?
        /// Digests of the reply ids this file counted (`ClaimDigest.pack`).
        var claims: String?
        /// Digests of the Codex running totals this file reached.
        var totals: String?
        /// When the file was found gone.
        var kept: Date?

        private enum CodingKeys: String, CodingKey {
            case days, timings, title, cwd, isReview, claims, totals, kept
        }

        init(
            days: [String: [String: TokenTally]], timings: [String: [String: ReplyTiming]]?,
            title: String?, cwd: String?, isReview: Bool?, claims: String?, totals: String?, kept: Date?
        ) {
            self.days = days
            self.timings = timings
            self.title = title
            self.cwd = cwd
            self.isReview = isReview
            self.claims = claims
            self.totals = totals
            self.kept = kept
        }

        /// Every field optional on the way in, so a field added later does
        /// not make the whole archive unreadable.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            days = try container.decodeIfPresent([String: [String: TokenTally]].self, forKey: .days) ?? [:]
            timings = try container.decodeIfPresent([String: [String: ReplyTiming]].self, forKey: .timings)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
            isReview = try container.decodeIfPresent(Bool.self, forKey: .isReview)
            claims = try container.decodeIfPresent(String.self, forKey: .claims)
            totals = try container.decodeIfPresent(String.self, forKey: .totals)
            kept = try container.decodeIfPresent(Date.self, forKey: .kept)
        }
    }

    private enum CodingKeys: String, CodingKey { case format, files }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(Int.self, forKey: .format) ?? Self.currentFormat
        files = try container.decodeIfPresent([String: Kept].self, forKey: .files) ?? [:]
    }

    /// The archive, an empty one when there is none yet, or **nil when a file
    /// is there and cannot be read** — damaged, or written by a later build.
    /// Nil means nothing may be moved into it and it must not be overwritten.
    static func load(for provider: Provider, directory: URL?) -> TranscriptArchive? {
        let url = file(for: provider, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return TranscriptArchive() }
        guard
            let data = try? Data(contentsOf: url),
            let archive = try? JSONDecoder().decode(TranscriptArchive.self, from: data),
            archive.format <= currentFormat
        else { return nil }
        return archive
    }

    /// Whether the archive is on disk. A caller drops the cache entries it
    /// just kept only when this is true.
    func save(for provider: Provider, directory: URL?) -> Bool {
        guard !Task.isCancelled else { return false }
        if directory == nil { PulseStorage.prepare() }
        guard let data = try? JSONEncoder().encode(self) else { return false }
        return (try? data.write(to: Self.file(for: provider, directory: directory), options: .atomic)) != nil
    }

    static func file(for provider: Provider, directory: URL?) -> URL {
        (directory ?? PulseStorage.directory).appending(path: "archive-ledger-\(provider.rawValue).json")
    }
}

/// A stable 64-bit digest of a claim (FNV-1a over its UTF-8), and a compact
/// way to store many. Swift's own `Hasher` is seeded per launch, so it cannot
/// be written down.
enum ClaimDigest {
    static func of(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Eight little-endian bytes each, in base 64. Nil for none.
    static func pack(_ digests: [UInt64]) -> String? {
        guard !digests.isEmpty else { return nil }
        var data = Data(capacity: digests.count * 8)
        for digest in digests { withUnsafeBytes(of: digest.littleEndian) { data.append(contentsOf: $0) } }
        return data.base64EncodedString()
    }

    static func unpack(_ packed: String?) -> [UInt64] {
        guard let packed, let data = Data(base64Encoded: packed) else { return [] }
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - bytes.count % 8, by: 8).map { offset in
            (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
        }
    }
}
