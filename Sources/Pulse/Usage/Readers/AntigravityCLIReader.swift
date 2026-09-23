import Foundation

/// Antigravity CLI's conversations, one SQLite database per conversation under
/// `<GEMINI_CLI_HOME or ~/.gemini>/antigravity-cli/conversations/`.
///
/// The token data is in protobuf blobs, and no `.proto` ships with the CLI.
/// This reader therefore carries its **own** minimal protobuf wire decoder —
/// written to the standard wire rules, not ported — which is kept deliberately
/// hostile-safe: a truncated buffer, an overlong varint, a length that runs
/// past the end, an unknown wire type and an unknown field number all end the
/// decode instead of reading out of bounds.
///
/// **Only fields whose meaning is established are counted.** The usage
/// message's `#2` (newly-processed input), `#5` (cache read), `#9` (output)
/// and `#10` (thinking) are the counters with an observed meaning; `#9 + #10`
/// is the contract's total output, so reasoning is folded into output once.
/// `#1` is a near-constant whose "fixed system prompt" reading is
/// reverse-engineered, **not** an established count, so it is read by nothing
/// here — not as input and not as unclassified work. A turn whose real
/// counters are all zero is dropped; nothing is estimated from text or cost.
///
/// **Every record is marked `isPartial`.** Excluding `#1` and having no
/// whole-usage total to reconcile the counted fields against means the read is
/// a proven subset rather than a confirmed complete one; the flag says so and
/// changes no count.
///
/// **Timestamps need evidence.** Only the explicit per-generation timestamp
/// (`#9.#4`) and the `steps` table's timestamp are used. The unknown
/// `#9.#10` bytes are never decoded into an event time: a lifetime check
/// cannot turn an unproven encoding into an exact one. A generation with no
/// such timestamp falls back to the conversation's created-at and is marked
/// **aggregate**, because a session anchor is not the moment of the turn. A
/// file modification date is never used.
enum AntigravityCLIReader {
    /// **The CLI and the IDE are two clients, and are never added together.**
    ///
    /// They write the same one-SQLite-per-conversation store into sibling
    /// folders under the same root, so one reader serves both — but each folder
    /// belongs to a different product, and a reader that pooled them would put
    /// one number on screen for two things the reader uses separately.
    ///
    /// The format spec named `antigravity-cli` alone, which is why the IDE went
    /// unread: measured on a Mac with the IDE installed, that folder was absent
    /// while `antigravity/conversations` held 38 readable generations. The
    /// spec's path is kept rather than repointed, since it is presumably right
    /// for whatever writes it; a root that does not exist yields no records.
    static func inputs(client: String, home: URL, environment: [String: String]) -> [URL] {
        let root: URL
        if let value = DatabaseReaderSupport.environment("GEMINI_CLI_HOME", environment) {
            root = DatabaseReaderSupport.directory(value)
        } else {
            root = home.appending(path: ".gemini", directoryHint: .isDirectory)
        }

        let folders: [String] = switch client {
        // Both IDE layouts: `antigravity` is what the current one writes,
        // `antigravity-ide` is the other spelling seen beside it.
        case "antigravity-ide": ["antigravity", "antigravity-ide"]
        default: ["antigravity-cli"]
        }

        return folders.map {
            root.appending(path: "\($0)/conversations", directoryHint: .isDirectory)
        }
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        AgentLogIO.files(in: roots, extensions: ["db"]).flatMap(read)
    }

    // MARK: - One conversation

    private static func read(_ file: URL) -> [AgentUsageRecord] {
        AgentSQLite.read(at: file) { database -> [AgentUsageRecord] in
            let session = DatabaseReaderSupport.stem(file)
            let anchor = trajectory(database)
            let steps = stepTimestamps(database)
            let generations = self.generations(database)

            // The models a label was seen with, and the file's single model if
            // it has exactly one. Used only to recover an identity the routing
            // label threw away.
            var labels: [String: Set<String>] = [:]
            var models: Set<String> = []
            for generation in generations {
                guard let model = generation.model, model != routingLabel else { continue }
                models.insert(model)
                if let label = generation.label { labels[label, default: []].insert(model) }
            }
            let soleModel = models.count == 1 ? models.first : nil

            var seen: Set<String> = []
            var records: [AgentUsageRecord] = []
            for generation in generations {
                guard let usage = generation.usage, usage.counted > 0 else { continue }
                if let response = usage.responseID {
                    guard seen.insert(response).inserted else { continue }
                }

                // An exact event time, or the session anchor as an aggregate.
                // The unknown `#9.#10` bytes never become a turn time.
                let event = generation.explicitTimestamp
                    ?? usage.responseID.flatMap { steps.byResponse[$0] }
                    ?? steps.byIndex[generation.index]
                guard let timestamp = event ?? anchor.createdAt else { continue }

                let model = resolvedModel(
                    generation, labels: labels, sole: soleModel
                )
                records.append(
                    DatabaseReaderSupport.record(
                        at: timestamp,
                        model: model,
                        tally: TokenTally(
                            input: usage.input,
                            cacheRead: usage.cacheRead,
                            output: usage.output + usage.reasoning
                        ),
                        sessionID: session,
                        project: anchor.workspace,
                        deduplicationID: usage.responseID.map {
                            "antigravity:\(session):\($0)"
                        } ?? "antigravity:\(session):\(generation.index)",
                        isAggregate: event == nil,
                        // `#1` is deliberately not counted and there is no
                        // whole-usage total to reconcile the counted fields
                        // against, so the record is a proven subset.
                        isPartial: true
                    )
                )
            }
            return records
        } ?? []
    }

