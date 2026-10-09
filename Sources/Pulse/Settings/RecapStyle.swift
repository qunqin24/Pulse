// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The recap cards' palette and the small pieces every card shares.
///
/// Flat colour and type, nothing else: no gradients, no blur, no shadow, no
/// material. Everything here has to render through `ImageRenderer`, which is
/// how a card becomes a PNG, so nothing here leans on glass or AppKit.
///
/// Lime is the app icon's accent and appears only as a **fill** — a highlight
/// bar, a tile, a pill — never as text on the light paper, where it cannot be
/// read.
enum RecapColor {
    static let paper = Color(recap: 0xF5F5F1)
    static let white = Color(recap: 0xFFFFFF)
    static let hairline = Color(recap: 0xE4E4DD)
    static let ink = Color(recap: 0x1B1B1E)
    static let lime = Color(recap: 0xC8F03C)
    static let secondary = Color(recap: 0x6E6E68)
    static let tertiary = Color(recap: 0x8A8A83)
    static let faint = Color(recap: 0xA3A39C)
    static let rule = Color(recap: 0xD6D6CF)
    static let track = Color(recap: 0xEFEFE9)
    static let bodyInk = Color(recap: 0x3C3C38)
    static let limeInk = Color(recap: 0x3F4D12)
    /// The calendar's four steps from a light day to a heavy one; the fifth,
    /// the busiest day, is ink.
    static let heat: [Color] = [Color(recap: 0xEEF7C9), Color(recap: 0xDDF290), lime, Color(recap: 0x9DC41A), ink]
    static let heatZero = Color(recap: 0xEDEDE7)
    /// Bars for a ranked list: lime for the first, ink for the second, then
    /// quieter greys.
    static let ranks: [Color] = [lime, ink, Color(recap: 0x5C5C57), Color(recap: 0x9A9A93), Color(recap: 0xC9C9C2)]
    static let restBar = Color(recap: 0xDADAD3)
    static let restLabel = Color(recap: 0x9A9A93)
    static let darkRest = Color(recap: 0x55554F)
}

extension Color {
    /// 0xRRGGBB in sRGB.
    init(recap hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    /// The system face — SF Pro, with the system's CJK fallback for the
    /// characters it lacks — or its monospaced design where the mockups use a
    /// mono for labels and digits.
    static func recap(_ size: CGFloat, _ weight: Font.Weight = .regular, mono: Bool = false) -> Font {
        .system(size: size, weight: weight, design: mono ? .monospaced : .default)
    }
}

// MARK: - Text pieces

/// Marks the words in a localized sentence that the card sets apart.
///
/// A translated sentence puts its numbers wherever that language wants them,
/// so the card cannot split the sentence around them in code. The value is
/// wrapped in private-use characters before it goes into the key's `%@`, and
/// `RecapRichText` finds them again in whatever order the translation chose.
enum RecapEmphasis {
    static let open = "\u{E000}"
    static let close = "\u{E001}"

    static func mark(_ value: String) -> String { open + value + close }

    static func segments(_ text: String) -> [(text: String, emphasised: Bool)] {
        var result: [(String, Bool)] = []
        var buffer = ""
        var emphasised = false
        for character in text {
            switch String(character) {
            case open:
                if !buffer.isEmpty { result.append((buffer, false)) }
                buffer = ""
                emphasised = true
            case close:
                if !buffer.isEmpty { result.append((buffer, true)) }
                buffer = ""
                emphasised = false
            default:
                buffer.append(character)
            }
        }
        if !buffer.isEmpty { result.append((buffer, emphasised)) }
        return result
    }

    /// The sentence with the markers taken out.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: open, with: "").replacingOccurrences(of: close, with: "")
    }
}

