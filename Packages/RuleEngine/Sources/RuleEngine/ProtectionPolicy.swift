import Foundation

/// Stato dell'opzione "Impedisci la disinstallazione delle app".
public enum AppRemovalProtection: String, Codable, Equatable, Sendable {
    case enabled
    /// Accesa perché era `suspended` ed è arrivata una restrizione: l'interfaccia lo spiega.
    case reenabledAutomatically
    /// Spenta senza attesa perché non c'erano restrizioni: vale solo finché non ne arriva una.
    case suspended
    /// Spenta con attesa e PIN: resta spenta finché non la si riattiva a mano.
    case disabled

    /// Come appare l'interruttore.
    public var isOn: Bool { self == .enabled || self == .reenabledAutomatically }
}

/// Decide quali protezioni di sistema tenere attive.
public enum ProtectionPolicy {
    /// La disinstallazione si blocca se c'è qualcosa da proteggere, salvo disattivazione confermata col PIN.
    public static func shouldDenyAppRemoval(
        rules: [Rule],
        isManualBlockActive: Bool,
        appRemoval: AppRemovalProtection
    ) -> Bool {
        appRemoval != .disabled && hasActiveRestrictions(rules: rules, isManualBlockActive: isManualBlockActive)
    }

    /// Senza ora automatica basterebbe spostare l'orologio per saltare attese e blocchi del PIN.
    public static func shouldRequireAutomaticDateAndTime(rules: [Rule], isManualBlockActive: Bool) -> Bool {
        hasActiveRestrictions(rules: rules, isManualBlockActive: isManualBlockActive)
    }

    public static func hasActiveRestrictions(rules: [Rule], isManualBlockActive: Bool) -> Bool {
        isManualBlockActive || rules.contains { $0.isEnabled }
    }

    /// L'interruttore cambiato a mano, quando `ChangePolicy` dice che non serve l'attesa.
    /// Ripetere il valore attuale non cambia nulla: non rende temporanea una disattivazione confermata col PIN.
    public static func appRemovalWithoutWait(
        from current: AppRemovalProtection,
        enabled: Bool
    ) -> AppRemovalProtection {
        guard enabled != current.isOn else { return current }
        return enabled ? .enabled : .suspended
    }

    /// Una disattivazione temporanea finisce con la prima restrizione attiva.
    public static func reconciled(
        _ current: AppRemovalProtection,
        hasActiveRestrictions: Bool
    ) -> AppRemovalProtection {
        current == .suspended && hasActiveRestrictions ? .reenabledAutomatically : current
    }
}

/// Stato della protezione salvato su file: chiudere e riaprire l'app non azzera attese e blocchi.
public struct ProtectionState: Codable, Equatable, Sendable {
    public var attempts: PINAttemptPolicy
    public var pending: PendingRelaxationQueue
    public var appRemoval: AppRemovalProtection

    public init(
        attempts: PINAttemptPolicy = PINAttemptPolicy(),
        pending: PendingRelaxationQueue = PendingRelaxationQueue(),
        appRemoval: AppRemovalProtection = .enabled
    ) {
        self.attempts = attempts
        self.pending = pending
        self.appRemoval = appRemoval
    }

    private enum CodingKeys: String, CodingKey {
        case attempts, pending, appRemoval
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case preventsAppRemoval
    }

    /// Legge anche il vecchio file col Bool `preventsAppRemoval`: se la decodifica fallisse,
    /// il chiamante ripartirebbe da zero perdendo attese e blocchi del PIN.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attempts = try container.decode(PINAttemptPolicy.self, forKey: .attempts)
        pending = try container.decode(PendingRelaxationQueue.self, forKey: .pending)
        if let appRemoval = try container.decodeIfPresent(AppRemovalProtection.self, forKey: .appRemoval) {
            self.appRemoval = appRemoval
        } else {
            // Il vecchio file non dice come era stata spenta: vale il significato che aveva, resta spenta.
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let prevents = try legacy.decodeIfPresent(Bool.self, forKey: .preventsAppRemoval) ?? true
            appRemoval = prevents ? .enabled : .disabled
        }
    }
}
