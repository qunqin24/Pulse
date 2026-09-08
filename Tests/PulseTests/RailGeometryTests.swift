import Foundation
import Testing
@testable import Pulse

/// Every ring the rail draws has to be reachable.
///
/// The panel window gates every press on its grab area, which it measures
/// from the rail's length. When that length was counted in accounts while the
/// view drew it in slots, the two differed by one the moment a provider was
/// split — and the shortfall lands at the far end, so the *last* ring was the
/// one that stopped responding.
///
/// Two halves, because the first alone is not enough: the count is what
/// shipped broken, and geometry asserted on two hand-built numbers cannot
/// catch a wrong count — the numbers *are* the bug. So `shownSlotCount` is
/// called here for real, and the rest pins the geometry that makes agreeing on
/// it sufficient, at every edge and both dock states.
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

    /// The count itself — which is what actually shipped broken.
    ///
    /// The window measured its rects from `shownAccounts.count` while the view
    /// drew `entries.count`; with a split account those differ by one. Asserting
    /// geometry on two hand-built numbers cannot catch that, because the numbers
    /// are the bug. This calls the function the window really uses, with a
    /// reading that really splits, and fails against `shownAccounts.count`.
    @MainActor
    @Test("The window counts rings, not accounts")
    func theWindowCountsRingsNotAccounts() {
        let antigravity = AccountKey(.antigravity)
        let settings = AppSettings(
            enabledAccounts: [antigravity.id],
            splitAccounts: [antigravity.id]
        )

        let split = ProviderUsage(
            account: antigravity,
            windows: [
                UsageWindow(id: "g5", kind: .fiveHour, scope: "Gemini", usedFraction: 0.4, windowSeconds: 18_000, resetsAt: nil),
                UsageWindow(id: "t5", kind: .fiveHour, scope: "Third-party", usedFraction: 0.2, windowSeconds: 18_000, resetsAt: nil),
            ],
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: nil
        )

        #expect(settings.shownAccounts == [antigravity])
        // One account, two rings. `shownAccounts.count` would answer 1.
        #expect(FloatingPanelController.shownSlotCount(settings, usage: { _ in split }) == 2)

        // And the rail the window sizes from is a ring longer for it.
        let short = DockLayout.size(for: 1, on: .vertical, docked: true)
        let real = DockLayout.size(for: 2, on: .vertical, docked: true)
        #expect(real.height > short.height)
    }

    /// The same account before its first reading lands: nothing to split by, so
    /// the window counts one — and must go back to two when the reading arrives,
    /// which is what `PanelPlacement.railLengthChanged()` exists to notice.
    @MainActor
    @Test("The count follows the reading, not the settings")
    func theCountFollowsTheReading() {
        let antigravity = AccountKey(.antigravity)
        let settings = AppSettings(
            enabledAccounts: [antigravity.id],
            splitAccounts: [antigravity.id]
        )

        let loading = ProviderUsage.unavailable(antigravity, reason: .loading)
        #expect(FloatingPanelController.shownSlotCount(settings, usage: { _ in loading }) == 1)
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
