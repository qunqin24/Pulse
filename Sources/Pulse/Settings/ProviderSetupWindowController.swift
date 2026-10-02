// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// A regular window so closing the chooser leaves the menu bar usable.
@MainActor
final class ProviderSetupWindowController {
    private let window: NSWindow

    init(settings: AppSettings, providers: Set<Provider>, isInitial: Bool) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        self.window = window
        window.isReleasedWhenClosed = false
        let ordered = providers.sorted {
            let left = settings.detectedProviders.contains($0)
            let right = settings.detectedProviders.contains($1)
            if left != right { return left }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        window.contentView = NSHostingView(rootView: ProviderSetupView(
            settings: settings, providers: ordered, isInitial: isInitial,
            finish: { [weak window] selected in
                guard !isInitial || !selected.isEmpty else { return }
                window?.close()
                settings.selectProviders(selected.intersection(providers))
            },
            dismiss: { [weak window] in window?.close() }
        ))
        refreshTitle()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }

    func refreshTitle() {
        window.title = .localized("Choose services to monitor")
    }
}
