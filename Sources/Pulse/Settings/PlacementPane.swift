// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Whether the rail is shown, where it sits, how it tucks away, and the
/// order of the rings on it.
struct PlacementPane: View {
    let settings: AppSettings
    let placement: PanelPlacement

    /// The row a reorder drag is currently over, so it can say so.
    @State private var dropTarget: AccountKey?

    private var positionRow: some View {
        SettingsRow(
            String.localized("Position"),
            subtitle: String.localized("Drag it anywhere; near an edge it snaps on.")
        ) {
            Picker("", selection: Binding(
                get: { placement.dock },
                set: { placement.update(dock: $0) }
            )) {
                Text(localized: "Left").tag(PanelDock.edge(.left))
                Text(localized: "Top").tag(PanelDock.edge(.top))
                Text(localized: "Bottom").tag(PanelDock.edge(.bottom))
                Text(localized: "Free across").tag(PanelDock.floating(.horizontal))
                Text(localized: "Free upright").tag(PanelDock.floating(.vertical))
                Text(localized: "Right").tag(PanelDock.edge(.right))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    String.localized("Show floating panel"),
                    subtitle: String.localized("The usage rail at the edge of the screen.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.isPanelVisible },
                        set: { settings.isPanelVisible = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Hide in full screen"),
                    subtitle: String.localized("Keep the floating panel out of full-screen apps.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.hidesInFullScreen },
                        set: { settings.hidesInFullScreen = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Hide from screenshots"),
                    subtitle: String.localized("Screenshot tools that support it leave the floating panel out. Recordings and screen sharing may still show it.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.hidesFromScreenCapture },
                        set: { settings.hidesFromScreenCapture = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Hide until pointed at"),
                    subtitle: String.localized("Against a screen edge, the rail shrinks to a sliver until you point at it.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.autoCollapse },
                        set: { settings.autoCollapse = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                positionRow

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Snap to screen edges"),
                    subtitle: String.localized("Dragged near an edge, the rail docks to it and turns to run along it. When this is off, dragging only moves the rail and keeps its direction.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.snapsToEdges },
                        set: { settings.snapsToEdges = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Follow the active display"),
                    subtitle: String.localized("With more than one display, the rail moves to the one the pointer is on.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.followsActiveDisplay },
                        set: { settings.followsActiveDisplay = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }

            SettingsGroup(String.localized("Order")) {
                // **Drag, and the arrows as well.** This was arrows only, on
                // the reasoning that four rows is not enough to make a drag
                // worth learning and that an arrow which misses does nothing
                // while a drag which misses does something. The first half of
                // that stopped being true at seventeen providers, plus every
                // added account, when moving the bottom one to the top was
                // already sixteen clicks.
                //
                // The arrows stay rather than being replaced. They are the
                // precise way to move one place, they are the only way that
                // works from the keyboard, and they carry the accessibility
                // labels — drag and drop has none to give.
                //
                // **Only what the rail draws.** Every switched-off provider
                // used to be listed too, marked "Not shown", which with
                // seventy-odd of them buried the few rings being arranged.
                // Something switched on later arrives at the end.
                ForEach(Array(settings.shownAccounts.enumerated()), id: \.element) { index, account in
                    if index > 0 { SettingsRowDivider() }

                    SettingsRow(
                        settings.label(for: account),
                        icon: account.provider.iconResource,
                        iconData: settings.pulseExtension(for: account)?.iconData
                    ) {
                        HStack(spacing: 4) {
                            Button {
                                settings.move(account, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            .accessibilityLabel(String.localized("Move \(settings.label(for: account)) up"))

                            Button {
                                settings.move(account, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == settings.shownAccounts.count - 1)
                            .accessibilityLabel(String.localized("Move \(settings.label(for: account)) down"))
                        }
                        .buttonStyle(.borderless)
                    }
                    // The whole row, not just the text: a drag that only
                    // starts on the label is a drag most people conclude
                    // isn't there.
                    .contentShape(.rect)
                    .background(dropTarget == account ? Color.accentColor.opacity(0.12) : .clear)
                    .draggable(account.id) {
                        // The system's own drag image is the row at full
                        // width, which at 900pt is a slab. This is the two
                        // things being moved: the mark and the name.
                        HStack(spacing: 8) {
                            LobeIconView(provider: account.provider, size: 15,
                                         iconData: settings.pulseExtension(for: account)?.iconData)
                            Text(settings.label(for: account))
                                .font(.system(size: 13))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        dropTarget = nil
                        guard let dragged = ids.first.flatMap(AccountKey.init(id:)),
                              settings.shownAccounts.contains(dragged)
                        else { return false }

                        settings.move(dragged, onto: account)
                        return true
                    } isTargeted: { isTargeted in
                        // Cleared by identity, not unconditionally: the row
                        // being left and the row being entered report in an
                        // order nobody promises, so a bare `nil` on exit can
                        // wipe the highlight the next row has just set.
                        if isTargeted {
                            dropTarget = account
                        } else if dropTarget == account {
                            dropTarget = nil
                        }
                    }
                }

                // Last, and disabled while there is nothing to undo. A drag
                // that went somewhere unintended is easy to make and, at
                // seventeen rows, tedious to walk back by hand.
                SettingsRowDivider()

                SettingsRow(
                    String.localized("Reset order"),
                    subtitle: String.localized("Back to the order Pulse ships with.")
                ) {
                    Button(String.localized("Reset")) { settings.resetOrder() }
                        .disabled(!settings.hasCustomOrder)
                }
            }
        }
    }
}
