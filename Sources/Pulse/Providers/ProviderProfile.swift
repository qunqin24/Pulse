// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Everything a provider says about itself, in one value, for the providers
/// written after there were dozens of them.
///
/// **Why this exists.** The first twenty-five providers each answer twenty-odd
/// exhaustive `switch`es spread over the app — name, icon, credential, access
/// sentence, route, colour, setup page, discovery, fetch. That is what made
/// every one of them get looked at in every place, and it is also what made
/// adding fifty more a merge conflict in every one of those files. A profiled
/// provider still has its case in every one of those switches, but the arm
/// hands the question to its profile, and the profile lives in the provider's
/// own file under `Providers/Profiled/`. Adding or changing one touches that
/// file and nothing shared.
///
/// Nothing here relaxes a rule. A profile states a credential kind, and the
/// kinds are the ones the rest of the app already knows how to draw and guard:
/// a pasted key, a browser session read on request, a key and a server address,
/// or a login the provider's own tool saved on this Mac.
struct ProviderProfile: Sendable {
    enum Credential: Sendable, Equatable {
        /// A key the user pastes. `optional` when the service can also find a
        /// login its own tool saved, and the field is only for a key from
        /// somewhere else.
        case apiKey(optional: Bool)
        /// A browser session for `host`, read when the user presses Read and
        /// kept to the named cookies. The first name is the one that has to
        /// be there for the session to count.
        case sessionCookie(host: String, cookies: [String])
        /// A sign-in a site keeps in a Chromium browser's `localStorage` rather
        /// than in a cookie, read when the user presses Read — the same reader
        /// Devin's pane uses. Every named key has to be there; they are stored
        /// together as one JSON object, which is what `context.credential`
        /// then holds. Nothing else in that origin's storage is kept.
        case browserStorage(origin: String, keys: [String])
        /// A self-hosted gateway: a key, and the address it is sent to. The
        /// key goes nowhere else.
        case keyAndAddress
        /// Nothing pasted: the service reads a login its own app or CLI saved.
        case localLogin
    }

    /// The product's name, left untranslated.
    let displayName: String
    /// How the account is paid for, which decides where it is listed and
    /// which rail it rides. See `Provider.Billing`.
    var billing: Provider.Billing = .subscription
    /// An SVG in `Resources`, without its extension.
    let iconResource: String
    let credential: Credential
    /// Shown before the provider is switched on, in the chooser and in
    /// Settings. What is read and from where — never a guess.
    let accessDescription: @Sendable () -> String
    /// The subtitle under the credential field. Nil for the shared wording.
    var keySubtitle: (@Sendable () -> String)? = nil
    /// For a `localLogin` provider, the route named on its pane.
    var soleRoute: (@Sendable () -> (name: String, note: String))? = nil
    /// Money in an account, spent by the call, with a number and a currency.
    var reportsSpendableBalance = false
    /// See `Provider.spendingIsWatchedLocally`. False for anything spent on
    /// somebody else's servers where nothing on this Mac moves.
    var spendingIsWatchedLocally = true
    /// Whether a banked reading may stand in only for the same account.
    var requiresScopeMatch = false
    /// The brand's colour for the animated mark, where the brand has one.
    var brandColor: UInt32? = nil
    /// `Docs/setup/<slug>.md`, which the in-app Setup help link opens.
    let setupSlug: String
    /// Presence-only hints for the chooser, relative to the home folder
    /// unless absolute. Never read, only checked for existence.
    var discoveryPaths: [String] = []
    /// The reading. Runs off the main actor; must never throw, and must
    /// return `.unavailable` with a reason from the shared set rather than
    /// invent one.
    let fetch: @Sendable (ProfileContext) async -> ProviderUsage
}

/// What the store hands a profiled provider's fetch: the provider, whatever
/// Pulse holds for it, and the settings that can change what it asks.
struct ProfileContext: Sendable {
    let provider: Provider
    /// The pasted key or the imported session header, if there is one.
    let credential: String?
    /// For `keyAndAddress`, the address the reader entered.
    let serverAddress: String?

    var account: AccountKey { AccountKey(provider) }

    /// The one way a profiled fetch says it has nothing. Keeps the account and
    /// the reason together so no provider can file a failure under another.
    func unavailable(_ reason: ProviderUsage.Unavailability) -> ProviderUsage {
        .unavailable(account, reason: reason)
    }
}

