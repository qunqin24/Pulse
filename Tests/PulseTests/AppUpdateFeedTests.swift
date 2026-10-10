import Testing
@testable import Pulse

/// Which feed the updater reads: the mirror or GitHub, and the language
/// Pulse is set to, so the notes in the update window come in that language.
struct AppUpdateFeedTests {
    @Test func followingTheSystemReadsTheMainFeed() {
        #expect(AppUpdate.feedURL(for: .system, host: .mirror) == "https://update.qunqin.org/appcast.xml")
        #expect(AppUpdate.feedURL(for: .system, host: .github)
            == "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast.xml")
    }

    @Test func aChosenLanguageReadsItsOwnFeed() {
        #expect(AppUpdate.feedURL(for: .chineseSimplified, host: .mirror) == "https://update.qunqin.org/appcast-zh.xml")
        // No Traditional notes are written; the Chinese ones read better than English.
        #expect(AppUpdate.feedURL(for: .chineseTraditional, host: .mirror) == "https://update.qunqin.org/appcast-zh.xml")
        #expect(AppUpdate.feedURL(for: .english, host: .github)
            == "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast-en.xml")
        #expect(AppUpdate.feedURL(for: .japanese, host: .mirror) == "https://update.qunqin.org/appcast-en.xml")
        #expect(AppUpdate.feedURL(for: .korean, host: .mirror) == "https://update.qunqin.org/appcast-en.xml")
        #expect(AppUpdate.feedURL(for: .russian, host: .mirror) == "https://update.qunqin.org/appcast-en.xml")
    }

    @Test func gitHubWhenItAnswersTheMirrorWhenNot() {
        var route = AppUpdate.FeedRoute()
        #expect(route.host == .github)
        route.probed(githubReachable: false)
        #expect(route.host == .mirror)
        route.probed(githubReachable: true)
        #expect(route.host == .github)
    }

    @Test func aFailedCheckIsTriedOnceMoreOnTheOtherHost() {
        var route = AppUpdate.FeedRoute()
        // GitHub fails: straight away on the mirror.
        let first = route.failed()
        #expect(first)
        #expect(route.host == .mirror)
        // The mirror fails too: nothing more until the next check.
        let second = route.failed()
        #expect(!second)
        #expect(route.host == .github)
        // A new check that fails is retried again, and an answer resets it.
        let third = route.failed()
        #expect(third)
        route.answered()
        let fourth = route.failed()
        #expect(fourth)
    }

    @Test @MainActor func gitHubIsFirst() {
        #expect(AppUpdate().host == .github)
    }
}
