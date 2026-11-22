import Foundation
import Testing
@testable import Pulse

/// GitHub Copilot's `copilot_internal/user` reply, reconstructed from
/// `CopilotUsageService`'s own field names and
/// [Docs/providers/copilot.md](../../Docs/providers/copilot.md) — not
/// captured from a live account. `windows(from:)` and `planName(_:)` were
/// already `internal` before this file existed; nothing was extracted for it.
@Suite("Copilot parsing")
struct CopilotParsingTests {
    private static func root(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static let resetDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private static let decemberReset: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 1
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    // MARK: - The three quotas

    @Test("A normal reply becomes three quotas, in the order they matter, inverted from what is left")
    func normalReply() throws {
        let root = try Self.root("copilot-normal")
        let windows = CopilotUsageService.windows(from: root)

        #expect(windows.map(\.id) == ["copilot.premium_interactions", "copilot.chat", "copilot.completions"])
        #expect(windows.map(\.scope) == ["Premium requests", "Chat", "Completions"])
        #expect(windows.allSatisfy { $0.kind == .monthly })
        #expect(windows.allSatisfy { !$0.reportsLength })
        #expect(windows.allSatisfy { $0.resetsAt == Self.resetDate })

        // percent_remaining 70/90/95 → 30%/10%/5% gone. The reply says what
        // is left; everything downstream must read what is gone.
        #expect(abs(windows[0].usedFraction - 0.30) < 0.000_001)
        #expect(abs(windows[1].usedFraction - 0.10) < 0.000_001)
        #expect(abs(windows[2].usedFraction - 0.05) < 0.000_001)
        #expect(windows.allSatisfy { !$0.isExhausted })

        #expect(CopilotUsageService.planName(root["copilot_plan"] as? String) == "Individual")
    }

    // MARK: - Unissued vs spent vs unlimited

    /// `has_quota: false` drops a lane outright — reading it literally would
    /// be a full red ring for something the account never had. A lane that
    /// **has** run out (chat, spent to zero) is not dropped just because it
    /// sits beside one that was. An unlimited lane has no share to show.
    @Test("An unissued quota is dropped, a spent one is not, an unlimited one has no ring")
    func unissuedSpentAndUnlimited() throws {
        let windows = CopilotUsageService.windows(from: try Self.root("copilot-unissued-and-spent"))

        #expect(windows.map(\.id) == ["copilot.chat"])
        #expect(windows[0].usedFraction == 1)
        #expect(windows[0].isExhausted)
    }

    /// A token-billed Business seat marks its unlimited chat and completions
    /// lanes `unlimited: true`, then reports its issued premium allowance with
    /// `has_quota: false` while also supplying `entitlement` and `credits_used`.
    /// That false is not "the plan has none": it is the only quota left to
    /// show, and an issued allowance already spent must stay visible.
    @Test("A token-billed Business seat keeps its spent premium allowance")
    func tokenBilledBusinessSeat() throws {
        let root = try Self.root("copilot-business-token-billing")
        let windows = CopilotUsageService.windows(from: root)

        #expect(windows.map(\.id) == ["copilot.premium_interactions"])
        #expect(windows[0].usedFraction == 1)
        #expect(windows[0].isExhausted)
        #expect(windows[0].resetsAt == Self.decemberReset)
        #expect(CopilotUsageService.planName(root["copilot_plan"] as? String) == "Business")
        #expect(windows[0].amounts == .init(used: 40_000, remaining: 0, limit: 40_000))
    }

    @Test("Numeric display uses the reported remainder, not credits_used or rounded percent")
    func numericQuotaUsesReportedRemainder() throws {
        let snapshot: [String: Any] = [
            "entitlement": 200, "quota_remaining": 72.6, "remaining": 72,
            "credits_used": 500, "percent_remaining": 36
        ]
        let windows = CopilotUsageService.windows(from: ["quota_snapshots": ["premium_interactions": snapshot]])
        let amounts = try #require(windows.first?.amounts)
        #expect(amounts.used == 200 - 72.6)
        #expect(amounts.remaining == 72.6)
        #expect(amounts.limit == 200)
        #expect(windows.first?.usedFraction == 0.64)
    }

    @Test("Missing or invalid remainder preserves the percentage without inventing counts")
    func invalidNumericQuotaKeepsPercentage() throws {
        let base: [String: Any] = ["entitlement": 200, "credits_used": 80, "percent_remaining": 60]
        for snapshot in [base, base.merging(["remaining": -1]) { _, new in new },
                         base.merging(["remaining": 201]) { _, new in new },
                         base.merging(["remaining": true]) { _, new in new }] {
            let windows = CopilotUsageService.windows(from: ["quota_snapshots": ["premium_interactions": snapshot]])
            let window = try #require(windows.first)
            #expect(window.amounts == nil)
            #expect(window.usedFraction == 0.40)
        }
    }

    /// **Spent is not the same as over the allowance.** A lane with overage
    /// permitted keeps working past its included share and is billed for it,
    /// so `overage_count` above zero must not paint a red ring for someone who
    /// deliberately paid to carry on.
    @Test("A lane with overage permitted is not read as spent")
    func overagePermittedIsNotSpent() throws {
        let windows = CopilotUsageService.windows(from: try Self.root("copilot-overage"))

        #expect(windows.map(\.id) == ["copilot.chat"])
        #expect(windows[0].usedFraction == 1)
        #expect(windows[0].isExhausted == false)
    }

    /// Older replies carry no `has_quota` flag at all. A lane the plan
    /// excludes then looks exactly like one with everything already spent —
    /// zero entitlement, zero remaining, 100% remaining — so it is the
    /// **placeholder** case (nothing ever issued) that is dropped, while
    /// completions, entitled but genuinely run dry, survives.
    @Test("Without has_quota, a placeholder lane is dropped and a spent one is not")
    func olderShapeWithoutHasQuotaFlag() throws {
        let windows = CopilotUsageService.windows(from: try Self.root("copilot-older-shape"))

        #expect(windows.map(\.id) == ["copilot.completions"])
        #expect(windows[0].usedFraction == 1)
        #expect(windows[0].isExhausted)
        #expect(windows[0].resetsAt == Self.resetDate, "the bare yyyy-MM-dd reset date still parses")
    }

    // MARK: - Nothing reported

    @Test("No quota snapshots at all draws nothing, and no plan name is nil")
    func emptyReplyDrawsNothing() throws {
        let root = try Self.root("copilot-empty")
        #expect(CopilotUsageService.windows(from: root).isEmpty)
        #expect(CopilotUsageService.planName(root["copilot_plan"] as? String) == nil)
    }

    @Test("A reply with no quota_snapshots key at all is the same as an empty one")
    func missingSnapshotsKey() {
        #expect(CopilotUsageService.windows(from: [:]).isEmpty)
        #expect(CopilotUsageService.windows(from: ["copilot_plan": "individual"]).isEmpty)
    }

    // MARK: - Plan names

    @Test("Known plan names are tidied; an unfamiliar one passes through untouched")
    func planNameMapping() {
        #expect(CopilotUsageService.planName("individual") == "Individual")
        #expect(CopilotUsageService.planName("FREE") == "Free")
        #expect(CopilotUsageService.planName("business") == "Business")
        #expect(CopilotUsageService.planName("enterprise") == "Enterprise")
        #expect(CopilotUsageService.planName("  business  ") == "Business", "trimmed before matching")
        #expect(CopilotUsageService.planName("MysteryPlan") == "MysteryPlan", "unknown name beats none")
        #expect(CopilotUsageService.planName("") == nil)
        #expect(CopilotUsageService.planName(nil) == nil)
    }

    // MARK: - Unreadable reply

    /// `fetch()` decides `.unreadableReply` from `JSONSerialization` failing to
    /// produce a `[String: Any]` at all — that happens before `windows(from:)`
    /// is ever called, so it is exercised directly here rather than through a
    /// network round trip.
    @Test("A reply that is not a JSON object at all is unreadable")
    func garbageReplyIsNotAnObject() {
        let data = Data("<html>rate limited</html>".utf8)
        #expect((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) == nil)
    }
}
