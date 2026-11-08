import AppKit
import SwiftUI
import Testing
@testable import Pulse

extension PanelGlobalsSuite {
    @MainActor
    @Suite("Screen-bounded detail card anchors")
    struct DetailCardAnchorTests {
        @Test("The screen budget is reserved before opening on every edge")
        func reservation() {
            for height: CGFloat in [855, 1_400, 1_123.5] {
                let visible = CGRect(x: -1_800, y: 52, width: 1_800, height: height)
                let budget = DetailCardLayout.screenHeightLimit(in: visible)
                #expect(budget == height * 0.75)
                for edge in [PanelEdge.left, .right, .top, .bottom] {
                    for docked in [false, true] {
                        for notch: CGSize? in [nil, CGSize(width: 210, height: 38)] {
                            let panel = FloatingPanelController.Layout.size(
                                for: edge, notchSize: notch, capacity: 1, docked: docked, cardHeight: budget)
                            let fallback = FloatingPanelController.Layout.size(
                                for: edge, notchSize: notch, capacity: 1, docked: docked)
                            #expect(panel.width == fallback.width)
                            #expect(panel.width == panel.width.rounded(.up))
                            #expect(panel.height == panel.height.rounded(.up))
                            let expected = edge.isVertical
                                ? max(DockLayout.maximumLength(on: .vertical, capacity: 1), budget)
                                : DockLayout.thickness(on: .horizontal, docked: docked)
                                    + (notch?.height ?? 0) + DetailCardLayout.horizontalGap
                                    + DetailCardLayout.pointerWidth + budget
                            #expect(panel.height == expected.rounded(.up))
                        }
                    }
                }
            }
        }

        @Test("Visible card bounds retain offsets in an oversized granted frame")
        func grantedBounds() {
            let visible = CGRect(x: -1_800, y: -200, width: 1_800, height: 855)
            let frame = CGRect(x: -1_900, y: -300, width: 800, height: 1_200)
            let bounds = PanelPlacement.cardBounds(visible: visible, panelFrame: frame)
            #expect(bounds == CGRect(x: 100, y: 245, width: 700, height: 855))
            let global = CGRect(x: frame.minX + bounds.minX, y: frame.maxY - bounds.maxY,
                                width: bounds.width, height: bounds.height)
            #expect(global == frame.intersection(visible))
            let placement = PanelPlacement()
            placement.setPanelFrame(frame, visible: visible)
            #expect(placement.panelSize == frame.size)
            #expect(placement.cardPlacementBounds == bounds)
            #expect(PanelPlacement.cardBounds(visible: visible, panelFrame: frame.offsetBy(dx: 3_000, dy: 0)) == .zero)
        }

        @Test("Clamped first and last rings retain the same tip anchor")
        func endRings() {
            let lower: CGFloat = 245
            let upper: CGFloat = 1_100
            for length: CGFloat in [80, 300, 855 * 0.75] {
                for ring in [lower + 3, lower + 100, (lower + upper) / 2, upper - 3] {
                    let anchor = DetailCardAnchor(ring: ring, length: length, lowerBound: lower,
                                                  upperBound: upper, panelLength: upper)
                    #expect(anchor.origin >= lower)
                    #expect(anchor.origin + length <= upper)
                    #expect(abs(anchor.origin + anchor.pointer - ring) < 0.001)
                }
            }
        }

