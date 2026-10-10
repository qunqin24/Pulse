import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// The recap cards drawn to PNG, for a person to look at.
///
/// Nothing here checks a pixel. A card either fits its language or it does not,
/// and the only judge of that is reading it, so this renders every card of
/// both decks in every language from the sample recaps and lays each
/// language out on one contact sheet.
///
///     PULSE_RECAP_PREVIEW=/tmp/recap swift test --filter RecapRenderTests
///
/// writes `<folder>/<language>/<deck>-<n>-<card>.png`, `<folder>/<language>/sheet.png`
/// and, under `<folder>/edge`, the decks of a recap with a field missing.
@MainActor
@Suite("Recap render", .serialized)
struct RecapRenderTests {
    private static let languages: [(folder: String, language: AppLanguage)] = [
        ("en", .english), ("zh-Hans", .chineseSimplified), ("zh-Hant", .chineseTraditional),
        ("ja", .japanese), ("ko", .korean), ("ru", .russian),
    ]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_RECAP_PREVIEW"] != nil))
    func renderEveryCardInEveryLanguage() throws {
        let destination = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_RECAP_PREVIEW"]))
        defer { LocalizationSource.use(.system) }

        for (folder, language) in Self.languages {
            LocalizationSource.use(language)
            let directory = destination.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var rows: [[CGImage]] = []
            for (name, deck) in [("month", RecapSamples.monthDeck), ("year", RecapSamples.yearDeck)] {
                var row: [CGImage] = []
                for (index, card) in deck.cards.enumerated() {
                    let image = try #require(RecapRenderer.image(of: card, in: deck), "\(name) \(card) \(folder)")
                    #expect(image.width == 1080 && image.height == 1920)
                    try write(image, to: directory.appendingPathComponent("\(name)-\(index + 1)-\(card.rawValue).png"))
                    row.append(image)
                }
                rows.append(row)
            }
            try write(try #require(Self.sheet(rows)), to: directory.appendingPathComponent("sheet.png"))
        }

        // A recap with fields missing: English in `edge`, and the languages that run
        // longest or wrap differently in `edge-<language>`.
        for (folder, language) in [("edge", AppLanguage.english), ("edge-zh-Hans", .chineseSimplified),
                                   ("edge-ja", .japanese), ("edge-ko", .korean), ("edge-ru", .russian)] {
            LocalizationSource.use(language)
            let edge = destination.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: edge, withIntermediateDirectories: true)
            let cases: [(String, RecapDeck)] = [
                ("no-price", RecapDeck(recap: RecapSamples.month(), monthlyPrice: nil, hidesProjects: false)),
                ("unpriced", RecapDeck(recap: RecapSamples.month(priced: false), monthlyPrice: 200, hidesProjects: false)),
                ("bare", RecapDeck(recap: RecapSamples.month(priced: false, hasHours: false, hasAgents: false, hasCache: false, persona: nil),
                                   monthlyPrice: nil, hidesProjects: true)),
                ("in-progress", RecapDeck(recap: RecapSamples.month(isInProgress: true, unpricedShare: 0.004, throughDay: 12), monthlyPrice: 200, hidesProjects: false)),
                ("year-in-progress", RecapDeck(recap: RecapSamples.year(throughMonth: 7), monthlyPrice: 200, hidesProjects: false)),
                ("no-hours", RecapDeck(recap: RecapSamples.month(hasHours: false), monthlyPrice: 200, hidesProjects: false)),
                ("no-cache", RecapDeck(recap: RecapSamples.month(hasCache: false), monthlyPrice: 200, hidesProjects: false)),
                ("floor", RecapDeck(recap: RecapSamples.month(unpricedShare: 0.004), monthlyPrice: 200, hidesProjects: false)),
                ("mostly-unpriced", RecapDeck(recap: RecapSamples.month(unpricedShare: 0.2), monthlyPrice: 200, hidesProjects: false)),
                // One, two and three agents fill the opener's lineup differently,
                // and August 2026 takes six weeks of rows.
                ("one-agent", RecapDeck(recap: RecapSamples.month(agentCount: 1), monthlyPrice: 200, hidesProjects: false)),
                ("two-agents", RecapDeck(recap: RecapSamples.month(agentCount: 2), monthlyPrice: 200, hidesProjects: false)),
                ("three-agents", RecapDeck(recap: RecapSamples.month(agentCount: 3), monthlyPrice: 200, hidesProjects: false)),
                ("six-weeks", RecapDeck(recap: RecapSamples.month(monthNumber: 8), monthlyPrice: 200, hidesProjects: false)),
            ]
            for (name, deck) in cases {
                for card in deck.cards {
                    let image = try #require(RecapRenderer.image(of: card, in: deck))
                    try write(image, to: edge.appendingPathComponent("\(name)-\(card.rawValue).png"))
                }
            }
        }
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    /// Every card of both decks, a quarter of its size, one deck to a row.
    private static func sheet(_ rows: [[CGImage]]) -> CGImage? {
        let content = VStack(alignment: .leading, spacing: 16) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(rows[row].indices, id: \.self) { index in
                        Image(decorative: rows[row][index], scale: 1)
                            .resizable()
                            .frame(width: 270, height: 480)
                            .border(Color.gray.opacity(0.5), width: 1)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.85))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.cgImage
    }
}
