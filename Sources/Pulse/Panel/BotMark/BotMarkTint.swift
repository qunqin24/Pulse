import AppKit
import SwiftUI

/// What colour a provider's bot mark is drawn in.
///
/// The mark stands where the provider's logo stood, so its colour is
/// **identity**, not status — the same job the logo was doing. That is what
/// keeps it clear of `UsageTint`, where colour means one thing only: how
/// close a limit is. The ring around the mark still carries that, unchanged.
///
/// **It is still a risk worth naming.** Rings were drawn in brand colours
/// once and it went badly, because Claude Code's orange-red at 3% used looked
/// like a warning. A brand colour on the disc is a weaker version of the same
/// hazard: the ring is the thing that turns red, but a red-ish body inside a
/// green ring is two colours disagreeing. If that reads badly on a real rail,
/// the fix is this table, not the ring.
enum BotMarkTint {
    /// Brand colours, for the providers that have one.
    ///
    /// Nil is not "unknown", it is **monochrome by design** — OpenAI, Cursor,
    /// GitHub, xAI, Ollama, OpenCode and the rest draw a black-or-white glyph
    /// and nothing else. Those get a colour of Pulse's own, see `assigned`.
    ///
    /// Marked below are the values taken from a product's palette with less
    /// certainty than the others; they are one line each to correct. Kimi's
    /// blue, Z.ai having no colour of its own, and MiniMax's red are what the
    /// person maintaining this app says they are.
    static func brand(for provider: Provider) -> Color? {
        switch provider {
        case .claudeCode: BotMarkPalette.rgb(0xD97757)
        case .deepSeek: BotMarkPalette.rgb(0x4D6BFE)
        case .volcengine: BotMarkPalette.rgb(0x1664FF)
        // Best-guess brand colours: right family, exact value unconfirmed.
        case .minimax, .minimaxCN: BotMarkPalette.rgb(0xE8483F)
        // Best-guess brand colours: right family, exact value unconfirmed.
        case .antigravity: BotMarkPalette.rgb(0x4285F4)
        case .glmCoding: BotMarkPalette.rgb(0x3A7BF7)
        case .kimiCode: BotMarkPalette.rgb(0x7AA5FF)
        // Xiaomi's orange. The MiMo console is black-on-white, but the parent
        // brand's colour is the one a reader recognises on a rail.
        case .xiaomiMiMo: BotMarkPalette.rgb(0xFF6900)
        case .codex, .kiro, .cursor, .openCodeGo, .ollamaCloud, .zai,
             .copilot, .grok, .grokBot, .commandCode, .devin:
            nil
        }
    }

    /// Colours for a rail, in the order its rings are drawn.
    ///
    /// Some providers are monochrome by design and carry no colour at all.
    /// A row of white bots is a rail you cannot read — the mark is
    /// the thing that says *which* ring this is, and identical is the one
    /// thing it must not be — so those are dealt a colour of Pulse's own.
    ///
    /// **Dealt across the rail, not fixed per provider.** Three fixed schemes
    /// were tried and each left two similar colours side by side. A hash of
    /// the provider id collided outright: three ids on one entry and three on
    /// another. Dealing a fixed palette in declaration order fixed that and
    /// still sat a dealt amber next to Claude Code's clay, because a hue can
    /// only be kept away from its neighbours if you know who its neighbours
    /// are — and the rail shows *enabled* accounts, so that is not knowable
    /// until it is drawn. Here it is: each ring takes the free hue furthest
    /// from the ring before it and from every brand colour on the rail.
    ///
    /// The cost is that adding or removing a provider can recolour the ones
    /// after it. Nothing is stored against these colours, and a mark is not a
    /// reading, so the trade is worth it — the alternative is two rings that
    /// look the same, which is the whole failure this is avoiding.
    /// `chosen` is a colour somebody picked for that ring, which is fixed:
    /// it is used as it is, and the rings beside it are dealt away from its
    /// hue exactly as they are from a brand colour.
    static func deal(over providers: [Provider], chosen: [Color?] = []) -> [Color] {
        let brands = providers.enumerated().map { index, provider in
            (index < chosen.count ? chosen[index] : nil) ?? brand(for: provider)
        }
        let dealtCount = brands.filter { $0 == nil }.count
        guard dealtCount > 0 else { return brands.map { lifted($0!) } }

        // Walking the wheel with a stride coprime to its size visits every
        // colour exactly once, so the rail cannot repeat one. Which stride and
        // where it starts are the only freedom there is, and there are forty
        // of those — few enough to simply try them all and keep the one whose
        // worst neighbouring pair is furthest apart. Greedy choice was tried
        // first and ran out of colours near the end of a long rail, which is
        // exactly where it then had no choice but to put two blues together.
        var best: (score: Double, stride: Int, rotation: Int)?
        for stride in 1..<paletteSize where coprime(stride, paletteSize) {
            for rotation in 0..<paletteSize {
                let score = worstNeighbour(brands: brands, stride: stride, rotation: rotation)
                if best == nil || score > best!.score { best = (score, stride, rotation) }
            }
        }
        let winner = best ?? (score: 0, stride: 3, rotation: 0)

        var index = 0
        return brands.map { brand in
            if let brand { return lifted(brand) }
            let slot = (winner.rotation + winner.stride * index) % paletteSize
            index += 1
            return wheel[slot]
        }
    }

