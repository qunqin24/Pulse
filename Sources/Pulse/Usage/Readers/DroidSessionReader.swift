// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Droid's session store: real totals, no per-reply counts.
///
/// `<session>.settings.json` holds the session's **cumulative** usage and a
/// sibling `<session>.jsonl` transcript holds the assistant replies with their
/// times but no tokens at all. Splitting a session total across replies would
/// have to invent a per-reply split from bytes or elapsed time, which is not a
/// count the store reported, so this reader emits **one aggregate record** for
/// the session instead. `isAggregate` marks it as a total rather than an
/// increment, so it lands on its day and never in an hour profile.
///
/// **The input/cache relation is never assumed.** The `tokenUsage` column names
/// resemble Anthropic's, but a provider lock is not proof that Factory persisted
/// the raw `input_tokens`/`cache_read_input_tokens` partition rather than a
/// normalized form — the storage schema is its own thing. So a **reported
/// total**, when present, is the only authority: it can prove the cache read
/// inside the prompt (subtract) or beside it (disjoint), and a total that proves
/// neither is carried as `unclassifiedTokens`. With **no total and a positive
/// cache**, the reported output is kept priced, the reported input is carried as
/// a known quantity of unknown kind, the cache is not added at all, and the
/// record is marked `isPartial` — a real readable subset, not a complete total.
/// A positive thinking count whose relation to output is likewise undocumented
/// marks the record partial even with no cache.
///
/// The time is the store's own `providerLockTimestamp`. A session whose usage
/// was recognized but has no locatable time is not emitted; when that happens
/// beside sessions that could be read, those records are marked `isPartial`
/// rather than presenting the survivor as the whole story. The model id is kept
/// as written (minus an explicit `custom:` transport prefix and bracketed
/// qualifier) so a published id such as `claude-opus-4.5` is not mangled; a
/// provider with no usable model gets a valueless `*-unknown` placeholder.
enum DroidSessionReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let files = AgentLogIO.files(in: roots, extensions: ["json"])
            .filter { $0.lastPathComponent.hasSuffix(".settings.json") }

        var result: [AgentUsageRecord] = []
        var incomplete = false
        for file in files {
            let evaluation = evaluate(at: file)
            if let record = evaluation.record { result.append(record) }
            if evaluation.sawUnusableUsage { incomplete = true }
        }
        return incomplete ? result.map(Self.markedPartial) : result
    }

    static func record(at url: URL) -> AgentUsageRecord? {
        evaluate(at: url).record
    }

    // MARK: - One settings file

    private struct Evaluation {
        var record: AgentUsageRecord?
        /// True when this file carried real usage that could not be counted
        /// (no locatable time or no usable model).
        var sawUnusableUsage: Bool
    }

    private static func evaluate(at url: URL) -> Evaluation {
        guard let root = AgentLogIO.object(AgentLogIO.json(at: url)) else {
            return Evaluation(record: nil, sawUnusableUsage: false)
        }
        guard let usage = root["tokenUsage"] as? [String: Any] else {
            return Evaluation(record: nil, sawUnusableUsage: false)
        }
        guard let counts = decode(usage) else {
            return Evaluation(record: nil, sawUnusableUsage: false)
        }
        guard counts.tally.total > 0 || counts.unclassified > 0 else {
            return Evaluation(record: nil, sawUnusableUsage: false)
        }

        // From here the file holds recognized usage; a missing locatable field
        // makes it uncountable rather than a non-reading.
        guard let timestamp = AgentLogIO.timestamp(root["providerLockTimestamp"]) else {
            return Evaluation(record: nil, sawUnusableUsage: true)
        }
        let session = sessionID(for: url)
        guard let model = normalize(AgentLogIO.text(root["model"]))
            ?? transcriptModel(sibling: url)
            ?? providerDefault(AgentLogIO.text(root["providerLock"]))
        else {
            return Evaluation(record: nil, sawUnusableUsage: true)
        }

        return Evaluation(
            record: AgentUsageRecord(
                timestamp: timestamp, model: model, tally: counts.tally,
                sessionID: session,
                deduplicationID: "droid:\(session)",
                unclassifiedTokens: counts.unclassified,
                isAggregate: true,
                isPartial: counts.isPartial
            ),
            sawUnusableUsage: false
        )
    }

    /// The file stem with `.settings` removed.
    static func sessionID(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasSuffix(".settings.json") { return String(name.dropLast(".settings.json".count)) }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Keeps the model id as the store wrote it. Only an explicit `custom:`
    /// transport prefix and a bracketed qualifier are removed; case and
    /// punctuation (`claude-opus-4.5`) are part of the pricing identity.
    static func normalize(_ raw: String?) -> String? {
        guard var value = AgentLogIO.text(raw) else { return nil }
        if value.hasPrefix("custom:") { value = String(value.dropFirst("custom:".count)) }
        value = value.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        return AgentLogIO.text(value)
    }

    /// A transcript system-reminder line names the model when the settings file
    /// does not.
    static func transcriptModel(sibling url: URL) -> String? {
        let transcript = url.deletingLastPathComponent().appending(path: sessionID(for: url) + ".jsonl")
        for line in LogLines(at: transcript) {
            guard let text = String(data: Data(line), encoding: .utf8) else { continue }
            guard let marker = text.range(of: "Model:") else { continue }
            let remainder = text[marker.upperBound...].drop { $0 == " " || $0 == "\t" }
            let name = String(remainder.prefix { !$0.isWhitespace && $0 != "<" && $0 != "\"" && $0 != "\\" })
            if let normalized = normalize(name) { return normalized }
        }
        return nil
    }

    /// A valueless placeholder for a provider with no usable model. Never a
    /// concrete model: naming one would price another model's rates.
    static func providerDefault(_ provider: String?) -> String? {
        guard let provider = provider?.lowercased(), !provider.isEmpty else { return nil }
        if provider.contains("anthropic") || provider.contains("claude") { return "claude-unknown" }
        if provider.contains("openai") || provider.contains("gpt") { return "gpt-unknown" }
        if provider.contains("google") || provider.contains("gemini") { return "gemini-unknown" }
        if provider.contains("xai") || provider.contains("grok") { return "grok-unknown" }
        return "\(provider)-unknown"
    }

    private static func markedPartial(_ record: AgentUsageRecord) -> AgentUsageRecord {
        var copy = record
        copy.isPartial = true
        return copy
    }

    // MARK: - Tokens

    /// Splits one `tokenUsage` object.
    ///
    /// Nil when nothing countable was reported. With a reported total, the
    /// total is reconciled against candidate identities; one that proves
    /// neither becomes `unclassifiedTokens` with `isPartial` false (the total
    /// itself is complete, only its kinds are unknown). With no total, a
    /// positive cache or thinking figure cannot be placed without a guess, so
    /// the output is kept, the input carried as unknown, and the record marked
    /// partial.
    static func decode(_ usage: [String: Any]) -> (tally: TokenTally, unclassified: Int, isPartial: Bool)? {
        let input = AgentLogIO.count(usage["inputTokens"])
        let output = AgentLogIO.count(usage["outputTokens"])
        let thinking = AgentLogIO.count(usage["thinkingTokens"])
        let cacheWrite = AgentLogIO.count(usage["cacheCreationTokens"])
        let cacheRead = AgentLogIO.count(usage["cacheReadTokens"])
        let total = AgentLogIO.count(usage["totalTokens"])
            ?? AgentLogIO.count(usage["total"])
            ?? AgentLogIO.count(usage["total_tokens"])

        let any = input != nil || output != nil || thinking != nil
            || cacheWrite != nil || cacheRead != nil || total != nil
        guard any else { return nil }

        let i = input ?? 0
        let o = output ?? 0
        let k = thinking ?? 0
        let cw = cacheWrite ?? 0
        let cr = cacheRead ?? 0
        let outputBucket = output ?? thinking ?? 0

        if let total {
            // Reasoning inside/independent of output, cache inside/beside
            // input: four candidate identities. A total that matches exactly
            // one settles both.
            let variants: [(input: Int, cacheWrite: Int, cacheRead: Int, output: Int)] = [
                (i, cw, cr, o + k),
                (max(0, i - cr - cw), cw, cr, o + k),
                (i, cw, cr, o),
                (max(0, i - cr - cw), cw, cr, o),
            ]
            for variant in variants
            where variant.input + variant.cacheWrite + variant.cacheRead + variant.output == total {
                return (
                    TokenTally(
                        input: variant.input, cacheWrite: variant.cacheWrite,
                        cacheRead: variant.cacheRead, output: variant.output
                    ),
                    0,
                    false
                )
            }
            return (TokenTally(), total, false)
        }

        if cr == 0, cw == 0 {
            // No cache ambiguity. A positive thinking count is still of
            // undocumented relation to output, so it marks the record partial
            // rather than being silently dropped.
            return (
                TokenTally(input: i, cacheWrite: 0, cacheRead: 0, output: outputBucket),
                0,
                k > 0
            )
        }

        // Positive cache with no total: the relation is not provable. Keep the
        // reported output, carry the reported input as a known unknown, add
        // nothing for the cache, and say the count is partial.
        return (TokenTally(output: outputBucket), i, true)
    }
}
