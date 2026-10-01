import Foundation
import Testing
@testable import Pulse

/// A rail lying across the screen and standing free.
///
/// It is the top dock's shape placed the way the upright floating rail is, so
/// what has to hold is the part neither of those already pins: the card opens
/// into the roomier half, the window keeps the rail where the ratios put it,
/// and nothing about it is mistaken for the top dock.
@Suite("Free across")
struct FreeAcrossTests {
    /// A 16" laptop: 1169pt tall, 35pt of menu bar, 72pt of Dock.
    private let visible = CGRect(x: 0, y: 72, width: 1800, height: 1058)
    private var panel: CGSize { FloatingPanelController.Layout.size(for: .top) }
    private var rail: CGSize { DockLayout.size(for: 5, on: .horizontal, docked: false) }

    private func layout(_ h: Double, _ v: Double) -> (PanelPlacement, PanelPlacement.Layout) {
        let placement = PanelPlacement(dock: .floating(.horizontal), horizontalRatio: h, verticalRatio: v)
        return (placement, placement.layout(in: visible, topEdge: 1169, panel: panel, rail: rail))
    }

    @Test("The card opens down in the top half and up in the bottom half")
    func cardOpensIntoTheRoomierHalf() {
        #expect(layout(0.5, 0.2).0.edge == .top)
        #expect(layout(0.5, 0.8).0.edge == .bottom)
        #expect(layout(0.5, 0.8).0.edge.axis == .horizontal)
    }

    @Test("The window hangs down from the rail, or stands up from it")
    func windowFollowsTheCard() {
        let (_, high) = layout(0.5, 0.2)
        #expect(abs(high.frame.maxY - high.railOrigin.y) < 0.01)

        let (_, low) = layout(0.5, 0.8)
        #expect(abs(low.frame.minY - (low.railOrigin.y - rail.height)) < 0.01)
    }

    @Test("The rail goes where the ratios say, kept off the sides")
    func railIsPlacedByBothRatios() {
        for v in [0.0, 0.3, 0.7, 1.0] {
            for h in [0.0, 0.5, 1.0] {
                let (_, placed) = layout(h, v)
                let railBottom = placed.railOrigin.y - rail.height
                #expect(abs(railBottom - (visible.minY + (1 - v) * (visible.height - rail.height))) < 0.01)
                #expect(placed.railOrigin.x >= visible.minX + PanelPlacement.dockDistance)
                #expect(placed.railOrigin.x + rail.width <= visible.maxX - PanelPlacement.dockDistance)
                #expect(visible.contains(placed.frame), "h \(h), v \(v): \(placed.frame)")
            }
        }
    }

    @Test("The two free placements are different docks, and neither is docked")
    func freePlacementsAreDistinct() {
        #expect(PanelDock.floating(.horizontal) != .floating(.vertical))
        #expect(!PanelDock.floating(.horizontal).isDocked)
        #expect(PanelDock.floating(.horizontal).edge == nil)
    }
}
