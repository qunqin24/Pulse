import SwiftUI

/// The details card's outline: rounded body and pointer as one path.
///
/// These used to be two views side by side in a stack — a rounded rectangle
/// and a separate pointer nudged into place with padding. Switching providers
/// changes the card's height and the pointer's target at the same time, and
/// two views animating separately don't stay in step: the tail visibly comes
/// away from the card mid-transition. Drawing both as one shape makes that
/// impossible, since there is nothing left to fall out of sync.
struct UsageBubbleShape: Shape {
    /// Which side the pointer leaves from — the side facing the rail.
    let edge: PanelEdge
    /// Centre of the pointer, measured down from the shape's top edge.
    var pointerCenterY: CGFloat
    let cornerRadius: CGFloat
    let pointerWidth: CGFloat
    let pointerHeight: CGFloat

    /// Lets the pointer slide as part of the shape rather than as a separate
    /// animation that could run on its own curve.
    var animatableData: CGFloat {
        get { pointerCenterY }
        set { pointerCenterY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // The pointer lives in a strip along the rail-facing side; the body
        // fills what's left.
        let body = CGRect(
            x: edge.isLeft ? pointerWidth : 0,
            y: 0,
            width: max(rect.width - pointerWidth, 0),
            height: rect.height
        )

        var path = Path(
            roundedRect: body,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )

        path.addPath(pointerPath(in: rect, body: body))
        return path
    }

    /// The tail, as a subpath overlapping the body's edge so the two read as a
    /// single silhouette once filled.
    private func pointerPath(in rect: CGRect, body: CGRect) -> Path {
        let half = pointerHeight / 2
        // Keep the tail clear of the rounded corners, and inside the card even
        // when the caller asks for something out of range.
        let centre = min(
            max(pointerCenterY, cornerRadius + half),
            max(rect.height - cornerRadius - half, cornerRadius + half)
        )

        let baseX = edge.isLeft ? body.minX : body.maxX
        let tipX = edge.isLeft ? rect.minX : rect.maxX
        let reach = tipX - baseX

        // Traverse the tail in the direction that winds the same way as the
        // body's rounded rectangle. The two are separate subpaths filled as
        // one shape, and under the non-zero fill rule opposite windings
        // *cancel* where they overlap — which is exactly what happened on the
        // left edge: mirroring the geometry reversed the tail's direction, and
        // the overlap with the body punched a gap between them.
        let sweep = edge.isLeft ? -half : half

        var path = Path()
        path.move(to: CGPoint(x: baseX, y: centre - sweep))
        path.addCurve(
            to: CGPoint(x: tipX, y: centre),
            control1: CGPoint(x: baseX + reach * 0.24, y: centre - sweep * 0.44),
            control2: CGPoint(x: baseX + reach * 0.55, y: centre - sweep * 0.24)
        )
        path.addCurve(
            to: CGPoint(x: baseX, y: centre + sweep),
            control1: CGPoint(x: baseX + reach * 0.55, y: centre + sweep * 0.24),
            control2: CGPoint(x: baseX + reach * 0.24, y: centre + sweep * 0.44)
        )
        // Bite back into the body so the join is covered by the fill rather
        // than leaving a seam along the edge.
        path.addLine(to: CGPoint(x: baseX - reach * 0.08, y: centre + sweep))
        path.addLine(to: CGPoint(x: baseX - reach * 0.08, y: centre - sweep))
        path.closeSubpath()
        return path
    }
}
