// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The OpenCode Go plan's limits.
///
/// Needs a key. Two places it can come from, in this order:
///
/// 1. **A key pasted into Settings**, kept encrypted on this Mac. It wins, because
///    someone who typed a key meant that one to be used — otherwise a stale
///    key left behind by OpenCode would quietly override a deliberate choice.
/// 2. **What OpenCode saved for itself** in `~/.local/share/opencode/auth.json`,
///    which is the same borrowing Claude Code and Codex get, and means anyone
///    already signed in there has nothing to configure.
///
/// The endpoint is `GET /zen/go/v1/usage`, which is not documented — OpenCode's
/// own docs describe only the model endpoints — so it can change without
/// notice, exactly like the two undocumented routes the CLIs use.
///
/// **A third way in: the console's session**, read from the browser in
/// Settings for the request log (`OpenCodeConsole`). The console answers the
/// same three limits at `GET /console/api/go/status`, in money rather than in
/// percent. It is asked when there is no key at all, or when the key route
/// turned the key away or did not answer — never instead of a key that works,
/// so nobody who set one up is moved off it.
struct OpenCodeGoUsageService: Sendable {
    /// The key the user entered, read by the caller so this stays free of
    /// both UI and storage concerns.
    let enteredKey: String?
    /// The console's session, from its own slot beside the key.
    var consoleCookie: String?

    private static let endpoint = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    func fetch() async -> ProviderUsage {
        guard let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) ?? Self.storedKey() else {
            if let consoleCookie { return await Self.fetchConsole(cookie: consoleCookie) }
            return .unavailable(.openCodeGo, reason: .apiKeyMissing)
        }

