import Foundation
import Testing
@testable import Pulse

/// Following the pointer onto another display moves the one panel there is.
///
/// The move is only ever a change of *which* display: both ratios are
/// fractions of one screen's usable area, so carrying them across unchanged is
/// what puts the rail in the same place on the new display as it held on the
/// old one. Anything that rewrote them here would slide the rail every time
/// the pointer crossed a bezel.
@Suite("Following the active display")
struct ActiveDisplayTests {
    private func placement(
        on display: String? = "A",
        pressed: Bool = false,
        dragging: Bool = false
    ) -> (PanelPlacement, () -> Int) {
        let placement = PanelPlacement(
            dock: .floating,
            horizontalRatio: 0.3,
            verticalRatio: 0.7,
            display: display
        )
        placement.isPressed = pressed
        placement.isDragging = dragging

        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        placement.onChange = { counter.value += 1 }
        return (placement, { counter.value })
    }

    @Test("Crossing to another display moves the panel and keeps its place on it")
    func crossingMovesThePanel() {
        let (placement, calls) = placement()

        #expect(placement.move(toDisplay: "B"))
        #expect(placement.display == "B")
        #expect(calls() == 1)
        #expect(placement.horizontalRatio == 0.3)
        #expect(placement.verticalRatio == 0.7)
        #expect(placement.dock == .floating)
    }

    /// The pointer resting on the display the panel is already on is the
    /// ordinary case, six times a second. It must not re-place the window, and
    /// it must not read as a refusal either, or the follower would offer the
    /// same display again on every tick forever.
    @Test("Staying on the same display does nothing, and is not a refusal")
    func stayingPutIsQuiet() {
        let (placement, calls) = placement()

        #expect(placement.move(toDisplay: "A"))
        #expect(calls() == 0)
    }

    @Test("A held panel refuses the move")
    func aHeldPanelIsLeftAlone() {
        let (placement, calls) = placement(pressed: true)

        #expect(placement.move(toDisplay: "B") == false)
        #expect(placement.display == "A")
        #expect(calls() == 0)
    }

    /// A refusal is reported rather than swallowed so the display stays on
    /// offer: the follower only remembers a display once the move was taken.
    @Test("Letting go lets the move happen")
    func releasingLetsItThrough() {
        let (placement, calls) = placement(pressed: true, dragging: true)
        #expect(placement.move(toDisplay: "B") == false)

        placement.isDragging = false
        placement.isPressed = false

        #expect(placement.move(toDisplay: "B"))
        #expect(placement.display == "B")
        #expect(calls() == 1)
    }

    /// Docked is the position most people are in, and the dock is a property of
    /// the edge rather than of the screen — so it crosses unchanged.
    @Test("A docked panel arrives docked to the same edge")
    func aDockedPanelKeepsItsEdge() {
        let placement = PanelPlacement(dock: .edge(.left), horizontalRatio: 0, verticalRatio: 0.25, display: "A")

        #expect(placement.move(toDisplay: "B"))
        #expect(placement.dock == .edge(.left))
        #expect(placement.edge == .left)
        #expect(placement.verticalRatio == 0.25)
    }
}
