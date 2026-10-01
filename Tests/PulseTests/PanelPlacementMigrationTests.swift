import Foundation
import Testing
@testable import Pulse

/// What a stored placement comes back as.
///
/// Before there were two free placements, "free" was `panel.floating` alone
/// and always upright. Anyone who chose it then has no `panel.floatingAxis`,
/// and must get the upright rail they left, not one lying across.
@Suite("Panel placement migration")
struct PanelPlacementMigrationTests {
    /// A throwaway domain, so nothing here reads or writes the real settings.
    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let name = "PanelPlacementMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    @Test("A free placement stored before the axis existed stays upright")
    func earlierFreePlacementStaysUpright() {
        let placement = PanelPlacement.restored(from: defaults(["panel.floating": true]))
        #expect(placement.dock == .floating(.vertical))
    }

    @Test("A stored axis is the one restored")
    func storedAxisIsRestored() {
        let across = PanelPlacement.restored(from: defaults(["panel.floating": true, "panel.floatingAxis": "horizontal"]))
        #expect(across.dock == .floating(.horizontal))
        let upright = PanelPlacement.restored(from: defaults(["panel.floating": true, "panel.floatingAxis": "vertical"]))
        #expect(upright.dock == .floating(.vertical))
    }

    @Test("An axis Pulse does not know is read as upright")
    func unknownAxisIsUpright() {
        let placement = PanelPlacement.restored(from: defaults(["panel.floating": true, "panel.floatingAxis": "diagonal"]))
        #expect(placement.dock == .floating(.vertical))
    }

    @Test("A docked placement ignores the axis")
    func dockedIgnoresTheAxis() {
        let placement = PanelPlacement.restored(from: defaults([
            "panel.floating": false, "panel.edge": "top", "panel.floatingAxis": "horizontal",
        ]))
        #expect(placement.dock == .edge(.top))
        #expect(PanelPlacement.restored(from: defaults([:])).dock == .edge(.right))
    }
}
