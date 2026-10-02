// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

struct ProviderSetupView: View {
    let settings: AppSettings
    let providers: [Provider]
    let isInitial: Bool
    let finish: (Set<Provider>) -> Void
    let dismiss: () -> Void
    @State private var selected: Set<Provider> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Grouped the way Settings lists them. Each group keeps the
                    // order it was handed: detected first, then by name.
                    ForEach(Provider.Billing.allCases, id: \.self) { billing in
                        let group = providers.filter { $0.billing == billing }
                        if !group.isEmpty {
                            Text(billing.sectionTitle)
                                .font(.headline)
                                .padding(.top, billing == Provider.Billing.allCases.first ? 4 : 20)
                                .padding(.bottom, 4)
                            ForEach(group) { provider in
                                ProviderSetupRow(
                                    provider: provider,
                                    detected: settings.detectedProviders.contains(provider),
                                    isSelected: Binding(
                                        get: { selected.contains(provider) },
                                        set: { enabled in
                                            if enabled { selected.insert(provider) }
                                            else { selected.remove(provider) }
                                        }
                                    )
                                )
                                Divider()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            HStack {
                Button(String.localized("Select detected services")) {
                    selected.formUnion(Set(providers).intersection(settings.detectedProviders))
                }
                .disabled(Set(providers).isDisjoint(with: settings.detectedProviders))
                Spacer()
                Button(String.localized("Not now"), action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(String.localized("Done")) { finish(selected) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInitial && selected.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 620, minHeight: 480)
        .id(settings.language)
    }

    private var title: String {
        isInitial ? .localized("Choose services to monitor") : .localized("New services detected")
    }

    private var explanation: String {
        isInitial
            ? .localized("Choose at least one service. Pulse reads its login and checks usage only after you finish. You can change this later in Settings.")
            : .localized("This version supports more services found on your Mac. Choose any you want to add; your existing choices stay in place.")
    }
}

private struct ProviderSetupRow: View {
    let provider: Provider
    let detected: Bool
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(alignment: .top, spacing: 12) {
                LobeIconView(provider: provider, size: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(provider.displayName).fontWeight(.medium)
                        if detected {
                            Text(localized: "Detected on this Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(provider.monitoringAccessDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 14)
    }
}

#Preview {
    ProviderSetupView(
        settings: AppSettings(enabledAccounts: []),
        providers: Provider.builtIn, isInitial: true,
        finish: { _ in }, dismiss: {}
    )
}
