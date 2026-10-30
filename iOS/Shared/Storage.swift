import Foundation
import FamilyControls
import RuleEngine

/// Persistenza su file JSON nell'App Group.
/// Protezione "until first user authentication": l'estensione deve poter leggere
/// le regole anche a telefono bloccato (es. blocco notturno alle 22:00).
struct RuleRepository {
    private static let manualKey = "manual"

    private var rulesURL: URL { AppGroup.containerURL.appendingPathComponent("rules.json") }
    private var selectionsURL: URL { AppGroup.containerURL.appendingPathComponent("selections.json") }
    private var appliedSpecsURL: URL { AppGroup.containerURL.appendingPathComponent("applied-specs.json") }
    private var stateURL: URL { AppGroup.containerURL.appendingPathComponent("state.json") }

    // MARK: Regole

    func loadRules() -> [Rule] {
        read([Rule].self, from: rulesURL) ?? []
    }

    func saveRules(_ rules: [Rule]) throws {
        try write(rules, to: rulesURL)
    }

    // MARK: Selezioni di app (token opachi di Apple)

    /// Selezioni per regola. La chiave "manual" è riservata al blocco immediato.
    private func loadAllSelections() -> [String: FamilyActivitySelection] {
        read([String: FamilyActivitySelection].self, from: selectionsURL) ?? [:]
    }

    func loadSelections() -> [UUID: FamilyActivitySelection] {
        var result: [UUID: FamilyActivitySelection] = [:]
        for (key, value) in loadAllSelections() {
            if let id = UUID(uuidString: key) { result[id] = value }
        }
        return result
    }

    func loadManualSelection() -> FamilyActivitySelection {
        loadAllSelections()[Self.manualKey] ?? FamilyActivitySelection()
    }

    func saveSelections(_ selections: [UUID: FamilyActivitySelection], manual: FamilyActivitySelection) throws {
        var all: [String: FamilyActivitySelection] = [:]
        for (id, selection) in selections { all[id.uuidString] = selection }
        all[Self.manualKey] = manual
        try write(all, to: selectionsURL)
    }

    // MARK: Piano applicato (serve a riavviare solo le attività cambiate)

    func loadAppliedSpecs() -> [ActivitySpec] {
        read([ActivitySpec].self, from: appliedSpecsURL) ?? []
    }

    func saveAppliedSpecs(_ specs: [ActivitySpec]) throws {
        try write(specs, to: appliedSpecsURL)
    }

    // MARK: Stato del blocco immediato

    struct State: Codable {
        var isManualBlockActive = false
    }

    func loadState() -> State {
        read(State.self, from: stateURL) ?? State()
    }

    func saveState(_ state: State) throws {
        try write(state, to: stateURL)
    }

    // MARK: Helpers

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Log.storage.error("Decodifica fallita \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Log eventi in formato JSON Lines, appeso dall'estensione Monitor.
struct EventLogStore {
    static let retentionDays = 14

    private var url: URL { AppGroup.containerURL.appendingPathComponent("events.jsonl") }

    func append(_ entry: EventLogEntry) {
        do {
            let line = try EventLogCodec.encodeLine(entry)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        } catch {
            Log.storage.error("Scrittura log fallita: \(error.localizedDescription, privacy: .public)")
        }
    }

    func load() -> [EventLogEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return EventLogCodec.decode(data)
    }

    /// Da chiamare dall'app (non dall'estensione): riscrive il file tenendo solo gli ultimi giorni.
    func prune(now: Date = Date()) {
        let kept = EventLogCodec.pruned(load(), keepingDays: Self.retentionDays, now: now)
        do {
            try EventLogCodec.encodeAll(kept)
                .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Log.storage.error("Pulizia log fallita: \(error.localizedDescription, privacy: .public)")
        }
    }
}