    private static let routingLabel = "gemini-default"

    private struct Anchor {
        var createdAt: Date?
        var workspace: String?
    }

    private struct Steps {
        var byResponse: [String: Date] = [:]
        var byIndex: [Int: Date] = [:]
    }

    private struct Usage {
        /// `#2`, newly-processed (non-cached) input. `#1` is deliberately
        /// absent: its meaning is not established, so it is no count at all.
        var fresh = 0
        var cacheRead = 0
        var output = 0
        var reasoning = 0
        var responseID: String?

        var input: Int { fresh }
        var counted: Int { fresh + cacheRead + output + reasoning }
    }

    private struct Generation {
        var index: Int
        var model: String?
        var label: String?
        var usage: Usage?
        var explicitTimestamp: Date?
    }

    // MARK: - Tables

    private static func trajectory(_ database: OpaquePointer) -> Anchor {
        var anchor = Anchor()
        AgentSQLite.each(
            database, sql: "SELECT data FROM trajectory_metadata_blob LIMIT 1"
        ) { statement in
            guard
                let blob = AgentSQLite.data(statement, column: 0),
                let message = AntigravityWire.decode(blob)
            else { return }

            anchor.createdAt = Self.timestamp(AntigravityWire.nested(message, 2))
            if let folder = AntigravityWire.nested(message, 1),
               let uri = folder.string(1) {
                anchor.workspace = Self.path(fromURI: uri)
            }
        }
        return anchor
    }

    private static func stepTimestamps(_ database: OpaquePointer) -> Steps {
        var steps = Steps()
        AgentSQLite.each(
            database, sql: "SELECT metadata FROM steps WHERE step_type = 15"
        ) { statement in
            guard
                let blob = AgentSQLite.data(statement, column: 0),
                let message = AntigravityWire.decode(blob),
                let timestamp = Self.timestamp(AntigravityWire.nested(message, 1))
            else { return }

            if let response = AntigravityWire.nested(message, 9)?.string(11) {
                steps.byResponse[response] = timestamp
            }
            if let index = AntigravityWire.nested(message, 20)?[3]?.varint {
                steps.byIndex[Int(index)] = timestamp
            }
        }
        return steps
    }

    private static func generations(_ database: OpaquePointer) -> [Generation] {
        var generations: [Generation] = []
        AgentSQLite.each(
            database, sql: "SELECT idx, data FROM gen_metadata ORDER BY idx"
        ) { statement in
            guard
                let index = DatabaseReaderSupport.intColumn(statement, 0),
                let blob = AgentSQLite.data(statement, column: 1),
                let message = AntigravityWire.decode(blob),
                let chat = AntigravityWire.nested(message, 1)
            else { return }

            var generation = Generation(index: index)
            generation.model = chat.string(19)
            generation.label = chat.string(21)

            generation.explicitTimestamp = Self.timestamp(
                AntigravityWire.nested(AntigravityWire.nested(chat, 9), 4)
            )

            if let usage = AntigravityWire.nested(chat, 4) {
                var parsed = Usage()
                parsed.fresh = Int(clamping: usage[2]?.varint ?? 0)
                parsed.cacheRead = Int(clamping: usage[5]?.varint ?? 0)
                parsed.output = Int(clamping: usage[9]?.varint ?? 0)
                parsed.reasoning = Int(clamping: usage[10]?.varint ?? 0)
                parsed.responseID = usage.string(11)
                generation.usage = parsed
            }
            generations.append(generation)
        }
        return generations
    }

    // MARK: - Fields

    /// A `{#1 seconds, #2 nanos}` timestamp. A non-positive or absurd seconds
    /// value is not a time.
    private static func timestamp(_ message: AntigravityWire.Message?) -> Date? {
        guard let seconds = message?[1]?.varint, seconds > 0, seconds < 1_000_000_000_000
        else { return nil }
        let nanos = message?[2]?.varint ?? 0
        return Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1_000_000_000)
    }

    /// A `file://` URI as a path, or the string unchanged when it is not one.
    private static func path(fromURI uri: String) -> String? {
        if let url = URL(string: uri), url.isFileURL { return url.path }
        return uri
    }

    /// The model identity, preferring the machine id, then a sibling row's id
    /// recovered through the display label, then the file's single model, then
    /// a verified label table, then the routing label itself.
    ///
    /// **No vendor default is invented.** A file that names no model at all
    /// falls back to `unknown`, an unpriced name, rather than to a concrete
    /// product model that would be priced at the wrong rate.
    private static func resolvedModel(
        _ generation: Generation,
        labels: [String: Set<String>],
        sole: String?
    ) -> String {
        if let model = generation.model, model != routingLabel { return model }
        if let label = generation.label, let models = labels[label], models.count == 1,
           let only = models.first {
            return only
        }
        if let sole { return sole }
        if let label = generation.label, let mapped = labelTable[label] { return mapped }
        return generation.model ?? "unknown"
    }

    /// Labels whose model identity is verified. Server-supplied and
    /// localisable, so an unknown label is never guessed at.
    private static let labelTable: [String: String] = [
        "Gemini 3.5 Flash (Low)": "gemini-3.5-flash-extra-low",
        "Gemini 3.5 Flash (Medium)": "gemini-3.5-flash-medium",
        "Gemini 3.5 Flash (High)": "gemini-3.5-flash-high",
    ]
}

