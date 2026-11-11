// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit

/// How the menu bar item draws the account it speaks for.
enum MenuBarStyle: String, CaseIterable, Sendable {
    /// The mark and the ring's figure: `✳ 15%`.
    case figure
    /// The mark and a small ring.
    case ring
    /// The mark and the account's timed limits side by side, each with a
    /// short name: `✳ 5h/9%  周/15%`. An account with fewer than two falls
    /// back to the figure.
    case split
}

/// What the menu bar item says when it shows usage: one account's ring.
///
/// **The rail's own figure, not a new one.** An account contributes the limit
/// its ring draws (`headlineWindow`, honouring a pinned limit), so the menu
/// bar never disagrees with the ring it sums up. Left out of the percentage:
/// a ring Pulse inferred — a balance measured against a watched peak or a
/// typed budget — since the menu bar has no room to say "estimate". Such an
/// account shows its money instead, as the rail does on "balance only".
struct MenuBarReading: Equatable {
    let account: AccountKey
    /// The limit the figure is about. Nil when the account has none to show.
    let window: UsageWindow?
    /// The balance, for an account whose only ring is inferred or absent.
    let money: String?
    /// Past the reader's warning line, or spent. Drawn in red.
    let isAlert: Bool
    /// The account's timed limits, shortest first, at most two and one of
    /// each length — what the split style draws. Only the account-wide ones:
    /// a limit scoped to one model is not "the five-hour limit".
    var split: [Part] = []

    /// One limit of the split style, and whether it is past the line.
    struct Part: Equatable {
        let window: UsageWindow
        let isAlert: Bool
    }

    /// The chosen account while it is on the rail; the tightest otherwise,
    /// so switching the chosen one off falls back rather than going blank.
    static func choose(
        among accounts: [AccountKey],
        chosen: AccountKey?,
        usage: (AccountKey) -> ProviderUsage,
        pinned: (AccountKey) -> String?,
        warningAt threshold: Double
    ) -> MenuBarReading? {
        if let chosen, accounts.contains(chosen) {
            return of(chosen, usage: usage(chosen), pinned: pinned(chosen), warningAt: threshold)
        }
        return tightest(among: accounts, usage: usage, pinned: pinned, warningAt: threshold)
    }

    /// The fullest ring among `accounts`. An account with no reading, or only
    /// an inferred one, is not in the comparison; a tie goes to the account
    /// earlier on the rail — the order the reader chose.
    static func tightest(
        among accounts: [AccountKey],
        usage: (AccountKey) -> ProviderUsage,
        pinned: (AccountKey) -> String?,
        warningAt threshold: Double
    ) -> MenuBarReading? {
        var best: MenuBarReading?
        for account in accounts {
            let reading = of(account, usage: usage(account), pinned: pinned(account), warningAt: threshold)
            guard let window = reading.window else { continue }
            if let fullest = best?.window, window.usedFraction <= fullest.usedFraction { continue }
            best = reading
        }
        return best
    }

    /// One account, whatever it has: its ring's limit, else its money, else
    /// nothing — never a zero standing in for a reading that is not there.
    static func of(
        _ account: AccountKey,
        usage: ProviderUsage,
        pinned: String?,
        warningAt threshold: Double
    ) -> MenuBarReading {
        if case .unavailable = usage.state {
            return MenuBarReading(account: account, window: nil, money: nil, isAlert: false)
        }
        if let window = usage.headlineWindow(preferring: pinned), window.estimate == nil {
            return MenuBarReading(
                account: account,
                window: window,
                money: nil,
                isAlert: UsageTint.isSpent(window) || window.usedFraction >= threshold,
                split: splitWindows(usage.windows).map { part in
                    Part(window: part, isAlert: UsageTint.isSpent(part) || part.usedFraction >= threshold)
                }
            )
        }
        return MenuBarReading(
            account: account,
            window: nil,
            money: usage.creditRemaining?.railText() ?? usage.creditBalance,
            isAlert: false
        )
    }

