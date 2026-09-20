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

    @Test("Notch docking closes the menu-bar seam and keeps the window fixed")
    func attachedLayout() {
        let placement = PanelPlacement(dock: .edge(.top), horizontalRatio: 0.2)
        placement.notch = notch
        let panel = FloatingPanelController.Layout.size(for: .top)
        for count in [1, 6, 12] {
            let rail = DockLayout.size(for: count, on: .horizontal)
            let layout = placement.layout(in: visible, topEdge: visible.maxY, panel: panel, rail: rail)
            let offsets = PanelPlacement.offsets(forRailTopLeft: layout.railOrigin, in: layout.frame, rail: rail)
            #expect(abs(layout.railOrigin.x + rail.width / 2 - notch.midX) < 0.01)
            #expect(layout.railOrigin.y + DockLayout.notchShoulderHeight == notch.minY)
            #expect(layout.frame.maxY == notch.minY)
            #expect(offsets.top == DockLayout.notchShoulderHeight)
            let localRail = CGRect(x: offsets.leading, y: offsets.top, width: rail.width, height: rail.height)
            let surface = PanelHitArea.notchSurface(rail: localRail)
            #expect(surface.minY == 0)
            #expect(surface.contains(localRail))
            #expect(surface.maxY == localRail.maxY)
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

    @Test("The collapsed notch surface draws nothing; the open neck never exceeds the housing")
    func silhouette() {
        for count in [1, 6, 12] {
            let rail = DockLayout.size(for: count, on: .horizontal)
            let rect = CGRect(x: 0, y: -DockLayout.notchShoulderHeight,
                              width: rail.width, height: rail.height + DockLayout.notchShoulderHeight)
            #expect(NotchBerthShape(notchWidth: notch.width, openness: 0).path(in: rect).isEmpty)
            for progress in [0.1, 0.5, 1.0] {
                let path = NotchBerthShape(notchWidth: notch.width, openness: progress).path(in: rect)
                #expect(path.boundingRect.minY == -DockLayout.notchShoulderHeight)
                #expect(path.boundingRect.maxY <= rail.height + 0.01)
                #expect(path.boundingRect.width <= rail.width + 0.01)
                let top = -DockLayout.notchShoulderHeight + 0.001
                #expect(path.contains(CGPoint(x: rail.width / 2, y: top)))
                #expect(!path.contains(CGPoint(x: rail.width / 2 + notch.width / 2 + 1, y: top)))
            }
        }
    }

    @Test("The new shoulder leaves every existing ring entirely inside the surface")
    func ringsRemainInside() {
        for count in [1, 2, 6, 12] {
            let rail = DockLayout.size(for: count, on: .horizontal)
            let path = NotchBerthShape(notchWidth: notch.width).path(in:
                CGRect(x: 0, y: -DockLayout.notchShoulderHeight,
                       width: rail.width, height: rail.height + DockLayout.notchShoulderHeight))
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
