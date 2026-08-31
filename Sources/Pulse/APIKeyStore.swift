import CryptoKit
import Foundation
import IOKit

/// Where a key typed into Settings is kept: encrypted, in Pulse's own folder.
///
/// One file, `keys.dat`, holding AES-GCM boxes keyed by provider. The file is
/// owner-only, and the key that opens it is derived from this Mac rather than
/// stored anywhere, so a copy of the file on its own — in a backup, a synced
/// folder, a shared screen — opens nowhere.
enum APIKeyStore {
    private static var file: URL {
        PulseStorage.directory.appending(path: "keys.dat")
    }

    static func key(for provider: Provider) -> String? {
        guard
            let stored = load()[provider.rawValue],
            let opened = LocalSecrets.open(stored, purpose: Self.purpose),
            let key = String(data: opened, encoding: .utf8),
            !key.isEmpty
        else { return nil }

        return key
    }

    /// Stores a key, or removes it when the field is cleared.
    @discardableResult
    static func setKey(_ key: String?, for provider: Provider) -> Bool {
        // A file that exists but won't decode is not an empty one. Treating it
        // as empty meant saving one provider's key silently threw away every
        // other provider's — and said it had succeeded.
        guard var keys = readable() else { return false }
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmed, !trimmed.isEmpty {
            guard let sealed = LocalSecrets.seal(Data(trimmed.utf8), purpose: Self.purpose) else { return false }
            keys[provider.rawValue] = sealed
        } else {
            keys[provider.rawValue] = nil
        }

        return save(keys)
    }

    /// Distinct from the account logins' purpose, so a box from one store can
    /// never be opened by the other.
    private static let purpose = "Pulse api keys"

    // MARK: - The file

    private static func load() -> [String: Data] { readable() ?? [:] }

    /// What is stored, or nil when there is a file here that cannot be read.
    /// An absent file is empty; an unreadable one is not.
    private static func readable() -> [String: Data]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }

        guard
            let data = try? Data(contentsOf: file),
            let keys = try? JSONDecoder().decode([String: Data].self, from: data)
        else { return nil }

        return keys
    }

    private static func save(_ keys: [String: Data]) -> Bool {
        guard let data = try? JSONEncoder().encode(keys) else { return false }
        return LocalSecrets.write(data, to: file)
    }
}
