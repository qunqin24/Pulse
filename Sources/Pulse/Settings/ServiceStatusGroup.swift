// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// How the provider says its service is doing, drawn the way its status page
/// draws it: per component, the state now, one bar a day for about ninety
/// days, and the page's uptime figure between "90 days ago" and "Today" — the
/// bars only where the page publishes its days.
///
/// **The provider's word, and said to be.** Pulse does not test the service;
/// the footnote names who reports it, the uptime is the page's own figure,
/// and each page keeps its own colours. Read when the pane opens and every
/// five minutes while it stays open, never once it is closed — nobody is
/// looking at it then. A page that
/// can't be read says so, rather than leaving rows to read as healthy.
struct ServiceStatusGroup: View {
    let page: StatusPage
    /// A reading to show without asking the page: the README's picture, drawn
    /// from made-up rows. Nil in the app.
    var sample: ServiceStatus?

    @State private var status: ServiceStatus?
    @State private var isReading = true
    /// Why the last read came back with nothing (`ResponseLog.failure`).
    @State private var failure: String?
    /// Bumped by Refresh, which reads again at once.
    @State private var refreshes = 0

    init(page: StatusPage, sample: ServiceStatus? = nil) {
        self.page = page
        self.sample = sample
        _status = State(initialValue: sample)
        _isReading = State(initialValue: sample == nil)
    }

    private struct Trigger: Hashable {
        let page: StatusPage
        let refreshes: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup(String.localized("Service status")) {
                if let status {
                    ForEach(Array(status.components.enumerated()), id: \.element.id) { index, component in
                        if index > 0 { SettingsRowDivider() }
                        ServiceStatusRow(component: component, palette: StatusPalette(page))
                    }
                } else if isReading {
                    SettingsRow(String.localized("Checking…")) {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    SettingsRow(String.localized("Couldn't read the status page."), subtitle: failure) { EmptyView() }
                }

                SettingsRowDivider()

                SettingsRow(String.localized("Status page"), subtitle: page.host) {
                    HStack(spacing: 8) {
                        // Reads again now, rather than at the next five-minute
                        // turn; the rows already shown stay until it answers.
                        Button {
                            refreshes += 1
                        } label: {
                            if isReading, status != nil {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(localized: "Refresh")
                            }
                        }
                        .disabled(isReading)

                        Button(String.localized("Open")) {
                            NSWorkspace.shared.open(page.address)
                        }
                    }
                }
            }

            Text(localized: "As \(page.company) reports it on its status page, read when this page opens and every five minutes while it stays open.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        // Read on opening, on Refresh, and again every `checkInterval` while
        // open; leaving the pane cancels it. A later read that fails replaces
        // the rows with "couldn't read" and why, rather than leaving old ones
        // to pass for current.
        .task(id: Trigger(page: page, refreshes: refreshes)) {
            while sample == nil, !Task.isCancelled {
                isReading = true
                let (read, replies) = await ResponseLog.capturing { await ServiceStatus.read(page) }
                guard !Task.isCancelled else { return }
                status = read
                failure = read == nil ? ResponseLog.failure(of: replies) : nil
                isReading = false
                try? await Task.sleep(for: ServiceStatus.checkInterval)
            }
        }
        // Another provider's pane: its own rows, never this one's.
        .onChange(of: page) {
            status = nil
            failure = nil
        }
    }
}

/// One component: its name and state, its days, and the uptime line.
private struct ServiceStatusRow: View {
    let component: ServiceStatus.Component
    let palette: StatusPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(component.name)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
                Text(component.state.title)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.colour(for: component.state))
            }

            if !component.days.isEmpty {
                DayBars(days: component.days, palette: palette)
                    .frame(height: 24)

                HStack(spacing: 8) {
                    // The page's own words: ninety days back, whether it
                    // draws ninety bars or ninety-one; Synthetic's draws thirty.
                    // Bars shorter than a day (OpenCode's three hours) say how
                    // many days they span, and end now.
                    if let hours = component.days.first?.hours {
                        Text(localized: "\(String(component.days.count * hours / 24)) days ago")
                    } else if component.days.count >= 90 {
                        Text(localized: "90 days ago")
                    } else {
                        Text(localized: "\(String(component.days.count)) days ago")
                    }
                    rule
                    if let uptime = component.uptime {
                        Text(localized: "\(Self.percent(uptime)) uptime")
                        rule
                    }
                    if component.days.first?.hours != nil {
                        Text(localized: "Now")
                    } else {
                        Text(localized: "Today")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var rule: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    /// The page's figure as it gives it: up to two decimals, none for 100.
    private static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0...2)).locale(LocalizationSource.locale))
    }
}

/// A bar a day — or a bar a few hours, where the page draws them so —
/// oldest on the left, at the page's own proportions (`barProportions`),
/// stretched across the row.
private struct DayBars: View {
    let days: [ServiceStatus.Day]
    let palette: StatusPalette

