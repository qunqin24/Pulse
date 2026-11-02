// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// Which accounts exist, which are on the rail, and in what order. Everything
// here is about the *set* of rings, so a change to it resizes the rail
// (`resizeRail`) before it is announced and then goes through `onChange`: a
// provider newly switched on has to be fetched. The exception is the order,
// which is layout and fetches nothing.

extension AppSettings.Key {
    static let extraAccounts = "settings.extraAccounts"
    static let extensionNames = "settings.extensionNames"
    static let providerOrder = "settings.providerOrder"
    // Which accounts are enabled is `ProviderSelection.enabledKey`: the first
    // run and upgrade offers read and write it too.
}

extension AppSettings {
    func extraAccountsChanged(from old: [ExtraAccount]) {
        orderedCache = nil
        guard extraAccounts != old else { return }
        // Before the change is announced: whoever reacts is about to measure
        // the panel, and the rail is now longer than it was.
        resizeRail()
        let data = try? JSONEncoder().encode(extraAccounts)
        defaults.set(data, forKey: Key.extraAccounts)
        onChange?()
    }

    func providerOrderChanged(from old: [String]) {
        orderedCache = nil
        guard providerOrder != old else { return }
        defaults.set(providerOrder, forKey: Key.providerOrder)
        // Deliberately no `onChange`: that is how the AppKit side hears
        // about settings the *usage loop* cares about, and it refetches
        // every provider when it fires. Rearranging the rail is a layout
        // change — the panel is `@Observable` and redraws on its own, and
        // nobody's rate limit should pay for a reorder.
    }

