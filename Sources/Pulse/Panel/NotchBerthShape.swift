import SwiftUI

/// An extension of the camera housing, flush with the physical screen top.
/// The rings retain their layout below the housing; only the surface grows.
struct NotchBerthShape: Shape {
    var notchSize: CGSize
    var openness: CGFloat = 1

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(openness, 0), 1)
        guard progress > 0 else { return Path() }
        let width = notchSize.width + (rect.width - notchSize.width) * progress
        let height = notchSize.height + (rect.height - notchSize.height) * progress
        let bounds = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        return UnevenRoundedRectangle(
            bottomLeadingRadius: DockLayout.cornerRadius,
            bottomTrailingRadius: DockLayout.cornerRadius,
            style: .continuous
        ).path(in: bounds)
    }
}
