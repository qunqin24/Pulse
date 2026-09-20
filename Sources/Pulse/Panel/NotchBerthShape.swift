import SwiftUI

/// A single surface from the housing's bottom edge to the existing rail.
/// The shoulder lives above the rail so its rings and card keep their layout.
struct NotchBerthShape: Shape {
    var notchWidth: CGFloat
    var openness: CGFloat = 1

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(openness, 0), 1)
        guard progress > 0 else { return Path() }
        let neck = min(notchWidth, rect.width)
        let width = neck + (rect.width - neck) * progress
        let left = rect.midX - width / 2
        let right = rect.midX + width / 2
        let top = rect.minY
        let shoulder = DockLayout.notchShoulderHeight * progress
        let bottom = top + rect.height * progress
        let radius = min(DockLayout.cornerRadius,
                         max(rect.height - DockLayout.notchShoulderHeight, 0) / 2, width / 2) * progress
        let neckLeft = rect.midX - neck / 2
        let neckRight = rect.midX + neck / 2
        let k: CGFloat = 0.5522847498

        var path = Path()
        path.move(to: CGPoint(x: neckLeft, y: top))
        path.addLine(to: CGPoint(x: neckRight, y: top))
        path.addCurve(to: CGPoint(x: right, y: top + shoulder),
                      control1: CGPoint(x: neckRight, y: top + shoulder / 2),
                      control2: CGPoint(x: right, y: top + shoulder / 2))
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addCurve(to: CGPoint(x: right - radius, y: bottom),
                      control1: CGPoint(x: right, y: bottom - radius * (1 - k)),
                      control2: CGPoint(x: right - radius * (1 - k), y: bottom))
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addCurve(to: CGPoint(x: left, y: bottom - radius),
                      control1: CGPoint(x: left + radius * (1 - k), y: bottom),
                      control2: CGPoint(x: left, y: bottom - radius * (1 - k)))
        path.addLine(to: CGPoint(x: left, y: top + shoulder))
        path.addCurve(to: CGPoint(x: neckLeft, y: top),
                      control1: CGPoint(x: left, y: top + shoulder / 2),
                      control2: CGPoint(x: neckLeft, y: top + shoulder / 2))
        path.closeSubpath()
        return path
    }
}
