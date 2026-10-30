import XCTest
@testable import RuleEngine

final class ChangePolicyTests: XCTestCase {
    func testCreateAndDelete() {
        let rule = limitRule(30)
        XCTAssertEqual(ChangePolicy.impact(old: nil, new: rule, selectionChanged: false), .tightening)
        XCTAssertEqual(ChangePolicy.impact(old: rule, new: nil, selectionChanged: false), .relaxing)
        XCTAssertEqual(ChangePolicy.impact(old: limitRule(30, enabled: false), new: nil, selectionChanged: false), .neutral)
    }

    func testToggle() {
        let on = limitRule(30)
        var off = on
        off.isEnabled = false
        XCTAssertEqual(ChangePolicy.impact(old: on, new: off, selectionChanged: false), .relaxing)
        XCTAssertEqual(ChangePolicy.impact(old: off, new: on, selectionChanged: false), .tightening)
    }

    func testLimitMinutes() {
        let old = limitRule(30)
        var more = old
        more.kind = .dailyLimit(minutes: 60)
        var less = old
        less.kind = .dailyLimit(minutes: 15)
        XCTAssertEqual(ChangePolicy.impact(old: old, new: more, selectionChanged: false), .relaxing)
        XCTAssertEqual(ChangePolicy.impact(old: old, new: less, selectionChanged: false), .tightening)
    }

    func testNameOnlyIsNeutral() {
        let old = limitRule(30)
        var renamed = old
        renamed.name = "Altro nome"
        XCTAssertEqual(ChangePolicy.impact(old: old, new: renamed, selectionChanged: false), .neutral)
    }

    func testSelectionChangeIsRelaxing() {
        let old = limitRule(30)
        XCTAssertEqual(ChangePolicy.impact(old: old, new: old, selectionChanged: true), .relaxing)
    }

    func testWeekdays() {
        let old = limitRule(30, weekdays: [.monday, .tuesday])
        var fewer = old
        fewer.weekdays = [.monday]
        var more = old
        more.weekdays = [.monday, .tuesday, .friday]
        XCTAssertEqual(ChangePolicy.impact(old: old, new: fewer, selectionChanged: false), .relaxing)
        XCTAssertEqual(ChangePolicy.impact(old: old, new: more, selectionChanged: false), .tightening)
    }

    func testScheduleWindow() {
        let old = scheduleRule(t(22), t(7))
        var wider = old
        wider.kind = .schedule(start: t(21), end: t(7))
        var narrower = old
        narrower.kind = .schedule(start: t(23), end: t(7))
        var shifted = old
        shifted.kind = .schedule(start: t(23), end: t(8))
        XCTAssertEqual(ChangePolicy.impact(old: old, new: wider, selectionChanged: false), .tightening)
        XCTAssertEqual(ChangePolicy.impact(old: old, new: narrower, selectionChanged: false), .relaxing)
        XCTAssertEqual(ChangePolicy.impact(old: old, new: shifted, selectionChanged: false), .relaxing)
    }

    func testKindChangeIsRelaxing() {
        let old = limitRule(30)
        var changed = old
        changed.kind = .schedule(start: t(0), end: t(23, 59))
        XCTAssertEqual(ChangePolicy.impact(old: old, new: changed, selectionChanged: false), .relaxing)
    }
}

final class CooldownTests: XCTestCase {
    func testCooldown() {
        let start = date(2026, 11, 2, 10)
        let cooldown = Cooldown(requestedAt: start, duration: 600)
        XCTAssertFalse(cooldown.canConfirm(at: start.addingTimeInterval(599)))
        XCTAssertTrue(cooldown.canConfirm(at: start.addingTimeInterval(600)))
        XCTAssertEqual(cooldown.remaining(at: start.addingTimeInterval(100)), 500)
        XCTAssertEqual(cooldown.remaining(at: start.addingTimeInterval(9_999)), 0)
    }
}

final class EventLogTests: XCTestCase {
    func testRoundTripAndCorruptLines() throws {
        let entries = [
            EventLogEntry(date: date(2026, 11, 2, 22), ruleID: UUID(), trigger: .intervalStarted, action: .shield),
            EventLogEntry(date: date(2026, 11, 3, 7), ruleID: nil, trigger: .intervalEnded, action: .unshield, note: "test")
        ]
        var data = try EventLogCodec.encodeAll(entries)
        data.append(Data("{riga rotta\n".utf8))
        XCTAssertEqual(EventLogCodec.decode(data), entries)
    }

    func testPrune() {
        let now = date(2026, 11, 30, 12)
        let old = EventLogEntry(date: date(2026, 10, 1), ruleID: nil, trigger: .intervalEnded, action: .noChange)
        let recent = EventLogEntry(date: date(2026, 11, 29), ruleID: nil, trigger: .intervalEnded, action: .noChange)
        XCTAssertEqual(EventLogCodec.pruned([old, recent], keepingDays: 14, now: now), [recent])
    }
}
