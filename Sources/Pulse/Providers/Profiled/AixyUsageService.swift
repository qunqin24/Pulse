// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Aixy, an AI gateway: the budgets that apply to one key — set on the key,
/// its user, team, project or organization — each as an amount used and a
/// limit in US dollars that the gateway states.
///
/// Read with the project API key the user pastes, from the hosted gateway's
/// `GET https://api.aixy-gateway.com/v1/usage`. The shape is second-hand —
/// taken from CodexBar's Aixy provider and the usage contract it validates,
/// not from a captured reply — and the fixture in the tests says so.
///
/// **Only budgets whose balance the gateway knows are drawn.** One marked
/// unavailable has a limit and no figure against it, and is left off rather
/// than drawn at zero. A hard budget's use is what was spent plus what is
/// reserved for requests in flight, because that is what the gateway enforces
/// against; a monitor-only budget's is what was spent.
///
/// Budgets overlap and are never summed. Where two share a period, the one
/// that binds is drawn: an enforced budget before a monitored one, then the
/// one nearest its limit. Their scope — key, team, project — is not a model
/// name and is not put on the row.
///
/// Left out on purpose: the last seven days' attributed spend, which Aixy
/// itself says may be estimated or partial and which has no limit beside it.
extension ProviderProfile {
    static let aixy = ProviderProfile(
        displayName: "Aixy",
        billing: .api,
        iconResource: "extension",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From aixy-gateway.com. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        setupSlug: "aixy",
        fetch: { await AixyUsageService.fetch($0) }
    )
}

enum AixyUsageService {
    static let endpoint = URL(string: "https://api.aixy-gateway.com/v1/usage")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(endpoint, token: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - Reading the reply

    /// An amount, written as a number or as a decimal string.
    private struct Amount: Decodable {
        let value: Double?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
            } else {
                value = (try? container.decode(String.self)).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            }
        }
    }

    private struct Reply: Decodable {
        struct Key: Decodable {
            let id: String?
            let projectId: String?
        }

        struct Budget: Decodable {
            struct Target: Decodable {
                let apiKeyId: String?
                let projectId: String?
            }

            struct Availability: Decodable {
                let status: String?
                let spentUsd: Amount?
                let reservedUsd: Amount?
            }

            let id: String?
            let interval: String?
            let enforcement: String?
            let limitUsd: Amount?
            let appliesTo: [Target]?
            let availability: Availability?
            let spendStatus: String?
            let spendUsd: Amount?
            let resetsAt: String?
        }

        let object: String?
        let currency: String?
        let key: Key?
        let budgets: [Budget]?
    }

    /// Aixy writes snake_case throughout.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// The periods Aixy names, with the length each is. A month is a
    /// calendar month and a lifetime budget never turns over, so both lengths
    /// are only sort keys.
    private static let periods: [String: (kind: UsageWindow.Kind, seconds: Int, reportsLength: Bool)] = [
        "daily": (.daily, 86_400, true),
        "weekly": (.weekly, 7 * 86_400, true),
        "monthly": (.monthly, 30 * 86_400, false),
        "lifetime": (.spend, 365 * 86_400, false),
    ]

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? decoder.decode(Reply.self, from: data),
              reply.object == "key.usage", reply.currency == "USD",
              let keyID = reply.key?.id,
              let budgets = reply.budgets
        else { return context.unavailable(.unreadableReply) }

        // Every budget that is this key's, has a known balance and a limit.
        let known = budgets.compactMap { budget -> (window: UsageWindow, hard: Bool, period: String)? in
            guard let id = budget.id, let interval = budget.interval, let period = periods[interval],
                  let targets = budget.appliesTo, !targets.isEmpty,
                  targets.allSatisfy({ $0.apiKeyId == keyID && $0.projectId == reply.key?.projectId }),
                  let limit = budget.limitUsd?.value, limit.isFinite, limit > 0
            else { return nil }

            let hard = budget.enforcement == "hard"
            guard hard || budget.enforcement == "monitor" else { return nil }
            let used: Double?
            if hard {
                guard budget.availability?.status == "available",
                      let spent = budget.availability?.spentUsd?.value,
                      let reserved = budget.availability?.reservedUsd?.value
                else { return nil }
                used = spent + reserved
            } else {
                guard budget.spendStatus == "available" else { return nil }
                used = budget.spendUsd?.value
            }
            guard let used, used.isFinite, used >= 0 else { return nil }

            let fraction = used / limit
            let window = UsageWindow(
                id: "aixy.\(id)",
                kind: period.kind,
                scope: nil,
                usedFraction: fraction,
                windowSeconds: period.seconds,
                // A lifetime budget has no reset, whatever the reply says.
                resetsAt: interval == "lifetime" ? nil : ProfileHTTP.date(budget.resetsAt),
                reportsLength: period.reportsLength,
                isExhausted: fraction >= 1
            )
            return (window, hard, interval)
        }

        // One per period: the one that binds.
        let binding = Dictionary(grouping: known, by: \.period).values.compactMap { group in
            group.max { a, b in
                a.hard != b.hard ? !a.hard : a.window.usedFraction < b.window.usedFraction
            }?.window
        }
        .sorted { $0.windowSeconds < $1.windowSeconds }

        guard !binding.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(binding, at: now)
    }
}
