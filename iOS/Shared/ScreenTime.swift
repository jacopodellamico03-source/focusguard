import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import RuleEngine

extension FamilyActivitySelection {
    var isEmptySelection: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    /// Riassunto per l'interfaccia, es. "3 app · 1 categoria".
    var summary: String {
        var parts: [String] = []
        if !applicationTokens.isEmpty { parts.append("\(applicationTokens.count) app") }
        if !categoryTokens.isEmpty {
            parts.append("\(categoryTokens.count) \(categoryTokens.count == 1 ? "categoria" : "categorie")")
        }
        if !webDomainTokens.isEmpty {
            parts.append("\(webDomainTokens.count) \(webDomainTokens.count == 1 ? "sito" : "siti")")
        }
        return parts.isEmpty ? "Nessuna app scelta" : parts.joined(separator: " · ")
    }
}

extension ManagedSettingsStore.Name {
    /// Uno store per regola: togliere un blocco non tocca gli altri.
    static func rule(_ id: UUID) -> ManagedSettingsStore.Name {
        ManagedSettingsStore.Name("rule.\(id.uuidString)")
    }

    static let manual = ManagedSettingsStore.Name("manual")
}

/// Applica e rimuove i blocchi (shield).
struct ShieldController {
    func shield(_ selection: FamilyActivitySelection, in name: ManagedSettingsStore.Name) {
        let store = ManagedSettingsStore(named: name)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
    }

    func unshield(_ name: ManagedSettingsStore.Name) {
        ManagedSettingsStore(named: name).clearAllSettings()
    }

    /// Uscita di emergenza durante lo sviluppo: toglie ogni blocco noto.
    func unshieldEverything(ruleIDs: [UUID]) {
        ruleIDs.forEach { unshield(.rule($0)) }
        unshield(.manual)
    }
}

/// Avvia e ferma il monitoraggio DeviceActivity.
struct ActivityScheduler {
    private let center = DeviceActivityCenter()

    func apply(
        diff: MonitoringDiff,
        allSpecs: [ActivitySpec],
        selections: [UUID: FamilyActivitySelection]
    ) throws {
        // Attività rimaste monitorate da versioni precedenti dell'app.
        let wanted = Set(allSpecs.map(\.activityName))
        let stale = center.activities.filter { !wanted.contains($0.rawValue) }

        let toStop = Set(diff.toStop.map { DeviceActivityName($0) }).union(stale)
        if !toStop.isEmpty {
            center.stopMonitoring(Array(toStop))
        }

        for spec in diff.toStart {
            guard let selection = selections[spec.ruleID], !selection.isEmptySelection else {
                Log.app.info("Regola senza app scelte, non monitorata: \(spec.activityName, privacy: .public)")
                continue
            }

            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: spec.intervalStart.hour, minute: spec.intervalStart.minute),
                intervalEnd: DateComponents(hour: spec.intervalEnd.hour, minute: spec.intervalEnd.minute),
                repeats: true
            )

            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            if let minutes = spec.thresholdMinutes {
                // includesPastActivity: conta anche l'uso dall'inizio della giornata,
                // così riavviare il monitoraggio non azzera il limite.
                events[DeviceActivityEvent.Name(ActivityNaming.limitEventName)] = DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: DateComponents(hour: minutes / 60, minute: minutes % 60),
                    includesPastActivity: true
                )
            }

            try center.startMonitoring(DeviceActivityName(spec.activityName), during: schedule, events: events)
            Log.app.info("Monitoraggio avviato: \(spec.activityName, privacy: .public)")
        }
    }
}
