// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Open Design (open-design.ai), OpenDesign Go included: the plan's credit
/// windows — five hours and seven days on Go, seven days on Plus, Pro and
/// Max — the plan's tier, and the wallet balance when a route states it.
///
/// Two ways in, the first that is there:
///
/// - **The console's browser session**, read from a browser signed in at
///   open-design.ai and kept to its better-auth cookies
///   (`__Secure-better-auth.session_token`, which must be there, and the rest
///   of that prefix). Sent as a `Cookie` header to `amr-api.open-design.ai`,
///   as the console sends it. This is the route for a Go subscriber who only
///   uses the API key and never installed the app.
/// - **The desktop app's login**, saved by Open Design's runtime (`vela`,
///   "AMR") in `~/.amr/config.json` under its `prod` profile: the control key
///   and the API address beside it. Only read, never written. The key is sent
///   only to an `https` address on `open-design.ai`.
///
/// Then, all under `/api/v1/`:
///
/// - `GET workspaces` — the workspaces the login can see. The personal one is
///   read: the owner's default, else the first personal one.
/// - The plan's windows, from the first route that has any, each with the
///   workspace also named in `x-vela-workspace-id`. With the session:
///   `billing/coding-plan-usage` (what the console's usage panel reads), then
///   `billing/snapshot`. With the app's login: `billing/funding-check` (what
///   the desktop daemon reads), then those two. `coding-plan-usage` is
///   `{ eligible, tier, windows: [{ policyId, durationSeconds, usedCredits,
///   remainingCredits, limitCredits, resetsAt }] }`; `funding-check` holds
///   the same under `codingPlan`, beside `balanceUsd`; `snapshot` is
///   `billing.planId`, `wallet.balanceUsd` and `designPlanWindows`.
///   A 401 or 403 from one billing route only rules that route out: the
///   workspace read already showed the login is good, and other projects
///   report `snapshot` answering 403 since October 2026.
///
/// **An OpenDesign Go API key cannot read any of this.** Open Design's API
/// takes the account login for account and billing reads and turns away the
/// keys made for model calls — its own design notes say so, and CodexBar and
/// the DSH plugins found the same — so there is no key field.
///
/// The shapes are second-hand — taken from Open Design's own code (contracts,
/// the daemon's reads, the console's published bundle) and from other
/// projects that read it (CodexBar's OpenDesign plugin, `dsh-opendesign-go`,
/// `dsh-opendesign-corouter`), not from a reply captured here — and the
/// fixtures in the tests say so.
extension ProviderProfile {
    static let openDesign = ProviderProfile(
        displayName: "Open Design",
        iconResource: "opendesign",
        credential: .sessionCookie(
            host: "open-design.ai",
            cookies: ["__Secure-better-auth.session_token", "__Secure-better-auth.*"]
        ),
        accessDescription: {
            .localized("Reads your open-design.ai sign-in from a browser when you press Read, or else the login the Open Design app saved in ~/.amr. Either is sent only to open-design.ai.")
        },
        setupSlug: "open-design",
        discoveryPaths: [".amr", "/Applications/Open Design.app"],
        fetch: { await OpenDesignUsageService.fetch($0) }
    )
}

enum OpenDesignUsageService {
    static let defaultAPI = URL(string: "https://amr-api.open-design.ai")!
    /// The profile Open Design uses unless told otherwise (`resolveAmrProfile`).
    static let profile = "prod"

    struct Login: Equatable {
        let controlKey: String
        let api: URL
    }

    /// Who is asking, and how that goes on a request.
    enum Credential: Equatable {
        /// The console's cookies, as a `Cookie` header.
        case session(String)
        /// The desktop app's control key.
        case app(Login)

        var api: URL {
            switch self {
            case .session: defaultAPI
            case .app(let login): login.api
            }
        }

        /// What a refusal of the workspace read means for this credential.
        var refused: ProviderUsage.Unavailability {
            switch self {
            case .session: .sessionExpired
            case .app: .localLoginExpired
            }
        }

        /// The billing routes to try, in order.
        var routes: [String] {
            switch self {
            case .session: ["coding-plan-usage", "snapshot"]
            case .app: ["funding-check", "coding-plan-usage", "snapshot"]
            }
        }

