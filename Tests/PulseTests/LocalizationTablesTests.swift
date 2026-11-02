import Foundation
import Testing
@testable import Pulse

/// Every language table loads, whole. One malformed line makes macOS drop the
/// entire file and the app falls back to English everywhere — 1.12.5 shipped
/// that way, with every key still present.
struct LocalizationTablesTests {
    @Test("Each language's table parses and has as many entries as English")
    func everyTableLoads() throws {
        let english = try #require(Self.table("en"))
        for language in ["zh-Hans", "zh-Hant", "ja", "ko", "ru"] {
            let table = try #require(Self.table(language), "\(language) does not parse")
            #expect(table.count == english.count, "\(language)")
        }
    }

    @Test("The app's own lookup returns the translation")
    func lookupIsTranslated() {
        LocalizationSource.use(.chineseSimplified)
        defer { LocalizationSource.use(.system) }
        #expect(String.localized("Close") == "关闭")
    }

    /// Pulse's own resource bundle — `Bundle.module` written here would be
    /// the test target's — found by listing it: SwiftPM may lowercase
    /// `zh-Hans.lproj` on the way in, so a lookup by the source spelling can
    /// come up empty.
    private static func table(_ language: String) -> NSDictionary? {
        guard let root = LocalizationSource.moduleBundle.resourceURL,
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil),
              let folder = folders.first(where: {
                  $0.lastPathComponent.caseInsensitiveCompare("\(language).lproj") == .orderedSame
              })
        else { return nil }
        return NSDictionary(contentsOf: folder.appending(path: "Localizable.strings"))
    }
}
