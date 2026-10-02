// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CryptoKit
import Foundation
import SQLite3

/// Devin's daily and weekly quota, read from the cache its own desktop app
/// keeps.
///
/// Devin is Cognition's agent, and `Devin.app` is the former Windsurf editor —
/// the bundle identifier is still `com.exafunction.windsurf` and every key it
/// writes is still named `windsurf.*`. That inheritance is the whole reason
/// this route exists: it is a VS Code fork, so it keeps its global state in
/// `User/globalStorage/state.vscdb`, an ordinary SQLite file, and the plan it
/// last read from the account is one row in it.
///
/// ```json
/// { "planName": "Pro", "billingStrategy": "quota",
///   "dailyRemainingPercent": 98, "weeklyRemainingPercent": 99,
///   "dailyResetAtUnix": 1789372800, "weeklyResetAtUnix": 1789891200,
///   "hideDailyQuota": false, "hideWeeklyQuota": false,
///   "remainingMessages": -1, "totalMessages": -1,
///   "overageBalanceMicros": 10000000 }
/// ```
///
/// **The provider reports both percentages itself**, which is unusual company
/// for a local file: nothing here is inferred, the resets are stated, and the
/// two windows have real lengths. `used = 100 − remaining`, and that is all.
///
/// **Two shapes, because the plans differ.** A paid plan reports the two
/// percentages and sets the message counters to `-1`; a free one reports
/// `remainingMessages`/`totalMessages` instead. Both were captured on this
/// machine — the free shape out of `state.vscdb.backup`, written the moment
/// before the account was upgraded — so both are read. A message allowance has
/// no window and no reset, which is why `UsageWindow.Kind.messages` exists
/// rather than it being filed under a period nobody reported.
///
/// ## What this route cannot do
///
/// **The row is written when the app launches, not while it runs.** Measured:
/// the account was spent down through the morning and the file sat at 100%
/// throughout; the app was quit and reopened at 09:20:01 and the row changed
/// at 09:20:16, fifteen seconds later. So this is a snapshot of the last
/// launch and nothing else, and it is reported with the launch as its
/// `observedAt` — which is what puts "as of …" on the card rather than letting
/// a morning-old reading pass for a fresh one. The launch time is taken from
/// the newest directory under `logs/`, which the app creates once per run.
///
/// That is a real limitation and not a small one. It is worth having anyway:
/// it costs nothing — no credential, no network, no keychain prompt, no Full
/// Disk Access — and someone who keeps Devin open all day is exactly the
/// person whose reading goes stale, which the card now says out loud.
///
/// ## The other route
///
/// `GET https://app.devin.ai/api/<org>/billing/quota/usage`, with a Bearer
/// token the user pastes. That one is live, and it is why this provider has a
/// route picker: the app's cache answers when there is no token, and the
/// endpoint answers when there is.
///
/// **The credential is read from the browser, not pasted.** It is not in the
/// app's own storage — checked; the app authenticates through the Codeium
/// extension's session against `server.codeium.com`, a different credential
/// for a different API. It *is* in a Chromium browser's `localStorage` for
/// `app.devin.ai`, which `ChromiumLocalStorage` reads without a keychain
/// prompt because `localStorage` is not encrypted. Reading one origin out of a
/// thirty-megabyte profile takes about forty milliseconds.
///
/// **Read on every fetch rather than saved.** A stored copy would be a second
/// place for the session to go stale, and the one that cannot be refreshed on
/// its own; the browser's copy is by definition the current one. A pasted
/// value still wins where there is one, for anyone whose browser is not a
/// Chromium — see `Credential`.
struct DevinUsageService: Sendable {
    /// What the user pasted, which overrides the browser. Nil where nothing
    /// was, which is not an error: the browser answers, and failing that the
    /// app's own cache is a complete route on its own.
    let enteredKey: String?
    /// The browser to read, or nil to try the default one and then the rest.
    let browser: BrowserCookies.Browser?

    /// Test seams, all nil in production. They exist so the **real** route
    /// decision below can be exercised against a scratch store and a stub
    /// endpoint, with no browser, no network and nothing read off this Mac.
    let credential: Credential?
    let store: URL?
    let endpoint: (@Sendable (Credential) async -> ProviderUsage)?
    /// The clock, injectable so a fixture with fixed reset times is not a time
    /// bomb waiting for the calendar to move past it.
    let clock: @Sendable () -> Date
    /// Whether the browser is searched when nothing is pasted. False in the
    /// tests, so a Mac that really is signed in to Devin does not supply a
    /// credential to a test that is about having none.
    let searchesBrowser: Bool

