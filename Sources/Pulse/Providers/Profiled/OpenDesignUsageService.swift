// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Open Design (open-design.ai), OpenDesign Go included: the plan's credit
/// windows — five hours and seven days on Go, seven days on Plus, Pro and
/// Max — the plan's tier, and the wallet balance.
///
/// Read with the login Open Design's own runtime (`vela`, "AMR") saved in
/// `~/.amr/config.json`, under its `prod` profile: the control key and the API
/// address beside it. Only read, never written; nothing else in the file is
/// kept. The key is sent only to an `https` address on `open-design.ai`.
///
/// - `GET /api/v1/workspaces` — the workspaces the login can see. The
///   personal one is read: the owner's default, else the first personal one.
/// - `GET /api/v1/workspaces/<id>/billing/funding-check` — the Coding Plan:
///   `codingPlan.tier` and `codingPlan.windows`, each with its
///   `durationSeconds`, `usedCredits`, `limitCredits` and `resetsAt`, and
///   `balanceUsd`. This is what Open Design's own billing panel draws.
/// - `GET /api/v1/workspaces/<id>/billing/snapshot` — only when that answers
///   with no window: `billing.planId`, `wallet.balanceUsd` and
///   `designPlanWindows` (`kind` `5h` or `7d`, `remainingCredits`,
///   `limitCredits`, `resetsAt`).
///
/// **An OpenDesign Go API key cannot read any of this.** Open Design's API
/// takes only the account login (the control key) for billing and turns away
/// the keys made for model calls, so there is no key field.
///
/// The shapes are second-hand — taken from Open Design's own source (its
/// `WorkspaceBillingPreflight` and `WorkspaceBillingSnapshot` contracts, the
/// daemon's billing and workspace directory reads and its end-to-end billing
/// fixture), not from a captured reply — and the fixtures in the tests say so.
extension ProviderProfile {
    static let openDesign = ProviderProfile(
        displayName: "Open Design",
        iconResource: "opendesign",
        credential: .localLogin,
        accessDescription: {
            .localized("Reads the login Open Design saved in ~/.amr and sends it only to open-design.ai. No Keychain prompt.")
        },
        soleRoute: {
            (.localized("Open Design login"), .localized("Uses the login Open Design already saved on this Mac."))
        },
        setupSlug: "open-design",
        discoveryPaths: [".amr"],
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

    static func fetch(
        _ context: ProfileContext,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        session: URLSession? = nil
    ) async -> ProviderUsage {
        guard let login = savedLogin(home: home) else { return context.unavailable(.localLoginMissing) }

        let workspaces = await ProfileHTTP.data(
            for: ProfileHTTP.bearer(login.api.appending(path: "api/v1/workspaces"), token: login.controlKey),
            refused: .localLoginExpired,
            session: session
        )
        let workspaceID: String
        switch workspaces {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data):
            guard let id = personalWorkspace(from: data) else { return context.unavailable(.noPlan) }
            workspaceID = id
        }

        // The Coding Plan first: it is what the plan is enforced by. A login
        // turned away here is turned away everywhere, so that is final; any
        // other failure, or an answer with no window, falls to the snapshot.
        let funding = await ProfileHTTP.data(
            for: ProfileHTTP.bearer(billingURL(login, workspaceID, "funding-check"), token: login.controlKey),
            refused: .localLoginExpired,
            session: session
        )
        var codingPlan: ProviderUsage?
        switch funding {
        case .failure(.localLoginExpired): return context.unavailable(.localLoginExpired)
        case .failure: break
        case .success(let data):
            let usage = codingPlanReading(from: data, context: context)
            if usage.state == .live, !usage.windows.isEmpty { return usage }
            if usage.state == .live { codingPlan = usage }
        }

        switch await ProfileHTTP.data(
            for: ProfileHTTP.bearer(billingURL(login, workspaceID, "snapshot"), token: login.controlKey),
            refused: .localLoginExpired,
            session: session
        ) {
        case .success(let data):
            let usage = reading(from: data, context: context)
            if usage.state == .live { return usage }
            return codingPlan ?? usage
        case .failure(let reason):
            return codingPlan ?? context.unavailable(reason)
        }
    }

    static func billingURL(_ login: Login, _ workspaceID: String, _ name: String) -> URL {
        var url = login.api.appending(path: "api/v1/workspaces")
            .appending(path: workspaceID)
            .appending(path: "billing")
            .appending(path: name)
        url.append(queryItems: [URLQueryItem(name: "workspaceId", value: workspaceID)])
        return url
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

    /// `{ balanceUsd, codingPlan: { tier, windows: [{ policyId,
    /// durationSeconds, usedCredits, remainingCredits, limitCredits,
    /// resetsAt }] } }`. A window is named by its length, as Open Design's own
    /// panel names it; a length Pulse has no kind for is left off.
    static func codingPlanReading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return context.unavailable(.unreadableReply) }
        let plan = root["codingPlan"] as? [String: Any]

        var windows: [UsageWindow] = []
        for window in plan?["windows"] as? [[String: Any]] ?? [] {
            guard let limit = credits(window["limitCredits"]), limit > 0,
                  let used = credits(window["usedCredits"]),
                  let duration = (window["durationSeconds"] as? NSNumber)?.intValue,
                  let seconds = UsageWindow.length(duration, unitSeconds: 1),
                  let kind = kind(lasting: seconds)
            else { continue }
            let remaining = credits(window["remainingCredits"])
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
        return context.reading(windows, plan: tier(plan?["tier"]), creditBalance: balance, at: now)
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
