import Foundation

/// Reads the Grok account's usage.
///
/// The same borrowing the two CLI routes do: Grok Build's CLI stores an OIDC
/// login in `~/.grok/auth.json`, and this asks the CLI's own proxy with it —
/// `GET cli-chat-proxy.grok.com/v1/billing?format=credits`. For the **primary**
/// account nothing is held here; a second account signed in to through
/// `OAuthLogin` reaches the same two endpoints with the token Pulse holds for
/// it, and never looks at the CLI's file.
///
/// **What comes back is the account's pool, not the CLI's.** Since June 2026 a
/// paid Grok plan spends one weekly pool across every Grok product — the web
/// chat, Imagine, voice, the API and Grok Build alike — and the reply's
/// `productUsage` breakdown is the proof: it lists `GrokChat` beside
/// `GrokTasks`. So the ring is what this xAI *account* has spent this week,
/// which is why the provider is called Grok rather than Grok Build. There is
/// no per-product limit to show instead; the breakdown is shares of the one
/// pool, and drawing them as separate windows would claim four limits where
/// there is one.
///
/// **An absent percentage means zero, and that is read off this reply rather
/// than assumed.** The payload is proto3 serialised to JSON with implicit
/// presence, so a zero is simply left out — visible in the same reply, where
/// the `GrokChat` entry carries a product name and no `usagePercent` at all
/// while `GrokTasks` carries one. Taking a missing figure as "no reading"
/// would blank the ring for the first hours of every week.
///
/// Two caveats, both shared with the other borrowed routes. Neither endpoint
/// is public API — they are what the CLI itself calls, and can change without
/// notice. And the stored token lasts about six hours: the CLI renews it while
/// you use Grok, and nothing renews it for Pulse, so an aged-out login is
/// reported rather than worked around.
struct GrokUsageService: Sendable {
    var authFile: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appending(path: ".grok/auth.json")

    var billingEndpoint = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    /// The plan's name comes from here, not from the billing reply.
    var settingsEndpoint = URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!

    func fetch() async -> ProviderUsage {
        switch storedLogin() {
        case .none:
            return .unavailable(.grok, reason: .grokSignInRequired)
        case .expired:
            return .unavailable(.grok, reason: .grokLoginExpired)
        case .usable(let token):
            return await fetch(token: token)
        }
    }

    /// An account Pulse signed in to itself, read with the token it holds for
    /// it. There is no route to choose: what is in `~/.grok/auth.json` belongs
    /// to whichever account the CLI is signed in to, which is not this one.
    func fetch(account: AccountKey, token: String) async -> ProviderUsage {
        await fetch(token: token, for: account)
    }