    func extensionsChanged(from old: [PulseExtension]) {
        orderedCache = nil
        // What `storedRail()` — `--json` — lists, so it never has to read
        // the folder itself.
        let names = Dictionary(extensions.map { ($0.account.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        defaults.set(names, forKey: Key.extensionNames)
    }

    // MARK: - What exists

    /// Every account there is: each provider's first, plus whatever has been
    /// added to the two that allow it, plus one per extension found. Declaration
    /// order, before the user's own order is applied.
    var allAccounts: [AccountKey] {
        Provider.builtIn.flatMap { provider in
            [AccountKey(provider)] + extraAccounts.filter { $0.provider == provider }.map(\.key)
        } + extensions.map(\.account)
    }

    /// Reads the extensions folder again and, if that changed anything, tells
    /// whoever draws the rail.
    func rescanExtensions() {
        apply(ExtensionCatalog.scan())
    }

    /// Separate from `rescanExtensions` so a test can hand in a scan without a
    /// folder on disk.
    func apply(_ scan: ExtensionCatalog.Scan) {
        guard scan.extensions != extensions || scan.problems != extensionProblems else { return }
        let changedAccounts = scan.extensions.map(\.account) != extensions.map(\.account)
        extensions = scan.extensions
        extensionProblems = scan.problems
        // Before the change is announced, for the reason `extraAccounts` gives.
        resizeRail()
        if changedAccounts { onChange?() }
    }

    /// The extension behind an account, if it is one and it is still there.
    func pulseExtension(for account: AccountKey) -> PulseExtension? {
        guard account.provider == .pulseExtension else { return nil }
        return extensions.first { $0.account == account }
    }

    /// What to call an account. A provider's first one is just the provider;
    /// the rest carry a label so two subscriptions can be told apart.
    func label(for account: AccountKey) -> String {
        // The manifest's name. A removed extension's account is gone from
        // every list, so the fallback is only ever read in passing.
        if account.provider == .pulseExtension {
            return pulseExtension(for: account)?.name ?? account.slot
        }
        return extraAccounts.first { $0.key == account }?.label ?? account.provider.displayName
    }

    // MARK: - Order

    /// Every account, in the user's order.
    ///
    /// Anything the stored order doesn't mention goes after it, **sorted by
    /// name**. Someone who has arranged the rail keeps their arrangement and a
    /// provider added later lands at the bottom of it; someone who never
    /// touched it — which is everybody until they do — gets the whole list in
    /// alphabetical order rather than in the order the enum happens to be
    /// written in.
    ///
    /// **Worked out once and kept.** The panel asks for it on every mouse
    /// event it handles and every view that draws the rail asks again, and
    /// with seventy-odd providers each answer was a sort of every name. It
    /// changes only with the stored order, the added accounts and the
    /// extensions found, which is exactly what clears it. Those three are
    /// still read on every call, so whoever asks is told when they change.
    var orderedAccounts: [AccountKey] {
        _ = providerOrder
        _ = extraAccounts
        _ = extensions
        if let orderedCache { return orderedCache }
        let known = allAccounts
        let knownSet = Set(known)
        let stored = providerOrder.compactMap(AccountKey.init(id:)).filter(knownSet.contains)
        let storedSet = Set(stored)
        let ordered = stored + known.filter { !storedSet.contains($0) }.sorted(by: byName)
        orderedCache = ordered
        return ordered
    }

    /// The order accounts fall into before anybody has arranged them: **by the
    /// name on the row**.
    ///
    /// It used to be declaration order, which is the order the providers were
    /// added to the enum over the months — an order with a meaning, but not one
    /// visible from the outside. Seventeen rows arranged by nothing a reader
    /// can see is a list you have to scan rather than one you can look in.
    ///
    /// An added account sorts by the label the user gave it, not by its
    /// provider, because the label is what is written on the row. Two Claude
    /// Code accounts called "Work" and "Personal" belong under W and P.
    ///
    /// `localizedStandardCompare` is Finder's comparison: case- and
    /// accent-insensitive, and it puts any digits in a name in numeric order.
    /// The same one the settings search matches with.
    private func byName(_ a: AccountKey, _ b: AccountKey) -> Bool {
        let left = label(for: a)
        let right = label(for: b)
        // Ids as the tie-break, so two rows that read the same never swap
        // places between launches.
        if left.localizedStandardCompare(right) == .orderedSame { return a.id < b.id }
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    /// Moves an account one place up or down **among the shown ones**.
    /// Silently does nothing at the ends, so the buttons can simply be
    /// disabled there.
    ///
    /// Among the shown ones because that is the only list the Order group
    /// draws: with seventy-odd providers, listing the switched-off ones made
    /// it a list of things that are not on the rail. A move that stepped over
    /// one of those would change nothing anybody can see.
    func move(_ account: AccountKey, by offset: Int) {
        var shown = shownAccounts
        guard
            let from = shown.firstIndex(of: account),
            shown.indices.contains(from + offset)
        else { return }

        shown.swapAt(from, from + offset)
        store(shownOrder: shown)
    }

    /// The shown accounts in the order given, then everything else in the
    /// order it already had. What is switched off keeps its place relative to
    /// its own kind, and comes back at the end of the rail when it is switched
    /// on again.
    private func store(shownOrder shown: [AccountKey]) {
        providerOrder = (shown + orderedAccounts.filter { !shown.contains($0) }).map(\.id)
    }

    /// Whether the rail is in an order somebody chose, rather than the one it
    /// ships with.
    ///
    /// Compared against the accounts themselves, not against whether anything
    /// is stored: dragging a row down and back up again leaves a full stored
    /// list that happens to match the default exactly, and offering to reset
    /// an order that is already the default is a button that does nothing.
    /// Whether anybody has actually arranged the rail.
    ///
    /// **Not `orderedAccounts != allAccounts`.** That compared the order shown
    /// against *declaration* order, and since the default became name order the
    /// two differ on a fresh install — so "Reset order" was enabled out of the
    /// box and did nothing when pressed, which is the one thing a control must
    /// never do. The question is whether a stored arrangement exists that still
    /// names something real.
    var hasCustomOrder: Bool {
        !providerOrder.compactMap(AccountKey.init(id:)).filter(allAccounts.contains).isEmpty
    }

    /// Back to declaration order.
    ///
    /// By clearing the stored list rather than writing the default into it, so
    /// a provider added in a later version keeps arriving at the bottom of the
    /// rail instead of being pinned by a list written before it existed —
    /// which is the whole reason `orderedAccounts` appends what it doesn't
    /// recognise.
    func resetOrder() { providerOrder = [] }

    /// Drops an account into the place another one currently holds.
    ///
    /// The standard "take its place" behaviour, and it reads in both
    /// directions because the indices shift underneath it: dragging *down*
    /// onto a row lands after it (the target moved up when the dragged row was
    /// lifted out), dragging *up* onto a row lands before it. Both are what
    /// the pointer was pointing at.
    func move(_ account: AccountKey, onto target: AccountKey) {
        guard account != target else { return }

        var shown = shownAccounts
        guard
            let from = shown.firstIndex(of: account),
            let to = shown.firstIndex(of: target)
        else { return }

        shown.remove(at: from)
        shown.insert(account, at: min(to, shown.count))
        store(shownOrder: shown)
    }

    // MARK: - What is shown

    var needsProviderSelection: Bool { shownAccounts.isEmpty }

    func selectProviders(_ providers: Set<Provider>) {
        guard !providers.isEmpty else { return }
        enabledAccounts.formUnion(providers.map(\.rawValue))
    }

    func isEnabled(_ account: AccountKey) -> Bool {
        enabledAccounts.contains(account.id)
    }

    func setEnabled(_ isEnabled: Bool, for account: AccountKey) {
        if isEnabled {
            enabledAccounts.insert(account.id)
        } else {
            enabledAccounts.remove(account.id)
        }
    }

    /// The accounts the rail is actually showing, in the user's order — which
    /// is what everything measuring or hit-testing the rail has to agree on.
    var shownAccounts: [AccountKey] { orderedAccounts.filter(isEnabled) }

    // MARK: - Adding and removing

    /// Adds an account Pulse has just signed in to, switched on and last in
    /// the rail. The slot is generated here so it can never collide with one
    /// that has been removed.
    @discardableResult
    func addAccount(_ provider: Provider, label: String, slot: String = UUID().uuidString) -> AccountKey {
        let account = ExtraAccount(provider: provider, slot: slot, label: label)
        extraAccounts.append(account)
        enabledAccounts.insert(account.id)
        return account.key
    }

    /// Forgets an account, and everything stored against it — a later account
    /// must never inherit a removed one's pinned window, route, colours, or
    /// any other per-account setting.
    ///
    /// **Add every new per-account store here.** `AppSettingsRemoveAccountTests`
    /// fails for the ones it knows about; a new one is only as safe as this
    /// list is complete.
    func removeAccount(_ account: AccountKey) {
        guard !account.isPrimary else { return }

        extraAccounts.removeAll { $0.key == account }
        // **The set refuses to go empty, and that refusal put the removed
        // account straight back.** `enabledAccounts` restores its old value
        // rather than accept nothing — so deleting the only enabled account
        // left its id behind, naming an account that no longer exists, and the
        // rail drew nothing at all because `shownAccounts` filters the real
        // ones. The provider this account belonged to takes its place: there
        // is always one, and it is the nearest thing to what was being watched.
        if enabledAccounts == [account.id] {
            enabledAccounts = [AccountKey(account.provider).id]
        } else {
            enabledAccounts.remove(account.id)
        }
        providerOrder.removeAll { $0 == account.id }
        pinnedWindows[account.id] = nil
        sources[account.id] = nil
        ringTints[account.id] = nil
        sessionBrowsers[account.id] = nil
        serverAddresses[account.id] = nil
        lowBalanceAlerts[account.id] = nil
        balanceBases[account.id] = nil
        balanceBudgets[account.id] = nil
        detailedCards.remove(account.id)
        splitAccounts.remove(account.id)
        if menuBarAccount == account.id { menuBarAccount = nil }
    }

    func rename(_ account: AccountKey, to label: String) {
        guard let index = extraAccounts.firstIndex(where: { $0.key == account }) else { return }
        extraAccounts[index].label = label
    }

    // MARK: - Reading the rail without the app

    /// What is on the rail, for a command that must not disturb anything.
    ///
    /// **Reads and never writes**, which is the whole reason it is not
    /// `restored()`. That one stamps `hasRun`, the offered list and the
    /// resolved enabled set on its way through — correct once at launch, and
    /// wrong for something a status line runs every few seconds. It also puts
    /// the language into effect and re-measures `PanelMetrics`, neither of
    /// which a command printing JSON has any business doing.
    ///
    /// Nothing is resolved or defaulted either: an installation that has never
    /// run the app has nothing stored, and the honest answer for it is an
    /// empty rail rather than a guess at what would be switched on.
    struct StoredRail: Sendable {
        /// Enabled accounts, in the order the rail draws them.
        let accounts: [AccountKey]
        /// What the user calls an added account.
        let labels: [String: String]
        /// The window each account's ring is pinned to, if any.
        let pinnedWindows: [String: String]
    }

    static func storedRail() -> StoredRail {
        let defaults = UserDefaults.standard

        let extras = defaults.data(forKey: Key.extraAccounts)
            .flatMap { try? JSONDecoder().decode([ExtraAccount].self, from: $0) } ?? []
        // **Not scanned here.** A status line runs this every couple of
        // seconds, and the folder was already read by the app, which writes
        // down what it found — account id to name — each time it looks.
        let found = (defaults.dictionary(forKey: Key.extensionNames) as? [String: String] ?? [:])
            .compactMap { id, name in AccountKey(id: id).map { ($0, name) } }
            .filter { $0.0.provider == .pulseExtension }
            .sorted { $0.0.id < $1.0.id }
        let known = Provider.builtIn.flatMap { provider in
            [AccountKey(provider)] + extras.filter { $0.provider == provider }.map(\.key)
        } + found.map(\.0)

        let enabled = Set(defaults.stringArray(forKey: ProviderSelection.enabledKey) ?? [])
        // Same resolution as `orderedAccounts`: stored order first, then
        // anything it doesn't mention, so a provider added since a stored list
        // was written comes last rather than vanishing.
        let stored = (defaults.stringArray(forKey: Key.providerOrder) ?? [])
            .compactMap(AccountKey.init(id:))
            .filter(known.contains)
        let ordered = stored + known.filter { !stored.contains($0) }

        return StoredRail(
            accounts: ordered.filter { enabled.contains($0.id) },
            // `uniqueKeysWithValues` **traps** on a duplicate, and this
            // dictionary is built from a file anyone can edit — in the one
            // command a status line runs every couple of seconds. Everywhere
            // else in the app tolerates duplicates (`label(for:)` takes the
            // first), so crashing here would be the only place that doesn't.
            labels: Dictionary(
                extras.map { ($0.id, $0.label) } + found.map { ($0.0.id, $0.1) },
                uniquingKeysWith: { first, _ in first }
            ),
            pinnedWindows: defaults.dictionary(forKey: Key.pinnedWindows) as? [String: String] ?? [:]
        )
    }

    /// The settings `init` has no parameter for: what discovery and the
    /// extensions folder found.
    func restoreAccounts(detected: Set<Provider>, suggested: Set<Provider>, scan: ExtensionCatalog.Scan) {
        detectedProviders = detected
        suggestedProviders = suggested
        extensions = scan.extensions
        extensionProblems = scan.problems
    }
}
