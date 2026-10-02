// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CryptoKit
import Foundation

/// The handful of conversions the Group E readers share.
///
/// Kept in one place so two readers cannot disagree about what an account slug
/// is or when two files are byte-identical — the same reason `AgentLogIO` exists
/// for numbers and time.
enum CapturedSupport {
    /// An ASCII slug for a product's own account or workspace label.
    ///
    /// Only ASCII letters and digits survive; every other run collapses to a
    /// single `-`, the result is lowercased, and a leading or trailing dash is
    /// dropped. Nil when nothing survives, so a caller can fall back rather
    /// than key a record under an empty name.
    static func slug(_ value: String) -> String? {
        var output = ""
        var pendingDash = false
        for character in value {
            if let ascii = character.asciiValue, Self.isASCIILetterOrDigit(ascii) {
                if pendingDash, !output.isEmpty { output.append("-") }
                pendingDash = false
                output.append(character)
            } else if !output.isEmpty {
                pendingDash = true
            }
        }
        return output.isEmpty ? nil : output.lowercased()
    }

    /// `true` for an ASCII `A–Z`, `a–z` or `0–9` byte.
    ///
    /// `UInt8` has no `isLetter`/`isNumber`; the ranges are written out so the
    /// slug stays exactly ASCII letters and digits, and a non-ASCII scalar
    /// (whose `asciiValue` is nil) never survives.
    private static func isASCIILetterOrDigit(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
            || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
    }

    /// A content digest, so a byte-identical export written to two roots is
    /// recognised as one export rather than read twice.
    ///
    /// This is **file replay**, not row identity: it only collapses files whose
    /// bytes are the same. Two rows with equal values inside one file, or two
    /// different files that merely overlap, are untouched by it.
    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
    }

    /// The multiset union of records read from several files of **one scope**.
    ///
    /// Two exports `{A}` and `{A, B}` yield `A` and `B`, never two `A`s: a row
    /// found in more than one file is kept **once per the most any single file
    /// holds**, not once per file. Two equal rows **inside one file** are kept,
    /// because that file itself says there were two.
    ///
    /// `overlapped` is true when some row appeared in more than one file — the
    /// increment inside the shared region cannot be confirmed, so the caller
    /// marks the scope incomplete rather than adding it again. A clean union of
    /// disjoint files is not flagged.
    ///
    /// `signature` is a row's content identity. It is used only to count, never
    /// to drop a row a single file already reported more than once.
    static func reconcile(
        _ files: [[AgentUsageRecord]],
        signature: (AgentUsageRecord) -> String
    ) -> (records: [AgentUsageRecord], overlapped: Bool) {
        var order: [String] = []
        var representative: [String: AgentUsageRecord] = [:]
        var maximum: [String: Int] = [:]
        var total: [String: Int] = [:]

        for records in files {
            var perFile: [String: Int] = [:]
            for record in records {
                let key = signature(record)
                perFile[key, default: 0] += 1
                if representative[key] == nil {
                    representative[key] = record
                    order.append(key)
                }
            }
            for (key, count) in perFile {
                maximum[key] = max(maximum[key] ?? 0, count)
                total[key] = (total[key] ?? 0) + count
            }
        }

        var out: [AgentUsageRecord] = []
        var overlapped = false
        for key in order {
            let emit = maximum[key] ?? 0
            if (total[key] ?? 0) > emit { overlapped = true }
            guard let record = representative[key] else { continue }
            for _ in 0..<emit { out.append(record) }
        }
        return (out, overlapped)
    }
}
