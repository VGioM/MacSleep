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
