import AppKit
import SwiftUI

struct DeveloperIntegrationsView: View {
    let settings: AppSettings
    @State private var selectedAccount = AccountKey(.claudeCode)
    @State private var message: String?

    private var executable: String {
        Bundle.main.executableURL?.path ?? "/Applications/Pulse.app/Contents/MacOS/Pulse"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Read cached usage")) {
                SettingsRow(
                    "Pulse --json",
                    subtitle: String.localized("Reads saved figures without fetching or opening credentials.")
                ) {
                    Button(String.localized("Copy command")) { copy(Self.quote(executable) + " --json") }
                }
                SettingsRowDivider()
                SettingsRow(
                    String.localized("Developer kit"),
                    subtitle: String.localized("Raycast extension, tmux and shell status, and a sketchybar plugin.")
                ) {
                    Button(String.localized("Export integration files…"), action: exportKit)
                }
                SettingsRowDivider()
                SettingsRow(String.localized("Installation guide")) {
                    Link(destination: URL(string: "https://github.com/harrisliangsu/Pulse/blob/main/Docs/integrations.md")!) {
                        Text(localized: "Open")
                    }
                }
            }

            SettingsGroup(String.localized("Open an account")) {
                SettingsRow(String.localized("Account")) {
                    Picker(String.localized("Account"), selection: $selectedAccount) {
                        ForEach(settings.orderedAccounts) { account in
                            Text(settings.label(for: account)).tag(account)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
                SettingsRowDivider()
                SettingsRow(
                    String.localized("Account link"),
                    subtitle: String.localized("Opens this account's settings in the installed Pulse app.")
                ) {
                    Button(String.localized("Copy link")) {
                        copy(PulseLink.account(selectedAccount).url.absoluteString)
                    }
                }
                SettingsRowDivider()
                SettingsRow(String.localized("Open from terminal")) {
                    Button(String.localized("Copy command")) {
                        copy("open " + Self.quote(PulseLink.account(selectedAccount).url.absoluteString))
                    }
                }
            }

            Text(localized: "Keep Pulse running to update the cache. Every reading includes its age; an old reading is not a live check.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let message {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .onChange(of: settings.orderedAccounts, initial: true) { _, accounts in
            if !accounts.contains(selectedAccount), let first = accounts.first { selectedAccount = first }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) { message = String.localized("Copied") }
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func exportKit() {
        let bundled = Bundle.main.resourceURL?.appending(path: "Integrations")
        let checkout = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Integrations")
        guard let source = [bundled, checkout].compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.appending(path: "pulse-status.sh").path)
        }) else {
            message = String.localized("Integration files weren't found. Open the installation guide.")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String.localized("Export")
        panel.begin { response in
            guard response == .OK, let directory = panel.url else { return }
            let destination = directory.appending(path: "Pulse Integrations")
            let staging = directory.appending(path: ".pulse-export-\(UUID().uuidString)")
            do {
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    message = String.localized("Pulse Integrations already exists here. Choose another folder.")
                    return
                }
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: staging) }
                try FileManager.default.createDirectory(at: staging.appending(path: "raycast"), withIntermediateDirectories: false)
                // A fixed list excludes a checkout's node_modules and build output.
                for file in ["pulse-status.sh", "pulse-sketchybar.sh", "raycast/package.json",
                             "raycast/package-lock.json", "raycast/tsconfig.json", "raycast/src", "raycast/assets", "raycast/tests"] {
                    try FileManager.default.copyItem(at: source.appending(path: file), to: staging.appending(path: file))
                }
                try FileManager.default.moveItem(at: staging, to: destination)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                message = String.localized("Integration files exported.")
            } catch {
                message = String.localized("Couldn't export integration files. Choose a writable folder.")
            }
        }
    }
}
