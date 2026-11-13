import XCTest
@testable import MacSleep

final class CatchUpTests: XCTestCase {
    /// « Éteindre à 0:30 » and « Réveiller ou allumer à 8:30 », every day.
    private let night = [
        Rule(action: .shutdown, at: 30, days: Weekday.all),
        Rule(action: .wakeorpoweron, at: 8 * 60 + 30, days: Weekday.all),
    ]

    private func today(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testMacOnAt0045IsCaughtUp() {
        let missed = CatchUp.missed(night, now: today(0, 45))
        XCTAssertEqual(missed?.action, .shutdown)
        XCTAssertEqual(missed?.date, today(0, 30))
    }

    func testStillCaughtUpLaterInTheNight() {
        XCTAssertEqual(CatchUp.missed(night, now: today(6, 0))?.action, .shutdown)
    }

    func testNothingInTheDay() {
        XCTAssertNil(CatchUp.missed(night, now: today(9, 0)))
        XCTAssertNil(CatchUp.missed(night, now: today(23, 0)))
    }

    func testNothingRightAfterTheNightEvent() {
        // pmset is doing the shutdown itself.
        XCTAssertNil(CatchUp.missed(night, now: today(0, 30).addingTimeInterval(30)))
    }

    func testNothingWhenTheWakeIsClose() {
        // A wake a little early, or the catch-up would land after it.
        XCTAssertNil(CatchUp.missed(night, now: today(8, 20)))
        XCTAssertNil(CatchUp.missed(night, now: today(8, 29)))
    }

    func testNothingWithoutAWakeRule() {
        XCTAssertNil(CatchUp.missed([night[0]], now: today(0, 45)))
    }

    func testSleepRuleIsCaughtUpAsSleep() {
        let rules = [Rule(action: .sleep, at: 23 * 60 + 30, days: Weekday.all), night[1]]
        XCTAssertEqual(CatchUp.missed(rules, now: today(23, 50))?.action, .sleep)
        XCTAssertEqual(CatchUp.missed(rules, now: today(2, 0))?.action, .sleep)
    }

    func testOnlyOnTheRuleDays() {
        // Shutdown on the day before only: tonight is not a MacSleep night.
        let yesterday = Weekday(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let rules = [Rule(action: .shutdown, at: 30, days: [yesterday]), night[1]]
        XCTAssertNil(CatchUp.missed(rules, now: today(0, 45)))
    }
}

final class SettingsTests: XCTestCase {
    func testReadsTheBareListOfVersion1() throws {
        let rules = [Rule(action: .shutdown, at: 30, days: Weekday.all)]
        let data = try JSONEncoder().encode(rules)
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(settings.rules, rules)
        XCTAssertTrue(settings.catchUp)
    }

    func testRoundTrip() throws {
        let settings = Settings(rules: [Rule()], catchUp: false)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Rules.encode(settings)), settings)
    }
}

final class UpdateTests: XCTestCase {
    func testPicksTheMacZip() {
        XCTAssertEqual(SelfUpdate.macZip(among: ["MacSleep-1.1.0-macOS-arm64.zip"]), "MacSleep-1.1.0-macOS-arm64.zip")
        XCTAssertTrue(SelfUpdate.isNewer("1.1.0", than: "1.0"))
    }
}

final class TonightOnlyTests: XCTestCase {
    private let sleep = Rule(action: .sleep, at: 30, days: Weekday.all)
    private let wake = Rule(action: .wakeorpoweron, at: 8 * 60 + 30, days: Weekday.all)

    private func day(_ offset: Int, _ hour: Int, _ minute: Int) -> Date {
        let d = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
    }

    private func dates(_ rules: [Rule], _ exceptions: [Exception] = [], from: Date, days: Int = 3) -> [Date] {
        Rules.events(rules, exceptions: exceptions, after: from, until: from.addingTimeInterval(Double(days) * 86_400)).map(\.date)
    }

    func testASwitchedOffRuleDoesNothing() {
        var off = sleep
        off.enabled = false
        XCTAssertEqual(dates([off, wake], from: day(0, 12, 0)), dates([wake], from: day(0, 12, 0)))
        // Without a wake rule switched on, there is no night to catch up.
        var noWake = wake
        noWake.enabled = false
        XCTAssertNil(CatchUp.missed([sleep, noWake], now: day(0, 1, 0)))
    }

    func testSkippingOnlyTheNextOccurrence() {
        let tonight = day(1, 0, 30)
        let skipped = [Exception(rule: sleep.id, date: tonight, moved: nil)]
        let all = dates([sleep], skipped, from: day(0, 12, 0))
        XCTAssertFalse(all.contains(tonight))
        XCTAssertTrue(all.contains(day(2, 0, 30))) // back the next night
    }

    func testMovingTheNextOccurrence() {
        let tonight = day(1, 0, 30), later = day(1, 2, 0)
        let moved = [Exception(rule: sleep.id, date: tonight, moved: later)]
        let all = dates([sleep], moved, from: day(0, 12, 0))
        XCTAssertFalse(all.contains(tonight))
        XCTAssertTrue(all.contains(later))
        // Still to come at 1:00, although the occurrence it replaces is past.
        XCTAssertEqual(dates([sleep], moved, from: day(1, 1, 0), days: 1).first, later)
    }

    func testNoCatchUpAfterASkippedNight() {
        let skipped = [Exception(rule: sleep.id, date: day(0, 0, 30), moved: nil)]
        XCTAssertNotNil(CatchUp.missed([sleep, wake], now: day(0, 1, 0)))
        XCTAssertNil(CatchUp.missed([sleep, wake], exceptions: skipped, now: day(0, 1, 0)))
    }

    func testCatchUpWaitsForAMovedNight() {
        let moved = [Exception(rule: sleep.id, date: day(0, 0, 30), moved: day(0, 2, 0))]
        XCTAssertNil(CatchUp.missed([sleep, wake], exceptions: moved, now: day(0, 1, 0)))
        XCTAssertEqual(CatchUp.missed([sleep, wake], exceptions: moved, now: day(0, 2, 30))?.date, day(0, 2, 0))
    }

    func testNextOccurrence() {
        XCTAssertEqual(Rules.next(sleep, after: day(0, 12, 0)), day(1, 0, 30))
    }

    func testOldExceptionsAndRulesAreDropped() {
        let old = Exception(rule: sleep.id, date: day(-3, 0, 30), moved: nil)
        let current = Exception(rule: sleep.id, date: day(1, 0, 30), moved: nil)
        let orphan = Exception(rule: UUID(), date: day(1, 0, 30), moved: nil)
        let s = Settings(rules: [sleep], exceptions: [old, current, orphan]).pruned()
        XCTAssertEqual(s.exceptions, [current])
    }

    func testRulesOfVersion11AreOn() throws {
        let json = #"{"rules":[{"id":"14E59E3A-0C3C-4DE1-B043-660BD5A51F25","action":"sleep","at":30,"days":[0,1,2,3,4,5,6]}],"catchUp":true}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertTrue(s.rules[0].enabled)
        XCTAssertEqual(s.exceptions, [])
        let round = Settings(rules: [sleep], exceptions: [Exception(rule: sleep.id, date: day(1, 0, 30), moved: day(1, 2, 0))])
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Rules.encode(round)), round)
    }
}
