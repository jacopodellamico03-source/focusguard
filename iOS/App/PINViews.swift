import RuleEngine
import SwiftUI

/// Campo PIN: tastierino numerico, cifre nascoste.
private struct PINField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        SecureField(title, text: $text)
            .keyboardType(.numberPad)
    }
}

/// Errori del nuovo PIN (inserimento + conferma), lista vuota se va bene.
private func newPINErrors(pin: String, confirmation: String) -> [String] {
    let errors = PINPolicy.validate(pin).map(\.description)
    if !errors.isEmpty { return errors }
    return pin == confirmation ? [] : ["I due PIN non coincidono."]
}

/// Creazione del PIN al primo avvio: senza PIN non si entra nell'app.
struct PINSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var errors: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PINField("Nuovo PIN", text: $pin)
                    PINField("Conferma PIN", text: $confirmation)
                } footer: {
                    Text("Il PIN serve per confermare le modifiche che allentano le regole. Scegli \(PINPolicy.minLength)–\(PINPolicy.maxLength) cifre, senza sequenze o ripetizioni.")
                }

                if !errors.isEmpty || model.errorMessage != nil {
                    Section {
                        ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red) }
                        if let message = model.errorMessage {
                            Text(message).foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button("Crea PIN") {
                        errors = newPINErrors(pin: pin, confirmation: confirmation)
                        if errors.isEmpty { model.createPIN(pin) }
                    }
                }
            }
            .navigationTitle("Crea il PIN")
        }
    }
}

/// Richiesta del PIN per confermare una modifica. Mostra il blocco dopo troppi errori.
struct PINEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var message: String?

    private let submit: @MainActor (String) -> PINCheckResult

    /// - Parameter submit: verifica il PIN; in caso di `.success` il foglio si chiude.
    init(submit: @escaping @MainActor (String) -> PINCheckResult) {
        self.submit = submit
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let lockout = model.pinLockoutRemaining(at: context.date)
                Form {
                    Section {
                        PINField("PIN", text: $pin)
                    }
                    if lockout > 0 {
                        Section {
                            Text("Troppi tentativi. Riprova tra \(Formatting.countdown(lockout)).")
                                .foregroundStyle(.red)
                        }
                    } else if let message {
                        Section {
                            Text(message).foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button("Conferma", action: confirm)
                            .disabled(lockout > 0 || pin.isEmpty)
                    }
                }
            }
            .navigationTitle("Inserisci il PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    private func confirm() {
        let result = submit(pin)
        pin = ""
        switch result {
        case .success:
            dismiss()
        case .wrong:
            message = "PIN errato."
        case .locked:
            message = nil
        case .unavailable:
            dismiss()
        }
    }
}

/// Cambio PIN: serve il PIN attuale, Face ID non basta.
struct ChangePINView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var errors: [String] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let lockout = model.pinLockoutRemaining(at: context.date)
            Form {
                Section("PIN attuale") {
                    PINField("PIN attuale", text: $current)
                }
                Section("Nuovo PIN") {
                    PINField("Nuovo PIN", text: $new)
                    PINField("Conferma PIN", text: $confirmation)
                }
                if lockout > 0 {
                    Section {
                        Text("Troppi tentativi. Riprova tra \(Formatting.countdown(lockout)).")
                            .foregroundStyle(.red)
                    }
                } else if !errors.isEmpty {
                    Section {
                        ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red) }
                    }
                }
                Section {
                    Button("Cambia PIN", action: change)
                        .disabled(lockout > 0 || current.isEmpty)
                }
            }
        }
        .navigationTitle("Cambia PIN")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func change() {
        // Il nuovo PIN si controlla prima: un errore di battitura non deve consumare un tentativo.
        errors = newPINErrors(pin: new, confirmation: confirmation)
        guard errors.isEmpty else { return }

        let result = model.changePIN(current: current, new: new)
        current = ""
        switch result {
        case .success:
            dismiss()
        case .wrong:
            errors = ["PIN attuale errato."]
        case .locked:
            errors = []
        case .unavailable:
            errors = [model.errorMessage ?? "Cambio PIN non riuscito."]
        }
    }
}