        @Test("A side Dock cannot push a free card outside its granted window")
        func sideDock() {
            let size = PanelSize.allCases.first { $0.scale == PanelMetrics.scale } ?? .default
            PanelMetrics.use(PanelSize.default)
            defer { PanelMetrics.use(size) }
            for screenX: CGFloat in [0, -1_440] {
                for left in [false, true] {
                    let screen = CGRect(x: screenX, y: 0, width: 1_440, height: 900)
                    let visible = CGRect(x: screenX + (left ? 80 : 0), y: 0, width: 1_360, height: 875)
                    let placement = PanelPlacement(dock: .floating(.horizontal),
                        horizontalRatio: left ? 0 : 1, verticalRatio: 0.4)
                    placement.snapsToEdges = false
                    let rail = DockLayout.size(for: 1, on: .horizontal, docked: false)
                    let panel = FloatingPanelController.Layout.size(for: placement.edge, capacity: 1,
                        docked: false, cardHeight: DetailCardLayout.screenHeightLimit(in: visible))
                    let layout = placement.layout(in: placement.room(visible: visible, screen: screen),
                        topEdge: screen.maxY, panel: panel, rail: rail)
                    placement.setPanelFrame(layout.frame, visible: visible)
                    let bounds = PanelPlacement.cardBounds(visible: visible, panelFrame: layout.frame)
                    #expect(bounds.width < DetailCardLayout.width)
                    let offsets = PanelPlacement.offsets(forRailTopLeft: layout.railOrigin,
                                                        in: layout.frame, rail: rail)
                    let ring = offsets.leading + DockLayout.firstRingAlong(docked: false, on: .horizontal)
                    let anchor = DetailCardAnchor(ring: ring, length: DetailCardLayout.width,
                        lowerBound: bounds.minX, upperBound: bounds.maxX, panelLength: panel.width)
                    #expect(anchor.origin >= 0)
                    #expect(anchor.origin + DetailCardLayout.width <= panel.width)
                    #expect(abs(anchor.origin + anchor.pointer - ring) < 0.001)
                }
            }
        }

        @Test("A narrow or empty visible intersection still keeps the card inside the panel")
        func narrowIntersection() {
            for bounds: (CGFloat, CGFloat) in [(80, 250), (0, 170), (0, 0), (100, 270)] {
                for ring: CGFloat in [10, 125, 240] {
                    let anchor = DetailCardAnchor(ring: ring, length: 250,
                        lowerBound: bounds.0, upperBound: bounds.1, panelLength: 250)
                    #expect(anchor.origin == 0)
                    #expect(anchor.origin + anchor.pointer == ring)
                }
            }
        }

        @Test("Rings outside the usable strip still keep their arrow inside the card")
        func ringOutsideUsableStrip() {
            for bounds: (CGFloat, CGFloat) in [(80, 400), (0, 320), (0, 0)] {
                for ring: CGFloat in [10, 125, 390] {
                    let anchor = DetailCardAnchor(ring: ring, length: 250,
                        lowerBound: bounds.0, upperBound: bounds.1, panelLength: 400)
                    #expect(anchor.origin >= 0 && anchor.origin + 250 <= 400)
                    #expect(anchor.pointer >= 0 && anchor.pointer <= 250)
                    #expect(anchor.origin + anchor.pointer == ring)
                }
            }
        }

        @Test("Actual tail paths aim at near-corner rings in every direction")
        func tailTips() throws {
            let previous = PanelMetrics.usesRoundEnds
            defer { PanelMetrics.useRoundEnds(previous) }
            for round in [false, true] {
                PanelMetrics.useRoundEnds(round)
                for edge in [PanelEdge.left, .right, .top, .bottom] {
                    for length: CGFloat in [6, 80, 855 * 0.75] {
                        let rect = CGRect(origin: .zero, size: edge.isVertical
                            ? CGSize(width: 270, height: length) : CGSize(width: length, height: 270))
                        for anchor in [CGFloat(0), 0.3, 3, length - 3, length - 0.3, length] {
                            let shape = UsageBubbleShape(edge: edge, pointerCenter: anchor,
                                cornerRadius: 20, pointerWidth: 20, pointerHeight: 40)
                            var tips: [CGPoint] = []
                            shape.only(.tail).path(in: rect).cgPath.applyWithBlock { element in
                                if element.pointee.type == .addCurveToPoint {
                                    tips.append(element.pointee.points[2])
                                }
                            }
                            let tip = try #require(tips.first)
                            let expected: CGPoint = switch edge {
                            case .left: CGPoint(x: 0, y: anchor)
                            case .right: CGPoint(x: rect.width, y: anchor)
                            case .top: CGPoint(x: anchor, y: 0)
                            case .bottom: CGPoint(x: anchor, y: rect.height)
                            }
                            #expect(abs(tip.x - expected.x) < 0.001)
                            #expect(abs(tip.y - expected.y) < 0.001)
                            let bounds = shape.path(in: rect).boundingRect
                            #expect(bounds.minX >= -0.001 && bounds.minY >= -0.001)
                            #expect(bounds.maxX <= rect.maxX + 0.001 && bounds.maxY <= rect.maxY + 0.001)
                        }
                    }
                }
            }
        }
    }
}
