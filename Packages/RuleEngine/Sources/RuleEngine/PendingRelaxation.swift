import Foundation

/// Richiesta di una modifica che allenta le regole: si conferma col PIN dopo l'attesa, si può annullare.
/// La selezione di app proposta (token opachi) è salvata a parte, nel livello iOS, con la stessa `id`.
public struct PendingRelaxation: Codable, Equatable, Identifiable, Sendable {
    public enum Change: Codable, Equatable, Sendable {
        case disableRule(UUID)
        case deleteRule(UUID)
        /// La regola come sarà dopo la conferma.
        case editRule(Rule)
        case disableManualBlock
        case changeManualSelection
        case disableAppRemovalProtection
    }

    /// Ciò che la richiesta tiene occupato: una sola richiesta per volta su ciascun bersaglio.
    public enum Target: Hashable, Sendable {
        case rule(UUID)
        case manualBlock
        case appRemovalProtection
    }

    public enum Phase: Equatable, Sendable {
        case waiting
        case confirmable
        case expired
    }

    public static let cooldownDuration: TimeInterval = 600
    /// Finita l'attesa la conferma vale per poco: altrimenti una richiesta tenuta "armata"
    /// permetterebbe di togliere la regola all'istante, in qualsiasi momento.
    public static let confirmationWindow: TimeInterval = 1800

    public let id: UUID
    public let change: Change
    public let cooldown: Cooldown

    public init(id: UUID = UUID(), change: Change, requestedAt: Date) {
        self.id = id
        self.change = change
        self.cooldown = Cooldown(requestedAt: requestedAt, duration: Self.cooldownDuration)
    }

    public var target: Target {
        switch change {
        case let .disableRule(id), let .deleteRule(id):
            return .rule(id)
        case let .editRule(rule):
            return .rule(rule.id)
        case .disableManualBlock, .changeManualSelection:
            return .manualBlock
        case .disableAppRemovalProtection:
            return .appRemovalProtection
        }
    }

    public var expiresAt: Date { cooldown.unlocksAt.addingTimeInterval(Self.confirmationWindow) }

    public func phase(at date: Date) -> Phase {
        if !cooldown.canConfirm(at: date) { return .waiting }
        return date < expiresAt ? .confirmable : .expired
    }

    public func canConfirm(at date: Date) -> Bool { phase(at: date) == .confirmable }

    /// Attesa che manca prima di poter confermare.
    public func remaining(at date: Date) -> TimeInterval { cooldown.remaining(at: date) }

    /// Tempo che manca alla scadenza della richiesta.
    public func confirmationRemaining(at date: Date) -> TimeInterval { max(0, expiresAt.timeIntervalSince(date)) }
}

/// Le richieste in corso.
public struct PendingRelaxationQueue: Codable, Equatable, Sendable {
    public private(set) var items: [PendingRelaxation]

    public init(items: [PendingRelaxation] = []) {
        self.items = items
    }

    public func pending(for target: PendingRelaxation.Target) -> PendingRelaxation? {
        items.first { $0.target == target }
    }

    public func request(id: UUID) -> PendingRelaxation? {
        items.first { $0.id == id }
    }

    /// Se il bersaglio ha già una richiesta restituisce quella: l'attesa non riparte
    /// e non si può cambiare ciò che si sta aspettando.
    @discardableResult
    public mutating func enqueue(_ change: PendingRelaxation.Change, at date: Date) -> PendingRelaxation {
        let request = PendingRelaxation(change: change, requestedAt: date)
        if let existing = pending(for: request.target) { return existing }
        items.append(request)
        return request
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Toglie le richieste scadute e le restituisce, così il chiamante può ripulire ciò che ha salvato a parte.
    @discardableResult
    public mutating func removeExpired(at date: Date) -> [PendingRelaxation] {
        let expired = items.filter { $0.phase(at: date) == .expired }
        items.removeAll { $0.phase(at: date) == .expired }
        return expired
    }
}
