import Foundation

/// Ora del giorno (ore e minuti), indipendente dalla data.
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    /// Restituisce nil se ore o minuti sono fuori intervallo.
    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Minuti trascorsi dalla mezzanotte (0...1439).
    public var minutesFromMidnight: Int { hour * 60 + minute }

    public init?(minutesFromMidnight: Int) {
        guard (0..<1440).contains(minutesFromMidnight) else { return nil }
        self.hour = minutesFromMidnight / 60
        self.minute = minutesFromMidnight % 60
    }

    /// Estrae l'ora del giorno da una data nel calendario indicato.
    public init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.hour = parts.hour ?? 0
        self.minute = parts.minute ?? 0
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }

    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static let midnight = TimeOfDay(hour: 0, minute: 0)!
    public static let endOfDay = TimeOfDay(hour: 23, minute: 59)!
}
