import CryptoKit
import Foundation
import IOKit

/// Encrypting something small enough to keep in Pulse's own folder.
///
/// The key is derived from this Mac rather than stored anywhere, so a copy of
/// the file on its own — in a backup, a synced folder, on someone else's
/// machine — opens nowhere. Both the entered API keys and the account logins
/// are kept this way; the crypto lives here so there is one copy of it to be
/// right about.
enum LocalSecrets {
    /// Nil when the machine identifier can't be read.
    ///
    /// Falling back to a fixed string would give every Mac the same key, which
    /// is worse than not encrypting at all — it would look protected while a
    /// copied file opened anywhere.
    static func seal(_ plain: Data, purpose: String) -> Data? {
        guard let key = key(for: purpose) else { return nil }
        return try? AES.GCM.seal(plain, using: key).combined
    }

    static func open(_ sealed: Data, purpose: String) -> Data? {
        guard
            let key = key(for: purpose),
            let box = try? AES.GCM.SealedBox(combined: sealed)
        else { return nil }

        return try? AES.GCM.open(box, using: key)
    }

    /// A different key per purpose, so a box from one store can never be
    /// opened by another even though both are derived from the same machine.
    private static func key(for purpose: String) -> SymmetricKey? {
        guard let hardware = hardwareIdentifier() else { return nil }

        let material = Data(purpose.utf8) + Data(hardware.utf8)
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

    /// Writes a file only this user can read, and keeps it that way.
    ///
    /// The permissions are set after every write, not once: an atomic write
    /// replaces the file, and the replacement does not inherit them.
    static func write(_ data: Data, to file: URL) -> Bool {
        PulseStorage.prepare()

        guard (try? data.write(to: file, options: .atomic)) != nil else { return false }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: file.path
        )
        return true
    }
}
