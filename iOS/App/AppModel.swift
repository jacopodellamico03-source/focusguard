import FamilyControls
import Foundation
import Observation
import RuleEngine

/// Esito di una verifica del PIN.
enum PINCheckResult: Equatable {
    case success
    case wrong
    case locked
    /// Non si è potuto verificare, o la richiesta non è più confermabile: vedi `errorMessage`.
    case unavailable
}

/// Stato dell'app e orchestrazione: salva le regole, aggiorna il monitoraggio, applica i blocchi.
@MainActor
@Observable
final class AppModel {
    private(set) var authorizationStatus: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    private(set) var rules: [Rule] = []
    private(set) var selections: [UUID: FamilyActivitySelection] = [:]
    private(set) var manualSelection = FamilyActivitySelection()
    private(set) var isManualBlockActive = false
    private(set) var hasPIN = false
    private var protection = ProtectionState()
    /// Selezioni proposte dalle richieste in attesa, per id della richiesta.
    private var pendingSelections: [UUID: FamilyActivitySelection] = [:]
    var errorMessage: String?

    private let repository = RuleRepository()
    private let scheduler = ActivityScheduler()
    private let shields = ShieldController()
    private let eventLog = EventLogStore()
    private let pinStore = PINStore()

    var preventsAppRemoval: Bool { protection.preventsAppRemoval }

    // MARK: Avvio

    func load() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        rules = repository.loadRules()
        selections = repository.loadSelections()
        manualSelection = repository.loadManualSelection()
        isManualBlockActive = repository.loadState().isManualBlockActive
        // Prima di leggere lo stato: conta se il file di protezione esiste già.
        refreshPINState()
        protection = repository.loadProtection()
        pendingSelections = repository.loadPendingSelections()
        removeExpiredRelaxations()
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

    /// La modifica allenta la regola, quindi passerebbe dall'attesa?
    func requiresWait(saving rule: Rule, selection: FamilyActivitySelection) -> Bool {
        let old = rules.first { $0.id == rule.id }
        return ChangePolicy.impact(old: old, new: rule, selectionChanged: selections[rule.id] != selection) == .relaxing
    }

    func save(_ rule: Rule, selection: FamilyActivitySelection) {
        guard hasPIN else {
            errorMessage = "Crea prima un PIN."
            return
        }
        guard pendingRelaxation(for: .rule(rule.id)) == nil else {
            errorMessage = "Questa regola ha una richiesta in attesa: annullala prima di modificarla."
            return
        }

        let old = rules.first { $0.id == rule.id }
        let selectionChanged = selections[rule.id] != selection
        let impact = ChangePolicy.impact(old: old, new: rule, selectionChanged: selectionChanged)
        Log.app.info("Salvataggio regola, impatto: \(impact.rawValue, privacy: .public)")

        if impact == .relaxing {
            enqueue(.editRule(rule), proposedSelection: selectionChanged ? selection : nil)
            return
        }
        store(rule, selection: selection)
        applyMonitoring(forceRestart: selectionChanged ? [rule.id] : [])
    }

