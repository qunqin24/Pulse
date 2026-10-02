// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The collapsed alert cue for a top-docked rail whose ordinary sliver is
/// replaced by the Mac's camera housing. It sits immediately under the
/// physical notch and stays narrower than it, so it reads as the housing's
/// status edge rather than as a second rail.
struct NotchAlertShape: Shape {
    var notchSize: CGSize

    func path(in rect: CGRect) -> Path {
        let height = max(2 * PanelMetrics.scale, 1)
        let sideInset = min(12 * PanelMetrics.scale, notchSize.width / 4)
        let width = max(notchSize.width - sideInset * 2, height)
        let indicator = CGRect(
            x: rect.midX - width / 2,
            y: min(rect.minY + notchSize.height, rect.maxY - height),
            width: width,
            height: height
        )
        return Path(roundedRect: indicator, cornerRadius: height / 2)
    }
}
