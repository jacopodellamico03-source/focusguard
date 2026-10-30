import Foundation
import LocalAuthentication

/// Face ID come scorciatoia del PIN. Solo biometria: `.deviceOwnerAuthentication`
/// ripiegherebbe sul codice del telefono invece che sul PIN dell'app.
enum BiometricAuth {
    /// `false` per qualunque motivo (annullato, non disponibile, non riconosciuto): si passa al PIN.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Usa il PIN"
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            Log.app.info("Face ID non riuscito: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
