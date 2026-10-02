// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Gemini CLI's quota: how much of each model's allowance is left, as a
/// fraction Google reports itself, with the time each one resets.
///
/// Read with the login Gemini CLI saved in `~/.gemini/oauth_creds.json`, from
/// the two endpoints the CLI itself calls: `loadCodeAssist`, which names the
/// account's project and tier, then `retrieveUserQuota` for that project. The
/// shape is second-hand — taken from CodexBar's Gemini provider and its tests,
/// not from a captured reply — and the fixture in the tests says so.
///
/// **The login is only ever read.** It is Gemini CLI's, and it lasts an hour.
/// CodexBar renews it by lifting Google's client secret out of the installed
/// CLI and writing the new token back into the CLI's file; Pulse does neither.
/// An expired token is reported as one, and using Gemini CLI renews it.
///
/// **One row per model, as Google reports them.** CodexBar folds the models
/// into Pro, Flash and Flash Lite; those families are its own grouping, so
/// here each model keeps its own name. Where a model has several buckets —
/// one per token type — the one with least left is the one that bites.
extension ProviderProfile {
    static let gemini = ProviderProfile(
        displayName: "Gemini",
        iconResource: "geminicli",
        credential: .localLogin,
        accessDescription: { .localized("Reads the login saved in ~/.gemini/oauth_creds.json. No Keychain prompt.") },
        soleRoute: {
            (.localized("Gemini CLI's own login"),
             .localized("Uses the login Gemini CLI already saved. Using Gemini CLI renews it."))
        },
        setupSlug: "gemini",
        discoveryPaths: [".gemini"],
        fetch: { await GeminiUsageService.fetch($0) }
    )
}

enum GeminiUsageService {
    static let loadCodeAssistEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    static let quotaEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!

