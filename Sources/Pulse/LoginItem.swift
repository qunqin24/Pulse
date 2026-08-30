import Foundation
import ServiceManagement

/// Starting Pulse when the user logs in.
///
/// Two routes, for the same reason the usage services have two: the modern one
/// is better but doesn't always apply.
///
/// - `SMAppService.mainApp` is the supported API and the one System Settings
///   shows under Login Items, but it only works for an app in a real `.app`
///   bundle. Run as a bare executable — which is what `swift run Pulse`
///   produces — it reports `notFound` and registration cannot succeed.
/// - So when there is no bundle, a launch agent is written to
///   `~/Library/LaunchAgents` instead. launchd reads that directory at login,
///   so nothing has to be loaded for it to take effect next time.
///
/// The agent deliberately does **not** set `KeepAlive`: quitting Pulse should
/// leave it quit until the next login, not have it immediately restarted.
enum LoginItem {
    /// Whether this build is an app bundle, and so can use the modern route.
    static var usesAppService: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    enum State: Equatable {
        case on
        case off
        /// Registered, but macOS wants the user to approve it in System
        /// Settings before it will actually run.
        case needsApproval
    }

    static var state: State {
        guard usesAppService else {
            return FileManager.default.fileExists(atPath: agentURL.path) ? .on : .off
        }

        return switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    static var isEnabled: Bool { state != .off }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard usesAppService else {
            return enabled ? writeAgent() : removeAgent()
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    /// Turns it on the first time Pulse runs, and never again.
    ///
    /// The flag is what stops this from fighting the user: switching it off —
    /// here or in System Settings — has to stick, so "on by default" can only
    /// ever be a decision taken once.
    static func applyDefaultOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Key.decided) else { return }
        defaults.set(true, forKey: Key.decided)
        setEnabled(true)
    }

    /// Hands a launch agent over to the supported route once there is a bundle
    /// to register.
    ///
    /// A build that has become an app bundle leaves its old agent behind, still
    /// naming the loose binary — so at the next login launchd starts the old
    /// build *and* `SMAppService` starts the new one, and there are two Pulses
    /// on screen. The agent existing is proof it was switched on, so the answer
    /// is to move that decision across rather than to drop it.
    static func adoptBundleIfNeeded() {
        guard usesAppService, FileManager.default.fileExists(atPath: agentURL.path) else { return }

        _ = removeAgent()
        setEnabled(true)
    }

    /// Rebuilding moves the executable, which leaves the agent pointing at a
    /// binary that is no longer there. Same problem, and same fix, as
    /// `StatusLineHook.repairPathIfNeeded`.
    static func repairPathIfNeeded() {
        guard !usesAppService, FileManager.default.fileExists(atPath: agentURL.path) else { return }

        guard
            let data = try? Data(contentsOf: agentURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let arguments = plist["ProgramArguments"] as? [String],
            arguments.first != Bundle.main.executablePath
        else { return }

        _ = writeAgent()
    }

    // MARK: - The launch agent

    private static let label = "com.pulse.launch-at-login"

    private static var agentURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/LaunchAgents/\(label).plist")
    }

    private static func writeAgent() -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true
        ]

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        ) else { return false }

        try? FileManager.default.createDirectory(
            at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return (try? data.write(to: agentURL, options: .atomic)) != nil
    }

    private static func removeAgent() -> Bool {
        guard FileManager.default.fileExists(atPath: agentURL.path) else { return true }
        return (try? FileManager.default.removeItem(at: agentURL)) != nil
    }

    private enum Key {
        static let decided = "settings.launchAtLogin.decided"
    }
}
