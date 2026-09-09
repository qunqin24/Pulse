import AppKit

/// Watches which display the pointer is on, so the panel can be moved onto it.
///
/// **The pointer is the whole definition of "active" here.** Not the key
/// window, not the frontmost app's frame: an app can be focused on one display
/// while the person is working on another, and reading window positions would
/// need Accessibility permission to be wrong in a more expensive way. Where the
/// pointer is, is where the hand is.
///
/// Sampled on a timer rather than driven by events, for the same reason
/// `PanelPointerWatcher` samples: a global mouse-moved monitor stops firing
/// over this app's own windows, and a pointer that crosses onto another display
/// and comes to rest there emits nothing further to notice. A position can be
/// asked for at any moment and is never out of date.
///
/// Only ever moves the one panel there is. Nothing here creates a second one.
@MainActor
final class ActiveDisplayFollower {
    /// The pointer has settled on a display other than the one it was last
    /// reported on, named as `PanelScreen` names them.
    ///
    /// Return `false` to say the move could not be made now — while the panel
    /// is under the hand, say — and the same display is offered again on the
    /// next tick rather than being remembered as already handled.
    var onEnter: ((String) -> Bool)?

    /// Slow enough to cost nothing, fast enough that the rail has arrived by
    /// the time the pointer has crossed the bezel and reached anything worth
    /// clicking on. The panel is not being animated along with the pointer:
    /// this fires once per crossing, not once per frame.
    private static let interval: TimeInterval = 0.25

    private var timer: Timer?
    private var lastIdentifier: String?

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        // Keep sampling while a menu or another modal run loop is up: crossing
        // to the other display with the menu bar's menu open is still crossing.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastIdentifier = nil
    }

    /// Forget where the pointer was last seen, so the next tick reports it
    /// again even though it has not moved.
    ///
    /// For when the displays themselves changed: unplugging the monitor the
    /// panel was on leaves the pointer exactly where it was, which this would
    /// otherwise read as "nothing to do" while the panel sits on a fallback
    /// screen nobody chose.
    func forgetLastDisplay() {
        lastIdentifier = nil
    }

    private func sample() {
        // One display cannot be departed from. Cheaper than asking where the
        // pointer is, and it is the common case.
        guard NSScreen.screens.count > 1 else { return }

        guard
            let screen = PanelScreen.containing(NSEvent.mouseLocation),
            let identifier = PanelScreen.identifier(of: screen),
            identifier != lastIdentifier
        else { return }

        if onEnter?(identifier) == false { return }
        lastIdentifier = identifier
    }
}
