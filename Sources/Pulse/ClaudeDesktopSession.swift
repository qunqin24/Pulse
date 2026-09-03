import Foundation

/// The Claude desktop app as a third route to the account's limits.
///
/// **Why this exists.** The desktop app runs the very same `claude` binary the
/// terminal does, but it hands that process a token through its environment
/// and renews the token itself. So a session started from the desktop app
/// never writes the keychain item the usage-endpoint route reads, and there is
/// no terminal status line for the other route to be pushed through. Measured
/// on a Mac driven through the desktop app for a day: the keychain item's
/// modification date and the status line's captured blob were frozen at the
/// same minute — the last time `claude` had been run in a terminal — while
/// transcripts went on being written every few minutes. Both of the existing
/// routes were answering with yesterday, and the cache made that look like a
/// refresh button that did nothing.
///
/// **What it borrows.** The desktop app is Electron, so it keeps a Chromium
/// cookie store and a `Safe Storage` key in the login keychain: the same two
/// things `BrowserCookies` already reads for Chrome and Edge, which is why the
/// SQLite and the AES live there rather than being copied here. Pulse holds no
/// credential of its own for this — it borrows a login the user's own app
/// stored, exactly as the CLI routes do.
///
/// **It is steadier than what it stands beside, and that is the point.** The
/// session cookie runs to a month; the CLI's access token expires in about
/// eight hours and only the CLI renews it. For someone who works in the
/// desktop app this is the only route of the three that keeps answering.
///
/// **Only `claude.ai`, and only the names that authenticate.** The host match
/// is the host, its dot-form and its subdomains — never a suffix — and every
/// other cookie in that store is dropped before anything leaves this file.
/// Nothing is written to disk here.
///
/// **Not public API.** `/api/bootstrap` and `/api/organizations/{id}/usage`
/// are what the web client itself calls, so they can change without notice —
/// the same caveat the endpoint route carries, and the same reason the other
/// routes are kept rather than replaced.
enum ClaudeDesktopSession {
    /// Where the desktop app keeps its cookie store. Plain Application
    /// Support, not a container: readable by anything running as this user, so
    /// unlike Safari's cookies this needs no Full Disk Access. What it does
    /// need is the keychain, and that prompts.
    static var supportDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/Claude")
    }

    /// Written out rather than derived from the app's name, for the reason
    /// `BrowserCookies.Browser.keychainService` records: a wrong service name
    /// finds nothing and fails silently, which reads as "not signed in".
    static let keychainService = "Claude Safe Storage"

    static let host = "claude.ai"

    /// The two names that carry the session. The store also holds analytics,
    /// Stripe and Intercom cookies, a Cloudflare clearance and two `…LC`
    /// companions; none of them authenticate and none of them is sent.
    /// Verified: the account's own endpoints answer with these alone.
    private static let sessionNames = ["sessionKey", "sessionKeyV3"]

    /// The web client records which organisation is in front here, and reads
    /// it back at launch. It is not a credential and is never sent — it is
    /// only matched against the memberships the bootstrap reply lists.
    private static let activeOrganizationName = "lastActiveOrg"

    /// Everything the usage call needs besides the cookie: which organisation
    /// to ask about, and the plan's name, which the usage reply does not carry.
    struct Identity: Sendable {
        let organization: String
        let plan: String?
        /// Who this session belongs to, for the one question `.automatic` has
        /// to answer before it may stand in for the CLI's account.
        let fingerprint: ClaudeAccountIdentity.Fingerprint
    }

    /// The account's limits, in the shape the endpoint route already parses.
    static func usage(for account: AccountKey) async -> ProviderUsage {
        guard let store = cookieStore() else {
            return .unavailable(account, reason: .claudeDesktopNotSignedIn)
        }
        // The read that raises "Pulse wants to use your confidential
        // information". Denying it is a decision, not a failure to report as a
        // network problem — hence its own reason, whose remedy is to try again.
        guard let key = BrowserCookies.safeStorageKey(service: keychainService) else {
            wasPermitted = false
            return .unavailable(account, reason: .claudeDesktopKeyRefused)
        }
        // Reaching here means macOS handed the key over, which it only does
        // for an app the user has allowed. See `usageIfAlreadyPermitted`.
        wasPermitted = true

        // Read once, not once per thing wanted from it: every row in this
        // store costs an AES decrypt, and the session and the active
        // organisation both live in it.
        let cookies = BrowserCookies.chromiumCookies(at: store, host: host, key: key)
        guard let cookie = sessionHeader(from: cookies) else {
            return .unavailable(account, reason: .claudeDesktopNotSignedIn)
        }
        let active = activeOrganization(from: cookies)

        // Two attempts, and only because a cached organisation can go stale:
        // the second one throws away what was remembered and asks again. Any
        // other failure is reported the first time.
        for attempt in 0...1 {
            let identity: Identity
            switch await resolveIdentity(cookie: cookie, preferring: active, ignoringCache: attempt > 0) {
            case .success(let found): identity = found
            case .failure(let reason): return .unavailable(account, reason: reason)
            }

            switch await read(organization: identity.organization, cookie: cookie) {
            case .success(let root):
                return ClaudeCodeUsageService.parse(root, for: account, plan: identity.plan)
            case .organizationGone where attempt == 0:
                continue
            case .organizationGone:
                return .unavailable(account, reason: .noLimitsReported)
            case .failure(let reason):
                return .unavailable(account, reason: reason)
            }
        }

        return .unavailable(account, reason: .unreachable)
    }

    /// Whether this Mac has a desktop app with a session in it at all.
    ///
    /// Deliberately does **not** touch the keychain: it is asked to decide
    /// whether to offer the route in Settings, and a question about the shape
    /// of the machine must not raise a password prompt.
    static var isAvailable: Bool { cookieStore() != nil }

    /// This route from a background pass, or nil to say it isn't this pass's
    /// business — which `.automatic` reads as "carry on down the chain".
    ///
    /// **The gate is whether the keychain has already been granted**, and it
    /// has to be, because there is no way to ask the keychain for an item
    /// *quietly*: `SecKeychainSetUserInteractionAllowed` is the only switch
    /// for the ACL dialog and it is deprecated with no replacement
    /// (`kSecUseAuthenticationUI` governs biometrics — "is this person here" —
    /// not "may this app read that app's item"). So the grant is remembered
    /// instead: pick the route once, answer the prompt once, and every later
    /// pass reads it silently, `.automatic` included. Until then a background
    /// pass never touches it, because a menu-bar app raising a keychain dialog
    /// nobody asked for is a scare rather than a step.
    ///
    /// A grant revoked afterwards costs exactly one surprise prompt: the read
    /// then fails, the flag is cleared, and nothing asks again.
    static func usageIfAlreadyPermitted(for account: AccountKey) async -> ProviderUsage? {
        guard wasPermitted, isAvailable else { return nil }

        let usage = await self.usage(for: account)
        // Only a real reading is worth interrupting the chain for. Anything
        // else — a session that has been signed out, a refusal — leaves the
        // older routes their turn, since between a live nothing and a dated
        // something the dated something is what the panel is for.
        guard case .live = usage.state else { return nil }

        // **The two apps can be signed in as different people**, and this ring
        // is the CLI account's. Substituting silently would put one person's
        // limits under another's name, which is worse than the stale figure it
        // replaced. Only a comparison that comes out *wrong* stops it — see
        // `ClaudeAccountIdentity` on why unknown has to mean yes. A pinned
        // `.desktopApp` skips this entirely: asked for the desktop app's
        // session, it gets the desktop app's session.
        guard let seen = await Known.shared.lastFingerprint(),
              ClaudeAccountIdentity.maySubstitute(seen)
        else { return nil }

        return usage
    }

    /// Whether macOS has handed this app the desktop app's storage key before.
    ///
    /// In `UserDefaults` rather than in memory because what it records is a
    /// decision the *user* took, in a dialog, and one taken once should not
    /// have to be taken again at the next launch. It holds no secret: it is a
    /// yes or a no about a prompt.
    private(set) static var wasPermitted: Bool {
        get { UserDefaults.standard.bool(forKey: permissionKey) }
        set { UserDefaults.standard.set(newValue, forKey: permissionKey) }
    }

    /// Whether the launch-time ask has happened at all. Separate from the
    /// answer, because "not yet asked" and "asked and refused" call for
    /// opposite behaviour and a single flag cannot say which it is.
    private static var wasAsked: Bool {
        get { UserDefaults.standard.bool(forKey: askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedKey) }
    }

    private static let permissionKey = "claudeDesktop.keychainGranted"
    private static let askedKey = "claudeDesktop.keychainAsked"

    /// Asks for the keychain at launch, so the route is ready without anyone
    /// having to find it in Settings.
    ///
    /// **This is a prompt the user did not press anything to get**, which is
    /// the thing the rest of this file is careful about — so it is fenced in
    /// three ways. It happens only when there is a desktop app with a session
    /// on this Mac; only when Claude Code is a provider the rail is actually
    /// showing, so nobody is asked about a service they don't watch; and only
    /// **once** — a refusal is a decision, and a menu-bar app that asks again
    /// at every launch is the worst version of this feature.
    ///
    /// A grant that stops working is asked about again, and that is not the
    /// same as asking twice: the keychain ties an allowance to the code
    /// signature, and Pulse is ad-hoc signed, so every update is a different
    /// app as far as the ACL is concerned. Without this an update would
    /// silently cost the route until the user went looking.
    ///
    /// Never on the main thread: the dialog blocks the caller until it is
    /// answered, and the panel is drawn on that thread.
    /// `onGranted` runs on the main actor when the answer was yes and the
    /// route was not already usable. Without it a grant given at launch would
    /// sit unused until the next pass came round, which the adaptive schedule
    /// can put half an hour away — the dialog would look like it did nothing.
    static func requestPermissionAtLaunch(
        willBeUsed: Bool,
        onGranted: @escaping @MainActor () -> Void
    ) {
        // Someone who has pinned the endpoint or the status line has said
        // which route they want, and this one will never run for them — so
        // asking for a keychain item it needs is a prompt with no purpose
        // behind it, which is exactly the thing the fences here are for.
        guard willBeUsed, isAvailable else { return }
        // Never asked, or asked and allowed — the second is the re-ask after a
        // signature change, and is silent when the allowance still holds.
        let hadRoute = wasPermitted
        guard !wasAsked || hadRoute else { return }

        Task.detached(priority: .utility) {
            let granted = BrowserCookies.safeStorageKey(service: keychainService) != nil
            wasAsked = true
            wasPermitted = granted

            guard granted, !hadRoute else { return }
            await MainActor.run { onGranted() }
        }
    }

    // MARK: - The cookie

    /// Electron writes the store at the profile's root on some versions and
    /// under `Network/` on others, so both are looked for and the first that
    /// exists wins.
    private static func cookieStore() -> URL? {
        let candidates = ["Network/Cookies", "Cookies"].map { supportDirectory.appending(path: $0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// `name=value; …` for the session, or nil when the app holds no session.
    ///
    /// **A repeated name is not a malformed store.** Every Chromium store
    /// routinely holds a host-only row and a domain row for the same name, and
    /// the host match returns both on purpose. The first wins, as it does in
    /// any cookie header; throwing on the duplicate would discard the whole
    /// store and report a signed-in app as signed out.
    private static func sessionHeader(from cookies: [(String, String)]) -> String? {
        var seen: Set<String> = []
        let pairs = cookies
            .filter { sessionNames.contains($0.0) && !$0.1.isEmpty }
            .filter { seen.insert($0.0).inserted }

        guard !pairs.isEmpty else { return nil }
        return pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
    }

    /// Which organisation the desktop app last had open, if it says.
    private static func activeOrganization(from cookies: [(String, String)]) -> String? {
        guard let raw = cookies.first(where: { $0.0 == activeOrganizationName })?.1 else { return nil }

        // Stored percent-encoded, and sometimes quoted.
        let decoded = (raw.removingPercentEncoding ?? raw)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return decoded.isEmpty ? nil : decoded
    }

    // MARK: - The two calls

    private enum IdentityOutcome {
        case success(Identity)
        case failure(ProviderUsage.Unavailability)
    }

    private enum ReadOutcome {
        case success([String: Any])
        /// The organisation we remembered is not one this account has any
        /// more, which is worth one more round trip rather than an error.
        case organizationGone
        case failure(ProviderUsage.Unavailability)
    }

    private static func resolveIdentity(
        cookie: String,
        preferring active: String?,
        ignoringCache: Bool
    ) async -> IdentityOutcome {
        // **Keyed by the organisation the app is in front of now**, not by
        // time alone. Switching organisation in the desktop app changes which
        // limits the user is looking at, and a six-hour cache went on
        // reporting the old one's — under the new one's name — for the rest of
        // an afternoon. The cookie says so at no cost; the only thing the
        // clock is still for is a plan that changed.
        if !ignoringCache, let known = await Known.shared.cached(for: active) { return .success(known) }
        await Known.shared.forget()

        switch await bootstrap(cookie: cookie, preferring: active) {
        case .success(let identity):
            await Known.shared.remember(identity, seenActive: active)
            return .success(identity)
        case .failure(let reason):
            return .failure(reason)
        }
    }

    /// Who this session belongs to. The usage call is addressed to an
    /// organisation, and nothing on this Mac names it — the desktop app asks
    /// for it the same way at launch.
    private static func bootstrap(cookie: String, preferring active: String?) async -> IdentityOutcome {
        let url = URL(string: "https://claude.ai/api/bootstrap")!
        switch await get(url, cookie: cookie) {
        case .success(let root):
            guard
                let account = root["account"] as? [String: Any],
                let memberships = account["memberships"] as? [[String: Any]]
            else { return .failure(.unreadableReply) }

            let organizations = memberships.compactMap { $0["organization"] as? [String: Any] }
            // **The one the app is actually in front of, not the first one
            // listed.** An account can belong to several — a personal one and
            // an employer's — and their limits are different limits. Taking
            // whichever the reply happened to order first reports one
            // organisation's usage under another's name, which is worse than
            // reporting nothing. The order is not documented to mean anything.
            guard
                let organization = organizations.first(where: { $0["uuid"] as? String == active })
                    ?? organizations.first,
                let id = organization["uuid"] as? String
            else { return .failure(.unreadableReply) }

            // The tier is where the multiplier lives — a Max plan is sold as
            // 5× or 20× and those are different products — so it goes through
            // the same reader the endpoint route uses rather than a second
            // copy of that judgement.
            let plan = ClaudeCodeUsageService.ClaudePlan.shared
                .planName(from: ["organization": organization])
            return .success(Identity(
                organization: id,
                plan: plan,
                fingerprint: ClaudeAccountIdentity.fingerprint(fromBootstrap: root)
            ))
        case .organizationGone:
            return .failure(.unreadableReply)
        case .failure(let reason):
            return .failure(reason)
        }
    }

    private static func read(organization: String, cookie: String) async -> ReadOutcome {
        let url = URL(string: "https://claude.ai/api/organizations/\(organization)/usage")!
        return await get(url, cookie: cookie)
    }

    /// **Not `URLSession.shared`.** That one is backed by the process-wide
    /// cookie jar, so a `Set-Cookie` on any of these replies — a Cloudflare
    /// token, a rotated session — would be stored there and then sent along on
    /// every other request Pulse makes to the same hosts. The session belongs
    /// to the desktop app; Pulse borrows it for the length of one call and
    /// keeps nothing. Ephemeral, and told twice not to store cookies.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        // A quota that moves in percent must never be answered from a cached
        // response: ephemeral means the cache dies with the process, not that
        // there isn't one.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private static func get(_ url: URL, cookie: String) async -> ReadOutcome {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        // A web session, so a web client's agent. The CLI's own string belongs
        // to the other route and is not what this endpoint is answering.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Claude/1.0 Chrome/130.0.0.0 Electron/33.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        for attempt in 0...retryLimit {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failure(.unreachable) }

                switch http.statusCode {
                case 200:
                    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return .failure(.unreadableReply)
                    }
                    return .success(root)
                case 401, 403:
                    return .failure(.claudeDesktopSessionExpired)
                case 404:
                    return .organizationGone
                case 429:
                    return .failure(.rateLimited)
                default:
                    return .failure(.serverError)
                }
            } catch {
                guard attempt < retryLimit, isWorthRetrying(error) else { return .failure(.unreachable) }
                try? await Task.sleep(for: .milliseconds(600 * (attempt + 1)))
            }
        }

        return .failure(.unreachable)
    }

    private static let retryLimit = 2

    /// A proxy or VPN dropping a connection shows up as `-1005`, which
    /// retrying usually clears. The same list the other services use.
    private static func isWorthRetrying(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .networkConnectionLost, .timedOut, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed
        ].contains(urlError.code)
    }

    // MARK: - What is worth remembering

    /// The organisation and the plan, which change about as often as somebody
    /// changes their mind about paying for something — while the refresh loop
    /// comes round every few minutes. Without this every pass would cost two
    /// requests instead of one.
    private actor Known {
        static let shared = Known()

        private static let freshFor: TimeInterval = 6 * 3600
        private var stored: (identity: Identity, active: String?, at: Date)?

        /// `active` is what the cookie says right now. A cache entry taken
        /// under a different answer is not stale, it is about something else.
        func cached(for active: String?) -> Identity? {
            guard let stored, stored.active == active else { return nil }
            guard Date().timeIntervalSince(stored.at) < Self.freshFor else { return nil }
            return stored.identity
        }

        func remember(_ identity: Identity, seenActive active: String?) {
            stored = (identity, active, Date())
        }

        /// Whoever the session belonged to when it was last read, cache age
        /// notwithstanding: the question is who, and that does not go stale on
        /// the same clock a plan does.
        func lastFingerprint() -> ClaudeAccountIdentity.Fingerprint? { stored?.identity.fingerprint }
        func forget() { stored = nil }
    }
}
