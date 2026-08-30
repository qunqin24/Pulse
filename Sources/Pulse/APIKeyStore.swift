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
            let box = try? AES.GCM.SealedBox(combined: stored),
            let opened = try? AES.GCM.open(box, using: secret()),
            let key = String(data: opened, encoding: .utf8),
            !key.isEmpty
        else { return nil }

        return key
    }

    /// Stores a key, or removes it when the field is cleared.
    @discardableResult
    static func setKey(_ key: String?, for provider: Provider) -> Bool {
        var keys = load()
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmed, !trimmed.isEmpty {
            guard let sealed = try? AES.GCM.seal(Data(trimmed.utf8), using: secret()).combined else {
                return false
            }
            keys[provider.rawValue] = sealed
        } else {
            keys[provider.rawValue] = nil
        }

        return save(keys)
    }

    // MARK: - The file

    private static func load() -> [String: Data] {
        guard
            let data = try? Data(contentsOf: file),
            let keys = try? JSONDecoder().decode([String: Data].self, from: data)
        else { return [:] }

        return keys
    }

    private static func save(_ keys: [String: Data]) -> Bool {
        PulseStorage.prepare()

        guard let data = try? JSONEncoder().encode(keys) else { return false }
        guard (try? data.write(to: file, options: .atomic)) != nil else { return false }

        // Written after the file exists, and again on every save: an atomic
        // write replaces the file, and the replacement does not inherit it.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: file.path
        )
        return true
    }

    // MARK: - The secret

    /// Derived from this Mac's hardware identifier, so the same file on
    /// another machine yields nothing.
    private static func secret() -> SymmetricKey {
        var material = Data("Pulse api keys".utf8)
        if let hardware = hardwareIdentifier() {
            material.append(Data(hardware.utf8))
        }
        return SymmetricKey(data: SHA256.hash(data: material))
    }

    private static func hardwareIdentifier() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let property = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )
        return property?.takeRetainedValue() as? String
    }
}
