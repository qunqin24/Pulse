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

    @Test("Different PNG content stays isolated even with the same provider fallback")
    func contentIsolation() throws {
        let red = try png(background: .red)
        let blue = try png(background: .blue)
        let first = try #require(LobeIconStore.image(for: .pulseExtension, iconData: red))
        let second = try #require(LobeIconStore.image(for: .pulseExtension, iconData: blue))
        #expect(first !== second)
        #expect(LobeIconStore.image(for: .pulseExtension, iconData: Data(red)) === first)
        // The external cache is independent of the fallback's resource name.
        #expect(LobeIconStore.image(for: .codex, iconData: red) === first)
        #expect(!first.isTemplate)
        #expect(!second.isTemplate)

        let redBitmap = try render(LobeIconView(provider: .pulseExtension, size: 16, iconData: red))
        let blueBitmap = try render(LobeIconView(provider: .pulseExtension, size: 16, iconData: blue))
        #expect(try color(redBitmap, x: 1, y: 1).redComponent > 0.9)
        #expect(try color(redBitmap, x: 1, y: 1).blueComponent < 0.1)
        #expect(try color(blueBitmap, x: 1, y: 1).blueComponent > 0.9)
        #expect(try color(blueBitmap, x: 1, y: 1).redComponent < 0.1)
    }

    @Test("Missing or undecodable data uses the existing template provider mark")
    func fallback() throws {
        let bundled = try #require(LobeIconStore.image(for: .pulseExtension))
        let invalid = Data("not a PNG".utf8)
        #expect(LobeIconStore.image(for: .pulseExtension, iconData: invalid) === bundled)
        #expect(LobeIconStore.image(for: .pulseExtension, iconData: Data()) === bundled)
        #expect(bundled.isTemplate)
        #expect(LobeIconView(provider: .pulseExtension, size: 16).iconData == nil)
        #expect(LobeIconView(resource: Provider.pulseExtension.iconResource, size: 16).iconData == nil)

        let menuFallback = try #require(MenuBarReading.markImage(for: .pulseExtension, size: 15, iconData: invalid))
        #expect(menuFallback.isTemplate)
        #expect(bundled.size == NSSize(width: 256, height: 256))
    }

    @Test("PNG interiors retain their original colours under a foreground tint")
    func originalColors() throws {
        let bitmap = try render(
            LobeIconView(provider: .pulseExtension, size: 16, iconData: png())
                .foregroundStyle(Color.red)
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

    @Test("Menu artwork fits its square without stretching or mutating the cached image", arguments: [1, 2])
    func menuSizing(scale: Int) throws {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let data = try png(background: red, glyph: red, width: 16, height: 8)
        let source = try #require(LobeIconStore.image(for: .pulseExtension, iconData: data))
        let sourceSize = source.size
        let mark = try #require(MenuBarReading.markImage(for: .pulseExtension, size: 16, iconData: data))
        let smaller = try #require(MenuBarReading.markImage(for: .pulseExtension, size: 8, iconData: data))
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

    @Test("Account metadata keeps independent snapshots and changes rail equality after a rescan")
    func accountSnapshots() throws {
        let (defaults, cleanup) = TestDefaults.make("extensionIconRendering")
        defer { cleanup() }
        let settings = AppSettings(enabledAccounts: [], defaults: defaults)
        let red = try png(background: .red)
        let blue = try png(background: .blue)
        let first = found(id: UUID().uuidString, data: red)
        let second = found(id: UUID().uuidString, data: blue)
        settings.apply(ExtensionCatalog.Scan(extensions: [first, second]))
        let snapshot = settings.pulseExtension(for: first.account)?.iconData
        #expect(snapshot == red)
        #expect(settings.pulseExtension(for: second.account)?.iconData == blue)
        #expect(settings.pulseExtension(for: AccountKey(.codex))?.iconData == nil)

        let usage = ProviderUsage.unavailable(first.account, reason: .loading)
        let original = RailEntry(usage: usage, headline: nil, slot: RailSlot(first.account),
                                 title: first.name, windowClock: nil, figure: nil, second: nil,
                                 iconData: snapshot)
        settings.apply(ExtensionCatalog.Scan(extensions: [found(id: first.id, data: blue), second]))
        var updated = original
        updated.iconData = settings.pulseExtension(for: first.account)?.iconData
        #expect(snapshot == red)
        #expect(updated.iconData == blue)
        #expect(updated.id == original.id)
        #expect(updated != original)
    }

    @Test("Existing ring, card and settings row constructors default to no PNG metadata")
    func optionalMetadataDefaults() {
        let usage = ProviderUsage.unavailable(AccountKey(.pulseExtension), reason: .loading)
        let ring = UsageRingView(provider: .pulseExtension, usedFraction: nil, diameter: 36, lineWidth: 4,
                                 secondFraction: nil, secondIsSpent: false)
        let card = UsageDetailCard(usage: usage, edge: .right, pointerCenter: 0)
        let row = SettingsRow("Extension", icon: Provider.pulseExtension.iconResource) { EmptyView() }
        let entry = RailEntry(usage: usage, headline: nil, slot: RailSlot(usage.account),
                              title: "Extension", windowClock: nil, figure: nil, second: nil)
        #expect(ring.iconData == nil)
        #expect(card.iconData == nil)
        #expect(row.iconData == nil)
        #expect(entry.iconData == nil)
    }

    private func found(id: String, data: Data) -> PulseExtension {
        let directory = FileManager.default.temporaryDirectory.appending(path: id)
        return PulseExtension(id: id, name: "Extension", directory: directory,
                              executable: directory.appending(path: "run"), timeout: 5, iconData: data)
    }
}
