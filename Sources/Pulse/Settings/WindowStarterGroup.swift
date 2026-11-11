// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Sends "hi" after each reset so the next window starts then — see
/// `WindowPrimer`. Switching it on goes through a confirmation that says
/// plainly this is not the provider's feature and may cost the account;
/// the reader decides with that in front of them, not in a subtitle.
struct WindowStarterGroup: View {
    let provider: Provider
    let settings: AppSettings

    /// The provider whose window starter is waiting on the risk confirmation.
    @State private var confirmingStarter: Provider?

    var body: some View {
        SettingsGroup(String.localized("Start windows automatically")) {
            SettingsRow(
                String.localized("Start a new window after each reset"),
                subtitle: provider == .claudeCode
                    ? String.localized("When the 5-hour limit resets, sends “hi” to Haiku through Claude Code, so the next window starts counting then rather than at your next message. Nothing is saved.")
                    : String.localized("When the 5-hour or weekly limit resets, sends “hi” to the cheapest model through Codex, so the next window starts counting then rather than at your next message. Nothing is saved."),
                symbol: "play.circle"
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.primesWindows(for: provider) },
                    set: { on in
                        if on { confirmingStarter = provider } else { settings.setPrimesWindows(false, for: provider) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if settings.primesWindows(for: provider) {
                SettingsRowDivider()

                SettingsRow(
                    String.localized("Only between"),
                    subtitle: String.localized("A reset outside these hours is started when they begin. Shared by Claude Code and Codex."),
                    symbol: "clock"
                ) {
                    HStack(spacing: 6) {
                        hourPicker(Binding(
                            get: { settings.primerHours.start },
                            set: { settings.primerHours.start = $0 }
                        ))
                        Text(verbatim: "–")
                        hourPicker(Binding(
                            get: { settings.primerHours.end },
                            set: { settings.primerHours.end = $0 }
                        ))
                    }
                }

                SettingsRowDivider()

                SettingsRow(String.localized("Last started"), symbol: "clock.arrow.circlepath") {
                    Text(verbatim: Self.primerStatus(settings.lastPrimerRun(for: provider)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            }
        }
        .alert(
            String.localized("Use at your own risk"),
            isPresented: Binding(
                get: { confirmingStarter == provider },
                set: { if !$0 { confirmingStarter = nil } }
            )
        ) {
            Button(String.localized("I understand the risk, turn it on"), role: .destructive) {
                settings.setPrimesWindows(true, for: provider)
                confirmingStarter = nil
            }
            Button(String.localized("Cancel"), role: .cancel) { confirmingStarter = nil }
        } message: {
            Text(localized: "This is not a feature of Anthropic or OpenAI. Starting usage windows automatically may be treated as getting around usage limits, and could get your account restricted or suspended. Pulse only sends one short message through the tool you are already signed in to, and is not responsible for anything that happens to your account as a result. Turn it on only if you accept that.")
        }
    }

    private func hourPicker(_ hour: Binding<Int>) -> some View {
        Picker("", selection: hour) {
            ForEach(0..<24, id: \.self) { value in
                Text(verbatim: String(format: "%02d:00", value)).tag(value)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private static func primerStatus(_ run: (date: Date, outcome: WindowStarter.Outcome)?) -> String {
        guard let run else { return .localized("Not started yet") }
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
        let when = formatter.string(from: run.date)
        return switch run.outcome {
        case .sent: when
        case .toolMissing: .localized("\(when) · the command-line tool was not found")
        case .failed: .localized("\(when) · it did not go through; check the tool is signed in")
        case .timedOut: .localized("\(when) · it did not answer in time")
        }
    }
}
