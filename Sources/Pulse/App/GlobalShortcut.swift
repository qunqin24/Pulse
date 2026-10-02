// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Carbon.HIToolbox

/// A key combination Pulse answers to from anywhere, not only while it is the
/// active application.
///
/// Stored rather than hardcoded, and unset until someone sets one: a default
/// combination is a key taken out of every other app's hands on behalf of a
/// person who never asked for it, and there is no combination free enough to
/// take that way.
struct GlobalShortcut: Equatable, Hashable, Sendable {
    /// The virtual key code, which is a position on the keyboard rather than a
    /// character — the same physical key on every layout.
    let keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw bits, already filtered to the four this can
    /// register. Kept as bits so the whole value stays `Sendable` and can be
    /// written to `UserDefaults` as one short string.
    let modifierBits: UInt

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierBits) }

    /// What may be part of a combination.
    static let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// At least one of these has to be in it.
    ///
    /// Shift alone is not a modifier for this purpose — `⇧P` would take the
    /// letter P away from every text field on the Mac, which is a bug report
    /// from someone who cannot type their own name. Bare keys are refused for
    /// the same reason, function keys included: F1 already belongs to the
    /// display's brightness.
    static let required: NSEvent.ModifierFlags = [.command, .option, .control]

    /// Nil when the combination is not one Pulse is willing to take.
    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let kept = modifiers.intersection(Self.allowed)
        guard !kept.intersection(Self.required).isEmpty else { return nil }
        self.keyCode = keyCode
        self.modifierBits = kept.rawValue
    }

    // MARK: - Storage

    var storage: String { "\(keyCode):\(modifierBits)" }

    /// A stored value that no longer parses — written by a version that stored
    /// them differently, or edited by hand — reads as no shortcut rather than
    /// as a wrong one.
    init?(storage: String) {
        let parts = storage.split(separator: ":")
        guard parts.count == 2,
              let keyCode = UInt16(parts[0]),
              let bits = UInt(parts[1])
        else { return nil }
        self.init(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: bits))
    }

    // MARK: - Display

    /// The combination as macOS writes it: modifiers in the system's own order,
    /// then the key.
    ///
    /// Not localized, and deliberately: these are symbols, not words, and they
    /// are the same on a keyboard in any language.
    var display: String {
        Self.modifierSymbols(modifiers) + Self.label(for: keyCode)
    }

    /// The modifier symbols on their own, in the system's order. Shared with
    /// `display` so a half-pressed combination in the recorder is written the
    /// same way as a finished one.
    static func modifierSymbols(_ modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text
    }

    /// The key's own label.
    ///
    /// A table rather than `UCKeyTranslate`, because what belongs here is what
    /// is *printed on the key* — and the two disagree for every key that
    /// carries a symbol instead of a character. An unlisted code falls back to
    /// its number, which is ugly but honest: better a combination the reader
    /// cannot name than one shown as some other key.
    static func label(for keyCode: UInt16) -> String {
        if let name = names[Int(keyCode)] { return name }
        return "#\(keyCode)"
    }

    private static let names: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "␣", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Help: "?",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_Keypad0: "0", kVK_ANSI_Keypad1: "1", kVK_ANSI_Keypad2: "2",
        kVK_ANSI_Keypad3: "3", kVK_ANSI_Keypad4: "4", kVK_ANSI_Keypad5: "5",
        kVK_ANSI_Keypad6: "6", kVK_ANSI_Keypad7: "7", kVK_ANSI_Keypad8: "8",
        kVK_ANSI_Keypad9: "9",
    ]

    /// Key codes the recorder reads as instructions rather than as the key
    /// being recorded, kept here so `Carbon` stays imported in one file.
    static let escapeKeyCode = UInt16(kVK_Escape)
    static let clearKeyCodes: Set<UInt16> = [UInt16(kVK_Delete), UInt16(kVK_ForwardDelete)]

    // MARK: - Carbon

    /// The same four modifiers in the bits `RegisterEventHotKey` wants.
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}

/// Holds Pulse's global shortcuts registered with the window server.
///
/// `RegisterEventHotKey` rather than an event tap: a tap that sees other apps'
/// keystrokes needs Accessibility permission, and asking for the right to
/// watch everything typed on the Mac in order to open a settings window is not
/// a trade worth offering. Hot keys need no permission at all, and the window
/// server never tells Pulse about any key but the ones it asked for.
@MainActor
@Observable
final class GlobalShortcutMonitor {
    /// What a shortcut can be bound to. The raw value is the id the window
    /// server hands back, so these numbers are part of nothing persisted and
    /// may change freely.
    enum Action: UInt32, CaseIterable, Sendable {
        case openSettings = 1
        case togglePanel = 2
    }

    /// Combinations the window server refused, which is almost always another
    /// app holding the same keys. Read by settings, which is the only place
    /// that can say so — a shortcut that quietly does nothing is worse than no
    /// shortcut, because the reader blames the feature rather than the clash.
    private(set) var unavailable: Set<Action> = []

    private var handlers: [Action: () -> Void] = [:]
    private var registered: [Action: (shortcut: GlobalShortcut, reference: EventHotKeyRef)] = [:]
    private var eventHandler: EventHandlerRef?

    /// Called after a complete pair of registrations has been applied. The
    /// app shell uses this to keep one visible way back into Pulse: a shortcut
    /// stored in Settings is not an entry point if the window server refused
    /// it.
    var onRegistrationChange: (() -> Void)?

    /// Whether either action can currently bring a hidden interface back.
    /// Stored combinations are deliberately not enough; `registered` is the
    /// window server's answer, including conflicts with another app.
    var hasRegisteredEntryPoint: Bool {
        registered[.openSettings] != nil || registered[.togglePanel] != nil
    }

    /// Four characters the window server uses to tell one app's hot keys from
    /// another's: 'PULS'.
    private static let signature: OSType = 0x5055_4C53

    func on(_ action: Action, run handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    /// Brings the registrations in line with what is stored. Safe to call as
    /// often as anything changes: a shortcut that has not moved is left alone
    /// rather than unregistered and registered again.
    func apply(_ settings: AppSettings) {
        update(.openSettings, to: settings.openSettingsShortcut)
        update(.togglePanel, to: settings.togglePanelShortcut)
        onRegistrationChange?()
    }

    private func update(_ action: Action, to shortcut: GlobalShortcut?) {
        if let existing = registered[action] {
            guard existing.shortcut != shortcut else { return }
            UnregisterEventHotKey(existing.reference)
            registered[action] = nil
        }

        unavailable.remove(action)
        guard let shortcut else { return }

        installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: action.rawValue),
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        if status == noErr, let reference {
            registered[action] = (shortcut, reference)
        } else {
            // Including the case where Pulse's own other shortcut already has
            // these keys: the window server refuses the second registration,
            // and the reader is told the same way as for any other clash.
            unavailable.insert(action)
        }
    }

    /// One handler for every hot key, installed the first time one is
    /// registered and left in place afterwards.
    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Unretained: the monitor outlives the handler — it is owned by the
        // app delegate for the life of the process — and retaining it here
        // would be a cycle nothing breaks.
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }

                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard status == noErr else { return status }

                // Carbon dispatches on the main run loop, which is this
                // actor's thread — the assumption is the same one the screen
                // notification observer makes.
                let monitor = Unmanaged<GlobalShortcutMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                MainActor.assumeIsolated { monitor.fire(id.id) }
                return noErr
            },
            1,
            &specification,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func fire(_ id: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        handlers[action]?()
    }
}
