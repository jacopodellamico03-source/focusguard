import Foundation

/// Decide quali protezioni di sistema tenere attive.
public enum ProtectionPolicy {
    /// La disinstallazione si blocca solo se la preferenza è attiva e c'è qualcosa da proteggere.
    public static func shouldDenyAppRemoval(
        rules: [Rule],
        isManualBlockActive: Bool,
        preventsAppRemoval: Bool
    ) -> Bool {
        preventsAppRemoval && hasActiveRestrictions(rules: rules, isManualBlockActive: isManualBlockActive)
    }

    /// Senza ora automatica basterebbe spostare l'orologio per saltare attese e blocchi del PIN.
    public static func shouldRequireAutomaticDateAndTime(rules: [Rule], isManualBlockActive: Bool) -> Bool {
        hasActiveRestrictions(rules: rules, isManualBlockActive: isManualBlockActive)
    }

    public static func hasActiveRestrictions(rules: [Rule], isManualBlockActive: Bool) -> Bool {
        isManualBlockActive || rules.contains { $0.isEnabled }
    }
}

/// Stato della protezione salvato su file: chiudere e riaprire l'app non azzera attese e blocchi.
public struct ProtectionState: Codable, Equatable, Sendable {
    public var attempts: PINAttemptPolicy
    public var pending: PendingRelaxationQueue
    /// Preferenza "Impedisci la disinstallazione delle app".
    public var preventsAppRemoval: Bool

    public init(
        attempts: PINAttemptPolicy = PINAttemptPolicy(),
        pending: PendingRelaxationQueue = PendingRelaxationQueue(),
        preventsAppRemoval: Bool = true
    ) {
        self.attempts = attempts
        self.pending = pending
        self.preventsAppRemoval = preventsAppRemoval
    }
}
