import Foundation

/// Errori di validazione, con messaggi pronti per l'interfaccia.
public enum RuleValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyName
    case noWeekdays
    case limitOutOfRange(minutes: Int)
    case scheduleTooShort(minutes: Int)
    case scheduleEmpty

    public var description: String {
        switch self {
        case .emptyName:
            return "Dai un nome alla regola."
        case .noWeekdays:
            return "Scegli almeno un giorno della settimana."
        case let .limitOutOfRange(minutes):
            return "Il limite deve essere tra 1 e \(RuleValidator.maxLimitMinutes) minuti (ora: \(minutes))."
        case let .scheduleTooShort(minutes):
            return "La finestra deve durare almeno \(RuleValidator.minScheduleMinutes) minuti (ora: \(minutes))."
        case .scheduleEmpty:
            return "Inizio e fine coincidono."
        }
    }
}

public enum RuleValidator {
    /// iOS rifiuta le DeviceActivitySchedule più brevi di 15 minuti.
    public static let minScheduleMinutes = 15
    /// Il limite giornaliero vive in una finestra 00:00–23:59.
    public static let maxLimitMinutes = 1439

    /// Durata in minuti della finestra, gestendo il passaggio della mezzanotte.
    public static func durationMinutes(start: TimeOfDay, end: TimeOfDay) -> Int {
        let diff = end.minutesFromMidnight - start.minutesFromMidnight
        return diff >= 0 ? diff : diff + 1440
    }

    /// Restituisce tutti gli errori (lista vuota = regola valida).
    public static func validate(_ rule: Rule) -> [RuleValidationError] {
        var errors: [RuleValidationError] = []

        if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyName)
        }
        if rule.weekdays.isEmpty {
            errors.append(.noWeekdays)
        }

        switch rule.kind {
        case let .dailyLimit(minutes):
            if !(1...maxLimitMinutes).contains(minutes) {
                errors.append(.limitOutOfRange(minutes: minutes))
            }
        case let .schedule(start, end):
            let duration = durationMinutes(start: start, end: end)
            if duration == 0 {
                errors.append(.scheduleEmpty)
            } else if duration < minScheduleMinutes {
                errors.append(.scheduleTooShort(minutes: duration))
            }
        }
        return errors
    }
}
