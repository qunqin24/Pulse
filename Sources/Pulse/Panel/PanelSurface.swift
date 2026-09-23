import SwiftUI

/// What the panel's shapes are filled with: flat black, or Liquid Glass.
///
/// Black is the default and stays it. The panel sits over whatever the user is
/// working on all day, and a solid surface is the one that is legible over
/// anything — glass takes on the colour and busyness of whatever happens to be
/// behind it, which is lovely over a photo and hard work over a code editor.
/// So it is offered rather than assumed.
///
/// No scrim is laid over the glass, deliberately. Apple's guidance is that the
/// material manages its own legibility — it shifts tint and dynamic range, and
/// switches between light and dark, to suit what is behind it — so the way to
/// keep content readable is to let it adapt too, which is why everything drawn
/// on the panel uses the standard `.primary` colours rather than a hardcoded
/// white. Darkening the glass by hand fights all of that and makes it look
/// like a grey box.
struct PanelSurface<S: Shape>: View {
    let shape: S
    let usesGlass: Bool
    /// Tints the surface when a limit is close enough to matter. Nil leaves it
    /// neutral.
    var tint: Color?
    /// Bumped to make the glass look behind the window again — see
    /// `GlassResample`.
    @Environment(\.glassResample) private var resample

    var body: some View {
        // Deliberately hit-testable, and the panel cannot be dragged without
        // it. A window is only handed a press if something in it claims that
        // point, and this surface is the only thing covering the empty black
        // between the rings — the rings themselves claim their own area for
        // their tracking areas, which is why they went on working while the
        // gaps between them went dead the moment this was marked
        // `allowsHitTesting(false)`.
        //
        // Nothing is at risk in claiming it: the drag is taken by the window
        // itself in `FloatingPanel.sendEvent`, before any view sees the event,
        // so there is no handle here for this to steal a press from.
        surface
            // Claimed to the capsule's own outline rather than to its bounding
            // box, so the whole capsule can be taken hold of and the corners
            // it doesn't fill still let a click through to what is behind.
            .contentShape(shape)
    }

    @ViewBuilder
    private var surface: some View {
        if usesGlass {
            glass
                // A new identity is a new material layer, and a new layer
                // samples what is behind the window now rather than whenever
                // the old one last did. Measured on 26.7 (where it is never
                // bumped): rebuilding every 0.3s changed no pixel.
                .id(resample)
        } else {
            shape.fill(tint ?? .black)
        }
    }


    /// `.clear`, not `.regular`. Measured over a bright, busy backdrop:
    /// `.regular` comes out an opaque milky white with nothing showing through
    /// — frosted glass, not Liquid Glass. AppKit's `NSGlassEffectView` was
    /// measured against this too and is pixel-for-pixel the same material, so
    /// the modifier wins: it takes the shape directly, which the open/close
    /// morph needs, where the AppKit view knows only a corner radius and would
    /// have to be clipped to the rail's flare.
    ///
    /// It needs macOS 26; the package deploys to 14, so older systems get the
    /// closest thing that has always existed — a vibrant blur. Not the same
    /// material, but the same idea, and it degrades rather than failing.
    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.clear.tint(tint), in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay { tint.map { shape.fill($0.opacity(0.28)) } }
        }
    }
}

/// Nudges Liquid Glass into re-reading what is behind the panel, on the
/// systems where it stops doing that by itself.
///
/// On macOS 26.2 (issue #36) the material over this panel kept showing the
/// backdrop it last sampled: light glass stayed light after the page behind it
/// went dark, and the other way round, until the pointer made the panel redraw.
/// 26.7 tracks the backdrop live and does not have the fault, so it never pays
/// for this. Versions in between are unknown and get the nudge.
///
/// **Not verified on an affected system.** The evidence is only that a redraw
/// cleared it in the reporter's recording. If it does not help there, take it
/// out rather than tuning the interval.
enum GlassResample {
    /// How long a stale surface can last when nothing else moves it — a tab
    /// switched inside one app says nothing to Pulse.
    static let interval: Duration = .seconds(2)

    static var isNeeded: Bool {
        let info = ProcessInfo.processInfo
        return info.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
            && !info.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 7, patchVersion: 0))
    }
}

private struct GlassResampleKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var glassResample: Int {
        get { self[GlassResampleKey.self] }
        set { self[GlassResampleKey.self] = newValue }
    }
}
