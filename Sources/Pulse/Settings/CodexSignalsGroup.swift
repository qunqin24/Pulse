// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Signs in this Mac's Codex sessions that a model gave less than it was
/// asked for: how often reasoning stopped on the 518·n − 2 lattice, and
/// settings that changed under a session without the user changing them
/// (`CodexSignals`).
///
/// **Signs, and said to be.** Nothing here can see which model the server ran
/// — Codex never writes that down — so the copy says "signs", the footnote
/// says what is and is not known, and a model with too few long replies says
/// so rather than reading as healthy.
struct CodexSignalsGroup: View {
    enum Span: String, CaseIterable, Identifiable {
        case month, quarter, all

        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .month: 30
            case .quarter: 90
            case .all: nil
            }
        }

        var title: String {
            switch self {
            case .month: String.localized("Last 30 days")
            case .quarter: String.localized("Last 90 days")
            case .all: String.localized("All sessions")
            }
        }
    }

    @State private var span: Span = .month
    @State private var signals: CodexSignals?
    @State private var readFor: Span?

    /// The most recent changes listed; the rest are counted.
    private static let listed = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup(String.localized("Signs of a weaker model")) {
                SettingsRow(String.localized("Period")) {
                    Picker(String.localized("Period"), selection: $span) {
                        ForEach(Span.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            if let signals, readFor == span {
                truncation(signals)
                changes(signals)
            } else {
                SettingsGroup(String.localized("Reasoning stopped at fixed points")) {
                    SettingsRow(String.localized("Reading local records…")) {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            // Four short lines rather than one paragraph: each answers one
            // question a reader has about the groups above.
            VStack(alignment: .leading, spacing: 4) {
                Text(localized: "Read from this Mac's Codex records; nothing is sent.")
                Text(localized: "Reasoning stopped at fixed points: the reasoning ended at exactly 516, 1,034, 1,552… tokens. The cause has not been published, and each model has its own usual share, so the share alone does not show that a model was weakened.")
                Text(localized: "Settings quietly lowered: a turn ran on a worse model or lower reasoning than you chose, without you changing anything.")
                Text(localized: "These are signs, not proof: Codex doesn't record which model the server actually used.")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        }
        .task(id: span) {
            let since = span.days.map { Date().addingTimeInterval(-Double($0) * 86_400) }
            let read = await CodexSignalReader.shared.read(since: since)
            guard !Task.isCancelled else { return }
            signals = read
            readFor = span
        }
    }

    // MARK: - Reasoning stopped at fixed points

    @ViewBuilder
    private func truncation(_ signals: CodexSignals) -> some View {
        SettingsGroup(String.localized("Reasoning stopped at fixed points")) {
            if signals.truncation.isEmpty {
                SettingsRow(String.localized("No Codex replies with reasoning in this period")) { EmptyView() }
            } else {
                ForEach(Array(signals.truncation.enumerated()), id: \.element.id) { index, model in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(model.model, subtitle: Self.detail(model)) {
                        verdict(model)
                    }
                }
            }
        }
    }

    /// "126 of 279 long replies stopped at a fixed point · 2,827 replies in all".
    private static func detail(_ model: CodexSignals.Truncation) -> String {
        let replies = String.localized("\(count(model.responses)) replies in all")
        guard model.reachedLattice > 0 else { return replies }
        let stopped = String.localized("\(count(model.onLattice)) of \(count(model.reachedLattice)) long replies stopped at a fixed point")
        return "\(stopped) · \(replies)"
    }

    /// The share as a figure and nothing more: what a stop on the lattice
    /// means is not known, so no share is called normal or weakened.
    @ViewBuilder
    private func verdict(_ model: CodexSignals.Truncation) -> some View {
        if !model.isMeasurable {
            Text(localized: "Too few to tell")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            Text(verbatim: Self.percent(model.share ?? 0))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
    }

    // MARK: - Settings quietly lowered

    @ViewBuilder
    private func changes(_ signals: CodexSignals) -> some View {
        SettingsGroup(String.localized("Settings quietly lowered")) {
            if signals.changes.isEmpty {
                SettingsRow(String.localized("None found"), subtitle: Self.checked(signals, clean: true)) { EmptyView() }
            } else {
                ForEach(Array(signals.changes.prefix(Self.listed).enumerated()), id: \.element.id) { index, change in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(Self.title(change), subtitle: Self.time(change.date)) { EmptyView() }
                }
                if signals.changes.count > Self.listed {
                    SettingsRowDivider()
                    SettingsRow(
                        String.localized("\(Self.count(signals.changes.count - Self.listed)) more"),
                        subtitle: Self.checked(signals, clean: false)
                    ) { EmptyView() }
                }
            }
        }
    }

    private static func title(_ change: CodexSignals.Change) -> String {
        switch change.kind {
        case .model(let asked, let ran):
            String.localized("Model: \(asked) swapped for \(ran)")
        case .effort(let asked, let ran):
            String.localized("Reasoning: \(asked) lowered to \(ran)")
        }
    }

    /// How many sessions were looked at — and, when nothing was found, that
    /// nothing was changed in them — and how many could not be: Codex before
    /// 0.144 writes down none of the user's own changes, and Codex's own
    /// helpers run on models it picks.
    private static func checked(_ signals: CodexSignals, clean: Bool) -> String {
        let judged = clean
            ? String.localized("Checked \(count(signals.judgedSessions)) sessions: the model and reasoning you chose were never changed.")
            : String.localized("Checked \(count(signals.judgedSessions)) sessions.")
        let older = signals.sessions - signals.judgedSessions
        guard older > 0 else { return judged }
        return judged + " " + String.localized("\(count(older)) other sessions can't be checked: older than Codex 0.144, or run by Codex itself.")
    }

    // MARK: - Formatting

    private static func count(_ value: Int) -> String {
        value.formatted(.number.locale(LocalizationSource.locale))
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)).locale(LocalizationSource.locale))
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMdjmm")
        return formatter.string(from: date)
    }
}
