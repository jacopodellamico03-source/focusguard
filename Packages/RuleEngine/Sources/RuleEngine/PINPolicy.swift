import Foundation

/// Errori di validazione del PIN, con messaggi pronti per l'interfaccia.
public enum PINValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case notDigits
    case wrongLength(count: Int)
    case trivial

    public var description: String {
        switch self {
        case .notDigits:
            return "Il PIN può contenere solo cifre."
        case .wrongLength:
            return "Il PIN deve avere da \(PINPolicy.minLength) a \(PINPolicy.maxLength) cifre."
        case .trivial:
            return "PIN troppo facile: evita sequenze e ripetizioni."
        }
    }
}

public enum PINPolicy {
    public static let minLength = 6
    public static let maxLength = 8

    /// Restituisce tutti gli errori (lista vuota = PIN valido).
    public static func validate(_ pin: String) -> [PINValidationError] {
        var errors: [PINValidationError] = []

        // Solo ASCII: Character.isNumber accetterebbe anche altre scritture.
        let isAllDigits = pin.utf8.allSatisfy { (48...57).contains($0) }
        if !isAllDigits {
            errors.append(.notDigits)
        }
        let hasValidLength = (minLength...maxLength).contains(pin.count)
        if !hasValidLength {
            errors.append(.wrongLength(count: pin.count))
        }
        if isAllDigits && hasValidLength && isTrivial(pin.utf8.map { Int($0) - 48 }) {
            errors.append(.trivial)
        }
        return errors
    }

    private static func isTrivial(_ digits: [Int]) -> Bool {
        isSequence(digits, step: 1) || isSequence(digits, step: 9) || isRepeatedPattern(digits)
    }

    /// Cifre consecutive, anche passando per lo zero (890123). Il passo 9 equivale a -1 modulo 10.
    private static func isSequence(_ digits: [Int], step: Int) -> Bool {
        zip(digits, digits.dropFirst()).allSatisfy { ($0 + step) % 10 == $1 }
    }

    /// Un blocco ripetuto per tutta la lunghezza: 111111, 121212, 123123.
    private static func isRepeatedPattern(_ digits: [Int]) -> Bool {
        (1...(digits.count / 2))
            .filter { digits.count % $0 == 0 }
            .contains { period in digits.indices.allSatisfy { digits[$0] == digits[$0 % period] } }
    }
}

/// Confronto che non si ferma al primo byte diverso: il tempo non rivela quanto è giusto l'hash.
public enum ConstantTime {
    public static func equals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
