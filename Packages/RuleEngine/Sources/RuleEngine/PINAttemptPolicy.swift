import Foundation

/// Tentativi di PIN errati e relativo blocco. Il tempo arriva sempre da fuori,
/// e lo stato si salva: chiudere l'app non azzera il blocco.
public struct PINAttemptPolicy: Codable, Equatable, Sendable {
    public static let freeAttempts = 5
    public static let baseLockout: TimeInterval = 60
    public static let maxLockout: TimeInterval = 3600

    public private(set) var failedAttempts: Int
    public private(set) var lockedUntil: Date?

    public init(failedAttempts: Int = 0, lockedUntil: Date? = nil) {
        self.failedAttempts = failedAttempts
        self.lockedUntil = lockedUntil
    }

    public func isLocked(at date: Date) -> Bool {
        remainingLockout(at: date) > 0
    }

    public func remainingLockout(at date: Date) -> TimeInterval {
        guard let lockedUntil else { return 0 }
        return max(0, lockedUntil.timeIntervalSince(date))
    }

    /// Un errore durante il blocco non conta: in quel momento il PIN non viene nemmeno verificato.
    public mutating func registerFailure(at date: Date) {
        guard !isLocked(at: date) else { return }
        failedAttempts += 1
        if failedAttempts >= Self.freeAttempts {
            lockedUntil = date.addingTimeInterval(Self.lockout(afterFailures: failedAttempts))
        }
    }

    public mutating func registerSuccess() {
        failedAttempts = 0
        lockedUntil = nil
    }

    private static func lockout(afterFailures failures: Int) -> TimeInterval {
        // Oltre 6 raddoppi si è già al massimo: niente potenze enormi.
        let doublings = min(failures - freeAttempts, 6)
        return min(baseLockout * pow(2, Double(doublings)), maxLockout)
    }
}
