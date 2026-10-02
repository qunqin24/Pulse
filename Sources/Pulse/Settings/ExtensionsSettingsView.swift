// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// The Extensions pane: where extensions live, which ones were found, and
/// which folders could not be used and why.
///
/// Each extension found also has its own row under this one in the sidebar,
/// with the same pane every account has. This is the list, not the switches.
struct ExtensionsSettingsView: View {
    let settings: AppSettings
    /// Opens an extension's own pane.
    let open: (AccountKey) -> Void

    static let guideURL = URL(string: "https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md")!

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(localized: "An extension is a program you add yourself that reports one account's usage. Pulse draws what it prints as a ring, runs it only once you switch it on, and gives it no credentials.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsGroup(String.localized("Folder")) {
                SettingsRow(
                    String.localized("Extensions folder"),
                    subtitle: Self.displayPath(ExtensionCatalog.folder)
                ) {
                    Button(String.localized("Show in Finder"), action: showFolder)
                }
                SettingsRowDivider()
                SettingsRow(
                    String.localized("Look again"),
                    subtitle: String.localized("Pulse reads this folder when it starts. After adding or changing an extension, look again.")
                ) {
                    Button(String.localized("Look again")) { settings.rescanExtensions() }
                }
                SettingsRowDivider()
                SettingsRow(String.localized("How to write an extension")) {
                    Link(destination: Self.guideURL) {
                        Text(localized: "Open")
                    }
                }
            }

            SettingsGroup(String.localized("Found")) {
                if settings.extensions.isEmpty {
                    SettingsRow(
                        String.localized("None yet"),
                        subtitle: String.localized("Each extension is a folder of its own, holding pulse-extension.json and its program.")
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(settings.extensions.enumerated()), id: \.element.id) { index, found in
                        if index > 0 { SettingsRowDivider() }
                        SettingsRow(
                            found.name,
                            subtitle: settings.isEnabled(found.account)
                                ? String.localized("Shown in the panel")
                                : String.localized("Off")
                        ) {
                            Button(String.localized("Settings…")) { open(found.account) }
                        }
                    }
                }
            }

            if !settings.extensionProblems.isEmpty {
                SettingsGroup(String.localized("Couldn't be used")) {
                    ForEach(Array(settings.extensionProblems.enumerated()), id: \.element.id) { index, problem in
                        if index > 0 { SettingsRowDivider() }
                        SettingsRow(problem.folder, subtitle: problem.reason.message) {
                            EmptyView()
                        }
                    }
                }
            }
        }
        // Somebody opening this pane has most likely just put something in
        // the folder. Reading it costs a directory listing and a few small
        // files, and runs nothing.
        .onAppear { settings.rescanExtensions() }
    }

    /// Made on first use rather than at launch, so a Pulse that never has an
    /// extension never has the folder either.
    private func showFolder() {
        let folder = ExtensionCatalog.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// `~` for the home folder: the full path is mostly a user name.
    static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// What an extension's own pane says about the program behind it: which file
/// runs, from where, and for how long at most.
struct ExtensionProgramGroup: View {
    let pulseExtension: PulseExtension

    var body: some View {
        SettingsGroup(String.localized("Extension")) {
            SettingsRow(
                String.localized("Program"),
                subtitle: ExtensionsSettingsView.displayPath(pulseExtension.executable)
            ) {
                Button(String.localized("Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([pulseExtension.executable])
                }
            }
            SettingsRowDivider()
            SettingsRow(
                String.localized("Time limit"),
                subtitle: String.localized("Stopped if it hasn't answered by then.")
            ) {
                Text(localized: "\(String(Int(pulseExtension.timeout))) seconds")
                    .foregroundStyle(.secondary)
            }
            SettingsRowDivider()
            SettingsRow(
                String.localized("Id"),
                subtitle: String.localized("From its pulse-extension.json. Pulse keeps this extension's settings under it.")
            ) {
                Text(verbatim: pulseExtension.id)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

#Preview {
    ExtensionsSettingsView(settings: AppSettings(), open: { _ in })
        .padding()
        .frame(width: 560)
}
