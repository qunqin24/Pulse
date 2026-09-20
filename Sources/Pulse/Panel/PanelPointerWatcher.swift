import AppKit
import SwiftUI

/// Reports where the pointer is inside the panel, by sampling its position
/// rather than by listening for enter/exit events.
///
/// The location is given in the tracked view's own coordinates, with the
/// origin at its top-left corner to match SwiftUI, or `nil` when the pointer
/// is outside the panel altogether. Callers decide what counts as "still on
/// the panel" — the window's frame is not a useful answer to that, because
/// most of this panel is transparent space the content does not occupy.
///
/// Enter/exit events proved unusable for this. Views appearing, disappearing
/// and animating under a stationary pointer fire spurious exits; acting on
/// one closes the card, which puts the pointer back on a ring, which opens it
/// again — an endless open/close loop. Sampling the pointer's actual position
/// cannot be knocked out of sync by animation, by a view sliding underneath,
/// or by an event that never arrives.
///
/// Attach as a background of a view that fills the panel.
struct PanelPointerWatcher: NSViewRepresentable {
    let onChange: (CGPoint?) -> Void

    func makeNSView(context: Context) -> WatcherView {
        let view = WatcherView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: WatcherView, context: Context) {
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: WatcherView, coordinator: ()) {
        view.stop()
    }

    final class WatcherView: NSView {
        var onChange: ((CGPoint?) -> Void)?

        /// Matches SwiftUI's top-left origin, so the reported point can be
        /// compared against SwiftUI frames without flipping it first.
        override var isFlipped: Bool { true }

        /// Fast enough to feel immediate when the pointer leaves, slow enough
        /// to be free.
        private static let interval: TimeInterval = 0.15

        private var timer: Timer?
        private var lastReported: CGPoint??

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? stop() : start()
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            lastReported = nil
        }

        private func start() {
            guard timer == nil else { return }

            let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            // Keep sampling while menus or other modal run loops are up.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        private func sample() {
            guard let window else { return }

            let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let local = convert(inWindow, from: nil)
            let point = bounds.contains(local) ? local : nil

            // Only speak up when something actually changed, so a resting
            // pointer doesn't churn SwiftUI state six times a second.
            if let lastReported, Self.isSame(lastReported, point) { return }

            lastReported = point
            onChange?(point)
        }

        private static func isSame(_ a: CGPoint?, _ b: CGPoint?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (a?, b?): abs(a.x - b.x) < 1 && abs(a.y - b.y) < 1
            default: false
            }
        }
    }
}
