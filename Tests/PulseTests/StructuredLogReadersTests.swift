import Foundation
import Testing
@testable import Pulse

/// Group D's structured-log readers, driven only from fresh temporary stores
/// that this file writes itself. No test touches the user's home, and no fixture
/// is copied from another project: every JSON document, log line and zstd frame
/// is built here.
///
/// The point is the boundary, not the parsing alone: each client must produce
/// records that a real `AgentUsageLedger.build` can price, and a store that says
/// nothing must produce nothing rather than a zero.
@Suite("Structured log readers")
struct StructuredLogReadersTests {
    // MARK: - Harness

    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private static let prices: [String: ModelPrice] = [
        "priced": ModelPrice(
            input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "Priced"
        ),
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeStore() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pulse-d-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func write(_ object: Any, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
    }

    private func writeLines(_ rows: [[String: Any]], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var text = ""
        for row in rows {
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            text += String(decoding: data, as: UTF8.self) + "\n"
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func records(_ client: String, _ roots: [URL]) -> [AgentUsageRecord] {
        StructuredLogReaders.records(client: client, roots: roots)
    }

    private func build(
        _ records: [AgentUsageRecord],
        namespace: String = SpendAgent.openCode.rawValue
    ) -> UsageLedger {
        AgentUsageLedger.build(
            records, prices: Self.prices, namespace: namespace, calendar: Self.calendar
        )
    }

    /// A zstd frame with a single uncompressed (raw) block, built from the
    /// published frame format so the test carries no third-party bytes.
    private func zstdFrame(_ payload: Data) -> Data {
        var frame = Data([0x28, 0xB5, 0x2F, 0xFD])
        let count = payload.count
        if count < 256 {
            frame.append(0x20)
            frame.append(UInt8(count))
        } else {
            // Single segment, two-byte frame content size.
            frame.append(0x60)
            frame.append(UInt8(count & 0xFF))
            frame.append(UInt8((count >> 8) & 0xFF))
        }
        let header = UInt32(1) | (UInt32(count) << 3)
        frame.append(UInt8(header & 0xFF))
        frame.append(UInt8((header >> 8) & 0xFF))
        frame.append(UInt8((header >> 16) & 0xFF))
        frame.append(payload)
        return frame
    }

    /// A structurally valid frame with a deliberately wrong checksum, so a
    /// decoder produces the block and then reports an explicit zstd error.
    private func checksumMismatchFrame(_ payload: Data) -> Data {
        var frame = Data([0x28, 0xB5, 0x2F, 0xFD, 0x24, UInt8(payload.count)])
        let header = UInt32(1) | (UInt32(payload.count) << 3)
        frame.append(UInt8(header & 0xFF))
        frame.append(UInt8((header >> 8) & 0xFF))
        frame.append(UInt8((header >> 16) & 0xFF))
        frame.append(payload)
        frame.append(contentsOf: [0, 0, 0, 0])
        return frame
    }

    // MARK: - Catalog

    @Test("The catalog names exactly the group D clients and dispatch is complete")
    func catalog() {
        #expect(StructuredLogReaders.supportedClients == Set([
            "mux", "codebuff", "freebuff", "jcode", "augment",
            "gjc", "junie", "dsh", "fx", "lmstudio", "reasonix",
        ]))

        let empty = URL(fileURLWithPath: "/nonexistent-pulse-store")
        for client in StructuredLogReaders.supportedClients {
            let inputs = StructuredLogReaders.inputs(client: client, home: empty, environment: [:])
            #expect(!inputs.isEmpty, "\(client) must name its store")
            #expect(records(client, []).isEmpty)
        }
        #expect(records("not-a-client", []).isEmpty)
    }

    @Test("Environment overrides replace the default macOS roots")
    func environmentOverrides() {
        let home = URL(fileURLWithPath: "/Users/nobody")

        func paths(_ client: String, _ environment: [String: String]) -> [String] {
            StructuredLogReaders.inputs(client: client, home: home, environment: environment)
                .map(\.path)
        }

        #expect(paths("codebuff", ["CODEBUFF_DATA_DIR": "/tmp/custom-codebuff"]) == ["/tmp/custom-codebuff"])
        #expect(paths("codebuff", [:]).count == 3)
        #expect(paths("jcode", ["JCODE_HOME": "/tmp/jcode"]) == ["/tmp/jcode/sessions"])
        #expect(paths("dsh", ["DSH_HOME": "/tmp/dsh"]) == ["/tmp/dsh/sessions"])
        #expect(paths("reasonix", ["REASONIX_HOME": "/tmp/rx"]) == ["/tmp/rx/stats"])
        #expect(paths("reasonix", ["REASONIX_STATE_HOME": "/tmp/rx-state"]) == ["/tmp/rx-state"])
        // Gajae Code always watches the XDG data tree, with its default
        // spelling when the variable is unset.
        #expect(paths("gjc", ["XDG_DATA_HOME": "/tmp/xdg"]).contains("/tmp/xdg/gjc/sessions"))
        #expect(paths("gjc", [:]).contains("/Users/nobody/.local/share/gjc/sessions"))
    }

    // MARK: - Reasoning against Pulse's output bucket

