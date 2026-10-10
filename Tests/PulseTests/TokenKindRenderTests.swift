import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Pulse

/// Opt-in visual checks of the production breakdown and its day table:
/// PULSE_TOKEN_KINDS_PREVIEW=/tmp/token-kinds swift test --filter TokenKindRenderTests
@Suite("Token kind render", .serialized)
@MainActor
struct TokenKindRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_TOKEN_KINDS_PREVIEW"] != nil))
    func renderRecordedAndUnclassifiedWork() throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_TOKEN_KINDS_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { LocalizationSource.use(.system) }

        let languages: [(String, AppLanguage)] = [
            ("en", .english), ("zh-Hans", .chineseSimplified), ("zh-Hant", .chineseTraditional),
            ("ja", .japanese), ("ko", .korean), ("ru", .russian),
        ]
        let examples: [(String, TokenTally, Int)] = [
            ("complete", TokenTally(input: 100, cacheWrite: 200, cacheRead: 400, output: 50), 0),
            ("mixed", TokenTally(input: 100, cacheWrite: 200, cacheRead: 400, output: 50), 250),
            ("bare-total", TokenTally(), 1_000),
            ("cache-unreported", TokenTally(input: 300, output: 50), 0),
        ]
        for (name, language) in languages {
            LocalizationSource.use(language)
            for (scenario, tally, unknown) in examples {
                for width in [480.0, 900.0] {
                    var model = ModelSpendSummary()
                    model.name = "Preview"
                    model.tokens = tally.total + unknown
                    model.tally = tally
                    model.unclassifiedTokens = unknown
                    model.unpricedTokens = unknown
                    model.days = [.init(date: Date(timeIntervalSince1970: 1_789_372_800), tokens: model.tokens, tally: tally, unclassifiedTokens: unknown)]
                    if tally.total > 0 {
                        model.costBreakdown = tally.costBreakdown(at: ModelPrice(input: 100, output: 400, cacheRead: 25, cacheWrite: 200, name: "Preview"))
                        model.days[0].costBreakdown = model.costBreakdown
                    }
                    if scenario == "cache-unreported" {
                        model.agents = [.init(agent: .goose, tokens: model.tokens, cost: model.cost)]
                    }
                    let view = ModelSpendDetailView(model: model)
                        .padding(16)
                        .frame(width: width)
                        .background(.white)
                        .environment(\.colorScheme, .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try #require(renderer.cgImage)
                    #expect(image.width == Int(width * 2))
                    let url = folder.appendingPathComponent("\(name)-\(scenario)-\(Int(width)).png")
                    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                    CGImageDestinationAddImage(destination, image, nil)
                    #expect(CGImageDestinationFinalize(destination))
                }
            }
        }
    }
}
