import Foundation

/// Una riga del log eventi, scritta dall'estensione Monitor.
public struct EventLogEntry: Codable, Equatable, Sendable {
    public let date: Date
    public let ruleID: UUID?
    public let trigger: MonitorTrigger
    public let action: ShieldVerdict
    public let note: String?

    public init(date: Date, ruleID: UUID?, trigger: MonitorTrigger, action: ShieldVerdict, note: String? = nil) {
        self.date = date
        self.ruleID = ruleID
        self.trigger = trigger
        self.action = action
        self.note = note
    }
}

/// Formato JSON Lines: una riga JSON per evento. Appendere costa poco,
/// adatto alla memoria limitata dell'estensione.
public enum EventLogCodec {
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Una riga terminata da "\n".
    public static func encodeLine(_ entry: EventLogEntry) throws -> Data {
        var data = try makeEncoder().encode(entry)
        data.append(0x0A)
        return data
    }

    /// Decodifica il file intero, saltando le righe corrotte (es. scrittura interrotta).
    public static func decode(_ data: Data) -> [EventLogEntry] {
        let decoder = makeDecoder()
        return data
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .compactMap { try? decoder.decode(EventLogEntry.self, from: Data($0)) }
    }

    /// Tiene solo gli eventi degli ultimi `days` giorni, per non far crescere il file.
    public static func pruned(_ entries: [EventLogEntry], keepingDays days: Int, now: Date) -> [EventLogEntry] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return entries.filter { $0.date >= cutoff }
    }

    public static func encodeAll(_ entries: [EventLogEntry]) throws -> Data {
        var data = Data()
        for entry in entries {
            data.append(try encodeLine(entry))
        }
        return data
    }
}
