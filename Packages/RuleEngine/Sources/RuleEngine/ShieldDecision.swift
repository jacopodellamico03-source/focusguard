import Foundation

/// Cosa ha svegliato l'estensione Monitor.
public enum MonitorTrigger: String, Codable, Sendable {
    case intervalStarted
    case intervalEnded
    case thresholdReached
}

/// Cosa deve fare l'estensione.
public enum ShieldVerdict: String, Codable, Equatable, Sendable {
    case shield
    case unshield
    case noChange
}

/// Decide se bloccare o sbloccare. Tutta la logica sta qui, così è testabile su Linux
/// e l'estensione iOS si limita a eseguire.
public enum ShieldDecision {
    public static func action(
        for trigger: MonitorTrigger,
        rule: Rule,
        at date: Date,
        calendar: Calendar
    ) -> ShieldVerdict {
        // Regola disattivata: qualunque evento porta allo sblocco, per non lasciare blocchi appesi.
        guard rule.isEnabled else { return .unshield }

        switch (rule.kind, trigger) {
        case (.dailyLimit, .intervalStarted):
            // Nuovo giorno: si riparte da zero.
            return .unshield
        case (.dailyLimit, .thresholdReached):
            return rule.appliesOn(date, calendar: calendar) ? .shield : .noChange
        case (.dailyLimit, .intervalEnded):
            return .unshield

        case (.schedule, .intervalStarted):
            // iOS sveglia l'estensione all'inizio della finestra: contano i giorni scelti.
            return rule.appliesOn(date, calendar: calendar) ? .shield : .noChange
        case (.schedule, .intervalEnded):
            return .unshield
        case (.schedule, .thresholdReached):
            // Le regole a orario non hanno soglie.
            return .noChange
        }
    }
}
