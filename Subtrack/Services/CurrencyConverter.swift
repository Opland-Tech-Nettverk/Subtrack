import Foundation

/// Valutakurser der `rates[kode]` er hvor mange enheter av valutaen 1 `base` tilsvarer.
struct ExchangeRates: Codable, Equatable {
    let base: String
    let rates: [String: Decimal]
    /// Datoen kursene gjelder for (ECB publiserer én gang per virkedag).
    let rateDate: Date
    /// Når appen sist hentet kursene, brukt til å avgjøre om de bør hentes på nytt.
    let fetchedAt: Date

    func rate(for currencyCode: String) -> Decimal? {
        currencyCode == base ? 1 : rates[currencyCode]
    }
}

/// Resultatet av å summere beløp i ulike valutaer. Beløp som ikke kunne regnes om
/// (manglende kurs) er utelatt fra `amount` og telles i `excludedCount`.
struct ConvertedTotal: Equatable {
    let amount: Decimal
    let excludedCount: Int
}

/// Rene, testbare funksjoner for valutaomregning.
enum CurrencyConverter {
    /// Valutaene Frankfurter-API-et (ECB-kurser) støtter.
    static let supportedCurrencies = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD",
        "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK",
        "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR"
    ]

    /// Regner om via kursenes basevaluta: beløp / kurs(fra) * kurs(til).
    /// Returnerer `nil` hvis en av kursene mangler.
    static func convert(
        _ amount: Decimal,
        from sourceCurrency: String,
        to targetCurrency: String,
        using rates: ExchangeRates?
    ) -> Decimal? {
        if sourceCurrency == targetCurrency { return amount }
        guard
            let rates,
            let sourceRate = rates.rate(for: sourceCurrency),
            let targetRate = rates.rate(for: targetCurrency),
            sourceRate != 0
        else { return nil }
        return amount / sourceRate * targetRate
    }

    static func total(
        of amounts: [(amount: Decimal, currencyCode: String)],
        in targetCurrency: String,
        using rates: ExchangeRates?
    ) -> ConvertedTotal {
        var sum = Decimal(0)
        var excluded = 0
        for item in amounts {
            if let converted = convert(item.amount, from: item.currencyCode, to: targetCurrency, using: rates) {
                sum += converted
            } else {
                excluded += 1
            }
        }
        return ConvertedTotal(amount: sum, excludedCount: excluded)
    }

    /// Visningsnavn for en valutakode på brukerens språk, f.eks. "norske kroner".
    static func displayName(for currencyCode: String) -> String {
        Locale.current.localizedString(forCurrencyCode: currencyCode) ?? currencyCode
    }
}
