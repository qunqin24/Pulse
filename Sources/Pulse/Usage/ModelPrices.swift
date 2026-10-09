// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What one model charges, per million tokens.
///
/// Straight from models.dev, which publishes the providers' own list prices.
/// Missing rates stay `nil` rather than falling back to a plausible number:
/// a model Pulse has no price for is left out of the total and counted
/// separately, so a figure on screen is never part guesswork.
struct ModelPrice: Codable, Sendable, Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double?
    let cacheWrite: Double?
    /// How the provider writes the model's name — "GPT-5.6 Sol" rather than
    /// `gpt-5.6-sol`. Optional so an older cached file still decodes.
    let name: String?
    /// The rates a request pays once its context passes a size, lowest
    /// threshold first (`cost.tiers`, or `context_over_200k` where that is all
    /// there is). Nil where the model has one rate whatever the context.
    var tiers: [ContextTier]? = nil

    /// One long-context tier: a request whose context — fresh input, cache
    /// read and cache write together — is **over** `threshold` tokens is
    /// billed at these rates, all of it, not just the part past the line.
    /// That is how OpenAI states its 272K tier, and what ccusage and CodexBar
    /// apply.
    struct ContextTier: Codable, Sendable, Equatable {
        let threshold: Int
        let input: Double
        let output: Double
        let cacheRead: Double?
        let cacheWrite: Double?

        /// The tier as a price of its own; a cache rate it does not state
        /// falls back to its own input rate, as the base rates do.
        var price: ModelPrice {
            ModelPrice(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite, name: nil)
        }
    }

    /// The tier a request whose context fell in `band` (`TokenTally.contextBands`)
    /// pays: the highest threshold at or under the band's floor.
    func tier(forBand band: Int) -> ContextTier? {
        tiers?.filter { $0.threshold <= band }.max { $0.threshold < $1.threshold }
    }
}

