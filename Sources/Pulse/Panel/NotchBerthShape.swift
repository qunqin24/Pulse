import SwiftUI

/// An extension of the camera housing, flush with the physical screen top.
/// The rings keep their layout below the housing; only the surface grows.
///
/// Drawn like the top rail it replaces: the body's sides sweep **out** into
/// the screen's top edge through a concave fillet, so the surface reads as
/// growing out of the edge rather than as a slab parked against it. Without
/// the fillet the two top corners are square, which is the one thing the
/// docked rail has never looked like. [`DockBerthShape`](UsageDockView.swift)
/// draws the same curve for a rail that is not on a notch.
struct NotchBerthShape: Shape {
    var notchSize: CGSize
    var openness: CGFloat = 1

    /// Pulls each fillet's control points off its endpoints, the same 0.55
    /// circular-arc approximation `DockBerthShape` uses. Keeping the two in
    /// step matters more than the number: a notched Mac and a plain one show
    /// the same rail.
    private static let fillet: CGFloat = 0.55

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    /// `rect` is the body **plus** `DockLayout.flareWidth` on each side, which
    /// is the room the fillets sweep into. The caller sizes the frame for it;
    /// `PanelHitArea.notchSurface` stays the body alone, so the grab area
    /// never claims more than the rail draws.
    func path(in rect: CGRect) -> Path {
        let progress = min(max(openness, 0), 1)
        guard progress > 0 else { return Path() }

        let flareWidth = DockLayout.flareWidth * progress
        let flareHeight = min(DockLayout.flareHeight * progress, rect.height)
        let body = rect.insetBy(dx: DockLayout.flareWidth, dy: 0)

        let width = notchSize.width + (body.width - notchSize.width) * progress
        let height = notchSize.height + (body.height - notchSize.height) * progress
        let minX = rect.midX - width / 2
        let maxX = rect.midX + width / 2
        let top = rect.minY
        let bottom = top + height

        // The bottom corners cannot take more than the surface has left below
        // the fillets, or the two curves cross and the outline folds.
        let radius = min(DockLayout.cornerRadius, width / 2, max(height - flareHeight, 0))
        let k = Self.fillet

        var path = Path()

        // Along the screen's top edge, left to right, past where the left
        // fillet leaves it.
        path.move(to: CGPoint(x: minX - flareWidth, y: top))

        // Down into the body's left edge. Horizontal where it leaves the
        // screen edge, vertical where it meets the body, so both joins are
        // tangent-continuous.
        path.addCurve(
            to: CGPoint(x: minX, y: top + flareHeight),
            control1: CGPoint(x: minX - flareWidth * (1 - k), y: top),
            control2: CGPoint(x: minX, y: top + flareHeight * (1 - k))
        )

        path.addLine(to: CGPoint(x: minX, y: bottom - radius))
        path.addArc(
            tangent1End: CGPoint(x: minX, y: bottom),
            tangent2End: CGPoint(x: maxX, y: bottom),
            radius: radius
        )
        path.addLine(to: CGPoint(x: maxX - radius, y: bottom))
        path.addArc(
            tangent1End: CGPoint(x: maxX, y: bottom),
            tangent2End: CGPoint(x: maxX, y: top),
            radius: radius
        )

        path.addLine(to: CGPoint(x: maxX, y: top + flareHeight))

        // The mirrored fillet back out to the screen edge.
        path.addCurve(
            to: CGPoint(x: maxX + flareWidth, y: top),
            control1: CGPoint(x: maxX, y: top + flareHeight * (1 - k)),
            control2: CGPoint(x: maxX + flareWidth * (1 - k), y: top)
        )

        path.closeSubpath()
        return path
    }
}