    init(
        enteredKey: String? = nil,
        browser: BrowserCookies.Browser? = nil,
        credential: Credential? = nil,
        store: URL? = nil,
        endpoint: (@Sendable (Credential) async -> ProviderUsage)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        searchesBrowser: Bool = true
    ) {
        self.enteredKey = enteredKey
        self.browser = browser
        self.credential = credential
        self.store = store
        self.endpoint = endpoint
        self.clock = clock
        self.searchesBrowser = searchesBrowser
    }

    /// Where the app keeps its state. Both names are checked because the
    /// product was renamed: an Electron app's support directory follows its
    /// product name, so a Mac that ran Windsurf before the rename carries the
    /// old directory and a fresh install carries the new one. Newest wins.
    private static let supportDirectoryNames = ["Devin", "Windsurf"]

    /// The row, current first. The second is the name CodexBar's notes carry
    /// and this build has never seen; it is read because a name that changed
    /// once can change back, and a `LIKE` for the old one costs nothing.
    private static let planKeyPatterns = [
        "windsurf.reactSettings.cachedPlanInfoData%",
        "windsurf.settings.cachedPlanInfo%",
    ]

    func fetch(source: UsageSource) async -> ProviderUsage {
        // A pinned saved-plan route has no need to open browser storage.
        let credential: Credential? = source == .tooling ? nil : (
            self.credential
                ?? Credential(pasted: enteredKey)
                ?? (searchesBrowser ? Self.fromBrowser(browser)?.credential : nil)
        )
        return await Self.result(
            for: source,
            credential: credential,
            store: store,
            endpoint: endpoint,
            now: clock()
        )
    }

    /// What each source actually does, with the credential already resolved.
    ///
    /// **The endpoint is never crossed with the app's saved plan.** The saved
    /// row names no organization, and the endpoint is scoped to one, so two
    /// readings can share a user id and still be different organizations'
    /// allowances. A failure on the endpoint is therefore reported as it is:
    /// the saved plan answers only when there is no endpoint credential to try,
    /// or when the tooling route was chosen explicitly. The reply's own plan
    /// name, when it sends one, is kept — it is the endpoint describing itself.
    ///
    /// Static and credential-explicit so the routing can be tested through
    /// itself, without a browser or a request.
    static func result(
        for source: UsageSource,
        credential: Credential?,
        store: URL?,
        endpoint: (@Sendable (Credential) async -> ProviderUsage)?,
        now: Date
    ) async -> ProviderUsage {
        let call = endpoint ?? Self.live
        switch source {
        case .endpoint:
            guard let credential else {
                return ProviderUsage.unavailable(.devin, reason: .apiKeyMissing).recording(.endpoint)
            }
            return Self.scoped(await call(credential), credential).recording(.endpoint)

        case .tooling:
            return appCache(store: store, now: now).recording(.appCache)

        case .automatic, .desktopApp:
            guard let credential else {
                return appCache(store: store, now: now).recording(.appCache)
            }
            // Endpoint only. **No crossing to the saved plan after it fails**:
            // the row names no organization to compare with the endpoint's, so
            // a fallback there could be another organization's allowance.
            return Self.scoped(await call(credential), credential).recording(.endpoint)
        }
    }

    // MARK: - The app's own cache

    /// How long after launch the saved plan still counts as current.
    ///
    /// The row is written once, at launch, and not again while the app runs —
    /// measured: the app was quit and reopened at 09:20:01 and the row changed
    /// at 09:20:16. So the figures are the launch's, and past this they are
    /// shown as a snapshot ("as of …") rather than as a live reading. The card
    /// would otherwise let a morning-old figure pass for a fresh one.
    static let snapshotFreshFor: TimeInterval = 10 * 60

    /// The app's saved plan, or why there is none.
    ///
    /// **The row's key names a user, not an organization**, and nothing in the
    /// file or its key carries one. So this reading's scope is the app-cache
    /// route plus that user id, and it can never match an endpoint reading's
    /// scope — which is the honest answer, because the endpoint is
    /// organization-scoped and this is not.
    static func appCache(store: URL?, now: Date) -> ProviderUsage {
        guard let support = store ?? defaultSupportDirectory() else {
            return .unavailable(.devin, reason: .devinAppMissing)
        }
        let database = support.appending(path: "User/globalStorage/state.vscdb")
        guard let plan = Self.plan(in: database) else {
            return .unavailable(.devin, reason: .devinPlanUnread)
        }
        return reading(for: plan, launchedAt: lastLaunch(in: support), now: now)
    }

