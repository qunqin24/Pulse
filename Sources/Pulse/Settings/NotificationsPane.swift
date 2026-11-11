// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

struct NotificationsPane: View {
    let store: UsageStore
    let settings: AppSettings
    let alerts: UsageAlerts

    /// What the last test came to, said in the row until the pane closes.
    @State private var testOutcome: UsageAlerts.TestOutcome?
    @State private var isSendingTest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    String.localized("Warn at"),
                    subtitle: alertsSubtitle,
                    symbol: "exclamationmark.triangle"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.alertThreshold },
                        set: {
                            settings.alertThreshold = $0
                            Task {
                                if await alerts.requestAuthorizationIfNeeded() {
                                    store.reconsiderAlerts()
                                }
                            }
                        }
                    )) {
                        ForEach(AlertThreshold.allCases) { threshold in
                            Text(threshold.title).tag(threshold)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!UsageAlerts.isSupported)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a limit comes back"),
                    subtitle: String.localized("Only for one you were warned about."),
                    symbol: "checkmark.circle"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnReset },
                        set: {
                            settings.alertsOnReset = $0
                            Task {
                                if await alerts.requestAuthorizationIfNeeded() {
                                    store.reconsiderAlerts()
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    // Nothing to fire about: a reset is only announced for a
                    // window that was mentioned on the way up.
                    .disabled(!UsageAlerts.isSupported || settings.alertThreshold == .off)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a reading stops arriving"),
                    subtitle: String.localized("After several failed checks in a row, once per outage."),
                    symbol: "wifi.exclamationmark"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnFailure },
                        set: {
                            settings.alertsOnFailure = $0
                            Task {
                                if await alerts.requestAuthorizationIfNeeded() {
                                    store.reconsiderAlerts()
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!UsageAlerts.isSupported)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a service is down"),
                    subtitle: String.localized("From each provider's own status page, for the providers you have switched on and only about what their accounts run on."),
                    symbol: "exclamationmark.icloud"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnOutage },
                        set: {
                            settings.alertsOnOutage = $0
                            // The status pages, not the readings: an outage
                            // already under way is said now, and switching off
                            // forgets what was said. `reconsiderAlerts` would
                            // refetch every provider for nothing.
                            Task {
                                _ = await alerts.requestAuthorizationIfNeeded()
                                alerts.checkServices()
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!UsageAlerts.isSupported)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a recap is ready"),
                    subtitle: String.localized("Last month's recap, at the start of the month. Needs Token spend reading."),
                    symbol: "calendar"
                ) {
                    // The request and the first check follow from the setting
                    // itself (`AppSettings.onRecapAlertChange`).
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnRecap },
                        set: { settings.alertsOnRecap = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    // The month is only known from records Pulse has read — but
                    // a switch that is on can always be turned off, whatever
                    // Token spend reading says.
                    .disabled(!UsageAlerts.isSupported || (!settings.readsTokenSpend && !settings.alertsOnRecap))
                }
            }

            SettingsGroup {
                SettingsRow(
                    String.localized("Test notification"),
                    subtitle: testSubtitle,
                    symbol: "bell"
                ) {
                    Button(String.localized("Send")) {
                        isSendingTest = true
                        Task {
                            testOutcome = await alerts.sendTest()
                            isSendingTest = false
                        }
                    }
                    .disabled(!UsageAlerts.isSupported || isSendingTest)
                }
            }
        }
    }

    /// What the test row says: what the button does, or what came of it when
    /// that is not a banner on screen.
    private var testSubtitle: String {
        guard UsageAlerts.isSupported else { return .localized("Notifications need the bundled app.") }
        switch testOutcome {
        case .denied: return .localized("Turned off for Pulse in System Settings › Notifications.")
        case .undecided: return .localized("Pulse has not been allowed to post notifications yet. Press Send again to be asked.")
        case .sent: return .localized("Sent. If nothing appeared, check Focus and System Settings › Notifications.")
        case .unsupported: return .localized("Notifications need the bundled app.")
        case nil: return .localized("Sends one now, so you can see that notifications reach you.")
        }
    }

    /// Says what the *system* thinks, which is the half the switches cannot
    /// know. A switch left on while macOS is dropping everything Pulse posts is
    /// a setting that lies, and permission can be withdrawn in System Settings
    /// long after it was given.
    private var alertsSubtitle: String {
        guard UsageAlerts.isSupported else {
            // The `swift run` case: a bare executable has no bundle, and the
            // notification centre raises rather than refusing politely.
            return .localized("Notifications need the bundled app.")
        }

        if settings.wantsAlerts, alerts.authorization == .denied {
            return .localized("Turned off for Pulse in System Settings › Notifications.")
        }
        return .localized("Notify when a limit passes this, and again when it is spent.")
    }
}