    /// How close the nearest pair of neighbouring rings would be, for one way
    /// of dealing the wheel.
    ///
    /// **Two brand colours side by side do not count.** Claude Code's clay
    /// next to MiniMax's red is what those two brands are; the mark cannot fix
    /// it and should not be scored on it. Every pair with a dealt colour in it
    /// is ours.
    private static func worstNeighbour(brands: [Color?], stride: Int, rotation: Int) -> Double {
        var hues: [(hue: Double, isBrand: Bool)] = []
        var index = 0
        for brand in brands {
            if let brand {
                hues.append((hue(of: brand), true))
            } else {
                hues.append((wheelHues[(rotation + stride * index) % paletteSize], false))
                index += 1
            }
        }
        var worst = 360.0
        for position in hues.indices.dropLast() {
            let first = hues[position]
            let second = hues[position + 1]
            if first.isBrand && second.isBrand { continue }
            worst = min(worst, separation(first.hue, second.hue))
        }
        return worst
    }

    /// A single provider's colour, for anywhere a whole rail is not in hand —
    /// previews, and the settings pane's own sample.
    static func body(for provider: Provider) -> Color {
        deal(over: [provider])[0]
    }

    /// Whether this provider draws a colour of Pulse's own rather than a brand
    /// one. Only the tests and the doc comments care.
    static func isDealt(_ provider: Provider) -> Bool {
        brand(for: provider) == nil
    }

    private static let paletteSize = 11

    /// The wheel, solved once: evenly spaced hues, each at the same
    /// luminance. `dealt(at:)` is a bisection, and a rail is dealt on every
    /// pass of the dock's body.
    private static let wheel: [Color] = (0..<paletteSize).map { dealt(at: $0) }
    private static let wheelHues: [Double] = wheel.map(hue(of:))

    private static func coprime(_ first: Int, _ second: Int) -> Bool {
        var a = first
        var b = second
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a == 1
    }

    private static func separation(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private static func hue(of colour: Color) -> Double {
        guard let base = NSColor(colour).usingColorSpace(.sRGB) else { return 0 }
        return Double(base.hueComponent) * 360
    }

    /// The nth dealt colour: an even hue, levelled to one brightness.
    ///
    /// Evenly spaced hues — the widest any fixed-size wheel can be. Which
    /// ring gets which is `deal(over:)`'s business; this is only the wheel it
    /// draws from.
    /// Hand-picked hexes were tried first and put two greens 49° apart, two
    /// blues 14° and two ambers 13°, which is what a palette chosen by eye
    /// tends to do. Placing the hues only in the gaps the brand colours leave
    /// was worse than either: brands hold the blue and the red ends, so
    /// avoiding them crowds all ten into yellow-green-through-purple at 24°
    /// apart — more near-identical greens, not fewer.
    ///
    /// Levelling matters as much as spacing. At one fixed lightness a yellow
    /// comes out glaring and a blue nearly black, so each hue's lightness is
    /// solved for the same perceived luminance instead.
    private static func dealt(at index: Int) -> Color {
        // 27° is the offset that keeps the wheel as a whole furthest from the
        // hues the brand colours already hold.
        let hue = (27 + 360 * Double(index % paletteSize) / Double(paletteSize))
        return levelled(hue: hue, saturation: 0.68, target: 0.62)
    }

    /// The lightness that puts this hue at `target` luminance, by bisection.
    ///
    /// Twenty steps is far more than the eye needs and costs nothing: the
    /// wheel above is a `static let`, so this runs ten times per process.
    private static func levelled(hue: Double, saturation: Double, target: Double) -> Color {
        var low = 0.0
        var high = 1.0
        var colour = BotMarkPalette.hsl(degrees: hue, saturation: saturation, lightness: 0.5)
        for _ in 0..<20 {
            let middle = (low + high) / 2
            colour = BotMarkPalette.hsl(degrees: hue, saturation: saturation, lightness: middle)
            if luminance(of: colour) < target { low = middle } else { high = middle }
        }
        return colour
    }

    /// Dark eyes on a light body, light eyes on a dark one. At 16pt contrast
    /// between the two is the entire face.
    static func eyes(on body: Color) -> Color {
        luminance(of: body) > 0.55 ? Color(white: 0.06) : Color(white: 0.97)
    }

    /// Where a body colour stops reading against the disc behind it.
    private static let luminanceFloor = 0.42

    private static func lifted(_ colour: Color) -> Color {
        let value = luminance(of: colour)
        guard value < luminanceFloor, value.isFinite else { return colour }
        guard let base = NSColor(colour).usingColorSpace(.sRGB) else { return colour }
        // Enough of the way to white to clear the floor, and no further.
        let amount = min(1, (luminanceFloor - value) / max(1 - value, 0.0001))
        return Color(red: BotMath.mix(base.redComponent, 1, amount),
                     green: BotMath.mix(base.greenComponent, 1, amount),
                     blue: BotMath.mix(base.blueComponent, 1, amount))
    }

    private static func luminance(of colour: Color) -> Double {
        guard let base = NSColor(colour).usingColorSpace(.sRGB) else { return 1 }
        return 0.2126 * base.redComponent
            + 0.7152 * base.greenComponent
            + 0.0722 * base.blueComponent
    }
}
