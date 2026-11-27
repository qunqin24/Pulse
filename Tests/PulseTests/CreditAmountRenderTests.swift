import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Pulse

/// Opt-in visual check of Qoder's credit amounts beside each row's name (#88):
/// PULSE_CREDIT_AMOUNTS_PREVIEW=/tmp/credit-amounts swift test --filter CreditAmountRenderTests
@Suite("Credit amount render", .serialized)
@MainActor
struct CreditAmountRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_CREDIT_AMOUNTS_PREVIEW"] != nil))
    func renderQoderParts() throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_CREDIT_AMOUNTS_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { LocalizationSource.use(.system) }

        // The issue's own account: the parts add up to the total.
        func window(_ id: String, _ kind: UsageWindow.Kind, used: Double, limit: Double) -> UsageWindow {
            UsageWindow(id: id, kind: kind, scope: nil, usedFraction: used / limit,
                        windowSeconds: 30 * 86_400, resetsAt: nil, reportsLength: false,
                        amounts: .init(used: used, remaining: limit - used, limit: limit))
        }
        let usage = ProviderUsage(
            account: AccountKey(.qoder),
            windows: [
                window("qoder.credits", .credits, used: 6_119, limit: 14_700),
                window("qoder.plan", .planCredits, used: 157, limit: 6_000),
                window("qoder.pack", .topUp, used: 1_951, limit: 2_700),
                window("qoder.dedicated", .dedicatedCredits, used: 4_011, limit: 6_000),
            ],
            observedAt: Date(), state: .live, plan: "Pro", creditBalance: nil
        )
        // The detailed card's credit section (`QoderCreditSection`), over a
        // made-up month.
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: Date()))!
        let records = (0..<31).map { day in
            QoderClient.HistoryReply.Record(
                beginAt: calendar.date(byAdding: .day, value: day, to: from)!.addingTimeInterval(36_000),
                credits: day % 4 == 0 ? 0 : Double(day % 7) * 1.5, originalCredits: Double((day * 37) % 260))
        }
        let credits = QoderCreditDays(records: records, from: from, calendar: calendar)

        let languages: [(String, AppLanguage)] = [
            ("en", .english), ("zh-Hans", .chineseSimplified), ("zh-Hant", .chineseTraditional),
            ("ja", .japanese), ("ko", .korean), ("ru", .russian),
        ]
        for (name, language) in languages {
            LocalizationSource.use(language)
            for remaining in [true, false] {
                let view = UsageDetailCard(
                    usage: usage, edge: .right, showsRemaining: remaining, showsAmounts: true,
                    parts: [.figures, .chart], qoderCredits: credits,
                    pointerCenter: DetailCardLayout.estimatedHeight / 2
                )
                .padding(20)
                .background(.gray)
                .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let url = folder.appendingPathComponent("\(name)-\(remaining ? "left" : "used").png")
                let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                #expect(CGImageDestinationFinalize(destination))
            }
        }
    }
}
