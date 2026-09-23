import AppKit
import Foundation
import Testing
@testable import Pulse

@Suite("Menu bar icon setting")
struct MenuBarIconSettingTests {
    @Test("The icon remains visible by default and uses a dedicated callback")
    @MainActor
    func defaultAndCallback() {
        let key = "settings.hidesMenuBarIcon"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let settings = AppSettings()
        #expect(!settings.hidesMenuBarIcon)

        var menuBarChanges = 0
        var panelChanges = 0
        settings.onMenuBarIconChange = { menuBarChanges += 1 }
        settings.onChange = { _ in panelChanges += 1 }

        settings.hidesMenuBarIcon = true
        #expect(menuBarChanges == 1)
        #expect(panelChanges == 0)

        settings.hidesMenuBarIcon = true
        #expect(menuBarChanges == 1)
        #expect(panelChanges == 0)
    }

    @Test("The menu bar remains when both other entry points are unavailable")
    func preservesAnEntryPoint() {
        // `panelVisible` means an actual panel can be shown. Before provider
        // selection the caller passes false even if the preference is true.
        #expect(AppDelegate.menuBarIconMustRemainVisible(
            panelVisible: false, hasRegisteredShortcut: false
        ))
        #expect(!AppDelegate.menuBarIconMustRemainVisible(
            panelVisible: true, hasRegisteredShortcut: false
        ))
        #expect(!AppDelegate.menuBarIconMustRemainVisible(
            panelVisible: false, hasRegisteredShortcut: true
        ))
    }

    @Test("The status menu can be rebuilt and keeps its keyboard shortcuts")
    @MainActor
    func statusMenuRebuild() {
        let delegate = AppDelegate()
        let menu = NSMenu()

        delegate.menuNeedsUpdate(menu)
        delegate.menuNeedsUpdate(menu)

        #expect(menu.items.map(\.keyEquivalent) == [",", "", "q"])
        #expect(menu.items[0].keyEquivalentModifierMask == .command)
        #expect(menu.items[2].keyEquivalentModifierMask == .command)
    }
}
