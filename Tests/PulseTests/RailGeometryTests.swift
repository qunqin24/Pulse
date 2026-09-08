import Foundation
import Testing
@testable import Pulse

/// Every ring the rail draws has to be reachable.
///
/// The panel window gates every press on its grab area, which it measures
/// from the rail's length. When that length was counted in accounts while the
/// view drew it in slots, the two differed by one the moment a provider was
/// split — and the shortfall lands at the far end, so the *last* ring was the
/// one that stopped responding. The counts agree again; these pin the geometry
/// that makes agreement sufficient, at every edge and both dock states.
@Suite("Rail geometry")
struct RailGeometryTests {
    private static let edges: [PanelEdge] = [.left, .right, .top]
    /// One, a handful, and a rail longer than any real one.
    private static let counts = [1, 2, 3, 7, 15, 16]

    /// Where the rail's own hit area sits, for a rail of `count` rings.
    private func rail(_ count: Int, _ edge: PanelEdge, docked: Bool) -> CGRect {
        PanelHitArea.rail(
            edge: edge,
            railSize: DockLayout.size(for: count, on: edge.axis, docked: docked),
            railTop: 0,
            railLeading: 0
        )
    }

    /// The centre of ring `index`, by the same sum the hit test uses.
    private func ringCentre(_ index: Int, in rail: CGRect, _ edge: PanelEdge, docked: Bool) -> CGPoint {
        let along = DockLayout.firstRingAlong(docked: docked, on: edge.axis)
            + CGFloat(index) * DockLayout.ringStep(on: edge.axis)
        let across = DockLayout.ringCentreAcross(on: edge.axis)
        return edge.isVertical
            ? CGPoint(x: rail.minX + across, y: rail.minY + along)
            : CGPoint(x: rail.minX + along, y: rail.minY + across)
    }

    @MainActor
    @Test("Every ring's centre lies inside the rail it is drawn on")
    func everyRingCentreIsInsideTheRail() {
        for edge in Self.edges {
            for docked in [true, false] {
                for count in Self.counts {
                    let area = rail(count, edge, docked: docked)

                    for index in 0..<count {
                        let centre = ringCentre(index, in: area, edge, docked: docked)
                        #expect(
                            area.contains(centre),
                            "ring \(index) of \(count), \(edge) edge, docked \(docked)"
                        )
                    }
                }
            }
        }
    }

    /// The bug in the flesh: the *whole* ring has to be reachable, not just
    /// its centre. At Loose spacing the old undersized rail left only the top
    /// 4pt of the last ring live, which reads as a ring that ignores clicks
    /// rather than as one that is half outside its own hit area.
    @MainActor
    @Test("The last ring is wholly inside the rail, at every scale")
    func theLastRingIsNotClippedByTheRail() {
        let radius = DockLayout.ringDiameter / 2

        for edge in Self.edges {
            for docked in [true, false] {
                for count in Self.counts {
                    let area = rail(count, edge, docked: docked)
                    let centre = ringCentre(count - 1, in: area, edge, docked: docked)
                    let ring = CGRect(
                        x: centre.x - radius, y: centre.y - radius,
                        width: radius * 2, height: radius * 2
                    )

                    #expect(
                        area.contains(ring),
                        "last of \(count) rings, \(edge) edge, docked \(docked): \(ring) escapes \(area)"
                    )
                }
            }
        }
    }

    /// A rail measured one ring short is what shipped. Pinning it here means a
    /// future change that reintroduces an account-based count fails a test
    /// rather than a click.
    @MainActor
    @Test("A rail measured one ring short cannot reach its last ring")
    func anUndersizedRailMissesItsLastRing() {
        // The drawn rail has one more ring than the window was told about.
        let drawn = 4
        let area = rail(drawn - 1, .right, docked: true)
        let centre = ringCentre(drawn - 1, in: rail(drawn, .right, docked: true), .right, docked: true)

        #expect(!area.contains(centre))
    }

    @MainActor
    @Test("Every ring answers the hit test as itself")
    func everyRingHitTestsToItsOwnSlot() {
        let slots = (0..<5).map { RailSlot(AccountKey(Provider.allCases[$0])) }

        for edge in Self.edges {
            for docked in [true, false] {
                let area = rail(slots.count, edge, docked: docked)

                for (index, slot) in slots.enumerated() {
                    let centre = ringCentre(index, in: area, edge, docked: docked)
                    let hit = PanelHitArea.slot(
                        at: centre, edge: edge, slots: slots,
                        railTop: 0, railLeading: 0, docked: docked
                    )

                    #expect(hit == slot, "ring \(index), \(edge) edge, docked \(docked)")
                }
            }
        }
    }
}
