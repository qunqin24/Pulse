// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
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
    @State private var showsRouteChecks = false
    @State private var showsReplies = false
    @State private var copiedReplies = false

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
                    .disabled(store.isRefreshing || !settings.isEnabled(account))
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
                DisclosureGroup(isExpanded: $showsRouteChecks) {
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
                    // On macOS only the chevron toggles a disclosure group;
                    // the whole row has to, or clicking the title does nothing.
                    Text(localized: "Route checks")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { showsRouteChecks.toggle() }
                        }
                }
                .padding(14)
            }

            if let diagnostic, !diagnostic.responses.isEmpty {
                SettingsRowDivider()
                DisclosureGroup(isExpanded: $showsReplies) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(localized: "Credentials are hidden. A reply can show an email or balance, so it stays out of shared diagnostics.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(diagnostic.responses.enumerated()), id: \.offset) { _, entry in
                            ServerReplyView(entry: entry)
                        }
                        Button(copiedReplies ? String.localized("Copied") : String.localized("Copy replies")) {
                            NSPasteboard.general.clearContents()
                            copiedReplies = NSPasteboard.general.setString(Self.repliesText(diagnostic.responses), forType: .string)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    Text(localized: "Server replies")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { showsReplies.toggle() }
                        }
                }
                .padding(14)
                .onChange(of: diagnostic.checkedAt) { copiedReplies = false }
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

    /// The replies as plain text, for pasting into an issue by someone who
    /// has read them first.
    static func repliesText(_ entries: [ResponseLog.Entry]) -> String {
        let stamp = ISO8601DateFormatter()
        return entries.map { entry in
            let status = entry.status.map { "HTTP \($0)" } ?? "no reply"
            let type = entry.contentType.map { " · \($0)" } ?? ""
            return "\(stamp.string(from: entry.at)) \(entry.method) \(entry.address)\n\(status)\(type)\n\(entry.body)"
        }.joined(separator: "\n\n")
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

/// One request and what came back: the status, the address, and the body as
/// the server sent it (redacted, `ResponseLog`), selectable.
private struct ServerReplyView: View {
    let entry: ResponseLog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: entry.status.map { "HTTP \($0)" } ?? String.localized("No reply"))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(statusColour)
                Text(verbatim: "\(entry.method) \(entry.address)")
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Text(verbatim: details)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if !entry.body.isEmpty {
                ScrollView {
                    Text(verbatim: entry.body)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.5)))
            }
        }
    }

    private var statusColour: Color {
        guard let status = entry.status else { return .red }
        return (200..<300).contains(status) ? .green : (300..<400).contains(status) ? .secondary : .orange
    }

    private var details: String {
        let time = entry.at.formatted(.dateTime.hour().minute().second().locale(LocalizationSource.locale))
        let size = Int64(entry.byteCount).formatted(.byteCount(style: .file).locale(LocalizationSource.locale))
        return [time, entry.contentType, entry.status == nil ? nil : size].compactMap { $0 }.joined(separator: " · ")
    }
}
