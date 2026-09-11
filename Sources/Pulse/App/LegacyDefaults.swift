import Foundation

/// Carries settings over the first time Pulse runs as an app bundle.
///
/// `UserDefaults.standard` writes to a domain named after the bundle
/// identifier — and, when there is no bundle, after the process name. So a
/// loose `swift run Pulse` build has been keeping everything in a domain called
/// `Pulse`, and the moment the same app runs from `Pulse.app` it reads a
/// different, empty one: every setting, the panel's position, which providers
/// are on, whether login-at-start was already decided. All of it would look
/// like a fresh install, and turning login-at-start back on would fight a user
/// who had turned it off.
///
/// This copies the old domain across once. Only keys the new domain does not
/// already have are taken, so a bundled build that has since been configured is
/// never overwritten by a stale value.
///
/// After this the two diverge, which is correct: a build running from Xcode and
/// an installed `Pulse.app` are two copies of the app and should not be editing
/// each other's settings.
enum LegacyDefaults {
    /// What `UserDefaults.standard` resolves to for a bare executable.
    private static let looseBinaryDomain = "Pulse"
    private static let flag = "settings.adoptedLooseBinaryDefaults"

    static func migrateIfNeeded() {
        // Nothing to do in the loose build — it *is* the old domain.
        guard Bundle.main.bundleIdentifier != nil else { return }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)

        guard let legacy = defaults.persistentDomain(forName: looseBinaryDomain) else { return }

        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