/// A sentence with some of its words set in bold, on a lime bar where the
/// card asks for one.
struct RecapRichText: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .regular
    var color: Color = RecapColor.ink
    var emphasisWeight: Font.Weight = .bold
    var highlights = true
    var lineSpacing: CGFloat = 0

    var body: some View {
        Text(attributed)
            .lineSpacing(lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for segment in RecapEmphasis.segments(text) {
            // A no-break space either side stands in for the bar's padding.
            // **One bar is one piece.** Korean breaks between "2025" and
            // "년", and a bar split over two lines read as two highlights:
            // a word joiner between every character keeps it whole.
            let unbroken = segment.text.map(String.init).joined(separator: "\u{2060}")
                .replacingOccurrences(of: " ", with: "\u{00A0}")
            var piece = AttributedString(segment.emphasised && highlights ? "\u{00A0}\(unbroken)\u{00A0}" : segment.text)
            piece.font = .recap(size, segment.emphasised ? emphasisWeight : weight)
            piece.foregroundColor = color
            if segment.emphasised, highlights { piece.backgroundColor = RecapColor.lime }
            result.append(piece)
        }
        return result
    }
}

/// A hero number with its unit set smaller beside it ("8.4" "亿"), both on one
/// baseline.
extension Text {
    /// `string` set tight, every character but the last: **`.tracking` on a
    /// `Text` is taken after the last glyph too**, so a negative value pulls
    /// the frame in past the last digit's ink — and the text is drawn inside
    /// its frame, so the right of a 9 or a 5 was cut off flat. Leaving the last
    /// character untracked keeps its whole advance, and the frame holds it.
    init(tight string: String, tracking: CGFloat) {
        var text = AttributedString(string)
        if !text.characters.isEmpty {
            let last = text.characters.index(before: text.endIndex)
            text[text.startIndex..<last].tracking = tracking
        }
        self.init(text)
    }
}

struct RecapFigureText: View {
    let figure: RecapFormat.Figure
    let numberSize: CGFloat
    let unitSize: CGFloat
    var numberWeight: Font.Weight = .bold
    var unitWeight: Font.Weight = .black
    var color: Color = RecapColor.ink
    /// Letter-spacing as a fraction of the font size; heavy numerals are set tight.
    var tracking: CGFloat = -0.05
    var unitGap: CGFloat = 8
    /// Cuts the line box down to the digits: the cap-height box, so that two
    /// heavy numbers stack with the space the mockup gives them and not with the
    /// font's ascender and descender room.
    var trimmed = false

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: figure.unit.isEmpty ? 0 : unitGap) {
            Text(tight: figure.number, tracking: numberSize * tracking)
                .font(.recap(numberSize, numberWeight))
                .lineLimit(1)
            if !figure.unit.isEmpty {
                Text(figure.unit)
                    .font(.recap(unitSize, unitWeight))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(color)
        .fixedSize()
        .padding(.top, trimmed ? -numberSize * Self.ascenderRoom : 0)
        .padding(.bottom, trimmed ? -numberSize * Self.descenderRoom : 0)
    }

    /// The room above and below the digits in a system-font line, as a
    /// fraction of the size. Measured against the rendered card.
    static let ascenderRoom: CGFloat = 0.262
    static let descenderRoom: CGFloat = 0.211
}

/// The small rounded label: "Night owl", "Peak", "↑ 38% vs August".
struct RecapPill<Content: View>: View {
    var fill: Color?
    var stroke: Color?
    var horizontal: CGFloat = 16
    var vertical: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background { if let fill { Capsule().fill(fill) } }
            .overlay { if let stroke { Capsule().strokeBorder(stroke, lineWidth: 1.5) } }
            .fixedSize()
    }
}

// MARK: - Containers

/// A white card with a hairline, or an ink one.
struct RecapBox<Content: View>: View {
    var dark = false
    var fill: Color?
    var padding = EdgeInsets(top: 24, leading: 26, bottom: 24, trailing: 26)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                let background = fill ?? (dark ? RecapColor.ink : RecapColor.white)
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(dark ? RecapColor.ink : (fill ?? RecapColor.hairline), lineWidth: 1)
            }
    }
}

