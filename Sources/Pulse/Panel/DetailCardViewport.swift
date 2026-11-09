// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Divides a bounded card between its fixed summary and scrolling details.
/// No window state: opening a longer reading must never resize the panel.
struct DetailCardViewport: Equatable {
    let height: CGFloat
    let detailHeight: CGFloat
    let fixesSummary: Bool
    let scrolls: Bool

    /// Placement reserves the screen budget before any card opens. Only a
    /// top/bottom pointer consumes vertical room; unplaced previews use a fallback.
    static func bodyLimit(maxHeight: CGFloat?, fallbackHeight: CGFloat, pointerHeight: CGFloat) -> CGFloat {
        guard let maxHeight, maxHeight.isFinite else { return max(fallbackHeight, 0) }
        return max(maxHeight - pointerHeight, 0)
    }

    init(limit: CGFloat, summary: CGFloat, details: CGFloat, spacing: CGFloat, padding: CGFloat,
         minimumDetailHeight: CGFloat) {
        let limit = max(limit, 0)
        let summary = max(summary, 0)
        let details = max(details, 0)
        let padding = max(padding, 0)
        let gap = details > 0 ? max(spacing, 0) : 0
        let natural = padding * 2 + summary + gap + details
        height = min(natural, limit)
        // At an extremely short top/bottom placement even the summary cannot
        // fit. Let the whole card scroll rather than clip an unscrollable title.
        fixesSummary = summary + padding * 2 + gap + min(details, max(minimumDetailHeight, 0)) <= limit
        let room = max(limit - padding * 2 - summary - gap, 0)
        detailHeight = fixesSummary ? min(details, room) : height
        scrolls = natural > limit
    }
}

/// Prefers the visible part of the granted window, but never pushes a card
/// outside the window when that intersection is too short to contain it.
/// The tip follows the ring independently of the base's corner clearance.
struct DetailCardAnchor {
    let origin: CGFloat
    let pointer: CGFloat

    init(ring: CGFloat, length: CGFloat, lowerBound: CGFloat, upperBound: CGFloat, panelLength: CGFloat) {
        let lastInPanel = max(panelLength - length, 0)
        // A visible ring must remain within the card's pointer edge, even
        // when a freely placed rail overlaps the menu bar or a side Dock.
        let firstForRing = min(max(ring - length, 0), lastInPanel)
        let lastForRing = min(max(ring, 0), lastInPanel)
        let first = min(max(lowerBound, firstForRing), lastForRing)
        let last = min(max(upperBound - length, first), lastForRing)
        origin = min(max(ring - length / 2, first), last)
        pointer = ring - origin
    }
}