/// The price list, fetched from models.dev and kept on disk.
///
/// Only the providers and plan vendors below are kept. The table is refreshed
/// on the next read after 24 hours, and the cached copy keeps the settings
/// pane working offline. Failed downloads may retry after five minutes.
///
/// Long-context tiers are applied where a request's own size is known: Claude
/// Code's replies and Codex's readings are one request each, and record their
/// context (`TokenTally.contextBands`). A store that adds requests up before
/// Pulse sees them is priced at the base rates.
actor ModelPrices {
    static let shared = ModelPrices()

    private var cached: Cache?
    /// The successful fetch's expiry, or a short retry delay after failure.
    /// Retrying does not change the snapshot's original `fetchedAt`.
    private var nextFetchAt: Date?
    private var inFlight: Task<[String: ModelPrice], Never>?
    private let cacheDirectory: URL
    private let now: @Sendable () -> Date
    private let downloadPrices: @Sendable () async -> [String: ModelPrice]?

    /// Isolated cache and clock/network boundaries for lifecycle tests.
    init(
        cacheDirectory: URL = PulseStorage.directory,
        now: @escaping @Sendable () -> Date = { Date() },
        download: @escaping @Sendable () async -> [String: ModelPrice]? = { await ModelPrices.download() }
    ) {
        self.cacheDirectory = cacheDirectory
        self.now = now
        self.downloadPrices = download
    }

    /// Providers whose models Pulse can see usage for, **in priority order**.
    ///
    /// It was these two alone, which was right while only Claude Code and
    /// Codex were read — and wrong the moment anything else was, because the
    /// agents run whatever their plan sells. Four of the seven agents on this
    /// machine came out at $0.00 for no better reason than that their vendor
    /// was not in this list, and so did every third-party model the two CLIs
    /// were pointed at.
    ///
    /// **Model ids are unique within a provider and not across all 213 of
    /// them**, which is why this is a list rather than the whole document.
    /// Across the fourteen here there are 22 collisions and 21 of them are
    /// `github-copilot` re-listing somebody else's model — it is a reseller,
    /// and Pulse reads no Copilot transcripts, so it is left out. The one real
    /// collision is `glm-5.2`, sold by both Zhipu and Alibaba; the order below
    /// settles it, and the rates are within a rounding error of each other
    /// anyway.
    private static let providers = [
        "anthropic", "openai", "xai", "moonshotai", "zhipuai", "minimax",
        "deepseek", "google", "xiaomi", "alibaba", "mistral", "meta",
    ]

    /// The plan vendors an agent can be priced against when **no first-party
    /// provider publishes the model at all**, keyed by the models.dev id.
    ///
    /// This is not a second guess at the same number, it is a different
    /// question. `deepseek-v4.1-flash` is real, it is what OpenCode Go sells,
    /// and DeepSeek's own provider entry does not list it — so the choice is
    /// between the rate the plan the tokens were actually bought on publishes,
    /// and no figure at all. Resellers stay out of the first-party list for
    /// the reason written there; they belong here, where they are only ever
    /// consulted for the agent whose plan they are.
    ///
    /// Stored **namespaced** (`vendor|id`) so a vendor's price can never be
    /// found by a lookup that did not ask for that vendor, and so adding one
    /// cannot collide with a first-party id.
    private static let vendors = ["opencode-go", "kilo", "cline-pass"]

    /// Separates a vendor from a model id in the table. Not a character any
    /// models.dev id uses.
    static let vendorSeparator: Character = "|"

    static func vendorKey(_ vendor: String, _ model: String) -> String {
        "\(vendor)\(vendorSeparator)\(model)"
    }

    private static let source = URL(string: "https://models.dev/api.json")!
    private static let refreshAfter: TimeInterval = 24 * 3600
    private static let retryAfter: TimeInterval = 5 * 60

    func prices() async -> [String: ModelPrice] {
        if let inFlight { return await inFlight.value }

        let at = now()
        if let nextFetchAt, at < nextFetchAt { return cached?.prices ?? [:] }

        if cached == nil {
            if let saved = Self.readCache(in: cacheDirectory) {
                cached = saved
                let expiresAt = saved.fetchedAt.addingTimeInterval(Self.refreshAfter)
                if at < expiresAt {
                    nextFetchAt = expiresAt
                    return saved.prices
                }
            } else {
                // A pre-vendor table is useful offline, but even a recent one
                // must not suppress the upgrade download.
                cached = Self.readCache(in: cacheDirectory, allowPreviousVersion: true)
            }
        }

        // One task owns the download and commits its result before releasing
        // the waiters, so none can return while the cache is still out of date.
        let task = Task<[String: ModelPrice], Never> {
            if let fetched = await downloadPrices() {
                let snapshot = Cache(fetchedAt: now(), prices: fetched)
                cached = snapshot
                nextFetchAt = snapshot.fetchedAt.addingTimeInterval(Self.refreshAfter)
                writeCache(snapshot)
            } else {
                // Keep the last table without renewing its age or writing it
                // back as a new download. Repeated reads offline are bounded.
                nextFetchAt = now().addingTimeInterval(Self.retryAfter)
            }
            inFlight = nil
            return cached?.prices ?? [:]
        }
        inFlight = task
        return await task.value
    }

    // MARK: - Network

    private static func download() async -> [String: ModelPrice]? {
        var request = URLRequest(url: source)
        request.timeoutInterval = 30

        guard
            let (data, response) = try? await NetworkSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var prices: [String: ModelPrice] = [:]
        for provider in providers {
            let models = (root[provider] as? [String: Any])?["models"] as? [String: Any] ?? [:]
            for (id, model) in models {
                // First provider in the list wins a shared id.
                guard prices[id] == nil else { continue }
                guard
                    let cost = (model as? [String: Any])?["cost"] as? [String: Any],
                    let input = number(cost["input"]),
                    let output = number(cost["output"])
                else { continue }

                prices[id] = ModelPrice(
                    input: input,
                    output: output,
                    cacheRead: number(cost["cache_read"]),
                    cacheWrite: number(cost["cache_write"]),
                    name: (model as? [String: Any])?["name"] as? String,
                    tiers: tiers(in: cost)
                )
            }
        }

        // The plan vendors, namespaced, and only for ids the first-party
        // providers did not already price: a vendor re-listing somebody else's
        // model must not shadow that model's own rate.
        for vendor in vendors {
            let models = (root[vendor] as? [String: Any])?["models"] as? [String: Any] ?? [:]
            for (id, model) in models {
                guard prices[id] == nil else { continue }
                guard
                    let cost = (model as? [String: Any])?["cost"] as? [String: Any],
                    let input = number(cost["input"]),
                    let output = number(cost["output"])
                else { continue }

                prices[vendorKey(vendor, id)] = ModelPrice(
                    input: input,
                    output: output,
                    cacheRead: number(cost["cache_read"]),
                    cacheWrite: number(cost["cache_write"]),
                    name: (model as? [String: Any])?["name"] as? String,
                    tiers: tiers(in: cost)
                )
            }
        }

        return prices.isEmpty ? nil : prices
    }

    /// `cost.tiers[]` of `tier.type == "context"`, or `context_over_200k` on
    /// its own. models.dev writes a threshold both as `272000` and `272001`
    /// ("over 272,000" either way), so the second is read as the first.
    static func tiers(in cost: [String: Any]) -> [ModelPrice.ContextTier]? {
        func tier(_ rates: [String: Any], over threshold: Int) -> ModelPrice.ContextTier? {
            guard let input = number(rates["input"]), let output = number(rates["output"]) else { return nil }
            return ModelPrice.ContextTier(
                threshold: threshold, input: input, output: output,
                cacheRead: number(rates["cache_read"]), cacheWrite: number(rates["cache_write"])
            )
        }
        var found: [ModelPrice.ContextTier] = []
        for entry in cost["tiers"] as? [[String: Any]] ?? [] {
            guard let shape = entry["tier"] as? [String: Any], shape["type"] as? String == "context",
                  let size = (shape["size"] as? Int) ?? (shape["size"] as? NSNumber)?.intValue, size > 1
            else { continue }
            let threshold = (size - 1) % 1_000 == 0 ? size - 1 : size
            if let tier = tier(entry, over: threshold) { found.append(tier) }
        }
        if found.isEmpty, let over = cost["context_over_200k"] as? [String: Any], let tier = tier(over, over: 200_000) {
            found.append(tier)
        }
        return found.isEmpty ? nil : found.sorted { $0.threshold < $1.threshold }
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }

    // MARK: - Spelling

    /// The price for a model id, allowing for the fact that the agents do not
    /// all spell one the same way.
    ///
    /// **Aliases, not fuzzy matching.** Every rule here is one product's known
    /// habit, written out, because the failure mode of a loose match is a
    /// model priced at another model's rate — a wrong number that looks right.
    /// A lookup that still misses is left unpriced, which is what the footnote
    /// on the page counts.
    static func price(
        for model: String,
        in table: [String: ModelPrice],
        vendor: String? = nil
    ) -> ModelPrice? {
        if let price = table[model] { return price }
        return resolve(for: model, vendor: vendor, exact: { table[$0] }, folded: { lowered in
            table.first(where: { $0.key.lowercased() == lowered })?.value
        })
    }

    /// Shared by single lookups and the indexed, scan-local lookup. The order
    /// is significant: every first-party spelling precedes every vendor rate.
    static func resolve(
        for model: String, vendor: String?,
        exact: (String) -> ModelPrice?, folded: (String) -> ModelPrice?
    ) -> ModelPrice? {
        if let price = exact(model) ?? folded(model.lowercased()) { return price }
        let candidates = aliases(for: model)
        for candidate in candidates {
            if let price = exact(candidate) ?? folded(candidate.lowercased()) { return price }
        }

        // Only now, and only for the vendor asked about: the plan the tokens
        // were bought on is the last word, never the first.
        guard let vendor else { return nil }
        if let price = exact(vendorKey(vendor, model)) { return price }
        let lowered = vendorKey(vendor, model).lowercased()
        if let price = folded(lowered) { return price }
        for candidate in candidates {
            if let price = exact(vendorKey(vendor, candidate)) { return price }
        }
        return nil
    }

    /// Spellings to try for one id, most specific first.
    static func aliases(for model: String) -> [String] {
        var candidates: [String] = []

        // Grok Build tags its own build of a model: `grok-4.6-build` is
        // xAI's `grok-4.6`, at xAI's rates.
        if model.hasSuffix("-build"), model != "grok-build-0.1" {
            candidates.append(String(model.dropLast("-build".count)))
        }

        // Devin's CLI writes the version with dashes and an effort on the end:
        // `gpt-5-6-sol-medium` is OpenAI's `gpt-5.6-sol`.
        for effort in ["-medium", "-high", "-low", "-minimal"] where model.hasSuffix(effort) {
            let base = String(model.dropLast(effort.count))
            candidates.append(base)
            candidates.append(Self.dotted(base))
        }
        candidates.append(Self.dotted(model))

        // A context window on the end is the same model with more room:
        // `k3-256k` is `kimi-k3`, and it is billed at `k3`'s rates.
        if let tag = model.range(of: "-[0-9]+[kKmM]$", options: .regularExpression) {
            let base = String(model[model.startIndex..<tag.lowerBound])
            candidates.append(base)
            candidates.append(contentsOf: Self.aliases(for: base))
        }

        // Kimi's CLI abbreviates: `k2p6` is `kimi-k2.6`, `k3` is `kimi-k3`.
        if model.first == "k", model.dropFirst().allSatisfy({ $0.isNumber || $0 == "p" }) {
            candidates.append("kimi-" + model.replacingOccurrences(of: "p", with: "."))
        }

        return candidates.filter { $0 != model }
    }

    /// `gpt-5-6-sol` → `gpt-5.6-sol`: a digit, a dash, a digit is a version
    /// number somebody spelled with the wrong separator. Two words joined by a
    /// dash are left alone.
    private static func dotted(_ model: String) -> String {
        var out = ""
        let characters = Array(model)
        for (index, character) in characters.enumerated() {
            if character == "-", index > 0, index + 1 < characters.count,
               characters[index - 1].isNumber, characters[index + 1].isNumber {
                out.append(".")
            } else {
                out.append(character)
            }
        }
        return out
    }

    // MARK: - Cache

    // Internal for isolated upgrade-cache tests; no test reads the user's table.
    struct Cache: Codable, Sendable {
        let fetchedAt: Date
        let prices: [String: ModelPrice]
    }

    /// Version 4 includes namespaced plan-vendor rates; version 5 keeps each
    /// model's long-context tiers. A version 4 table can be fresh but carries
    /// no tiers, so it is only an offline fallback and never suppresses a
    /// download on upgrade.
    private static var cacheFile: URL {
        PulseStorage.directory.appending(path: "model-prices-5.json")
    }

    static func readCache(
        in directory: URL = PulseStorage.directory,
        allowPreviousVersion: Bool = false
    ) -> Cache? {
        let names = [cacheFile.lastPathComponent] + (allowPreviousVersion ? ["model-prices-4.json"] : [])
        for name in names {
            guard let data = try? Data(contentsOf: directory.appending(path: name)),
                  let cached = try? JSONDecoder().decode(Cache.self, from: data) else { continue }
            return cached
        }
        return nil
    }

    private func writeCache(_ cache: Cache) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheDirectory.appending(path: Self.cacheFile.lastPathComponent), options: .atomic)
    }
}

