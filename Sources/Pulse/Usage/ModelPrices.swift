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
}

/// The price list, fetched from models.dev and kept on disk.
///
/// Only the providers and plan vendors below are kept. The table is refreshed
/// on the next read after 24 hours, and the cached copy keeps the settings
/// pane working offline. Failed downloads may retry after five minutes.
///
/// Prices are the base rates. Some models charge more above a long-context
/// threshold, and that tier isn't applied here: the logs record how many
/// tokens a request used, not how full its context was, so honouring the tier
/// would mean guessing which side of the line each request fell on.
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
                    name: (model as? [String: Any])?["name"] as? String
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
                    name: (model as? [String: Any])?["name"] as? String
                )
            }
        }

        return prices.isEmpty ? nil : prices
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
        if let price = firstParty(model, table) { return price }

        // Only now, and only for the vendor asked about: the plan the tokens
        // were bought on is the last word, never the first.
        guard let vendor else { return nil }
        if let exact = table[vendorKey(vendor, model)] { return exact }
        let lowered = vendorKey(vendor, model).lowercased()
        if let match = table.first(where: { $0.key.lowercased() == lowered })?.value { return match }
        for candidate in aliases(for: model) {
            if let match = table[vendorKey(vendor, candidate)] { return match }
        }
        return nil
    }

    private static func firstParty(_ model: String, _ table: [String: ModelPrice]) -> ModelPrice? {
        if let exact = table[model] { return exact }

        // MiniMax writes `MiniMax-M3` and the agents that call it write
        // `minimax-m3`. Case is the only difference.
        let lowered = model.lowercased()
        if let match = table.first(where: { $0.key.lowercased() == lowered })?.value { return match }

        for candidate in aliases(for: model) {
            if let match = table[candidate] { return match }
            let folded = candidate.lowercased()
            if let match = table.first(where: { $0.key.lowercased() == folded })?.value { return match }
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

    /// Version 4 includes namespaced plan-vendor rates. A version 3 table can
    /// be fresh but cannot satisfy the new lookup, so it is only an offline
    /// fallback and never suppresses a download on upgrade.
    private static var cacheFile: URL {
        PulseStorage.directory.appending(path: "model-prices-4.json")
    }

    static func readCache(
        in directory: URL = PulseStorage.directory,
        allowPreviousVersion: Bool = false
    ) -> Cache? {
        let names = [cacheFile.lastPathComponent] + (allowPreviousVersion ? ["model-prices-3.json"] : [])
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
    /// away, so this does. Add a name here whenever a cache is versioned up.
    private static let superseded = [
        "ledger-claudeCode.json",   // day buckets, before quarter-hours
        "ledger-codex.json",
        "model-prices.json"         // before model display names were kept
    ]

    static func removeSupersededFiles() {
        for name in superseded {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
