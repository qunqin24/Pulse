import Foundation
import Testing
@testable import Pulse

@Suite("Browser cookie stores")
struct BrowserCookiesTests {
    @Test("Zen is a Firefox fork: no keychain prompt")
    func zenIsGecko() {
        #expect(BrowserCookies.Browser.zen.name == "Zen")
        #expect(BrowserCookies.Browser.zen.promptsForKeychain == false)
        #expect(BrowserCookies.Browser.zen.keychainService == nil)
    }

    @Test("A Zen profile on this Mac is offered in the picker")
    func zenDetectedWhenInstalled() {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/zen/Profiles")
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        #expect(BrowserCookies.present().contains(.zen))
        // The browser may be running; a locked store must not crash the read.
        _ = BrowserCookies.session(forHost: "example.com", allowing: [.zen]) { $0 }
    }
}