    /// The reading a saved plan amounts to at `now`, given when it was written.
    ///
    /// **Pure**, so the age rules can be argued without a file on disk. Three
    /// things happen here that an untouched snapshot did not:
    ///
    /// - A window whose reset has passed is **dropped, not aged**: whatever it
    ///   said belongs to a window that no longer exists.
    /// - A snapshot with **no reliable stamp** — missing, in the future, or
    ///   past `UsageCache.maximumAge` — is not shown at all. Reading it as
    ///   current and letting the cache stamp it with the fetch's own clock is a
    ///   fresh reading invented out of nothing. It reads as `.devinPlanUnread`,
    ///   neutral to the alert rules, and the remedy — open the app — writes a
    ///   new row.
    /// - A snapshot older than `snapshotFreshFor` is marked `.stale`, which is
    ///   what puts "as of …" on the card.
    static func reading(for plan: Plan, launchedAt: Date?, now: Date) -> ProviderUsage {
        guard let launchedAt, launchedAt <= now,
              now.timeIntervalSince(launchedAt) <= UsageCache.maximumAge else {
            return .unavailable(.devin, reason: .devinPlanUnread)
        }

        let windows = Self.windows(from: plan).filter { ($0.resetsAt ?? .distantFuture) > now }
        let balance = plan.overageBalance
        guard !windows.isEmpty || balance != nil else {
            return .unavailable(.devin, reason: .noLimitsReported)
        }

        var reading = ProviderUsage(
            account: AccountKey(.devin),
            windows: windows,
            observedAt: launchedAt,
            state: now.timeIntervalSince(launchedAt) <= snapshotFreshFor ? .live : .stale,
            plan: plan.planName,
            creditBalance: balance.map(Self.money)
        )
        // The row names the account it was written for; the scope travels with
        // the reading so the cache never lends its figures to another account's
        // or another organization's failure.
        reading.sourceScope = UsageScope(route: .appCache, organization: nil, identity: plan.accountID)
        return reading
    }

    /// Whether this Mac has ever run the app. Read by `Provider` to decide
    /// whether a ring is worth offering at all — there is nothing to paste
    /// here, so an install is the only evidence there is.
    static func isInstalled() -> Bool { defaultSupportDirectory() != nil }

    // MARK: - The pasted credential

    /// A Bearer token, and the organisation the quota path is scoped by.
    ///
    /// One field, because the whole store, the whole settings row and the
    /// whole "is it set" test are built around one string per provider — the
    /// same reason Volcengine's holds a key pair. Here the two are separated
    /// by whitespace rather than a colon: a token may contain one and an
    /// organisation URL certainly does.
    ///
    /// Accepted, in any combination:
    ///
    /// ```text
    /// eyJ… my-team
    /// Authorization: Bearer eyJ… org_1a2b3c
    /// eyJ… https://app.devin.ai/org/my-team/settings
    /// ```
    struct Credential: Equatable, Sendable {
        let token: String
        /// Already normalised to the path segment it belongs in —
        /// `org/<slug>` or `organizations/<id>`. Nil when nothing was given,
        /// which the endpoint refuses; it is a separate reason from a missing
        /// token so the message can say which half is missing.
        let organization: String?
        /// The account the browser session named, when it named one.
        ///
        /// `auth1_session` carries a `userId` beside the token. It identifies
        /// endpoint readings only together with their organization; it does
        /// not establish that an app-cache row belongs to that organization.
        /// A pasted token and the older flat store name no user. Their cache
        /// scope uses a credential fingerprint, not a guessed account id.
        let accountID: String?

        init?(pasted: String?) {
            var text = pasted?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }

