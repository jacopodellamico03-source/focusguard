import Foundation

/// Giorno della settimana con la stessa numerazione di `Calendar` (1 = domenica ... 7 = sabato).
public enum Weekday: Int, Codable, CaseIterable, Comparable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Ordine lunedì → domenica, comodo per l'interfaccia italiana.
    public static let mondayFirst: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    public static let all: Set<Weekday> = Set(allCases)

    public init(date: Date, calendar: Calendar) {
        let value = calendar.component(.weekday, from: date)
        self = Weekday(rawValue: value) ?? .monday
    }
}

/// Tipo di regola.
public enum RuleKind: Codable, Hashable, Sendable {
    /// Le app scelte si bloccano dopo `minutes` minuti d'uso nella giornata.
    /// Con tutte le categorie selezionate diventa il limite di tempo totale.
    case dailyLimit(minutes: Int)
    /// Le app scelte sono bloccate tra `start` e `end` (anche a cavallo della mezzanotte).
    case schedule(start: TimeOfDay, end: TimeOfDay)
}

/// Una regola di blocco. Le app vere (token opachi di Apple) sono salvate a parte,
/// nel livello iOS, con la stessa `id`: così questo pacchetto resta testabile su Linux.
public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: RuleKind
    public var weekdays: Set<Weekday>
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: RuleKind,
        weekdays: Set<Weekday> = Weekday.all,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.weekdays = weekdays
        self.isEnabled = isEnabled
    }

    /// La regola vale nel giorno della settimana di `date`?
    public func appliesOn(_ date: Date, calendar: Calendar) -> Bool {
        weekdays.contains(Weekday(date: date, calendar: calendar))
    }

    /// Per una regola a orario: `date` cade dentro la finestra di blocco?
    /// Per le finestre notturne (es. 22:00–07:00) il giorno che conta è quello in cui la finestra inizia.
    public func isScheduleActive(at date: Date, calendar: Calendar) -> Bool {
        guard isEnabled, case let .schedule(start, end) = kind else { return false }
        let now = TimeOfDay(date: date, calendar: calendar)

        if start < end {
            return now >= start && now < end && appliesOn(date, calendar: calendar)
        }

        // Finestra a cavallo della mezzanotte.
        if now >= start {
            return appliesOn(date, calendar: calendar)
        }
        if now < end {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
            return appliesOn(yesterday, calendar: calendar)
        }
        return false
    }
}
