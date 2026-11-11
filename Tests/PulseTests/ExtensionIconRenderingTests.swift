import AppKit
import SwiftUI
import Testing
@testable import Pulse

@Suite("Extension icon rendering")
@MainActor
struct ExtensionIconRenderingTests {
    /// In-memory artwork with an opaque background and an opaque interior
    /// glyph: a template would flatten these into one solid silhouette.
    private func png(background: NSColor = .white, glyph: NSColor = .black,
                     width: Int = 16, height: Int = 16) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let background = try #require(background.usingColorSpace(.sRGB))
        let glyph = try #require(glyph.usingColorSpace(.sRGB))
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(glyph.cgColor)
        context.fill(CGRect(x: CGFloat(width / 4), y: CGFloat(height / 4),
                            width: CGFloat(width / 2), height: CGFloat(height / 2)))
        let bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func render<Content: View>(_ content: Content) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    /// Menu marks are AppKit drawing-handler images. Rasterize both the mark
    /// and its PNG reference into sRGB; ImageRenderer can bridge the handler
    /// through a display-profile bitmap while keeping the PNG in sRGB.
    private func render(_ image: NSImage, scale: Int) throws -> NSBitmapImageRep {
        let width = Int(image.size.width) * scale
        let height = Int(image.size.height) * scale
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        return NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    }

    private func color(_ bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
        try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }

    private func account(_ id: String = UUID().uuidString) -> AccountKey {
        AccountKey(.pulseExtension, slot: id)
    }

    /// A store holding `data` for `account`, as a scan would leave it.
    private func icons(_ pairs: [(AccountKey, Data)]) -> ExtensionIcons {
        let icons = ExtensionIcons()
        icons.update(from: pairs.map { found(id: $0.0.slot, data: $0.1) })
        return icons
    }

    @Test("Each account draws its own PNG, found by the account alone")
    func perAccountIcons() throws {
        let red = try png(background: .red)
        let blue = try png(background: .blue)
        let first = account(), second = account()
        let store = icons([(first, red), (second, blue)])
        let firstImage = try #require(store.image(for: first))
        let secondImage = try #require(store.image(for: second))
        #expect(firstImage !== secondImage)
        #expect(!firstImage.isTemplate)
        #expect(store.image(for: account()) == nil)
        #expect(store.image(for: AccountKey(.codex)) == nil)

        let redBitmap = try render(LobeIconView(account: first, size: 16).environment(\.extensionIcons, store))
        let blueBitmap = try render(LobeIconView(account: second, size: 16).environment(\.extensionIcons, store))
        #expect(try color(redBitmap, x: 1, y: 1).redComponent > 0.9)
        #expect(try color(redBitmap, x: 1, y: 1).blueComponent < 0.1)
        #expect(try color(blueBitmap, x: 1, y: 1).blueComponent > 0.9)
        #expect(try color(blueBitmap, x: 1, y: 1).redComponent < 0.1)
    }

    @Test("A rescan keeps an unchanged image and decodes changed bytes at the same path")
    func rescan() throws {
        let red = try png(background: .red)
        let blue = try png(background: .blue)
        let key = account()
        let store = icons([(key, red)])
        let original = try #require(store.image(for: key))

        store.update(from: [found(id: key.slot, data: Data(red))])
        #expect(store.image(for: key) === original)

        store.update(from: [found(id: key.slot, data: blue)])
        let replaced = try #require(store.image(for: key))
        #expect(replaced !== original)

        store.update(from: [])
        #expect(store.image(for: key) == nil)
    }

    @Test("Missing or undecodable data, or no store, uses the template provider mark")
    func fallback() throws {
        let bundled = try #require(LobeIconStore.image(for: .pulseExtension))
        #expect(bundled.isTemplate)
        #expect(bundled.size == NSSize(width: 256, height: 256))

        let invalid = account(), empty = account()
        let store = icons([(invalid, Data("not a PNG".utf8)), (empty, Data())])
        #expect(store.image(for: invalid) == nil)
        #expect(store.image(for: empty) == nil)

        let menuFallback = try #require(MenuBarReading.markImage(for: invalid, size: 15, icons: store))
        #expect(menuFallback.isTemplate)
        let noStore = try #require(MenuBarReading.markImage(for: invalid, size: 15))
        #expect(noStore.isTemplate)
    }