            // A whole header line, as copied out of a browser's network tab.
            if let colon = text.firstIndex(of: ":"),
               text[text.startIndex..<colon].lowercased() == "authorization" {
                text = String(text[text.index(after: colon)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if text.lowercased().hasPrefix("bearer ") {
                text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let token = parts.first, !token.isEmpty else { return nil }

            self.token = token
            organization = parts.dropFirst().first.flatMap(Self.normalize)
            // What somebody pastes is a string, and a string asserts no
            // account. Saying it did would be the guess this type refuses.
            accountID = nil
        }

        /// The same values, out of a browser's `localStorage`.
        ///
        /// Nil unless **both** a token and an organisation are there. Half a
        /// session is not a credential: it would fire a request that can only
        /// fail, and — worse — stop the search at a browser that has nothing
        /// to offer.
        init?(storage: [String: String]) {
            guard let session = Self.session(in: storage),
                  let organization = Self.organization(in: storage),
                  let normalized = Self.normalize(organization)
            else { return nil }
            token = session.token
            accountID = session.userID
            self.organization = normalized
        }

        /// The token and the user id that came with it, read out of one object
        /// rather than two independent searches that could return different
        /// accounts' halves.
        private static func session(in storage: [String: String]) -> (token: String, userID: String?)? {
            if let session = storage["auth1_session"], let found = auth1(in: session) { return found }
            if let flat = storage["devin_auth1_token"].flatMap(unquote), flat.count > 20 {
                return (flat, nil)
            }

            for value in storage.values.sorted() {
                if let found = auth1(in: value) { return found }
            }
            for value in storage.values.sorted() {
                guard let object = object(in: value),
                      let token = object["access_token"] as? String, token.count > 20
                else { continue }
                return (token, object["userId"] as? String)
            }
            return nil
        }

        private static func auth1(in value: String) -> (token: String, userID: String?)? {
            guard let object = object(in: value), let token = object["token"] as? String,
                  token.hasPrefix("auth1_"), token.count > 20
            else { return nil }
            return (token, object["userId"] as? String)
        }

        /// The internal id, which is what the account's own pages are scoped
        /// by. The key's suffix is the *external* slug and is often the string
        /// `null`, so the value is what is read rather than the name.
        private static func organization(in storage: [String: String]) -> String? {
            let live = storage
                .filter { $0.key.hasPrefix("last-internal-org-for-external-org-v1-") }
                .sorted { $0.key < $1.key }
            for (_, value) in live {
                if let id = unquote(value), isInternalID(id) { return id }
            }

            if let flat = storage["devin_primary_org_id"].flatMap(unquote), !flat.isEmpty { return flat }

            // The list every page falls back to when the "last used" note is
            // missing. One organisation is the ordinary case; where there are
            // several, the first is the one its own UI opens.
            for (key, value) in storage.sorted(by: { $0.key < $1.key }) where key.hasPrefix("known-org-ids") {
                guard let ids = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String],
                      let first = ids.first(where: { isInternalID($0) })
                else { continue }
                return first
            }
            return nil
        }

        private static func object(in value: String) -> [String: Any]? {
            try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        }

        /// Chromium hands back what the page stored, and a page may have
        /// stored a JSON string rather than a bare one.
        private static func unquote(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let decoded = try? JSONDecoder().decode(String.self, from: Data(trimmed.utf8)) {
                return decoded.isEmpty ? nil : decoded
            }
            return trimmed.isEmpty ? nil : trimmed
        }

        /// A slug, an internal `org_…` id, or any `app.devin.ai` URL carrying
        /// one, reduced to the path segment the API wants. The rules are
        /// CodexBar's (MIT); nothing here was measured against a live account.
        static func normalize(_ raw: String) -> String? {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }

            if let url = URL(string: value), let host = url.host()?.lowercased(),
               host == "devin.ai" || host.hasSuffix(".devin.ai") {
                let segments = url.path().split(separator: "/").map(String.init)
                if segments.count >= 2, segments[0] == "org" || segments[0] == "organizations" {
                    value = "\(segments[0])/\(segments[1])"
                }
            }

            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !value.isEmpty else { return nil }
            if value.hasPrefix("org/") || value.hasPrefix("organizations/") { return value }
            // `org_` and `org-` are the internal id's prefixes; anything else
            // is the slug that appears in the address bar.
            return isInternalID(value) ? "organizations/\(value)" : "org/\(value)"
        }

        static func isInternalID(_ value: String) -> Bool {
            value.hasPrefix("org_") || value.hasPrefix("org-")
        }

        /// The internal id, where the organisation was given as one. It also
        /// travels as a header, which is how the service resolves an account
        /// with more than one organisation on it.
        var internalID: String? {
            guard let organization, organization.hasPrefix("organizations/") else { return nil }
            return String(organization.dropFirst("organizations/".count))
        }

        /// The scope the endpoint's figures belong to.
        ///
        /// **The organization is part of it, and that is the point.** The
        /// endpoint is organization-scoped: two sessions can share a user id
        /// and be different organizations' allowances, so a shared `userId` is
        /// not enough to fuse them. The identity is the browser session's user
        /// id where there is one, and otherwise a hash of the pasted credential
        /// — **never the credential itself** — so the same pasted token's
        /// readings stay together and a different token's do not.
        var endpointScope: UsageScope {
            let namedAccount = accountID.flatMap {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
            }
            return UsageScope(
                route: .endpoint,
                organization: organization,
                identity: namedAccount ?? Self.fingerprint(of: token)
            )
        }

        /// SHA-256 of the credential, as hex. A stable name for a pasted token
        /// that is not the token and cannot be turned back into it here.
        private static func fingerprint(of value: String) -> String {
            SHA256.hash(data: Data(value.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }

        /// The paths to try, in order. The API is undocumented and the shape
        /// of this one segment is the part CodexBar found varies, so a 404 on
        /// the first spelling is tried again as the others rather than
        /// reported as "no quota".
        var paths: [String] {
            guard let organization else { return [] }
            var paths = [organization]
            if let internalID { paths.insert(internalID, at: 0) }
            if organization.hasPrefix("org/") {
                let slug = String(organization.dropFirst(4))
                paths.append(slug)
                if Self.isInternalID(slug) { paths.append("organizations/\(slug)") }
            }
            var seen = Set<String>()
            return paths.filter { seen.insert($0).inserted }.map { "\($0)/billing/quota/usage" }
        }
    }

    // MARK: - The browser's session

    /// Devin's session, out of a Chromium browser's `localStorage`.
    ///
    /// Two keys under `https://app.devin.ai` carry what the endpoint needs,
    /// and both were read off this Mac rather than taken from anybody's
    /// parser:
    ///
    /// ```text
    /// auth1_session                                {"token":"auth1_…","userId":"user-…"}
    /// last-internal-org-for-external-org-v1-<slug> org-<32 hex>
    /// ```
    ///
    /// The organisation id is **hyphenated** here (`org-`), not underscored,
    /// which is why `Credential.isInternalID` accepts both.
    ///
    /// `windsurf.com` is read as a fallback: the same account signed in
    /// through the older storefront leaves `devin_auth1_token` and
    /// `devin_primary_org_id` there, which are the same two values under
    /// different names.
    static func fromBrowser(
        _ browser: BrowserCookies.Browser? = nil
    ) -> (credential: Credential, browser: BrowserCookies.Browser)? {
        let browsers = browser.map { [$0] } ?? ChromiumLocalStorage.present()

        // Origin before browser, so a complete session in the second browser
        // beats half of one in the first: a site can leave a stale key behind
        // long after the value beside it has gone.
        for origin in ["https://app.devin.ai", "https://windsurf.com"] {
            for browser in browsers {
                for store in ChromiumLocalStorage.stores(browser) {
                    let values = ChromiumLocalStorage.entries(origin: origin, in: store)
                    if let credential = Credential(storage: values) { return (credential, browser) }
                }
            }
        }
        return nil
    }

    // MARK: - The endpoint

    private static let host = "https://app.devin.ai"

    /// **Measured against a live account**, and against the app's own cache at
    /// the same moment: the row said 98% and 99% *remaining* while this said
    /// 2% and 1% *used*, which is the one thing carrying both routes could get
    /// backwards. The path's shape is the part that is still second-hand —
    /// CodexBar found it varies — so each spelling is tried in turn.
    static func live(_ credential: Credential) async -> ProviderUsage {
        guard !credential.paths.isEmpty else {
            return scoped(.unavailable(.devin, reason: .devinOrganizationMissing), credential)
        }

        var lastReason = ProviderUsage.Unavailability.unreachable
        for path in credential.paths {
            switch await get(path, credential) {
            case .reply(let data):
                guard let reply = Reply(json: data) else {
                    return scoped(.unavailable(.devin, reason: .unreadableReply), credential)
                }
                let windows = Self.windows(from: reply)
                guard !windows.isEmpty || reply.overageBalance != nil else {
                    return scoped(.unavailable(.devin, reason: .noLimitsReported), credential)
                }
                return scoped(ProviderUsage(
                    account: AccountKey(.devin),
                    windows: windows,
                    observedAt: Date(),
                    state: .live,
                    // **Only the reply's own plan name.** The row the app saved
                    // may name one, but it names no organization — and the
                    // endpoint is scoped to one — so there is no way to know
                    // the two are the same allowance. A plan line borrowed
                    // across organizations is the same invention as a figure
                    // taken from one.
                    plan: reply.planName,
                    creditBalance: reply.overageBalance.map(money)
                ), credential)
            case .failed(let reason):
                // A refused token is refused at every spelling of the path;
                // only a path that was not found is worth trying again.
                guard reason == .serverError else {
                    return scoped(.unavailable(.devin, reason: reason), credential)
                }
                lastReason = reason
            }
        }
        return scoped(.unavailable(.devin, reason: lastReason), credential)
    }

    /// Stamps a reading with the account and organization its endpoint route
    /// was scoped to, so the cache holds one allowance's figures apart from
    /// another's even across a relaunch. Applied to every return, failures
    /// included — a failure still has to say which scope it failed in.
    private static func scoped(_ usage: ProviderUsage, _ credential: Credential) -> ProviderUsage {
        var copy = usage
        copy.sourceScope = credential.endpointScope
        return copy
    }

    private enum Fetch {
        case reply(Data)
        case failed(ProviderUsage.Unavailability)
    }

    private static func get(_ path: String, _ credential: Credential) async -> Fetch {
        guard let url = URL(string: "\(host)/api/\(path)") else { return .failed(.unreadableReply) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // How the service picks between organisations on one account. Sent
        // only where the internal id is what was given — a slug is not one.
        if let internalID = credential.internalID {
            request.setValue(internalID, forHTTPHeaderField: "x-cog-org-id")
        }
        request.timeoutInterval = 15

        guard let (data, response) = try? await NetworkSession.shared.data(for: request) else {
            return .failed(.unreachable)
        }

        return switch (response as? HTTPURLResponse)?.statusCode {
        case 200: .reply(data)
        case 401, 403: .failed(.apiKeyRefused)
        case 429: .failed(.rateLimited)
        default: .failed(.serverError)
        }
    }

    /// The live reply, which is **not** shaped like the cached row: it reports
    /// what has been **used** where the row reports what is left, and it names
    /// its fields in snake case. Measured, 232 bytes of it:
    ///
    /// ```json
    /// { "daily_percentage": 2, "weekly_percentage": 1,
    ///   "daily_reset_at": "2026-09-14T00:00:00-08:00",
    ///   "weekly_reset_at": "2026-09-20T00:00:00-08:00",
    ///   "hide_daily_quota": false, "has_quota_allocation": true,
    ///   "is_quota_plan": true, "overage_balance": 10 }
    /// ```
    ///
    /// **This captured reply names no plan.** The card leaves that line absent
    /// unless the endpoint itself supplies one; the app's row has no matching
    /// organization evidence and cannot lend its plan name.
    ///
    /// CodexBar reads a value of 1 or less as a fraction and multiplies it by a
    /// hundred. **Deliberately not copied.** A genuine 0.4% used would then be
    /// drawn as 40%, which is a figure nobody reported — and the cached row is
    /// whole percentages, so a fraction here would be the surprise rather than
    /// the rule. If a live reply ever proves otherwise it is one line, with
    /// evidence behind it.
    struct Reply: Equatable, Sendable {
        var planName: String?
        var dailyUsedPercent: Double?
        var weeklyUsedPercent: Double?
        var dailyResetAt: Date?
        var weeklyResetAt: Date?
        var hideDailyQuota = false
        var hideWeeklyQuota = false
        var overageBalance: Double?
        /// False on an account with no quota to allocate — a legacy credit
        /// plan, or one that has lapsed. The percentages beside it are then
        /// not a reading of anything, so they are not drawn.
        var hasQuotaAllocation = true

        init?(json data: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            planName = ["plan_name", "planName", "plan", "tier"]
                .lazy.compactMap { object[$0] as? String }.first.flatMap { $0.isEmpty ? nil : $0 }
            dailyUsedPercent = Plan.number(object["daily_percentage"])
            weeklyUsedPercent = Plan.number(object["weekly_percentage"])
            dailyResetAt = Self.date(object["daily_reset_at"])
            weeklyResetAt = Self.date(object["weekly_reset_at"])
            hideDailyQuota = object["hide_daily_quota"] as? Bool ?? false
            hideWeeklyQuota = object["hide_weekly_quota"] as? Bool ?? false
            // Absent means yes: only an explicit `false` says there is no
            // allowance, and a field that stops being sent must not silently
            // empty the rings.
            hasQuotaAllocation = object["has_quota_allocation"] as? Bool ?? true
            overageBalance = Plan.number(object["overage_balance"])
                ?? Plan.number(object["overage_balance_cents"]).map { $0 / 100 }

            // Neither window and no money is not a reply, whatever it parsed
            // as: something else is being read.
            guard dailyUsedPercent != nil || weeklyUsedPercent != nil || overageBalance != nil else {
                return nil
            }
        }

        /// ISO 8601, epoch seconds, or epoch milliseconds — all three appear in
        /// CodexBar's account of this API, so all three are read.
        static func date(_ value: Any?) -> Date? {
            if let text = value as? String {
                if let date = ISO8601DateFormatter().date(from: text) { return date }
                return Double(text).flatMap(epoch)
            }
            return Plan.number(value).flatMap(epoch)
        }

        private static func epoch(_ number: Double) -> Date? {
            guard number > 0 else { return nil }
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
        }
    }

    static func windows(from reply: Reply) -> [UsageWindow] {
        guard reply.hasQuotaAllocation else { return [] }

        var windows: [UsageWindow] = []

        if !reply.hideDailyQuota, let used = reply.dailyUsedPercent {
            windows.append(
                UsageWindow(
                    id: "devin-daily", kind: .daily, scope: nil,
                    usedFraction: min(max(used / 100, 0), 1),
                    windowSeconds: 86_400, resetsAt: reply.dailyResetAt
                )
            )
        }

        if !reply.hideWeeklyQuota, let used = reply.weeklyUsedPercent {
            windows.append(
                UsageWindow(
                    id: "devin-weekly", kind: .weekly, scope: nil,
                    usedFraction: min(max(used / 100, 0), 1),
                    windowSeconds: 604_800, resetsAt: reply.weeklyResetAt
                )
            )
        }

        return windows
    }

    // MARK: - The file

    private static func defaultSupportDirectory() -> URL? {
        let support = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        let manager = FileManager.default

        return supportDirectoryNames
            .map { support.appending(path: $0) }
            .filter { manager.fileExists(atPath: $0.appending(path: "User/globalStorage/state.vscdb").path) }
            .max { (modified($0) ?? .distantPast) < (modified($1) ?? .distantPast) }
    }

    /// When the app last started, which is when the plan row was last written.
    ///
    /// Taken from `logs/`, where each run creates one directory whose **name**
    /// is its start time — `20260914T092003`, in this Mac's own zone. The name
    /// rather than the directory's date because the date moves: writing inside
    /// an existing file leaves it alone, but a log file created an hour into
    /// the session bumps it, and every minute it gains is a minute the card
    /// under-reports the age of a reading that has not changed since launch.
    /// An unparseable name carries no launch evidence and is ignored.
    ///
    /// **Not the database's own modification date**, which every other key in
    /// the file keeps current — a reading from breakfast would look a second
    /// old.
    private static func lastLaunch(in support: URL) -> Date? {
        let logs = support.appending(path: "logs")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: logs, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        return entries.compactMap { entry -> Date? in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return launchStamp(entry.lastPathComponent)
        }.max()
    }

    /// `20260914T092003`, written in local time and with no zone on it — which
    /// is why the formatter is given this Mac's own rather than left at UTC.
    static func launchStamp(_ name: String) -> Date? {
        guard name.count == 15 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.isLenient = false
        guard let date = formatter.date(from: name), formatter.string(from: date) == name else { return nil }
        return date
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // MARK: - The row

    /// Opened read-only and in place, the same way Pulse reads every other
    /// application's store: the app may be running and its journal belongs to
    /// that process.
    ///
    /// More than one row can exist where two accounts have signed in on this
    /// Mac, and nothing in the file says which is current. The one whose plan
    /// runs longest is taken — an active subscription outranks a lapsed one —
    /// and the plan name is on the card either way.
    static func plan(in file: URL) -> Plan? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(handle) }

        var found: [Plan] = []
        for pattern in planKeyPatterns {
            found += rows(handle, pattern).compactMap { row in
                Plan(json: row.value, accountID: Self.accountID(fromKey: row.key))
            }
            if !found.isEmpty { break }
        }

        return found.max { ($0.endTimestamp ?? 0) < ($1.endTimestamp ?? 0) }
    }

    /// The account a row belongs to, out of its key. The newer key ends
    /// `:user-<32 hex>`; the older `windsurf.settings.cachedPlanInfo` has no
    /// suffix and names no one, so it is nil rather than a guess.
    static func accountID(fromKey key: String) -> String? {
        guard let colon = key.lastIndex(of: ":") else { return nil }
        let suffix = String(key[key.index(after: colon)...])
        return suffix.isEmpty ? nil : suffix
    }

    private static func rows(_ handle: OpaquePointer?, _ pattern: String) -> [(key: String, value: Data)] {
        var statement: OpaquePointer?
        let sql = "SELECT key, value FROM ItemTable WHERE key LIKE ?"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, pattern, -1, transient)

        var values: [(key: String, value: Data)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = sqlite3_column_text(statement, 0),
                  let bytes = sqlite3_column_text(statement, 1)
            else { continue }
            values.append((String(cString: key), Data(String(cString: bytes).utf8)))
        }
        return values
    }

    // MARK: - The cached plan

    /// One account's plan, as the app cached it.
    ///
    /// Every figure is optional because this is a client's own cache rather
    /// than a documented reply: a field that stops being written should drop
    /// its window, not the whole reading.
    struct Plan: Equatable, Sendable {
        var planName: String?
        /// The account this row was written for, out of the key's suffix
        /// (`…cachedPlanInfoData:user-<32 hex>`) rather than out of the JSON,
        /// which does not carry one. Nil for the older key, which names no one.
        var accountID: String?
        var dailyRemainingPercent: Double?
        var weeklyRemainingPercent: Double?
        var dailyResetAtUnix: Double?
        var weeklyResetAtUnix: Double?
        var hideDailyQuota = false
        var hideWeeklyQuota = false
        var remainingMessages: Int?
        var totalMessages: Int?
        var overageBalanceMicros: Double?
        var endTimestamp: Double?

        /// Micros, as the field's name says: 10,000,000 is ten dollars.
        var overageBalance: Double? { overageBalanceMicros.map { $0 / 1_000_000 } }

        init?(json data: Data, accountID: String? = nil) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            planName = (object["planName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            self.accountID = accountID
            dailyRemainingPercent = Self.number(object["dailyRemainingPercent"])
            weeklyRemainingPercent = Self.number(object["weeklyRemainingPercent"])
            dailyResetAtUnix = Self.number(object["dailyResetAtUnix"])
            weeklyResetAtUnix = Self.number(object["weeklyResetAtUnix"])
            hideDailyQuota = object["hideDailyQuota"] as? Bool ?? false
            hideWeeklyQuota = object["hideWeeklyQuota"] as? Bool ?? false
            remainingMessages = Self.number(object["remainingMessages"]).map(Int.init)
            totalMessages = Self.number(object["totalMessages"]).map(Int.init)
            overageBalanceMicros = Self.number(object["overageBalanceMicros"])
            endTimestamp = Self.number(object["endTimestamp"])
        }

        /// Booleans are `NSNumber` too, and `NSNumber(true).doubleValue` is 1 —
        /// which would turn `hideDailyQuota` into a percentage if it were ever
        /// read through here. Shared with `Reply`, whose fields arrive from
        /// `JSONSerialization` in exactly the same shapes.
        static func number(_ value: Any?) -> Double? {
            guard let value = value as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID()
            else { return nil }
            let double = value.doubleValue
            return double.isFinite ? double : nil
        }
    }

    static func windows(from plan: Plan) -> [UsageWindow] {
        var windows: [UsageWindow] = []

        if !plan.hideDailyQuota,
           let window = window(
               id: "devin-daily", kind: .daily, seconds: 86_400,
               remainingPercent: plan.dailyRemainingPercent, resetAt: plan.dailyResetAtUnix
           ) {
            windows.append(window)
        }

        if !plan.hideWeeklyQuota,
           let window = window(
               id: "devin-weekly", kind: .weekly, seconds: 604_800,
               remainingPercent: plan.weeklyRemainingPercent, resetAt: plan.weeklyResetAtUnix
           ) {
            windows.append(window)
        }

        // A free plan's message pool. **`-1` is the paid plans' way of saying
        // "not applicable"**, not a count, so anything below zero — at either
        // end — is absent rather than empty.
        if let total = plan.totalMessages, let remaining = plan.remainingMessages,
           total > 0, remaining >= 0 {
            windows.append(
                UsageWindow(
                    id: "devin-messages",
                    kind: .messages,
                    scope: nil,
                    usedFraction: min(max(Double(total - remaining) / Double(total), 0), 1),
                    // No window was reported and none is invented: the seconds
                    // exist only so this sorts after the two timed ones.
                    windowSeconds: 2_592_000,
                    resetsAt: nil,
                    reportsLength: false
                )
            )
        }

        return windows
    }

    /// Nil rather than a zeroed window when the percentage is missing: a plan
    /// that reports no daily quota draws nothing, never a full ring.
    private static func window(
        id: String,
        kind: UsageWindow.Kind,
        seconds: Int,
        remainingPercent: Double?,
        resetAt: Double?
    ) -> UsageWindow? {
        guard let remainingPercent else { return nil }
        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: min(max(1 - remainingPercent / 100, 0), 1),
            windowSeconds: seconds,
            resetsAt: resetAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// US dollars, which is what the field is denominated in — there is no
    /// currency beside it and Devin bills in one.
    private static func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").locale(LocalizationSource.locale))
    }
}
