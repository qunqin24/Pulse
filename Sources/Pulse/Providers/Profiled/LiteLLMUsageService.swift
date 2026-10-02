// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// LiteLLM, a self-hosted proxy: the budget on the user a virtual key belongs
/// to, and the budget on its team, each as spend against a limit the proxy
/// states.
///
/// Read with the virtual key and the proxy address the user enters, from
/// three of LiteLLM's own routes: `GET /key/info` names the key's user and
/// team, then `GET /user/info?user_id=…` — or, for a key with a team and no
/// user, `GET /team/info?team_id=…` — carries the spend and the budget. The
/// key goes nowhere but that address. The shapes are second-hand — taken from
/// CodexBar's LiteLLM provider and its tests, not from a captured reply — and
/// the fixtures in the tests say so.
///
/// **The team's budget is drawn first**, because it is the one the proxy
/// enforces on the key. A user or team with no `max_budget` has spend and
/// nothing to measure it against, and is left off. The ids the proxy answers
/// with are checked against the ones `/key/info` named, so another user's or
/// another team's budget is never drawn as this key's.
///
/// A deployment that will not let a key read its own information (403, 404)
/// has no budget Pulse can read: CodexBar falls back to a month's spend report
/// there, which is spend with no limit, and Pulse has nowhere to show that.
extension ProviderProfile {
    static let liteLLM = ProviderProfile(
        displayName: "LiteLLM",
        billing: .api,
        iconResource: "extension",
        credential: .keyAndAddress,
        accessDescription: { .localized("Sends the key you enter only to the server address you enter. No Keychain prompt.") },
        keySubtitle: { .localized("The same key your AI client uses for this gateway. Sent only to the address above. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        requiresScopeMatch: true,
        setupSlug: "litellm",
        fetch: { await LiteLLMUsageService.fetch($0) }
    )
}

enum LiteLLMUsageService {
    /// Every reading is stamped with the proxy and key it came from, so a
    /// banked reading from another server never stands in for this one's.
    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        var usage = await read(context, session: session)
        usage.sourceScope = GatewayAddress.scope(of: context.serverAddress, key: context.trimmedCredential)
        return usage
    }

    private static func read(_ context: ProfileContext, session: URLSession?) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        let typed = context.serverAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !typed.isEmpty else { return context.unavailable(.serverAddressMissing) }
        guard let keyInfo = url(typed, "/key/info") else { return context.unavailable(.serverAddressRefused) }

        let identity: Identity
        switch await ProfileHTTP.reply(for: ProfileHTTP.bearer(keyInfo, token: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let reply) where reply.status == 403 || reply.status == 404:
            return context.unavailable(.noLimitsReported)
        case .success(let reply):
            switch ProfileHTTP.classify(reply) {
            case .failure(let reason): return context.unavailable(reason)
            case .success(let data):
                guard let named = Self.identity(from: data) else { return context.unavailable(.unreadableReply) }
                identity = named
            }
        }

        let route: URL?
        if let user = identity.user {
            route = url(typed, "/user/info", query: ["user_id": user])
        } else if let team = identity.team {
            route = url(typed, "/team/info", query: ["team_id": team])
        } else {
            // A key bound to neither — a master key — has no budget of its own.
            return context.unavailable(.noLimitsReported)
        }
        guard let route else { return context.unavailable(.serverAddressRefused) }

        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(route, token: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return identity.user != nil
                ? reading(userInfo: data, identity: identity, context: context)
                : reading(teamInfo: data, identity: identity, context: context)
        }
    }

    /// A route on the proxy the reader named. `/v1` is dropped off what they
    /// typed: people paste the base URL their client uses, and these routes
    /// sit beside it rather than under it.
    private static func url(_ typed: String, _ path: String, query: [String: String] = [:]) -> URL? {
        guard let base = GatewayAddress.url(from: typed, path: path, trimming: ["/v1"]) else { return nil }
        guard !query.isEmpty else { return base }
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        parts?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts?.url
    }

    // MARK: - Reading the replies

    struct Identity: Equatable {
        let user: String?
        let team: String?
    }