/// Where Pulse keeps the things too big for `UserDefaults`.
enum PulseStorage {
    static let directory: URL = URL.applicationSupportDirectory.appending(path: "Pulse")

    static func prepare() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Files left behind by earlier cache formats.
    ///
    /// Renaming the file is the right way to invalidate a cache whose shape
    /// changed — the alternative, reusing the name, leaves old entries parsing
    /// as nothing at all, silently. But it does mean the superseded file sits
    /// in the user's Application Support forever unless something takes it
    /// away, so this does.
    ///
    /// **The numbered caches go by a rule, not a list.** `agent-<n>-<store>`
    /// and `ledger-<n>-<provider>` are superseded whenever `n` is below the
    /// version that is current (`AgentCache.version`,
    /// `UsageLedgerReader.cacheVersion`), so versioning one up needs no name
    /// added here — the list that used to hold them missed every `agent-`
    /// file, and tens of stale ones piled up. Add a name to this list only
    /// for a file that is not numbered that way.
    ///
    /// **Never `archive-*`.** `TranscriptArchive` and `AgentArchive` keep
    /// history the tools have deleted; nothing can rebuild them, so they are
    /// not numbered, change shape by migrating, and are never listed here.
    private static let superseded = [
        "ledger-claudeCode.json",   // day buckets, before quarter-hours
        "ledger-codex.json",
        "model-prices.json",        // before model display names were kept
        "model-prices-2.json",      // before plan vendors were namespaced
        "model-prices-3.json"
    ]

    /// Whether a file in this folder is from a cache format no longer read.
    static func isSuperseded(
        _ name: String,
        agentVersion: Int = AgentCache.version,
        ledgerVersion: Int = UsageLedgerReader.cacheVersion
    ) -> Bool {
        superseded.contains(name)
            || isOlder(name, prefix: "agent-", than: agentVersion)
            || isOlder(name, prefix: "ledger-", than: ledgerVersion)
    }

    /// `<prefix><n>-<name>.json` with `n` below `current`. A name without the
    /// number — `ledger-codex.json` — is not this rule's to judge.
    private static func isOlder(_ name: String, prefix: String, than current: Int) -> Bool {
        guard name.hasPrefix(prefix), name.hasSuffix(".json") else { return false }
        let rest = name.dropFirst(prefix.count)
        guard let dash = rest.firstIndex(of: "-"), let number = Int(rest[..<dash]) else { return false }
        return number < current
    }

    static func removeSupersededFiles() {
        let present = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in Set(superseded).union(present.filter { isSuperseded($0) }) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
