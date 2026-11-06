import Foundation

// Innboksen for delte kvitteringer. Delingsutvidelsen skriver én fil per kvittering, og appen leser og sletter dem.
//
// Denne filen skal kunne brukes av både appen og delingsutvidelsen, så den bruker bare Foundation og er `nonisolated`.
//
// Filformat, `<App Group>/Inbox/<id>.json` (id med store bokstaver):
//
//     { "id": "<UUID>", "text": "<tekst, maks 20 000 tegn>", "kind": "text" | "pdf" | "image",
//       "createdAt": "<ISO 8601, f.eks. 2026-11-06T14:19:25Z>" }

/// Hva som ble delt. Teksten er uansett hentet ut av utvidelsen (PDF-tekst eller OCR av bilde).
nonisolated enum ReceiptInboxKind: String, Codable, Sendable {
    case text
    case pdf
    case image

    /// Ukjente verdier blir `.text`: slaget er bare informasjon, og en nyere utvidelse skal ikke gjøre filen ulesbar.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReceiptInboxKind(rawValue: raw) ?? .text
    }
}

/// Én delt kvittering slik den ligger i filen.
nonisolated struct ReceiptInboxItem: Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let kind: ReceiptInboxKind
    let createdAt: Date
}

nonisolated struct ReceiptInbox {
    /// Appens og utvidelsens felles App Group.
    static let appGroupIdentifier = "group.com.opland.subtrack"
    static let folderName = "Inbox"
    /// Lengre tekst kuttes, både når den skrives og når den leses.
    static let maxTextLength = 20_000
    /// Filer eldre enn dette slettes uten å vises.
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    /// En fil som ikke kan tolkes, får ligge så lenge før den regnes som ødelagt: den kan fortsatt bli skrevet.
    static let partialFileGrace: TimeInterval = 60
    /// Større filer enn dette kan ikke være gyldige (20 000 tegn gir under 120 kB selv med `\u`-koding).
    static let maxFileSize = 512 * 1024

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// Innboksen i App Group-mappen, eller nil hvis App Group ikke er tilgjengelig.
    static func appGroup(fileManager: FileManager = .default) -> ReceiptInbox? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            .map { ReceiptInbox(directory: $0.appendingPathComponent(folderName, isDirectory: true)) }
    }

    /// En fil som er lest, med stedet den ligger.
    nonisolated struct Entry: Equatable, Sendable {
        let item: ReceiptInboxItem
        let url: URL
    }

    nonisolated enum WriteError: Error, Equatable {
        case emptyText
    }

    // MARK: - Koding

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Godtar ISO 8601 med og uten brøkdeler av sekunder.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = plain.date(from: text) ?? fractional.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Ugyldig dato \"\(text)\".")
                )
            }
            return date
        }
        return decoder
    }

    // MARK: - Lesing (appen)

    /// Gyldige filer, eldste først. Rydder samtidig: filer eldre enn 7 dager og ødelagte filer slettes uten å
    /// bli returnert. Gyldige filer slettes ikke her; bruk `remove(_:)` når de er tatt imot, eller `drain`.
    ///
    /// - En fil som ikke kan tolkes og er endret for under `partialFileGrace` siden, røres ikke: utvidelsen kan
    ///   fortsatt skrive den. Den tas med neste gang.
    /// - En fil som ikke kan leses (f.eks. fordi enheten er låst), røres ikke.
    func entries(now: Date = Date(), fileManager: FileManager = .default) -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [Entry] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate ?? .distantPast

            // Halvferdige skrivinger (`.tmp`) hører ikke til; de ryddes bort når de er gamle nok.
            if url.pathExtension == "tmp" {
                if now.timeIntervalSince(modified) > Self.maxAge {
                    try? fileManager.removeItem(at: url)
                }
                continue
            }
            guard url.pathExtension == "json" else { continue }

            let isStale = now.timeIntervalSince(modified) > Self.partialFileGrace
            if let size = values?.fileSize, size > Self.maxFileSize {
                if isStale { try? fileManager.removeItem(at: url) }
                continue
            }
            guard let data = try? Data(contentsOf: url) else { continue }

            guard let decoded = try? Self.makeDecoder().decode(ReceiptInboxItem.self, from: data) else {
                if isStale { try? fileManager.removeItem(at: url) }
                continue
            }

            if now.timeIntervalSince(decoded.createdAt) > Self.maxAge
                || decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? fileManager.removeItem(at: url)
                continue
            }

            let item = decoded.text.count > Self.maxTextLength
                ? ReceiptInboxItem(
                    id: decoded.id,
                    text: String(decoded.text.prefix(Self.maxTextLength)),
                    kind: decoded.kind,
                    createdAt: decoded.createdAt
                )
                : decoded
            result.append(Entry(item: item, url: url))
        }
        return result.sorted { ($0.item.createdAt, $0.url.lastPathComponent) < ($1.item.createdAt, $1.url.lastPathComponent) }
    }

    /// Sletter filen til en kvittering som er tatt imot.
    func remove(_ entry: Entry, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: entry.url)
    }

    /// Leser alle gyldige kvitteringer, eldste først, og sletter filene.
    func drain(now: Date = Date(), fileManager: FileManager = .default) -> [ReceiptInboxItem] {
        let found = entries(now: now, fileManager: fileManager)
        for entry in found {
            remove(entry, fileManager: fileManager)
        }
        return found.map(\.item)
    }

    // MARK: - Skriving (delingsutvidelsen)

    /// Lagrer en kvittering som en fil i innboksen og returnerer det som ble lagret.
    ///
    /// - Teksten trimmes og kuttes til `maxTextLength` tegn. Tom tekst gir `WriteError.emptyText`.
    /// - Mappen og filen får `FileProtectionType.complete` og holdes utenfor sikkerhetskopi.
    /// - Filen skrives først som `<id>.tmp` og gis så det endelige navnet `<id>.json`, så appen aldri ser en halv fil.
    @discardableResult
    func write(
        text: String,
        kind: ReceiptInboxKind,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> ReceiptInboxItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WriteError.emptyText }

        let item = ReceiptInboxItem(
            id: UUID(),
            text: String(trimmed.prefix(Self.maxTextLength)),
            kind: kind,
            createdAt: now
        )
        let data = try Self.makeEncoder().encode(item)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try Self.excludeFromBackup(directory)

        let name = item.id.uuidString
        let temporary = directory.appendingPathComponent("\(name).tmp")
        let final = directory.appendingPathComponent("\(name).json")
        try data.write(to: temporary, options: [.completeFileProtection])
        try Self.excludeFromBackup(temporary)
        try fileManager.moveItem(at: temporary, to: final)
        return item
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }
}
