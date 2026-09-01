import AppKit
import CoreGraphics

/// Which display the panel is on, and how to name one so it can be found again.
///
/// **A display's `CGDirectDisplayID` is not an identity.** It is handed out
/// afresh when a screen is attached, so it changes between sessions, when a
/// monitor is unplugged and plugged back in, and when a laptop is docked. Its
/// UUID does not — that is the same physical display every time — so that is
/// what gets stored.
enum PanelScreen {
    /// A name for this display that survives a reboot and a reconnection.
    static func identifier(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
        else { return nil }

        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))
        else { return nil }

        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    /// The display that name refers to, or nil if it isn't attached right now.
    ///
    /// Nil is the ordinary answer, not an error: people unplug monitors. The
    /// caller falls back to a screen that exists rather than leaving the panel
    /// parked in a space nobody can see.
    static func screen(withIdentifier identifier: String?) -> NSScreen? {
        guard let identifier else { return nil }
        return NSScreen.screens.first { self.identifier(of: $0) == identifier }
    }

    /// The display a point is on.
    ///
    /// `frame`, not `visibleFrame` — the menu bar and the Dock are part of a
    /// screen for the purpose of "which one is the pointer over", and a
    /// pointer up in the menu bar must not read as being on no screen at all.
    static func containing(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
