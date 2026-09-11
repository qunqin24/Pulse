import AppKit
import SwiftUI

struct ConnectionDiagnosticsView: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings
    let isSigningIn: Bool
    let repairMessage: String?
    let repair: (ConnectionRemedy) -> Void

    @State private var copied = false

    private var reading: ProviderUsage { store.usage(for: account) }
    private var diagnostic: ConnectionDiagnostic? { store.diagnostics[account.id] }
    private var reason: ProviderUsage.Unavailability? {
        if case .unavailable(let reason) = diagnostic?.state ?? reading.state { return reason }
        return diagnostic?.attempts.compactMap { attempt in
            if case .unavailable(let reason) = attempt.state { return reason }
            return nil
        }.first
    }

    var body: some View {
        SettingsGroup(String.localized("Connection diagnostics")) {
            SettingsRow(
                String.localized("Latest check"),
                subtitle: diagnostic.map { ConnectionDiagnostic.message($0.state) }
                    ?? String.localized("No completed check since launch.")
            ) {
                Button(String.localized("Retry")) { store.refresh(account) }
                    .disabled(store.isRefreshing)
            }

            SettingsRowDivider()
            SettingsRow(String.localized("Checked at")) {
                timestamp(diagnostic?.checkedAt)
            }

            SettingsRowDivider()
            SettingsRow(String.localized("Last successful reading")) {
                timestamp(diagnostic?.lastSuccessfulReadingAt ?? reading.observedAt)
            }

            SettingsRowDivider()
            SettingsRow(
                String.localized("Displayed figures"),
                subtitle: reading.isCached
                    ? String.localized("Showing a saved reading; its original source is retained.")
                    : nil
            ) {
                Text(reading.origin?.title ?? String.localized("Source not recorded"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if let diagnostic, !diagnostic.attempts.isEmpty {
                SettingsRowDivider()
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(diagnostic.attempts.enumerated()), id: \.offset) { _, attempt in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(attempt.route.title).font(.system(size: 12, weight: .medium))
                                Text(attempt.message)
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    Text(localized: "Route checks")
                        .font(.system(size: 13))
                }
                .padding(14)
            }

            if let reason, let remedy = ConnectionRemedy.forReason(reason, account: account), remedy != .retry {
                SettingsRowDivider()
                SettingsRow(String.localized("Next step"), subtitle: repairMessage ?? reason.message) {
                    Button(remedy.title) { repair(remedy) }
                        .disabled(isSigningIn)
                }
            } else if let repairMessage {
                SettingsRowDivider()
                SettingsRow(repairMessage) { EmptyView() }
            }

            SettingsRowDivider()
            SettingsRow(
                String.localized("Share diagnostics"),
                subtitle: String.localized("Only source, status and timestamps; no account details or secrets.")
            ) {
                Button(copied ? String.localized("Copied") : String.localized("Copy diagnostics"), action: copyReport)
            }

            SettingsRowDivider()
            SettingsRow(String.localized("Setup help")) {
                Link(destination: ConnectionRemedy.helpURL(for: account.provider)) {
                    Text(localized: "Open")
                }
            }
        }
    }

    private func timestamp(_ date: Date?) -> some View {
        Text(date.map {
            $0.formatted(.dateTime.year().month().day().hour().minute().second().locale(LocalizationSource.locale))
        } ?? String.localized("Not recorded"))
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    private func copyReport() {
        let report = ConnectionDiagnostic.report(
            account: account, preference: settings.source(for: account), displayed: reading,
            diagnostic: diagnostic,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
            now: Date()
        )
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(report, forType: .string)
    }
}
