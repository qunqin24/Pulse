// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Augment Code's credits for the billing cycle: how many were used against
/// how many the cycle makes available, both as Augment reports them.
///
/// Read with the browser session the user imports in Settings, from the two
/// endpoints Augment's own account page calls on `app.augmentcode.com`:
/// `GET /api/credits` for the figures and `GET /api/subscription` for the
/// plan's name and when the cycle ends. The second is a nicety — a reading
/// stands without it, as it does in CodexBar.
///
/// The shape is second-hand — taken from CodexBar's Augment provider and its
/// tests, not from a captured reply — and the fixtures in the tests say so.
///
/// **What CodexBar does and this does not.** When `usageUnitsAvailable` is
/// missing or zero it adds the remaining credits to the consumed ones and
/// calls that the limit; a limit Augment did not state is not one Pulse
/// draws against, so that reading is left off. It also prefers the `auggie`
/// CLI and keeps the browser session alive by pinging Augment on a timer;
/// here the session is read when the user asks, and nothing is run and
/// nothing is sent on Pulse's own schedule but the reading itself.
extension ProviderProfile {
    static let augment = ProviderProfile(
        displayName: "Augment Code",
        iconResource: "extension",
        credential: .sessionCookie(host: "app.augmentcode.com", cookies: ["_session", "web_rpc_proxy_session"]),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        keySubtitle: { .localized("Copied from your browser. Stored encrypted on this Mac.") },
        setupSlug: "augment",
        discoveryPaths: [".augment"],
        fetch: { await AugmentUsageService.fetch($0) }
    )
}

enum AugmentUsageService {
    static let base = URL(string: "https://app.augmentcode.com")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookies = context.trimmedCredential else { return context.unavailable(.sessionMissing) }

        let credits: Data
        switch await ProfileHTTP.data(for: request("api/credits", cookies: cookies),
                                      refused: .sessionExpired, session: session) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data): credits = data
        }

        // Optional, as in CodexBar: without it there is no plan name and no
        // reset, and the figures are still the figures.
        let subscription: Data? = switch await ProfileHTTP.data(
            for: request("api/subscription", cookies: cookies), refused: .sessionExpired, session: session) {
        case .success(let data): data
        case .failure: nil
        }

        return reading(credits: credits, subscription: subscription, context: context)
    }

    private static func request(_ path: String, cookies: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    // MARK: - Reading the reply

    private struct Credits: Decodable {
        let usageUnitsRemaining: Double?
        let usageUnitsConsumedThisBillingCycle: Double?
        let usageUnitsAvailable: Double?
    }

    private struct Subscription: Decodable {
        let planName: String?
        let billingPeriodEnd: String?
    }

    static func reading(credits: Data, subscription: Data?, context: ProfileContext,
                        now: Date = Date()) -> ProviderUsage {
        // Not a dictionary of figures — an HTML sign-in page served with a
        // 200, say — is not a reply this can read.
        guard (try? JSONSerialization.jsonObject(with: credits)) is [String: Any],
              let reply = try? JSONDecoder().decode(Credits.self, from: credits)
        else { return context.unavailable(.unreadableReply) }

        let about = subscription.flatMap { try? JSONDecoder().decode(Subscription.self, from: $0) }
        let plan = about?.planName.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }

        guard let used = reply.usageUnitsConsumedThisBillingCycle, used.isFinite, used >= 0,
              let available = reply.usageUnitsAvailable, available.isFinite, available > 0
        else { return context.unavailable(.noLimitsReported) }

        // Credits, with the reset Augment states and no length it claims: a
        // billing cycle's thirty days are a sort key only.
        let window = UsageWindow(
            id: "augment.credits",
            kind: .credits,
            scope: nil,
            usedFraction: used / available,
            windowSeconds: 30 * 86_400,
            resetsAt: ProfileHTTP.date(about?.billingPeriodEnd),
            reportsLength: false,
            isExhausted: used >= available
        )
        return context.reading([window], plan: plan, at: now)
    }
}
