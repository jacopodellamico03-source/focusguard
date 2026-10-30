import Foundation

/// Nomi delle attività DeviceActivity: "rule.<UUID>". Condivisi tra app ed estensione.
public enum ActivityNaming {
    public static let prefix = "rule."
    public static let limitEventName = "limit"

    public static func activityName(for ruleID: UUID) -> String {
        prefix + ruleID.uuidString
    }

    public static func ruleID(fromActivityName name: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }
}

/// Descrizione di un'attività da monitorare, tradotta poi in DeviceActivitySchedule dal livello iOS.
public struct ActivitySpec: Codable, Equatable, Sendable {
    public let ruleID: UUID
    public let activityName: String
    public let intervalStart: TimeOfDay
    public let intervalEnd: TimeOfDay
    /// Soglia in minuti per l'evento "limit"; nil per le regole a orario.
    public let thresholdMinutes: Int?
}

public enum MonitoringPlanError: Error, Equatable, Sendable, CustomStringConvertible {
    case tooManyActivities(count: Int, max: Int)

    public var description: String {
        switch self {
        case let .tooManyActivities(count, max):
            return "Troppe regole attive (\(count)): iOS ne monitora al massimo \(max). Raggruppa le app in meno regole."
        }
    }
}

/// Traduce le regole in attività da monitorare.
public enum MonitoringPlan {
    /// Limite prudente al numero di attività monitorate contemporaneamente.
    public static let maxActivities = 20

    /// Solo regole abilitate e valide. Le regole non valide vengono scartate:
    /// l'interfaccia impedisce di salvarle, qui è una difesa in più.
    public static func build(from rules: [Rule]) throws -> [ActivitySpec] {
        let specs: [ActivitySpec] = rules
            .filter { $0.isEnabled && RuleValidator.validate($0).isEmpty }
            .map { rule in
                switch rule.kind {
                case let .dailyLimit(minutes):
                    return ActivitySpec(
                        ruleID: rule.id,
                        activityName: ActivityNaming.activityName(for: rule.id),
                        intervalStart: .midnight,
                        intervalEnd: .endOfDay,
                        thresholdMinutes: minutes
                    )
                case let .schedule(start, end):
                    return ActivitySpec(
                        ruleID: rule.id,
                        activityName: ActivityNaming.activityName(for: rule.id),
                        intervalStart: start,
                        intervalEnd: end,
                        thresholdMinutes: nil
                    )
                }
            }

        if specs.count > maxActivities {
            throw MonitoringPlanError.tooManyActivities(count: specs.count, max: maxActivities)
        }
        return specs
    }

    /// Calcola cosa fermare e cosa (ri)avviare rispetto al piano già applicato.
    /// Riavviare un'attività può azzerare il conteggio dei minuti della giornata,
    /// quindi si toccano solo le attività davvero cambiate.
    /// - Parameter forceRestart: regole da riavviare comunque (es. app scelte cambiate:
    ///   i token non fanno parte di `ActivitySpec`).
    public static func diff(
        old: [ActivitySpec],
        new: [ActivitySpec],
        forceRestart: Set<UUID> = []
    ) -> MonitoringDiff {
        let oldByName = Dictionary(old.map { ($0.activityName, $0) }, uniquingKeysWith: { first, _ in first })
        let newByName = Dictionary(new.map { ($0.activityName, $0) }, uniquingKeysWith: { first, _ in first })

        let toStop = old
            .filter { newByName[$0.activityName] != $0 || forceRestart.contains($0.ruleID) }
            .map(\.activityName)
            .sorted()

        let toStart = new
            .filter { oldByName[$0.activityName] != $0 || forceRestart.contains($0.ruleID) }
            .sorted { $0.activityName < $1.activityName }

        let removedRuleIDs = Set(old.map(\.ruleID)).subtracting(new.map(\.ruleID))

        return MonitoringDiff(toStop: toStop, toStart: toStart, removedRuleIDs: removedRuleIDs)
    }
}

/// Risultato di `MonitoringPlan.diff`.
public struct MonitoringDiff: Equatable, Sendable {
    /// Attività da fermare (rimosse o cambiate).
    public let toStop: [String]
    /// Attività da avviare (nuove o cambiate).
    public let toStart: [ActivitySpec]
    /// Regole non più monitorate: i loro blocchi vanno tolti.
    public let removedRuleIDs: Set<UUID>

    public var isEmpty: Bool { toStop.isEmpty && toStart.isEmpty }
}