        func request(_ url: URL, workspace: String? = nil) -> URLRequest {
            var request: URLRequest
            switch self {
            case .session(let cookies):
                request = URLRequest(url: url)
                request.setValue(cookies, forHTTPHeaderField: "Cookie")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                // The console's origin, which the API's CORS rule names.
                request.setValue("https://open-design.ai", forHTTPHeaderField: "Origin")
                request.setValue("https://open-design.ai/cloud/dashboard", forHTTPHeaderField: "Referer")
                request.timeoutInterval = 15
            case .app(let login):
                request = ProfileHTTP.bearer(url, token: login.controlKey)
            }
            if let workspace { request.setValue(workspace, forHTTPHeaderField: "x-vela-workspace-id") }
            return request
        }
    }

    static func fetch(
        _ context: ProfileContext,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        session: URLSession? = nil
    ) async -> ProviderUsage {
        // The browser session first: it was read on purpose, and it is the
        // only way in without the app. A refused session falls back to the
        // app's login when there is one.
        let cookies = context.trimmedCredential.flatMap {
            ProviderProfile.keep($0, cookies: ["__Secure-better-auth.session_token", "__Secure-better-auth.*"])
        }
        let saved = savedLogin(home: home)
        if let cookies {
            let usage = await read(with: .session(cookies), context: context, session: session)
            if case .unavailable(.sessionExpired) = usage.state, let saved {
                return await read(with: .app(saved), context: context, session: session)
            }
            return usage
        }
        if let saved { return await read(with: .app(saved), context: context, session: session) }
        return context.unavailable(.sessionMissing)
    }

    static func read(
        with credential: Credential,
        context: ProfileContext,
        session: URLSession?
    ) async -> ProviderUsage {
        let workspaces = await ProfileHTTP.data(
            for: credential.request(credential.api.appending(path: "api/v1/workspaces")),
            refused: credential.refused,
            session: session
        )
        let workspaceID: String
        switch workspaces {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data):
            guard let id = personalWorkspace(from: data) else { return context.unavailable(.noPlan) }
            workspaceID = id
        }

