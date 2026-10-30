import CommonCrypto
import Foundation
import RuleEngine
import Security

/// PIN nel Keychain: solo hash e salt, mai il PIN in chiaro.
/// Serve solo all'app, quindi niente access group condiviso con le estensioni.
struct PINStore {
    enum StoreError: Error, CustomStringConvertible {
        case keychain(OSStatus)
        case randomBytes(OSStatus)
        case keyDerivation(Int32)
        case corruptRecord

        var description: String {
            switch self {
            case let .keychain(status): return "Errore del portachiavi (\(status))."
            case let .randomBytes(status): return "Generazione casuale non riuscita (\(status))."
            case let .keyDerivation(status): return "Calcolo dell'hash non riuscito (\(status))."
            case .corruptRecord: return "Dati del PIN illeggibili."
            }
        }
    }

    /// Le iterazioni stanno nel record: si potranno aumentare senza invalidare i PIN esistenti.
    private struct Record: Codable {
        let salt: Data
        let hash: Data
        let iterations: UInt32
    }

    private static let service = "it.jacopo.focusguard.pin"
    private static let account = "pin"
    private static let iterations: UInt32 = 200_000
    private static let saltLength = 16
    private static let hashLength = 32

    func hasPIN() throws -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = false
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw StoreError.keychain(status)
        }
    }

    /// Crea il PIN o sostituisce quello esistente.
    func set(_ pin: String) throws {
        let salt = try Self.randomSalt()
        let record = Record(
            salt: salt,
            hash: try Self.derive(pin, salt: salt, iterations: Self.iterations),
            iterations: Self.iterations
        )
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(record),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw StoreError.keychain(updateStatus) }

        let addStatus = SecItemAdd(baseQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
    }

    func verify(_ pin: String) throws -> Bool {
        let record = try loadRecord()
        let hash = try Self.derive(pin, salt: record.salt, iterations: record.iterations)
        return ConstantTime.equals(hash, record.hash)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    // MARK: Interni

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }

    private func loadRecord() throws -> Record {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = result as? Data, let record = try? JSONDecoder().decode(Record.self, from: data) else {
            throw StoreError.corruptRecord
        }
        return record
    }

    private static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltLength, &bytes)
        guard status == errSecSuccess else { throw StoreError.randomBytes(status) }
        return Data(bytes)
    }

    private static func derive(_ pin: String, salt: Data, iterations: UInt32) throws -> Data {
        var derived = [UInt8](repeating: 0, count: hashLength)
        let saltBytes = [UInt8](salt)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            pin,
            pin.utf8.count,
            saltBytes,
            saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            iterations,
            &derived,
            hashLength
        )
        guard status == Int32(kCCSuccess) else { throw StoreError.keyDerivation(status) }
        return Data(derived)
    }
}
