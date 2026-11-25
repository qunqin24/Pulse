// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// Added accounts of the self-hosted gateways (`Provider.addsAccountsByAddress`).
// Each is another deployment: its own address (`serverAddresses`, keyed by
// account id like every per-account setting), its own key and its own name.
// Nothing about it is signed in to, so it has no entry in
// `AccountCredentialStore`; the key is in `APIKeyStore` beside the first
// account's.

extension AppSettings {
    /// Where an account's typed key is kept beside its provider's own entry.
    ///
    /// A first account keeps the provider's slot (`keySlot(for:)` — nil, or
    /// MiniMax's site), so nothing already saved moves. An added account keeps
    /// its own slot, which makes the store's entry `provider#slot`: the
    /// account's id, generated once and never reused, so a key can never be
    /// read on behalf of another account or inherited by a later one.
    func keySlot(for account: AccountKey) -> String? {
        account.isPrimary ? keySlot(for: account.provider) : account.slot
    }

    /// Adds another deployment of a gateway, switched on and last in the rail.
    /// It starts with no address and no key: the pane that opens asks for both.
    @discardableResult
    func addGatewayAccount(_ provider: Provider) -> AccountKey? {
        guard provider.addsAccountsByAddress else { return nil }
        return addAccount(provider, label: nextGatewayLabel(for: provider))
    }

    /// "sub2api 2", "sub2api 3", …: the first number no added account of this
    /// provider is called by. A gateway reports no account name to seed it
    /// from, and a number at least tells two new rows apart until they are
    /// renamed. Counting the accounts instead gave a second "sub2api 3" after
    /// one in the middle was removed.
    func nextGatewayLabel(for provider: Provider) -> String {
        let taken = Set(extraAccounts.filter { $0.provider == provider }.map(\.label))
        var number = 2
        while taken.contains("\(provider.displayName) \(number)") { number += 1 }
        return "\(provider.displayName) \(number)"
    }

    /// Forgets an added gateway account: its key first, then every setting
    /// stored against it (`removeAccount`), its address and name among them.
    ///
    /// **Nothing is removed if the key could not be.** A key left in the file
    /// under a slot no account names any more is a secret nobody can see or
    /// delete from Settings.
    @discardableResult
    func removeGatewayAccount(_ account: AccountKey, keysIn directory: URL = PulseStorage.directory) -> Bool {
        guard !account.isPrimary, account.provider.addsAccountsByAddress else { return false }
        guard APIKeyStore.setKey(nil, for: account.provider, slot: keySlot(for: account), in: directory) else {
            return false
        }
        removeAccount(account)
        return true
    }
}