    /// A budget as LiteLLM keeps it on a user or a team.
    private struct Budget: Decodable {
        let userId: String?
        let teamId: String?
        let spend: Double?
        let maxBudget: Double?
        let budgetDuration: String?
        let budgetResetAt: String?
    }

    private struct KeyInfo: Decodable {
        struct Info: Decodable {
            let userId: String?
            let teamId: String?
        }

        let info: Info?
    }

    private struct UserInfo: Decodable {
        let userId: String?
        let userInfo: Budget?
        let teams: [Budget]?
    }

    private struct TeamInfo: Decodable {
        let teamId: String?
        let teamInfo: Budget?
    }

    /// LiteLLM writes snake_case throughout.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// The user and team `/key/info` names, blank ones as none.
    static func identity(from data: Data) -> Identity? {
        guard let info = (try? decoder.decode(KeyInfo.self, from: data))?.info else { return nil }
        func named(_ text: String?) -> String? {
            text.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        return Identity(user: named(info.userId), team: named(info.teamId))
    }

    static func reading(userInfo data: Data, identity: Identity, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? decoder.decode(UserInfo.self, from: data),
              let user = reply.userInfo
        else { return context.unavailable(.unreadableReply) }
        // Whichever id the proxy answered with has to be the one asked about.
        if let answered = user.userId ?? reply.userId, answered != identity.user {
            return context.unavailable(.unreadableReply)
        }

        var windows: [UsageWindow] = []
        if let team = identity.team,
           let budget = reply.teams?.first(where: { $0.teamId == team }),
           let window = window(budget, id: "litellm.team", team: true) {
            windows.append(window)
        }
        if let window = window(user, id: "litellm.user", team: false) {
            windows.append(window)
        }
        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, at: now)
    }

    static func reading(teamInfo data: Data, identity: Identity, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? decoder.decode(TeamInfo.self, from: data),
              let team = reply.teamInfo
        else { return context.unavailable(.unreadableReply) }
        if let answered = team.teamId ?? reply.teamId, answered != identity.team {
            return context.unavailable(.unreadableReply)
        }
        guard let window = window(team, id: "litellm.team", team: true) else {
            return context.unavailable(.noLimitsReported)
        }
        return context.reading([window], at: now)
    }

    /// A budget's spend against its limit. A team's pool is its own kind, so
    /// the two rows are told apart and never read as one.
    private static func window(_ budget: Budget, id: String, team: Bool) -> UsageWindow? {
        guard let spend = budget.spend, spend.isFinite, spend >= 0,
              let limit = budget.maxBudget, limit.isFinite, limit > 0
        else { return nil }
        let period = period(budget.budgetDuration)
        let fraction = spend / limit
        return UsageWindow(
            id: id,
            kind: team ? .sharedCredits : period.kind,
            scope: nil,
            usedFraction: fraction,
            windowSeconds: period.seconds,
            resetsAt: ProfileHTTP.date(budget.budgetResetAt),
            reportsLength: period.stated,
            isExhausted: fraction >= 1
        )
    }

    /// LiteLLM's `budget_duration`: a count and a unit — `30s`, `12h`, `7d`,
    /// `1mo`. Seconds, minutes, hours, days and weeks are a stated length; a
    /// month is a calendar month and only sorts. No duration is a budget that
    /// never turns over.
    static func period(_ duration: String?) -> (kind: UsageWindow.Kind, seconds: Int, stated: Bool) {
        let unstated: (UsageWindow.Kind, Int, Bool) = (.spend, 30 * 86_400, false)
        guard let text = duration?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else {
            return unstated
        }
        let digits = text.prefix { $0.isNumber }
        guard let count = Int(digits), count > 0 else { return unstated }
        let seconds: Int
        switch text.dropFirst(digits.count) {
        case "mo": return (count == 1 ? .monthly : .spend, count * 30 * 86_400, false)
        case "s": seconds = count
        case "m": seconds = count * 60
        case "h": seconds = count * 3_600
        case "d": seconds = count * 86_400
        case "w": seconds = count * 7 * 86_400
        default: return unstated
        }
        let kind: UsageWindow.Kind = switch seconds {
        case 5 * 3_600: .fiveHour
        case 86_400: .daily
        case 7 * 86_400: .weekly
        default: .other(seconds: seconds)
        }
        return (kind, seconds, true)
    }
}