/// A minimal, bounds-checked protobuf wire decoder.
///
/// Only the wire format itself is implemented — tags, the three scalar wire
/// types and length-delimited bytes — because the message schemas differ per
/// client and none of their `.proto` files ship. Unknown field numbers are
/// kept; an unsupported wire type (the group types) or any malformed byte
/// **fails the whole message** rather than returning a partial one, so a
/// caller never reads a truncated field as a value.
///
/// Internal rather than private so a test can drive the wire rules directly,
/// including overlong varints and lengths that run past the buffer.
enum AntigravityWire {
    // MARK: - Values

    enum Value: Equatable {
        case varint(UInt64)
        case fixed64(UInt64)
        case length([UInt8])
        case fixed32(UInt32)

        var varint: UInt64? {
            if case .varint(let value) = self { return value }
            return nil
        }

        var fixed64: UInt64? {
            if case .fixed64(let value) = self { return value }
            return nil
        }

        var bytes: [UInt8]? {
            if case .length(let value) = self { return value }
            return nil
        }
    }

    // MARK: - Messages

    struct Message: Equatable {
        private(set) var fields: [Int: [Value]] = [:]

        /// The first value of a field, if it has one.
        subscript(number: Int) -> Value? { fields[number]?.first }

        /// Every value of a repeated field.
        func all(_ number: Int) -> [Value] { fields[number] ?? [] }

        /// A length-delimited field as a UTF-8 string.
        func string(_ number: Int) -> String? {
            guard let bytes = self[number]?.bytes else { return nil }
            let text = String(bytes: bytes, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }

        mutating func append(_ value: Value, to number: Int) {
            fields[number, default: []].append(value)
        }
    }

    /// A length-delimited field decoded as a nested message, or nil when it is
    /// another wire type or not a valid message.
    static func nested(_ message: Message?, _ number: Int) -> Message? {
        guard let bytes = message?[number]?.bytes else { return nil }
        return decode(bytes)
    }

    // MARK: - Decoding

    static func decode(_ data: Data) -> Message? { decode(Array(data)) }

    static func decode(_ bytes: [UInt8]) -> Message? {
        var reader = ByteReader(bytes: bytes)
        var message = Message()
        while !reader.isAtEnd {
            guard let (number, value) = reader.next() else { return nil }
            message.append(value, to: number)
        }
        return message
    }

    /// A forward cursor over a buffer. Every read is bounds-checked and every
    /// failure returns nil rather than trapping.
    struct ByteReader {
        let bytes: [UInt8]
        private(set) var index = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        var isAtEnd: Bool { index >= bytes.count }

        mutating func next() -> (Int, Value)? {
            guard let tag = varint() else { return nil }
            let number = Int(tag >> 3)
            // Field zero is not a field.
            guard number > 0 else { return nil }

            switch tag & 7 {
            case 0:
                guard let value = varint() else { return nil }
                return (number, .varint(value))
            case 1:
                guard let value = fixed64() else { return nil }
                return (number, .fixed64(value))
            case 2:
                guard let length = varint(), length <= UInt64(bytes.count - index) else {
                    return nil
                }
                let end = index + Int(length)
                let slice = Array(bytes[index..<end])
                index = end
                return (number, .length(slice))
            case 5:
                guard let value = fixed32() else { return nil }
                return (number, .fixed32(value))
            default:
                // Wire types 3 and 4 are the deprecated groups.
                return nil
            }
        }

        /// A base-128 varint, refused past ten bytes or when the tenth would
        /// overflow.
        private mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            for _ in 0..<10 {
                guard index < bytes.count else { return nil }
                let byte = bytes[index]
                index += 1
                if shift == 63 && byte > 1 { return nil }
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }

        private mutating func fixed64() -> UInt64? {
            guard bytes.count - index >= 8 else { return nil }
            var value: UInt64 = 0
            for offset in 0..<8 {
                value |= UInt64(bytes[index + offset]) << (8 * UInt64(offset))
            }
            index += 8
            return value
        }

        private mutating func fixed32() -> UInt32? {
            guard bytes.count - index >= 4 else { return nil }
            var value: UInt32 = 0
            for offset in 0..<4 {
                value |= UInt32(bytes[index + offset]) << (8 * UInt32(offset))
            }
            index += 4
            return value
        }
    }
}