extension ProviderProfile {
    /// Keeps only the named cookies out of a browser's `name=value; …`
    /// header, and nothing at all if the first name is missing. What is not
    /// kept never leaves the process.
    ///
    /// A name ending in `*` is a prefix, for a service whose session cookie
    /// carries a suffix of its own — Mistral's is `ory_session_` and then the
    /// deployment's id. The prefix has to be followed by something; `*` alone
    /// would keep every cookie the browser holds for the host.
    ///
    /// Names joined with `|` are alternatives, for a service whose session can
    /// sit under any one of several names. In the first entry that means any
    /// one of them is enough; every one of them is kept.
    static func keep(_ header: String, cookies names: [String]) -> String? {
        guard let first = names.first else { return nil }
        let required = first.split(separator: "|").map(String.init)
        let patterns = names.flatMap { $0.split(separator: "|").map(String.init) }
        func matches(_ name: String, _ pattern: String) -> Bool {
            guard pattern.hasSuffix("*") else { return name == pattern }
            let prefix = String(pattern.dropLast())
            return !prefix.isEmpty && name.hasPrefix(prefix) && name.count > prefix.count
        }
        let pairs = header.split(separator: ";").compactMap { part -> (String, String)? in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { return nil }
            let name = String(trimmed[..<equals])
            let value = String(trimmed[trimmed.index(after: equals)...])
            return patterns.contains(where: { matches(name, $0) }) && !value.isEmpty ? (name, value) : nil
        }
        guard pairs.contains(where: { pair in required.contains { matches(pair.0, $0) } }) else { return nil }
        var seen: Set<String> = []
        return pairs.filter { seen.insert($0.0).inserted }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "; ")
    }
}

extension ProviderProfile {
    /// The named `localStorage` values as one JSON object of strings, or nil
    /// unless every one is there. A value the site stored JSON-encoded — a
    /// quoted string — is unwrapped, so the service reads plain strings
    /// whichever way the site wrote them.
    static func storageCredential(from values: [String: String], keys: [String]) -> String? {
        var picked: [String: String] = [:]
        for key in keys {
            guard let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            let unwrapped = (try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed)) as? String
            picked[key] = unwrapped ?? raw
        }
        guard let data = try? JSONSerialization.data(withJSONObject: picked, options: .sortedKeys) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// So a request can fail with the reason itself: `Result<Data, Unavailability>`.
extension ProviderUsage.Unavailability: Error {}

/// One request, and what its status means, for the profiled providers.
///
/// Every one of them asks an HTTP endpoint and every one of them has to turn
/// the same handful of failures into the same handful of reasons. Written once
/// so that a refused key reads as a refused key everywhere — and so a provider
/// cannot quietly treat a 500 as "no limits".
enum ProfileHTTP {
    struct Reply: Sendable {
        let data: Data
        let status: Int
    }

    /// Sends `request` and returns the body of a 2xx reply, or the reason there
    /// is none. `refused` is what a 401 or 403 means for this credential: a
    /// pasted key, a browser session, or a saved login.
    static func data(
        for request: URLRequest,
        refused: ProviderUsage.Unavailability = .apiKeyRefused,
        session: URLSession? = nil
    ) async -> Result<Data, ProviderUsage.Unavailability> {
        switch await reply(for: request, session: session) {
        case .failure(let reason): return .failure(reason)
        case .success(let reply): return classify(reply, refused: refused)
        }
    }

    /// What a status means, apart from the request. Separate so a provider's
    /// tests can pin its mapping without a network.
    static func classify(_ reply: Reply, refused: ProviderUsage.Unavailability = .apiKeyRefused)
        -> Result<Data, ProviderUsage.Unavailability> {
        switch reply.status {
        case 200..<300: .success(reply.data)
        // A redirect is never followed (see `reply`), and for every service
        // here the one it sends is to its sign-in page.
        case 300..<400, 401, 403: .failure(refused)
        case 429: .failure(.rateLimited)
        default: .failure(.serverError)
        }
    }

    /// The reply whatever its status, for a provider whose failures carry
    /// meaning in the body. Only a request that never got an answer fails.
    ///
    /// **Redirects are not followed.** A key or a session cookie is set on the
    /// request by hand, and a hand-set header travels with a redirect to
    /// whatever host it names. The redirect comes back as a 3xx instead, which
    /// `classify` reads as the credential being turned away.
    static func reply(
        for request: URLRequest,
        session: URLSession? = nil
    ) async -> Result<Reply, ProviderUsage.Unavailability> {
        guard let (data, response) = try? await (session ?? NetworkSession.shared)
                .data(for: request, delegate: NoRedirects()),
              let http = response as? HTTPURLResponse
        else { return .failure(.unreachable) }
        return .success(Reply(data: data, status: http.statusCode))
    }

    /// A GET with a bearer token, which is most of them.
    static func bearer(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    /// ISO 8601 with or without fractional seconds, the two shapes every
    /// service here uses.
    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

extension ProfileContext {
    /// The credential, trimmed, or nil when there is nothing usable.
    var trimmedCredential: String? {
        credential.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A live reading of this provider, from what it reported.
    func reading(
        _ windows: [UsageWindow],
        plan: String? = nil,
        creditBalance: String? = nil,
        creditRemaining: ProviderUsage.CreditAmount? = nil,
        at now: Date = Date()
    ) -> ProviderUsage {
        var usage = ProviderUsage(
            account: account,
            windows: windows,
            observedAt: now,
            state: .live,
            plan: plan,
            creditBalance: creditBalance
        )
        usage.creditRemaining = creditRemaining
        return usage
    }
}
