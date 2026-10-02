// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Manus, the agent: the plan's monthly credits, the credits that refresh on a
/// shorter clock, and the account's total credit balance. Each allowance is a
/// size and a remainder the service states.
///
/// Read with the manus.im browser session the user imports: the `session_id`
/// cookie's value goes as a bearer token to
/// `POST https://api.manus.im/user.v1.UserService/GetAvailableCredits`, the
/// way CodexBar sends it. The shape is second-hand — taken from CodexBar's Manus
/// provider and its tests, not from a captured reply — and the fixture in the
/// tests says so.
///
/// A figure the reply leaves out is left out here, never read as zero: an
/// allowance with no remainder has no share used. The refresh's reset is read
/// only as an ISO 8601 date; its length only when the reply names the
/// interval as daily.
extension ProviderProfile {
    static let manus = ProviderProfile(
        displayName: "Manus",
        iconResource: "manus",
        credential: .sessionCookie(host: "manus.im", cookies: ["session_id"]),
        accessDescription: { .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.") },
        spendingIsWatchedLocally: false,
        setupSlug: "manus",
        fetch: { await ManusUsageService.fetch($0) }
    )
}

enum ManusUsageService {
    static let endpoint = URL(string: "https://api.manus.im/user.v1.UserService/GetAvailableCredits")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let token = context.trimmedCredential.flatMap(sessionToken) else {
            return context.unavailable(.sessionMissing)
        }
        switch await ProfileHTTP.data(for: request(token: token), refused: .sessionExpired, session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    /// The headers CodexBar sends: a Connect call with an empty body, from the
    /// site's own origin, in a browser's name. Nothing else about the session
    /// goes with it.
    static func request(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("https://manus.im", forHTTPHeaderField: "Origin")
        request.setValue("https://manus.im/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15
        return request
    }

    /// The `session_id` value out of the kept `name=value` header.
    static func sessionToken(from header: String) -> String? {
        ProviderProfile.keep(header, cookies: ["session_id"])
            .flatMap { $0.split(separator: "=", maxSplits: 1).last.map(String.init) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Reading the reply

    private struct Credits: Decodable {
        let totalCredits: Double?
        let periodicCredits: Double?
        let proMonthlyCredits: Double?
        let refreshCredits: Double?
        let maxRefreshCredits: Double?
        let nextRefreshTime: String?
        let refreshInterval: String?

        enum CodingKeys: String, CodingKey {
            case totalCredits, periodicCredits, proMonthlyCredits
            case refreshCredits, maxRefreshCredits, nextRefreshTime, refreshInterval
        }

        /// Counts arrive as numbers or as numeric strings; anything else is
        /// no figure. The reset is read only when it is a date string.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func figure(_ key: CodingKeys) -> Double? {
                if let number = try? container.decode(Double.self, forKey: key) { return number }
                return (try? container.decode(String.self, forKey: key)).flatMap(Double.init)
            }
            totalCredits = figure(.totalCredits)
            periodicCredits = figure(.periodicCredits)
            proMonthlyCredits = figure(.proMonthlyCredits)
            refreshCredits = figure(.refreshCredits)
            maxRefreshCredits = figure(.maxRefreshCredits)
            nextRefreshTime = try? container.decode(String.self, forKey: .nextRefreshTime)
            refreshInterval = try? container.decode(String.self, forKey: .refreshInterval)
        }

        var hasAnyFigure: Bool {
            [totalCredits, periodicCredits, proMonthlyCredits, refreshCredits, maxRefreshCredits]
                .contains { $0 != nil }
        }
    }

    /// The credits object, bare or inside one of the envelopes Manus has used.
    private struct Envelope: Decodable {
        let data: Credits?
        let result: Credits?
        let response: Credits?
        let availableCredits: Credits?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        let bare = try? JSONDecoder().decode(Credits.self, from: data)
        guard let credits = [envelope?.data, envelope?.result, envelope?.response, envelope?.availableCredits, bare]
            .compactMap({ $0 })
            .first(where: \.hasAnyFigure)
        else { return context.unavailable(.unreadableReply) }

        var windows: [UsageWindow] = []
        let daily = credits.refreshInterval?.lowercased().contains("daily") == true
        if let window = window(
            id: "manus.refresh", kind: daily ? .daily : .credits,
            size: credits.maxRefreshCredits, left: credits.refreshCredits,
            seconds: 86_400, reportsLength: daily, resetsAt: ProfileHTTP.date(credits.nextRefreshTime)
        ) { windows.append(window) }
        // The plan's monthly credits. No renewal date is reported, so no
        // reset is claimed and the month is a sort key.
        if let window = window(
            id: "manus.monthly", kind: .monthly,
            size: credits.proMonthlyCredits, left: credits.periodicCredits,
            seconds: 30 * 86_400, reportsLength: false, resetsAt: nil
        ) { windows.append(window) }

        let total = credits.totalCredits.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        guard !windows.isEmpty || total != nil else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, creditBalance: total.map(count), at: now)
    }

    /// Used is the size less what is left, both as reported. A size of zero is
    /// no allowance.
    private static func window(
        id: String,
        kind: UsageWindow.Kind,
        size: Double?,
        left: Double?,
        seconds: Int,
        reportsLength: Bool,
        resetsAt: Date?
    ) -> UsageWindow? {
        guard let size, size.isFinite, size > 0, let left, left.isFinite, left >= 0 else { return nil }
        let fraction = max(size - left, 0) / size
        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: fraction,
            windowSeconds: seconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength,
            isExhausted: left <= 0
        )
    }

    /// Manus's credits are its own unit, not money. The number alone, grouped
    /// for the reader's language.
    private static func count(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded()))
    }
}
