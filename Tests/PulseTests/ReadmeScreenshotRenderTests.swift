import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// The README's pictures, drawn from the current code instead of captured from
/// a running app, so they can be made again whenever the panel changes.
///
///     PULSE_README_SHOTS=/tmp/readme-shots swift test --filter ReadmeScreenshotRenderTests
///
/// writes, in English, at 2×, to `<folder>`:
///
/// - `panel.png`: the side rail with Cursor's card open.
/// - `glass.png`: the same on Liquid Glass, over a backdrop drawn here.
/// - `rings.png`: the ring styles on the dark rail, each captioned.
/// - `detailed-card.png`: Codex's compact and detailed cards, the detailed one
///   with the burn-rate forecast.
/// - `menu-bar.png`: three menu bar readings on a drawn strip (a mock-up) and
///   the menu dashboard open under them.
/// - `placement.png`: the rail docked across the top and the sliver it folds to.
/// - `recap.png`: the week, month and year recap posters.
/// - `status-diagnostics.png`: Settings' Service status and Connection
///   diagnostics groups, from made-up rows.
///
/// Copy them over the files of the same name in `Docs/images/` after reading
/// them. The glass is drawn by the window server, so that one is a real window
/// read back (`WindowCapture`) and needs macOS 26; so are the pictures that
/// say `live` below. The figures are made up; dates follow the day the test
/// runs. Nothing here checks a pixel, and without the variable the test is
/// skipped. `PULSE_README_ONLY=rings,recap` draws just those.
@MainActor
@Suite("README screenshots", .serialized)
struct ReadmeScreenshotRenderTests {
    nonisolated(unsafe) private static var retained: [AnyObject] = []
    static let backdrop = Color(red: 0.965, green: 0.965, blue: 0.965)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_README_SHOTS"] != nil))
    func render() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_README_SHOTS"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }
        // `PULSE_README_ONLY=rings,detailed-card` draws just those, while one
        // of them is being worked on.
        let only = ProcessInfo.processInfo.environment["PULSE_README_ONLY"]?.split(separator: ",").map(String.init)
        func wanted(_ name: String) -> Bool { only?.contains(name) ?? true }

