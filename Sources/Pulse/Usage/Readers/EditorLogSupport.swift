import CryptoKit
import Foundation

/// Decoding helpers shared by the editor/agent readers in this directory.
///
/// Everything here is deliberately narrow: it decodes a value that a product
/// actually wrote and never turns a length, a duration, a cost or a missing
/// field into a token count. A missing key stays `nil`; a record is only built
/// when the store named a model and a real timestamp.
enum EditorLog {
    // MARK: - JSON

    /// Parses a JSON object out of a string a log field carries as text.
    ///
    /// Some products serialise a request's usage as a JSON string inside a
    /// JSON string. Malformed or non-object text is `nil`, never a partial
    /// object.
    static func jsonObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return AgentLogIO.object(try? JSONSerialization.jsonObject(with: data))
    }

    /// The first `{…}` in `text`, balanced and unescaped, as an object.
    ///
    /// A log line can put a usage object in the middle of a sentence and then
    /// keep talking; taking the first balanced object is how that object is
    /// read without guessing where the line ends.
    static func braceObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    guard
                        let data = String(text[start...index]).data(using: .utf8),
                        let value = try? JSONSerialization.jsonObject(with: data)
                    else { return nil }
                    return AgentLogIO.object(value)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - Counts

    /// The first key that carries a whole count, preferring a positive one.
    ///
    /// Some objects list the same quantity twice under different spellings,
    /// and a zero in the first is not evidence the second is absent. A present
    /// zero is returned when no key is positive, so "reported as zero" is not
    /// confused with "not reported".
    static func firstCount(_ object: [String: Any], _ keys: [String]) -> Int? {
        var zero: Int?
        for key in keys {
            guard let value = AgentLogIO.count(object[key]) else { continue }
            if value > 0 { return value }
            if zero == nil { zero = value }
        }
        return zero
    }

    /// A whole count, with a missing or malformed value read as zero.
    ///
    /// Only for a bucket where zero and absent mean the same thing to the
    /// arithmetic downstream, and only after the caller has established that
    /// at least one real count was present.
    static func int(_ value: Any?) -> Int { AgentLogIO.count(value) ?? 0 }

    static func nonBlank(_ value: String?) -> String? { AgentLogIO.text(value) }

    /// A deterministic content digest, used only as a fragment identity for a
    /// whole-file mirror. Two byte-identical files share it; two different
    /// files do not.
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
    }

    // MARK: - Models

    /// A model id with a gateway's provider prefix removed.
    ///
    /// CommandCode and ZCode write `provider/model`; Pulse's price table is
    /// keyed by the bare id models.dev publishes. The prefix is not part of
    /// what the model is, so it is dropped at the boundary rather than making
    /// every one of these records unpriced.
    static func modelID(_ raw: String?) -> String? {
        guard let raw = AgentLogIO.text(raw) else { return nil }
        guard let slash = raw.lastIndex(of: "/") else { return raw }
        let tail = String(raw[raw.index(after: slash)...])
        return tail.isEmpty ? raw : tail
    }

    /// Keep the stated directory; display names are derived after grouping.
    static func project(_ path: String?) -> String? {
        AgentLogIO.text(path)
    }

    // MARK: - Timestamps

    /// A `Date` from an epoch value whose unit the schema fixes per branch.
    ///
    /// Used only where a store documents the same column as milliseconds above
    /// a stated threshold and seconds below it (WorkBuddy's `updated_at`). The
    /// threshold is the schema's, not a guess from the magnitude of a value
    /// nobody described.
    static func autoEpoch(_ value: Int?) -> Date? {
        guard let value, value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? Double(value) / 1000 : Double(value)
        guard seconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// A naive local `YYYY/MM/DD HH:MM:SS[.fff]` prefix, which is what the
    /// Tencent extension log writes. The wall-clock string *is* the timestamp;
    /// nothing is filled from a file's modification date or the clock.
    static func naiveTimestamp(_ line: String) -> Date? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        for (length, formatter) in naiveFormats {
            let candidate = String(trimmed.prefix(length))
            guard candidate.count == length else { continue }
            if let date = formatter.date(from: candidate) { return date }
        }
        return nil
    }

    // DateFormatter is thread-safe on supported macOS versions. Construct once
    // and never mutate, rather than allocating four formatters per log line.
    private static let naiveFormats: [(Int, DateFormatter)] = {
        [
            "yyyy/MM/dd HH:mm:ss.SSS",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss",
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return (format.count, formatter)
        }
    }()

    // MARK: - Records

    /// Builds one normalized record, in one place.
    ///
    /// `unclassifiedTokens` carries a total the store reported without saying
    /// how it split; `isAggregate` marks a session- or report-level total
    /// whose per-hour timing is not known; `isPartial` marks a record the
    /// reader knows is only a subset of the source. None invents a bucket, and
    /// the caller passes `tally` empty when no kind was named.
    static func record(
        timestamp: Date,
        model: String,
        tally: TokenTally,
        sessionID: String? = nil,
        sessionName: String? = nil,
        title: String? = nil,
        project: String? = nil,
        deduplicationID: String? = nil,
        unclassifiedTokens: Int = 0,
        isAggregate: Bool = false,
        isPartial: Bool = false
    ) -> AgentUsageRecord {
        AgentUsageRecord(
            timestamp: timestamp,
            model: model,
            tally: tally,
            sessionID: sessionID,
            sessionName: sessionName,
            title: title,
            project: project,
            deduplicationID: deduplicationID,
            unclassifiedTokens: unclassifiedTokens,
            isAggregate: isAggregate,
            isPartial: isPartial
        )
    }

    // MARK: - Combining a reported usage object

    /// One usage object reduced to Pulse's four disjoint buckets.
    struct UsageParts {
        var tally: TokenTally
        /// A total the store reported that the named kinds do not add up to.
        var unclassified = 0
    }

    /// Turns one product's usage keys into disjoint buckets.
    ///
    /// `input`/`output`/`cacheRead`/`cacheWrite`/`reasoning` are the values
    /// the store reported, each `nil` when the key was absent. `total` is the
    /// store's own total, when it carries one.
    ///
    /// **Inclusion is only decided by the store's own arithmetic.** When the
    /// total provisionally equals `input + output` and does *not* equal the sum
    /// of every named kind, the two are taken to be inclusive — so the cache
    /// overlap is removed from input. When the total instead equals the sum of
    /// every named kind, reasoning is a bucket of its own. In any other case
    /// the values are kept exactly as reported.
    ///
    /// **Reasoning is folded into output only when proven separate.** A store
    /// whose output already contains reasoning would be double-counted by
    /// adding it again, so `reasoning` is added to output only when the total
    /// equals the sum of every named kind; otherwise the reported output is
    /// kept whole and reasoning is not counted a second time.
    ///
    /// **A bare total is not input.** When the object names no kind at all,
    /// the tally stays empty and the total becomes `unclassifiedTokens`; a
    /// total larger than the named kinds leaves the remainder unclassified.
    /// `exclusiveInput` is a cache-miss field the store already reports
    /// cache-exclusive; it wins over `input`.
    static func combine(
        input: Int?,
        output: Int?,
        cacheRead: Int?,
        cacheWrite: Int?,
        reasoning: Int?,
        total: Int?,
        exclusiveInput: Int? = nil,
        inputMayIncludeCache: Bool = true
    ) -> UsageParts {
        let cacheReadValue = cacheRead ?? 0
        let cacheWriteValue = cacheWrite ?? 0
        let reasoningValue = reasoning ?? 0
        let namesAKind = input != nil || output != nil || cacheRead != nil
            || cacheWrite != nil || reasoning != nil || exclusiveInput != nil

        if !namesAKind, let total, total > 0 {
            return UsageParts(tally: TokenTally(), unclassified: total)
        }

        let reportedInput = input ?? 0
        let rawOutput = output ?? 0
        let baseInput = exclusiveInput ?? reportedInput
        let disjoint = baseInput + rawOutput + cacheReadValue + cacheWriteValue + reasoningValue

        let inclusive = exclusiveInput == nil
            && inputMayIncludeCache
            && total != nil
            && total == reportedInput + rawOutput
            && total != disjoint

        var freshInput = baseInput
        if inclusive {
            freshInput = max(0, reportedInput - cacheReadValue - cacheWriteValue)
        }

        var unclassified = 0
        if let total, total > disjoint { unclassified = total - disjoint }

        // Reasoning is a separate kind only when the store's total counts it
        // separately. A store whose output already contains it keeps the whole
        // reported output; adding reasoning here would count it twice.
        let reasoningIsSeparate = total != nil && total == disjoint
        let foldedOutput = reasoningIsSeparate ? rawOutput + reasoningValue : rawOutput

        return UsageParts(
            tally: TokenTally(
                input: freshInput,
                cacheWrite: cacheWriteValue,
                cacheRead: cacheReadValue,
                output: foldedOutput
            ),
            unclassified: unclassified
        )
    }
}
