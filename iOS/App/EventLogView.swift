import RuleEngine
import SwiftUI

struct EventLogView: View {
    @Environment(AppModel.self) private var model
    @State private var entries: [EventLogEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                Text("Nessun evento negli ultimi \(EventLogStore.retentionDays) giorni.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ruleName(entry.ruleID)).font(.headline)
                    Text("\(Formatting.label(for: entry.trigger)) → \(Formatting.label(for: entry.action))")
                        .font(.subheadline)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = entry.note {
                        Text(note).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Registro eventi")
        .refreshable { reload() }
        .onAppear { reload() }
    }

    private func reload() {
        entries = EventLogStore().load().reversed()
    }

    private func ruleName(_ id: UUID?) -> String {
        guard let id else { return "—" }
        return model.rules.first { $0.id == id }?.name ?? "Regola eliminata"
    }
}
