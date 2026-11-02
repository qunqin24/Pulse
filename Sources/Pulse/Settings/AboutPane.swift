// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

struct AboutPane: View {
    let update: AppUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(String.localized("Version"), subtitle: updateSubtitle) {
                    if update.canCheck {
                        // Sparkle puts up its own window with whatever it
                        // finds, so this is the same button either way — there
                        // is nothing for Pulse to draw on top of it.
                        Button(
                            update.newer.map { String.localized("Update to \($0.version)") }
                                ?? String.localized("Check now")
                        ) {
                            update.check()
                        }
                        .disabled(update.isChecking)
                    } else {
                        Text(Self.version)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                if update.canCheck {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Check automatically"),
                        subtitle: String.localized("Every two hours. Updates are offered, never installed on their own.")
                    ) {
                        Toggle("", isOn: Binding(
                            get: { update.checksAutomatically },
                            set: { update.checksAutomatically = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Usage data"),
                    subtitle: String.localized("Read from each provider's own account. Pulse shows the figures they report; where it has to infer one, the figure itself says so.")
                ) {
                    EmptyView()
                }

                SettingsRowDivider()

                // The address itself as the subtitle, not a sentence about it:
                // somebody reading this pane wants to know where the source is,
                // and half of them will want to type it rather than click.
                SettingsRow(
                    String.localized("Source code"),
                    subtitle: "github.com/qunqin24/Pulse"
                ) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(URL(string: "https://github.com/qunqin24/Pulse")!)
                    }
                }
            }

            SettingsGroup(String.localized("Credits")) {
                SettingsRow(
                    "Vinz (@hivinz_)",
                    subtitle: String.localized("Panel design inspired by Vinz's work shared on X.")
                ) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(
                            URL(string: "https://x.com/hivinz_/status/2092996055248126353")!
                        )
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    "Lobe Icons",
                    subtitle: String.localized("Provider marks from github.com/lobehub/lobe-icons.")
                ) {
                    EmptyView()
                }

                SettingsRowDivider()

                // A port, and said to be one: the character and its motion
                // are CX ArtLab's original design, not Pulse's.
                SettingsRow(
                    "Agent Robot Avatar",
                    subtitle: String.localized("The robot in the rings is ported from CX ArtLab's Agent Robot Avatar, an original character by CX ArtLab, under the MIT License.")
                ) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(URL(string: "https://github.com/CX-ArtLab/agent-robot-avatar")!)
                    }
                }
            }
        }
        // Without this the row says "up to date" on nothing but the last
        // answer, however old. Quiet: the subtitle is where the result goes.
        .onAppear { update.probe() }
    }

    /// The version, and what is known about a newer one. All four states are
    /// distinguishable on purpose: "no update" and "couldn't ask" look
    /// identical otherwise, and a check that silently failed is worse than one
    /// that says so.
    private var updateSubtitle: String {
        if let newer = update.newer {
            return .localized("\(Self.version) installed · \(newer.version) available")
        }
        if update.isChecking { return .localized("Checking…") }
        if update.didFail { return .localized("Couldn't reach the update feed.") }
        if !update.canCheck { return .localized("Built from source — no update check.") }
        return .localized("\(Self.version) · up to date")
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1 (prototype)"
    }
}
