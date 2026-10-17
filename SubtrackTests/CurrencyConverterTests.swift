import Foundation
import Testing
@testable import Subtrack

@MainActor
struct CurrencyConverterTests {

    private let rates = ExchangeRates(
        base: "EUR",
        rates: ["NOK": 10, "USD": 2, "SEK": 11],
        rateDate: .now,
        fetchedAt: .now
    )

    @Test func sameCurrencyNeedsNoRates() {
        let result = CurrencyConverter.convert(149, from: "NOK", to: "NOK", using: nil)
        #expect(result == 149)
    }

    @Test func convertsFromBaseCurrency() {
        let result = CurrencyConverter.convert(5, from: "EUR", to: "NOK", using: rates)
        #expect(result == 50)
    }

    @Test func convertsBetweenNonBaseCurrencies() {
        // 10 USD = 5 EUR = 50 NOK
        let result = CurrencyConverter.convert(10, from: "USD", to: "NOK", using: rates)
        #expect(result == 50)
    }

    @Test func missingRateReturnsNil() {
        let result = CurrencyConverter.convert(10, from: "GBP", to: "NOK", using: rates)
        #expect(result == nil)
    }

    @Test func totalSumsConvertibleAndCountsExcluded() {
        let total = CurrencyConverter.total(
            of: [(100, "NOK"), (10, "USD"), (7, "GBP")],
            in: "NOK",
            using: rates
        )
        #expect(total == ConvertedTotal(amount: 150, excludedCount: 1))
    }

    @Test func totalWithoutRatesOnlyIncludesTargetCurrency() {
        let total = CurrencyConverter.total(
            of: [(100, "NOK"), (10, "USD")],
            in: "NOK",
            using: nil
        )
        #expect(total == ConvertedTotal(amount: 100, excludedCount: 1))
    }
}
