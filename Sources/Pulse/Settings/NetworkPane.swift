// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// How often Pulse asks, and through what.
struct NetworkPane: View {
    let store: UsageStore
    let settings: AppSettings

    /// Manual proxy fields are committed as one valid endpoint rather than on
    /// every keystroke.
    @State private var proxyHost = ""
    @State private var proxyPort = ""
    @State private var proxyHostInvalid = false
    @State private var proxyPortInvalid = false
    private enum ProxyField: Hashable { case host, port }
    /// macOS's proxy switch, read again every few seconds while the pane is
    /// open: it changes in another app, which tells Pulse nothing.
    @State private var systemProxyOn = SystemProxy.isOn
    @FocusState private var proxyField: ProxyField?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Refresh")) {
                SettingsRow(
                    String.localized("Check every"),
                    subtitle: refreshSubtitle,
                    symbol: "arrow.clockwise"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.refreshInterval },
                        set: { settings.refreshInterval = $0 }
                    )) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            }

            SettingsGroup(String.localized("Network")) {
                SettingsRow(
                    String.localized("Proxy"),
                    subtitle: proxySubtitle,
                    symbol: "network"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.networkProxy.mode },
                        set: { mode in
                            var proxy = settings.networkProxy
                            proxy.mode = mode
                            settings.networkProxy = proxy
                            if mode != .manual {
                                proxyHostInvalid = false
                                proxyPortInvalid = false
                            }
                        }
                    )) {
                        ForEach(NetworkProxyMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }

                if settings.networkProxy.mode == .manual {
                    SettingsRowDivider()

                    SettingsRow(String.localized("Type"), symbol: "tag") {
                        Picker("", selection: Binding(
                            get: { settings.networkProxy.kind },
                            set: { kind in
                                var proxy = settings.networkProxy
                                proxy.kind = kind
                                settings.networkProxy = proxy
                            }
                        )) {
                            ForEach(NetworkProxyKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Host"),
                        subtitle: proxyHostInvalid
                            ? String.localized("Enter a host.")
                            : String.localized("The proxy server's name or address."),
                        symbol: "server.rack"
                    ) {
                        TextField("", text: $proxyHost, prompt: Text(verbatim: "127.0.0.1"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: SettingsLayout.controlWidth)
                            .focused($proxyField, equals: .host)
                            .onSubmit { saveManualProxy() }
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Port"),
                        subtitle: proxyPortInvalid
                            ? String.localized("Enter a whole number from 1 to 65535.")
                            : String.localized("A number from 1 to 65535."),
                        symbol: "number"
                    ) {
                        TextField("", text: $proxyPort, prompt: Text(verbatim: "7897"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: SettingsLayout.controlWidth)
                            .focused($proxyField, equals: .port)
                            .onSubmit { saveManualProxy() }
                    }
                }
            }
        }
        .onAppear {
            proxyHost = settings.networkProxy.host
            proxyPort = settings.networkProxy.port.map(String.init) ?? ""
            proxyHostInvalid = false
            proxyPortInvalid = false
        }
        .task {
            while !Task.isCancelled {
                let on = SystemProxy.isOn
                if systemProxyOn != on { systemProxyOn = on }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .onChange(of: proxyField) { previous, current in
            guard previous != nil, previous != current else { return }
            saveManualProxy()
        }
    }

    /// What the chosen mode does — or, for "System Proxy Only" with nothing
    /// switched on in macOS, that Pulse is not connecting at all, which is
    /// otherwise only visible as every ring going stale.
    private var proxySubtitle: String {
        let mode = settings.networkProxy.mode
        if mode == .systemRequired, !systemProxyOn {
            return .localized("macOS has no proxy switched on, so Pulse isn't connecting.")
        }
        return mode.explanation
    }

    /// Host and port become one setting only after both fields are valid. The
    /// text remains as typed on refusal so the row can explain what to fix.
    private func saveManualProxy() {
        let host = NetworkProxySettings.validHost(proxyHost)
        let port = NetworkProxySettings.validPort(proxyPort)
        proxyHostInvalid = host == nil
        proxyPortInvalid = port == nil
        guard let host, let port else { return }

        var proxy = settings.networkProxy
        proxy.host = host
        proxy.port = port
        settings.networkProxy = proxy
        proxyHost = host
        proxyPort = String(port)
    }

    /// On automatic the cadence is decided at each tick, so the setting says
    /// what it has settled on — otherwise the choice is a black box that seems
    /// to do nothing.
    private var refreshSubtitle: String {
        guard settings.refreshInterval == .automatic else {
            return .localized("How often to fetch new figures.")
        }

        let minutes = Int((store.currentInterval / 60).rounded())
        return .localized("2 to 30 minutes as needed. Now: \("\(minutes)") minutes.")
    }
}
