import Foundation

/// Gjør om bytene fra en fil til tekst. Filen leses bare i minnet.
///
/// Fjerner byte order mark, prøver UTF-8 først og Windows-1252 (eller ISO-8859-1) etterpå, siden
/// mange norske nettbanker eksporterer i den eldre kodingen, og gjør alle linjeskift til `\n`.
/// `nonisolated` fordi den er ren beregning uten tilknytning til brukergrensesnittet.
nonisolated enum StatementDecoder {
    static func decode(_ data: Data) -> String {
        let text = decodeWithoutLineBreakNormalization(data)
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func decodeWithoutLineBreakNormalization(_ data: Data) -> String {
        let bytes = [UInt8](data)

        // UTF-16 med byte order mark, som noen Excel-eksporter lager.
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) {
                return stripByteOrderMark(text)
            }
        }

        let payload = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(bytes.dropFirst(3)) : data
        if let text = String(data: payload, encoding: .utf8) {
            return stripByteOrderMark(text)
        }
        // Windows-1252 har noen få udefinerte byte; ISO-8859-1 godtar alle.
        if let text = String(data: payload, encoding: .windowsCP1252) {
            return text
        }
        return String(data: payload, encoding: .isoLatin1) ?? ""
    }

    private static func stripByteOrderMark(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}
