// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// The window `UpdateMessage` is shown in. A regular titled window, so it can
/// be read at leisure and closed like any other.
@MainActor
final class UpdateMessageWindowController {
    private let window: NSWindow

    /// `dismiss` is "Don't show again"; closing the window any other way
    /// leaves the message to come back on the next launch.
    init(version: String, paragraphs: [String], dismiss: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        self.window = window
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UpdateMessageView(
            version: version,
            paragraphs: paragraphs,
            close: { [weak window] in window?.close() },
            dismiss: { [weak window] in
                dismiss()
                window?.close()
            }
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
        window.title = .localized("A note from the developer")
    }
}

struct UpdateMessageView: View {
    let version: String
    let paragraphs: [String]
    let close: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "Pulse \(version)")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(Self.rendered(paragraph))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(String.localized("Don't show again"), action: dismiss)
                Spacer()
                Button(String.localized("Close"), action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 360)
    }

    /// Bold, italics, code and links, as the maintainer wrote them; anything
    /// else in the Markdown is shown as typed rather than dropped.
    static func rendered(_ paragraph: String) -> AttributedString {
        (try? AttributedString(
            markdown: paragraph,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(paragraph)
    }
}

#Preview {
    UpdateMessageView(
        version: "1.12.5",
        paragraphs: [
            "感谢一直使用 Pulse。",
            "这个版本重做了圆环里的**小机器人**，详情见 [更新说明](https://github.com/qunqin24/Pulse/releases/latest)。",
        ],
        close: {},
        dismiss: {}
    )
}