/// The frame of a numbered card: paper, the running head, the page counter.
struct RecapStoryPage<Content: View>: View {
    let page: (number: Int, count: Int)?
    /// A small outlined mono stamp centred in the running head ("NO. 2026·10").
    var stamp: String?
    /// Lines at the foot of the card, for where its figures come from and what
    /// they leave out (`RecapDeck.provenance`, `notes`). A card can be saved
    /// and shared alone, so it carries its own.
    var footnotes: [String] = []
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "PULSE RECAP")
                    .font(.recap(20, .medium, mono: true))
                    .tracking(1.6)
                Spacer()
                if let page {
                    Text(verbatim: String(format: "%02d / %02d", page.number, page.count))
                        .font(.recap(20, .regular, mono: true))
                        .tracking(1.6)
                        .foregroundStyle(RecapColor.tertiary)
                }
            }
            .overlay {
                if let stamp {
                    Text(verbatim: stamp)
                        .font(.recap(16, .regular, mono: true))
                        .tracking(1.3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(RecapColor.ink, lineWidth: 1.5) }
                }
            }
            content
            if !footnotes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(footnotes, id: \.self) { line in
                        Text(line)
                            .font(.recap(15))
                            .foregroundStyle(RecapColor.tertiary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
            }
        }
        .foregroundStyle(RecapColor.ink)
        .padding(EdgeInsets(top: 80, leading: 80, bottom: 72, trailing: 80))
        .frame(width: RecapRenderer.cardSize.width, height: RecapRenderer.cardSize.height, alignment: .topLeading)
        .background(RecapColor.paper)
    }
}

// MARK: - Marks and glyphs

/// The Pulse mark on its ink tile: the stem in paper, the bowl in lime, drawn
/// from `AppIcon/pulse-mark.svg`'s path.
struct RecapMark: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 12 / 46, style: .continuous).fill(RecapColor.ink)
            Canvas { context, size in
                // The path lives in 292…772 × 184…840 of the icon's 1024 space.
                let scale = min(size.width / 480, size.height / 656)
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(x: (x - 292) * scale + (size.width - 480 * scale) / 2,
                            y: (y - 184) * scale + (size.height - 656 * scale) / 2)
                }
                let style = StrokeStyle(lineWidth: 100 * scale, lineCap: .round, lineJoin: .round)

                var stem = Path()
                stem.move(to: point(352, 780))
                stem.addLine(to: point(352, 244))
                context.stroke(stem, with: .color(RecapColor.paper), style: style)

                var bowl = Path()
                bowl.move(to: point(352, 244))
                bowl.addLine(to: point(562, 244))
                bowl.addArc(center: point(562, 394), radius: 150 * scale,
                            startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                bowl.addLine(to: point(530, 544))
                context.stroke(bowl, with: .color(RecapColor.lime), style: style)
            }
            .frame(width: side * 28 / 46, height: side * 34 / 46)
        }
        .frame(width: side, height: side)
    }
}

/// A crescent.
struct RecapMoon: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let outer = Path(ellipseIn: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        let bite = Path(ellipseIn: CGRect(x: rect.midX - side * 0.5 + side * 0.34, y: rect.midY - side * 0.5 - side * 0.26,
                                          width: side * 0.9, height: side * 0.9))
        return outer.subtracting(bite)
    }
}

/// A disc with eight rays.
struct RecapSun: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path(ellipseIn: CGRect(x: center.x - side * 0.2, y: center.y - side * 0.2, width: side * 0.4, height: side * 0.4))
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            let inner = side * 0.32, outer = side * 0.48
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
            ray.addLine(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
            path.addPath(ray.strokedPath(StrokeStyle(lineWidth: side * 0.09, lineCap: .round)))
        }
        return path
    }
}

/// A flame, for a streak.
struct RecapFlame: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 24, rect.height / 28)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(12, 1))
        path.addCurve(to: point(19, 16), control1: point(13, 6), control2: point(19, 8.5))
        path.addArc(center: point(12, 16), radius: 7 * scale, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addCurve(to: point(8.4, 9), control1: point(5, 12.4), control2: point(7, 10.4))
        path.addCurve(to: point(11, 13.4), control1: point(8.6, 11.4), control2: point(9.7, 12.8))
        path.addCurve(to: point(12, 1), control1: point(10, 9), control2: point(10.5, 4.5))
        path.closeSubpath()
        return path
    }
}

/// The persona's glyph: a moon for the night owl, a sun for everyone else.
struct RecapPersonaGlyph: View {
    let persona: Recap.Persona
    let side: CGFloat
    var color: Color = RecapColor.lime

    var body: some View {
        Group {
            if persona == .nightOwl {
                RecapMoon().fill(color)
            } else {
                RecapSun().fill(color)
            }
        }
        .frame(width: side, height: side)
    }
}
