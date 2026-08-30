import Foundation
import Security

/// Where a key typed into Settings is kept.
///
/// The keychain, not `UserDefaults`. Preferences are a plain plist in the
/// user's Library that any process running as them can read, and every backup
/// and sync mechanism copies it around; a credential does not belong there
/// however convenient the API is. This is the only secret Pulse ever holds —
/// the other providers' logins stay where their own tools put them, and Pulse
/// only reads those.
enum APIKeyStore {
    private static let service = "Pulse API keys"

    static func key(for provider: Provider) -> String? {
        var query = base(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let key = String(data: data, encoding: .utf8),
            !key.isEmpty
        else { return nil }

        return key
    }

    /// Stores a key, or removes it when the field is cleared.
    @discardableResult
    static func setKey(_ key: String?, for provider: Provider) -> Bool {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Deleting first rather than updating: an update has to know whether
        // there was anything there, and this has to work either way.
        SecItemDelete(base(provider) as CFDictionary)

        guard let trimmed, !trimmed.isEmpty else { return true }

        var item = base(provider)
        item[kSecValueData as String] = Data(trimmed.utf8)
        // Available without unlocking the keychain interactively, since the
        // refresh loop runs unattended; still never leaves this Mac.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func base(_ provider: Provider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}
