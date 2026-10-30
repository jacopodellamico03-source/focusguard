import XCTest
@testable import RuleEngine

final class ActivityNamingTests: XCTestCase {
    func testRoundTrip() {
        let id = UUID()
        let name = ActivityNaming.activityName(for: id)
        XCTAssertTrue(name.hasPrefix("rule."))
        XCTAssertEqual(ActivityNaming.ruleID(fromActivityName: name), id)
    }

    func testRejectsForeignNames() {
        XCTAssertNil(ActivityNaming.ruleID(fromActivityName: "manual"))
        XCTAssertNil(ActivityNaming.ruleID(fromActivityName: "rule.not-a-uuid"))
    }
}

final class MonitoringPlanTests: XCTestCase {
    func testLimitBecomesFullDayWithThreshold() throws {
        let rule = limitRule(45)
        let specs = try MonitoringPlan.build(from: [rule])
        XCTAssertEqual(specs, [ActivitySpec(
            ruleID: rule.id,
            activityName: ActivityNaming.activityName(for: rule.id),
            intervalStart: .midnight,
            intervalEnd: .endOfDay,
            thresholdMinutes: 45
        )])
    }

    func testScheduleKeepsWindowWithoutThreshold() throws {
        let rule = scheduleRule(t(22), t(7))
        let spec = try XCTUnwrap(MonitoringPlan.build(from: [rule]).first)
        XCTAssertEqual(spec.intervalStart, t(22))
        XCTAssertEqual(spec.intervalEnd, t(7))
        XCTAssertNil(spec.thresholdMinutes)
    }

    func testSkipsDisabledAndInvalid() throws {
        let rules = [limitRule(30, enabled: false), limitRule(0), scheduleRule(t(9), t(9, 5)), limitRule(20)]
        XCTAssertEqual(try MonitoringPlan.build(from: rules).count, 1)
    }

    func testDiffTouchesOnlyChanges() throws {
        let keep = limitRule(30)
        var changed = limitRule(60)
        let removed = scheduleRule(t(22), t(7))
        let old = try MonitoringPlan.build(from: [keep, changed, removed])

        changed.kind = .dailyLimit(minutes: 45)
        let added = scheduleRule(t(9), t(12))
        let new = try MonitoringPlan.build(from: [keep, changed, added])

        let diff = MonitoringPlan.diff(old: old, new: new)
        XCTAssertEqual(Set(diff.toStop), Set([changed.id, removed.id].map(ActivityNaming.activityName(for:))))
        XCTAssertEqual(Set(diff.toStart.map(\.ruleID)), [changed.id, added.id])
        XCTAssertEqual(diff.removedRuleIDs, [removed.id])
    }

    func testDiffForceRestartAndNoop() throws {
        let rule = limitRule(30)
        let plan = try MonitoringPlan.build(from: [rule])
        XCTAssertTrue(MonitoringPlan.diff(old: plan, new: plan).isEmpty)

        let forced = MonitoringPlan.diff(old: plan, new: plan, forceRestart: [rule.id])
        XCTAssertEqual(forced.toStop, [ActivityNaming.activityName(for: rule.id)])
        XCTAssertEqual(forced.toStart.map(\.ruleID), [rule.id])
        XCTAssertTrue(forced.removedRuleIDs.isEmpty)
    }

    func testSpecCodable() throws {
        let plan = try MonitoringPlan.build(from: [limitRule(30), scheduleRule(t(22), t(7))])
        let decoded = try JSONDecoder().decode([ActivitySpec].self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded, plan)
    }

    func testTooManyActivities() {
        let rules = (0..<21).map { _ in limitRule(10) }
        XCTAssertThrowsError(try MonitoringPlan.build(from: rules)) { error in
            XCTAssertEqual(error as? MonitoringPlanError, .tooManyActivities(count: 21, max: 20))
        }
    }
}

final class ShieldDecisionTests: XCTestCase {
    let monday = date(2026, 11, 2, 15)
    let saturday = date(2026, 11, 7, 15)

    func testLimitLifecycle() {
        let rule = limitRule(30)
        XCTAssertEqual(ShieldDecision.action(for: .intervalStarted, rule: rule, at: monday, calendar: testCalendar), .unshield)
        XCTAssertEqual(ShieldDecision.action(for: .thresholdReached, rule: rule, at: monday, calendar: testCalendar), .shield)
        XCTAssertEqual(ShieldDecision.action(for: .intervalEnded, rule: rule, at: monday, calendar: testCalendar), .unshield)
    }

    func testLimitIgnoredOnOtherDays() {
        let rule = limitRule(30, weekdays: [.monday])
        XCTAssertEqual(ShieldDecision.action(for: .thresholdReached, rule: rule, at: saturday, calendar: testCalendar), .noChange)
    }

    func testScheduleLifecycle() {
        let rule = scheduleRule(t(22), t(7), weekdays: [.monday])
        XCTAssertEqual(ShieldDecision.action(for: .intervalStarted, rule: rule, at: monday, calendar: testCalendar), .shield)
        XCTAssertEqual(ShieldDecision.action(for: .intervalStarted, rule: rule, at: saturday, calendar: testCalendar), .noChange)
        XCTAssertEqual(ShieldDecision.action(for: .intervalEnded, rule: rule, at: saturday, calendar: testCalendar), .unshield)
        XCTAssertEqual(ShieldDecision.action(for: .thresholdReached, rule: rule, at: monday, calendar: testCalendar), .noChange)
    }

    func testDisabledAlwaysUnshields() {
        let rule = limitRule(30, enabled: false)
        XCTAssertEqual(ShieldDecision.action(for: .thresholdReached, rule: rule, at: monday, calendar: testCalendar), .unshield)
    }
}
