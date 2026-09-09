import Foundation

/// One thing the rail shows a ring for.
///
/// A provider used to be the identity: one ring, one card, one settings pane
/// each. Someone with two Claude subscriptions wants two of each, so the
/// identity is now a provider *plus* which of its accounts.
///
/// **A provider's first account has the provider's own raw value as its id**,
/// and that is the whole migration strategy. Every stored preference — which
/// rings are shown, the order they are drawn in, which window each ring is
/// pinned to, which route each is read by — was written keyed by the
/// provider's raw value, and leaving the first account's key identical means
/// all of it goes on matching with no migration step to get wrong. Making an
/// upgrade look like a fresh install has already cost this app one release;
/// the cheapest way not to repeat that is for the old keys to keep meaning
/// exactly what they meant.
struct AccountKey: Hashable, Codable, Sendable, Identifiable {
    let provider: Provider
    /// Empty for a provider's first account — the one read from whatever that
    /// tool already stored on this Mac. Added accounts carry a slot that is
    /// generated once and never reused, so removing one and adding another
    /// cannot inherit the first one's settings.
    let slot: String

    init(_ provider: Provider, slot: String = "") {
        self.provider = provider
        self.slot = slot
    }

    /// The string every stored preference is keyed by.
    var id: String { slot.isEmpty ? provider.rawValue : "\(provider.rawValue)#\(slot)" }

    /// Whether this is the account read from the tool's own login rather than
    /// one Pulse signed in to itself.
    var isPrimary: Bool { slot.isEmpty }

    init?(id: String) {
        let parts = id.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let provider = Provider(rawValue: String(first)) else { return nil }
        self.init(provider, slot: parts.count > 1 ? String(parts[1]) : "")
    }
}

/// One ring on the rail.
///
/// **Not the same thing as an account**, and that is the whole point. A ring
/// has always been an account, because every provider reported one pool of
/// limits per login. Antigravity reports two that have nothing to do with each
/// other — a Gemini allowance and one for Claude and GPT — from a single
/// login, and folding them into one ring throws away whichever is not the
/// worse.
///
/// So the rail is drawn from slots, and an account contributes one of them or,
/// where its limits are split by model group, one per group. Everything that
/// is genuinely about the *account* — the credential, the refresh, the pinned
/// window, the chosen colour, the settings pane — still keys on `AccountKey`.
/// Only what is drawn and what is pointed at keys on this.
struct RailSlot: Hashable, Identifiable, Sendable {
    let account: AccountKey
    /// The model group this ring is for, or nil for an unsplit account.
    let group: String?

    init(_ account: AccountKey, group: String? = nil) {
        self.account = account
        self.group = group
    }

    /// **An account's unsplit slot keeps the account's own id**, so a stored
    /// order, a hover, or a selection written before this existed still
    /// matches. The suffix cannot collide with an added account's, which uses
    /// `#`, because a group is only ever appended to an id that is already
    /// whole.
    var id: String { group.map { "\(account.id)@\($0)" } ?? account.id }

    /// The rail, in order. **One place**, because the panel draws from it and
    /// the click handler indexes into it — and a ring that is drawn at one
    /// position and refreshed from another is the kind of fault nobody
    /// reports clearly.
    ///
    /// A split account keeps its single slot until a reading actually carries
    /// more than one group: before the first answer there is nothing to split
    /// by, and one ring that becomes two a second later is better than two
    /// empty ones that may never fill.
    static func rail(
        for accounts: [AccountKey],
        isSplit: (AccountKey) -> Bool,
        groups: (AccountKey) -> [String]
    ) -> [RailSlot] {
        accounts.flatMap { account -> [RailSlot] in
            guard isSplit(account) else { return [RailSlot(account)] }
            let groups = groups(account)

            // More groups than the rail budgeted for: stay whole. `railSlotCount`
            // reserves `modelGroupCount` per split account and `PanelMetrics`
            // sizes the rail from that, so drawing a third would run past the end
            // of the rail and have it sliced off — what happened the first time a
            // seventh account existed. Taking the first two instead would file
            // the third group's limits under no ring at all, which is the silent
            // loss `modelGroups(of:)` refuses two lines below. One ring showing
            // the busiest of three is worse than two rings; it is not worse than
            // a limit nobody can see.
            guard groups.count > 1, groups.count <= account.provider.modelGroupCount else {
                return [RailSlot(account)]
            }
            return groups.map { RailSlot(account, group: $0) }
        }
    }

    /// The model groups a reading carries, in the order the provider reported
    /// them — not sorted, because that order is the provider's own and is what
    /// its own settings screen shows.
    /// **All or nothing.** A reading that mixes scoped and unscoped windows
    /// gets no groups at all, so the account stays whole: splitting it would
    /// file every window under a scope and leave the unscoped ones belonging
    /// to no ring, gone from the rail and from every card. A limit that
    /// silently disappears is worse than a limit sharing a ring.
    static func modelGroups(of usage: ProviderUsage) -> [String] {
        guard !usage.windows.isEmpty, usage.windows.allSatisfy({ $0.scope != nil }) else { return [] }

        var seen: Set<String> = []
        return usage.windows.compactMap { window in
            guard let scope = window.scope, seen.insert(scope).inserted else { return nil }
            return scope
        }
    }
}

/// An account beyond the first, which exists only because Pulse was signed in
/// to it. The first account of every provider is implicit — it is whatever
/// that tool already stored — so only these need remembering.
struct ExtraAccount: Codable, Hashable, Identifiable, Sendable {
    let provider: Provider
    let slot: String
    /// What the user calls it. Seeded from whatever the provider says about
    /// the account when it is added, and editable afterwards, because "Max"
    /// and "Max" tell two subscriptions apart no better than nothing does.
    var label: String

    var key: AccountKey { AccountKey(provider, slot: slot) }
    var id: String { key.id }
}

extension Provider {
    /// Whether Pulse can watch more than one account of this provider.
    ///
    /// Only the ones it can sign in to itself. The others are read from a
    /// credential their own tool stored, and that store holds exactly one
    /// login — so a second account of theirs is not something Pulse can be
    /// shown, however the rest of the app is shaped.
    var supportsMultipleAccounts: Bool {
        switch self {
        // Grok Bot is signed in to through Cursor's own login page rather
        // than by OAuth — a second allowance is a second Cursor account. See
        // `CursorWebLogin`.
        case .claudeCode, .codex, .grok, .grokBot: true
        // **Cursor itself is not on this list, and that is not an oversight.**
        // The same sign-in would work, but Cursor's usage summary is read
        // from the editor's own stored login and a second account has no
        // editor behind it. Grok Bot needs nothing but the token.
        case .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .volcengine,
             .commandCode: false
        }
    }
}
