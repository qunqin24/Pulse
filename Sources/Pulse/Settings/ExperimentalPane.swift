// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Features still being tuned, off until switched on here.
struct ExperimentalPane: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup {
                SettingsRow(
                    String.localized("Liquid docking"),
                    subtitle: String.localized("Pulled off a screen edge, the rail stretches and parts like a drop; brought near one, it is drawn in. While dragged, it follows the pointer with a little give."),
                    symbol: "flask"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.liquidDocking },
                        set: { settings.liquidDocking = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }

            Text(localized: "These features are still being tuned and may change or be removed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }
}
