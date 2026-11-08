// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

struct UsageRingView: View {
    let provider: Provider
    /// How much of the tightest limit is gone, or nil when there is no
    /// fraction to draw — an empty track then says "nothing known" rather than
    /// "nothing used".
    let usedFraction: Double?
    /// Whether this ring has a reading at all.
    ///
    /// **Not `usedFraction != nil`**, which is what the icon used to dim on.
    /// The two agreed while every provider reported a percentage; DeepSeek
    /// reports prepaid credit and no allowance, so on "balance only" there is
    /// deliberately no fraction and the ring shows the money instead — a
    /// perfectly good reading, drawn at 35% opacity as though nothing had come
    /// back.
    var hasReading: Bool = true
    /// A colour chosen for this account, or nil to colour by how much is gone.
    ///
    /// Nil is the default and the one that carries meaning — see `RingTint`.
    /// A chosen colour is identity, which is a different thing from status, so
    /// a **spent** limit still shows the spent colour: being blocked is not a
    /// matter of taste, and it is the one reading the app exists to give.
    var chosenTint: Color?
    /// Whether the provider says this limit is **spent**, which it can say
    /// well short of 100% — Claude Code reports a locked reason, Codex flags a
    /// group, OpenCode a status other than `ok`. Reading it off the fraction
    /// instead is how the spent colour came to be shown only at 100%, and how
    /// a chosen colour came to survive a limit the user is blocked on.
    var isSpent: Bool = false
    /// Draw the arc as what is **left** rather than what is gone.
    ///
    /// Only the arc. The colour is worked out from `usedFraction` either way,
    /// because what it means — how close this limit is — does not change
    /// because the figure beside it was counted from the other end. So a ring
    /// with a sliver left is a small red arc, not a large one.
    var showsRemaining: Bool = false
    let diameter: CGFloat
    let lineWidth: CGFloat
    /// Whether this provider's CLI is working right now. This drives the white
    /// travelling mark inside the usage ring.
    var isBusy: Bool = false
    /// Whether Pulse is fetching a fresh usage reading. This rotates the
    /// coloured usage arc itself, keeping white reserved for CLI activity.
    var isRefreshing: Bool = false
    /// Whether `isBusy`/`isRefreshing` are allowed to turn anything.
    ///
    /// On by default — see `AppSettings.animatesRingActivity`. Off, the two
    /// facts above are still tracked but draw nothing extra: no travelling
    /// mark, no refresh sweep, and the usage arc stays at full opacity while
    /// a reading is fetched instead of dimming for the turn to sit in.
    var animatesActivity: Bool = true
    /// Whether this ring is the one being pointed at.
    var highlight: Bool = false
    /// How much of the window clock to draw, 0...1, or nil to leave it out.
    ///
    /// Drawn as a thin arc **outside** the usage ring. Outside because the
    /// circle inside is spoken for — the CLI-activity mark rides there — and
    /// thin, in a neutral, because colour on this ring already means one
    /// thing. A second hue would be a second colour language to learn; a
    /// hairline at a different radius reads as a different measurement
    /// without claiming a status of its own, and cannot clash with a colour
    /// somebody chose for the ring.
    var windowClockFraction: Double?

    /// The next-fullest limit, drawn as a smaller ring inside this one.
    ///
    /// Inside rather than outside, which is where the clock arc goes: two
    /// usage arcs have to read as the same kind of measurement, and the one
    /// that matters most should stay the outer, bigger, thicker one. Nil for a
    /// provider that reports a single limit — an empty second ring reads as a
    /// limit at zero, or as a fault.
    /// **`let`, not `var`.** An optional `var` gets an implicit `nil` in the
    /// memberwise initializer, so leaving this off the call site compiles
    /// perfectly and draws nothing — which is exactly what happened: the wire
    /// from the rail was written, lost to a bad patch, and the build stayed
    /// green while the setting did nothing. A `let` has no default, so the
    /// next person who forgets it is told.
    let secondFraction: Double?
    let secondIsSpent: Bool
    /// CX ArtLab's robot in place of the provider's mark, or nil for the mark.
    /// Per account, off by default (`AppSettings.robotAccounts`).
    var robot: RobotCue?
    /// False while the rail is collapsed, which stops the robot's timeline.
    var isLive: Bool = true
    /// The account's discovered PNG, or nil for the bundled provider mark.
    var iconData: Data? = nil

    @State private var spinning = false
    @State private var refreshSpinning = false

    /// Where red begins, as the panel has been set. See `WarningThreshold`.
    @Environment(\.usageWarningThreshold) private var warningThreshold


