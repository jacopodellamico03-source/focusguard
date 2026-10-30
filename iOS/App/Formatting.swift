import RuleEngine

/// Testi in italiano per l'interfaccia.
enum Formatting {
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }

    static func summary(of rule: Rule) -> String {
        let kind: String
        switch rule.kind {
        case let .dailyLimit(minutes):
            kind = "Max \(duration(minutes: minutes)) al giorno"
        case let .schedule(start, end):
            kind = "Bloccate \(start)–\(end)"
        }
        return "\(kind) · \(days(rule.weekdays))"
    }

    static func days(_ weekdays: Set<Weekday>) -> String {
        if weekdays == Weekday.all { return "tutti i giorni" }
        if weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "lun–ven" }
        if weekdays == [.saturday, .sunday] { return "weekend" }
        return Weekday.mondayFirst
            .filter { weekdays.contains($0) }
            .map { shortName(of: $0) }
            .joined(separator: " ")
    }

    static func shortName(of day: Weekday) -> String {
        switch day {
        case .monday: return "L"
        case .tuesday: return "M"
        case .wednesday: return "M"
        case .thursday: return "G"
        case .friday: return "V"
        case .saturday: return "S"
        case .sunday: return "D"
        }
    }

    static func fullName(of day: Weekday) -> String {
        switch day {
        case .monday: return "lunedì"
        case .tuesday: return "martedì"
        case .wednesday: return "mercoledì"
        case .thursday: return "giovedì"
        case .friday: return "venerdì"
        case .saturday: return "sabato"
        case .sunday: return "domenica"
        }
    }

    static func label(for trigger: MonitorTrigger) -> String {
        switch trigger {
        case .intervalStarted: return "Inizio finestra"
        case .intervalEnded: return "Fine finestra"
        case .thresholdReached: return "Limite raggiunto"
        }
    }

    static func label(for action: ShieldVerdict) -> String {
        switch action {
        case .shield: return "bloccato"
        case .unshield: return "sbloccato"
        case .noChange: return "nessuna azione"
        }
    }
}
