// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// DeepSeek Harness (`dsh`) transcripts.
///
/// `~/.dsh/sessions/<encoded-cwd>/<session-id>/session.jsonl[.zstd]` holds one
/// event per line: `session`, `request/header`, `user/message`,
/// `assistant/message` and `compaction/summary`. Assistant replies and
/// compaction summaries are both real provider calls and are counted additively.
///
/// **The suffix is physical; the magic is the truth.** A transcript is decoded
/// with zstd only when its first four bytes are the zstd frame magic, never
/// because it ends in `.zstd`; a plain file is already JSONL. The decoder
/// streams, keeps complete frames and the decodable prefix of a torn one, and
/// bounds both the raw and decoded size. `session.jsonl` and
/// `session.jsonl.zstd` (and versioned `session.v<N>…` spellings) are two names
/// for one transcript; record identity below makes the copies collapse.
///
/// **Reasoning is a subset of output, so it is not added.** The format states
/// that `reasoningTokens` is contained in `outputTokens`, and Pulse's output
/// bucket already counts reasoning once. The reported `outputTokens` is kept
/// whole; subtracting reasoning and then counting it again — in output or in
/// `unclassifiedTokens` — would either drop real output or double it.
///
/// **A forked prefix is not this session's work.** Events whose `seq` is below
/// the session header's `seedLength` were inherited verbatim and are skipped.
/// The identity is deliberately not session-scoped, so a call copied into a
/// fork collapses with its original.
enum DSHUsageReader {
    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []

        for file in transcriptFiles(roots) {
            guard !Task.isCancelled else { return [] }
            guard case let .success(data) = read(file), !data.isEmpty else { continue }

            var sessionID: String?
            var workspace: String?
            var seedLength = 0
            var headerProvider: String?
            var headerModel: String?

            for raw in LogLines(data: data) {
                guard
                    let value = try? JSONSerialization.jsonObject(with: Data(raw)),
                    let event = value as? [String: Any],
                    let type = AgentLogIO.text(event["type"])
                else { continue }

                let seq = AgentLogIO.count(event["seq"]) ?? 0
                let data = AgentLogIO.object(event["data"])

                switch type {
                case "session":
                    if sessionID == nil { sessionID = AgentLogIO.text(event["id"]) }
                    if workspace == nil { workspace = AgentLogIO.text(event["cwd"]) }
                    if seedLength == 0 { seedLength = AgentLogIO.count(event["seedLength"]) ?? 0 }

                case "request/header":
                    let config = data
                        .flatMap { AgentLogIO.object($0["header"]) }
                        .flatMap { AgentLogIO.object($0["config"]) }
                    headerProvider = AgentLogIO.text(config?["provider"]) ?? headerProvider
                    headerModel = AgentLogIO.text(config?["model"]) ?? headerModel

                case "assistant/message", "compaction/summary":
                    guard seq >= seedLength else { continue }
                    guard let usage = data.flatMap({ AgentLogIO.object($0["usage"]) }) else { continue }

                    let message = data.flatMap { AgentLogIO.object($0["message"]) }
                    let source = message.flatMap { AgentLogIO.object($0["source"]) }
                    let response = source
                        .flatMap { AgentLogIO.object($0["replayState"]) }
                        .flatMap { AgentLogIO.object($0["response"]) }
                    let model = AgentLogIO.text(response?["responseModel"])
                        ?? AgentLogIO.text(source?["model"])
                        ?? headerModel
                    let provider = AgentLogIO.text(source?["provider"]) ?? headerProvider
                    guard let model else { continue }

                    guard let milliseconds = AgentLogIO.count(event["time"]), milliseconds > 0 else { continue }
                    let timestamp = Date(timeIntervalSince1970: Double(milliseconds) / 1000)

                    let reasoning = AgentLogIO.count(usage["reasoningTokens"]) ?? 0
                    let tally = TokenTally(
                        input: AgentLogIO.count(usage["inputTokens"]) ?? 0,
                        cacheWrite: AgentLogIO.count(usage["cacheWriteTokens"]) ?? 0,
                        cacheRead: AgentLogIO.count(usage["cacheReadTokens"]) ?? 0,
                        // reasoningTokens is a subset of outputTokens.
                        output: StructuredLogSupport.output(
                            reported: AgentLogIO.count(usage["outputTokens"]) ?? 0,
                            reasoning: reasoning,
                            relationship: .includedInOutput
                        )
                    )

                    let identity: String
                    if type == "compaction/summary" {
                        identity = AgentLogIO.text(data?["compactionId"])
                            .map { "summary:cmp:\($0)" } ?? "seq:\(seq)"
                    } else if let id = AgentLogIO.text(message?["id"]) {
                        identity = "msg:\(id)"
                    } else {
                        identity = "assistant:seq:\(seq)"
                    }

                    let key = "dsh:\(identity):\(milliseconds):\(provider ?? ""):\(model):"
                        + "\(tally.input):\(tally.output):\(tally.cacheRead):\(tally.cacheWrite):\(reasoning)"

                    let resolved = sessionID ?? file.deletingLastPathComponent().lastPathComponent
                    guard
                        let record = StructuredLogSupport.record(
                            timestamp: timestamp,
                            model: model,
                            tally: tally,
                            sessionID: resolved,
                            sessionName: provider,
                            project: StructuredLogSupport.project(workspace),
                            deduplicationID: key
                        )
                    else { continue }
                    records.append(record)

                default:
                    continue
                }
            }
        }

