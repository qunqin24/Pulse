import Foundation
import Testing
@testable import Pulse

/// When the one request for a GitHub star is due. See `Docs/ui/settings.md`.
struct StarRequestTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double, hour: Double = 0) -> Date { start.addingTimeInterval((n * 24 + hour) * 3600) }

    @Test("The first sighting starts the count; a new calendar day adds one, the same day does not")
    func counting() {
        var record = StarRequest.noting(.init(), now: day(0), calendar: calendar)
        #expect(record.since == day(0) && record.days == 1)
        record = StarRequest.noting(record, now: day(0, hour: 1), calendar: calendar)
        #expect(record.days == 1)
        record = StarRequest.noting(record, now: day(3), calendar: calendar)
        #expect(record.days == 2 && record.since == day(0))
    }

    @Test("Due only after fourteen days and on the seventh day of use, and never once shown")
    func due() {
        var record = StarRequest.Record(since: day(0), days: 7)
        #expect(!StarRequest.isDue(record, now: day(13.9)))
        #expect(StarRequest.isDue(record, now: day(14)))
        record.days = 6
        #expect(!StarRequest.isDue(record, now: day(60)), "installed and forgotten is never asked")
        record.days = 30
        record.shown = true
        #expect(!StarRequest.isDue(record, now: day(60)))
        #expect(!StarRequest.isDue(.init(), now: day(60)))
    }

    @Test("Through the defaults: counted, then claimed exactly once")
    func throughDefaults() {
        let (defaults, cleanup) = TestDefaults.make("StarRequest")
        defer { cleanup() }
        for n in 0..<7 { StarRequest.noteActive(now: day(Double(n) * 2), defaults: defaults) }
        #expect(StarRequest.record(in: defaults).days == 7)
        #expect(!StarRequest.claimIfDue(now: day(13), defaults: defaults))
        #expect(StarRequest.claimIfDue(now: day(15), defaults: defaults))
        #expect(!StarRequest.claimIfDue(now: day(16), defaults: defaults))
        #expect(defaults.bool(forKey: StarRequest.Key.shown))
    }
}