    private func fetch(token: String, for account: AccountKey = AccountKey(.grok)) async -> ProviderUsage {
        guard let (data, response) = try? await URLSession.shared.data(for: request(billingEndpoint, token: token)) else {
            return .unavailable(account, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(account, reason: account.isPrimary ? .grokLoginExpired : .signedOut)
        case 429: return .unavailable(account, reason: .rateLimited)
        default: return .unavailable(account, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Billing.self, from: data),
              let config = reply.config
        else {
            return .unavailable(account, reason: .unreadableReply)
        }

        guard let window = Self.window(from: config) else {
            return .unavailable(account, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: account,
            windows: [window],
            observedAt: Date(),
            state: .live,
            plan: await plan(token: token),
            // `prepaidBalance` and `onDemandCap` are both denominated in a
            // unit the reply never names, and the cap is an allowance rather
            // than a balance — the reason Antigravity reports none either.
            creditBalance: nil
        )
    }

    private func request(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // What the CLI sends. Without it the proxy answers the enterprise
        // credit shape instead, whose `monthlyLimit` is zero on a personal
        // plan — a denominator of nothing, and no percentage at all.
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - The plan's name

    /// A second call, because the billing reply does not name the plan —
    /// the same shape Claude Code's and Antigravity's plan lookups take.
    ///
    /// Optional enrichment on a short budget: the usage figures are already in
    /// hand by the time this runs, and a stalled settings call must not hold
    /// them back. Only the plan-shaped field is read; the reply also carries
    /// this account's subagent and planner settings, which are no use here.
    private func plan(token: String) async -> String? {
        var request = request(settingsEndpoint, token: token)
        request.timeoutInterval = 4

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let settings = try? JSONDecoder().decode(Settings.self, from: data),
            let tier = settings.subscriptionTierDisplay?.trimmingCharacters(in: .whitespacesAndNewlines),
            !tier.isEmpty
        else { return nil }

        return tier
    }

    // MARK: - Reading the reply

    private struct Billing: Decodable {
        struct Period: Decodable {
            let start: String?
            let end: String?
        }

        struct Config: Decodable {
            let currentPeriod: Period?
            /// How much of the pool is **gone**, 0...100. Omitted when zero.
            let creditUsagePercent: Double?
            let billingPeriodStart: String?
            let billingPeriodEnd: String?
        }

        let config: Config?
    }

    private struct Settings: Decodable {
        let subscriptionTierDisplay: String?

        enum CodingKeys: String, CodingKey {
            case subscriptionTierDisplay = "subscription_tier_display"
        }
    }

    /// The one window the pool amounts to.
    ///
    /// Both ends of the period are stated, so the length is measured from them
    /// rather than assumed from the period's name — `reportsLength` is true
    /// and the window clock and the forecast both have a real number to divide
    /// by. `currentPeriod` is preferred over the flat `billingPeriod*` pair
    /// because it is the one that says which period is *current*; the flat
    /// pair is the fallback for a reply that omits it.
    private static func window(from config: Billing.Config) -> UsageWindow? {
        guard
            let start = date(from: config.currentPeriod?.start ?? config.billingPeriodStart),
            let end = date(from: config.currentPeriod?.end ?? config.billingPeriodEnd),
            end > start
        else { return nil }

        let seconds = Int(end.timeIntervalSince(start).rounded())

        // An omitted percentage is a zero the serialiser dropped — but only
        // inside a period that is actually running. A reply describing a
        // period that has ended says nothing about what has been spent in the
        // one that followed it, and reading that as 0% would report an empty
        // pool as a full one.
        let now = Date()
        guard let percent = config.creditUsagePercent ?? ((start...end).contains(now) ? 0 : nil) else {
            return nil
        }

        return UsageWindow(
            id: "grok-pool",
            kind: kind(seconds: seconds),
            scope: nil,
            usedFraction: min(max(percent / 100, 0), 1),
            windowSeconds: seconds,
            resetsAt: end
        )
    }

    /// Named from the length the reply gave, not from its `type` string: the
    /// enum is theirs to rename, the two timestamps are arithmetic. A period
    /// that is neither of the two familiar lengths is still shown, under a
    /// heading built from its own duration.
    private static func kind(seconds: Int) -> UsageWindow.Kind {
        switch seconds {
        case 6 * 86_400...8 * 86_400: .weekly
        case 27 * 86_400...32 * 86_400: .monthly
        default: .other(seconds: seconds)
        }
    }

    // MARK: - The stored login

    private enum Login {
        case none
        case expired
        case usable(String)
    }

    /// What the CLI wrote at its last `grok login`.
    ///
    /// The file is keyed by issuer and client id rather than by account, and
    /// may hold more than one entry, so the freshest unexpired one is taken.
    /// An entry that has aged out is kept as evidence: "signed in, and the
    /// login has gone stale" is a different instruction from "never signed
    /// in", and the difference is the whole message.
    private func storedLogin() -> Login {
        guard
            let data = try? Data(contentsOf: authFile),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .none }

        var sawEntry = false
        var best: (token: String, expiry: Date)?

        for case let entry as [String: Any] in root.values {
            guard let token = entry["key"] as? String, !token.isEmpty else { continue }
            sawEntry = true

            // No expiry stated is not the same as expired — the token is
            // simply undated, and the service is the one that decides. It is
            // kept as a last resort and **cannot outrank a dated one**: parked
            // at `.distantFuture` it won every comparison, so a file holding an
            // undated entry before a perfectly good dated one used the wrong
            // token. `.distantPast` loses instead, which is what a fallback
            // should do.
            guard let expiry = Self.date(from: entry["expires_at"] as? String) else {
                if best == nil { best = (token, .distantPast) }
                continue
            }
            guard expiry > Date() else { continue }
            if best == nil || expiry > best!.expiry { best = (token, expiry) }
        }

        if let best { return .usable(best.token) }
        return sawEntry ? .expired : .none
    }

    /// Built per call: `ISO8601DateFormatter` is not `Sendable`, and this
    /// parses a handful of stamps a refresh. They carry fractional seconds,
    /// and the period's stamps carry a `+00:00` offset rather than a `Z`.
    private static func date(from text: String?) -> Date? {
        guard let text else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
