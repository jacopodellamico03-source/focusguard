import Foundation

/// Effetto di una modifica sulle restrizioni.
public enum ChangeImpact: String, Equatable, Sendable {
    /// Rende le regole più severe: nessun PIN richiesto.
    case tightening
    /// Allenta le regole: attesa e PIN richiesti.
    case relaxing
    /// Nessun effetto sulle restrizioni (es. solo il nome).
    case neutral
}

/// Classifica le modifiche per decidere quando chiedere il PIN.
/// Principio: nel dubbio è "relaxing".
public enum ChangePolicy {
    /// - Parameters:
    ///   - old: regola esistente, nil se nuova.
    ///   - new: regola dopo la modifica, nil se eliminata.
    ///   - selectionChanged: le app scelte sono cambiate. I token di Apple sono opachi e
    ///     non si può sapere se la nuova selezione è più ampia: trattato sempre come "relaxing".
    public static func impact(old: Rule?, new: Rule?, selectionChanged: Bool) -> ChangeImpact {
        switch (old, new) {
        case (nil, nil):
            return .neutral
        case (nil, .some(_)):
            return .tightening
        case (.some(let old), nil):
            return old.isEnabled ? .relaxing : .neutral
        case let (.some(old), .some(new)):
            return compare(old: old, new: new, selectionChanged: selectionChanged)
        }
    }

    private static func compare(old: Rule, new: Rule, selectionChanged: Bool) -> ChangeImpact {
        // Regole spente prima e dopo: niente cambia nei blocchi.
        if !old.isEnabled && !new.isEnabled { return .neutral }
        if old.isEnabled && !new.isEnabled { return .relaxing }
        if !old.isEnabled && new.isEnabled { return .tightening }

        if selectionChanged { return .relaxing }

        var relaxes = false
        var tightens = false

        if !new.weekdays.isSuperset(of: old.weekdays) { relaxes = true }
        if new.weekdays.isStrictSuperset(of: old.weekdays) { tightens = true }

        switch (old.kind, new.kind) {
        case let (.dailyLimit(a), .dailyLimit(b)):
            if b > a { relaxes = true }
            if b < a { tightens = true }
        case let (.schedule(s1, e1), .schedule(s2, e2)):
            let oldMinutes = minuteSet(start: s1, end: e1)
            let newMinutes = minuteSet(start: s2, end: e2)
            if !newMinutes.isSuperset(of: oldMinutes) { relaxes = true }
            if newMinutes.isStrictSuperset(of: oldMinutes) { tightens = true }
        default:
            // Cambio di tipo: non confrontabile, quindi prudenza.
            relaxes = true
        }

        if relaxes { return .relaxing }
        if tightens { return .tightening }
        return .neutral
    }

    /// Blocco immediato. Le app scelte sono token opachi: cambiarle a blocco attivo è sempre "relaxing".
    public static func manualBlockImpact(wasActive: Bool, isActive: Bool, selectionChanged: Bool) -> ChangeImpact {
        switch (wasActive, isActive) {
        case (true, false): return .relaxing
        case (false, true): return .tightening
        case (true, true): return selectionChanged ? .relaxing : .neutral
        case (false, false): return .neutral
        }
    }

    /// Preferenza "Impedisci la disinstallazione delle app".
    /// Senza regole attive né blocco immediato la protezione è già spenta: toglierla non allenta nulla.
    public static func appRemovalProtectionImpact(
        wasEnabled: Bool,
        isEnabled: Bool,
        hasActiveRestrictions: Bool
    ) -> ChangeImpact {
        switch (wasEnabled, isEnabled) {
        case (true, false): return hasActiveRestrictions ? .relaxing : .neutral
        case (false, true): return .tightening
        default: return .neutral
        }
    }

    /// Minuti del giorno coperti dalla finestra (gestisce la mezzanotte).
    private static func minuteSet(start: TimeOfDay, end: TimeOfDay) -> Set<Int> {
        let duration = RuleValidator.durationMinutes(start: start, end: end)
        return Set((0..<duration).map { (start.minutesFromMidnight + $0) % 1440 })
    }
}

/// Attesa obbligatoria prima di confermare una modifica che allenta le regole.
public struct Cooldown: Codable, Equatable, Sendable {
    public let requestedAt: Date
    public let duration: TimeInterval

    public init(requestedAt: Date, duration: TimeInterval) {
        self.requestedAt = requestedAt
        self.duration = duration
    }

    public var unlocksAt: Date { requestedAt.addingTimeInterval(duration) }

    public func canConfirm(at date: Date) -> Bool { date >= unlocksAt }

    public func remaining(at date: Date) -> TimeInterval { max(0, unlocksAt.timeIntervalSince(date)) }
}
