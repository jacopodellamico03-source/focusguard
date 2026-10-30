import Foundation
import os

/// Identificativi condivisi tra app ed estensioni.
/// Se cambi l'App Group, aggiorna anche i file .entitlements in iOS/Config/.
enum AppGroup {
    static let identifier = "group.it.jacopo.focusguard"

    /// Cartella condivisa. Manca solo se l'entitlement App Groups non è nel profilo di firma.
    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            fatalError("App Group \(identifier) non disponibile: controlla entitlements e profilo di firma.")
        }
        return url
    }
}

/// Log leggibili da Ubuntu con: idevicesyslog | grep it.jacopo.focusguard
enum Log {
    static let subsystem = "it.jacopo.focusguard"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    static let storage = Logger(subsystem: subsystem, category: "storage")
}
