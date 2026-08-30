import Foundation

/// The OpenCode Go plan's limits.
///
/// The only provider here that Pulse needs a key for. Two places it can come
/// from, in this order:
///
/// 1. **A key pasted into Settings**, kept in the keychain. It wins, because
///    someone who typed a key meant that one to be used — otherwise a stale
///    key left behind by OpenCode would quietly override a deliberate choice.
/// 2. **What OpenCode saved for itself** in `~/.local/share/opencode/auth.json`,
///    which is the same borrowing Claude Code and Codex get, and means anyone
///    already signed in there has nothing to configure.
///
/// The endpoint is `GET /zen/go/v1/usage`, which is not documented — OpenCode's
/// own docs describe only the model endpoints — so it can change without
/// notice, exactly like the two undocumented routes the CLIs use.
struct OpenCodeGoUsageService: Sendable {
    /// The key the user entered, read from the keychain by the caller so this
    /// stays free of both UI and storage concerns.
    let enteredKey: String?

    private static let endpoint = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    func fetch() async -> ProviderUsage {
        guard let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) ?? Self.storedKey() else {
            return .unavailable(.openCodeGo, reason: .openCodeKeyMissing)
        }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .unavailable(.openCodeGo, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        // Not `.signInRequired`: that message names Codex, and a message that
        // names the wrong provider is the exact trap this file's neighbours
        // were fixed for once already.
        case 401, 403: return .unavailable(.openCodeGo, reason: .openCodeKeyRefused)
        case 429: return .unavailable(.openCodeGo, reason: .rateLimited)
        default: return .unavailable(.openCodeGo, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(.openCodeGo, reason: .unreadableReply)
        }

        let windows = Self.windows(from: reply)
        guard !windows.isEmpty else {
            return .unavailable(.openCodeGo, reason: .noLimitsReported)
        }

        return ProviderUsage(
            provider: .openCodeGo,
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

    // MARK: - Reading the reply

    private struct Reply: Decodable {
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
    private static func windows(from reply: Reply) -> [UsageWindow] {
        guard let usage = reply.usage else { return [] }

        return [
            window(usage.rolling, id: "rolling", kind: .fiveHour, seconds: 5 * 3_600),
            window(usage.weekly, id: "weekly", kind: .weekly, seconds: 7 * 86_400),
            window(usage.monthly, id: "monthly", kind: .monthly, seconds: 30 * 86_400),
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
        seconds: Int
    ) -> UsageWindow? {
        guard let reported, let percent = reported.percent else { return nil }

        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: min(max(percent / 100, 0), 1),
            windowSeconds: seconds,
            resetsAt: reported.resetsAt.flatMap(Self.date(from:)),
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