    @Test("PNG interiors retain their original colours under a foreground tint")
    func originalColors() throws {
        let key = account()
        let store = icons([(key, try png())])
        let bitmap = try render(
            LobeIconView(account: key, size: 16)
                .foregroundStyle(Color.red)
                .environment(\.extensionIcons, store)
        )
        let background = try color(bitmap, x: 1, y: 1)
        let glyph = try color(bitmap, x: 8, y: 8)
        #expect(background.redComponent > 0.9)
        #expect(background.greenComponent > 0.9)
        #expect(background.blueComponent > 0.9)
        #expect(glyph.redComponent < 0.1)
        #expect(glyph.greenComponent < 0.1)
        #expect(glyph.blueComponent < 0.1)
        #expect(background.alphaComponent > 0.9)
        #expect(glyph.alphaComponent > 0.9)
    }

    @Test("Menu artwork fits its square without stretching or mutating the stored image", arguments: [1, 2])
    func menuSizing(scale: Int) throws {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let key = account()
        let store = icons([(key, try png(background: red, glyph: red, width: 16, height: 8))])
        let source = try #require(store.image(for: key))
        let sourceSize = source.size
        let mark = try #require(MenuBarReading.markImage(for: key, size: 16, icons: store))
        let smaller = try #require(MenuBarReading.markImage(for: key, size: 8, icons: store))
        #expect(mark !== source)
        #expect(mark.size == NSSize(width: 16, height: 16))
        #expect(smaller.size == NSSize(width: 8, height: 8))
        #expect(source.size == sourceSize)
        #expect(!source.isTemplate)
        #expect(!mark.isTemplate)
        #expect(!smaller.isTemplate)

        let bitmap = try render(mark, scale: scale)
        let centre = try color(bitmap, x: 8 * scale, y: 8 * scale)
        let original = try render(source, scale: scale)
        let expected = try color(original, x: 8 * scale, y: 4 * scale)
        #expect(centre.redComponent > 0.9)
        #expect(abs(centre.redComponent - expected.redComponent) < 0.02)
        #expect(abs(centre.greenComponent - expected.greenComponent) < 0.02)
        #expect(abs(centre.blueComponent - expected.blueComponent) < 0.02)
        #expect(try color(bitmap, x: 8 * scale, y: scale).alphaComponent < 0.1)
        #expect(try color(bitmap, x: scale, y: 8 * scale).alphaComponent > 0.9)
    }

    @Test("Settings keep the store in step with each scan, per account")
    func settingsUpdateTheStore() throws {
        let (defaults, cleanup) = TestDefaults.make("extensionIconRendering")
        defer { cleanup() }
        let settings = AppSettings(enabledAccounts: [], defaults: defaults)
        let red = try png(background: .red)
        let blue = try png(background: .blue)
        let first = found(id: UUID().uuidString, data: red)
        let second = found(id: UUID().uuidString, data: blue)
        settings.apply(ExtensionCatalog.Scan(extensions: [first, second]))
        let original = try #require(settings.extensionIcons.image(for: first.account))
        #expect(settings.extensionIcons.image(for: second.account) != nil)

        settings.apply(ExtensionCatalog.Scan(extensions: [found(id: first.id, data: blue), second]))
        let replaced = try #require(settings.extensionIcons.image(for: first.account))
        #expect(replaced !== original)

        settings.apply(ExtensionCatalog.Scan(extensions: [second]))
        #expect(settings.extensionIcons.image(for: first.account) == nil)
    }

    private func found(id: String, data: Data) -> PulseExtension {
        let directory = FileManager.default.temporaryDirectory.appending(path: id)
        return PulseExtension(id: id, name: "Extension", directory: directory,
                              executable: directory.appending(path: "run"), timeout: 5, iconData: data)
    }
}
