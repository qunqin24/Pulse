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