    /// Gap between the progress ring and the dark disc it encircles.
    private static let centreGap: CGFloat = 4
    /// The icon's share of that dark disc. Sizing the icon from the disc
    /// rather than from the full diameter keeps the margin around it steady
    /// even if the ring's stroke gets thicker or thinner.
    ///
    /// The whole disc: 0.8 read small beside the robot, and 0.9 and 1.0 were
    /// drawn side by side and 1.0 was picked. The cost, accepted: a busy
    /// ring's activity arc and a second ring both pass close to the glyph.
    private static let iconScale: CGFloat = 1.0
    /// The robot's share of the same disc: **wider than the disc**. Its
    /// drawing carries the antenna and room to move above the head, so the
    /// head needs the extra width to read as large as a logo. It may spread
    /// into the band between the disc and the usage ring because a ring with
    /// a robot draws no activity arc there. With a second ring that band is
    /// taken, and its taller outline would touch the inner ring at the
    /// logo's size, so it is drawn smaller there.
    private var robotScale: CGFloat { secondFraction == nil ? 1.1 : 0.8 }

    private var centreDiameter: CGFloat {
        // The disc gives up two points a side to the second ring, which needs
        // the band the disc's margin was using. Only when it is actually
        // drawn: a provider with one limit keeps the icon it always had.
        let squeeze = secondFraction == nil ? 0 : Self.secondRingSqueeze * PanelMetrics.scale
        return max(diameter - (lineWidth + Self.centreGap) * 2 - squeeze * 2, 0)
    }

    /// How much the icon's disc shrinks to make room, per side.
    private static let secondRingSqueeze: CGFloat = 2

    /// The busy arc rides the empty ring between the icon's disc and the
    /// usage ring — halfway between the two, so it touches neither.
    ///
    /// It goes *there* rather than on the ring itself for the same reason the
    /// ring is not drawn in the provider's brand colour: on this panel colour
    /// on that circle means one thing, how much of the limit is gone. A white
    /// arc laid over it would cover the answer while claiming to be about
    /// something else entirely.
    private var busyDiameter: CGFloat {
        // **The second ring takes this band.** The mark and the ring would be
        // stroked at the same radius otherwise — and the providers that report
        // two limits are exactly the two whose CLIs make this spin. With the
        // ring there the mark rides just outside the disc instead.
        guard secondFraction == nil else {
            return max(centreDiameter + Self.secondRingSqueeze * PanelMetrics.scale, 0)
        }
        return max(diameter - lineWidth * 1.5 - Self.centreGap, 0)
    }

    /// How much of the circle the arc covers. Short enough to read as a
    /// travelling mark rather than as a second progress ring.
    private static let busySweep: CGFloat = 0.22
    private static let busyPeriod: TimeInterval = 1.0

    /// How much of the circle the refresh mark covers, and how long it takes
    /// to go round. Shorter and quicker than the activity mark, so the two
    /// read as different things when a provider happens to be doing both.
    private static let refreshSweep: CGFloat = 0.16
    private static let refreshPeriod: TimeInterval = 0.85

    /// Spread of the glow that marks the ring being pointed at.
    private static let haloRadius: CGFloat = 10

    /// The clock arc's own geometry, measured out from the usage ring's outer
    /// edge. The rail is far wider than a ring — 64pt against 36 at standard
    /// scale — so its width is unchanged; the figures stand further off
    /// while it is on (`DockLayout.ringToTextSpacing`), which is 5pt here.
    private static let clockGap: CGFloat = 3
    private static let clockLineWidth: CGFloat = 2
    /// The circle the clock arc is stroked along.
    private var clockDiameter: CGFloat {
        diameter + lineWidth + (Self.clockGap + Self.clockLineWidth / 2) * 2 * PanelMetrics.scale
    }

    /// The next-fullest limit, as a thinner ring inside the first.
    ///
    /// Same colour language, deliberately: two arcs measuring the same kind of
    /// thing must be read the same way, and a second hue would be a second
    /// vocabulary for one idea. What tells them apart is size and weight — the
    /// limit that matters most is the outer, thicker one, and stays where a
    /// single ring has always been so nothing moves for somebody who leaves
    /// this off.
    @ViewBuilder
    private func secondRing(_ fraction: Double) -> some View {
        let used = min(max(fraction, 0), 1)
        let spent = secondIsSpent || used >= 1
        let shown = showsRemaining && !spent ? 1 - used : used
        let colour = chosenTint.flatMap { spent ? nil : $0 }
            ?? UsageTint.color(for: used, isExhausted: spent, warningAt: warningThreshold)

        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: DockLayout.secondRingLineWidth)

