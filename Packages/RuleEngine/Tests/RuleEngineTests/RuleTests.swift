import XCTest
@testable import RuleEngine

final class TimeOfDayTests: XCTestCase {
    func testRejectsOutOfRange() {
        XCTAssertNil(TimeOfDay(hour: 24, minute: 0))
        XCTAssertNil(TimeOfDay(hour: 10, minute: 60))
        XCTAssertNil(TimeOfDay(hour: -1, minute: 0))
        XCTAssertNotNil(TimeOfDay(hour: 23, minute: 59))
    }

    func testMinutesRoundTrip() {
        XCTAssertEqual(t(1, 30).minutesFromMidnight, 90)
        XCTAssertEqual(TimeOfDay(minutesFromMidnight: 90), t(1, 30))
        XCTAssertNil(TimeOfDay(minutesFromMidnight: 1440))
    }

    func testDescription() {
        XCTAssertEqual(t(7, 5).description, "07:05")
    }

    func testFromDate() {
        XCTAssertEqual(TimeOfDay(date: date(2026, 11, 2, 22, 45), calendar: testCalendar), t(22, 45))
    }
}

final class RuleScheduleTests: XCTestCase {
    func testWeekdayFromDate() {
        XCTAssertEqual(Weekday(date: date(2026, 11, 2), calendar: testCalendar), .monday)
        XCTAssertEqual(Weekday(date: date(2026, 11, 8), calendar: testCalendar), .sunday)
    }

    func testDaytimeWindow() {
        let rule = scheduleRule(t(9), t(13))
        XCTAssertFalse(rule.isScheduleActive(at: date(2026, 11, 2, 8, 59), calendar: testCalendar))
        XCTAssertTrue(rule.isScheduleActive(at: date(2026, 11, 2, 9, 0), calendar: testCalendar))
        XCTAssertTrue(rule.isScheduleActive(at: date(2026, 11, 2, 12, 59), calendar: testCalendar))
        XCTAssertFalse(rule.isScheduleActive(at: date(2026, 11, 2, 13, 0), calendar: testCalendar))
    }

    func testOvernightWindow() {
        let rule = scheduleRule(t(22), t(7))
        XCTAssertTrue(rule.isScheduleActive(at: date(2026, 11, 2, 23, 30), calendar: testCalendar))
        XCTAssertTrue(rule.isScheduleActive(at: date(2026, 11, 3, 6, 59), calendar: testCalendar))
        XCTAssertFalse(rule.isScheduleActive(at: date(2026, 11, 3, 7, 0), calendar: testCalendar))
        XCTAssertFalse(rule.isScheduleActive(at: date(2026, 11, 3, 15, 0), calendar: testCalendar))
    }

    func testOvernightUsesStartDay() {
        // Solo domenica sera: lunedì 06:00 è ancora dentro la finestra iniziata domenica.
        let rule = scheduleRule(t(22), t(7), weekdays: [.sunday])
        XCTAssertTrue(rule.isScheduleActive(at: date(2026, 11, 8, 23, 0), calendar: testCalendar))
        XCTAssertTrue(rule.isScheduleActive(at: date(2026, 11, 9, 6, 0), calendar: testCalendar))
        // Domenica mattina appartiene alla finestra di sabato sera: non attiva.
        XCTAssertFalse(rule.isScheduleActive(at: date(2026, 11, 8, 6, 0), calendar: testCalendar))
    }

    func testWeekdayFilterDaytime() {
        let rule = scheduleRule(t(9), t(17), weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])
        XCTAssertTrue(rule.isScheduleActive(at: date(2026, 11, 6, 10), calendar: testCalendar))   // venerdì
        XCTAssertFalse(rule.isScheduleActive(at: date(2026, 11, 7, 10), calendar: testCalendar))  // sabato
    }

    func testDisabledOrLimitNeverActive() {
        XCTAssertFalse(scheduleRule(t(0), t(23, 59), enabled: false)
            .isScheduleActive(at: date(2026, 11, 2), calendar: testCalendar))
        XCTAssertFalse(limitRule(30).isScheduleActive(at: date(2026, 11, 2), calendar: testCalendar))
    }

    func testCodableRoundTrip() throws {
        let rules = [limitRule(45, weekdays: [.monday]), scheduleRule(t(22), t(7))]
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([Rule].self, from: data)
        XCTAssertEqual(decoded, rules)
    }
}

final class RuleValidatorTests: XCTestCase {
    func testValidRules() {
        XCTAssertEqual(RuleValidator.validate(limitRule(30)), [])
        XCTAssertEqual(RuleValidator.validate(scheduleRule(t(22), t(7))), [])
    }

    func testEmptyNameAndWeekdays() {
        let rule = Rule(name: "  ", kind: .dailyLimit(minutes: 10), weekdays: [])
        XCTAssertEqual(RuleValidator.validate(rule), [.emptyName, .noWeekdays])
    }

    func testLimitRange() {
        XCTAssertEqual(RuleValidator.validate(limitRule(0)), [.limitOutOfRange(minutes: 0)])
        XCTAssertEqual(RuleValidator.validate(limitRule(1440)), [.limitOutOfRange(minutes: 1440)])
        XCTAssertEqual(RuleValidator.validate(limitRule(1439)), [])
    }

    func testScheduleDuration() {
        XCTAssertEqual(RuleValidator.durationMinutes(start: t(22), end: t(7)), 540)
        XCTAssertEqual(RuleValidator.validate(scheduleRule(t(10), t(10, 10))), [.scheduleTooShort(minutes: 10)])
        // 23:50 → 00:05 dura esattamente 15 minuti: valida.
        XCTAssertEqual(RuleValidator.durationMinutes(start: t(23, 50), end: t(0, 5)), 15)
        XCTAssertEqual(RuleValidator.validate(scheduleRule(t(23, 50), t(0, 5))), [])
        XCTAssertEqual(RuleValidator.validate(scheduleRule(t(10), t(10))), [.scheduleEmpty])
    }
}
