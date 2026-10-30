import SwiftUI

@main
struct FocusGuardApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { model.load() }
                .onChange(of: scenePhase) { _, phase in
                    // Al ritorno in primo piano: l'autorizzazione può essere stata revocata dalle Impostazioni.
                    if phase == .active { model.load() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.authorizationStatus {
        case .approved:
            if model.hasPIN {
                RulesListView()
            } else {
                PINSetupView()
            }
        default:
            AuthorizationView()
        }
    }
}

struct AuthorizationView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hourglass")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Controllo del tempo d'uso")
                .font(.title2.bold())
            Text("FocusGuard usa le API Tempo di utilizzo di Apple per bloccare le app che scegli. Le app restano anonime: l'app non vede quali sono, solo dei codici cifrati.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if model.authorizationStatus == .denied {
                Text("Autorizzazione negata. Riprova, oppure controlla in Impostazioni → Tempo di utilizzo.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Concedi l'accesso") {
                Task { await model.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
            if let message = model.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(32)
    }
}
