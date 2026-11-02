import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// The README's two panel screenshots, drawn from the current code instead of
/// captured from a running app, so they can be made again whenever the panel
/// changes.
///
///     PULSE_README_SHOTS=/tmp/readme-shots swift test --filter ReadmeScreenshotRenderTests
///
/// writes `<folder>/panel.png` (the side rail with Cursor's card open) and
/// `<folder>/detailed-card.png` (Codex's compact and detailed cards side by
/// side), in English on the dark panel at 2×. Copy them over
/// `Docs/images/panel.png` and `Docs/images/detailed-card.png` after reading
/// them. The figures are made up; dates follow the day the test runs.
/// Nothing here checks a pixel, and without the variable the test is skipped.
@MainActor
@Suite("README screenshots", .serialized)
struct ReadmeScreenshotRenderTests {
    static let backdrop = Color(red: 0.965, green: 0.965, blue: 0.965)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_README_SHOTS"] != nil))
    func render() throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_README_SHOTS"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }

        try write(panelShot(), to: folder.appendingPathComponent("panel.png"), scale: 2)
        PanelMetrics.showDetailedCard(true)
        defer { PanelMetrics.showDetailedCard(false) }
        try writeSwiftUI(detailedShot(), to: folder.appendingPathComponent("detailed-card.png"), scale: 2)
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

    private func card(_ usage: ProviderUsage, pointer: CGFloat, detailed: Bool,
                      spend: UsageDetailCard.Spend? = nil) -> some View {
        UsageDetailCard(usage: usage, edge: .right, isDetailed: detailed, spend: spend, pointerCenter: pointer)
            .fixedSize()
            .foregroundStyle(.primary)
            .environment(\.colorScheme, .dark)
    }

    private func measure<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        return host.fittingSize
    }

    // MARK: Detailed

    private func codexUsage(now: Date, reset: Date) -> ProviderUsage {
        ProviderUsage(
            account: AccountKey(.codex),
            windows: [window("secondary", .weekly, 0.46, seconds: 7 * 86_400, resets: reset)],
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
            column(card(usage, pointer: pointer, detailed: true, spend: spend), caption: "Detailed")
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

    // MARK: Output

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
