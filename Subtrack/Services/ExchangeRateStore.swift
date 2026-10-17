import Foundation
import Observation

/// Henter valutakurser fra Frankfurter (ECB-referansekurser, gratis og uten nøkkel)
/// og cacher dem lokalt, slik at omregning fungerer uten nett med siste kjente kurs.
@Observable
final class ExchangeRateStore {
    private(set) var rates: ExchangeRates?

    private static let cacheKey = "exchangeRates"
    private static let refreshInterval: TimeInterval = 60 * 60 * 12
    // EUR som base fordi det er ECBs egen base; kryss-kurser regnes lokalt.
    private static let endpoint = URL(string: "https://api.frankfurter.dev/v1/latest?base=EUR")!

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            rates = try? JSONDecoder().decode(ExchangeRates.self, from: data)
        }
    }

    /// Henter nye kurser hvis de cachede er eldre enn `refreshInterval`.
    /// Feil (f.eks. ingen nett) ignoreres stille - da brukes de forrige kursene videre.
    func refreshIfNeeded() async {
        if let rates, Date.now.timeIntervalSince(rates.fetchedAt) < Self.refreshInterval {
            return
        }

        guard
            let (data, response) = try? await URLSession.shared.data(from: Self.endpoint),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let decoded = try? JSONDecoder().decode(FrankfurterResponse.self, from: data),
            let rateDate = Self.rateDateFormatter.date(from: decoded.date)
        else { return }

        let fresh = ExchangeRates(base: decoded.base, rates: decoded.rates, rateDate: rateDate, fetchedAt: .now)
        rates = fresh
        if let encoded = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
        }
    }

    private struct FrankfurterResponse: Decodable {
        let base: String
        let date: String
        let rates: [String: Decimal]
    }

    private static let rateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
