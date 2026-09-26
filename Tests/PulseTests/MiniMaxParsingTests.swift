import Foundation
import Testing
@testable import Pulse

/// MiniMax's token-plan endpoint is undocumented, and its shape here follows
/// CodexBar's written account of the reply rather than a captured one — the
/// only written account of it that exists, per the source comments. Every
/// fixture below is built by hand from those field names and from
/// `Docs/providers/minimax.md`, not captured from a live account.
@Suite("MiniMax parsing")
struct MiniMaxParsingTests {
    private static func root(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        return try #require(object as? [String: Any])
    }

    private static func windows(_ name: String, provider: Provider = .minimax) throws -> [UsageWindow] {
        let root = try Self.root(name)
        let payload = MiniMaxUsageService.payload(from: root)
        return MiniMaxUsageService.windows(from: payload, provider: provider)
    }

    // MARK: - A normal reply

    @Test("A normal reply gives the plan two windows, shortest first")
    func normalReplyGivesTwoWindows() throws {
        let windows = try Self.windows("minimax-normal")

        // "general" is the plan itself, left unscoped; "video" is a lane the
        // plan does not include and is dropped entirely. Sorted shortest
        // window first: general's five-hour interval, then its week, then
        // creative-writer's thirty-day interval.
        #expect(windows.map(\.id) == [
            "minimax.general.interval", "minimax.general.weekly", "minimax.creative-writer.interval",
        ])
        #expect(windows[0].scope == nil)
        #expect(windows[2].scope == "creative-writer")
    }

    /// `current_*_remaining_percent` at 96 means 4% spent — the inversion is
    /// the whole feature, and it applies whether the figure arrived as a
    /// string or as a number in the same reply.
    @Test("Remaining percent is inverted to a spent fraction, string or number alike")
    func remainingPercentIsInvertedRegardlessOfType() throws {
        let windows = try Self.windows("minimax-normal")
        let general = try #require(windows.first { $0.id == "minimax.general.interval" })
        let weekly = try #require(windows.first { $0.id == "minimax.general.weekly" })

        // "96" arrived as a JSON string.
        #expect(abs(general.usedFraction - 0.04) < 0.000_001)
        // 75 arrived as a JSON number.
        #expect(abs(weekly.usedFraction - 0.25) < 0.000_001)
    }

    @Test("The interval's length is measured from its own timestamps")
    func intervalLengthIsMeasuredFromTimestamps() throws {
        let windows = try Self.windows("minimax-normal")
        let general = try #require(windows.first { $0.id == "minimax.general.interval" })
        let creative = try #require(windows.first { $0.id == "minimax.creative-writer.interval" })

        #expect(general.kind == .fiveHour)
        #expect(general.windowSeconds == 5 * 3_600)
        // Thirty days between the two timestamps, which has nowhere else to
        // map but monthly.
        #expect(creative.kind == .monthly)
        #expect(creative.windowSeconds == 30 * 86_400)
    }

    @Test("The weekly window names its own length and reset")
    func weeklyWindowNamesItsOwnLength() throws {
        let windows = try Self.windows("minimax-normal")
        let weekly = try #require(windows.first { $0.id == "minimax.general.weekly" })

        #expect(weekly.kind == .weekly)
        #expect(weekly.windowSeconds == 7 * 86_400)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_767_830_400)) // 2026-01-08T00:00:00Z
        #expect(weekly.reportsLength)
    }

    /// Status 3 with nothing issued and 100% remaining is the service's way
    /// of saying "not part of your plan" — a video lane on a plan with no
    /// video. Drawn literally that would be a ring pinned at 0% for
    /// something the account cannot use at all, so both of its windows are
    /// dropped rather than shown as empty.
    @Test("A lane the subscription does not include draws nothing")
    func unavailableLaneDrawsNothing() throws {
        let windows = try Self.windows("minimax-normal")
        #expect(!windows.contains { $0.scope == "video" })
    }

    // MARK: - The older endpoint's counts, and the unwrapped payload

    /// `current_interval_usage_count` is the quota that is **left**, despite
    /// its name — reading it as a spend would invert every figure on the
    /// card. It is the fallback the older endpoint uses in place of a
    /// percentage.
    @Test("The older endpoint's usage_count is read as what remains, not what was spent")
    func usageCountIsReadAsRemaining() throws {
        let windows = try Self.windows("minimax-old-endpoint-unwrapped")
        let window = try #require(windows.first)
        // 100 total, 80 left → 20 spent.
        #expect(abs(window.usedFraction - 0.20) < 0.000_001)
    }

    /// The payload is not always wrapped in `data`; the reference decoder —
    /// and this fixture — put it at the root instead.
    @Test("A reply with no data wrapper is still read")
    func unwrappedReplyIsStillRead() throws {
        let root = try Self.root("minimax-old-endpoint-unwrapped")
        let payload = MiniMaxUsageService.payload(from: root)
        #expect(payload["model_remains"] != nil)
    }

    // MARK: - The service's own verdict

    @Test("Status zero is no problem at all")
    func statusZeroIsNoProblem() {
        #expect(MiniMaxUsageService.statusVerdict(base: ["status_code": 0]) == nil)
        #expect(MiniMaxUsageService.statusVerdict(base: nil) == nil)
    }

    /// 1004 is the credential code; every other non-zero status is the
    /// service having a bad day, not a bad key — saying otherwise sends the
    /// user to check a credential that is fine.
    @Test("Status 1004 is a refused key; other non-zero statuses are a server problem")
    func status1004IsCredentialOthersAreServerError() {
        #expect(MiniMaxUsageService.statusVerdict(base: ["status_code": 1004]) == .apiKeyRefused)
        #expect(MiniMaxUsageService.statusVerdict(base: ["status_code": 2013, "status_msg": "internal error"])
            == .serverError)
    }

    /// The message text can say "credential" even where the code does not,
    /// and that is read too.
    @Test("A status message naming a credential problem is read as one")
    func statusMessageNamingCredentialIsRead() {
        let verdict = MiniMaxUsageService.statusVerdict(
            base: ["status_code": 2049, "status_msg": "invalid API token"]
        )
        #expect(verdict == .apiKeyRefused)
    }

    // MARK: - Plan name and credit balance

    @Test("The plan name is the first of several fields that carries one")
    func planNameIsFirstFieldThatCarriesOne() {
        let payload: [String: Any] = ["plan_name": "", "combo_title": "  ", "current_plan_title": "Coding Plan"]
        #expect(MiniMaxUsageService.first(payload, of: [
            "current_subscribe_title", "plan_name", "combo_title", "current_plan_title",
        ]) == "Coding Plan")
    }

    @Test("The plan name from a normal reply")
    func planNameFromANormalReply() throws {
        let root = try Self.root("minimax-normal")
        let payload = MiniMaxUsageService.payload(from: root)
        #expect(MiniMaxUsageService.first(payload, of: [
            "current_subscribe_title", "plan_name", "combo_title", "current_plan_title",
        ]) == "Pro Plan")
    }

    @Test("The credit balance reads a string figure, formatted for the reader's locale")
    func creditBalanceReadsAStringFigure() throws {
        let root = try Self.root("minimax-normal")
        let payload = MiniMaxUsageService.payload(from: root)
        let balance = MiniMaxUsageService.balance(payload, of: [
            "points_balance", "point_balance", "credits_balance", "credit_balance", "balance",
        ])
        let count = Int(12_345).formatted(.number.locale(LocalizationSource.locale))
        #expect(balance == .localized("\(count) points"))
    }

    /// A balance of zero or absent is not shown as a figure — only a field
    /// that actually carries something above zero counts.
    @Test("A balance of zero or absent draws no figure")
    func zeroOrAbsentBalanceDrawsNothing() {
        #expect(MiniMaxUsageService.balance(["points_balance": 0], of: ["points_balance"]) == nil)
        #expect(MiniMaxUsageService.balance([:], of: ["points_balance"]) == nil)
    }

    // MARK: - Two regions, one service

    @Test("MiniMax and MiniMax CN are the same reply shape under different provider ids")
    func twoRegionsShareOneShape() throws {
        let root = try Self.root("minimax-normal")
        let payload = MiniMaxUsageService.payload(from: root)
        let intl = MiniMaxUsageService.windows(from: payload, provider: .minimax)
        let cn = MiniMaxUsageService.windows(from: payload, provider: .minimaxCN)

        #expect(intl.map(\.id) == cn.map(\.id).map { $0.replacingOccurrences(of: "minimaxCN", with: "minimax") })
        #expect(cn[0].id.hasPrefix("minimaxCN."))
        #expect(intl[0].id.hasPrefix("minimax."))
    }

    // MARK: - Unreadable

    @Test("A reply with no model_remains at all produces no windows")
    func noModelRemainsProducesNoWindows() {
        #expect(MiniMaxUsageService.windows(from: [:], provider: .minimax).isEmpty)
        #expect(MiniMaxUsageService.windows(from: nil, provider: .minimax).isEmpty)
    }
}
