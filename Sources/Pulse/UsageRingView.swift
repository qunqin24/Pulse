import AppKit
import SwiftUI

struct UsageRingView: View {
    let provider: Provider
    /// How much of the tightest limit is gone, or nil when there is no reading
    /// — an empty track then says "nothing known" rather than "nothing used".
    let usedFraction: Double?
    let diameter: CGFloat
    let lineWidth: CGFloat
    /// Whether this provider's CLI is working right now.
    var isBusy: Bool = false
    /// Whether this ring is the one being pointed at.
    var highlight: Bool = false

    @State private var spinning = false

    /// Gap between the progress ring and the dark disc it encircles.
    private static let centreGap: CGFloat = 4
    /// The icon's share of that dark disc. Sizing the icon from the disc
    /// rather than from the full diameter keeps the margin around it steady
    /// even if the ring's stroke gets thicker or thinner.
    private static let iconScale: CGFloat = 0.8

    private var centreDiameter: CGFloat {
        max(diameter - (lineWidth + Self.centreGap) * 2, 0)
    }

    /// The busy arc rides the empty ring between the icon's disc and the
    /// usage ring — halfway between the two, so it touches neither.
    ///
    /// It goes *there* rather than on the ring itself for the same reason the
    /// ring is not drawn in the provider's brand colour: on this panel colour
    /// on that circle means one thing, how much of the limit is gone. A white
    /// arc laid over it would cover the answer while claiming to be about
    /// something else entirely.
    private var busyDiameter: CGFloat {
        max(diameter - lineWidth * 1.5 - Self.centreGap, 0)
    }

    /// How much of the circle the arc covers. Short enough to read as a
    /// travelling mark rather than as a second progress ring.
    private static let busySweep: CGFloat = 0.22
    private static let busyPeriod: TimeInterval = 1.0

    /// Spread of the glow that marks the ring being pointed at.
    private static let haloRadius: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: lineWidth)

            Circle()
                // Never let a full ring mean "over limit": clamp the arc, and
                // let the number next to it carry any overage.
                .trim(from: 0, to: min(max(usedFraction ?? 0, 0), 1))
                .stroke(
                    // Colour says how full the limit is, not which provider
                    // this is — the icon already says that.
                    UsageTint.color(for: usedFraction ?? 0),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // The pointed-at halo belongs to the *arc*, not to the ring
                // view as a whole. Hung on the whole view it is drawn behind
                // everything, including behind the icon — whose antialiased
                // edges let it through, so the mark picks up a wash of
                // whatever colour the limit happens to be. Measured at a green
                // cast of +16 over neutral on a 35% ring.
                .shadow(
                    color: UsageTint.color(for: usedFraction ?? 0).opacity(highlight ? 0.42 : 0),
                    radius: Self.haloRadius
                )
                .mask { haloMask }

            LobeIconView(
                provider: provider,
                size: centreDiameter * Self.iconScale
            )
            // Dimmed while there is no reading, so the rail shows at a glance
            // which providers it actually has data for.
            .foregroundStyle(.primary.opacity(usedFraction == nil ? 0.35 : 1))

            if isBusy {
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
        .accessibilityHidden(true)
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
    let provider: Provider
    let size: CGFloat

    var body: some View {
        Group {
            if let image = LobeIconStore.image(for: provider) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
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

/// Loads the bundled Lobe Icons (https://github.com/lobehub/lobe-icons) once
/// and keeps them around, keyed by provider.
///
/// The icons ship as SVG, which `NSImage` renders as vectors, so one file
/// serves every size the app draws at (36pt in the dock rail, 16pt in the
/// detail card header) with no separate raster assets. Their SVGs declare
/// `width="1em"`, which `NSImage` reads as an intrinsic size of 1x1 pt — far
/// too small to scale up from — so each image is given an explicit, generous
/// size up front. They are also marked as template images: the artwork is a
/// solid `currentColor` fill, and only its alpha matters once
/// `LobeIconView` tints it.
@MainActor
private enum LobeIconStore {
    /// Comfortably above any size the app draws these at, so scaling only
    /// ever goes downwards.
    private static let renderSize = NSSize(width: 256, height: 256)

    private static let images: [Provider: NSImage] = Dictionary(
        uniqueKeysWithValues: Provider.allCases.compactMap { provider in
            guard
                let url = Bundle.module.url(
                    forResource: provider.iconResource,
                    withExtension: "svg"
                ),
                let image = NSImage(contentsOf: url)
            else {
                return nil
            }
            image.size = renderSize
            image.isTemplate = true
            return (provider, image)
        }
    )

    static func image(for provider: Provider) -> NSImage? {
        images[provider]
    }
}

#Preview("Usage rings") {
    HStack(spacing: 20) {
        ForEach(Provider.allCases) { provider in
            UsageRingView(provider: provider, usedFraction: 0.42, diameter: 68, lineWidth: 6)
        }
    }
    .padding()
    .background(.black)
}