    /// Lengths the split style names, in the order it draws them.
    static let splitKinds: [UsageWindow.Kind] = [.fiveHour, .daily, .weekly, .monthly]

    static func splitWindows(_ windows: [UsageWindow]) -> [UsageWindow] {
        var seen: [UsageWindow.Kind] = []
        let picked = windows.filter { window in
            guard window.scope == nil, window.estimate == nil,
                  splitKinds.contains(window.kind), !seen.contains(window.kind)
            else { return false }
            seen.append(window.kind)
            return true
        }
        return Array(picked
            .sorted { splitKinds.firstIndex(of: $0.kind)! < splitKinds.firstIndex(of: $1.kind)! }
            .prefix(2))
    }

    /// A limit's name at menu bar size.
    static func shortName(_ kind: UsageWindow.Kind) -> String {
        switch kind {
        case .fiveHour: "5h"
        case .daily: .localized("Short: day")
        case .weekly: .localized("Short: week")
        case .monthly: .localized("Short: month")
        default: ""
        }
    }

    func text(remaining: Bool) -> String {
        window?.percentText(remaining: remaining) ?? money ?? "–"
    }

    /// How much of the ring is drawn: the rail's rule — what is left while
    /// "left" is on, except a spent ring, which is drawn full.
    func ringFraction(remaining: Bool) -> Double? {
        guard let window else { return nil }
        let used = min(max(window.usedFraction, 0), 1)
        return remaining && !UsageTint.isSpent(window) ? 1 - used : used
    }
}

extension MenuBarReading {
    /// Puts a reading on the status item's button: Pulse's mark alone when
    /// there is none, else the account's mark and its figure — or a small
    /// ring in its place — red past the warning line. The tooltip names the
    /// account and the limit.
    @MainActor
    static func draw(
        _ reading: MenuBarReading?,
        remaining: Bool,
        style: MenuBarStyle,
        label: String?,
        iconData: Data? = nil,
        on button: NSStatusBarButton
    ) {
        guard let reading else {
            button.image = pulseMark(height: 16)
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
            button.toolTip = "Pulse"
            return
        }

        let mark = markImage(for: reading.account.provider, size: 15, iconData: iconData)
        let tooltipFigure: String
        if let window = reading.window {
            tooltipFigure = remaining
                ? String.localized("\(window.percentText(remaining: true)) left, \(window.name)")
                : String.localized("\(window.percentText) used, \(window.name)")
        } else {
            tooltipFigure = reading.money ?? String.localized("No reading")
        }
        button.toolTip = [label, tooltipFigure].compactMap { $0 }.joined(separator: "\n")

        // The ring needs a limit to measure; money and "no reading" stay text.
        if style == .ring, let fraction = reading.ringFraction(remaining: remaining) {
            button.image = combined(mark, ring(fraction: fraction, alert: reading.isAlert))
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
            return
        }

        button.image = mark
        button.imagePosition = .imageLeading
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        // Each limit red on its own: a spent five-hour window beside a quiet
        // week is exactly the thing this style is for.
        if style == .split, reading.split.count == 2 {
            let title = NSMutableAttributedString()
            for (index, part) in reading.split.enumerated() {
                let window = part.window
                var attributes: [NSAttributedString.Key: Any] = [.font: font]
                if part.isAlert { attributes[.foregroundColor] = NSColor.systemRed }
                let gap = index == 0 ? " " : "  "
                title.append(NSAttributedString(string: gap, attributes: [.font: font]))
                title.append(NSAttributedString(
                    string: shortName(window.kind) + "/" + window.percentText(remaining: remaining),
                    attributes: attributes
                ))
            }
            button.attributedTitle = title
            return
        }

        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if reading.isAlert { attributes[.foregroundColor] = NSColor.systemRed }
        button.attributedTitle = NSAttributedString(string: " " + reading.text(remaining: remaining), attributes: attributes)
    }

