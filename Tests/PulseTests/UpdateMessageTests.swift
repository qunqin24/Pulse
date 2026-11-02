import Foundation
import Testing
@testable import Pulse

/// When the maintainer's note after an update shows, and where it is read
/// from. See `Docs/update-message.md`.
struct UpdateMessageTests {
    @Test("A fresh install shows nothing; the first update to carry this does")
    func freshInstallVersusUpdate() {
        let fresh = UpdateMessage.launch(current: "1.12.5", lastLaunched: nil, hasRunBefore: false,
                                         pending: nil, dismissed: nil)
        #expect(fresh == .init(shows: nil, pending: nil))
        let upgraded = UpdateMessage.launch(current: "1.12.5", lastLaunched: nil, hasRunBefore: true,
                                            pending: nil, dismissed: nil)
        #expect(upgraded == .init(shows: "1.12.5", pending: "1.12.5"))
    }

    @Test("It shows on every launch of that version until dismissed, and the next update's shows again")
    func everyLaunchUntilDismissed() {
        let again = UpdateMessage.launch(current: "1.12.5", lastLaunched: "1.12.5", hasRunBefore: true,
                                         pending: "1.12.5", dismissed: nil)
        #expect(again.shows == "1.12.5")
        let dismissed = UpdateMessage.launch(current: "1.12.5", lastLaunched: "1.12.5", hasRunBefore: true,
                                             pending: "1.12.5", dismissed: "1.12.5")
        #expect(dismissed.shows == nil)
        let next = UpdateMessage.launch(current: "1.12.6", lastLaunched: "1.12.5", hasRunBefore: true,
                                        pending: "1.12.5", dismissed: "1.12.5")
        #expect(next == .init(shows: "1.12.6", pending: "1.12.6"))
    }

    @Test("Recorded before settings are restored, through the defaults")
    func throughDefaults() throws {
        let (defaults, cleanup) = TestDefaults.make("UpdateMessage")
        defer { cleanup() }
        UpdateMessage.noteLaunch(current: "1.12.5", defaults: defaults)
        #expect(UpdateMessage.due(current: "1.12.5", defaults: defaults) == nil)

        defaults.set(true, forKey: ProviderSelection.hasRunKey)
        UpdateMessage.noteLaunch(current: "1.12.6", defaults: defaults)
        #expect(UpdateMessage.due(current: "1.12.6", defaults: defaults) == "1.12.6")
        UpdateMessage.noteLaunch(current: "1.12.6", defaults: defaults)
        #expect(UpdateMessage.due(current: "1.12.6", defaults: defaults) == "1.12.6")

        UpdateMessage.dismiss("1.12.6", defaults: defaults)
        #expect(UpdateMessage.due(current: "1.12.6", defaults: defaults) == nil)
        #expect(UpdateMessage.due(current: nil, defaults: defaults) == nil)
    }

    @Test("The reader's language, macOS's choice when following the system, English otherwise")
    func language() {
        #expect(UpdateMessage.language(for: .chineseTraditional) == "zh-Hant")
        #expect(UpdateMessage.language(for: .russian) == "ru")
        #expect(UpdateMessage.language(for: .system, preferences: ["zh-Hans-CN"]) == "zh-Hans")
        #expect(UpdateMessage.language(for: .system, preferences: ["fr-FR"]) == "en")
        #expect(UpdateMessage.url(version: "1.12.5", language: "zh-Hans").absoluteString
            == "https://raw.githubusercontent.com/qunqin24/Pulse/main/Messages/1.12.5/zh-Hans.md")
    }

    @Test("Paragraphs split on blank lines; an empty file is no message")
    func paragraphs() {
        #expect(UpdateMessage.paragraphs("\n第一段\n第二行\r\n\r\n第二段\n\n\n") == ["第一段\n第二行", "第二段"])
        #expect(UpdateMessage.paragraphs(" \n\n ").isEmpty)
    }
}
