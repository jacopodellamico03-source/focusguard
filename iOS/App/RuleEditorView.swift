import FamilyControls
import RuleEngine
import SwiftUI

struct RuleEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Rule
    @State private var selection: FamilyActivitySelection
    @State private var isPickerPresented = false
    private let isNew: Bool
    private let hint: String?

    init(context: EditorContext, initialSelection: FamilyActivitySelection) {
        switch context {
        case let .new(template):
            _draft = State(initialValue: template.makeRule())
            isNew = true
            hint = template.hint
        case let .edit(rule):
            _draft = State(initialValue: rule)
            isNew = false
            hint = nil
        }
        _selection = State(initialValue: initialSelection)
    }

    private var errors: [RuleValidationError] { RuleValidator.validate(draft) }
    private var canSave: Bool { errors.isEmpty && !selection.isEmptySelection }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Nome della regola", text: $draft.name)
                }

                kindSection

                Section("Giorni") {
                    WeekdayPicker(selection: $draft.weekdays)
                }

                Section {
                    Button("Scegli app e categorie") { isPickerPresented = true }
                    Text(selection.summary).foregroundStyle(.secondary)
                } header: {
                    Text("App")
                } footer: {
                    if let hint { Text(hint) }
                }

                if !errors.isEmpty {
                    Section {
                        ForEach(errors, id: \.description) { error in
                            Text(error.description).foregroundStyle(.red)
                        }
                    }
                }

                if !isNew && model.requiresWait(saving: draft, selection: selection) {
                    Section {
                        Text("Questa modifica allenta la regola: avrà effetto dopo un'attesa di 10 minuti e la conferma col PIN.")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(isNew ? "Nuova regola" : "Modifica regola")
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        model.save(draft, selection: selection)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private var kindSection: some View {
        switch draft.kind {
        case .dailyLimit:
            Section("Limite giornaliero") {
                Stepper(value: limitMinutes, in: 5...1435, step: 5) {
                    Text(Formatting.duration(minutes: limitMinutes.wrappedValue))
                }
            }
        case .schedule:
            Section("Finestra di blocco") {
                DatePicker("Inizio", selection: time(isStart: true), displayedComponents: .hourAndMinute)
                DatePicker("Fine", selection: time(isStart: false), displayedComponents: .hourAndMinute)
            }
        }
    }

    private var limitMinutes: Binding<Int> {
        Binding(
            get: {
                if case let .dailyLimit(minutes) = draft.kind { return minutes }
                return 30
            },
            set: { draft.kind = .dailyLimit(minutes: $0) }
        )
    }

    private func time(isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                guard case let .schedule(start, end) = draft.kind else { return Date() }
                let value = isStart ? start : end
                return Calendar.current.date(bySettingHour: value.hour, minute: value.minute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                guard case let .schedule(start, end) = draft.kind else { return }
                let value = TimeOfDay(date: newDate, calendar: .current)
                draft.kind = isStart ? .schedule(start: value, end: end) : .schedule(start: start, end: value)
            }
        )
    }
}

/// Sette pulsanti L M M G V S D.
struct WeekdayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Weekday.mondayFirst, id: \.self) { day in
                let isOn = selection.contains(day)
                Button(Formatting.shortName(of: day)) {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .accessibilityLabel(Formatting.fullName(of: day))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}
