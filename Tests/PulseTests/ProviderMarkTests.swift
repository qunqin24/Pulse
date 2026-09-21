import AppKit
import Testing
@testable import Pulse

/// Every provider's mark has to actually draw something.
///
/// `LobeIconStore.image(named:)` returns non-nil for any file `NSImage` can
/// open, which is not the same as one that renders. An SVG that parses but
/// puts no ink down — a stroke the rasteriser drops, a path outside the
/// viewBox, `fill="none"` with nothing else — comes back as a perfectly valid
/// image, is set `isTemplate`, and draws a **blank disc** on the rail. Nothing
/// fails; the row simply loses its mark.
///
/// That is not hypothetical: it is the check the mark before this one was
/// switched by hand (`cc077d3`, "Checked it renders solid through NSImage at
/// the size the rail draws it, since a blank template image fails silently"),
/// and doing it by hand is what stops happening.
@Suite("Provider marks")
struct ProviderMarkTests {
    /// Roughly the rail's icon at 2x: `centreDiameter * UsageRingView.iconScale`
    /// lands near 22pt, and a mark that survives this survives the larger
    /// sizes the card and the spend pane draw it at.
    private static let pixels = 44

    /// Well under the thinnest mark bundled today — `commandcode` covers
    /// 22.4% at this size, and the set runs up to 52.7% — and far above
    /// anything a blank or near-blank raster could reach.
    private static let minimumInk = 8.0

    /// Share of the square the mark actually covers, as a percentage.
    @MainActor
    private func inkCoverage(of image: NSImage) -> Double {
        let px = Self.pixels
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: px * 4, bitsPerPixel: 32
        )!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)))
        NSGraphicsContext.restoreGraphicsState()

        var inked = 0
        for y in 0..<px {
            for x in 0..<px where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.08 {
                inked += 1
            }
        }
        return Double(inked) / Double(px * px) * 100
    }

    @MainActor
    @Test("Every provider's mark loads and draws ink at rail size")
    func everyMarkDrawsSomething() {
        for provider in Provider.allCases {
            let name = provider.iconResource
            guard let image = LobeIconStore.image(named: name) else {
                Issue.record("\(provider.rawValue): no mark named \(name).svg in the bundle")
                continue
            }

            let ink = inkCoverage(of: image)
            #expect(
                ink >= Self.minimumInk,
                "\(provider.rawValue): \(name).svg covers \(String(format: "%.1f", ink))% at \(Self.pixels)px — it loads but barely draws"
            )
        }
    }
}