        // A reading with figures but no window is kept in case no route has
        // one. A route that turns the login away is only that route's answer.
        var fallback: ProviderUsage?
        var lastReason: ProviderUsage.Unavailability = .noLimitsReported
        var refusals = 0
        for route in credential.routes {
            let request = credential.request(billingURL(credential.api, workspaceID, route), workspace: workspaceID)
            switch await ProfileHTTP.data(for: request, refused: credential.refused, session: session) {
            case .failure(credential.refused):
                refusals += 1
            case .failure(let reason):
                lastReason = reason
            case .success(let data):
                let usage = route == "snapshot"
                    ? reading(from: data, context: context)
                    : codingPlanReading(from: data, context: context)
                guard usage.state == .live else { continue }
                if !usage.windows.isEmpty { return usage }
                fallback = fallback ?? usage
            }
        }
        if let fallback { return fallback }
        // Every billing route refused a login the workspace read accepted:
        // this account is not one billing will answer for.
        return context.unavailable(refusals == credential.routes.count ? .noPlan : lastReason)
    }

    static func billingURL(_ api: URL, _ workspaceID: String, _ name: String) -> URL {
        api.appending(path: "api/v1/workspaces")
            .appending(path: workspaceID)
            .appending(path: "billing")
            .appending(path: name)
    }

    /// The `prod` profile's control key and API address. A login still in
    /// progress (`pendingLogin`) does not count. An address that is not
    /// `https` on `open-design.ai` is not one Pulse sends the key to.
    static func savedLogin(home: URL) -> Login? {
        let file = home.appending(path: ".amr/config.json")
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [String: Any],
              let stored = profiles[profile] as? [String: Any]
        else { return nil }
        if let pending = stored["pendingLogin"], !(pending is NSNull) { return nil }
        guard let key = (stored["controlKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }

        let api: URL
        if let text = (stored["apiUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            guard let url = URL(string: text), isOpenDesign(url) else { return nil }
            api = url
        } else {
            api = defaultAPI
        }
        return Login(controlKey: key, api: api)
    }

    static func isOpenDesign(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host()?.lowercased()
        else { return false }
        return host == "open-design.ai" || host.hasSuffix(".open-design.ai")
    }

    /// `{ items: [{ workspaceId, workspaceType, isDefault, … }] }`: the
    /// owner's default personal workspace, else the first personal one.
    static func personalWorkspace(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]]
        else { return nil }
        let personal = items.filter { $0["workspaceType"] as? String == "personal" }
        let chosen = personal.first { $0["isDefault"] as? Bool == true } ?? personal.first
        return (chosen?["workspaceId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Reading the Coding Plan

    /// `{ tier, windows: [{ policyId, durationSeconds, usedCredits,
    /// remainingCredits, limitCredits, resetsAt }] }`, alone (the console's
    /// read) or as `codingPlan` beside `balanceUsd` (the daemon's). A window
    /// is named by its length, as Open Design's own panels name it; a length
    /// Pulse has no kind for is left off.
    static func codingPlanReading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return context.unavailable(.unreadableReply) }
        let plan = root["codingPlan"] as? [String: Any] ?? root

        var windows: [UsageWindow] = []
        for window in plan["windows"] as? [[String: Any]] ?? [] {
            let remaining = credits(window["remainingCredits"])
            guard let limit = credits(window["limitCredits"]), limit > 0,
                  let used = credits(window["usedCredits"]) ?? remaining.map({ max(limit - min($0, limit), 0) }),
                  let duration = (window["durationSeconds"] as? NSNumber)?.intValue,
                  let seconds = UsageWindow.length(duration, unitSeconds: 1),
                  let kind = kind(lasting: seconds)
            else { continue }
            let policy = (window["policyId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(seconds)s"
            windows.append(UsageWindow(
                id: "openDesign.codingPlan.\(policy)",
                kind: kind,
                scope: nil,
                usedFraction: min(used / limit, 1),
                windowSeconds: seconds,
                resetsAt: ProfileHTTP.date(window["resetsAt"] as? String),
                isExhausted: remaining.map { $0 <= 0 } ?? (used >= limit)
            ))
        }
        windows.sort { $0.windowSeconds < $1.windowSeconds }

        let balance = money(root["balanceUsd"])
        guard !windows.isEmpty || balance != nil else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: tier(plan["tier"]), creditBalance: balance, at: now)
    }

    /// The kinds a Coding Plan window can be, by its length.
    private static func kind(lasting seconds: Int) -> UsageWindow.Kind? {
        switch seconds {
        case 5 * 3_600: .fiveHour
        case 86_400: .daily
        case 7 * 86_400: .weekly
        case 28 * 86_400...31 * 86_400: .monthly
        default: nil
        }
    }

    // MARK: - Reading the snapshot

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return context.unavailable(.unreadableReply) }

        var windows: [UsageWindow] = []
        for window in root["designPlanWindows"] as? [[String: Any]] ?? [] {
            // Credits are integers written as strings; a limit of zero or
            // less, or a missing figure, is left off rather than drawn.
            guard let limit = credits(window["limitCredits"]), limit > 0,
                  let remaining = credits(window["remainingCredits"])
            else { continue }
            let shape: (id: String, kind: UsageWindow.Kind, seconds: Int)? = switch window["kind"] as? String {
            case "5h": ("openDesign.fiveHour", .fiveHour, 5 * 3_600)
            case "7d": ("openDesign.weekly", .weekly, 7 * 86_400)
            default: nil
            }
            guard let (id, kind, seconds) = shape else { continue }
            let used = max(limit - min(remaining, limit), 0)
            windows.append(UsageWindow(
                id: id,
                kind: kind,
                scope: nil,
                usedFraction: used / limit,
                windowSeconds: seconds,
                resetsAt: ProfileHTTP.date(window["resetsAt"] as? String),
                isExhausted: remaining <= 0
            ))
        }
        windows.sort { $0.windowSeconds < $1.windowSeconds }

        let billing = root["billing"] as? [String: Any]
        let plan = tier(billing?["planId"])
        let balance = money((root["wallet"] as? [String: Any])?["balanceUsd"])

        guard !windows.isEmpty || balance != nil else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: plan, creditBalance: balance, at: now)
    }

    /// `go`, `plus`, `pro`, `max` → "Go", "Plus", …
    private static func tier(_ value: Any?) -> String? {
        (value as? String)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    /// US dollars written as a decimal string.
    private static func money(_ value: Any?) -> String? {
        (value as? String)
            .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .flatMap { $0.isFinite ? Money.reported($0, code: "USD") : nil }
    }

    /// A credit count: digits in a string, or a non-negative number.
    private static func credits(_ value: Any?) -> Double? {
        let figure: Double? = switch value {
        case let text as String: Double(text.trimmingCharacters(in: .whitespaces))
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): number.doubleValue
        default: nil
        }
        guard let figure, figure.isFinite, figure >= 0 else { return nil }
        return figure
    }
}
