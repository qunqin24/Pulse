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
/// models.dev covers every provider in one 4MB document; only the two Pulse
/// reads usage for are kept, which leaves a few kilobytes to cache. It is
/// re-fetched once a day — list prices change on the order of months, and the
/// cached copy is what makes the settings pane work on a plane.
///
/// Prices are the base rates. Some models charge more above a long-context
/// threshold, and that tier isn't applied here: the logs record how many
/// tokens a request used, not how full its context was, so honouring the tier
/// would mean guessing which side of the line each request fell on.
actor ModelPrices {
    static let shared = ModelPrices()

    private var table: [String: ModelPrice]?
    private var inFlight: Task<[String: ModelPrice], Never>?

    /// Providers whose models Pulse can see usage for. Model ids are unique
    /// within a provider but not across all 200-odd of them, so the table is
    /// built from these two only.
    private static let providers = ["anthropic", "openai"]

    private static let source = URL(string: "https://models.dev/api.json")!
    private static let refreshAfter: TimeInterval = 24 * 3600

    func prices() async -> [String: ModelPrice] {
        if let table { return table }

        if let cached = Self.readCache(), cached.age < Self.refreshAfter {
            table = cached.prices
            return cached.prices
        }

        // One download even if several panes ask at once.
        if let inFlight { return await inFlight.value }

        let task = Task<[String: ModelPrice], Never> {
            if let fetched = await Self.download() {
                Self.writeCache(fetched)
                return fetched
            }
            // Offline: an old copy beats no prices at all, since list prices
            // barely move.
            return Self.readCache()?.prices ?? [:]
        }
        inFlight = task

        let result = await task.value
        inFlight = nil
        if !result.isEmpty { table = result }
        return result
    }

    // MARK: - Network

    private static func download() async -> [String: ModelPrice]? {
        var request = URLRequest(url: source)
        request.timeoutInterval = 30

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var prices: [String: ModelPrice] = [:]
        for provider in providers {
            let models = (root[provider] as? [String: Any])?["models"] as? [String: Any] ?? [:]
            for (id, model) in models {
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

        return prices.isEmpty ? nil : prices
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }

    // MARK: - Cache

    private struct Cache: Codable {
        let fetchedAt: Date
        let prices: [String: ModelPrice]

        var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }
    }

    /// The `2` is the stored shape. Model names were added to it, and a file
    /// written before that decodes fine with every name missing — a cache
    /// that is quietly a little bit wrong is worse than one that misses.
    private static var cacheFile: URL {
        PulseStorage.directory.appending(path: "model-prices-2.json")
    }

    private static func readCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private static func writeCache(_ prices: [String: ModelPrice]) {
        PulseStorage.prepare()
        guard let data = try? JSONEncoder().encode(Cache(fetchedAt: Date(), prices: prices)) else { return }
        try? data.write(to: cacheFile, options: .atomic)
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
