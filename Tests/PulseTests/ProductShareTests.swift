import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Pulse

/// Claude Code's split of the week by product (#113). The fixture is the
/// reply the issue's author posted on 2026-11-17, with the `limits` entries
/// the endpoint sends beside it; every key, token and id was already removed.
@Suite("Product share")
struct ProductShareTests {
    private static func root(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private static func rows(_ rows: [[String: Any]]) -> [String: Any] {
        ["seven_day_breakdown": ["rows": rows]]
    }

    @Test("The reply's split becomes the products above zero, largest first")
    func readsTheSplit() throws {
        let usage = ClaudeCodeUsageService.parse(try Self.root("claude-usage-product-share"), for: AccountKey(.claudeCode))
        let share = try #require(usage.productShare)
        #expect(share.rows == [.init(name: "Claude Code", percent: 94), .init(name: "Claude Duet", percent: 6)])
        #expect(share.asOf == ISO8601DateFormatter().date(from: "2026-11-17T03:04:38Z"))
        // The split is beside the limits, not one of them.
        #expect(usage.windows.count == 2)
    }

    @Test("No split, no share; odd rows are skipped; four at most, ties in the reply's order")
    func edges() {
        #expect(ClaudeCodeUsageService.productShare(in: [:]) == nil)
        #expect(ClaudeCodeUsageService.productShare(in: Self.rows([["display_name": "Chats", "percent": 0]])) == nil)

        let share = ClaudeCodeUsageService.productShare(in: Self.rows([
            ["display_name": "A", "percent": 10],
            ["percent": 30],
            ["display_name": "B", "percent": "40"],
            ["display_name": "C", "percent": 140],
            ["display_name": "D", "percent": 20],
            ["display_name": "E", "percent": 20],
            ["display_name": "F", "percent": 45],
            ["display_name": "G", "percent": 5],
        ]))
        #expect(share?.rows.map(\.name) == ["F", "D", "E", "A"])
    }

    @Test("Last week's split is not shown once the weekly limit has reset")
    func hiddenAfterReset() throws {
        let usage = ClaudeCodeUsageService.parse(try Self.root("claude-usage-product-share"), for: AccountKey(.claudeCode))
        let reset = try #require(usage.windows.first { $0.kind == .weekly }?.resetsAt)
        #expect(AccountLiveUsageGroup.visibleShare(of: usage, at: reset.addingTimeInterval(-60)) != nil)
        #expect(AccountLiveUsageGroup.visibleShare(of: usage, at: reset) == nil)
    }
}

/// The Current usage group with the split, drawn for a person to look at:
///
///     PULSE_PRODUCT_SHARE_PREVIEW=/tmp/share swift test --filter ProductShareRenderTests
///
/// writes `share-<language>-<appearance>.png`. Nothing is checked, and
/// without the variable the test is skipped.
@MainActor
@Suite("Product share render", .serialized)
struct ProductShareRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_PRODUCT_SHARE_PREVIEW"] != nil))
    func render() throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_PRODUCT_SHARE_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { LocalizationSource.use(.system) }

        let account = AccountKey(.claudeCode)
        let settings = AppSettings(enabledAccounts: [Provider.claudeCode.rawValue])
        let store = UsageStore(settings: settings)
        let now = Date()
        var usage = ProviderUsage(
            account: account,
            windows: [
                UsageWindow(id: "session", kind: .fiveHour, scope: nil, usedFraction: 0.12,
                            windowSeconds: 5 * 3600, resetsAt: now.addingTimeInterval(3 * 3600)),
                UsageWindow(id: "weekly", kind: .weekly, scope: nil, usedFraction: 0.45,
                            windowSeconds: 7 * 86_400, resetsAt: now.addingTimeInterval(3 * 86_400)),
            ],
            observedAt: now.addingTimeInterval(-120), state: .live, plan: "Max 20x", creditBalance: nil
        )
        usage.productShare = ProductShare(rows: [
            ["display_name": "Claude Code", "percent": 94],
            ["display_name": "Claude Duet", "percent": 6],
        ], asOf: now)

        for language in [AppLanguage.chineseSimplified, .english] {
            LocalizationSource.use(language)
            for dark in [false, true] {
                let view = AccountLiveUsageGroup(account: account, store: store, settings: settings, reading: usage)
                    .frame(width: 520)
                    .padding(20)
                    .background(Color(nsColor: .windowBackgroundColor))
                let name = "share-\(language == .english ? "en" : "zh")-\(dark ? "dark" : "light").png"
                try write(view, appearance: NSAppearance(named: dark ? .darkAqua : .aqua)!, to: folder.appendingPathComponent(name))
            }
        }
    }

    private func write<V: View>(_ view: V, appearance: NSAppearance, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.contentView = nil
    }
}
