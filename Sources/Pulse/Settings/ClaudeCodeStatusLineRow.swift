// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Registering Pulse as Claude Code's status line is the backup route for
/// its figures — the main one is the account's usage endpoint. It earns
/// its place because the stored login expires after a few hours and
/// nothing here renews it, so the status line covers the gap until Claude
/// Code is next used. Kept visible and reversible rather than being wired
/// up behind the user's back.
struct ClaudeCodeStatusLineRow: View {
    let store: UsageStore
    let repairs: ConnectionRepairModel

    var body: some View {
        Group {
            SettingsRow(
                String.localized("Claude Code status line"),
                subtitle: String.localized("A backup for when the saved login expires. Your own status line keeps working."),
                symbol: "terminal"
            ) {
                Button(
                    repairs.isHookInstalled
                        ? String.localized("Disconnect")
                        : String.localized("Connect")
                ) {
                    _ = repairs.isHookInstalled ? StatusLineHook.uninstall() : StatusLineHook.install()
                    repairs.hookGeneration += 1
                    store.refresh()
                }
            }
        }
    }
}
