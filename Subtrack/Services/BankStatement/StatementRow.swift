import Foundation

/// En utgående betaling fra en kontoutskrift. Bare i minnet: aldri lagret eller sendt noe sted.
/// (Ikke `Transaction`, som er en SwiftUI-type.)
nonisolated struct StatementTransaction: Equatable {
    /// Dagen betalingen ble gjort, kl. 12.
    let date: Date
    /// Beløpet som ble trukket, alltid positivt, i `currencyCode`.
    let amount: Decimal
    let currencyCode: String
    /// Teksten fra banken, med enkle mellomrom, f.eks. "*1234 14.08 USD 20.00 NETFLIX.COM Kurs: 9.1234".
    let text: String
}

/// Gjør en rad fra CSV-filen om til en transaksjon.
/// `nonisolated` fordi den er ren beregning uten tilknytning til brukergrensesnittet.
nonisolated enum StatementRow {
    /// Transaksjonen i raden, eller nil for rader som ikke er en utgående betaling: reservasjoner,
    /// saldo- og bunnlinjer, rader uten gyldig dato eller tekst, og inngående beløp.
    static func transaction(
        from row: [String],
        layout: StatementLayout,
        calendar: Calendar = StatementValues.defaultCalendar
    ) -> StatementTransaction? {
        func cell(_ column: Int?) -> String {
            guard let column, column >= 0, column < row.count else { return "" }
            return row[column]
        }

        // En reservert betaling er ikke trukket ennå, og kommer igjen som en vanlig rad.
        if row.contains(where: { StatementLayout.headerKey($0) == "reservert" }) {
            return nil
        }
        guard let date = StatementValues.date(from: cell(layout.dateColumn), calendar: calendar) else {
            return nil
        }
        let text = cell(layout.textColumn).split { $0.isWhitespace }.joined(separator: " ")
        guard !text.isEmpty else { return nil }

        let amount: Decimal
        switch layout.amount {
        case .single(let column):
            // Utgående er negativt. Positive beløp er innskudd og tas ikke med.
            guard let value = StatementValues.amount(from: cell(column)), value < 0 else { return nil }
            amount = -value
        case .outgoingIncoming(let outgoing, _):
            // Fortegnet i ut-kolonnen stoles ikke på, så det er størrelsen som teller.
            guard let value = StatementValues.amount(from: cell(outgoing)), value != 0 else { return nil }
            amount = value < 0 ? -value : value
        }

        let currencyText = cell(layout.currencyColumn).uppercased()
        let currency = CurrencyConverter.supportedCurrencies.contains(currencyText) ? currencyText : "NOK"
        return StatementTransaction(date: date, amount: amount, currencyCode: currency, text: text)
    }

    /// Alle transaksjonene i radene etter overskriftsraden.
    static func transactions(
        in rows: [[String]],
        layout: StatementLayout,
        calendar: Calendar = StatementValues.defaultCalendar
    ) -> [StatementTransaction] {
        rows.dropFirst(layout.headerRowIndex + 1).compactMap {
            transaction(from: $0, layout: layout, calendar: calendar)
        }
    }
}

/// Tolking av datoer og beløp i enkeltfelt.
nonisolated enum StatementValues {
    static var defaultCalendar: Calendar { Calendar(identifier: .gregorian) }

    /// Datoene bankene bruker: `dd.MM.yyyy`, `dd.MM.yy`, `yyyy-MM-dd` og `yyyy/MM/dd`. Et klokkeslett
    /// etter datoen (`2026-10-14 08:12:33`) ignoreres. Dagen settes til kl. 12 i kalenderens tidssone.
    static func date(from text: String, calendar: Calendar = defaultCalendar) -> Date? {
        let token = text
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "T" })
            .first
            .map(String.init) ?? ""
        let parts = token
            .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "/" })
            .map(String.init)
        guard parts.count == 3,
              parts.allSatisfy({ part in !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }

        let year: Int
        let month: Int
        let day: Int
        if parts[0].count == 4 {
            year = numbers[0]
            month = numbers[1]
            day = numbers[2]
        } else if parts[2].count == 4 {
            day = numbers[0]
            month = numbers[1]
            year = numbers[2]
        } else if parts[2].count == 2, token.contains(".") {
            day = numbers[0]
            month = numbers[1]
            year = 2000 + numbers[2]
        } else {
            return nil
        }
        guard (1990...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        // En dag som ikke finnes (31.02.) hadde blitt rullet over til neste måned.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    /// Mønster for valutakoder og «kr» i et beløpsfelt, som «NOK» i «1 299,00 NOK».
    private static let currencyWords: NSRegularExpression = {
        let codes = CurrencyConverter.supportedCurrencies.joined(separator: "|")
        return try! NSRegularExpression(pattern: #"\b(?:kr|"# + codes + #")\b\.?"#, options: [.caseInsensitive])
    }()

    /// Beløpet i et felt, med fortegn (utgående er negativt), eller nil hvis det ikke er et beløp.
    ///
    /// Forstår mellomrom og hardt mellomrom som tusenskille, «NOK» og «kr», og minustegn foran, bak
    /// eller som parentes. Siste skilletegn (komma eller punktum) er desimaltegn. Unntaket er når
    /// det bare finnes ett skilletegn med nøyaktig tre siffer etter og 1–3 siffer foran, f.eks.
    /// «1.299», som er tusen og ikke én, og når samme tegn står flere ganger («1.234.567»).
    static func amount(from text: String) -> Decimal? {
        let range = NSRange(text.startIndex..., in: text)
        let stripped = currencyWords.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        // Det som er igjen må være tall og tegnsetting, ikke tekst som «Saldo».
        guard !stripped.contains(where: { $0.isLetter }) else { return nil }

        var isNegative = false
        var digits = ""
        for character in stripped {
            if character == "-" || character == "\u{2212}" || character == "(" {
                isNegative = true
            } else if character.isASCII && (character.isNumber || character == "," || character == ".") {
                digits.append(character)
            }
        }
        guard digits.contains(where: { $0.isNumber }) else { return nil }

        let separatorIndices = digits.indices.filter { digits[$0] == "," || digits[$0] == "." }
        let plain: String
        if let last = separatorIndices.last {
            let integerPart = String(digits[..<last].filter { $0.isNumber })
            let fraction = String(digits[digits.index(after: last)...])
            let separatorKinds = Set(separatorIndices.map { digits[$0] })
            let isThousands = separatorKinds.count == 1 && (
                separatorIndices.count > 1
                || (fraction.count == 3 && (1...3).contains(integerPart.count) && integerPart != "0")
            )
            if isThousands {
                plain = integerPart + fraction
            } else if fraction.isEmpty {
                plain = integerPart
            } else {
                plain = (integerPart.isEmpty ? "0" : integerPart) + "." + fraction
            }
        } else {
            plain = digits
        }
        guard let value = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return isNegative ? -value : value
    }
}
