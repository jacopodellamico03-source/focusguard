import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import RuleEngine

/// Estensione svegliata da iOS all'inizio/fine delle finestre e al raggiungimento delle soglie,
/// anche ad app chiusa. Tutta la logica decisionale sta in RuleEngine.ShieldDecision:
/// qui si legge, si decide, si esegue, si registra.
///
/// Memoria molto limitata: niente SwiftData, niente lavori pesanti.
final class MonitorExtension: DeviceActivityMonitor {
    private let repository = RuleRepository()
    private let shields = ShieldController()
    private let eventLog = EventLogStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        handle(.intervalStarted, activity: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        handle(.intervalEnded, activity: activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        handle(.thresholdReached, activity: activity)
    }

    private func handle(_ trigger: MonitorTrigger, activity: DeviceActivityName) {
        let now = Date()
        Log.monitor.info("\(trigger.rawValue, privacy: .public) per \(activity.rawValue, privacy: .public)")

        guard let ruleID = ActivityNaming.ruleID(fromActivityName: activity.rawValue) else {
            Log.monitor.error("Attività sconosciuta: \(activity.rawValue, privacy: .public)")
            return
        }

        guard let rule = repository.loadRules().first(where: { $0.id == ruleID }) else {
            // Regola eliminata mentre il monitoraggio era attivo: meglio sbloccare.
            shields.unshield(.rule(ruleID))
            eventLog.append(EventLogEntry(date: now, ruleID: ruleID, trigger: trigger, action: .unshield, note: "regola non trovata"))
            return
        }

        let action = ShieldDecision.action(for: trigger, rule: rule, at: now, calendar: .current)

        switch action {
        case .shield:
            if let selection = repository.loadSelections()[ruleID], !selection.isEmptySelection {
                shields.shield(selection, in: .rule(ruleID))
            } else {
                Log.monitor.error("Nessuna selezione per la regola \(ruleID.uuidString, privacy: .public)")
            }
        case .unshield:
            shields.unshield(.rule(ruleID))
        case .noChange:
            break
        }

        eventLog.append(EventLogEntry(date: now, ruleID: ruleID, trigger: trigger, action: action))
    }
}
