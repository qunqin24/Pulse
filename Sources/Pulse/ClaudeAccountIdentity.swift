import Foundation

/// Whether the Claude desktop app and the Claude Code CLI are signed in as the
/// same person.
///
/// **Why this cannot simply be asked.** The desktop route exists precisely for
/// the moment the CLI's own login is dead — that is when `.automatic` reaches
/// for it — and `GET /api/oauth/profile`, the only thing that would say whose
/// login the CLI holds, needs that dead token to answer. So the question has
/// to be settled *earlier*: the profile call already goes out every six hours
/// while the token still works, for the plan's name, and what it says about
/// whose account it is is remembered here. The desktop route then compares
/// against that, however long ago it was.
///
/// **Unknown means yes.** Someone who works only in the desktop app may never
/// have had a working CLI token on this Mac, and refusing the route until one
/// appeared would withhold it from exactly the person it was built for. So a
/// comparison that cannot be made is not treated as a failure — only a
/// comparison that comes out *wrong* stops the reading. The cost of being
/// wrong the permissive way is one Mac showing one account's limits where
/// both logins are the same person's anyway; the cost of the strict way is
/// the feature not working at all.
///
/// **Like is compared with like.** Both replies name several things — an
/// account id, an email address, an organisation id — and which of them a
/// reply carries has changed before. Flattening them into one set would let a
/// profile that gave only an organisation and a bootstrap that gave only an
/// account come out "different" because they had nothing in common to be the
/// same about. Each kind is compared against its own kind, and a mismatch is
/// only a mismatch when both sides actually stated that kind.
enum ClaudeAccountIdentity {
    /// The identifiers one reply gives for whoever it belongs to.
    struct Fingerprint: Equatable, Sendable, Codable {
        var accounts: Set<String> = []
        var organizations: Set<String> = []
        var emails: Set<String> = []

        var isEmpty: Bool { accounts.isEmpty && organizations.isEmpty && emails.isEmpty }
    }

    enum Verdict {
        case same
        case different
        /// Nothing comparable on one side or the other.
        case unknown
    }

    // MARK: - Reading a reply

    /// From `GET /api/oauth/profile`, which is the CLI's own login.
    ///
    /// Only the identifying fields are read, and they are never displayed or
    /// sent anywhere — the same reply carries the account's name and other
    /// details that are the user's and no use to Pulse.
    static func fingerprint(fromProfile root: [String: Any]) -> Fingerprint {
        let account = root["account"] as? [String: Any] ?? root
        let organization = root["organization"] as? [String: Any]

        return Fingerprint(
            accounts: ids(account["uuid"], account["id"]),
            organizations: ids(organization?["uuid"], organization?["id"]),
            emails: ids(account["email_address"], account["email"])
        )
    }

    /// From `GET claude.ai/api/bootstrap`, which is the desktop app's session.
    static func fingerprint(fromBootstrap root: [String: Any]) -> Fingerprint {
        let account = root["account"] as? [String: Any] ?? [:]
        let memberships = account["memberships"] as? [[String: Any]] ?? []
        let organizations = memberships.compactMap { $0["organization"] as? [String: Any] }

        var found = Fingerprint(
            accounts: ids(account["uuid"], account["id"]),
            emails: ids(account["email_address"], account["email"])
        )
        // Every organisation the account belongs to, not only the active one:
        // the CLI may be sitting in a different one of the same person's
        // organisations, and that is the same person.
        found.organizations = Set(organizations.flatMap { ids($0["uuid"], $0["id"]) })
        return found
    }

    private static func ids(_ values: Any?...) -> Set<String> {
        Set(values.compactMap { ($0 as? String)?.lowercased() }.filter { !$0.isEmpty })
    }

    // MARK: - What the CLI's login last said

    /// Remembered across launches: the token it came from expires in hours,
    /// while the question it answers can be asked days later.
    static func remember(_ fingerprint: Fingerprint) {
        guard !fingerprint.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(fingerprint) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static var remembered: Fingerprint? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Fingerprint.self, from: data)
    }

    private static let key = "claudeCode.accountFingerprint"

    // MARK: - The comparison

    static func compare(_ one: Fingerprint, _ other: Fingerprint) -> Verdict {
        let pairs = [
            (one.accounts, other.accounts),
            (one.organizations, other.organizations),
            (one.emails, other.emails),
        ]

        var comparable = false
        for (left, right) in pairs where !left.isEmpty && !right.isEmpty {
            comparable = true
            // One kind agreeing settles it: a person whose desktop app is in a
            // different organisation of their own is still that person.
            if !left.isDisjoint(with: right) { return .same }
        }

        return comparable ? .different : .unknown
    }

    /// Whether a desktop reading may stand in for the CLI's account.
    static func maySubstitute(_ desktop: Fingerprint) -> Bool {
        guard let known = remembered else { return true }
        return compare(known, desktop) != .different
    }
}
