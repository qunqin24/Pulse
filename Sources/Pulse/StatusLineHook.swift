import AppKit
import Foundation

/// Pulse's side of Claude Code's status line.
///
/// Claude Code doesn't publish a usage figure anywhere Pulse could read: the
/// session transcripts carry token counts but no limits, and `rateLimits` only
/// appears there on a rate-limit *error*. What it does do — documented at
/// code.claude.com/docs/en/statusline — is pipe a JSON blob to whatever command
/// you register as your status line after every response, and that blob carries
/// `rate_limits.five_hour` and `rate_limits.seven_day` with the official
/// `used_percentage` and `resets_at`.
///
/// So Pulse registers itself as that command. Run as `Pulse --statusline`, it
/// reads the blob from stdin, keeps the usage part, and prints a status line
/// back for Claude Code to display.
///
/// The catch is that this is a push, not a pull: the figures only refresh while
/// a Claude Code session is running. Between sessions the reading is whatever
/// it was when you last used it, which is why `ClaudeCodeUsageService` reports
/// its age rather than presenting it as current.
enum StatusLineHook {
    /// Where the captured usage is parked for the app to pick up.
    static var cacheFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: ".claude/pulse-usage.json")
    }

    static var settingsFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: ".claude/settings.json")
    }

    /// The argument that switches the executable out of app mode.
    static let modeArgument = "--statusline"

    // MARK: - Running as the status line

    /// Reads one status line payload from stdin, banks the usage figures, and
    /// prints the line Claude Code should show.
    ///
    /// Anything unexpected is swallowed on purpose: this runs inside someone's
    /// editor after every response, and a status line that errors out or hangs
    /// is far worse than one that says nothing.
    static func runAsStatusLine() {
        let input = FileHandle.standardInput.readDataToEndOfFile()

        guard
            let root = try? JSONSerialization.jsonObject(with: input) as? [String: Any]
        else { return }

        if let limits = root["rate_limits"] as? [String: Any] {
            capture(limits)
        }

        if let chained = chainedOutput(for: input) {
            print(chained, terminator: "")
        } else {
            print(defaultLine(root), terminator: "")
        }
    }

    /// Writes the reading somewhere the app can read it, replacing the file in
    /// one step so the app never catches it half-written.
    private static func capture(_ limits: [String: Any]) {
        let payload: [String: Any] = [
            "capturedAt": Date().timeIntervalSince1970,
            "rate_limits": limits
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let temporary = cacheFile.appendingPathExtension("tmp-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(
            at: cacheFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard (try? data.write(to: temporary)) != nil else { return }
        _ = try? FileManager.default.replaceItemAt(cacheFile, withItemAt: temporary)
    }

    /// If the user already had a status line before Pulse took the slot, run it
    /// with the same input and show its output, so installing Pulse doesn't
    /// quietly throw away their own status line.
    private static func chainedOutput(for input: Data) -> String? {
        guard let command = UserDefaults.standard.string(forKey: Key.previousCommand),
              !command.isEmpty
        else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// What Pulse shows when it owns the status line outright: the two limits,
    /// which is the reason the hook is there in the first place.
    private static func defaultLine(_ root: [String: Any]) -> String {
        let limits = root["rate_limits"] as? [String: Any]

        let parts = [("five_hour", "5h"), ("seven_day", "7d")].compactMap { key, label -> String? in
            guard
                let window = limits?[key] as? [String: Any],
                let percent = Self.percent(window["used_percentage"])
            else { return nil }
            return "\(label) \(Int(percent.rounded()))%"
        }

        let model = (root["model"] as? [String: Any])?["display_name"] as? String
        return ([model] + parts).compactMap { $0 }.joined(separator: "  ·  ")
    }

    static func percent(_ value: Any?) -> Double? {
        let number = (value as? Double) ?? (value as? Int).map(Double.init)
        // Claude Code has shipped builds where this field leaked the epoch
        // reset time instead of a percentage; anything past 101 is not a
        // percentage, so drop it rather than draw a full ring from it.
        guard let number, number >= 0, number <= 101 else { return nil }
        return number
    }

    // MARK: - Installing

    static var isInstalled: Bool {
        guard let settings = readSettings(),
              let line = settings["statusLine"] as? [String: Any],
              let command = line["command"] as? String
        else { return false }
        return command.contains(modeArgument)
    }

    /// Points Claude Code's status line at this executable, remembering any
    /// command that was already there so it can be chained and later restored.
    @discardableResult
    static func install() -> Bool {
        var settings = readSettings() ?? [:]

        if let existing = settings["statusLine"] as? [String: Any],
           let command = existing["command"] as? String,
           !command.contains(modeArgument) {
            UserDefaults.standard.set(command, forKey: Key.previousCommand)
        }

        let executable = ProcessInfo.processInfo.arguments.first.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        } ?? Bundle.main.executablePath ?? ""

        settings["statusLine"] = [
            "type": "command",
            "command": "\"\(executable)\" \(modeArgument)"
        ]
        return writeSettings(settings)
    }

    /// Puts the status line back the way it was.
    @discardableResult
    static func uninstall() -> Bool {
        guard var settings = readSettings() else { return false }

        if let previous = UserDefaults.standard.string(forKey: Key.previousCommand), !previous.isEmpty {
            settings["statusLine"] = ["type": "command", "command": previous]
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        UserDefaults.standard.removeObject(forKey: Key.previousCommand)

        return writeSettings(settings)
    }

    /// Rewrites the registered path when the executable has moved, which it
    /// does whenever the project is rebuilt somewhere else.
    static func repairPathIfNeeded() {
        guard isInstalled else { return }
        guard let settings = readSettings(),
              let line = settings["statusLine"] as? [String: Any],
              let command = line["command"] as? String
        else { return }

        let executable = ProcessInfo.processInfo.arguments.first.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        } ?? ""
        guard !executable.isEmpty, !command.contains(executable) else { return }

        install()
    }

    // MARK: - Settings file

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root
    }

    private static func writeSettings(_ settings: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return false }

        // Keep a copy of the file as it was before Pulse first touched it.
        let backup = settingsFile.appendingPathExtension("pulse-backup")
        if !FileManager.default.fileExists(atPath: backup.path),
           let original = try? Data(contentsOf: settingsFile) {
            try? original.write(to: backup)
        }

        return (try? data.write(to: settingsFile)) != nil
    }

    /// Asks — once, ever — whether to connect the status line.
    ///
    /// Without it Pulse works only while Claude Code's saved login is fresh,
    /// which it is for a few hours after Claude Code is used and never at the
    /// moment someone opens their Mac and wants to know what they have left.
    /// That is a feature half missing, and leaving the decision to a user who
    /// has no way of knowing the choice exists is not respecting them, it is
    /// passing them the bill.
    ///
    /// It is still a question rather than a default. Connecting writes into
    /// *another program's* configuration and changes what that program prints
    /// at the bottom of the screen — reading a credential is invisible and
    /// harmless, this is neither.
    ///
    /// Asked at first launch and never again, whatever the answer: the reply
    /// is recorded before the alert is even shown, so a crash mid-question
    /// cannot turn into a second one. Declining is not a dead end — the row in
    /// Settings stays, and an expired login now says where to find it.
    @MainActor
    static func offerOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Key.offered) else { return }

        // Nothing to offer someone who doesn't have Claude Code.
        guard FileManager.default.fileExists(atPath: settingsFile.deletingLastPathComponent().path) else {
            return
        }

        defaults.set(true, forKey: Key.offered)
        guard !isInstalled else { return }

        let alert = NSAlert()
        alert.messageText = .localized("Keep reading Claude Code's usage after its login expires?")
        alert.informativeText = .localized("Claude Code saves a login that lasts a few hours, and only Claude Code can renew it. It also reports your limits to whatever status line command is registered — Pulse can be that command, and then it keeps working whether the login is fresh or not.\n\nThis edits ~/.claude/settings.json and changes the status line at the bottom of your Claude Code sessions. Any status line you already have keeps working, and you can disconnect it in Settings.")
        alert.addButton(withTitle: .localized("Connect"))
        alert.addButton(withTitle: .localized("Not now"))

        // An .accessory app has to bring itself forward or the question opens
        // behind whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            _ = install()
        }
    }

    private enum Key {
        static let previousCommand = "statusLine.previousCommand"
        /// Whether the question has been put, regardless of the answer.
        static let offered = "statusLine.offered"
    }
}
