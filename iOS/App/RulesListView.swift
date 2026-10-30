import FamilyControls
import RuleEngine
import SwiftUI

/// Cosa si sta modificando nel foglio dell'editor.
enum EditorContext: Identifiable {
    case new(RuleTemplate)
    case edit(Rule)

    var id: String {
        switch self {
        case let .new(template): return "new-\(template.rawValue)"
        case let .edit(rule): return rule.id.uuidString
        }
    }
}

enum RuleTemplate: String {
    case dailyLimit, totalScreenTime, schedule

    func makeRule() -> Rule {
        switch self {
        case .dailyLimit:
            return Rule(name: "Social", kind: .dailyLimit(minutes: 30))
        case .totalScreenTime:
            return Rule(name: "Tempo totale", kind: .dailyLimit(minutes: 180))
        case .schedule:
            return Rule(name: "Notte", kind: .schedule(start: TimeOfDay(hour: 22, minute: 0)!, end: TimeOfDay(hour: 7, minute: 0)!))
        }
    }

    var hint: String? {
        switch self {
        case .totalScreenTime:
            return "Per il tempo totale scegli tutte le categorie nel selettore di app."
        default:
            return nil
        }
    }
}

struct RulesListView: View {
    @Environment(AppModel.self) private var model
    @State private var editor: EditorContext?

    var body: some View {
        NavigationStack {
            List {
                Section("Blocco immediato") {
                    ManualBlockSection()
                }

                Section("Regole") {
                    if model.rules.isEmpty {
                        Text("Nessuna regola. Tocca + per crearne una.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.rules) { rule in
                        RuleRow(rule: rule) { editor = .edit(rule) }
                    }
                    .onDelete { offsets in
                        offsets.map { model.rules[$0].id }.forEach(model.delete)
                    }
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }

                Section {
                    NavigationLink("Registro eventi") { EventLogView() }
                    #if DEBUG
                    Button("Sblocca tutto (debug)", role: .destructive) {
                        model.emergencyUnshieldAll()
                    }
                    #endif
                }
            }
            .navigationTitle("FocusGuard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Limite giornaliero", systemImage: "timer") { editor = .new(.dailyLimit) }
                        Button("Tempo totale", systemImage: "iphone") { editor = .new(.totalScreenTime) }
                        Button("Blocco a orario", systemImage: "moon") { editor = .new(.schedule) }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editor) { context in
                RuleEditorView(context: context, initialSelection: initialSelection(for: context))
            }
        }
    }

    private func initialSelection(for context: EditorContext) -> FamilyActivitySelection {
        if case let .edit(rule) = context {
            return model.selection(for: rule.id)
        }
        return FamilyActivitySelection()
    }
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let rule: Rule
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name).font(.headline)
                Text(Formatting.summary(of: rule)).font(.subheadline).foregroundStyle(.secondary)
                Text(model.selection(for: rule.id).summary).font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            Spacer()
            Toggle("Attiva", isOn: Binding(
                get: { rule.isEnabled },
                set: { model.setEnabled($0, for: rule.id) }
            ))
            .labelsHidden()
        }
    }
}

private struct ManualBlockSection: View {
    @Environment(AppModel.self) private var model
    @State private var isPickerPresented = false

    var body: some View {
        @Bindable var model = model
        Button("Scegli app da bloccare") { isPickerPresented = true }
        Text(model.manualSelection.summary).font(.caption).foregroundStyle(.secondary)
        Toggle("Blocca ora", isOn: Binding(
            get: { model.isManualBlockActive },
            set: { model.setManualBlock($0) }
        ))
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $model.manualSelection)
        .onChange(of: model.manualSelection) { _, _ in
            model.manualSelectionChanged()
        }
    }
}
