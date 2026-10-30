import FamilyControls
import Foundation
import Observation
import RuleEngine

/// Stato dell'app e orchestrazione: salva le regole, aggiorna il monitoraggio, applica i blocchi.
@MainActor
@Observable
final class AppModel {
    private(set) var authorizationStatus: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    private(set) var rules: [Rule] = []
    private(set) var selections: [UUID: FamilyActivitySelection] = [:]
    var manualSelection = FamilyActivitySelection()
    private(set) var isManualBlockActive = false
    var errorMessage: String?

    private let repository = RuleRepository()
    private let scheduler = ActivityScheduler()
    private let shields = ShieldController()
    private let eventLog = EventLogStore()

    // MARK: Avvio

    func load() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        rules = repository.loadRules()
        selections = repository.loadSelections()
        manualSelection = repository.loadManualSelection()
        isManualBlockActive = repository.loadState().isManualBlockActive
        eventLog.prune()
        if authorizationStatus == .approved {
            applyMonitoring()
        }
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            errorMessage = "Autorizzazione non concessa: \(error.localizedDescription)"
        }
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        if authorizationStatus == .approved {
            applyMonitoring()
        }
    }

    // MARK: Regole

    func selection(for ruleID: UUID) -> FamilyActivitySelection {
        selections[ruleID] ?? FamilyActivitySelection()
    }

    func save(_ rule: Rule, selection: FamilyActivitySelection) {
        let old = rules.first { $0.id == rule.id }
        let selectionChanged = selections[rule.id] != selection
        let impact = ChangePolicy.impact(old: old, new: rule, selectionChanged: selectionChanged)
        // TODO(Fase 5): se impact == .relaxing chiedere PIN e far partire il Cooldown.
        Log.app.info("Salvataggio regola, impatto: \(impact.rawValue, privacy: .public)")

        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        selections[rule.id] = selection
        persist()
        applyMonitoring(forceRestart: selectionChanged ? [rule.id] : [])
    }

    func setEnabled(_ enabled: Bool, for ruleID: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        // TODO(Fase 5): disattivare = relaxing → PIN.
        rules[index].isEnabled = enabled
        persist()
        applyMonitoring()
    }

    func delete(_ ruleID: UUID) {
        // TODO(Fase 5): eliminare una regola attiva = relaxing → PIN.
        rules.removeAll { $0.id == ruleID }
        selections[ruleID] = nil
        shields.unshield(.rule(ruleID))
        persist()
        applyMonitoring()
    }

    // MARK: Blocco immediato

    func setManualBlock(_ active: Bool) {
        // TODO(Fase 5): sbloccare = relaxing → PIN.
        if active {
            guard !manualSelection.isEmptySelection else {
                errorMessage = "Scegli prima le app da bloccare."
                return
            }
            shields.shield(manualSelection, in: .manual)
        } else {
            shields.unshield(.manual)
        }
        isManualBlockActive = active
        persist()
    }

    func manualSelectionChanged() {
        if isManualBlockActive {
            shields.shield(manualSelection, in: .manual)
        }
        persist()
    }

    /// Solo per lo sviluppo: toglie ogni blocco.
    func emergencyUnshieldAll() {
        shields.unshieldEverything(ruleIDs: rules.map(\.id))
        isManualBlockActive = false
        persist()
    }

    // MARK: Interni

    private func persist() {
        do {
            try repository.saveRules(rules)
            try repository.saveSelections(selections, manual: manualSelection)
            try repository.saveState(.init(isManualBlockActive: isManualBlockActive))
        } catch {
            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }

    private func applyMonitoring(forceRestart: Set<UUID> = []) {
        do {
            let specs = try MonitoringPlan.build(from: rules)
            let diff = MonitoringPlan.diff(old: repository.loadAppliedSpecs(), new: specs, forceRestart: forceRestart)

            try scheduler.apply(diff: diff, allSpecs: specs, selections: selections)
            try repository.saveAppliedSpecs(specs)

            // Regole non più monitorate (disattivate o eliminate): via i blocchi.
            diff.removedRuleIDs.forEach { shields.unshield(.rule($0)) }

            // iOS non sempre chiama intervalDidStart se il monitoraggio parte a finestra già aperta:
            // per le regole a orario attive adesso si blocca subito dall'app.
            let now = Date()
            for rule in rules where rule.isScheduleActive(at: now, calendar: .current) {
                let selection = self.selection(for: rule.id)
                if !selection.isEmptySelection {
                    shields.shield(selection, in: .rule(rule.id))
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
            Log.app.error("Monitoraggio non aggiornato: \(String(describing: error), privacy: .public)")
        }
    }
}
