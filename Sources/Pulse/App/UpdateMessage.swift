// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A few words from the maintainer after an update — not the release notes,
/// which Sparkle already shows, but whatever the maintainer wants to say.
///
/// **Read from the repository, not from the bundle**, so it can be written or
/// corrected after a release: `Messages/<version>/<language>.md` on `main`,
/// fetched once per launch through `NetworkSession`, so the Network setting
/// governs it like any other request. No file for this version, or no answer,
/// shows nothing.
///
/// **Shown on every launch after an update until dismissed.** The version is
/// remembered when Pulse first runs it; a later launch of a different version
/// marks that version pending, and it stays pending until "Don't show again".
/// A fresh install has nothing to be told about an update and shows nothing.
/// See `Docs/update-message.md`.
enum UpdateMessage {
    enum Key {
        static let lastLaunched = "settings.lastLaunchedVersion"
        static let pending = "settings.updateMessagePending"
        static let dismissed = "settings.updateMessageDismissed"
    }

    /// The languages a message may be written in, in the strings files'
    /// spelling. Anything else reads the English one.
    static let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "ru"]

    static let base = URL(string: "https://raw.githubusercontent.com/qunqin24/Pulse/main/Messages")!

    /// What one launch decides, kept apart from `UserDefaults` so it can be
    /// tested.
    struct Launch: Equatable {
        /// The version to show a message for now, or nil.
        let shows: String?
        /// What `pending` should hold from now on.
        let pending: String?
    }

    /// `hasRunBefore` covers the update from a version that never recorded
    /// itself: everything before this feature. Without it, the first update
    /// to carry the feature would look like a fresh install and say nothing.
    static func launch(current: String, lastLaunched: String?, hasRunBefore: Bool,
                       pending: String?, dismissed: String?) -> Launch {
        var pending = pending
        if lastLaunched != current {
            pending = (lastLaunched != nil || hasRunBefore) ? current : nil
        }
        let shows = pending == current && dismissed != current ? current : nil
        return Launch(shows: shows, pending: pending)
    }

    /// This build's version, or nil when it is not running from a bundle —
    /// a `swift run` build has nothing to have been updated from.
    static var bundleVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Records this launch. **Called before settings are restored**, which
    /// is what writes `hasRun` on a fresh install; asked afterwards, every
    /// first launch would look like an update.
    static func noteLaunch(current: String? = bundleVersion, defaults: UserDefaults = .standard) {
        guard let current else { return }
        let decision = launch(
            current: current,
            lastLaunched: defaults.string(forKey: Key.lastLaunched),
            hasRunBefore: defaults.object(forKey: ProviderSelection.hasRunKey) != nil,
            pending: defaults.string(forKey: Key.pending),
            dismissed: defaults.string(forKey: Key.dismissed)
        )
        defaults.set(current, forKey: Key.lastLaunched)
        defaults.set(decision.pending, forKey: Key.pending)
    }

    /// The version whose message is due on this launch, or nil.
    static func due(current: String? = bundleVersion, defaults: UserDefaults = .standard) -> String? {
        guard let current,
              defaults.string(forKey: Key.pending) == current,
              defaults.string(forKey: Key.dismissed) != current
        else { return nil }
        return current
    }

    /// "Don't show again", for this version only: the next update's message
    /// still shows.
    static func dismiss(_ version: String, defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: Key.dismissed)
    }

    /// The language to ask for: Pulse's own setting, or macOS's choice among
    /// the six when it follows the system.
    static func language(for chosen: AppLanguage = LocalizationSource.language,
                         preferences: [String] = Locale.preferredLanguages) -> String {
        if let name = chosen.bundleName {
            return languages.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? "en"
        }
        return Bundle.preferredLocalizations(from: languages, forPreferences: preferences).first ?? "en"
    }

    static func url(version: String, language: String) -> URL {
        base.appending(path: version).appending(path: "\(language).md")
    }

    /// The message's paragraphs: separated by a blank line, each one's
    /// line breaks kept. Leading and trailing blank lines are dropped, and an
    /// empty file is no message.
    static func paragraphs(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The message in the reader's language, else in English, else nil.
    static func fetch(version: String, session: URLSession = NetworkSession.shared) async -> [String]? {
        let preferred = language()
        for candidate in preferred == "en" ? ["en"] : [preferred, "en"] {
            var request = URLRequest(url: url(version: version, language: candidate))
            request.timeoutInterval = 15
            // A message corrected after release should be the one shown.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8)
            else { continue }
            let paragraphs = paragraphs(text)
            if !paragraphs.isEmpty { return paragraphs }
        }
        return nil
    }
}
