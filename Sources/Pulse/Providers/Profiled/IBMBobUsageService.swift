// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// IBM Bob: the month's Bobcoins against each team's budget.
///
/// Read with a key the user pastes, in two steps, from the admin routes Bob's
/// own tools call:
/// 1. `GET https://api.us-east.bob.ibm.com/admin/v1/profile` lists the
///    subscriptions the key can see, each with its teams, the user's id in
///    it, and the regional host that serves it.
/// 2. `GET https://api.<region>/admin/v1/teams/<team>/users/<user>` for each
///    team gives the Bobcoins used and the budget.
///
/// The shape is second-hand — taken from CodexBar's IBM Bob provider and its
/// tests, not from a captured reply — and the fixtures in the tests say so.
///
/// **The key goes to IBM Bob's hosts and nowhere else.** The regional host
/// comes from the reply; one that is not `bob.ibm.com` or under it, or that
/// carries anything but a bare host, is refused before anything is sent.
///
/// **One ring, only when every team has a budget.** Bobcoins are counted per
/// month; a team with no budget is unlimited, and adding its usage to the
/// others' budgets would make a fraction nobody reported. So the sum is drawn
/// only when every team states one. The period is a billing month, so its
/// length is a sort key and is not claimed.
extension ProviderProfile {
    static let ibmBob = ProviderProfile(
        displayName: "IBM Bob",
        iconResource: "ibm",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From bob.ibm.com. Stored encrypted on this Mac.") },
        setupSlug: "ibm-bob",
        fetch: { await IBMBobUsageService.fetch($0) }
    )
}

enum IBMBobUsageService {
    static let home = URL(string: "https://api.us-east.bob.ibm.com")!

    struct Team: Equatable {
        let used: Double
        let budget: Double?
        let plan: String?
        let resetsAt: Date?
    }

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }

        let profile: Profile
        switch await ProfileHTTP.data(for: request(home.appending(path: "admin/v1/profile"), key: key), session: session) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data):
            guard let decoded = try? JSONDecoder().decode(Profile.self, from: data) else {
                return context.unavailable(.unreadableReply)
            }
            profile = decoded
        }

        var teams: [Team] = []
        for instance in profile.instances {
            guard let user = instance.userID, !user.isEmpty else { continue }
            guard let base = regionalHost(instance.regionDomain) else { return context.unavailable(.unreadableReply) }
            for team in instance.teams where !team.id.isEmpty {
                let url = base.appending(path: "admin/v1/teams").appending(path: team.id)
                    .appending(path: "users").appending(path: user)
                var ask = request(url, key: key)
                ask.setValue(instance.instanceID, forHTTPHeaderField: "x-instance-id")
                ask.setValue(team.id, forHTTPHeaderField: "x-team-id")
                switch await ProfileHTTP.data(for: ask, session: session) {
                case .failure(let reason): return context.unavailable(reason)
                case .success(let data):
                    guard let budget = try? JSONDecoder().decode(Budget.self, from: data) else {
                        return context.unavailable(.unreadableReply)
                    }
                    teams.append(Team(
                        used: budget.usage,
                        budget: budget.budgetLimit ?? team.budgetLimit,
                        plan: instance.planName,
                        resetsAt: instance.refreshAt?.date
                    ))
                }
            }
        }
        return reading(teams, context: context)
    }

    /// What the key is sent as: a JWT from a Bob sign-in as a bearer token,
    /// anything else as an IBM API key.
    static func authorization(_ key: String) -> String {
        isJWT(key) ? "Bearer \(key)" : "Apikey \(key)"
    }

    private static func request(_ url: URL, key: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(authorization(key), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func isJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }

    /// The regional host a subscription names, as an https URL, or nil for
    /// one the key must not be sent to. No region named is the home host.
    static func regionalHost(_ domain: String?) -> URL? {
        guard let domain = domain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty else {
            return home
        }
        let host = (domain.lowercased().hasPrefix("api.") ? domain : "api.\(domain)").lowercased()
        // A bare host and nothing else: no path, port, user or query to hide
        // another host behind.
        guard host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }),
              host == "bob.ibm.com" || host.hasSuffix(".bob.ibm.com"),
              let url = URL(string: "https://\(host)"), url.host == host
        else { return nil }
        return url
    }

    // MARK: - Reading the replies

    struct Profile: Decodable {
        struct Instance: Decodable {
            struct Team: Decodable {
                let id: String
                let budgetLimit: Double?

                enum CodingKeys: String, CodingKey {
                    case id
                    case budgetLimit = "budget_limit"
                }
            }

            let instanceID: String
            let userID: String?
            let planName: String?
            let refreshAt: Moment?
            let regionDomain: String?
            let teams: [Team]

            enum CodingKeys: String, CodingKey {
                case instanceID = "instance_id"
                case userID = "user_id"
                case planName = "plan_name"
                case refreshAt = "refresh_at"
                case regionDomain = "region_domain"
                case teams
            }
        }

        let instances: [Instance]
    }

    /// `refresh_at` has come as Unix seconds and as an ISO 8601 string.
    struct Moment: Decodable {
        let date: Date?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                date = seconds.isFinite && seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
            } else {
                date = ProfileHTTP.date(try? container.decode(String.self))
            }
        }
    }

    struct Budget: Decodable {
        let usage: Double
        let budgetLimit: Double?

        enum CodingKeys: String, CodingKey {
            case usage
            case budgetLimit = "budget_limit"
        }
    }

    static func reading(_ teams: [Team], context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard !teams.isEmpty else { return context.unavailable(.noPlan) }
        let plans = Array(Set(teams.compactMap { $0.plan?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })).sorted()
        let plan = plans.isEmpty ? nil : plans.joined(separator: ", ")

        let budgets = teams.compactMap(\.budget)
        guard budgets.count == teams.count,
              teams.allSatisfy({ $0.used.isFinite && $0.used >= 0 }),
              budgets.allSatisfy({ $0.isFinite && $0 >= 0 })
        else { return context.unavailable(.noLimitsReported) }
        let used = teams.reduce(0) { $0 + $1.used }
        let budget = budgets.reduce(0, +)
        guard budget > 0 else { return context.unavailable(.noLimitsReported) }

        let window = UsageWindow(
            id: "ibmbob.bobcoins",
            kind: .monthly,
            scope: nil,
            usedFraction: used / budget,
            windowSeconds: 30 * 86_400,
            resetsAt: teams.compactMap(\.resetsAt).min(),
            reportsLength: false,
            isExhausted: used >= budget
        )
        return context.reading([window], plan: plan, at: now)
    }
}
