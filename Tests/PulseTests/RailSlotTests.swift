import Foundation
import Testing
@testable import Pulse

/// The rail's order, which two places depend on agreeing: the panel draws
/// from it and the click handler indexes into it. A ring drawn at one
/// position and refreshed from another is a fault nobody reports clearly,
/// so the ordering lives in one function and is pinned here.
@Suite("Rail slots")
struct RailSlotTests {
    private func window(_ id: String, scope: String?, used: Double = 0.5) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: .fiveHour,
            scope: scope,
            usedFraction: used,
            windowSeconds: 5 * 3_600,
            resetsAt: nil
        )
    }

    private func usage(_ account: AccountKey, _ windows: [UsageWindow]) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: nil
        )
    }

    private let antigravity = AccountKey(.antigravity)
    private let codex = AccountKey(.codex)

    private var twoGroups: [UsageWindow] {
        [
            window("g5", scope: "Gemini"),
            window("g7", scope: "Gemini"),
            window("t5", scope: "Third-party"),
        ]
    }

    // MARK: - The order before anybody arranges it

    /// Seventeen rows in the order the enum happens to be written in is a list
    /// you have to scan; by name it is one you can look in.
    @Test("With nothing arranged, accounts come out in name order")
    func theDefaultOrderIsByName() {
        let names = AppSettings(providerOrder: []).orderedAccounts.map(\.provider.displayName)

        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(names.first == "Antigravity")
        #expect(names.count == Provider.allCases.count)
    }

    /// An arrangement somebody made is theirs, and is not to be re-sorted
    /// under them.
    @Test("A stored arrangement is kept, and what it does not mention follows in name order")
    func aStoredArrangementSurvives() {
        let settings = AppSettings(providerOrder: [
            AccountKey(.volcengine).id, AccountKey(.codex).id,
        ])
        let order = settings.orderedAccounts.map(\.provider)

        #expect(Array(order.prefix(2)) == [.volcengine, .codex])

        let rest = order.dropFirst(2).map(\.displayName)
        #expect(rest == rest.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(!rest.contains("Volcengine"))
    }

    /// An added account is sorted by what is written on its row, which is the
    /// label its owner gave it rather than the provider behind it.
    @Test("An added account sorts by its own label")
    func addedAccountsSortByLabel() {
        let extra = ExtraAccount(provider: .claudeCode, slot: "work", label: "Aardvark")
        let settings = AppSettings(extraAccounts: [extra], providerOrder: [])

        #expect(settings.orderedAccounts.first == extra.key)
    }

    @Test("An account that is not split gets exactly one slot")
    func unsplitAccountIsOneSlot() {
        let slots = RailSlot.rail(
            for: [antigravity, codex],
            isSplit: { _ in false },
            groups: { _ in ["Gemini", "Third-party"] }
        )

        #expect(slots.map(\.id) == [antigravity.id, codex.id])
        #expect(slots.allSatisfy { $0.group == nil })
    }

    @Test("A split account becomes one slot per group, in the provider's order")
    func splitAccountBecomesOneSlotPerGroup() {
        let slots = RailSlot.rail(
            for: [antigravity, codex],
            isSplit: { $0 == self.antigravity },
            groups: { _ in ["Gemini", "Third-party"] }
        )

        #expect(slots.count == 3)
        #expect(slots[0].account == antigravity)
        #expect(slots[0].group == "Gemini")
        #expect(slots[1].group == "Third-party")
        // The split stays local to the account that asked for it.
        #expect(slots[2] == RailSlot(codex))
    }

    /// Before the first answer there is nothing to split by. Two empty rings
    /// that may never fill are worse than one that becomes two a moment later.
    @Test("A split account with nothing to split by keeps its single slot")
    func splitWithoutGroupsStaysWhole() {
        for groups in [[], ["Gemini"]] {
            let slots = RailSlot.rail(
                for: [antigravity],
                isSplit: { _ in true },
                groups: { _ in groups }
            )

            #expect(slots == [RailSlot(antigravity)])
        }
    }

    @Test("Slot ids are unique per group, so SwiftUI keeps the rings apart")
    func slotIDsAreDistinct() {
        let slots = RailSlot.rail(
            for: [antigravity],
            isSplit: { _ in true },
            groups: { _ in ["Gemini", "Third-party"] }
        )

        #expect(Set(slots.map(\.id)).count == 2)
        #expect(slots[0].id != antigravity.id)
    }

    @Test("Model groups come back in the provider's order, deduplicated")
    func modelGroupsKeepProviderOrder() {
        let groups = RailSlot.modelGroups(of: usage(antigravity, twoGroups))

        #expect(groups == ["Gemini", "Third-party"])
    }

    /// Every other provider reports one pool. Unscoped windows must not turn
    /// into a nameless group, or a provider that never asked to be split
    /// would be.
    @Test("Windows without a scope produce no groups")
    func unscopedWindowsProduceNoGroups() {
        let reading = usage(codex, [window("5h", scope: nil), window("weekly", scope: nil)])

        #expect(RailSlot.modelGroups(of: reading).isEmpty)
    }

    /// Splitting a mixed reading would file every window under a scope and
    /// leave the unscoped ones belonging to no ring — gone from the rail and
    /// from every card. Staying whole is the honest answer.
    @Test("A reading that mixes scoped and unscoped windows is not split")
    func mixedScopesDoNotSplit() {
        let mixed = usage(antigravity, [
            window("g5", scope: "Gemini"),
            window("t5", scope: "Third-party"),
            window("credits", scope: nil),
        ])

        #expect(RailSlot.modelGroups(of: mixed).isEmpty)

        let slots = RailSlot.rail(
            for: [antigravity],
            isSplit: { _ in true },
            groups: { _ in RailSlot.modelGroups(of: mixed) }
        )
        #expect(slots == [RailSlot(antigravity)])
    }

    /// The rail's own budget reserves `modelGroupCount` per split account and
    /// `PanelMetrics` sizes the rail from that, so a third group cannot be
    /// drawn. Taking the first two would leave the third belonging to no ring
    /// and gone from every card, so the account stays whole instead.
    @Test("More groups than the rail budgeted for leaves the account whole")
    func tooManyGroupsStayWhole() {
        let slots = RailSlot.rail(
            for: [antigravity],
            isSplit: { _ in true },
            groups: { _ in ["Gemini", "Third-party", "Something new"] }
        )

        #expect(slots == [RailSlot(antigravity)])
        // Not silently truncated to the budget.
        #expect(slots.count != Provider.antigravity.modelGroupCount)
    }

    /// The invariant the panel window depends on: what the controller measures
    /// its rects from and what the view draws are the same list, so a click
    /// lands on the ring it looks like it landed on.
    @Test("Exactly the budgeted number of groups is what splits")
    func theBudgetedCountSplits() {
        let slots = RailSlot.rail(
            for: [antigravity],
            isSplit: { _ in true },
            groups: { _ in ["Gemini", "Third-party"] }
        )

        #expect(slots.count == Provider.antigravity.modelGroupCount)
    }
}