        if wanted("panel") { try write(panelShot(), to: folder.appendingPathComponent("panel.png"), scale: 2) }
        if wanted("glass") { try WindowCapture.write(glassShot(), to: folder.appendingPathComponent("glass.png")) }
        if wanted("rings") {
            try await ringsShot(to: folder.appendingPathComponent("rings.png"))
        }
        // The pictures read back from a window go last: a window left over
        // from one crashed the drawing of the next that was not.
        if wanted("placement") {
            try await writeHosted(placementShot(), to: folder.appendingPathComponent("placement.png"), scale: 2,
                                  settle: 0.6)
        }
        if wanted("recap") { try recapShot(to: folder.appendingPathComponent("recap.png")) }
        if wanted("menu-bar") { try await menuBarShot(to: folder.appendingPathComponent("menu-bar.png")) }
        if wanted("status-diagnostics") {
            try await statusDiagnosticsShot(to: folder.appendingPathComponent("status-diagnostics.png"))
        }
        if wanted("detailed-card") {
            PanelMetrics.showDetailedCard(true)
            PanelMetrics.showForecast(true)
            defer {
                PanelMetrics.showDetailedCard(false)
                PanelMetrics.showForecast(false)
            }
            try await writeHosted(detailedShot(), to: folder.appendingPathComponent("detailed-card.png"), scale: 2,
                                  settle: 1.0, live: true)
        }
    }

    // MARK: Panel

    private static func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func entry(_ provider: Provider, _ windows: [UsageWindow], plan: String? = nil) -> RailEntry {
        let usage = ProviderUsage(
            account: AccountKey(provider), windows: windows,
            observedAt: Date().addingTimeInterval(-180), state: .live, plan: plan, creditBalance: nil
        )
        return RailEntry(usage: usage, headline: windows.first, slot: RailSlot(AccountKey(provider)),
                         title: provider.displayName)
    }

    private func window(_ id: String, _ kind: UsageWindow.Kind, _ used: Double, seconds: Int,
                        resets: Date?, scope: String? = nil, reportsLength: Bool = true) -> UsageWindow {
        UsageWindow(id: id, kind: kind, scope: scope, usedFraction: used, windowSeconds: seconds,
                    resetsAt: resets, reportsLength: reportsLength)
    }

    private var railEntries: [RailEntry] {
        let cursorReset = Self.date(11, 30, 13, 33)
        return [
            entry(.claudeCode, [window("fiveHour", .fiveHour, 0.06, seconds: 18_000, resets: Date().addingTimeInterval(4 * 3600))]),
            entry(.codex, [window("primary", .fiveHour, 0.89, seconds: 18_000, resets: Date().addingTimeInterval(52 * 60))]),
            entry(.cursor, [
                window("cursorModels", .monthly, 0.02, seconds: 30 * 86_400, resets: cursorReset,
                       scope: "Cursor Models", reportsLength: false),
                window("otherModels", .monthly, 0.0, seconds: 30 * 86_400, resets: cursorReset,
                       scope: "Other Models", reportsLength: false),
            ]),
            entry(.devin, [window("daily", .daily, 0.01, seconds: 86_400, resets: Date().addingTimeInterval(9 * 3600))]),
            entry(.openCodeGo, [window("monthly", .monthly, 0.22, seconds: 30 * 86_400, resets: Self.date(11, 21, 0, 0))]),
            entry(.grok, [window("weekly", .weekly, 0.15, seconds: 7 * 86_400, resets: Self.date(11, 6, 18, 0))]),
        ]
    }

    private func panelShot() -> some View {
        let entries = railEntries
        let cursor = entries[2]
        let rail = DockLayout.size(for: entries.count, on: .vertical, docked: false)
        let ringY = DockLayout.firstRingAlong(docked: false, on: .vertical)
            + 2 * DockLayout.ringStep(on: .vertical, docked: false)
        let cardHeight = measure(card(cursor.usage, pointer: 80, detailed: false)).height
        let pointer = cardHeight / 2
        let cardSize = measure(card(cursor.usage, pointer: pointer, detailed: false))

        let marginX: CGFloat = 44
        let marginY: CGFloat = 36
        let width = marginX * 2 + cardSize.width + DetailCardLayout.horizontalGap + rail.width
        let height = marginY * 2 + rail.height

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Self.backdrop)
            card(cursor.usage, pointer: pointer, detailed: false)
                .offset(x: marginX, y: marginY + ringY - pointer)
            UsageDockView(
                entries: entries,
                selectedSlot: cursor.slot.id,
                edge: .right,
                isDocked: false,
                onEnter: { _ in }
            )
            .fixedSize()
            .offset(x: marginX + cardSize.width + DetailCardLayout.horizontalGap, y: marginY)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .foregroundStyle(.primary)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Glass

    /// The panel shot on Liquid Glass at the default transparency, set as
    /// `FloatingUsagePanelContent` sets it, over a backdrop for the glass to
    /// bend: soft colour fields and a few hard edges, drawn here.
    private func glassShot() -> some View {
        let entries = railEntries
        let cursor = entries[2]
        let transparency = PanelGlass.defaultTransparency
        let rail = DockLayout.size(for: entries.count, on: .vertical, docked: false)
        let ringY = DockLayout.firstRingAlong(docked: false, on: .vertical)
            + 2 * DockLayout.ringStep(on: .vertical, docked: false)
        let cardHeight = measure(card(cursor.usage, pointer: 80, detailed: false, glass: true)).height
        let pointer = cardHeight / 2
        let cardSize = measure(card(cursor.usage, pointer: pointer, detailed: false, glass: true))

        let marginX: CGFloat = 44
        let marginY: CGFloat = 36
        let width = marginX * 2 + cardSize.width + DetailCardLayout.horizontalGap + rail.width
        let height = marginY * 2 + rail.height

        return ZStack(alignment: .topLeading) {
            Self.glassBackdrop
            Group {
                card(cursor.usage, pointer: pointer, detailed: false, glass: true)
                    .offset(x: marginX, y: marginY + ringY - pointer)
                UsageDockView(
                    entries: entries,
                    selectedSlot: cursor.slot.id,
                    edge: .right,
                    isDocked: false,
                    usesGlass: true,
                    onEnter: { _ in }
                )
                .fixedSize()
                .offset(x: marginX + cardSize.width + DetailCardLayout.horizontalGap, y: marginY)
            }
            .foregroundStyle(PanelGlass.ink(transparency: transparency).map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
            .environment(\.colorScheme, PanelGlass.scheme(transparency: transparency))
            .environment(\.glassTransparency, transparency)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// Warm and cool fields with a few crisp bands across them, so the glass
    /// has colour to carry and edges to bend.
    private static var glassBackdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.52), Color(red: 0.47, green: 0.20, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 1.0, green: 0.55, blue: 0.30)).frame(width: 360).blur(radius: 60).offset(x: 140, y: -170)
            Circle().fill(Color(red: 0.20, green: 0.80, blue: 0.85)).frame(width: 300).blur(radius: 55).offset(x: -150, y: 40)
            Circle().fill(Color(red: 0.95, green: 0.35, blue: 0.62)).frame(width: 320).blur(radius: 60).offset(x: 120, y: 250)
            VStack(spacing: 34) {
                ForEach(0..<9) { band in
                    Capsule().fill(.white.opacity(band.isMultiple(of: 2) ? 0.22 : 0.10)).frame(height: 10)
                        .rotationEffect(.degrees(-18))
                }
            }
            .frame(width: 900)
        }
    }

    private func card(_ usage: ProviderUsage, pointer: CGFloat, detailed: Bool,
                      spend: UsageDetailCard.Spend? = nil, glass: Bool = false,
                      forecast: Bool = false) -> some View {
        UsageDetailCard(usesGlass: glass, usage: usage, edge: .right, showsForecast: forecast,
                        parts: detailed ? CardPart.detailed : [], spend: spend, pointerCenter: pointer)
            .fixedSize()
            .foregroundStyle(.primary)
            .environment(\.colorScheme, .dark)
    }

    private func measure<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        return host.fittingSize
    }

    // MARK: Detailed

    /// Two limits, so the forecast has both answers to give: the five-hour
    /// window 3.5 hours in and 85% gone runs out in about half an hour, the
    /// week 46% gone and four days in is on course to last.
    private func codexUsage(now: Date, reset: Date) -> ProviderUsage {
        ProviderUsage(
            account: AccountKey(.codex),
            windows: [
                window("primary", .fiveHour, 0.85, seconds: 18_000, resets: now.addingTimeInterval(90 * 60)),
                window("secondary", .weekly, 0.46, seconds: 7 * 86_400, resets: reset),
            ],
            observedAt: now.addingTimeInterval(-3 * 60 - 10), state: .live, plan: "Pro", creditBalance: nil
        )
    }

    /// 31 days of Codex work, today last. Weekdays busy, weekends light.
    private func ledger(now: Date) -> UsageLedger {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // Millions of tokens per day, oldest first; the last is today.
        let millions: [Double] = [
            18, 31, 36, 9, 0, 41, 52, 57, 33, 14, 3, 66, 48, 37,
            12, 0, 22, 54, 71, 79, 49, 38, 30, 46, 63, 73, 50, 29, 17, 0, 97,
        ]
        var days: [LedgerDay] = []
        var slots: [UsageLedger.Slot] = []
        for (index, amount) in millions.enumerated() {
            let date = calendar.date(byAdding: .day, value: index - (millions.count - 1), to: today)!
            let tokens = Int(amount * 1_000_000)
            // About $0.42 a million at API prices with a ~91% cache hit rate.
            let cost = amount * 0.42
            let cacheRead = Int(Double(tokens) * 0.88)
            let output = Int(Double(tokens) * 0.013)
            let input = tokens - cacheRead - output
            let tally = TokenTally(input: input, cacheWrite: 0, cacheRead: cacheRead, output: output)
            let main = Int(Double(tokens) * 0.74)
            days.append(LedgerDay(date: date, tokens: tokens, cost: cost, unpricedTokens: 0,
                                  models: tokens > 0 ? ["gpt-5.5": main, "gpt-5.4-mini": tokens - main] : [:],
                                  tally: tally))
            if tokens > 0 {
                // Spread over the working day; today's ends an hour ago.
                let isToday = index == millions.count - 1
                let end = isToday ? now.addingTimeInterval(-3600) : date.addingTimeInterval(19 * 3600)
                let start = isToday ? max(date, end.addingTimeInterval(-6 * 3600)) : date.addingTimeInterval(10 * 3600)
                let count = max(Int(end.timeIntervalSince(start) / 900), 1)
                for step in 0..<count {
                    slots.append(.init(start: start.addingTimeInterval(Double(step) * 900),
                                       tokens: tokens / count, cost: cost / Double(count)))
                }
            }
        }
        return UsageLedger(days: days, earliest: days.first?.date, unpricedModels: [], modelNames: [:], slots: slots)
    }

    private func detailedShot() -> some View {
        let now = Date()
        // A weekly window three days from its reset, at 1:07 AM: opened four
        // days ago, so it is read about halfway through whatever the hour.
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))!
        let reset = calendar.date(bySettingHour: 1, minute: 7, second: 0, of: day)!
        let usage = codexUsage(now: now, reset: reset)
        let spend = UsageDetailCard.Spend.ledger(ledger(now: now))
        let pointer: CGFloat = 60

        return HStack(alignment: .top, spacing: 56) {
            column(card(usage, pointer: pointer, detailed: false), caption: "Compact")
            column(card(usage, pointer: pointer, detailed: true, spend: spend, forecast: true), caption: "Detailed")
        }
        .padding(.horizontal, 48)
        .padding(.top, 44)
        .padding(.bottom, 36)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Self.backdrop))
    }

    private func column<V: View>(_ card: V, caption: String) -> some View {
        VStack(spacing: 18) {
            card
            Text(verbatim: caption)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.5))
        }
    }

    // MARK: Rings

    private struct RingSpec {
        var provider: Provider
        var used: Double?
        var caption: String
        var remaining = false
        var clock: Double?
        var second: Double?
        var busy = false
        var robot: String?
    }

    /// Ring cells on the dark rail, with a caption for each on the backdrop
    /// beneath. The robots are drawn from JavaScript on the figure engine's
    /// queue: every figure is built first, and the picture is taken after
    /// real frames have arrived, not the provider's mark that stands in
    /// until they do.
    private func ringsShot(to url: URL) async throws {
        PanelMetrics.showWindowClock(true)
        defer { PanelMetrics.showWindowClock(false) }

        let figures = ["mug", "ghost", "rocket"]
        for figure in figures {
            _ = await BotAvatarEngine.shared.frame(key: "readme-warm", figure: figure, state: .idle, happy: false,
                                                   time: 0, now: 0, reducedMotion: false, size: 27, colour: "#ffffff")
        }
        BotAvatarEngine.shared.forget(key: "readme-warm")
        let robotProviders: [Provider] = [.claudeCode, .codex, .cursor]
        let inks = RobotAutomatic.inks(for: robotProviders, custom: [nil, nil, nil]).map(\.ink)

        let specs: [RingSpec] = [
            RingSpec(provider: .claudeCode, used: 0.12, caption: "Low usage"),
            RingSpec(provider: .codex, used: 0.93, caption: "Near the limit"),
            RingSpec(provider: .cursor, used: 0.75, caption: "25% left", remaining: true),
            RingSpec(provider: .grok, used: 0.38, caption: "Window clock", clock: 0.62),
            RingSpec(provider: .antigravity, used: 0.28, caption: "Second limit", second: 0.64),
            RingSpec(provider: .kimiCode, used: 0.45, caption: "Working", busy: true),
            RingSpec(provider: .claudeCode, used: 0.12, caption: RobotFigures.title(figures[0]), robot: figures[0]),
            RingSpec(provider: .codex, used: 0.55, caption: RobotFigures.title(figures[1]), robot: figures[1]),
            RingSpec(provider: .cursor, used: 0.81, caption: RobotFigures.title(figures[2]), robot: figures[2]),
        ]
        let cellWidth: CGFloat = 80
        let gap: CGFloat = 8

        func cell(_ spec: RingSpec) -> some View {
            let index = spec.robot.flatMap { figures.firstIndex(of: $0) }
            let cue = spec.robot.map { figure in
                RobotCue(ink: index.map { inks[$0] }, figure: figure)
            }
            return VStack(spacing: DockLayout.ringToTextSpacing) {
                UsageRingView(
                    provider: spec.provider, usedFraction: spec.used, hasReading: spec.used != nil,
                    showsRemaining: spec.remaining,
                    diameter: DockLayout.ringDiameter, lineWidth: DockLayout.ringLineWidth,
                    isBusy: spec.busy, windowClockFraction: spec.clock,
                    secondFraction: spec.second, secondIsSpent: false, robot: cue
                )
                Text(verbatim: spec.used.map { "\(Int(((spec.remaining ? 1 - $0 : $0) * 100).rounded()))%" } ?? "—")
                    .font(.system(size: DockLayout.percentFontSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: cellWidth)
        }

        let railHeight = DockLayout.ringDiameter + DockLayout.ringToTextSpacing + DockLayout.percentTextHeight
            + 2 * DockLayout.horizontalPadding + 16
        let view = VStack(spacing: 16) {
            HStack(spacing: gap) {
                ForEach(Array(specs.enumerated()), id: \.offset) { _, spec in cell(spec) }
            }
            .padding(.horizontal, 22)
            .frame(height: railHeight)
            .background(Capsule().fill(Color.black))
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)

            HStack(spacing: gap) {
                ForEach(Array(specs.enumerated()), id: \.offset) { _, spec in
                    Text(verbatim: spec.caption)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                        .frame(width: cellWidth, height: 40, alignment: .top)
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Self.backdrop))
        try await writeHosted(view, to: url, scale: 2, settle: 1.5)
    }

    // MARK: Menu bar

    /// Hands the store the readings it was given, as if each provider had
    /// answered.
    @MainActor
    private final class SampleServices: UsageServiceFactory {
        let readings: [String: ProviderUsage]
        init(_ readings: [ProviderUsage]) {
            self.readings = Dictionary(uniqueKeysWithValues: readings.map { ($0.account.id, $0) })
        }
        func storedKey(for provider: Provider) -> String? { nil }
        func fetch(for account: AccountKey, key: String?) -> UsageFetch {
            let reading = readings[account.id] ?? .unavailable(account, reason: .loading)
            return { reading }
        }
    }

    /// A store that has been through one pass over made-up readings, with a
    /// scratch cache file, and the settings that go with it. Nothing is read
    /// from this Mac: no keys, no transcripts, no real cache.
    private func sampleStore(_ readings: [ProviderUsage]) async throws -> (UsageStore, AppSettings) {
        let accounts = readings.map(\.account)
        let settings = AppSettings(enabledAccounts: Set(accounts.map(\.provider.rawValue)),
                                   providerOrder: accounts.map(\.provider.rawValue), readsTokenSpend: false)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "readme-shots-\(UUID().uuidString).json")
        let store = UsageStore(settings: settings, services: SampleServices(readings), cache: UsageCache(file: scratch))
        store.refresh()
        for _ in 0..<500 {
            if !store.isRefreshing, accounts.allSatisfy({ store.diagnostics[$0.id] != nil }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(accounts.allSatisfy { store.diagnostics[$0.id] != nil }, "the sample pass did not finish")
        // Kept for the rest of the run: releasing a store and its settings
        // while a window that showed them is closing crashed the next picture.
        Self.retained.append(store)
        Self.retained.append(settings)
        return (store, settings)
    }

    private func sampleReading(_ provider: Provider, _ windows: [UsageWindow], plan: String? = nil) -> ProviderUsage {
        ProviderUsage(account: AccountKey(provider), windows: windows, observedAt: Date().addingTimeInterval(-120),
                      state: .live, plan: plan, creditBalance: nil)
    }

    /// A button as the menu bar draws one: `MenuBarReading.draw` on a real
    /// `NSStatusBarButton`, which is not attached to any status item.
    private struct MenuBarButton: NSViewRepresentable {
        let reading: MenuBarReading?
        let style: MenuBarStyle

        func makeNSView(context: Context) -> NSStatusBarButton {
            let button = NSStatusBarButton(frame: .zero)
            button.isBordered = false
            button.appearance = NSAppearance(named: .aqua)
            MenuBarReading.draw(reading, remaining: false, style: style, label: nil, on: button)
            button.frame.size = Self.size(of: button)
            return button
        }
        func updateNSView(_ button: NSStatusBarButton, context: Context) {}
        func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSStatusBarButton, context: Context) -> CGSize? {
            Self.size(of: button)
        }
        /// The button's own fitting size leaves the title out; the mark, the
        /// text and the status item's side padding are added up here.
        private static func size(of button: NSStatusBarButton) -> CGSize {
            let image = button.image?.size.width ?? 0
            let text = button.attributedTitle.size().width
            return CGSize(width: ceil(image + text + 12), height: 22)
        }
    }

    /// The mark and the text of the figure and split styles, set with the
    /// fields `MenuBarReading.draw` uses (`text`, `split`, `shortName`,
    /// `isAlert`): a status button that is not on a status item does not
    /// paint its title, so the text is laid out here. The ring style is the
    /// real button.
    private struct MenuBarText: View {
        let reading: MenuBarReading
        let style: MenuBarStyle

        var body: some View {
            HStack(spacing: 0) {
                if let mark = MenuBarReading.markImage(for: reading.account, size: 15) {
                    Image(nsImage: mark).renderingMode(.template).foregroundStyle(Color(white: 0.12))
                }
                if style == .split, reading.split.count == 2 {
                    ForEach(Array(reading.split.enumerated()), id: \.offset) { index, part in
                        Text(verbatim: (index == 0 ? " " : "  ") + MenuBarReading.shortName(part.window.kind)
                             + "/" + part.window.percentText(remaining: false))
                            .foregroundStyle(part.isAlert ? Color.red : Color(white: 0.12))
                    }
                } else {
                    Text(verbatim: " " + reading.text(remaining: false))
                        .foregroundStyle(reading.isAlert ? Color.red : Color(white: 0.12))
                }
            }
            .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
    }

    /// Three of the menu bar's readings on a drawn strip, and the menu's
    /// dashboard open under the first. The strip is a mock-up; everything
    /// else is Pulse's own drawing.
    private func menuBarShot(to url: URL) async throws {
        let resets = Date().addingTimeInterval(2.5 * 3600)
        let weekResets = Date().addingTimeInterval(4 * 86_400)
        let readings = [
            sampleReading(.codex, [window("primary", .fiveHour, 0.93, seconds: 18_000, resets: resets)], plan: "Pro"),
            sampleReading(.claudeCode, [
                window("fiveHour", .fiveHour, 0.09, seconds: 18_000, resets: resets),
                window("weekly", .weekly, 0.15, seconds: 7 * 86_400, resets: weekResets),
            ], plan: "Max"),
            sampleReading(.cursor, [window("monthly", .monthly, 0.31, seconds: 30 * 86_400, resets: Self.date(12, 3, 0, 0))]),
            sampleReading(.devin, [window("daily", .daily, 0.04, seconds: 86_400, resets: Date().addingTimeInterval(9 * 3600))]),
            sampleReading(.grok, [window("weekly", .weekly, 0.22, seconds: 7 * 86_400, resets: Self.date(12, 1, 18, 0))]),
        ]
        let (store, settings) = try await sampleStore(readings)
        let threshold = settings.warningThreshold.fraction
        func reading(_ provider: Provider) -> MenuBarReading {
            MenuBarReading.of(AccountKey(provider), usage: store.usage(for: AccountKey(provider)),
                              pinned: nil, warningAt: threshold)
        }
        let model = MenuDashboardModel()

        let stripHeight: CGFloat = 30
        let items: [(String, Provider, MenuBarStyle)] = [
            ("Figure", .codex, .figure), ("Small ring", .cursor, .ring), ("Split limits", .claudeCode, .split),
        ]
        let leading: CGFloat = 330

        let strip = HStack(spacing: 0) {
            Spacer().frame(width: leading)
            HStack(spacing: 22) {
                ForEach(items, id: \.0) { caption, provider, style in
                    Group {
                        if style == .ring {
                            MenuBarButton(reading: reading(provider), style: style)
                        } else {
                            MenuBarText(reading: reading(provider), style: style)
                        }
                    }
                    .frame(height: 22)
                    .overlay(alignment: .top) {
                        Text(verbatim: caption)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(white: 0.5))
                            .fixedSize()
                            .offset(y: -30)
                    }
                }
            }
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(verbatim: "Tue 9:41").monospacedDigit()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(white: 0.2))
            .padding(.trailing, 16)
        }
        .frame(width: 780, height: stripHeight)
        .background(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14).fill(Color(white: 0.88)))

        // Where each reading starts is only needed for its caption: the
        // captions sit over the readings at the same spacing as the strip.
        let view = VStack(alignment: .leading, spacing: 0) {
            strip
            MenuDashboard(store: store, settings: settings, model: model)
                .environment(\.colorScheme, .light)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.97)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.12)))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .padding(.leading, leading - 14)
                .padding(.top, 6)
        }
        .padding(.horizontal, 40)
        .padding(.top, 52)
        .padding(.bottom, 44)
        .frame(width: 860, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Self.backdrop))
        try await writeHosted(view, to: url, scale: 2, settle: 0.8, live: true)
    }

    // MARK: Placement

    /// The rail docked across the top of a drawn screen, and the sliver it
    /// folds to when the pointer is elsewhere: `UsageDockView` itself, open
    /// and not, at the size `DockLayout` gives each.
    private func placementShot() -> some View {
        let entries = Array(railEntries.prefix(4))
        let open = DockLayout.size(for: entries.count, on: .horizontal, docked: true)
        let tileWidth = open.width + 120
        let stripHeight: CGFloat = 26
        let tileHeight = stripHeight + open.height + 56

        func tile(expanded: Bool) -> some View {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.80, green: 0.86, blue: 0.94),
                                                  Color(red: 0.90, green: 0.84, blue: 0.92)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                UsageDockView(entries: entries, selectedSlot: nil, edge: .top, isDocked: true,
                              isExpanded: expanded, onEnter: { _ in })
                    .fixedSize()
                    .padding(.top, stripHeight)
                Rectangle().fill(Color.white.opacity(0.6)).frame(height: stripHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(width: tileWidth, height: tileHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.1)))
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.primary)
        }

        return HStack(alignment: .top, spacing: 48) {
            column(tile(expanded: true), caption: "Docked at the top")
            column(tile(expanded: false), caption: "Folded when idle")
        }
        .padding(.horizontal, 48)
        .padding(.top, 44)
        .padding(.bottom, 36)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Self.backdrop))
    }

    // MARK: Recap

    /// The month, the week and the year as the poster card, from the sample
    /// recaps, a third of their size each.
    private func recapShot(to url: URL) throws {
        let decks: [(String, RecapDeck)] = [("Week", RecapSamples.weekDeck), ("Month", RecapSamples.monthDeck),
                                            ("Year", RecapSamples.yearDeck)]
        var columns: [AnyView] = []
        for (caption, deck) in decks {
            let image = try #require(RecapRenderer.image(of: .poster, in: deck), "\(caption) poster")
            columns.append(AnyView(
                column(Image(decorative: image, scale: 1).resizable().frame(width: 270, height: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.1))),
                       caption: caption)
            ))
        }
        let view = HStack(alignment: .top, spacing: 36) {
            ForEach(columns.indices, id: \.self) { columns[$0] }
        }
        .padding(.horizontal, 48)
        .padding(.top, 44)
        .padding(.bottom, 36)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Self.backdrop))
        try writeSwiftUI(view, to: url, scale: 2)
    }

    // MARK: Service status and diagnostics

    private var sampleStatus: ServiceStatus {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func days(bad: [Int: ServiceStatus.State]) -> [ServiceStatus.Day] {
            (0..<90).map { index in
                let date = calendar.date(byAdding: .day, value: index - 89, to: today)!
                return ServiceStatus.Day(date: calendar.dateComponents([.year, .month, .day], from: date),
                                         state: bad[index] ?? .operational)
            }
        }
        let page = StatusPage.of(.claudeCode)!
        return ServiceStatus(page: page, components: [
            .init(id: "cli", name: "Command line", state: .operational,
                  days: days(bad: [12: .degraded, 31: .partialOutage, 58: .degraded, 77: .degraded]), uptime: 99.62),
            .init(id: "api", name: "Programming interface", state: .degraded,
                  days: days(bad: [9: .degraded, 31: .fullOutage, 32: .degraded, 58: .partialOutage, 88: .degraded, 89: .degraded]),
                  uptime: 99.31),
            .init(id: "app", name: "Desktop app", state: .operational,
                  days: days(bad: [31: .partialOutage, 70: .degraded]), uptime: 99.88),
        ])
    }

    private func statusDiagnosticsShot(to url: URL) async throws {
        let now = Date()
        let account = AccountKey(.claudeCode)
        var reading = sampleReading(.claudeCode, [
            window("fiveHour", .fiveHour, 0.09, seconds: 18_000, resets: now.addingTimeInterval(2.5 * 3600)),
        ], plan: "Max")
        reading.origin = .endpoint
        reading.attempts = [
            .init(route: .statusLine, state: .unavailable(.awaitingResponse)),
            .init(route: .endpoint, state: .live),
        ]
        reading.responses = [
            ResponseLog.Entry(at: now, method: "GET", address: "https://api.example.com/v1/usage", status: 200,
                              contentType: "application/json", body: "{\"five_hour\": {\"utilization\": 9}}", byteCount: 33),
        ]
        let (store, settings) = try await sampleStore([reading])

        let status = ServiceStatusGroup(page: sampleStatus.page, sample: sampleStatus)
            .frame(width: 520)
        let diagnostics = ConnectionDiagnosticsView(account: account, store: store, settings: settings,
                                                   isSigningIn: false, repairMessage: nil, repair: { _ in })
            .frame(width: 520)
        let view = HStack(alignment: .top, spacing: 24) {
            status
            diagnostics
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .environment(\.colorScheme, .light)
        try await writeHosted(view, to: url, scale: 2, settle: 0.8, live: true)
    }

    // MARK: Output

    /// For views that size themselves from what they measure on screen, or
    /// whose frames arrive later: drawn through `NSHostingView` after waiting
    /// on the main actor, which a blocked run loop would never give the
    /// robots' frames. The size is taken again after each wait until it stops
    /// changing. With `live` the picture is read back from an off-screen
    /// window of the test's own (`WindowCapture`) instead of `cacheDisplay`,
    /// which draws the detailed card's plan ("Pro") at full strength.
    private func writeHosted<V: View>(_ view: V, to url: URL, scale: CGFloat, settle: Double,
                                      live: Bool = false) async throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        var size = host.fittingSize
        let window = WindowCapture.ActiveWindow(
            contentRect: CGRect(origin: WindowCapture.offscreen, size: size), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView = host
        if live {
            window.setFrameOrigin(WindowCapture.offscreen)
            window.orderFrontRegardless()
        }
        // Never released: a window animation outliving its window crashed the
        // next picture, and a handful of small windows cost nothing.
        Self.retained.append(window)
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .seconds(settle / 2))
            let next = host.fittingSize
            if next == size { break }
            size = next
            window.setContentSize(size)
            if live { window.setFrameOrigin(WindowCapture.offscreen) }
        }
        try await Task.sleep(for: .seconds(settle / 2))
        host.layoutSubtreeIfNeeded()

        if live {
            let image = try #require(WindowCapture.image(of: window))
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: url)
            return
        }
        host.display()
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    /// The cards alone are pure SwiftUI, and `ImageRenderer` draws them as the
    /// panel does. `cacheDisplay` below lost the plan's dimming ("Pro" came
    /// out at full white), so it is kept for the rail, which needs it.
    private func writeSwiftUI<V: View>(_ view: V, to url: URL, scale: CGFloat) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    /// Drawn through `NSHostingView` rather than `ImageRenderer`: the rail's
    /// rings carry AppKit views (`PointerEntryReporter`), which
    /// `ImageRenderer` replaces with a placeholder. The window is never
    /// ordered on screen.
    private func write<V: View>(_ view: V, to url: URL, scale: CGFloat) throws {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Let any insertion transitions finish before the picture is taken.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        host.display()

        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        window.contentView = nil
    }
}
