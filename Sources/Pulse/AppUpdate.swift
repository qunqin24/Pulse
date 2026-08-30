import Foundation
import Observation

/// Whether a newer Pulse has been published.
///
/// A **notice, not an installer**. Pulse isn't signed with a Developer ID yet,
/// and an app that downloads and swaps itself out without one is asking the
/// user to trust something macOS itself refuses to vouch for. So this only
/// ever says "there is a newer one, here it is" and leaves the download to the
/// browser. When there is a Developer ID to sign and notarise with, this is
/// the piece Sparkle replaces.
///
/// It reads GitHub's own idea of the latest release rather than a feed of our
/// own: `/releases/latest` already skips drafts and pre-releases, so tagging a
/// release is the whole publishing step.
///
/// Nothing happens in a build that isn't an app bundle. A loose executable has
/// no version to compare against — `swift run` produces one — and telling a
/// developer their working copy is out of date is noise.
@MainActor
@Observable
final class AppUpdate {
    struct Release: Equatable, Sendable {
        let version: String
        let page: URL
    }

    /// Set only when the published version is actually newer than this one.
    private(set) var newer: Release?
    private(set) var isChecking = false
    private(set) var lastChecked: Date?
    /// The last check couldn't reach GitHub. Worth showing, because otherwise
    /// "no update" and "no answer" look identical.
    private(set) var didFail = false

    /// This build's version, or nil when it isn't running from a bundle.
    var current: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var canCheck: Bool { current != nil }

    private static let endpoint = URL(string: "https://api.github.com/repos/qunqin24/Pulse/releases/latest")!
    private static let interval: TimeInterval = 24 * 3_600
    private static let lastCheckedKey = "update.lastChecked"

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.lastCheckedKey)
        lastChecked = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    /// Once a day, which is often enough for a release and rare enough to stay
    /// well inside GitHub's unauthenticated rate limit.
    func checkIfDue() {
        guard canCheck else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.interval { return }
        check()
    }

    func check() {
        guard canCheck, !isChecking else { return }
        isChecking = true
        didFail = false

        Task { [current] in
            let answer = await Self.latest()

            self.isChecking = false
            self.lastChecked = Date()
            UserDefaults.standard.set(self.lastChecked!.timeIntervalSince1970, forKey: Self.lastCheckedKey)

            switch answer {
            case .none:
                // Nothing published yet. That is an answer, not a failure —
                // and it is the state a repository is in until its first
                // release, which would otherwise show an error indefinitely.
                self.newer = nil
            case .failed:
                self.didFail = true
            case .found(let release):
                // Only ever *newer*. A local build running ahead of the
                // published release — the normal state while working on it —
                // must not be told to downgrade itself.
                self.newer = Self.isNewer(release.version, than: current ?? "0") ? release : nil
            }
        }
    }

    private enum Answer {
        case found(Release)
        /// Reached GitHub; there are no releases.
        case none
        case failed
    }

    private static func latest() async -> Answer {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        // GitHub refuses anonymous requests that don't identify themselves.
        request.setValue("Pulse", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .failed
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        // A repository with no releases answers 404, and so does a private or
        // renamed one. Either way there is nothing to offer.
        case 404: return .none
        default: return .failed
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = root["tag_name"] as? String,
            let page = (root["html_url"] as? String).flatMap(URL.init(string:))
        else { return .failed }

        // Tags are published as `v1.2.0`; the bundle's version is `1.2.0`.
        return .found(Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page))
    }

    /// Compares dot-separated version numbers a component at a time.
    ///
    /// Not a string comparison: "1.10.0" is newer than "1.9.0" and sorts
    /// before it. Missing components count as zero, so "1.2" and "1.2.0" are
    /// the same version rather than different ones.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(of: candidate)
        let right = components(of: current)

        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { part in Int(part.prefix { $0.isNumber }) ?? 0 }
    }
}
