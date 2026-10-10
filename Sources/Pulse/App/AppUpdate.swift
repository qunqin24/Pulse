// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation
import Sparkle

/// Keeping Pulse up to date, through Sparkle.
///
/// **An EdDSA key is what makes this safe without an Apple Developer ID.**
/// Sparkle refuses any archive not signed by the key in `Info.plist`, whoever
/// served it — so the update path is verifiable even though the app itself
/// carries only an ad-hoc signature. Apple's signing and notarisation are
/// recommended by Sparkle rather than required, and the one thing they would
/// fix — Gatekeeper blocking the *first* launch — is not something an updater
/// can help with anyway.
///
/// **Nothing starts unless Pulse is running from a bundle.** Sparkle needs an
/// `Info.plist` carrying the feed URL and that public key, its framework in
/// `Contents/Frameworks`, and a version to compare against; a `swift run`
/// build has none of them. Started anyway it would log complaints about a
/// missing feed forever, and telling a developer their working copy is out of
/// date is noise.
///
/// Sparkle owns the schedule and the windows it puts up. What is kept here is
/// only what the rest of the app asks about: whether a check can happen at
/// all, whether one is running, and whether a newer version was found — which
/// is what the menu bar shows.
@MainActor
@Observable
final class AppUpdate {
    struct Release: Equatable, Sendable {
        let version: String
    }

    /// Set once Sparkle has found something newer, so the menu bar can say so.
    private(set) var newer: Release?
    private(set) var isChecking = false
    /// The last check couldn't reach the feed. Worth showing, because "no
    /// update" and "no answer" look identical otherwise.
    private(set) var didFail = false

    /// This build's version, or nil when it isn't running from a bundle.
    var current: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var canCheck: Bool { controller != nil }

    /// Sparkle's own daily schedule. Stored by Sparkle, not by `AppSettings`,
    /// so it can't drift from what the updater is actually doing.
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private var controller: SPUStandardUpdaterController?
    private let relay = UpdaterRelay()

