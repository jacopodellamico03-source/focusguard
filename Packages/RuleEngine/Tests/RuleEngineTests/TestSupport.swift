import Foundation
@testable import RuleEngine

/// Calendario fisso (gregoriano, Europe/Rome) per test deterministici.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
    calendar.locale = Locale(identifier: "it_IT")
    return calendar
}()

/// Data nel fuso Europe/Rome. 2026-11-02 è un lunedì.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var parts = DateComponents()
    parts.year = year
    parts.month = month
    parts.day = day
    parts.hour = hour
    parts.minute = minute
    return testCalendar.date(from: parts)!
}

func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay {
    TimeOfDay(hour: hour, minute: minute)!
}

func limitRule(_ minutes: Int, weekdays: Set<Weekday> = Weekday.all, enabled: Bool = true) -> Rule {
    Rule(name: "Social", kind: .dailyLimit(minutes: minutes), weekdays: weekdays, isEnabled: enabled)
}

func scheduleRule(_ start: TimeOfDay, _ end: TimeOfDay, weekdays: Set<Weekday> = Weekday.all, enabled: Bool = true) -> Rule {
    Rule(name: "Notte", kind: .schedule(start: start, end: end), weekdays: weekdays, isEnabled: enabled)
}
