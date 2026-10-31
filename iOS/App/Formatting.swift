import Foundation
import RuleEngine

/// Testi in italiano per l'interfaccia.
enum Formatting {
    /// Conto alla rovescia, es. "9:05" o "1:00:00". Arrotonda per eccesso: non mostra 0:00 prima del tempo.
    static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let (hours, minutes, seconds) = (total / 3600, total % 3600 / 60, total % 60)
        let tail = String(format: "%02d", seconds)
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(tail)"
        }
        return "\(minutes):\(tail)"
    }

    static func label(for change: PendingRelaxation.Change) -> String {
        switch change {
        case .disableRule: return "Disattivazione"
        case .deleteRule: return "Eliminazione"
        case .editRule: return "Modifica"
        case .disableManualBlock: return "Sblocco"
        case .changeManualSelection: return "Cambio app"
        case .disableAppRemovalProtection: return "Disattivazione"
        case .resetPIN: return "Reset del PIN"
        }
    }

    /// Generico di proposito: finisce sulla schermata di blocco.
    static func notificationBody(for kind: RelaxationNotification.Kind) -> String {
        switch kind {
        case .windowOpened: return "Puoi confermare la modifica in FocusGuard."
        case .expiringSoon: return "La richiesta in FocusGuard scade tra 5 minuti."
        }
    }

    /// Nota sotto l'opzione "Impedisci la disinstallazione delle app".
    static func note(for appRemoval: AppRemovalProtection) -> String? {
        switch appRemoval {
        case .suspended:
            return "Spenta solo per ora: si riaccende da sola appena attivi una regola o il blocco immediato."
        case .reenabledAutomatically:
            return "Si è riaccesa da sola perché hai attivato una regola o il blocco immediato."
        case .enabled, .disabled:
            return nil
        }
    }

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