    /// Pulse's own mark — the app icon's P, one stroke — as a template, so
    /// the menu bar colours it like every other item there. Drawn from
    /// `AppIcon/pulse-mark.svg`'s path rather than shipped as a file: one
    /// stroke, a 100-unit pen with round ends, bounds 302–762 × 194–830.
    @MainActor
    static func pulseMark(height: CGFloat) -> NSImage {
        let bounds = NSRect(x: 302, y: 194, width: 460, height: 636)
        let scale = height / bounds.height
        let image = NSImage(size: NSSize(width: (bounds.width * scale).rounded(.up), height: height), flipped: false) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.translateX(by: -bounds.minX, yBy: -bounds.minY)
            transform.concat()
            // The SVG's y runs down; here it runs up, so every y is 1024 − y.
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 352, y: 244))
            path.line(to: NSPoint(x: 352, y: 780))
            path.line(to: NSPoint(x: 562, y: 780))
            path.appendArc(withCenter: NSPoint(x: 562, y: 630), radius: 150, startAngle: 90, endAngle: -90, clockwise: true)
            path.line(to: NSPoint(x: 530, y: 480))
            path.lineWidth = 100
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pulse"
        return image
    }

    /// Fits a mark inside the menu's square without resizing a cached image.
    /// Bundled marks stay templates; extension artwork keeps its own colours.
    @MainActor
    static func markImage(for provider: Provider, size: CGFloat, iconData: Data? = nil) -> NSImage? {
        guard let source = LobeIconStore.image(for: provider, iconData: iconData) else {
            let fallback = NSImage(systemSymbolName: "chart.pie.fill", accessibilityDescription: nil)
            fallback?.size = NSSize(width: size, height: size)
            fallback?.isTemplate = true
            return fallback
        }
        let mark = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = min(rect.width / source.size.width, rect.height / source.size.height)
            let fitted = NSSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: NSRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                                   width: fitted.width, height: fitted.height))
            return true
        }
        mark.isTemplate = source.isTemplate
        return mark
    }

    /// The rail's ring at menu bar size: a faint track and the arc from the
    /// top, clockwise. Drawn when shown, so `labelColor` is whatever the menu
    /// bar's appearance makes it — light on a dark bar, dark on a light one.
    private static func ring(fraction: Double, alert: Bool) -> NSImage {
        NSImage(size: NSSize(width: 15, height: 15), flipped: false) { rect in
            let line: CGFloat = 2.2
            let box = rect.insetBy(dx: line / 2 + 0.5, dy: line / 2 + 0.5)
            let track = NSBezierPath(ovalIn: box)
            track.lineWidth = line
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            track.stroke()

            guard fraction > 0 else { return true }
            let centre = NSPoint(x: box.midX, y: box.midY)
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: centre,
                radius: box.width / 2,
                startAngle: 90,
                endAngle: 90 - 360 * min(fraction, 1),
                clockwise: true
            )
            arc.lineWidth = line
            arc.lineCapStyle = .round
            (alert ? NSColor.systemRed : NSColor.labelColor).setStroke()
            arc.stroke()
            return true
        }
    }

    /// The mark and the ring side by side as one image. Not a template: the
    /// ring may be red. Only template marks are tinted to `labelColor`.
    private static func combined(_ mark: NSImage?, _ ring: NSImage) -> NSImage {
        let gap: CGFloat = 4
        let markWidth = mark?.size.width ?? 0
        let size = NSSize(width: markWidth + (mark == nil ? 0 : gap) + ring.size.width, height: 15)
        return NSImage(size: size, flipped: false) { _ in
            if let mark {
                let tinted = NSImage(size: mark.size, flipped: false) { markRect in
                    mark.draw(in: markRect)
                    if mark.isTemplate {
                        NSColor.labelColor.set()
                        markRect.fill(using: .sourceAtop)
                    }
                    return true
                }
                tinted.draw(in: NSRect(origin: .zero, size: mark.size))
            }
            ring.draw(in: NSRect(x: size.width - ring.size.width, y: 0, width: ring.size.width, height: ring.size.height))
            return true
        }
    }
}
