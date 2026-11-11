// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

// The single rows `AccountConnectionGroup` and the account pane draw inside
// their cards. Each is its own view so the card's body reads as the order of
// its rows; what they edit lives in `ProviderCredentialModel` and
// `AccountEntryFields`.

/// Which Qoder site the account is on.
///
/// **Changing it discards the saved session.** The two sites are two
/// sign-ins, and a session kept across the switch would be sent to the
/// host that did not issue it — the one thing `QoderSite` exists to rule
/// out. The reader reads the new site's session next, which is what the
/// subtitle says.
struct QoderSiteRow: View {
    let account: AccountKey
    let settings: AppSettings
    let credentials: ProviderCredentialModel

    var body: some View {
        SettingsRow(
            String.localized("Site"),
            subtitle: String.localized("Where you signed in. Changing it clears the saved session."),
            symbol: "globe.asia.australia"
        ) {
            Picker("", selection: Binding(
                get: { settings.qoderSite },
                set: { site in
                    guard site != settings.qoderSite else { return }
                    settings.qoderSite = site
                    credentials.forgetSession(of: .qoder, for: account)
                }
            )) {
                ForEach(QoderSite.allCases, id: \.self) { site in
                    Text(verbatim: site.host).tag(site)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }
    }
}

/// Which MiniMax site the key is from: minimax.io or minimaxi.com.
///
/// **Unlike Qoder's, changing it keeps the key.** A pasted key is not read
/// back from a browser, so clearing it would lose it; instead each site keeps
/// its own (`MiniMaxSite.keySlot`), and the field shows the chosen site's.
struct MiniMaxSiteRow: View {
    let account: AccountKey
    let settings: AppSettings
    let credentials: ProviderCredentialModel

    var body: some View {
        SettingsRow(
            String.localized("Site"),
            subtitle: String.localized("Where your key is from. Each site keeps its own key."),
            symbol: "globe.asia.australia"
        ) {
            Picker("", selection: Binding(
                get: { settings.minimaxSite },
                set: { site in
                    guard site != settings.minimaxSite else { return }
                    settings.minimaxSite = site
                    credentials.seed(for: account)
                }
            )) {
                ForEach(MiniMaxSite.allCases, id: \.self) { site in
                    Text(verbatim: site.label).tag(site)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }
    }
}

/// Which StepFun console the account is on. The same rule as
/// `QoderSiteRow`: changing it discards the saved session, which belongs
/// to the other host.
struct StepFunSiteRow: View {
    let account: AccountKey
    let settings: AppSettings
    let credentials: ProviderCredentialModel

    var body: some View {
        SettingsRow(
            String.localized("Site"),
            subtitle: String.localized("Where you signed in. Changing it clears the saved session."),
            symbol: "globe.asia.australia"
        ) {
            Picker("", selection: Binding(
                get: { settings.stepFunSite },
                set: { site in
                    guard site != settings.stepFunSite else { return }
                    settings.stepFunSite = site
                    credentials.forgetSession(of: .stepFun, for: account)
                }
            )) {
                ForEach(StepFunSite.allCases, id: \.self) { site in
                    Text(verbatim: site.label).tag(site)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }
    }
}

/// Where a self-hosted gateway lives.
///
/// The only addresses in the app a reader types, so the only ones that can
/// be wrong. Checked on Save rather than on every keystroke — `https://s`
/// is not a mistake, it is somebody halfway through a word — and a refusal
/// says what the rule is rather than just colouring the box.
struct ServerAddressRow: View {
    let account: AccountKey
    let settings: AppSettings
    @Bindable var fields: AccountEntryFields
    let focus: FocusState<Bool>.Binding

    var body: some View {
        SettingsRow(
            String.localized("Server address"),
            subtitle: fields.serverAddressInvalid
                ? String.localized("That address can't be used. It needs https://, unless the server is on your own network.")
                : String.localized("Your own deployment's address, such as https://gateway.example.com. Pulse asks it for usage and sends nothing else."),
            symbol: "server.rack"
        ) {
            HStack(spacing: 8) {
                TextField("", text: $fields.serverAddress)
                    .focused(focus)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsLayout.controlWidth)
                    .onSubmit { fields.saveServerAddress(for: account) }

                Button(String.localized("Save")) { fields.saveServerAddress(for: account) }
                    .disabled(fields.serverAddress == settings.serverAddress(for: account))
            }
        }
    }
}

/// An API account reports money and no allowance, so the ring has no
/// denominator until one is chosen. Three modes because there are exactly
/// three places one can come from — see `BalanceBasis`.
///
/// **Not "Ring shows".** That is the Panel group's row, which picks the
/// limit the ring follows; two rows of one name on one pane read as one
/// setting shown twice.
struct BalanceBasisRow: View {
    let account: AccountKey
    let settings: AppSettings

    var body: some View {
        SettingsRow(
            String.localized("Ring measures"),
            subtitle: Self.balanceBasisSubtitle(settings.balanceBasis(for: account)),
            symbol: "ruler"
        ) {
            Picker("", selection: Binding(
                get: { settings.balanceBasis(for: account) },
                set: { settings.setBalanceBasis($0, for: account) }
            )) {
                ForEach(BalanceBasis.allCases) { basis in
                    Text(basis.title).tag(basis)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            // Its own width, not `controlWidth`: a frame narrower than the
            // control does not shrink it — it overflows leftwards over the
            // subtitle. Sized to itself, the row makes room and the subtitle
            // wraps instead.
            .fixedSize()
        }
    }

    private static func balanceBasisSubtitle(_ basis: BalanceBasis) -> String {
        switch basis {
        case .sinceTopUp:
            .localized("How much of the balance Pulse last saw you top up to is gone.")
        case .balanceOnly:
            .localized("The money left, with no ring. There is no allowance to measure against.")
        case .budget:
            .localized("How much of the figure you set is gone.")
        }
    }
}

struct BalanceBudgetRow: View {
    let account: AccountKey
    @Bindable var fields: AccountEntryFields

    var body: some View {
        SettingsRow(
            String.localized("Full tank"),
            subtitle: String.localized("What you call a full balance. The ring measures against it."),
            symbol: "fuelpump"
        ) {
            HStack(spacing: 8) {
                TextField("", text: $fields.balanceBudgetText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsLayout.controlWidth - 70)
                    .onSubmit { fields.saveBalanceBudget(for: account) }

                Button(String.localized("Save")) { fields.saveBalanceBudget(for: account) }
            }
        }
    }
}

/// A prepaid balance has no percentage to warn at, so it gets a line of
/// its own: the money, not a fraction of an allowance nobody reports.
struct LowBalanceRow: View {
    let account: AccountKey
    @Bindable var fields: AccountEntryFields

    var body: some View {
        SettingsRow(
            String.localized("Warn below"),
            subtitle: String.localized("Notify once when the balance falls under this. Blank for never."),
            symbol: "bell"
        ) {
            HStack(spacing: 8) {
                TextField("", text: $fields.lowBalance)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsLayout.controlWidth - 70)
                    .onSubmit { fields.saveLowBalance(for: account) }

                Button(String.localized("Save")) { fields.saveLowBalance(for: account) }
            }
            // Greyed out in a build with no bundle, like every other alert
            // control: `UNUserNotificationCenter` raises without one.
            .disabled(!UsageAlerts.isSupported)
        }
    }
}
