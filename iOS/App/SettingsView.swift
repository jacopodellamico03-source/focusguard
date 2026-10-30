import RuleEngine
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pending = model.pendingRelaxation(for: .appRemovalProtection)
        Form {
            Section {
                Toggle("Impedisci la disinstallazione delle app", isOn: Binding(
                    get: { model.preventsAppRemoval },
                    set: { model.setPreventsAppRemoval($0) }
                ))
                .disabled(pending != nil)
                if let pending {
                    PendingRelaxationView(request: pending)
                }
            } header: {
                Text("Protezione")
            } footer: {
                Text("Vale finché c'è almeno una regola attiva o il blocco immediato. Probabilmente iOS blocca la disinstallazione di tutte le app del telefono, non solo di FocusGuard. Disattivare l'opzione richiede un'attesa di 10 minuti e il PIN.")
            }

            Section("PIN") {
                NavigationLink("Cambia PIN") { ChangePINView() }
            }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Richiesta in attesa: conto alla rovescia, "Conferma" (attivo a fine attesa) e "Annulla".
struct PendingRelaxationView: View {
    @Environment(AppModel.self) private var model
    @State private var isPINPresented = false

    private let request: PendingRelaxation

    init(request: PendingRelaxation) {
        self.request = request
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let phase = request.phase(at: context.date)
            VStack(alignment: .leading, spacing: 8) {
                Text(status(phase: phase, at: context.date))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                HStack(spacing: 20) {
                    Button("Conferma", action: confirm)
                        .disabled(phase != .confirmable)
                    Button("Annulla") { model.cancelPending(id: request.id) }
                }
                // In una riga di List, senza questo stile, un tocco attiverebbe tutti i pulsanti.
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
            // initial: la richiesta può essere già scaduta quando la schermata si apre.
            .onChange(of: phase, initial: true) { _, newPhase in
                if newPhase == .expired { model.removeExpiredRelaxations() }
            }
        }
        .sheet(isPresented: $isPINPresented) {
            PINEntryView { pin in model.confirmPending(id: request.id, pin: pin) }
        }
    }

    private func status(phase: PendingRelaxation.Phase, at date: Date) -> String {
        let label = Formatting.label(for: request.change)
        switch phase {
        case .waiting:
            return "\(label): si potrà confermare tra \(Formatting.countdown(request.remaining(at: date)))"
        case .confirmable:
            return "\(label): conferma entro \(Formatting.countdown(request.confirmationRemaining(at: date)))"
        case .expired:
            return "\(label): richiesta scaduta"
        }
    }

    private func confirm() {
        Task {
            if await !model.confirmPendingWithBiometrics(id: request.id) {
                isPINPresented = true
            }
        }
    }
}
