// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Every Claude Code conversation whose prompt cache is still alive, soonest
/// to lapse first, each with the time it has left.
///
/// The detailed card names only the soonest; this is where the rest are. Read
/// again every half minute while the pane is open — a directory listing and
/// the tails of the files written in the last hour — and counted down in
/// between, so a conversation that lapses drops off without waiting for a read.
struct PromptCacheSessionsGroup: View {
    let provider: Provider
    @State private var reading: PromptCacheReading?
    /// Whose conversations `reading` holds.
    @State private var readFor: Provider?

    /// A reading to start from, for a preview; the pane reads its own.
    init(provider: Provider, reading: PromptCacheReading? = nil) {
        self.provider = provider
        _reading = State(initialValue: reading)
        _readFor = State(initialValue: reading == nil ? nil : provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup(String.localized("Prompt cache")) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    content(at: context.date)
                }
            }

            Text(String.localized("Read from Claude Code's own records: each reply says whether it cached for an hour or five minutes, and a cache lasts that long from the last request that used it. That is the time if nothing before it has changed — switching model, changing tools or compacting starts a new cache. Subagents keep caches of their own and are not listed."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        // **Keyed by provider.** SwiftUI keeps this view in place when the
        // pane moves to another provider, so a bare `.task` neither restarted
        // nor let go of the reading — Codex's pane, when it had this group,
        // listed Claude Code's conversations.
        .task(id: provider) {
            if readFor != provider { reading = nil }
            while !Task.isCancelled {
                let provider = provider
                let read = await Task.detached(priority: .utility) { PromptCacheReading.read(for: provider) }.value
                // A detached read outlives the task that started it; one that
                // lands after the pane moved to another provider is dropped.
                guard !Task.isCancelled else { return }
                reading = read
                readFor = provider
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let reading = readFor == provider ? reading : nil
        let live = (reading?.live ?? []).filter { $0.lapse.expiresAt > now }
        if reading == nil {
            SettingsRow(String.localized("Reading local records…")) {
                ProgressView().controlSize(.small)
            }
        } else if live.isEmpty {
            SettingsRow(
                String.localized("No conversation is holding a cache"),
                subtitle: lapsedLine(now: now)
            ) { EmptyView() }
        } else {
            ForEach(Array(live.enumerated()), id: \.element.id) { index, session in
                if index > 0 { SettingsRowDivider() }
                SettingsRow(
                    session.displayName,
                    subtitle: subtitle(session)
                ) {
                    Text(verbatim: String.localized("\(PromptCacheLapse.duration(session.lapse.expiresAt.timeIntervalSince(now))) left"))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        // Red in its last five minutes: a message now still
                        // reads the cache; one a little later writes it again.
                        .foregroundStyle(session.lapse.expiresAt.timeIntervalSince(now) <= 300 ? Color.red : Color.primary)
                }
            }
        }
    }

    /// "Pulse · 1 hr cache · Last used 14:02". The project only when the
    /// title is something else.
    private func subtitle(_ session: PromptCacheSession) -> String {
        var parts: [String] = []
        if SessionLabel.namesItself(title: session.title, isReview: false), let project = session.project {
            parts.append(project)
        }
        parts.append(String.localized("\(PromptCacheLapse.duration(session.lapse.lifetime)) cache"))
        parts.append(String.localized("Last used \(Self.time(session.lapse.lastRequest))"))
        return parts.joined(separator: " · ")
    }

    private func lapsedLine(now: Date) -> String? {
        guard let lapsed = reading?.lastLapsed ?? reading?.live.map(\.lapse).max(by: { $0.expiresAt < $1.expiresAt }),
              now.timeIntervalSince(lapsed.expiresAt) < PromptCacheLapse.staleAfter
        else { return nil }
        return String.localized("The latest one's cache lapsed at \(Self.time(lapsed.expiresAt)).")
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(date) ? "jmm" : "MMMdjmm")
        return formatter.string(from: date)
    }
}
