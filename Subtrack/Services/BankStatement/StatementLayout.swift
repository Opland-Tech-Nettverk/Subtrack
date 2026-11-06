import Foundation

/// Kolonnene som mangler i en fil, med norske navn, så brukeren kan se hva som er galt.
nonisolated struct StatementLayoutError: Error, Equatable {
    let missingColumns: [String]
}

/// Hvilke kolonner i en CSV-fil som er dato, tekst og beløp. Kolonnene gjenkjennes fra overskriftene,
/// ikke fra hvilken bank filen kommer fra, så nye eller endrede oppbygninger ofte virker uten endringer.
/// `nonisolated` fordi den er ren beregning uten tilknytning til brukergrensesnittet.
nonisolated struct StatementLayout: Equatable {
    nonisolated enum Amount: Equatable {
        /// Ett beløp per rad, der utgående er negativt.
        case single(column: Int)
        /// Egen kolonne for beløp ut, og eventuelt én for beløp inn. Fortegnet i ut-kolonnen stoles ikke på.
        case outgoingIncoming(outgoing: Int, incoming: Int?)
    }

    /// Raden overskriftene står i. Radene etter den er transaksjoner.
    let headerRowIndex: Int
    let dateColumn: Int
    let textColumn: Int
    let amount: Amount
    let currencyColumn: Int?
    /// Kolonne med status («State» hos Revolut, «Status» hos Danske Bank), om filen har en. Rader som
    /// ikke er gjennomført (venter, avvist, tilbakeført), hoppes over.
    var statusColumn: Int? = nil

    // Overskriftene som gjenkjennes, i prioritert rekkefølge og skrevet slik `headerKey` gir dem.
    // «Rentedato» og «Valuteringsdato» er med vilje utelatt: de er ikke datoen varen ble kjøpt.
    private static let dateHeaders = [
        "dato", "bokforingsdato", "bokfort dato", "utfort dato",
        "transactiondate", "transaction date", "started date", "date"
    ]
    private static let textHeaders = [
        "forklaring", "beskrivelse", "tekst", "tekst/kid", "tittel",
        "text", "description", "melding/kid/fakt.nr"
    ]
    private static let amountHeaders = ["belop", "amount"]
    private static let outgoingHeaders = ["ut fra konto", "ut", "belop ut", "uttak"]
    private static let incomingHeaders = ["inn pa konto", "inn", "belop inn", "innskudd"]
    private static let currencyHeaders = ["valuta", "currency", "valutakode"]
    private static let statusHeaders = ["state", "status", "tilstand"]

    /// Hvor mange rader i starten det letes etter overskrifter i. Noen banker har linjer foran dem.
    private static let headerSearchLimit = 30

    /// Finner overskriftsraden og kolonnene. Mangler det kolonner, sies det hvilke.
    static func detect(in rows: [[String]]) -> Result<StatementLayout, StatementLayoutError> {
        var bestMissing = ["dato", "tekst (forklaring eller beskrivelse)", "beløp"]
        var bestScore = -1

        for (index, row) in rows.prefix(headerSearchLimit).enumerated() {
            let keys = row.map(headerKey)
            let date = firstColumn(in: keys, matching: dateHeaders)
            let text = firstColumn(in: keys, matching: textHeaders)
            let amount = amountColumns(in: keys)

            if let date, let text, let amount {
                return .success(StatementLayout(
                    headerRowIndex: index,
                    dateColumn: date,
                    textColumn: text,
                    amount: amount,
                    currencyColumn: firstColumn(in: keys, matching: currencyHeaders),
                    statusColumn: firstColumn(in: keys, matching: statusHeaders)
                ))
            }

            var missing: [String] = []
            if date == nil { missing.append("dato") }
            if text == nil { missing.append("tekst (forklaring eller beskrivelse)") }
            if amount == nil { missing.append("beløp") }
            let score = 3 - missing.count
            if score > bestScore {
                bestScore = score
                bestMissing = missing
            }
        }
        return .failure(StatementLayoutError(missingColumns: bestMissing))
    }

    /// Små bokstaver uten diakritiske tegn og med enkle mellomrom, så «Bokføringsdato» og
    /// «Inn på konto» blir «bokforingsdato» og «inn pa konto».
    static func headerKey(_ header: String) -> String {
        header
            .lowercased()
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.diacriticInsensitive], locale: nil)
            .split { $0.isWhitespace }
            .joined(separator: " ")
    }

    private static func firstColumn(in keys: [String], matching headers: [String]) -> Int? {
        for header in headers {
            if let index = keys.firstIndex(of: header) {
                return index
            }
        }
        return nil
    }

    private static func amountColumns(in keys: [String]) -> Amount? {
        if let single = firstColumn(in: keys, matching: amountHeaders) {
            return .single(column: single)
        }
        if let outgoing = firstColumn(in: keys, matching: outgoingHeaders) {
            return .outgoingIncoming(
                outgoing: outgoing,
                incoming: firstColumn(in: keys, matching: incomingHeaders)
            )
        }
        return nil
    }
}
