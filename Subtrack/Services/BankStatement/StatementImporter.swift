import Foundation

/// Hvorfor en fil ikke kunne gi forslag.
enum StatementImportError: Error, Equatable {
    /// Filen er tom eller har ingen rader.
    case unreadable
    /// Overskriftene mangler kolonner vi trenger. Navnene står på norsk.
    case missingColumns([String])
    /// Kolonnene finnes, men ingen rader er en utgående betaling med gyldig dato.
    case noTransactions
}

/// Resultatet av å lese en kontoutskrift: hva som ble lest, og forslagene.
struct StatementAnalysis: Equatable {
    /// Perioder kortere enn dette gir få trekk som kommer igjen. Brukeren får beskjed om det.
    static let shortPeriodDays = 60

    /// Antall utgående betalinger som ble lest.
    let transactionCount: Int
    let periodStart: Date
    let periodEnd: Date
    /// Antall dager fra første til siste betaling.
    let periodDays: Int
    let suggestions: [SubscriptionSuggestion]

    var isShortPeriod: Bool { periodDays < Self.shortPeriodDays }
}

/// Hele veien fra bytene i en fil til forslag: avkoding, CSV, kolonner, transaksjoner og gjentakende trekk.
/// Alt skjer i minnet. Ingenting lagres eller logges.
enum StatementImporter {
    static func analyze(
        data: Data,
        catalog: ServiceCatalog = .bundled,
        existingNames: [String] = [],
        now: Date = .now,
        calendar: Calendar = StatementValues.defaultCalendar
    ) throws -> StatementAnalysis {
        let rows = CSVTokenizer.parse(StatementDecoder.decode(data))
        guard !rows.isEmpty else { throw StatementImportError.unreadable }

        let layout: StatementLayout
        switch StatementLayout.detect(in: rows) {
        case .success(let detected):
            layout = detected
        case .failure(let error):
            throw StatementImportError.missingColumns(error.missingColumns)
        }

        let transactions = StatementRow.transactions(in: rows, layout: layout, calendar: calendar)
        guard let first = transactions.map(\.date).min(), let last = transactions.map(\.date).max() else {
            throw StatementImportError.noTransactions
        }

        return StatementAnalysis(
            transactionCount: transactions.count,
            periodStart: first,
            periodEnd: last,
            periodDays: calendar.dateComponents([.day], from: first, to: last).day ?? 0,
            suggestions: RecurringChargeDetector.detect(
                transactions: transactions,
                catalog: catalog,
                existingNames: existingNames,
                now: now,
                calendar: calendar
            )
        )
    }
}