        let byKey = await fetch(key: key)
        // The console stands in only where the key could not answer. A
        // reading the key did get — even one with no limits in it — stands.
        if case .unavailable(let reason) = byKey.state,
           [.apiKeyRefused, .noPlan, .unreachable, .serverError, .unreadableReply].contains(reason),
           let consoleCookie {
            let byConsole = await Self.fetchConsole(cookie: consoleCookie)
            if case .live = byConsole.state { return byConsole }
        }
        return byKey
    }

    private func fetch(key: String) async -> ProviderUsage {

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        guard let (data, response) = try? await NetworkSession.shared.recordedData(for: request, delegate: NoRedirects()) else {
            return .unavailable(.openCodeGo, reason: .unreachable)
        }

        if let refusal = Self.refusal(status: (response as? HTTPURLResponse)?.statusCode, body: data) {
            return .unavailable(.openCodeGo, reason: refusal)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(.openCodeGo, reason: .unreadableReply)
        }

        let windows = Self.windows(from: reply)
        guard !windows.isEmpty else {
            return .unavailable(.openCodeGo, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: AccountKey(.openCodeGo),
            windows: windows,
            observedAt: Date(),
            state: .live,
            // The reply carries limits and nothing else — no plan name, no
            // balance — so neither is invented here.
            plan: nil,
            creditBalance: nil
        )
    }

    /// The key `opencode` wrote when it signed in.
    /// Why the usage endpoint said no, or nil for a 200.
    ///
    /// **A 403 is not always the key.** A valid key whose workspace has no Go
    /// subscription is answered `403` with `"type":"EntitlementError"`
    /// ("OpenCode Go subscription required."), measured 2026-10-15; calling
    /// that a refused key sent people to replace a key that worked. A 401, and
    /// any other 403, is the key.
    static func refusal(status: Int?, body: Data) -> ProviderUsage.Unavailability? {
        switch status {
        case 200: return nil
        case 403 where Self.isEntitlementError(body): return .noPlan
        // Not `.signInRequired`: that message names Codex, and a message that
        // names the wrong provider is the exact trap this file's neighbours
        // were fixed for once already.
        case 401, 403: return .apiKeyRefused
        case 429: return .rateLimited
        default: return .serverError
        }
    }

    private static func isEntitlementError(_ body: Data) -> Bool {
        struct Failure: Decodable {
            struct Detail: Decodable { let type: String? }
            let error: Detail?
        }
        return (try? JSONDecoder().decode(Failure.self, from: body))?.error?.type == "EntitlementError"
    }

    static func storedKey() -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: ".local/share/opencode/auth.json")

        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entry = root["opencode-go"] as? [String: Any],
            let key = entry["key"] as? String,
            !key.isEmpty
        else { return nil }

        return key
    }

    // MARK: - The console

    private static let consoleStatus = URL(string: "https://\(OpenCodeConsole.host)/console/api/go/status")!

    static func fetchConsole(cookie: String) async -> ProviderUsage {
        let org: String
        switch await OpenCodeConsoleWorkspace.shared.resolve(cookie: cookie) {
        case .workspace(let workspace): org = workspace.id
        case .signedOut: return .unavailable(.openCodeGo, reason: .sessionExpired)
        case .failed: return .unavailable(.openCodeGo, reason: .serverError)
        }

        var request = URLRequest(url: consoleStatus)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(org, forHTTPHeaderField: "x-org-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await NetworkSession.shared.recordedData(for: request, delegate: NoRedirects()) else {
            return .unavailable(.openCodeGo, reason: .unreachable)
        }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(.openCodeGo, reason: .sessionExpired)
        case 429: return .unavailable(.openCodeGo, reason: .rateLimited)
        default: return .unavailable(.openCodeGo, reason: .serverError)
        }
        guard let status = try? JSONDecoder().decode(ConsoleStatus.self, from: data) else {
            // Signed out, the console answers its sign-in page.
            let text = String(decoding: data.prefix(64), as: UTF8.self)
            return .unavailable(.openCodeGo, reason: text.contains("<") ? .sessionExpired : .unreadableReply)
        }
        let windows = windows(from: status)
        guard !windows.isEmpty else {
            return .unavailable(.openCodeGo, reason: status.access == nil ? .noPlan : .noLimitsReported)
        }

        var usage = ProviderUsage(
            account: AccountKey(.openCodeGo),
            windows: windows,
            observedAt: Date(),
            state: .live,
            // The console names the product it bills; the key's reply names none.
            plan: status.product == "go" ? "Go" : nil,
            creditBalance: nil
        )
        usage.origin = .webSession
        return usage
    }

    /// Whether a workspace holds a Go subscription, for choosing among several.
    static func hasGoAccess(cookie: String, org: String) async -> Bool {
        var request = URLRequest(url: consoleStatus)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(org, forHTTPHeaderField: "x-org-id")
        request.timeoutInterval = 15
        guard let (data, response) = try? await NetworkSession.shared.recordedData(for: request, delegate: NoRedirects()),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let status = try? JSONDecoder().decode(ConsoleStatus.self, from: data)
        else { return false }
        return status.access != nil
    }

    /// The console's answer: the plan's three meters, each in micro-cents
    /// used against a limit, with when it started and when it resets.
    ///
    /// Internal for the fixture test, like `Reply`. **Only these fields are
    /// decoded**: the reply also names the payment method and the account,
    /// which Pulse has no use for and does not hold.
    struct ConsoleStatus: Decodable {
        struct Meter: Decodable {
            let startsAt: String?
            let resetsAt: String?
            /// Strings in the reply: a micro-cent count runs past what JSON
            /// numbers carry exactly.
            let limitMicroCents: String?
            let usedMicroCents: String?
        }

        struct Meters: Decodable {
            let fiveHour: Meter?
            let week: Meter?
            let month: Meter?
        }

        struct Access: Decodable {
            let startsAt: String?
            let endsAt: String?
            let meters: Meters?
        }

        let product: String?
        let access: Access?
    }

    /// The same three windows, under the same ids, as the key's reply — so a
    /// pinned limit and the rest of the app see one plan whichever route
    /// answered.
    ///
    /// **The fraction is the console's own two figures**, used over limit.
    /// Its lengths are measured where it states a start: the five-hour and
    /// weekly meters do; the monthly one starts with the billing period, which
    /// is the subscription's access when the two end together.
    static func windows(from status: ConsoleStatus) -> [UsageWindow] {
        guard let meters = status.access?.meters else { return [] }
        let periodStart = status.access?.endsAt == meters.month?.resetsAt ? status.access?.startsAt : nil
        return [
            consoleWindow(meters.fiveHour, id: "rolling", kind: .fiveHour, seconds: 5 * 3_600, startsAt: meters.fiveHour?.startsAt),
            consoleWindow(meters.week, id: "weekly", kind: .weekly, seconds: 7 * 86_400, startsAt: meters.week?.startsAt),
            consoleWindow(meters.month, id: "monthly", kind: .monthly, seconds: 30 * 86_400, startsAt: periodStart),
        ].compactMap { $0 }
    }

    private static func consoleWindow(
        _ meter: ConsoleStatus.Meter?,
        id: String,
        kind: UsageWindow.Kind,
        seconds: Int,
        startsAt: String?
    ) -> UsageWindow? {
        guard let meter,
              let limit = meter.limitMicroCents.flatMap({ Decimal(string: $0) }), limit > 0,
              let used = meter.usedMicroCents.flatMap({ Decimal(string: $0) })
        else { return nil }

        let fraction = NSDecimalNumber(decimal: used / limit).doubleValue
        let resets = meter.resetsAt.flatMap(Self.date(from:))
        let start = startsAt.flatMap(Self.date(from:))
        let measured = resets.flatMap { end in start.map { Int(end.timeIntervalSince($0)) } }.flatMap { $0 > 0 ? $0 : nil }

        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: min(max(fraction, 0), 1),
            windowSeconds: measured ?? seconds,
            resetsAt: resets,
            // A length the console stated by giving a start; otherwise the
            // nominal one, there to sort by and not to divide by.
            reportsLength: measured != nil,
            isExhausted: used >= limit
        )
    }

    // MARK: - Reading the reply

    /// Internal rather than private, and deliberately: this and `windows(from:)`
    /// below are what a fixture test holds a reconstructed reply against.
    /// Nothing outside the module can see them either way. Do not tidy these
    /// back to `private` — that takes the fixture test with it.
    struct Reply: Decodable {
        struct Window: Decodable {
            let status: String?
            /// How much is *gone*, 0...100.
            let percent: Double?
            let resetsAt: String?
        }

        struct Usage: Decodable {
            let rolling: Window?
            let weekly: Window?
            let monthly: Window?
        }

        let usage: Usage?
    }

    /// Shortest window first, which is the order the other providers' limits
    /// arrive in and the order they matter in — the one about to bite leads.
    static func windows(from reply: Reply) -> [UsageWindow] {
        guard let usage = reply.usage else { return [] }

        return [
            window(usage.rolling, id: "rolling", kind: .fiveHour, seconds: 5 * 3_600),
            window(usage.weekly, id: "weekly", kind: .weekly, seconds: 7 * 86_400),
            // **A month is not thirty days.** The reply states its reset and
            // no start, so the length only orders the row; claimed as reported
            // it set a 28- or 31-day cycle's window clock and burn rate by 30.
            // The console route already says the same when it has no start.
            window(usage.monthly, id: "monthly", kind: .monthly, seconds: 30 * 86_400, reportsLength: false),
        ].compactMap { $0 }
    }

    /// The reply calls the short window "rolling" and never says how long it
    /// runs, but it is the five-hour one — measured, the reset it reports lands
    /// five hours out. So it is named as such rather than by the key it arrives
    /// under; the key stays the id, which is what a pinned window is matched on.
    ///
    /// `seconds` orders the rows. Only the reset stamp is ever displayed, so
    /// for weekly and monthly these are the nominal lengths their names imply.
    private static func window(
        _ reported: Reply.Window?,
        id: String,
        kind: UsageWindow.Kind,
        seconds: Int,
        reportsLength: Bool = true
    ) -> UsageWindow? {
        guard let reported, let percent = reported.percent else { return nil }

        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: min(max(percent / 100, 0), 1),
            windowSeconds: seconds,
            resetsAt: reported.resetsAt.flatMap(Self.date(from:)),
            reportsLength: reportsLength,
            // The provider's own verdict, not one inferred from the
            // percentage. Anything other than "ok" is treated as spent —
            // erring towards "you're blocked" is the safer way to be wrong.
            isExhausted: (reported.status ?? "ok").lowercased() != "ok"
        )
    }

    /// Built per call: `ISO8601DateFormatter` is not `Sendable`, and this
    /// parses three stamps a refresh. The stamps carry milliseconds.
    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