    static func fetch(
        _ context: ProfileContext,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        session: URLSession? = nil,
        now: Date = Date()
    ) async -> ProviderUsage {
        let folder = home.appendingPathComponent(".gemini", isDirectory: true)

        // Signed in with a key or with Vertex, the CLI has no Google login for
        // Pulse to read, whatever an old credentials file still says.
        if let settings = try? Data(contentsOf: folder.appendingPathComponent("settings.json")),
           !usesGoogleLogin(settings) {
            return context.unavailable(.localLoginMissing)
        }

        guard let saved = try? Data(contentsOf: folder.appendingPathComponent("oauth_creds.json")) else {
            return context.unavailable(.localLoginMissing)
        }
        let token: String
        switch accessToken(from: saved, now: now) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let value): token = value
        }

        // The project and the plan. Best-effort, as the CLI treats it: a
        // quota asked for without a project is still the account's quota.
        var codeAssist = CodeAssist()
        switch await ProfileHTTP.reply(for: post(loadCodeAssistEndpoint, token: token, body: [
            "metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"],
        ]), session: session) {
        case .success(let reply) where reply.status == 401:
            return context.unavailable(.localLoginExpired)
        case .success(let reply) where !(200..<300).contains(reply.status)
            && saysUnsupported(String(decoding: reply.data, as: UTF8.self)):
            return context.unavailable(.noPlan)
        case .success(let reply) where (200..<300).contains(reply.status):
            codeAssist = Self.codeAssist(from: reply.data)
        default:
            break
        }

        let body: [String: Any] = codeAssist.project.map { ["project": $0] } ?? [:]
        switch await ProfileHTTP.reply(for: post(quotaEndpoint, token: token, body: body), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let reply):
            switch quota(reply, unsupportedClient: codeAssist.unsupportedClient) {
            case .failure(let reason): return context.unavailable(reason)
            case .success(let data): return reading(from: data, context: context, plan: codeAssist.plan, now: now)
            }
        }
    }

    // MARK: - The saved login

    /// Whether the CLI's settings leave it signed in with Google. Only a key or
    /// Vertex say otherwise; a file that names neither is given the benefit.
    static func usesGoogleLogin(_ settings: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: settings) as? [String: Any] else { return true }
        let nested = ((json["security"] as? [String: Any])?["auth"] as? [String: Any])?["selectedType"] as? String
        let selected = nested ?? json["selectedAuthType"] as? String
        return !["gemini-api-key", "api-key", "vertex-ai"].contains(selected ?? "")
    }

    /// The access token in Gemini CLI's credentials, or why it can't be used.
    /// `expiry_date` is in milliseconds. A token past it is not sent: Google
    /// would refuse it, and renewing it is the CLI's business.
    static func accessToken(from data: Data, now: Date = Date()) -> Result<String, ProviderUsage.Unavailability> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.localLoginMissing)
        }
        guard let token = (json["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return .failure(.localLoginExpired) }
        if let milliseconds = (json["expiry_date"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: milliseconds / 1000) <= now {
            return .failure(.localLoginExpired)
        }
        return .success(token)
    }

    // MARK: - The account

    struct CodeAssist: Equatable {
        var project: String?
        /// Google's own name for the plan, when it gives one.
        var plan: String?
        /// Google listed this client as no longer serving the account's tier —
        /// its answer to the consumer accounts it moved off Gemini CLI.
        var unsupportedClient = false
    }

    static func codeAssist(from data: Data) -> CodeAssist {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return CodeAssist() }

        let companion = json["cloudaicompanionProject"]
        let rawProject = companion as? String
            ?? (companion as? [String: Any]).flatMap { $0["id"] as? String ?? $0["projectId"] as? String }
        let project = rawProject?.trimmingCharacters(in: .whitespacesAndNewlines)

        // A named paid tier is the most specific thing Google says about the
        // plan; the current tier's name is the fallback. Neither is guessed.
        let paid = (json["paidTier"] as? [String: Any])?["name"] as? String
        let current = (json["currentTier"] as? [String: Any])?["name"] as? String
        let plan = [paid, current]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let ineligible = json["ineligibleTiers"] as? [[String: Any]] ?? []
        let unsupported = paid == nil && json["currentTier"] == nil && ineligible.contains { tier in
            [tier["reasonCode"], tier["reasonMessage"]].compactMap { $0 as? String }.contains(where: saysUnsupported)
        }

        return CodeAssist(project: project?.isEmpty == false ? project : nil, plan: plan, unsupportedClient: unsupported)
    }

    /// Google's wording for "this client no longer serves this account".
    static func saysUnsupported(_ text: String) -> Bool {
        let text = text.lowercased()
        return text.contains("unsupported_client") || text.contains("ineligibletiererror")
    }

    // MARK: - Reading the reply

    /// What the quota call's status means. A 403 is a refused login unless
    /// Google said, here or in the tier lookup, that the account's tier is no
    /// longer served — then there is no plan here to read, and signing in
    /// again would not change that.
    static func quota(_ reply: ProfileHTTP.Reply, unsupportedClient: Bool) -> Result<Data, ProviderUsage.Unavailability> {
        if reply.status == 403 {
            let body = String(decoding: reply.data, as: UTF8.self)
            if unsupportedClient || saysUnsupported(body) { return .failure(.noPlan) }
        }
        return ProfileHTTP.classify(reply, refused: .localLoginExpired)
    }

    private struct Reply: Decodable {
        struct Bucket: Decodable {
            let modelId: String?
            let remainingFraction: Double?
            let resetTime: String?
        }

        let buckets: [Bucket]?
    }

    /// Google states when each bucket resets and never how long it runs.
    /// Its Gemini CLI quotas are published as daily ones, so the row is named
    /// daily and sorted as a day — but the length is not claimed, and no
    /// elapsed arc is drawn from it.
    static func reading(from data: Data, context: ProfileContext, plan: String? = nil, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), let buckets = reply.buckets else {
            return context.unavailable(.unreadableReply)
        }

        var least: [String: (remaining: Double, resetsAt: String?)] = [:]
        for bucket in buckets {
            guard let model = bucket.modelId?.trimmingCharacters(in: .whitespaces), !model.isEmpty,
                  let remaining = bucket.remainingFraction, remaining.isFinite, (0...1).contains(remaining)
            else { continue }
            if let known = least[model], known.remaining <= remaining { continue }
            least[model] = (remaining, bucket.resetTime)
        }

        let windows = least.keys.sorted().compactMap { model -> UsageWindow? in
            guard let entry = least[model] else { return nil }
            return UsageWindow(
                id: "gemini.\(model)",
                kind: .daily,
                scope: model,
                usedFraction: 1 - entry.remaining,
                windowSeconds: 86_400,
                resetsAt: ProfileHTTP.date(entry.resetsAt),
                reportsLength: false,
                isExhausted: entry.remaining <= 0
            )
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: plan, at: now)
    }

    // MARK: - Requests

    private static func post(_ url: URL, token: String, body: [String: Any]) -> URLRequest {
        var request = ProfileHTTP.bearer(url, token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}