    init() {
        // The feed URL is the tell: present only in a bundle built by
        // Scripts/bundle.sh, which is also the only place the framework is.
        guard
            Bundle.main.bundleIdentifier != nil,
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else { return }

        relay.owner = self
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: relay,
            userDriverDelegate: nil
        )
        // Started once GitHub has been tried, so a check due at launch reads
        // the host that answers rather than finding out by failing.
        Task { [weak self] in
            let reachable = await Self.githubReachable()
            guard let self else { return }
            self.route.probed(githubReachable: reachable)
            self.startIfNeeded()
        }
    }

    /// Where the feed is read from: GitHub, or **update.qunqin.org**, a
    /// Cloudflare Worker that passes it through (`Scripts/update-mirror`) for
    /// places that cannot reach GitHub. Which one is `FeedRoute`'s call.
    /// [Docs/update-mirror.md]
    enum FeedHost: Equatable, Sendable {
        case github
        case mirror

        var base: String {
            switch self {
            case .github: "https://raw.githubusercontent.com/qunqin24/Pulse/main/"
            case .mirror: "https://update.qunqin.org/"
            }
        }

        var other: FeedHost { self == .github ? .mirror : .github }
    }

    /// Which host the next check reads, and whether a failed check is tried
    /// again at once on the other. Pure, so the rules can be pinned.
    ///
    /// **GitHub whenever it answers.** A five-second request for the feed
    /// decides before the updater starts and again after every check, so a
    /// Mac that moves between networks follows. **A check that fails is tried
    /// again straight away on the other host** — not two hours later at the
    /// next scheduled one — once: when that fails too, nothing more is tried
    /// until the next check.
    struct FeedRoute: Equatable, Sendable {
        private(set) var host: FeedHost = .github
        private(set) var retried = false

        /// GitHub's feed answered within the timeout, or did not.
        mutating func probed(githubReachable: Bool) {
            host = githubReachable ? .github : .mirror
        }

        /// A check could not reach the feed or the archive. True when it
        /// should be tried again now, on the host this switched to.
        mutating func failed() -> Bool {
            host = host.other
            if retried {
                retried = false
                return false
            }
            retried = true
            return true
        }

        /// A check got an answer, update or not.
        mutating func answered() {
            retried = false
        }
    }

    private var route = FeedRoute()
    /// The feed to read next.
    var host: FeedHost { route.host }
    /// A failed check is to be tried again once Sparkle has ended its cycle.
    private var retryPending = false
    /// The check under way is `probe()`'s, so a retry stays quiet too.
    private var quietCheck = false
    /// Sparkle's updater has been started: after the launch probe, or sooner
    /// when somebody asks for a check before it is back.
    private var isStarted = false

    private func startIfNeeded() {
        guard !isStarted, let controller else { return }
        isStarted = true
        controller.startUpdater()
    }

    /// Whether GitHub's feed answers within five seconds.
    nonisolated static func githubReachable() async -> Bool {
        guard let url = URL(string: FeedHost.github.base + "appcast.xml") else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// The feed for a host and the language Pulse is set to.
    ///
    /// The notes in the update window come in one language: each item in
    /// `appcast.xml` carries one `<description xml:lang>` per language and
    /// Sparkle shows the one the **system's** languages pick, which Pulse's own
    /// language setting cannot reach. So a Pulse set to a language reads that
    /// language's copy of the feed (`appcast-zh.xml`, `appcast-en.xml`, written
    /// by `Scripts/appcast.py` beside the main one). The changelog is written in
    /// Chinese and English; Japanese, Korean and Russian read the English.
    nonisolated static func feedURL(for language: AppLanguage, host: FeedHost) -> String {
        let file = switch language {
        case .system: "appcast.xml"
        case .chineseSimplified, .chineseTraditional: "appcast-zh.xml"
        case .english, .japanese, .korean, .russian: "appcast-en.xml"
        }
        return host.base + file
    }

    /// Asks now, and shows Sparkle's own window with whatever it finds.
    func check() {
        guard let controller else { return }
        startIfNeeded()
        isChecking = true
        didFail = false
        quietCheck = false
        controller.updater.checkForUpdates()
    }

    /// Asks quietly, for a screen that is about to state the result: no
    /// Sparkle window, just `newer` / `didFail` brought up to date. Opening
    /// About calls this, so "up to date" there is an answer, not a default.
    /// Skipped while any check or update is already under way — that one will
    /// report, and starting another would only abort it.
    func probe() {
        startIfNeeded()
        guard
            let updater = controller?.updater,
            !isChecking,
            !updater.sessionInProgress,
            updater.canCheckForUpdates
        else { return }
        isChecking = true
        didFail = false
        quietCheck = true
        updater.checkForUpdateInformation()
    }

    /// Nothing to do: Sparkle runs its own schedule from the moment it starts.
    /// Kept so the app's launch path doesn't have to know which updater is
    /// behind this.
    func checkIfDue() {}

    fileprivate func finishCheck(found item: SUAppcastItem?) {
        isChecking = false
        didFail = false
        route.answered()
        newer = item.map { Release(version: $0.displayVersionString) }
    }

    fileprivate func failCheck(_ failed: Bool, unreachable: Bool) {
        // Tried again on the other host before the row says it failed. (A
        // check asked for with "Check now" has already shown Sparkle's own
        // error alert by here; the retry is a background check, which puts up
        // the update window if it finds one.)
        if unreachable, route.failed() {
            retryPending = true
            return
        }
        isChecking = false
        if failed { didFail = true }
    }

    /// The feed Sparkle asks for at the start of each check.
    fileprivate var feedURLForNextCheck: String {
        Self.feedURL(for: LocalizationSource.language, host: host)
    }

    /// Every cycle ends here, whichever of the calls above it made first, so a
    /// cycle that made none of them cannot leave the row saying "Checking…".
    fileprivate func endCycle() {
        if retryPending {
            retryPending = false
            let quiet = quietCheck
            // Once Sparkle has wound this cycle down. **Not on the next turn**:
            // right after this callback it schedules the next check, which marks
            // a session in progress until an installer-status probe answers a
            // couple of main-queue hops later — a retry asked for in between is
            // refused, and was. So wait for the session to clear, up to a few
            // seconds; a session still going by then is a check Sparkle started
            // itself, which reads the host just switched to anyway.
            Task { @MainActor [weak self] in
                for _ in 0..<30 {
                    guard let self, let updater = self.controller?.updater else { return }
                    if !updater.sessionInProgress {
                        if quiet { updater.checkForUpdateInformation() } else { updater.checkForUpdatesInBackground() }
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                self?.route.answered()
                self?.isChecking = false
            }
            return
        }
        isChecking = false
        quietCheck = false
        // Asked again after every check, so the next one takes GitHub
        // whenever it answers.
        Task { [weak self] in
            let reachable = await Self.githubReachable()
            // Not under a check that has started meanwhile: it is reading the
            // host it was given, and a failure flips from that one.
            guard let self, self.controller?.updater.sessionInProgress != true, !self.isChecking else { return }
            self.route.probed(githubReachable: reachable)
        }
    }
}

/// Sparkle's delegate, kept apart from `AppUpdate` itself.
///
/// `SPUUpdaterDelegate` is an `@objc` protocol, so it has to be an `NSObject`
/// and its methods cannot be main-actor-isolated. Rather than fight that on a
/// type that is also `@Observable`, this stands between the two and hops onto
/// the main actor — where Sparkle calls it from in any case.
private final class UpdaterRelay: NSObject, SPUUpdaterDelegate {
    /// Weak: the app owns the updater, not the other way round.
    weak var owner: AppUpdate?

    /// Read at every check, so a language changed in Settings, or a host
    /// switched after a failure, applies to the next one.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { owner?.feedURLForNextCheck }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { owner?.finishCheck(found: item) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { owner?.finishCheck(found: nil) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        // Sparkle aborts for benign reasons too — the user closing its window
        // is one — and reporting those as "couldn't reach the feed" would be a
        // lie on the one row that exists to tell the truth about that. Only a
        // failure to *reach or read* the feed counts.
        //
        // Sparkle reports a feed it could not fetch, and an archive it could
        // not download, as `SUDownloadError` wrapping the URL error — never a
        // bare `NSURLErrorDomain` and never `SUAppcastError`, which nothing in
        // Sparkle raises. A feed that came back as something else (a captive
        // portal's page) is `SUAppcastParseError`. All of them are "could not
        // reach or read", and all are tried again on the other host
        // (`FeedRoute`); the archive comes from the host the feed did — the
        // mirror rewrites the feed's downloads to itself.
        let nsError = error as NSError
        let unreachable = nsError.domain == NSURLErrorDomain
            || (nsError.domain == SUSparkleErrorDomain && [
                SUError.downloadError.rawValue, SUError.appcastParseError.rawValue, SUError.appcastError.rawValue,
            ].contains(Int32(nsError.code)))
        MainActor.assumeIsolated { owner?.failCheck(unreachable, unreachable: unreachable) }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated { owner?.endCycle() }
    }
}
