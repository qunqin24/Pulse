import Foundation
import Testing
@testable import Pulse

/// JetBrains AI's quota file.
///
/// **The fixture is second-hand**: written from CodexBar's JetBrains provider
/// and its tests (MIT), not copied from an IDE's settings folder. It pins the
/// shape Pulse reads; it does not prove the shape is right. It is inline
/// rather than in `Fixtures/` because it is XML, written as the IDE writes it:
/// JSON inside attributes, escaped.
@Suite("JetBrains AI")
struct JetBrainsAITests {
    private let context = ProfileContext(provider: .jetBrainsAI, credential: nil, serverAddress: nil)

    static func xml(quota: String? = Self.quota, refill: String? = Self.refill) -> Data {
        let options = [quota.map { ("quotaInfo", $0) }, refill.map { ("nextRefill", $0) }]
            .compactMap { $0 }
            .map { #"<option name="\#($0.0)" value="\#(escaped($0.1))" />"# }
            .joined(separator: "\n    ")
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <application>
          <component name="AIAssistantQuotaManager2">
            \(options)
          </component>
        </application>
        """.utf8)
    }

    /// As the IDE writes it: quotes and newlines as entities.
    private static func escaped(_ json: String) -> String {
        json.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "&#10;")
    }

    static let quota = """
    {
      "type": "Available",
      "current": "7478.3",
      "maximum": "1000000",
      "until": "2026-11-09T21:00:00Z",
      "tariffQuota": { "current": "7478.3", "maximum": "1000000", "available": "992521.7" }
    }
    """

    static let refill = """
    {
      "type": "Known",
      "next": "2026-10-16T14:00:54.939Z",
      "tariff": { "amount": "1000000", "duration": "PT720H" }
    }
    """

    @Test("The quota is read as stated, with the refill's length and date")
    func quota() throws {
        let usage = JetBrainsAIUsageService.reading(from: Self.xml(), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.jetBrainsAI))
        let window = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(window.usedFraction == 7478.3 / 1_000_000)
        #expect(window.kind == .other(seconds: 720 * 3_600))
        #expect(window.reportsLength)
        #expect(window.windowSeconds == 720 * 3_600)
        // The refill, not the subscription's `until`.
        #expect(window.resetsAt == ProfileHTTP.date("2026-10-16T14:00:54.939Z"))
        #expect(!window.isExhausted)
    }

    @Test("A refill length that isn't an ISO duration is not claimed")
    func unstatedLength() throws {
        let refill = #"{"type":"monthly","next":"2026-10-01T00:00:00Z","tariff":{"amount":"100000","duration":"monthly"}}"#
        let usage = JetBrainsAIUsageService.reading(from: Self.xml(refill: refill), context: context)
        let window = try #require(usage.windows.first)
        #expect(window.kind == .credits)
        #expect(!window.reportsLength)
        #expect(window.resetsAt == ProfileHTTP.date("2026-10-01T00:00:00Z"))
    }

    @Test("No refill at all leaves the reset and the length off, not the quota")
    func noRefill() throws {
        let usage = JetBrainsAIUsageService.reading(from: Self.xml(refill: nil), context: context)
        let window = try #require(usage.windows.first)
        #expect(window.resetsAt == nil)
        #expect(!window.reportsLength)
    }

    @Test("ISO 8601 lengths it can state exactly", arguments: [
        ("PT720H", 2_592_000), ("P30D", 2_592_000), ("P1DT12H", 129_600), ("P1W", 604_800),
    ])
    func durations(text: String, seconds: Int) {
        #expect(JetBrainsAIUsageService.seconds(fromISODuration: text) == seconds)
    }

    @Test("Lengths it can't", arguments: ["P1M", "monthly", "", "PT0H", "720"])
    func notDurations(text: String) {
        #expect(JetBrainsAIUsageService.seconds(fromISODuration: text) == nil)
    }

    @Test("A file that isn't XML can't be read")
    func unreadable() {
        let usage = JetBrainsAIUsageService.reading(from: Data("not xml".utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A file with no quota in it yet has nothing saved")
    func noQuota() {
        let usage = JetBrainsAIUsageService.reading(from: Self.xml(quota: nil, refill: nil), context: context)
        #expect(usage.state == .unavailable(.localAppMissing))
    }

    @Test("A figure that isn't one is left off, and nothing left is no limits", arguments: [
        #"{"current":"50","maximum":"0"}"#,
        #"{"current":"-5","maximum":"100"}"#,
        #"{"current":"50"}"#,
        #"{"maximum":"100"}"#,
    ])
    func noFigures(quota: String) {
        let usage = JetBrainsAIUsageService.reading(from: Self.xml(quota: quota), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    /// What WebStorm 2026.3 leaves behind, as the reporter of #122 described
    /// it: the component is there, the quota is `Unknown`, the refill is
    /// `Error`, and no figures. Shape from that description, not a copy.
    @Test("An IDE that marked its quota unknown didn't save one", arguments: [
        (#"{"type":"Unknown"}"#, #"{"type":"Error"}"#),
        (#"{"type":"Unknown"}"#, nil),
        (#"{"type":"Available"}"#, #"{"type":"Error"}"#),
    ] as [(String, String?)])
    func quotaUnsaved(quota: String, refill: String?) {
        let usage = JetBrainsAIUsageService.reading(from: Self.xml(quota: quota, refill: refill), context: context)
        #expect(usage.state == .unavailable(.localQuotaUnsaved))
    }

    @Test("A stated figure keeps no-limits, even beside an unknown type")
    func statedFigureIsNotUnsaved() {
        let usage = JetBrainsAIUsageService.reading(
            from: Self.xml(quota: #"{"type":"Unknown","current":"5","maximum":"0"}"#, refill: #"{"type":"Error"}"#),
            context: context
        )
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("No IDE on this Mac has saved a quota")
    func noIDE() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(await JetBrainsAIUsageService.fetch(context, home: home).state == .unavailable(.localAppMissing))
    }

    @Test("The quota written last is the one read, and only from an IDE's folder")
    func newestFile() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let older = try write(Self.xml(quota: #"{"current":"10","maximum":"100"}"#),
                              to: home, "Library/Application Support/JetBrains/PyCharm2025.1")
        let newer = try write(Self.xml(quota: #"{"current":"30","maximum":"100"}"#),
                              to: home, "Library/Application Support/JetBrains/IntelliJIdea2025.3")
        // Not an IDE: never looked in, however recent.
        let stranger = try write(Self.xml(quota: #"{"current":"90","maximum":"100"}"#),
                                 to: home, "Library/Application Support/Google/Chrome")
        let files = FileManager.default
        try files.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: older.path)
        try files.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: newer.path)
        try files.setAttributes([.modificationDate: Date(timeIntervalSince1970: 3_000)], ofItemAtPath: stranger.path)

        let usage = await JetBrainsAIUsageService.fetch(context, home: home)
        #expect(usage.windows.map(\.usedFraction) == [0.3])
    }

    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "jetbrains-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ data: Data, to home: URL, _ folder: String) throws -> URL {
        let options = home.appending(path: folder).appending(path: "options")
        try FileManager.default.createDirectory(at: options, withIntermediateDirectories: true)
        let file = options.appending(path: "AIAssistantQuotaManager2.xml")
        try data.write(to: file)
        return file
    }
}
