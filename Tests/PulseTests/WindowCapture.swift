import AppKit
import SwiftUI

/// Pictures of a real window, for the screenshot suites that need what only
/// the window server draws: a title bar and sidebar, or Liquid Glass, which
/// `cacheDisplay` and `ImageRenderer` both leave out.
///
/// The window goes on screen far outside every display and is read back by its
/// number, which needs no screen-recording grant for the process's own window
/// and shows nothing to the person running the tests.
@MainActor
enum WindowCapture {
    /// A window drawn as the active one — coloured traffic lights, a sidebar at
    /// full strength, glass that is clear rather than frosted — without making
    /// the test runner the active app.
    final class ActiveWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
        @objc(_hasActiveAppearance) func hasActiveAppearance() -> Bool { true }
        @objc(_hasActiveAppearanceIgnoringKeyFocus) func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    }

    static let offscreen = NSPoint(x: -12_000, y: -12_000)

    /// `CGWindowListCreateImage`, looked up at run time: it is deprecated in
    /// the SDK, and a warning is a failure here, but it is still the one call
    /// that reads back the process's own window without a grant. Just this
    /// window, without its shadow, at the backing scale.
    static func image(of window: NSWindow) -> CGImage? {
        typealias Create = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: Create.self)
        let includingWindow: UInt32 = 1 << 3
        let ignoreFraming: UInt32 = 1 << 0, bestResolution: UInt32 = 1 << 3
        return create(.null, includingWindow, UInt32(window.windowNumber), ignoreFraming | bestResolution)?.takeRetainedValue()
    }

    /// Writes a borderless, transparent window holding `view` at its own size.
    static func write<V: View>(_ view: V, to url: URL) throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = ActiveWindow(contentRect: CGRect(origin: offscreen, size: size), styleMask: .borderless,
                                  backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Closed below while its ordering-in animation may still be running:
        // released with the window, that animation crashed the next picture.
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = host
        window.setFrameOrigin(offscreen)
        window.orderFrontRegardless()
        defer { window.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        guard let image = image(of: window),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }
}
