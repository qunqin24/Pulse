import Foundation
import Testing
@testable import Pulse

@Suite("Notch docking geometry")
@MainActor
struct NotchGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    private let visible = CGRect(x: 0, y: 72, width: 1800, height: 1058)
    private let notch = CGRect(x: 791, y: 1131, width: 221, height: 38)

    @Test("The housing comes from the system areas, including an offset display")
    func housingCoordinates() {
        for origin in [CGPoint.zero, CGPoint(x: -1800, y: 400)] {
            let frame = screen.offsetBy(dx: origin.x, dy: origin.y)
            let left = CGRect(x: frame.minX, y: frame.maxY - 38, width: 791, height: 38)
            let right = CGRect(x: frame.minX + 1012, y: left.minY, width: 788, height: 38)
            #expect(PanelScreen.notch(in: frame, topInset: 38, left: left, right: right)
                    == notch.offsetBy(dx: origin.x, dy: origin.y))
            #expect(PanelScreen.notch(in: frame, topInset: 0, left: left, right: right) == nil)
            #expect(PanelScreen.notch(in: frame, topInset: 38, left: nil, right: right) == nil)
            #expect(PanelScreen.notch(in: frame, topInset: 38, left: left, right: left) == nil)
        }
    }

    @Test("Notch docking reaches the physical screen top and keeps controls below the housing")
    func attachedLayout() {
        let placement = PanelPlacement(dock: .edge(.top), horizontalRatio: 0.2)
        placement.notch = notch
        let panel = FloatingPanelController.Layout.size(for: .top, notchSize: notch.size)
        for count in [1, 6, 12] {
            let rail = DockLayout.size(for: count, on: .horizontal)
            let layout = placement.layout(in: visible, topEdge: visible.maxY, panel: panel, rail: rail)
            let offsets = PanelPlacement.offsets(forRailTopLeft: layout.railOrigin, in: layout.frame, rail: rail)
            #expect(abs(layout.railOrigin.x + rail.width / 2 - notch.midX) < 0.01)
            #expect(layout.railOrigin.y == notch.minY)
            #expect(layout.frame.maxY == screen.maxY)
            #expect(offsets.top == notch.height)
            let localRail = CGRect(x: offsets.leading, y: offsets.top, width: rail.width, height: rail.height)
            let surface = PanelHitArea.notchSurface(rail: localRail, notchSize: notch.size)
            #expect(surface.minY == 0)
            #expect(surface.contains(localRail))
            // The rail ends the surface: the housing sits above the rings,
            // and nothing is added under them to answer it.
            #expect(surface.maxY == localRail.maxY)
            #expect(surface.width >= notch.width)
            #expect(panel.width >= surface.width)
            #expect(layout.frame.size == panel)
            #expect(placement.horizontalRatio == 0.2)
        }
    }

    @Test("Without a notch, top docking still uses the chosen horizontal position")
    func ordinaryTopLayout() {
        let placement = PanelPlacement(dock: .edge(.top), horizontalRatio: 0.2)
        let panel = FloatingPanelController.Layout.size(for: .top)
        let rail = DockLayout.size(for: 6, on: .horizontal)
        let layout = placement.layout(in: visible, topEdge: screen.maxY, panel: panel, rail: rail)
        #expect(layout.railOrigin.x == (visible.width - rail.width) * 0.2)
        #expect(layout.railOrigin.y == screen.maxY)
        #expect(layout.frame.maxY == screen.maxY)
    }

    @Test("The housing costs its own height and nothing else, at every scale", arguments: [false, true])
    func paddingBudget(roundEnds: Bool) {
        let previousEnds = PanelMetrics.usesRoundEnds
        PanelMetrics.useRoundEnds(roundEnds)
        defer { PanelMetrics.useRoundEnds(previousEnds) }
        let previousSize = PanelSize.allCases.first { $0.scale == PanelMetrics.scale } ?? .default
        let previousLabels = PanelMetrics.topRailShowsPercentages
        defer {
            PanelMetrics.use(previousSize)
            PanelMetrics.showTopPercentages(previousLabels)
        }
        for size in PanelSize.allCases {
            PanelMetrics.use(size)
            for labels in [false, true] {
                PanelMetrics.showTopPercentages(labels)
                let railSize = DockLayout.size(for: 6, on: .horizontal)
                let rail = CGRect(x: 100, y: notch.height, width: railSize.width, height: railSize.height)
                let surface = PanelHitArea.notchSurface(rail: rail, notchSize: notch.size)
                #expect(surface.maxY == rail.maxY)
                #expect(surface.minY == 0)
                #expect(surface.midX == rail.midX)
                let ordinary = FloatingPanelController.Layout.size(for: .top)
                let attached = FloatingPanelController.Layout.size(for: .top, notchSize: notch.size)
                #expect(abs(attached.height - ordinary.height - notch.height) < 0.01)
                let cardTop = surface.maxY + DetailCardLayout.horizontalGap
                #expect(abs(attached.height - cardTop - DetailCardLayout.pointerWidth - DetailCardLayout.maximumHeight) < 0.01)
                // The old window budgets remain intact away from a notch.
                #expect(ordinary.height == railSize.height + DetailCardLayout.horizontalGap
                        + DetailCardLayout.pointerWidth + DetailCardLayout.maximumHeight)
                for edge in [PanelEdge.left, .right] {
                    #expect(FloatingPanelController.Layout.size(for: edge, notchSize: notch.size)
                            == FloatingPanelController.Layout.size(for: edge))
                }
            }
        }
    }

    /// What the view and the hit test hand the shape: the surface plus the
    /// room the fillets sweep into at the screen edge.
    private func drawn(_ rail: CGSize) -> CGRect {
        PanelHitArea.notchSurface(rail: CGRect(origin: .zero, size: rail), notchSize: notch.size)
            .insetBy(dx: -DockLayout.flareWidth, dy: 0)
    }

    @Test("The collapsed surface is empty; the expanded one is filled to the screen top")
    func silhouette() {
        for count in [1, 6, 12] {
            let rail = DockLayout.size(for: count, on: .horizontal)
            let rect = drawn(rail)
            #expect(NotchBerthShape(notchSize: notch.size, openness: 0).path(in: rect).isEmpty)
            for progress in [0.1, 0.5, 1.0] {
                let path = NotchBerthShape(notchSize: notch.size, openness: progress).path(in: rect)
                #expect(path.boundingRect.minY == -notch.height)
                #expect(path.boundingRect.maxY <= rect.maxY + 0.01)
                #expect(path.boundingRect.width <= rect.width + 0.01)
                let top = -notch.height + 0.001
                #expect(path.contains(CGPoint(x: rect.midX, y: top)))
                // The old neck and flared shoulder failed here: the pixels
                // beside the housing must be filled all the way to the top.
                #expect(path.contains(CGPoint(x: path.boundingRect.minX + 1, y: top)))
                #expect(path.contains(CGPoint(x: path.boundingRect.maxX - 1, y: top)))
            }
        }
    }

    /// The fillet into the screen edge, which a rail that is not on a notch
    /// has always had. Losing it leaves two square corners against the top of
    /// the screen — nothing fails, the rail just stops looking like the rail.
    @Test("The surface sweeps out into the screen edge instead of meeting it square", arguments: [false, true])
    func filletsReachTheScreenEdge(roundEnds: Bool) {
        let previousEnds = PanelMetrics.usesRoundEnds
        PanelMetrics.useRoundEnds(roundEnds)
        defer { PanelMetrics.useRoundEnds(previousEnds) }

        for count in [1, 6, 12] {
            let rect = drawn(DockLayout.size(for: count, on: .horizontal))
            let path = NotchBerthShape(notchSize: notch.size).path(in: rect)
            let top = rect.minY
            let body = rect.insetBy(dx: DockLayout.flareWidth, dy: 0)

            // Wider at the screen edge than at the body, by the whole flare.
            #expect(abs(path.boundingRect.width - body.width - DockLayout.flareWidth * 2) < 0.01)

            // Concave, not a chamfer: at the body's own edge the fillet has
            // already left the screen edge, so a point just outside the body
            // is filled at the very top and empty further down.
            let outside = body.minX - 1
            #expect(path.contains(CGPoint(x: outside, y: top + 0.5)))
            #expect(!path.contains(CGPoint(x: outside, y: top + DockLayout.flareHeight + 1)))
        }
    }

    @Test("The rectangular surface leaves every existing ring entirely inside it", arguments: [false, true])
    func ringsRemainInside(roundEnds: Bool) {
        let previousEnds = PanelMetrics.usesRoundEnds
        PanelMetrics.useRoundEnds(roundEnds)
        defer { PanelMetrics.useRoundEnds(previousEnds) }
        for count in [1, 2, 6, 12] {
            let rail = DockLayout.size(for: count, on: .horizontal)
            let path = NotchBerthShape(notchSize: notch.size).path(in: drawn(rail))
            for index in 0..<count {
                let x = DockLayout.firstRingAlong(on: .horizontal)
                    + CGFloat(index) * DockLayout.ringStep(on: .horizontal)
                let y = DockLayout.ringCentreAcross(on: .horizontal)
                for step in 0..<24 {
                    let angle = Double(step) * .pi / 12
                    let radius = DockLayout.ringDiameter / 2 * 1.08
                    #expect(path.contains(CGPoint(x: x + cos(angle) * radius, y: y + sin(angle) * radius)))
                }
            }
        }
    }
}