    func setEnabled(_ enabled: Bool, for ruleID: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }),
              pendingRelaxation(for: .rule(ruleID)) == nil else { return }

        var updated = rules[index]
        updated.isEnabled = enabled
        if ChangePolicy.impact(old: rules[index], new: updated, selectionChanged: false) == .relaxing {
            enqueue(.disableRule(ruleID))
            return
        }
        rules[index] = updated
        persist()
        applyMonitoring()
    }

    func delete(_ ruleID: UUID) {
        guard pendingRelaxation(for: .rule(ruleID)) == nil else { return }
        let old = rules.first { $0.id == ruleID }
        if ChangePolicy.impact(old: old, new: nil, selectionChanged: false) == .relaxing {
            enqueue(.deleteRule(ruleID))
            return
        }
        removeRule(ruleID)
    }

    private func store(_ rule: Rule, selection: FamilyActivitySelection) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        selections[rule.id] = selection
        persist()
    }

    private func removeRule(_ ruleID: UUID) {
        rules.removeAll { $0.id == ruleID }
        selections[ruleID] = nil
        shields.unshield(.rule(ruleID))
        persist()
        applyMonitoring()
    }

    // MARK: Blocco immediato

    func setManualBlock(_ active: Bool) {
        guard pendingRelaxation(for: .manualBlock) == nil else { return }
        let impact = ChangePolicy.manualBlockImpact(
            wasActive: isManualBlockActive,
            isActive: active,
            selectionChanged: false
        )
        if impact == .relaxing {
            enqueue(.disableManualBlock)
            return
        }
        if active {
            guard !manualSelection.isEmptySelection else {
                errorMessage = "Scegli prima le app da bloccare."
                return
            }
            shields.shield(manualSelection, in: .manual)
        }
        isManualBlockActive = active
        persist()
        updateProtection()
    }

    /// A blocco attivo togliere app dalla selezione equivale a sbloccarle, quindi passa dall'attesa.
    func setManualSelection(_ selection: FamilyActivitySelection) {
        guard selection != manualSelection, pendingRelaxation(for: .manualBlock) == nil else { return }
        let impact = ChangePolicy.manualBlockImpact(
            wasActive: isManualBlockActive,
            isActive: isManualBlockActive,
            selectionChanged: true
        )
        if impact == .relaxing {
            enqueue(.changeManualSelection, proposedSelection: selection)
            return
        }
        manualSelection = selection
        persist()
    }

    #if DEBUG
    /// Solo per lo sviluppo: toglie ogni blocco, senza PIN né attesa.
    /// Anche le protezioni, per poter disinstallare: tornano al prossimo `applyMonitoring`.
    func emergencyUnshieldAll() {
        shields.unshieldEverything(ruleIDs: rules.map(\.id))
        shields.setProtection(denyAppRemoval: false, requireAutomaticDateAndTime: false)
        isManualBlockActive = false
        if let request = pendingRelaxation(for: .manualBlock) {
            cancelPending(id: request.id)
        }
        persist()
    }
    #endif

    // MARK: Preferenze

    func setPreventsAppRemoval(_ enabled: Bool) {
        guard pendingRelaxation(for: .appRemovalProtection) == nil else { return }
        let impact = ChangePolicy.appRemovalProtectionImpact(
            wasEnabled: protection.preventsAppRemoval,
            isEnabled: enabled
        )
        if impact == .relaxing {
            enqueue(.disableAppRemovalProtection)
            return
        }
        protection.preventsAppRemoval = enabled
        persistProtection()
        updateProtection()
    }

    // MARK: PIN

    func pinLockoutRemaining(at date: Date) -> TimeInterval {
        protection.attempts.remainingLockout(at: date)
    }

    func createPIN(_ pin: String) {
        guard !hasPIN, PINPolicy.validate(pin).isEmpty else { return }
        do {
            // Prima il file: un PIN senza file di protezione è trattato come residuo di una vecchia installazione.
            try repository.saveProtection(protection)
            try pinStore.set(pin)
            hasPIN = true
            errorMessage = nil
        } catch {
            errorMessage = "PIN non salvato: \(String(describing: error))"
            Log.app.error("PIN non salvato: \(String(describing: error), privacy: .public)")
        }
    }

    func changePIN(current: String, new: String) -> PINCheckResult {
        guard PINPolicy.validate(new).isEmpty else { return .unavailable }
        let result = checkPIN(current)
        guard result == .success else { return result }
        do {
            try pinStore.set(new)
            errorMessage = nil
            return .success
        } catch {
            errorMessage = "PIN non salvato: \(String(describing: error))"
            Log.app.error("PIN non salvato: \(String(describing: error), privacy: .public)")
            return .unavailable
        }
    }

    /// Durante il blocco il PIN non viene nemmeno verificato.
    private func checkPIN(_ pin: String) -> PINCheckResult {
        guard !protection.attempts.isLocked(at: Date()) else { return .locked }
        do {
            let matches = try pinStore.verify(pin)
            if matches {
                protection.attempts.registerSuccess()
            } else {
                protection.attempts.registerFailure(at: Date())
            }
            persistProtection()
            guard matches else {
                return protection.attempts.isLocked(at: Date()) ? .locked : .wrong
            }
            return .success
        } catch {
            errorMessage = "PIN non verificato: \(String(describing: error))"
            Log.app.error("PIN non verificato: \(String(describing: error), privacy: .public)")
            return .unavailable
        }
    }

    /// Il Keychain sopravvive alla disinstallazione, il container dell'App Group no.
    /// Un PIN senza file di protezione viene da una vecchia installazione: reinstallare è l'unica
    /// via d'uscita da un PIN dimenticato. Non apre scappatoie: disinstallando le regole sono già perse.
    private func refreshPINState() {
        do {
            var exists = try pinStore.hasPIN()
            if exists && !repository.hasProtectionState {
                try pinStore.delete()
                exists = false
                Log.app.info("PIN di una vecchia installazione rimosso")
            }
            hasPIN = exists
        } catch {
            // Nel dubbio non si propone di creare un PIN nuovo sopra a quello esistente.
            hasPIN = true
            Log.app.error("Keychain non leggibile: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Richieste in attesa

    func pendingRelaxation(for target: PendingRelaxation.Target) -> PendingRelaxation? {
        protection.pending.pending(for: target)
    }

    func cancelPending(id: UUID) {
        forgetRequest(id: id)
        persistProtection()
    }

    func removeExpiredRelaxations() {
        let expired = protection.pending.removeExpired(at: Date())
        guard !expired.isEmpty else { return }
        expired.forEach { pendingSelections[$0.id] = nil }
        savePendingSelections()
        persistProtection()
    }

    func confirmPending(id: UUID, pin: String) -> PINCheckResult {
        guard isConfirmable(id: id) else { return .unavailable }
        let result = checkPIN(pin)
        if result == .success { applyConfirmed(id: id) }
        return result
    }

    /// Face ID non azzera i tentativi di PIN errati. `false` se bisogna passare al PIN.
    func confirmPendingWithBiometrics(id: UUID) async -> Bool {
        guard isConfirmable(id: id),
              await BiometricAuth.authenticate(reason: "Conferma la modifica alle regole"),
              isConfirmable(id: id) else { return false }
        applyConfirmed(id: id)
        return true
    }

    private func isConfirmable(id: UUID) -> Bool {
        guard let request = protection.pending.request(id: id), request.canConfirm(at: Date()) else {
            errorMessage = "Richiesta non più confermabile."
            return false
        }
        return true
    }

    private func enqueue(_ change: PendingRelaxation.Change, proposedSelection: FamilyActivitySelection? = nil) {
        let request = protection.pending.enqueue(change, at: Date())
        if let proposedSelection {
            pendingSelections[request.id] = proposedSelection
            savePendingSelections()
        }
        persistProtection()
    }

    private func forgetRequest(id: UUID) {
        protection.pending.remove(id: id)
        if pendingSelections.removeValue(forKey: id) != nil {
            savePendingSelections()
        }
    }

    /// Si applica prima e si dimentica dopo: se l'app muore in mezzo, ripetere la conferma non fa danni.
    private func applyConfirmed(id: UUID) {
        guard let request = protection.pending.request(id: id) else { return }
        Log.app.info("Richiesta confermata")

        switch request.change {
        case let .disableRule(ruleID):
            if let index = rules.firstIndex(where: { $0.id == ruleID }) {
                rules[index].isEnabled = false
                persist()
                applyMonitoring()
            }
        case let .deleteRule(ruleID):
            removeRule(ruleID)
        case let .editRule(rule):
            store(rule, selection: pendingSelections[id] ?? selection(for: rule.id))
            // Il blocco già scattato non vale più per la regola nuova. Si toglie e si riavvia sempre:
            // l'app riapplica le regole a orario e la soglia, che conta l'uso già fatto, può riscattare.
            shields.unshield(.rule(rule.id))
            applyMonitoring(forceRestart: [rule.id])
        case .disableManualBlock:
            shields.unshield(.manual)
            isManualBlockActive = false
            persist()
            updateProtection()
        case .changeManualSelection:
            if let selection = pendingSelections[id] {
                manualSelection = selection
                if isManualBlockActive {
                    shields.shield(selection, in: .manual)
                }
                persist()
            }
        case .disableAppRemovalProtection:
            protection.preventsAppRemoval = false
            updateProtection()
        }

        forgetRequest(id: id)
        persistProtection()
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

    private func persistProtection() {
        do {
            try repository.saveProtection(protection)
        } catch {
            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }

    private func savePendingSelections() {
        do {
            try repository.savePendingSelections(pendingSelections)
        } catch {
            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }

    private func updateProtection() {
        shields.setProtection(
            denyAppRemoval: ProtectionPolicy.shouldDenyAppRemoval(
                rules: rules,
                isManualBlockActive: isManualBlockActive,
                preventsAppRemoval: protection.preventsAppRemoval
            ),
            requireAutomaticDateAndTime: ProtectionPolicy.shouldRequireAutomaticDateAndTime(
                rules: rules,
                isManualBlockActive: isManualBlockActive
            )
        )
    }

    private func applyMonitoring(forceRestart: Set<UUID> = []) {
        // Fuori dal do/catch: la protezione vale anche se il piano di monitoraggio fallisce.
        defer { updateProtection() }
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