    var body: some View {
        // One formatter for all ninety tooltips, made per pass so a language
        // switch still takes effect at once.
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")

        return GeometryReader { geometry in
            let (bar, gap) = palette.barProportions
            let unit = geometry.size.width / max(CGFloat(days.count) * (bar + gap) - gap, 1)
            HStack(spacing: unit * gap) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    RoundedRectangle(cornerRadius: palette.barCornerRadius, style: .continuous)
                        .fill(palette.colour(for: day))
                        .frame(width: unit * bar)
                        .help(Self.tooltip(day, formatter))
                }
            }
        }
    }

    private static func tooltip(_ day: ServiceStatus.Day, _ formatter: DateFormatter) -> String {
        let state = day.state?.title ?? String.localized("No data")
        guard let date = Calendar.current.date(from: day.date) else { return state }
        // A bar shorter than a day says its hours: "Oct 13, 09:00–12:00".
        if let hours = day.hours, let end = Calendar.current.date(byAdding: .hour, value: hours, to: date) {
            let locale = LocalizationSource.locale
            let from = date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(locale))
            let to = end.formatted(.dateTime.hour().minute().locale(locale))
            return "\(from)–\(to) · \(state)"
        }
        return "\(formatter.string(from: date)) · \(state)"
    }
}

/// Each page's own colours where they were taken off it — incident.io's for
/// OpenAI (2026-10-04), Claude's and Cursor's Statuspage themes, Flashcat's
/// for DeepSeek — and otherwise its platform's defaults: Statuspage's stock
/// theme, incident.io's, and a plain set for the rest. A Statuspage page's
/// bars come in its own colours whatever this says (`Day.rgb`).
private struct StatusPalette {
    /// Operational, degraded, partial outage, full outage, maintenance.
    let colours: [UInt32]
    /// Statuspage's bars are square; the others round theirs.
    let barCornerRadius: CGFloat
    /// A bar's width and the gap after it, in the same units: three and two
    /// for ninety days; OpenCode's 56 are seven and two (2026-10-15).
    let barProportions: (CGFloat, CGFloat)
    /// How strongly a bar with no record is drawn. OpenCode's page draws most
    /// of its week that way, barely there (6% white on its dark page); the
    /// others have a few such days at most.
    let noDataOpacity: Double

    init(_ page: StatusPage) {
        if case .openCode = page.feed {
            barProportions = (7, 2)
            noDataOpacity = 0.1
        } else {
            barProportions = (3, 2)
            noDataOpacity = 0.2
        }
        switch (page.host, page.feed) {
        // Its page's own (2026-10-15); it has no maintenance colour.
        case (_, .openCode): colours = [0x3F7A55, 0xF2CF76, 0xF17471, 0xF17471, 0x3B82F6]
        case ("status.openai.com", _): colours = [0x24C19A, 0xFBBF24, 0xF5785C, 0xF87171, 0x60A5FA]
        case ("status.claude.com", _): colours = [0x76AD2A, 0xFAA72A, 0xE86235, 0xE04343, 0x2C84DB]
        case ("status.cursor.com", _): colours = [0x1E8542, 0xF1C40F, 0xB35E14, 0xDE2F1B, 0x207AB6]
        case (_, .statuspage): colours = [0x2FCC66, 0xF1C40F, 0xE67E22, 0xE74C3C, 0x3498DB]
        // incident.io's own; maintenance not seen on OpenAI's page.
        case (_, .incidentIO): colours = [0x24C19A, 0xFBBF24, 0xF5785C, 0xF87171, 0x60A5FA]
        // Tailwind's, as Flashcat draws DeepSeek's.
        default: colours = [0x22C55E, 0xEAB308, 0xF97316, 0xEF4444, 0x3B82F6]
        }
        if case .statuspage = page.feed { barCornerRadius = 0 } else { barCornerRadius = 1.5 }
    }

    func colour(for state: ServiceStatus.State) -> Color {
        switch state {
        case .operational: Self.rgb(colours[0])
        case .degraded: Self.rgb(colours[1])
        case .partialOutage: Self.rgb(colours[2])
        case .fullOutage: Self.rgb(colours[3])
        case .maintenance: Self.rgb(colours[4])
        case .unrecognised: .secondary
        }
    }

    /// The page's own colour when it gave one; otherwise the state's. A day
    /// with no record is drawn faint in both light and dark.
    func colour(for day: ServiceStatus.Day) -> Color {
        if let rgb = day.rgb { return Self.rgb(rgb) }
        guard let state = day.state else { return Color.secondary.opacity(noDataOpacity) }
        return colour(for: state)
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#Preview("Claude") {
    ServiceStatusGroup(page: StatusPage.of(.claudeCode)!)
        .padding(24)
        .frame(width: 560)
}
