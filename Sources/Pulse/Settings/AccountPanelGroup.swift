// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// An account's Panel card: whether it is on the rail, which limit its ring
/// follows, its detailed card, and how its mark and ring are drawn.
struct AccountPanelGroup: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings

    private var provider: Provider { account.provider }

    var body: some View {
        SettingsGroup(String.localized("Panel")) {
            SettingsRow(String.localized("Show in panel"), symbol: "eye") {
                Toggle("", isOn: Binding(
                    get: { settings.isEnabled(account) },
                    set: { settings.setEnabled($0, for: account) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                // The last one standing can't be switched off: an empty
                // rail has nothing to hover and nothing to drag.
                .disabled(settings.isEnabled(account) && settings.enabledAccounts.count == 1)
            }

            SettingsRowDivider()

            ringWindowRow(for: account)

            // Only where there is more than one budget to split. Every
            // other provider reports one pool, and a switch that promises
            // a second ring it can never draw is worse than no switch.
            if provider.splitsByModelGroup {
                SettingsRowDivider()

                splitRow(for: account)

                // One switch per group the reading carries, while split: a
                // group somebody never uses need not cost a ring (#106).
                // Nothing to list before the first reading.
                if settings.isSplit(account) {
                    let groups = RailSlot.modelGroups(of: store.usage(for: account))
                    ForEach(groups, id: \.self) { group in
                        SettingsRowDivider()

                        groupRow(group, of: groups)
                    }
                }
            }

            // Codex's first account only: the count comes from the app
            // server, which reads the login the CLI saved — not an
            // account Pulse signed in to itself.
            if account == AccountKey(.codex) {
                SettingsRowDivider()

                SettingsRow(
                    String.localized("Reset credits on the card"),
                    subtitle: String.localized("How many limit reset credits are left, and when the next one expires. Asks Codex's app server on every refresh."),
                    symbol: "arrow.counterclockwise.circle"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsCodexResetCredits },
                        set: {
                            settings.showsCodexResetCredits = $0
                            store.refreshCodexResetCredits()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            // Qoder's three parts, each spent and lapsing on its own. Off
            // by default: they count the same credits as the total again.
            if account == AccountKey(.qoder) {
                SettingsRowDivider()

                SettingsRow(
                    String.localized("Show each part of the credits"),
                    subtitle: String.localized("Plan credits, a top-up pack and dedicated credits are spent separately. The total can look ample while one of them is nearly gone."),
                    symbol: "chart.pie"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.qoderShowsParts },
                        set: { settings.qoderShowsParts = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRowDivider()

                // On the card only: the rail keeps its percentages.
                SettingsRow(
                    String.localized("Show credit amounts"),
                    subtitle: String.localized("Each row on the card also shows the credits, such as 5,843 / 6,000. The rail keeps its percentages."),
                    symbol: "number"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.qoderShowsAmounts },
                        set: { settings.qoderShowsAmounts = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

            }

            SettingsRowDivider()

            // The history half only where it can appear, and said the way
            // it will: this Mac's records need Token spend, a provider's
            // own statistics do not.
            SettingsRow(
                String.localized("Detailed card"),
                subtitle: Self.detailedCardSubtitle(account.isPrimary ? provider.cardHistory : nil),
                symbol: "list.bullet.rectangle"
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.showsDetailedCard(for: account) },
                    set: { settings.setShowsDetailedCard($0, for: account) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Ring colour"),
                // Which state it is in, said outright. A colour well always
                // shows *a* colour, so on its own it cannot tell "automatic"
                // from "they picked green" — and a greyed-out button next to
                // it reads as unavailable, not as the state you are in.
                subtitle: settings.ringTint(for: account) == nil
                    ? String.localized("Coloured by how much is left.")
                    : String.localized("A colour of your own, whatever the usage."),
                symbol: "paintpalette"
            ) {
                Picker("", selection: Binding(
                    get: { settings.ringTint(for: account) != nil },
                    set: { custom in
                        // Switching on lands on something visibly chosen
                        // rather than on the colour the automatic mode
                        // happened to be showing.
                        settings.setRingTint(custom ? RingTint.suggestions.first : nil, for: account)
                    }
                )) {
                    Text(localized: "Automatic").tag(false)
                    Text(localized: "Custom").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
            }

            // Only when there is a colour to change. Shown otherwise it is
            // a control that contradicts the row above it.
            if let chosen = settings.ringTint(for: account) {
                SettingsRowDivider()

                SettingsRow(
                    String.localized("Colour"),
                    subtitle: chosen.hexString,
                    symbol: "eyedropper"
                ) {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { chosen },
                            set: { settings.setRingTint($0, for: account) }
                        ),
                        // A translucent ring reads as a dim one, and dim
                        // already means "no reading".
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }

            SettingsRowDivider()

            // Credited in the subtitle as well as in About: the character is
            // CX ArtLab's, and the switch is where somebody first meets it.
            SettingsRow(
                String.localized("Robot in the ring"),
                subtitle: String.localized("Replaces the provider's mark and shows what this account is doing. The robot is Agent Robot Avatar by CX ArtLab."),
                symbol: "theatermasks"
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.showsRobot(for: account) },
                    set: { settings.setShowsRobot($0, for: account) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            // Only while the robot is on: choices about something that is
            // not drawn read as settings that do nothing.
            if settings.showsRobot(for: account) {
                robotRows
            }
        }
    }

    @ViewBuilder
    private var robotRows: some View {
        SettingsRowDivider()

        SettingsRow(
            String.localized("Robot colour"),
            subtitle: settings.robotColour(for: account) == nil
                ? String.localized("The provider's own colour. Where it has none, one that differs from neighbouring robots.")
                : String.localized("A colour of your own. The ring keeps its colour."),
            symbol: "paintpalette"
        ) {
            Picker("", selection: Binding(
                get: { settings.robotColour(for: account) != nil },
                set: { custom in
                    // Starts from the colour Automatic would give a lone robot,
                    // so switching to Custom changes nothing until a colour is
                    // picked.
                    let start = RobotAutomatic.inks(for: [provider], custom: [nil])[0].ink
                    settings.setRobotColour(custom ? start.color : nil, for: account)
                }
            )) {
                Text(localized: "Automatic").tag(false)
                Text(localized: "Custom").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }

        if let chosen = settings.robotColour(for: account) {
            SettingsRowDivider()

            SettingsRow(String.localized("Colour"), subtitle: chosen.hexString, symbol: "eyedropper") {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { chosen },
                        set: { settings.setRobotColour($0, for: account) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
            }
        }

        SettingsRowDivider()

        SettingsRow(
            String.localized("Robot personality"),
            subtitle: Self.personalitySubtitle(settings.robotPersonality(for: account)),
            symbol: "face.smiling"
        ) {
            Picker("", selection: Binding(
                get: { settings.robotPersonality(for: account) },
                set: { settings.setRobotPersonality($0, for: account) }
            )) {
                Text(localized: "Automatic").tag(RobotPersonality?.none)
                ForEach(RobotPersonality.allCases) { personality in
                    Text(personality.title).tag(RobotPersonality?.some(personality))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }

        SettingsRowDivider()

        SettingsRow(
            String.localized("Robot shape"),
            subtitle: String.localized("The outline of the robot's head."),
            symbol: "square.on.circle"
        ) {
            Picker("", selection: Binding(
                get: { settings.robotShape(for: account) },
                set: { settings.setRobotShape($0, for: account) }
            )) {
                ForEach(RobotShape.allCases) { shape in
                    Text(shape.title).tag(shape)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }
    }

    /// What the personality does while idle, said for the one chosen.
    static func personalitySubtitle(_ personality: RobotPersonality?) -> String {
        switch personality {
        case nil:
            String.localized("Chosen so that neighbouring robots differ.")
        case .calm:
            String.localized("Glances and blinks slowly, and now and then looks slowly from side to side.")
        case .curious:
            String.localized("Glances about, and now and then narrows its eyes and looks up and down.")
        case .lively:
            String.localized("Glances quickly and often, and now and then opens its eyes wide.")
        }
    }

    /// Which of the provider's limits the rail's ring shows.
    ///
    /// The options are whatever that provider is reporting right now, so the
    /// list changes as limits come and go — a per-model window appears only
    /// once that model has one. A pin that stops matching falls back to the
    /// automatic choice rather than leaving the ring blank.
    private func ringWindowRow(for account: AccountKey) -> some View {
        let usage = store.usage(for: account)

        return SettingsRow(
            String.localized("Ring shows"),
            subtitle: String.localized("Which limit the rail's ring tracks."),
            symbol: "circle.dashed"
        ) {
            Picker("", selection: Binding(
                get: {
                    let pinned = settings.pinnedWindow(for: account)
                    // Show "automatic" when the pin no longer matches anything.
                    return usage.windows.contains { $0.id == pinned } ? pinned : nil
                },
                set: { settings.setPinnedWindow($0, for: account) }
            )) {
                Text(localized: "Highest usage").tag(String?.none)

                ForEach(usage.windows) { window in
                    Text(window.name).tag(String?.some(window.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
            .disabled(usage.windows.isEmpty)
        }
    }

    /// One ring per model group, for the one provider that has more than one.
    ///
    /// Off by default. It costs a slot on the rail, and the rail is the whole
    /// of the panel when it is docked — a user who has not asked for a second
    /// ring should not find the first one narrower for it.
    private func splitRow(for account: AccountKey) -> some View {
        SettingsRow(
            String.localized("A ring for each model group"),
            subtitle: String.localized("Antigravity's model groups draw on separate allowances. One ring can only follow the busiest of them."),
            symbol: "circle.grid.2x1"
        ) {
            Toggle("", isOn: Binding(
                get: { settings.isSplit(account) },
                set: { settings.setSplit($0, for: account) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    /// The last group shown cannot be switched off: with no ring the account
    /// would be gone from the rail. Turning the split off is the way to one.
    private func groupRow(_ group: String, of groups: [String]) -> some View {
        let shows = settings.showsModelGroup(group, for: account)
        let shownCount = groups.filter { settings.showsModelGroup($0, for: account) }.count
        return SettingsRow(
            String.localized("Ring for \(group)"),
            subtitle: shows
                ? String.localized("Shown on the panel.")
                : String.localized("Not shown on the panel."),
            symbol: "circle.dashed"
        ) {
            Toggle("", isOn: Binding(
                get: { shows },
                set: { settings.setShowsModelGroup($0, group, known: groups, for: account) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(shows && shownCount <= 1)
        }
    }

    static func detailedCardSubtitle(_ history: CardHistorySource?) -> String {
        switch history {
        case nil:
            String.localized("Adds the plan and when the figures were read.")
        case .accountStatistics, .accountLogs:
            String.localized("Adds the plan, when the figures were read and the account's usage over the last month.")
        case .transcripts, .agents:
            String.localized("Adds the plan, when the figures were read and, with Token spend on, this Mac's recent activity.")
        }
    }
}
