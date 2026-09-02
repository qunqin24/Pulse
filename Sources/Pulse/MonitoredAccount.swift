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
    /// Only the two it can sign in to itself. The others are read from a
    /// credential their own tool stored, and that store holds exactly one
    /// login — so a second account of theirs is not something Pulse can be
    /// shown, however the rest of the app is shaped.
    var supportsMultipleAccounts: Bool {
        switch self {
        case .claudeCode, .codex: true
        case .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot: false
        }
    }
}