            Circle()
                // Full when spent, whichever way it counts — the same rule the
                // outer ring gets, and for the same reason: the most urgent
                // state must not be the one with the least ink.
                .trim(from: 0, to: spent ? 1 : max(shown, 0))
                .stroke(
                    colour,
                    style: StrokeStyle(lineWidth: DockLayout.secondRingLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: shown)
        }
        .frame(width: DockLayout.secondRingDiameter, height: DockLayout.secondRingDiameter)
    }

    /// What the arc and the halo are drawn in.
    private var arcColour: Color {
        let spent = isSpent || (usedFraction ?? 0) >= 1
        let automatic = UsageTint.color(for: usedFraction ?? 0, isExhausted: spent, warningAt: warningThreshold)

        // Spent is the one state a chosen colour does not get to hide.
        guard let chosenTint, !spent else { return automatic }
        return chosenTint
    }

    /// How much of the circle the coloured arc covers.
    private var arcFraction: CGFloat {
        // **No reading draws nothing, either way round.** `?? 0` inverted to a
        // full circle, so a provider that had not answered — the first seconds
        // after launch, one signed out, one waiting on a key, one being rate
        // limited — drew a complete *green* ring reading "all fine". Measured
        // by sampling the rendered circumference: 7,200 of 7,200 points
        // coloured. The empty track is what "nothing known" looks like.
        guard let usedFraction else { return 0 }
        let used = min(max(usedFraction, 0), 1)

        // **Spent fills the ring whichever way it counts.** Counting down,
        // nothing left is no arc at all — so the most urgent state had the
        // least ink on screen, and on a top rail the figure beside it is off
        // by default. The colour is already right; this gives it something to
        // colour.
        if isSpent || used >= 1 { return 1 }
        return showsRemaining ? 1 - used : used
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: lineWidth)

            usageArc
                .rotationEffect(.degrees(-90))
                // Quietened while a reading is being fetched, never moved.
                // The arc starts at twelve o'clock and that is what makes it a
                // gauge; turning it takes the reading away for as long as the
                // refresh lasts, and puts it back with a jump when the spin
                // stops at whatever angle it had reached.
                .opacity(isRefreshing && animatesActivity ? 0.3 : 1)

            if isRefreshing && animatesActivity { refreshMark }

            // Dimmed while there is no reading, so the rail shows at a
            // glance which providers it actually has data for. An opacity
            // rather than a dimmer foreground, because the robot may have a
            // colour of its own.
            centreMark
                .opacity(hasReading ? 1 : 0.35)

            if let secondFraction {
                secondRing(secondFraction)
            }

            // **Not with the robot.** It shows the CLI working itself, and
            // the same fact is not drawn twice on one ring.
            if isBusy && animatesActivity && robot == nil {
                Circle()
                    .trim(from: 0, to: Self.busySweep)
                    .stroke(
                        Color.primary,
                        style: StrokeStyle(lineWidth: max(lineWidth * 0.5, 1.5), lineCap: .round)
                    )
                    .frame(width: busyDiameter, height: busyDiameter)
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    // Core Animation drives this, not a per-frame timeline:
                    // Pulse is an `.accessory` app behind a panel that never
                    // becomes key, so it is essentially never the active app,
                    // and a schedule tied to the app's own frames is a poor
                    // bet. The reset on the way out matters — without it a
                    // second appearance sets an already-true value and no
                    // animation is created at all.
                    .animation(
                        .linear(duration: Self.busyPeriod).repeatForever(autoreverses: false),
                        value: spinning
                    )
                    .onAppear { spinning = true }
                    .onDisappear { spinning = false }
                    .transition(.opacity)
            }
        }
        .frame(width: diameter, height: diameter)
        // **An overlay, after the frame — never a child of the stack.** A
        // fixed-size child sets a `ZStack`'s size, and this circle is wider
        // than the ring by design: inside the stack it grew the usage ring
        // itself from 36pt to 52pt, which moves every ring centre the hit
        // testing is measured against. An overlay draws outside its host
        // without being measured into it.
        .overlay { windowClock }
        .animation(.easeOut(duration: 0.2), value: isRefreshing)
        .accessibilityHidden(true)
    }

    /// What sits in the disc: the provider's mark, or the robot, sized by
    /// `robotScale`. Nothing around it moves either way.
    @ViewBuilder
    private var centreMark: some View {
        if let robot {
            RobotMarkView(
                mood: RobotMood.resolve(hasReading: hasReading, isSpent: isSpent, isWorking: isBusy, isRefreshing: isRefreshing,
                                        activity: animatesActivity),
                gesture: robot.gesture,
                size: centreDiameter * robotScale,
                isLive: isLive,
                ink: robot.ink,
                inkIsChosen: robot.inkIsChosen,
                personality: robot.personality,
                shape: robot.shape
            )
        } else {
            LobeIconView(
                provider: provider,
                size: centreDiameter * Self.iconScale,
                iconData: iconData
            )
        }
    }

    /// The selected side of the window clock: a hairline outside the usage
    /// ring, in a neutral rather than a second hue.
    @ViewBuilder
    private var windowClock: some View {
        if let windowClockFraction {
            ZStack {
                // Its own faint track, so an arc a tenth of the way round
                // still reads as a proportion of something rather than as a
                // stray tick.
                Circle()
                    .stroke(Color.primary.opacity(0.16), lineWidth: Self.clockLineWidth * PanelMetrics.scale)

                Circle()
                    .trim(from: 0, to: windowClockFraction)
                    .stroke(
                        Color.primary.opacity(0.7),
                        style: StrokeStyle(lineWidth: Self.clockLineWidth * PanelMetrics.scale, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    // It moves in minutes, so it is never worth animating from
                    // one reading to the next — but a reset jumps between the
                    // two ends in either direction, and should not look like a
                    // glitch.
                    .animation(.easeOut(duration: 0.35), value: windowClockFraction)
            }
            .frame(width: clockDiameter, height: clockDiameter)
        }
    }

    /// The mark that says a fresh reading is being fetched: a short segment of
    /// the ring, in the usage colour, travelling the whole circle.
    ///
    /// It runs over the track and the usage arc alike, which is the point.
    /// Spinning the usage arc itself instead makes the feedback depend on the
    /// number it is showing: at 0% there is no arc, so a click produced no
    /// visible response whatsoever, and at 95% a rotated arc is nearly
    /// indistinguishable from a still one. This is the same at every reading.
    ///
    /// The usage colour rather than white: white on this ring is spoken for by
    /// the CLI-activity mark, which rides the empty circle further in.
    private var refreshMark: some View {
        Circle()
            .trim(from: 0, to: Self.refreshSweep)
            .stroke(
                arcColour,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90 + (refreshSpinning ? 360 : 0)))
            // Core Animation drives it, for the same reason the activity mark
            // does — and the reset on the way out matters just as much, or a
            // second refresh sets an already-true value and animates nothing.
            .animation(
                .linear(duration: Self.refreshPeriod).repeatForever(autoreverses: false),
                value: refreshSpinning
            )
            .onAppear { refreshSpinning = true }
            .onDisappear { refreshSpinning = false }
            .transition(.opacity)
    }

    private var usageArc: some View {
        Circle()
            // Never let a full ring mean "over limit": clamp the arc, and let
            // the number next to it carry any overage.
            .trim(from: 0, to: arcFraction)
            .stroke(
                // Colour says how full the limit is, not which provider this
                // is — the icon already says that.
                arcColour,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            // The pointed-at halo belongs to the *arc*, not to the ring view as
            // a whole. Hung on the whole view it is drawn behind everything,
            // including behind the icon — whose antialiased edges let it
            // through, so the mark picks up a wash of whatever colour the limit
            // happens to be. Measured at a green cast of +16 over neutral on a
            // 35% ring.
            .shadow(
                color: arcColour.opacity(highlight ? 0.42 : 0),
                radius: Self.haloRadius
            )
            .mask { haloMask }
            // A new reading slides into place rather than cutting to it. This
            // is what a manual refresh is *for*: if the figure moved, the
            // movement is the answer.
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: arcFraction)
    }

    /// Keeps the halo out of the ring's centre.
    ///
    /// The glow is a shadow cast by the arc, so it spreads inwards as well as
    /// outwards, and the inward half lands under the provider's mark. This
    /// takes that half away at exactly the radius where the ring's clearing
    /// begins, and leaves the outward half — the part that was wanted —
    /// untouched. The arc itself is well outside the hole, so it is not
    /// touched either.
    ///
    /// It used to be an opaque disc laid over the blur instead, which works on
    /// the black panel because a black disc on a black rail is invisible. On
    /// Liquid Glass there is no such colour: the disc has to follow the
    /// appearance the material picked, and over a light backdrop that is a
    /// solid white coin behind the mark. A mask has no colour to get wrong.
    private var haloMask: some View {
        ZStack {
            // Wide enough that the outward blur is never clipped — a mask is
            // not bounded by the view it is applied to.
            Circle()
                .fill(Color.white)
                .frame(
                    width: diameter + Self.haloRadius * 4,
                    height: diameter + Self.haloRadius * 4
                )

            Circle()
                .fill(Color.white)
                .frame(width: centreDiameter, height: centreDiameter)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}

struct LobeIconView: View {
    /// The fallback SVG in `Resources` to draw, without its extension.
    let resource: String
    let size: CGFloat
    let iconData: Data?

    init(provider: Provider, size: CGFloat, iconData: Data? = nil) {
        self.resource = provider.iconResource
        self.size = size
        self.iconData = iconData
    }

    /// For a mark that belongs to an agent rather than to a provider. See
    /// `LobeIconStore`.
    init(resource: String, size: CGFloat, iconData: Data? = nil) {
        self.resource = resource
        self.size = size
        self.iconData = iconData
    }

    var body: some View {
        Group {
            if let image = LobeIconStore.image(named: resource, iconData: iconData) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(image.isTemplate ? .template : .original)
                    .scaledToFit()
            } else {
                Image(systemName: "questionmark")
                    .resizable()
                    .scaledToFit()
                    .opacity(0.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Loads bundled Lobe Icons (https://github.com/lobehub/lobe-icons) by resource
/// name, or an extension's PNG snapshot by content in a separate bounded cache.
///
/// The icons ship as SVG, which `NSImage` renders as vectors, so one file
/// serves every size the app draws at (36pt in the dock rail, 16pt in the
/// detail card header) with no separate raster assets. Their SVGs declare
/// `width="1em"`, which `NSImage` reads as an intrinsic size of 1x1 pt — far
/// too small to scale up from — so each image is given an explicit, generous
/// size up front. They are also marked as template images: the artwork is a
/// solid `currentColor` fill, and only its alpha matters once
/// `LobeIconView` tints it.
///
/// Not `private` so `AgentIconTests` can ask whether a named mark actually
/// loads — a test's own `Bundle.module` is the test target's, so the only way
/// to ask about Pulse's resources is through Pulse. Do not tidy it back.
@MainActor
enum LobeIconStore {
    /// Comfortably above any size the app draws these at, so scaling only
    /// ever goes downwards.
    private static let renderSize = NSSize(width: 256, height: 256)

    /// Keyed by **resource name**, not by `Provider`.
    ///
    /// The spend pane draws clients that are not providers at all — a provider
    /// is something Pulse can put a ring and a pane behind, and most of the
    /// agent catalogue is neither. Keying the store by the file name is what
    /// lets an agent carry its own mark without being promoted to a provider
    /// to get one.
    ///
    /// Loaded on demand rather than all at once: the catalogue's marks are
    /// only ever needed if that pane is opened, and most installs draw a
    /// handful of them.
    private static var images: [String: NSImage] = [:]

    /// NSData compares bytes, so two accounts cannot collide just because they
    /// share a filename, and changed bytes after a rescan get a new image.
    private static let externalImages: NSCache<NSData, NSImage> = {
        let cache = NSCache<NSData, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    static func image(named name: String, iconData: Data? = nil) -> NSImage? {
        if let iconData, let image = externalImage(data: iconData) { return image }
        if let cached = images[name] { return cached }
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = renderSize
        image.isTemplate = true
        images[name] = image
        return image
    }

    static func image(for provider: Provider, iconData: Data? = nil) -> NSImage? {
        image(named: provider.iconResource, iconData: iconData)
    }

    private static func externalImage(data: Data) -> NSImage? {
        let key = data as NSData
        if let cached = externalImages.object(forKey: key) { return cached }
        guard let image = NSImage(data: data), image.isValid else { return nil }
        // PNGs are app artwork: treating their opaque interiors as a template
        // would erase details such as a black glyph on a white background.
        image.isTemplate = false
        let cost = image.representations.compactMap { $0 as? NSBitmapImageRep }
            .reduce(data.count) { $0 + $1.bytesPerRow * $1.pixelsHigh }
        externalImages.setObject(image, forKey: key, cost: cost)
        return image
    }
}

#Preview("Usage rings") {
    HStack(spacing: 20) {
        ForEach(Provider.builtIn) { provider in
            UsageRingView(
                provider: provider,
                usedFraction: 0.42,
                diameter: 68,
                lineWidth: 6,
                secondFraction: 0.18,
                secondIsSpent: false
            )
        }
    }
    .padding()
    .background(.black)
}
