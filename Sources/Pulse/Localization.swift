import Foundation
import SwiftUI

/// The interface language: whatever the system is set to, or one the user has
/// picked explicitly.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case chineseSimplified

    var id: String { rawValue }

    /// The locale to format dates, times and money in.
    ///
    /// Strings and numbers have to agree: picking English and then being told
    /// a credit expires "in 22天8小时" is the sort of half-translated seam
    /// that makes an app feel unfinished.
    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en_US")
        case .chineseSimplified: Locale(identifier: "zh_Hans")
        }
    }

    /// Name of the `.lproj` folder to read strings from, or `nil` to let the
    /// system choose. Lowercased because SwiftPM lowercases these folder
    /// names when it builds the resource bundle.
    var bundleName: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .chineseSimplified: "zh-hans"
        }
    }

    /// Languages are conventionally listed in their own language, so only the
    /// "follow the system" option gets translated.
    var title: String {
        switch self {
        case .system: .localized("System")
        case .english: "English"
        case .chineseSimplified: "简体中文"
        }
    }
}

/// Where `String.localized(_:)` reads from.
///
/// Normally the module's own bundle, which resolves against the system
/// language. Picking a language in settings swaps in that language's `.lproj`
/// sub-bundle instead, so the change takes effect immediately rather than on
/// the next launch.
enum LocalizationSource {
    private static let lock = NSLock()
    // Written only from the main thread when the setting changes, read from
    // anywhere a string is looked up; the lock covers the crossing.
    nonisolated(unsafe) private static var override: Bundle?
    nonisolated(unsafe) private static var chosen: AppLanguage = .system

    static var bundle: Bundle {
        lock.withLock { override } ?? .module
    }

    /// The locale that goes with the language the strings are coming from.
    static var locale: Locale {
        lock.withLock { chosen }.locale
    }

    static func use(_ language: AppLanguage) {
        lock.withLock {
            chosen = language
            override = language.bundleName.flatMap(loadTable)
        }
    }

    /// Finds a language's `.lproj` bundle.
    ///
    /// Resolved against the names the bundle itself reports rather than a
    /// hardcoded folder name: SwiftPM lowercases `zh-Hans.lproj` on the way
    /// into the built bundle, and there is no guarantee about the casing it
    /// will use, so anything that assumes one spelling can come up empty —
    /// silently, leaving the app in the system language with no clue why.
    private static func loadTable(named name: String) -> Bundle? {
        let match = Bundle.module.localizations.first {
            $0.caseInsensitiveCompare(name) == .orderedSame
        } ?? name

        if let path = Bundle.module.path(forResource: match, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        // Fall back to building the path by hand, in case the resource lookup
        // above doesn't consider `.lproj` directories.
        return Bundle.module.resourceURL
            .map { $0.appendingPathComponent("\(match).lproj") }
            .flatMap { Bundle(url: $0) }
    }
}

extension LocalizationSource {
    /// Whether large numbers should be grouped the East Asian way — by 万
    /// (10⁴) and 亿 (10⁸) — instead of by thousands.
    ///
    /// Chinese doesn't group in thousands, so "419M" is something a reader has
    /// to convert in their head before it means anything. The unit characters
    /// are written here rather than in the strings file on purpose: they
    /// belong to the numeral system, not to the copy, and a translator being
    /// offered them as text to change would be a mistake waiting to happen.
    static var groupsByTenThousands: Bool {
        locale.language.languageCode?.identifier == "zh"
    }
}

extension String {
    /// Looks a key up in the app's current language.
    ///
    /// Always use this instead of letting SwiftUI localize implicitly.
    /// `Text("Some text")` and friends resolve against `Bundle.main`, which
    /// for a SwiftPM target is the bare executable — the `.lproj` folders
    /// live in `Bundle.module`, so implicit lookups silently fall through to
    /// the key itself and the app stays in English no matter the system
    /// language or the user's choice.
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: LocalizationSource.bundle)
    }
}

extension Text {
    /// `Text` that resolves its key in the app's current language. See
    /// `String.localized(_:)` for why the implicit form can't be used.
    init(localized key: String.LocalizationValue) {
        self.init(String.localized(key))
    }
}
