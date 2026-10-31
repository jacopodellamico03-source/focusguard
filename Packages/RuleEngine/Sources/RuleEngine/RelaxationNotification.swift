import Foundation

/// Notifica locale legata a una richiesta in attesa. Il testo dipende solo da `kind`,
/// quindi sulla schermata di blocco non può finire il nome di una regola.
public struct RelaxationNotification: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// Finita l'attesa, si può confermare.
        case windowOpened
        /// La finestra di conferma sta per chiudersi.
        case expiringSoon
    }

    /// Anticipo dell'avviso rispetto alla scadenza della richiesta.
    public static let expiryWarning: TimeInterval = 300
    public static let identifierPrefix = "relaxation."

    public let requestID: UUID
    public let kind: Kind
    public let fireDate: Date

    public init(requestID: UUID, kind: Kind, fireDate: Date) {
        self.requestID = requestID
        self.kind = kind
        self.fireDate = fireDate
    }

    public var identifier: String { Self.identifier(requestID: requestID, kind: kind) }

    public static func identifier(requestID: UUID, kind: Kind) -> String {
        "\(identifierPrefix)\(requestID.uuidString).\(kind.rawValue)"
    }
}

/// Decide quali notifiche programmare e quali togliere. Il tempo arriva sempre da fuori.
public enum RelaxationNotificationPlan {
    /// Cosa fare per allineare le notifiche di iOS alle richieste salvate.
    public struct Reconciliation: Equatable, Sendable {
        public let toSchedule: [RelaxationNotification]
        public let toCancel: Set<String>
        public let toRemoveDelivered: Set<String>

        public init(toSchedule: [RelaxationNotification], toCancel: Set<String>, toRemoveDelivered: Set<String>) {
            self.toSchedule = toSchedule
            self.toCancel = toCancel
            self.toRemoveDelivered = toRemoveDelivered
        }
    }

    /// Le notifiche ancora da venire: una data uguale a `now` è già passata.
    public static func notifications(for request: PendingRelaxation, now: Date) -> [RelaxationNotification] {
        let dates: [(RelaxationNotification.Kind, Date)] = [
            (.windowOpened, request.cooldown.unlocksAt),
            (.expiringSoon, request.expiresAt.addingTimeInterval(-RelaxationNotification.expiryWarning))
        ]
        return dates
            .filter { $0.1 > now }
            .map { RelaxationNotification(requestID: request.id, kind: $0.0, fireDate: $0.1) }
    }

    /// - Parameters:
    ///   - requests: le richieste salvate.
    ///   - scheduled: identificativi delle notifiche programmate in iOS.
    ///   - delivered: identificativi delle notifiche già consegnate.
    public static func reconcile(
        requests: [PendingRelaxation],
        scheduled: Set<String>,
        delivered: Set<String>,
        now: Date
    ) -> Reconciliation {
        let live = requests.filter { $0.phase(at: now) != .expired }
        // Tutti i tipi, non solo quelli futuri: una notifica dovuta in questo istante non va cancellata.
        let liveIdentifiers = Set(live.flatMap { request in
            RelaxationNotification.Kind.allCases.map {
                RelaxationNotification.identifier(requestID: request.id, kind: $0)
            }
        })
        func orphans(in identifiers: Set<String>) -> Set<String> {
            identifiers.filter { $0.hasPrefix(RelaxationNotification.identifierPrefix) && !liveIdentifiers.contains($0) }
        }
        return Reconciliation(
            toSchedule: live
                .flatMap { notifications(for: $0, now: now) }
                .filter { !scheduled.contains($0.identifier) },
            toCancel: orphans(in: scheduled),
            toRemoveDelivered: orphans(in: delivered)
        )
    }
}
