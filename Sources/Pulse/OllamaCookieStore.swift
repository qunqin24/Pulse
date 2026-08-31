import Foundation
import Security
import LocalAuthentication

/// Separate from APIKeyStore: a browser session is a password-equivalent secret.
/// Reads do not prompt at startup; writes happen only after an explicit Save.
enum OllamaCookieStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "io.github.qunqin24.Pulse.ollama-cloud",
         kSecAttrAccount as String: "session-cookie",
         kSecAttrSynchronizable as String: false]
    }

    static func cookie() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ header: String) -> Bool {
        if header.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        guard let normalized = try? OllamaSessionCookie.normalize(header) else { return false }
        let attributes: [String: Any] = [kSecValueData as String: Data(normalized.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query.merging(attributes) { _, value in value }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
