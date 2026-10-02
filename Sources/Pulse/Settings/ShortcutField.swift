// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// The control that records a global shortcut: a key-cap sized button that
/// shows the current combination, and takes the next one pressed after a click.
///
/// A local event monitor rather than a first-responder `NSView`. The monitor is
/// installed only while recording and sees keys before anything dispatches
/// them, which is what lets ⌘Q be *recorded* rather than quitting the app
/// mid-recording. A hosted view asking for first responder would have to win
/// that argument with SwiftUI on every pane change instead.
struct ShortcutField: View {
    let shortcut: GlobalShortcut?
    /// Nil clears it.
    let onChange: (GlobalShortcut?) -> Void

    @State private var capture = KeyCapture()
    @State private var isRecording = false
    /// What is held down right now, so the field answers the hand before the
    /// combination is finished.
    @State private var heldModifiers = NSEvent.ModifierFlags()
    /// Set when a combination was refused for having no ⌘, ⌥ or ⌃ in it. The
    /// field stays open — the reader is being told what is missing, not thrown
    /// out for having typed.
    @State private var needsModifier = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(verbatim: label)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
                    .frame(minWidth: 96)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary.opacity(isRecording ? 0.7 : 0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isRecording ? Color.accentColor : .clear,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String.localized("Record a shortcut"))

            Button {
                stop()
                onChange(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String.localized("Clear this shortcut"))
            // Kept in the layout when there is nothing to clear, so the key
            // caps beside each other stay on one line rather than sliding
            // sideways the first time a shortcut is set.
            .opacity(shortcut == nil || isRecording ? 0 : 1)
            .disabled(shortcut == nil || isRecording)
        }
        .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
        // Recording holds the keyboard for the whole app, so it must not
        // survive the pane it was started in.
        .onDisappear(perform: stop)
    }

    private var label: String {
        if isRecording {
            if needsModifier { return .localized("Add ⌘, ⌥ or ⌃") }
            let held = GlobalShortcut.modifierSymbols(heldModifiers)
            return held.isEmpty ? .localized("Press keys…") : held
        }
        if let shortcut { return shortcut.display }
        return .localized("Not set")
    }

    private func start() {
        needsModifier = false
        heldModifiers = []
        isRecording = true

        capture.start(interrupted: { stop() }) { event in
            // Read off the event out here, because an `NSEvent` cannot cross
            // into the isolated body below — a key code and a set of modifier
            // bits can.
            let type = event.type
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags

            let handled = MainActor.assumeIsolated { () -> Bool in
                switch type {
                case .flagsChanged:
                    heldModifiers = modifiers.intersection(GlobalShortcut.allowed)
                    if !heldModifiers.isEmpty { needsModifier = false }
                    return true
                case .keyDown:
                    accept(keyCode: keyCode, modifiers: modifiers)
                    return true
                default:
                    return false
                }
            }

            // Every key the monitor sees while recording is swallowed: half a
            // combination must not reach a text field, and the whole of one
            // must not reach a menu.
            return handled ? nil : event
        }
    }

    private func accept(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Escape leaves it as it was; delete takes it away. Both only bare —
        // ⌘⌫ is a combination somebody may want, and ⎋ with a modifier too.
        let bare = modifiers.intersection(GlobalShortcut.allowed).isEmpty
        if bare, keyCode == GlobalShortcut.escapeKeyCode {
            stop()
            return
        }
        if bare, GlobalShortcut.clearKeyCodes.contains(keyCode) {
            stop()
            onChange(nil)
            return
        }

        guard let shortcut = GlobalShortcut(keyCode: keyCode, modifiers: modifiers) else {
            // Nothing is stored and recording continues: the next press is
            // very likely the same key with a modifier this time.
            needsModifier = true
            return
        }

        stop()
        onChange(shortcut)
    }

    private func stop() {
        capture.stop()
        isRecording = false
        needsModifier = false
        heldModifiers = []
    }
}

/// Owns the local event monitor, because a monitor is a resource with a
/// lifetime and `@State` on a `struct` is not a place to keep one.
@MainActor
private final class KeyCapture {
    private var monitor: Any?
    private var resignObserver: (any NSObjectProtocol)?

    /// Starts recording, and arranges for it to stop again if the settings
    /// window stops being the key window.
    ///
    /// **That second half is not tidiness.** The monitor swallows every key
    /// the app is handed, and closing the settings window does not tear the
    /// view down — the controller keeps the window alive — so a field left
    /// recording would go on eating keystrokes with nothing on screen to say
    /// why.
    func start(
        interrupted: @escaping @MainActor () -> Void,
        handler: @escaping (NSEvent) -> NSEvent?
    ) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: handler)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { interrupted() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }
}

#Preview {
    VStack(spacing: 12) {
        ShortcutField(shortcut: GlobalShortcut(keyCode: 35, modifiers: [.command, .option])) { _ in }
        ShortcutField(shortcut: nil) { _ in }
    }
    .padding(24)
}