        return records
    }

    /// Every compressed transcript that actually failed to decode.
    ///
    /// **Not just a missing library.** A file whose bytes are zstd (the frame
    /// magic) that cannot be decoded — no library, a corrupt frame, or one
    /// past the size ceiling — is surfaced here, so a store that would
    /// otherwise be read as a smaller figure is called out instead of looking
    /// complete. The check is a fresh read, not a cached result, so a file that
    /// later becomes readable is reported correctly. A plain JSONL transcript
    /// that is merely malformed is **not** a compression failure and is not
    /// reported here; the JSONL reader drops its bad lines as usual.
    static func notes(roots: [URL]) -> [String] {
        transcriptFiles(roots).compactMap { file in
            guard
                !Task.isCancelled,
                let data = try? Data(contentsOf: file, options: .mappedIfSafe),
                let failure = compressedFailure(data)
            else { return nil }
            return "\(file.lastPathComponent): \(failure.description)"
        }
    }

    /// The decode error a **compressed** transcript would meet, or nil when it
    /// decodes — or is a plain, uncompressed JSONL, which was never a
    /// compression concern and is not reported as one.
    ///
    /// Pure and limit-injectable: the ceilings are arguments, so a test can
    /// exercise the bound without building a real 64 MiB frame, and there is no
    /// global mutable to reset. The decoding itself stays `DSHZstdDecoder`'s.
    static func compressedFailure(
        _ data: Data,
        rawLimit: Int = DSHZstdDecoder.maxRawBytes,
        decodedLimit: Int = DSHZstdDecoder.maxDecodedBytes
    ) -> DSHZstdDecoder.Failure? {
        guard DSHZstdDecoder.isZstd(data) else { return nil }
        switch decode(data, rawLimit: rawLimit, decodedLimit: decodedLimit) {
        case .success: return nil
        case let .failure(failure): return failure
        }
    }

    /// `session.jsonl`, `session.jsonl.zstd` and versioned spellings.
    private static func transcriptFiles(_ roots: [URL]) -> [URL] {
        AgentLogIO.files(in: roots).filter { file in
            let name = file.lastPathComponent
            return name.hasPrefix("session.") && name.contains(".jsonl")
        }
    }

    /// The transcript's bytes with the standard ceilings: the file itself when
    /// it is plain JSONL, or its streaming decode when its bytes are zstd.
    ///
    /// Pure — the file is read each time, with no cached result — so `records`
    /// and `notes` never disagree about a store that changed between calls.
    private static func read(_ file: URL) -> Result<Data, DSHZstdDecoder.Failure> {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            return .failure(.corrupt("file could not be read"))
        }
        return decode(
            data,
            rawLimit: DSHZstdDecoder.maxRawBytes,
            decodedLimit: DSHZstdDecoder.maxDecodedBytes
        )
    }

    /// The bytes as JSONL, decoding only when the zstd frame magic is actually
    /// present; the ceilings are passed straight through to `DSHZstdDecoder`.
    private static func decode(
        _ data: Data,
        rawLimit: Int,
        decodedLimit: Int
    ) -> Result<Data, DSHZstdDecoder.Failure> {
        guard DSHZstdDecoder.isZstd(data) else { return .success(data) }

        do {
            return .success(
                try DSHZstdDecoder.decode(data, rawLimit: rawLimit, decodedLimit: decodedLimit)
            )
        } catch let failure as DSHZstdDecoder.Failure {
            return .failure(failure)
        } catch {
            return .failure(.corrupt("\(error)"))
        }
    }
}