    @Test("A reasoning count that is inside output is never added to the total")
    func reasoningSubsetIsNotAdded() {
        // T = I + O with R ⊆ O must stay I + O, never become I + O + R.
        let output = StructuredLogSupport.output(
            reported: 100, reasoning: 30, relationship: .includedInOutput
        )
        #expect(output == 100)

        // The opposite, confirmed case: an output figure that does not contain
        // reasoning gains it exactly once.
        #expect(StructuredLogSupport.output(
            reported: 100, reasoning: 30, relationship: .independent
        ) == 130)

        // Unknown: not added and not carried, because there is no total here to
        // place it and adding would double it if it is already inside.
        #expect(StructuredLogSupport.output(
            reported: 100, reasoning: 30, relationship: .unknown
        ) == 100)
    }

    @Test("A reported total is what places an ambiguous remainder, and only then")
    func ambiguousRemainderNeedsATotal() {
        #expect(StructuredLogSupport.unclassifiedRemainder(reportedTotal: 130, classified: 100) == 30)
        #expect(StructuredLogSupport.unclassifiedRemainder(reportedTotal: 100, classified: 100) == 0)
        // No total is no guess: the classified kinds stay as they are.
        #expect(StructuredLogSupport.unclassifiedRemainder(reportedTotal: nil, classified: 100) == 0)
    }

    // MARK: - mux

    @Test("Mux reads one aggregate record per model and marks the timing aggregate")
    func mux() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "mux", home: home, environment: [:])
        let file = roots[0].appending(path: "workspace-1/session-usage.json")
        try write(
            [
                "version": 1,
                "byModel": [
                    "anthropic:claude": [
                        "input": ["tokens": 100],
                        "cached": ["tokens": 40],
                        "cacheCreate": ["tokens": 10],
                        "output": ["tokens": 50],
                        "reasoning": ["tokens": 7],
                    ],
                    "openai:gpt": [
                        "input": ["tokens": 5],
                        "output": ["tokens": 6],
                    ],
                ],
                "lastRequest": ["model": "claude", "timestamp": 1_700_000_000_000],
            ],
            to: file
        )

        let decoded = records("mux", roots)
        #expect(decoded.count == 2)
        #expect(decoded.allSatisfy { $0.isAggregate })
        #expect(decoded.allSatisfy { $0.timestamp == Self.fixedNow })

        let claude = try #require(decoded.first { $0.model == "claude" })
        #expect(claude.tally == TokenTally(input: 100, cacheWrite: 10, cacheRead: 40, output: 50))
        // No token total exists, so the separate reasoning figure is not added
        // to output and not carried as unknown either; the record is partial
        // because that reasoning was reported but not placed.
        #expect(claude.unclassifiedTokens == 0)
        #expect(claude.isPartial)
        #expect(claude.sessionID == "workspace-1")
        #expect(claude.deduplicationID == "mux:workspace-1:anthropic:claude")

        // A model that reported no reasoning is complete.
        let gpt = try #require(decoded.first { $0.model == "gpt" })
        #expect(!gpt.isPartial)

        // Through the builder: reasoning is not counted at all, and the
        // aggregate session keeps no buckets.
        let ledger = build(decoded)
        #expect(ledger.hasAggregateTiming)
        #expect(ledger.hasPartialCounts)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 211)
        #expect(ledger.days.allSatisfy { $0.modelUnclassifiedTokens.isEmpty })
        #expect(ledger.sessions.first?.slots.isEmpty == true)
    }

    @Test("A mux session with no real timestamp is skipped, not dated from its file")
    func muxWithoutTimestamp() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "mux", home: home, environment: [:])
        try write(
            ["byModel": ["anthropic:claude": ["input": ["tokens": 1]]]],
            to: roots[0].appending(path: "ws/session-usage.json")
        )
        #expect(records("mux", roots).isEmpty)

        // A zero timestamp is unset too, not 1970-01-01.
        try write(
            [
                "byModel": ["anthropic:claude": ["input": ["tokens": 1]]],
                "lastRequest": ["model": "claude", "timestamp": 0],
            ],
            to: roots[0].appending(path: "ws2/session-usage.json")
        )
        #expect(records("mux", roots).isEmpty)
    }

    // MARK: - codebuff

    @Test("Codebuff merges usage spelling variants and keeps the path identity")
    func codebuff() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "codebuff", home: home, environment: [:])
        let chatID = "2024-01-02T03-04-05.000Z"
        let file = roots[0].appending(
            path: "projects/ring/chats/\(chatID)/chat-messages.json"
        )
        try write(
            [
                [
                    "id": "m1",
                    "role": "assistant",
                    "timestamp": "2024-01-02T03:04:06Z",
                    "metadata": [
                        "model": "claude-sonnet",
                        "usage": [
                            "input_tokens": 100,
                            "output_tokens": 20,
                            "cache_read_input_tokens": 30,
                            "promptTokensDetails": ["cachedTokens": 0],
                        ],
                    ],
                ],
                [
                    "id": "u1",
                    "role": "user",
                    "content": "hi",
                ],
            ],
            to: file
        )

        let decoded = records("codebuff", roots)
        #expect(decoded.count == 1)
        let record = try #require(decoded.first)
        #expect(record.model == "claude-sonnet")
        #expect(record.tally == TokenTally(input: 100, cacheWrite: 0, cacheRead: 30, output: 20))
        #expect(record.sessionID == "manicode/ring/\(chatID)")
        #expect(record.deduplicationID == "codebuff:manicode/ring/\(chatID):m1")
        #expect(record.timestamp == AgentLogIO.timestamp("2024-01-02T03:04:06Z"))
    }

    @Test("Codebuff falls back to the run-state history and restores the chat id")
    func codebuffHistoryFallback() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "codebuff", home: home, environment: [:])
        let chatID = "2024-05-06T07-08-09Z"
        try write(
            [
                [
                    "id": "m2",
                    "variant": "ai",
                    // Zero is unset, so the chat id's own ISO date is used.
                    "timestamp": 0,
                    "metadata": [
                        "runState": [
                            "sessionState": [
                                "mainAgentState": [
                                    "messageHistory": [
                                        [
                                            "providerOptions": [
                                                "codebuff": [
                                                    "model": "gpt-x",
                                                    "usage": ["prompt_tokens": 11, "completion_tokens": 4],
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ],
                ]
            ],
            to: roots[0].appending(path: "projects/p/chats/\(chatID)/chat-messages.json")
        )

        let record = try #require(records("codebuff", roots).first)
        #expect(record.model == "gpt-x")
        #expect(record.tally == TokenTally(input: 11, output: 4))
        #expect(record.timestamp == AgentLogIO.timestamp("2024-05-06T07:08:09Z"))
    }

    @Test("Malformed chat JSON yields nothing")
    func codebuffBadJSON() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "codebuff", home: home, environment: [:])
        try writeText("not json at all", to: roots[0].appending(path: "projects/p/chats/c/chat-messages.json"))
        #expect(records("codebuff", roots).isEmpty)
    }

    // MARK: - freebuff

    @Test("Freebuff reports no counters, so it emits nothing and says why")
    func freebuff() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "freebuff", home: home, environment: [:])
        let chatID = "2024-03-04T05-06-07Z"
        try write(
            [
                [
                    "role": "assistant",
                    "metadata": [
                        "runState": [
                            "sessionState": [
                                "mainAgentState": ["agentType": "base2-free-lite"]
                            ]
                        ]
                    ],
                ]
            ],
            to: roots[0].appending(path: "projects/p/chats/\(chatID)/chat-messages.json")
        )

        #expect(records("freebuff", roots).isEmpty)
        #expect(!FreebuffUsageReader.limitation.isEmpty)
        #expect(!StructuredLogReaders.notes(client: "freebuff", roots: roots).isEmpty)
    }

    // MARK: - jcode

    @Test("Jcode merges the journal and decides cache shape from the usage object")
    func jcode() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(
            client: "jcode", home: home, environment: ["JCODE_HOME": home.path]
        )
        let session = roots[0].appending(path: "session_a.json")
        try write(
            [
                "id": "sess-a",
                "provider_key": "anthropic",
                "model": "claude",
                "working_dir": "/Users/me/Code/ring",
                "messages": [
                    [
                        "id": "n1",
                        "role": "assistant",
                        "timestamp": "2024-01-02T03:04:05Z",
                        "token_usage": [
                            "input_tokens": 100,
                            "output_tokens": 20,
                            "cache_read_input_tokens": 30,
                            "cache_creation_input_tokens": 0,
                            "reasoning_output_tokens": 5,
                        ],
                    ]
                ],
            ],
            to: session
        )
        try writeLines(
            [
                [
                    "meta": ["model": "claude-3"],
                    "append_messages": [
                        [
                            "id": "t1",
                            "role": "assistant",
                            "timestamp": "2024-01-02T03:05:05Z",
                            "token_usage": ["input_tokens": 50, "output_tokens": 10],
                        ]
                    ],
                ]
            ],
            to: roots[0].appending(path: "session_a.journal.jsonl")
        )

        let decoded = records("jcode", roots)
        #expect(decoded.count == 2)

        // Anthropic-style: the cache-creation key makes input cache-exclusive.
        let first = try #require(decoded.first { $0.deduplicationID?.contains(":n1") == true })
        #expect(first.model == "claude")
        #expect(first.tally == TokenTally(input: 100, cacheRead: 30, output: 20))
        // Reasoning is not added to output and not carried as unknown, but the
        // record is partial because it was reported and not placed.
        #expect(first.unclassifiedTokens == 0)
        #expect(first.isPartial)
        #expect(first.project == "/Users/me/Code/ring")

        // A journal row with no cache and no reasoning is complete.
        let second = try #require(decoded.first { $0.deduplicationID?.contains(":t1") == true })
        #expect(second.model == "claude-3")
        #expect(second.tally == TokenTally(input: 50, output: 10))
        #expect(!second.isPartial)
    }

    @Test("Jcode settles the cache shape only from explicit schema markers")
    func jcodeCacheShapeIsSchemaDriven() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(
            client: "jcode", home: home, environment: ["JCODE_HOME": home.path]
        )
        // Same magnitudes throughout; only the schema differs.
        let noCache: [String: Any] = [
            "id": "none",
            "role": "assistant",
            "timestamp": "2024-01-02T03:04:07Z",
            "token_usage": ["input_tokens": 50, "output_tokens": 1],
        ]
        let anthropic: [String: Any] = [
            "id": "anthropic",
            "role": "assistant",
            "timestamp": "2024-01-02T03:04:05Z",
            "token_usage": [
                "input_tokens": 100, "output_tokens": 1,
                "cache_read_input_tokens": 30, "cache_creation_input_tokens": 0,
            ],
        ]
        let openAI: [String: Any] = [
            "id": "openai",
            "role": "assistant",
            "timestamp": "2024-01-02T03:04:06Z",
            "token_usage": [
                "input_tokens": 100, "output_tokens": 1, "cache_read_input_tokens": 30,
                "prompt_tokens_details": ["cached_tokens": 30],
            ],
        ]
        let ambiguous: [String: Any] = [
            "id": "ambiguous",
            "role": "assistant",
            "timestamp": "2024-01-02T03:04:08Z",
            "token_usage": [
                "input_tokens": 100, "output_tokens": 1, "cache_read_input_tokens": 30,
            ],
        ]
        try write(
            ["id": "s", "model": "m", "messages": [noCache, anthropic, openAI, ambiguous]],
            to: roots[0].appending(path: "session_shape.json")
        )

        let decoded = records("jcode", roots)
        func record(_ id: String) throws -> AgentUsageRecord {
            try #require(decoded.first { $0.deduplicationID?.contains(":\(id)") == true })
        }

        // No cache in play: the input is fresh and the record is complete.
        let none = try record("none")
        #expect(none.tally == TokenTally(input: 50, output: 1))
        #expect(!none.isPartial)

        // Anthropic marker: input is cache-exclusive.
        let anthropicRecord = try record("anthropic")
        #expect(anthropicRecord.tally == TokenTally(input: 100, cacheRead: 30, output: 1))
        #expect(!anthropicRecord.isPartial)

        // OpenAI-native details: the cache is a subset of input.
        let openAIRecord = try record("openai")
        #expect(openAIRecord.tally == TokenTally(input: 70, cacheRead: 30, output: 1))
        #expect(!openAIRecord.isPartial)

        // Positive cache with neither marker: the input is not priced as fresh.
        let ambiguousRecord = try record("ambiguous")
        #expect(ambiguousRecord.tally == TokenTally(output: 1))
        #expect(ambiguousRecord.unclassifiedTokens == 100)
        #expect(ambiguousRecord.isPartial)
    }

    @Test("Jcode folds a message replayed through the journal")
    func jcodeJournalReplayCollapses() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(
            client: "jcode", home: home, environment: ["JCODE_HOME": home.path]
        )
        let message: [String: Any] = [
            "id": "n1",
            "role": "assistant",
            "timestamp": "2024-01-02T03:04:05Z",
            "token_usage": ["input_tokens": 100, "output_tokens": 20],
        ]
        try write(
            ["id": "s", "model": "claude", "messages": [message]],
            to: roots[0].appending(path: "session_b.json")
        )
        try writeLines(
            [["meta": [:], "append_messages": [message]]],
            to: roots[0].appending(path: "session_b.journal.jsonl")
        )

        let ledger = build(records("jcode", roots))
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 120)
    }

    // MARK: - augment

    @Test("Augment counts completed turns only, taking the last non-empty usage")
    func augment() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "augment", home: home, environment: [:])
        try write(
            [
                "sessionId": "aug-1",
                "agentState": ["modelId": "default-model"],
                "chatHistory": [
                    [
                        "finishedAt": "2024-01-02T03:04:05Z",
                        "completed": true,
                        "sequenceId": 1,
                        "exchange": [
                            "model_id": "claude",
                            "request_id": "r1",
                            "response_nodes": [
                                ["token_usage": ["input_tokens": 10, "output_tokens": 1]],
                                ["token_usage": ["input_tokens": 100, "output_tokens": 20]],
                            ],
                        ],
                    ],
                    [
                        "finishedAt": "2024-01-02T03:10:00Z",
                        "completed": false,
                        "sequenceId": 2,
                        "exchange": [
                            "request_id": "r2",
                            "response_nodes": [
                                ["token_usage": ["input_tokens": 999, "output_tokens": 999]]
                            ],
                        ],
                    ],
                ],
            ],
            to: roots[0].appending(path: "aug-1.json")
        )

        let decoded = records("augment", roots)
        #expect(decoded.count == 1)
        let record = try #require(decoded.first)
        // The last node wins; the partial first node is not added.
        #expect(record.tally == TokenTally(input: 100, output: 20))
        #expect(record.model == "claude")
        #expect(record.deduplicationID == "augment:aug-1:r1")
        #expect(record.timestamp == AgentLogIO.timestamp("2024-01-02T03:04:05Z"))
    }

    // MARK: - gjc

    @Test("Gajae Code reads assistant messages and ignores service events")
    func gjc() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "gjc", home: home, environment: [:])
        try writeLines(
            [
                ["type": "session", "id": "g1", "timestamp": "2024-01-02T00:00:00Z", "cwd": "/Users/me/Code/work"],
                ["type": "service_tier_change", "id": "x"],
                [
                    "type": "message",
                    "id": "e1",
                    "message": [
                        "role": "assistant",
                        "model": "gpt-5",
                        "provider": "openai",
                        "timestamp": 1_700_000_000_000,
                        "usage": [
                            "input": 10, "output": 5, "cacheRead": 2, "cacheWrite": 1,
                            "totalTokens": 18,
                            "cost": ["total": 0.5],
                        ],
                    ],
                ],
                ["type": "message", "id": "e2", "message": ["role": "user", "content": "hi"]],
            ],
            to: roots[0].appending(path: "proj/session.jsonl")
        )

        let decoded = records("gjc", roots)
        #expect(decoded.count == 1)
        let record = try #require(decoded.first)
        #expect(record.model == "gpt-5")
        #expect(record.tally == TokenTally(input: 10, cacheWrite: 1, cacheRead: 2, output: 5))
        #expect(record.project == "/Users/me/Code/work")
        #expect(record.sessionID == "g1")
        #expect(record.deduplicationID == "gjc:g1:e1")
    }

    @Test("Gajae Code counts two id-less rows with identical values as two requests")
    func gjcMissingIDKeepsBothRequests() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "gjc", home: home, environment: [:])
        // Same second, same model, same counts, no id: two real calls, and
        // nothing on disk says otherwise. A value hash would wrongly drop one.
        let message: [String: Any] = [
            "type": "message",
            "message": [
                "role": "assistant",
                "model": "gpt-5",
                "provider": "openai",
                "timestamp": 1_700_000_000_000,
                "usage": ["input": 10, "output": 5],
            ],
        ]
        try writeLines(
            [["type": "session", "id": "g1", "cwd": "/w"], message, message],
            to: roots[0].appending(path: "slug/session.jsonl")
        )

        let decoded = records("gjc", roots)
        #expect(decoded.count == 2)
        #expect(decoded.allSatisfy { $0.deduplicationID == nil })
        let ledger = build(decoded)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 30)
    }

    @Test("Gajae Code folds an explicit-id replay to one request")
    func gjcExplicitIDReplayCountsOnce() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "gjc", home: home, environment: [:])
        let message: [String: Any] = [
            "type": "message",
            "id": "e1",
            "message": [
                "role": "assistant",
                "model": "gpt-5",
                "provider": "openai",
                "timestamp": 1_700_000_000_000,
                "usage": ["input": 10, "output": 5],
            ],
        ]
        try writeLines(
            [["type": "session", "id": "g1", "cwd": "/w"], message, message],
            to: roots[0].appending(path: "slug/session.jsonl")
        )

        let decoded = records("gjc", roots)
        #expect(decoded.count == 2)
        let ledger = build(decoded)
        // The same entry id is one request, however often it was written.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 15)
    }

    @Test("Gajae Code reads a complete mirror file once, by session and file identity")
    func gjcMirrorFileReadOnce() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "gjc", home: home, environment: [:])
        let rows: [[String: Any]] = [
            ["type": "session", "id": "g1", "cwd": "/w"],
            [
                "type": "message",
                "message": [
                    "role": "assistant",
                    "model": "gpt-5",
                    "provider": "openai",
                    "timestamp": 1_700_000_000_000,
                    "usage": ["input": 10, "output": 5],
                ],
            ],
        ]
        // Same session id and the same file name at two depths: one mirror.
        try writeLines(rows, to: roots[0].appending(path: "slug/session.jsonl"))
        try writeLines(rows, to: roots[0].appending(path: "slug/deep/session.jsonl"))

        let decoded = records("gjc", roots)
        #expect(decoded.count == 1)
        #expect(build(decoded).days.reduce(0) { $0 + $1.tokens } == 15)
    }

    @Test("Gajae Code parses a same-named file with extra requests instead of dropping it")
    func gjcDifferentContentSameNameIsNotDropped() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "gjc", home: home, environment: [:])
        let header: [String: Any] = ["type": "session", "id": "g1", "cwd": "/Users/me/Code/w"]
        let e1: [String: Any] = [
            "type": "message", "id": "e1",
            "message": [
                "role": "assistant", "model": "gpt-5", "provider": "openai",
                "timestamp": 1_700_000_000_000, "usage": ["input": 10, "output": 5],
            ],
        ]
        let e2: [String: Any] = [
            "type": "message", "id": "e2",
            "message": [
                "role": "assistant", "model": "gpt-5", "provider": "openai",
                "timestamp": 1_700_000_001_000, "usage": ["input": 7, "output": 3],
            ],
        ]
        // Same session id and file name, but the deeper file is a fuller record,
        // not a mirror: it must be parsed so e2 is not lost.
        try writeLines([header, e1], to: roots[0].appending(path: "g1/session.jsonl"))
        try writeLines([header, e1, e2], to: roots[0].appending(path: "g1/deep/session.jsonl"))

        let decoded = records("gjc", roots)
        #expect(decoded.count == 3)
        #expect(decoded.contains { $0.deduplicationID == "gjc:g1:e2" })
        // e1 folds across the two files by its real entry id; e2 is counted.
        let ledger = build(decoded)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 25)
    }

    @Test("A zero Gajae Code message time falls back to the envelope's time")
    func gjcZeroMessageTimeFallsBack() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "gjc", home: home, environment: [:])
        let message: [String: Any] = [
            "type": "message", "id": "e1",
            "message": [
                "role": "assistant", "model": "gpt-5", "provider": "openai",
                "timestamp": 0, "usage": ["input": 10, "output": 5],
            ],
        ]
        let withEnvelopeTime: [String: Any] = [
            "type": "message", "id": "e1", "timestamp": "2024-01-02T03:04:05Z",
            "message": message["message"]!,
        ]
        try writeLines(
            [["type": "session", "id": "g1", "cwd": "/w"], withEnvelopeTime],
            to: roots[0].appending(path: "with-time/session.jsonl")
        )
        // Only zero, and no envelope time: no record rather than 1970.
        try writeLines(
            [["type": "session", "id": "g2", "cwd": "/w"], message],
            to: roots[0].appending(path: "only-zero/session.jsonl")
        )

        let decoded = records("gjc", roots)
        let record = try #require(decoded.first { $0.sessionID == "g1" })
        #expect(record.timestamp == AgentLogIO.timestamp("2024-01-02T03:04:05Z"))
        #expect(!decoded.contains { $0.sessionID == "g2" })
    }

    // MARK: - junie

    @Test("Junie anchors a usage row at its start and reads each model row")
    func junie() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "junie", home: home, environment: [:])
        try writeLines(
            [
                [
                    "timestampMs": 1_700_000_000_000,
                    "kind": "UserPromptEvent",
                    "event": ["agentEvent": ["kind": "UserPromptEvent"]],
                ],
                [
                    "timestampMs": 1_700_000_010_000,
                    "kind": "AgentEvent",
                    "event": [
                        "agentEvent": [
                            "kind": "LlmResponseMetadataEvent",
                            "agent": ["name": "junie"],
                            "modelUsage": [
                                [
                                    "model": "claude",
                                    "time": 2000,
                                    "inputTokens": 100,
                                    "outputTokens": 30,
                                    "cacheInputTokens": 10,
                                    "reasoningTokens": 5,
                                    "cost": 0.25,
                                ],
                                ["model": "gpt", "input": 7, "output": 3],
                            ],
                        ]
                    ],
                ],
            ],
            to: roots[0].appending(path: "session-240102-030405/events.jsonl")
        )

        let decoded = records("junie", roots)
        #expect(decoded.count == 2)
        let claude = try #require(decoded.first { $0.model == "claude" })
        #expect(claude.tally == TokenTally(input: 100, cacheRead: 10, output: 30))
        // Reasoning sits beside output with no total, so it is not added; the
        // record is partial because it was reported and not placed.
        #expect(claude.unclassifiedTokens == 0)
        #expect(claude.isPartial)
        let gpt = try #require(decoded.first { $0.model == "gpt" })
        #expect(!gpt.isPartial)
        // 1_700_000_010 s minus the 2 s latency is the call's start.
        #expect(claude.timestamp == Date(timeIntervalSince1970: 1_700_000_008))
        #expect(claude.sessionID == "session-240102-030405")
    }

    @Test("A zero Junie time falls back to the session id, and bare zeros emit nothing")
    func junieZeroTimeFallback() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "junie", home: home, environment: [:])
        // `timestampMs` 0 is unset, not 1970, so the session id's own start is
        // the real time.
        try writeLines(
            [
                [
                    "timestampMs": 0,
                    "event": [
                        "agentEvent": [
                            "kind": "LlmResponseMetadataEvent",
                            "modelUsage": [["model": "claude", "inputTokens": 10, "outputTokens": 2]],
                        ]
                    ],
                ]
            ],
            to: roots[0].appending(path: "session-240102-030405/events.jsonl")
        )

        let record = try #require(records("junie", roots).first)
        let sessionStart = try #require(JunieUsageReader.sessionIDTime("session-240102-030405"))
        #expect(record.timestamp == sessionStart)

        // A latency that would place the start at or before the epoch keeps the
        // response end rather than inventing a pre-epoch time.
        let end = Date(timeIntervalSince1970: 1)
        #expect(JunieUsageReader.eventTime(end: end, latency: 5_000, fallback: nil) == end)

        // A session whose id carries no parseable start, with only a zero time,
        // is no record rather than 1970-01-01.
        let bare = try makeStore()
        defer { cleanup(bare) }
        let bareRoots = StructuredLogReaders.inputs(client: "junie", home: bare, environment: [:])
        try writeLines(
            [
                [
                    "timestampMs": 0,
                    "event": [
                        "agentEvent": [
                            "kind": "LlmResponseMetadataEvent",
                            "modelUsage": [["model": "claude", "inputTokens": 10, "outputTokens": 2]],
                        ]
                    ],
                ]
            ],
            to: bareRoots[0].appending(path: "no-stamp/events.jsonl")
        )
        #expect(records("junie", bareRoots).isEmpty)
    }

    // MARK: - dsh

    @Test("DeepSeek Harness reads plain JSONL, drops the seed prefix and folds a fork")
    func dshPlain() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(
            client: "dsh", home: home, environment: ["DSH_HOME": home.path]
        )
        try writeLines(
            [
                ["type": "session", "seq": 0, "id": "d1", "cwd": "/Users/me/Code/work", "seedLength": 3],
                [
                    "type": "assistant/message",
                    "seq": 1,
                    "time": 1_700_000_000_000,
                    "data": [
                        "usage": ["inputTokens": 999, "outputTokens": 999],
                        "message": ["id": "seed", "source": ["provider": "p", "model": "m"]],
                    ],
                ],
                ["type": "request/header", "seq": 4, "data": ["header": ["config": ["provider": "routed", "model": "routed-model"]]]],
                [
                    "type": "assistant/message",
                    "seq": 5,
                    "time": 1_700_000_005_000,
                    "data": [
                        "usage": [
                            "inputTokens": 100, "outputTokens": 40,
                            "cacheReadTokens": 10, "cacheWriteTokens": 5, "reasoningTokens": 8,
                        ],
                        "message": ["id": "call-1", "source": ["provider": "p", "model": "m"]],
                    ],
                ],
                [
                    "type": "compaction/summary",
                    "seq": 6,
                    "time": 1_700_000_006_000,
                    "data": [
                        "compactionId": "cmp-1",
                        "usage": ["inputTokens": 1, "outputTokens": 2],
                        "message": ["id": "summary", "source": ["provider": "p", "model": "m"]],
                    ],
                ],
            ],
            to: roots[0].appending(path: "encoded/d1/session.jsonl")
        )

        let decoded = records("dsh", roots)
        // The seed event (seq 1 < 3) is skipped; the other two are real calls.
        #expect(decoded.count == 2)

        let call = try #require(decoded.first { $0.deduplicationID?.contains("msg:call-1") == true })
        // reasoningTokens is a subset of outputTokens, so the reported 40 is
        // kept whole and reasoning is not subtracted or carried again.
        #expect(call.tally == TokenTally(input: 100, cacheWrite: 5, cacheRead: 10, output: 40))
        #expect(call.unclassifiedTokens == 0)
        // The relationship is stated, so the record is complete.
        #expect(!call.isPartial)
        #expect(call.sessionID == "d1")
        #expect(call.project == "/Users/me/Code/work")

        let summary = try #require(decoded.first { $0.deduplicationID?.contains("summary:cmp:cmp-1") == true })
        #expect(summary.tally == TokenTally(input: 1, output: 2))
    }

    @Test("DeepSeek Harness decodes zstd, and the compressed copy folds with the plain one")
    func dshCompressed() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(
            client: "dsh", home: home, environment: ["DSH_HOME": home.path]
        )
        let rows: [[String: Any]] = [
            ["type": "session", "seq": 0, "id": "d2", "cwd": "/w"],
            [
                "type": "assistant/message",
                "seq": 5,
                "time": 1_700_000_000_000,
                "data": [
                    "usage": ["inputTokens": 20, "outputTokens": 4],
                    "message": ["id": "c1", "source": ["provider": "p", "model": "m"]],
                ],
            ],
        ]
        let directory = roots[0].appending(path: "enc/d2")
        try writeLines(rows, to: directory.appending(path: "session.jsonl"))

        let plainText = rows.map { row in
            let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n") + "\n"
        try Data(zstdFrame(Data(plainText.utf8))).write(
            to: directory.appending(path: "session.jsonl.zstd")
        )

        if let limitation = DSHZstdDecoder.limitation {
            // The Mac cannot decode zstd: report it, do not read zero.
            #expect(!limitation.isEmpty)
            #expect(!StructuredLogReaders.notes(client: "dsh", roots: roots).isEmpty)
            return
        }

        // Raw frame round-trips through the system decoder.
        let decodedPayload = try DSHZstdDecoder.decode(zstdFrame(Data("{\"a\":1}\n".utf8)))
        #expect(decodedPayload == Data("{\"a\":1}\n".utf8))

        let decoded = records("dsh", roots)
        // Two records (one per spelling) both present...
        #expect(decoded.count == 2)
        // ...and the ledger folds them by call identity.
        let ledger = build(decoded)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 24)
    }

    @Test("A zstd error after a decoded prefix throws instead of keeping the prefix")
    func dshCorruptZstd() {
        // A valid raw block whose frame checksum is deliberately wrong. The
        // decoder produces the block, then reports an explicit zstd error;
        // that must throw rather than be accepted as a good prefix. On a host
        // with no local library it throws `unavailable`, which is also a
        // failure and never a silent zero.
        var frame = Data([0x28, 0xB5, 0x2F, 0xFD, 0x24, 5])
        let header = UInt32(1) | (UInt32(5) << 3)
        frame.append(contentsOf: [
            UInt8(header & 0xFF), UInt8((header >> 8) & 0xFF), UInt8((header >> 16) & 0xFF),
        ])
        frame.append(contentsOf: Array("hello".utf8))
        frame.append(contentsOf: [0, 0, 0, 0])

        #expect(throws: DSHZstdDecoder.Failure.self) {
            _ = try DSHZstdDecoder.decode(frame)
        }
    }

    @Test("A torn trailing frame keeps the complete frames before it")
    func dshTornTrailingFrame() throws {
        if DSHZstdDecoder.limitation != nil { return }

        let first = Data("{\"a\":1}\n".utf8)
        let second = Data("{\"b\":2}\n".utf8)
        // The second frame is cut in its header: the stream simply ends
        // mid-frame, which is a torn tail rather than corrupt data.
        var stream = zstdFrame(first)
        stream.append(Data(zstdFrame(second).prefix(6)))

        let decoded = try DSHZstdDecoder.decode(stream)
        // The complete first frame survives; the torn second contributes no
        // complete record and the JSONL reader drops any partial line.
        #expect(decoded.starts(with: first))
        let lines = String(decoding: decoded, as: UTF8.self).split(separator: "\n").map(String.init)
        #expect(!lines.contains("{\"b\":2}"))
    }

    @Test("DeepSeek Harness notes surface a compressed file that fails to decode")
    func dshNotesSurfaceCompressedFailures() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(
            client: "dsh", home: home, environment: ["DSH_HOME": home.path]
        )
        let directory = roots[0].appending(path: "enc/bad")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A zstd-magic file whose checksum is wrong. With a working library it
        // fails to decode; without one the library is missing. Either way the
        // store must be called out rather than read as a smaller figure.
        try checksumMismatchFrame(Data("{\"a\":1}\n".utf8)).write(
            to: directory.appending(path: "session.jsonl.zstd")
        )
        #expect(!StructuredLogReaders.notes(client: "dsh", roots: roots).isEmpty)

        // A plain JSONL that is malformed is not a compression failure.
        let plainHome = try makeStore()
        defer { cleanup(plainHome) }
        let plainRoots = StructuredLogReaders.inputs(
            client: "dsh", home: plainHome, environment: ["DSH_HOME": plainHome.path]
        )
        let plainDirectory = plainRoots[0].appending(path: "enc/plain")
        try FileManager.default.createDirectory(at: plainDirectory, withIntermediateDirectories: true)
        try "not json\n{ broken\n".write(
            to: plainDirectory.appending(path: "session.jsonl"), atomically: true, encoding: .utf8
        )
        #expect(StructuredLogReaders.notes(client: "dsh", roots: plainRoots).isEmpty)
    }

    @Test("A compressed transcript past the decode ceiling is a surfaced failure")
    func dshNotesSurfaceSizeLimit() {
        // A real frame, but the injected raw ceiling is smaller than it, so the
        // bound is hit before any decoding — no 64 MiB fixture, and no global
        // state to set. The same path `notes` uses decides it.
        let frame = zstdFrame(Data("x".utf8))
        switch DSHUsageReader.compressedFailure(frame, rawLimit: 0) {
        case .some(.tooLarge):
            break
        case let other:
            Issue.record("expected a size-limit failure, got \(String(describing: other))")
        }

        // With room to decode and a library present, the same frame is not a
        // failure. Without a library every frame is `unavailable`, so that host
        // cannot make this claim.
        if DSHZstdDecoder.limitation == nil {
            #expect(DSHUsageReader.compressedFailure(frame, rawLimit: 1 << 20) == nil)
        }

        // A plain, uncompressed payload is never reported as compression loss.
        #expect(DSHUsageReader.compressedFailure(Data("not json\n".utf8)) == nil)
    }

    // MARK: - fx

    @Test("Fx reads one aggregate record per model, with title and workspace sidecars")
    func fx() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "fx", home: home, environment: [:])
        let directory = roots[0].appending(path: "fx-1")
        try write(
            [
                "session_id": "fx-1",
                "snapshot": [
                    "input_tokens": 50, "output_tokens": 20,
                    "models": [
                        [
                            "model": "claude", "input_tokens": 100, "output_tokens": 30,
                            "cache_read_tokens": 10, "cache_write_tokens": 5,
                            "reasoning_tokens": 4,
                        ],
                        ["model": "gpt", "output_tokens": 7],
                    ],
                ],
            ],
            to: directory.appending(path: "usage-v2.json")
        )
        try write(
            ["updated_at_ms": 1_700_000_000_000, "workspace_root": "/Users/me/Code/fx"],
            to: directory.appending(path: "session.json")
        )
        try write(
            ["sessions": ["fx-1": ["title": "Fix the ring"]]],
            to: roots[0].appending(path: "index.json")
        )

        let decoded = records("fx", roots)
        #expect(decoded.count == 2)
        let claude = try #require(decoded.first { $0.model == "claude" })
        #expect(claude.tally == TokenTally(input: 100, cacheWrite: 5, cacheRead: 10, output: 30))
        // No token total, so the separate reasoning figure is not added; the
        // record is partial because it was reported and not placed.
        #expect(claude.unclassifiedTokens == 0)
        #expect(claude.isPartial)
        let gpt = try #require(decoded.first { $0.model == "gpt" })
        #expect(!gpt.isPartial)
        #expect(claude.title == "Fix the ring")
        #expect(claude.project == "/Users/me/Code/fx")
        #expect(claude.isAggregate)
        #expect(claude.deduplicationID == "fx:fx-1:claude")
    }

    @Test("Fx keeps an aggregate total even when no models are grouped")
    func fxUnknownAggregate() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "fx", home: home, environment: [:])
        let directory = roots[0].appending(path: "fx-2")
        try write(
            [
                "session_id": "fx-2",
                "snapshot": ["input_tokens": 12, "output_tokens": 3, "models": []],
            ],
            to: directory.appending(path: "usage-v2.json")
        )
        try write(["created_at_ms": 1_700_000_000_000], to: directory.appending(path: "session.json"))

        let record = try #require(records("fx", roots).first)
        #expect(record.model == "fx-unknown")
        #expect(record.tally == TokenTally(input: 12, output: 3))
    }

    @Test("A zero Fx updated_at_ms is unset and falls through to created_at_ms")
    func fxZeroUpdatedFallsBackToCreated() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "fx", home: home, environment: [:])
        let directory = roots[0].appending(path: "fx-3")
        try write(
            [
                "session_id": "fx-3",
                "snapshot": ["input_tokens": 5, "output_tokens": 1, "models": []],
            ],
            to: directory.appending(path: "usage-v2.json")
        )
        try write(
            ["updated_at_ms": 0, "created_at_ms": 1_700_000_000_000],
            to: directory.appending(path: "session.json")
        )

        let record = try #require(records("fx", roots).first)
        #expect(record.timestamp == Self.fixedNow)

        // Only a zero, with no real fallback, is no record rather than 1970.
        let onlyZero = try makeStore()
        defer { cleanup(onlyZero) }
        let zeroRoots = StructuredLogReaders.inputs(client: "fx", home: onlyZero, environment: [:])
        let zeroDirectory = zeroRoots[0].appending(path: "fx-4")
        try write(
            ["session_id": "fx-4", "snapshot": ["input_tokens": 5, "output_tokens": 1]],
            to: zeroDirectory.appending(path: "usage-v2.json")
        )
        try write(["updated_at_ms": 0, "created_at_ms": 0], to: zeroDirectory.appending(path: "session.json"))
        #expect(records("fx", zeroRoots).isEmpty)
    }

    // MARK: - lmstudio

    @Test("LM Studio extracts the usage block and the log facts around it")
    func lmstudio() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(
            client: "lmstudio", home: home, environment: ["LM_STUDIO_HOME": home.path]
        )
        let log = """
        2024-06-07 08:09:10 [INFO] request received
        { "id": "chatcmpl-1", "model": "llama-3",
          "usage": {
            "prompt_tokens": 100,
            "completion_tokens": 40,
            "total_tokens": 140,
            "prompt_tokens_details": { "cached_tokens": 30, "cache_creation_input_tokens": 10 },
            "output_tokens_details": { "reasoning_tokens": 8 }
          } }

        """
        try writeText(log, to: roots[0].appending(path: "2024-06-07.log"))

        let record = try #require(records("lmstudio", roots).first)
        #expect(record.model == "llama-3")
        // total 140 = input 60 + cacheRead 30 + cacheWrite 10 + output 40;
        // completion already contains its reasoning detail.
        #expect(record.tally == TokenTally(input: 60, cacheWrite: 10, cacheRead: 30, output: 40))
        #expect(record.unclassifiedTokens == 0)
        // Reasoning is a stated subset of completion, so nothing is partial.
        #expect(!record.isPartial)
        #expect(record.deduplicationID == "lmstudio:chatcmpl-1")
        #expect(record.timestamp == Self.localDate("2024-06-07 08:09:10"))
    }

    @Test("Reasoning inside output is counted once at its reported size and priced there")
    func reasoningInsideOutputIsCountedOnce() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(
            client: "lmstudio", home: home, environment: ["LM_STUDIO_HOME": home.path]
        )
        let log = """
        2024-06-07 08:09:10 [INFO] request received
        { "id": "chatcmpl-2", "model": "priced",
          "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 100,
            "total_tokens": 110,
            "output_tokens_details": { "reasoning_tokens": 30 }
          } }

        """
        try writeText(log, to: roots[0].appending(path: "2024-06-07.log"))

        let record = try #require(records("lmstudio", roots).first)
        // output 100 already contains the 30 reasoning; nothing is added and
        // nothing is carried as unknown.
        #expect(record.tally == TokenTally(input: 10, output: 100))
        #expect(record.unclassifiedTokens == 0)
        #expect(!record.isPartial)

        let ledger = build([record])
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 110)
        // input 10 * 1_000/M + output 100 * 10_000/M = 0.01 + 1.0.
        let cost = ledger.days.reduce(0.0) { $0 + $1.cost }
        #expect(abs(cost - 1.01) < 1e-9)
    }

    @Test("An LM Studio block with no log timestamp is skipped")
    func lmstudioWithoutTimestamp() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(
            client: "lmstudio", home: home, environment: ["LM_STUDIO_HOME": home.path]
        )
        try writeText(
            "{ \"id\": \"x\", \"model\": \"m\", \"usage\": { \"prompt_tokens\": 1, \"completion_tokens\": 1 } }",
            to: roots[0].appending(path: "no-time.log")
        )
        #expect(records("lmstudio", roots).isEmpty)
    }

    // MARK: - reasonix

    @Test("Reasonix reads the stats rows and skips markers and empty rows")
    func reasonix() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "reasonix", home: home, environment: [:])
        try writeLines(
            [
                [
                    "ts": "2024-01-02T03:04:05Z",
                    "model": "openai/gpt-5",
                    "prompt": 100, "completion": 40, "reasoning": 8,
                    "cache_hit": 30, "cache_miss": 70, "total": 140, "requests": 2,
                ],
                ["ts": "2024-01-02T03:04:06Z", "model": "", "total": 5, "requests": 1],
                ["ts": "2024-01-02T03:04:07Z", "model": "openai/gpt-5", "turn": true, "total": 9, "requests": 1],
                ["ts": "2024-01-02T03:04:08Z", "model": "openai/gpt-5", "total": 0, "requests": 0],
            ],
            to: roots[0].appending(path: "2024-01-02.jsonl")
        )

        let decoded = records("reasonix", roots)
        #expect(decoded.count == 1)
        let record = try #require(decoded.first)
        // cache_miss 70 is the fresh input; completion 40 already contains its
        // 8 reasoning tokens, so output is kept whole.
        #expect(record.tally == TokenTally(input: 70, cacheRead: 30, output: 40))
        #expect(record.unclassifiedTokens == 0)
        // Reasoning is a stated subset of completion, so nothing is partial.
        #expect(!record.isPartial)
        #expect(record.model == "openai/gpt-5")
        #expect(record.timestamp == AgentLogIO.timestamp("2024-01-02T03:04:05Z"))
    }

    @Test("Reasonix keeps a bare total as unclassified rather than inventing a kind")
    func reasonixBareTotal() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "reasonix", home: home, environment: [:])
        try writeLines(
            [["ts": "2024-01-02T03:04:05Z", "model": "m", "total": 77, "requests": 1]],
            to: roots[0].appending(path: "day.jsonl")
        )

        let record = try #require(records("reasonix", roots).first)
        #expect(record.tally == TokenTally())
        #expect(record.unclassifiedTokens == 77)
    }

    // MARK: - Through the production chain

    @Test("Reasonix records price through the ledger, with money and a session span")
    func integration() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "reasonix", home: home, environment: [:])
        try writeLines(
            [
                [
                    "ts": "2024-01-02T03:04:05Z", "model": "priced",
                    "prompt": 100, "completion": 40, "cache_hit": 30, "total": 140, "requests": 2,
                ],
                [
                    "ts": "2024-01-02T05:06:07Z", "model": "mystery",
                    "prompt": 10, "completion": 5, "total": 15, "requests": 1,
                ],
            ],
            to: roots[0].appending(path: "day.jsonl")
        )

        let ledger = build(records("reasonix", roots))

        // priced: input 70, cacheRead 30, output 40; mystery: input 10, output 5.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 155)
        #expect(ledger.days.reduce(TokenTally()) { $0 + $1.tally }
            == TokenTally(input: 80, cacheRead: 30, output: 45))

        let summary = SpendSummary.of(
            [.openCode: ledger], overLast: nil, now: Self.fixedNow, calendar: Self.calendar
        )
        #expect(summary.tokens == 155)
        #expect(summary.tally == TokenTally(input: 80, cacheRead: 30, output: 45))
        // Every input in this fixture is settled, so nothing is partial.
        #expect(!summary.hasPartialCounts)
        #expect(summary.unpricedTokens == 15)
        #expect(summary.unpricedModels.contains("mystery"))
        #expect(summary.sessions.count == 1)
        let session = try #require(summary.sessions.first)
        #expect(session.session.start == AgentLogIO.timestamp("2024-01-02T03:04:05Z"))
        #expect(session.session.end == AgentLogIO.timestamp("2024-01-02T05:06:07Z"))

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "Priced", overLast: nil,
            now: Self.fixedNow, calendar: Self.calendar
        )
        #expect(model.tokens == 140)
        #expect(model.unpricedTokens == 0)
        #expect(!model.hasPartialCounts)
        // All four kinds priced at 1_000 per million except output at 10_000:
        // 70*0.001 + 30*0.0001 + 40*0.01 = 0.473.
        let cost = try #require(model.cost)
        #expect(abs(cost - 0.473) < 1e-9)
    }

    @Test("A shared explicit directory merges into one project across readers")
    func projectNameMatchesLegacyReaders() throws {
        let home = try makeStore()
        defer { cleanup(home) }

        let roots = StructuredLogReaders.inputs(client: "gjc", home: home, environment: [:])
        try writeLines(
            [
                ["type": "session", "id": "g1", "cwd": "/Users/me/Code/Pulse"],
                [
                    "type": "message",
                    "id": "e1",
                    "message": [
                        "role": "assistant", "model": "priced", "provider": "openai",
                        "timestamp": 1_700_000_000_000,
                        "usage": ["input": 100, "output": 20],
                    ],
                ],
            ],
            to: roots[0].appending(path: "slug/session.jsonl")
        )

        let decoded = records("gjc", roots)
        let record = try #require(decoded.first)
        #expect(record.project == "/Users/me/Code/Pulse")
        // An explicit directory, shared across readers, identifies one project.
        let legacy = "/Users/me/Code/Pulse"

        let sibling = AgentUsageRecord(
            timestamp: Self.fixedNow, model: "priced",
            tally: TokenTally(input: 10, output: 5),
            sessionID: "legacy-pulse", project: legacy
        )
        let summary = SpendSummary.of(
            [.openCode: build(decoded + [sibling])], overLast: nil,
            now: Self.fixedNow, calendar: Self.calendar
        )
        #expect(summary.projects.count == 1)
        #expect(summary.projects.first?.name == "Pulse")
        #expect(summary.projects.first?.tokens == 135)
    }

    // MARK: - Helpers

    private static func localDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)
    }
}
