import Foundation
@testable import Subtrack

/// Felles hjelpere for testene av kontoutskrift-importen.
@MainActor
enum BankStatementTestSupport {
    private final class BundleToken {}

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    /// Dagen kl. 12 i Oslo, slik transaksjonene har den.
    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    /// «I dag» i testene, etter siste trekk i testfilene (14. oktober 2026).
    static var now: Date { day(2026, 10, 20) }

    /// Bytene i en testfil fra `SubtrackTests/Fixtures/`.
    static func fixtureData(_ fileName: String) throws -> Data {
        let name = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension
        let bundle = Bundle(for: BundleToken.self)
        // Mappen kan være flatet ut i testpakken, så begge steder prøves.
        let url = bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: fileExtension)
        guard let url else {
            throw FixtureError.missing(fileName)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error {
        case missing(String)
    }

    private static func service(
        id: String,
        name: String,
        aliases: [String],
        category: SubscriptionCategory,
        plans: [CatalogPlan]
    ) -> CatalogService {
        CatalogService(
            id: id,
            name: name,
            aliases: aliases,
            category: category,
            symbolName: "play.tv",
            colorHex: "#FF453A",
            cancelURL: "https://example.com/avslutt",
            plans: plans
        )
    }

    private static func plan(_ label: String, _ price: Decimal, _ currency: String = "NOK", _ interval: BillingInterval = .monthly) -> CatalogPlan {
        CatalogPlan(label: label, price: price, currencyCode: currency, interval: interval)
    }

    /// En liten katalog med tjenestene testfilene bruker, og noen til for spesialtilfeller.
    static var catalog: ServiceCatalog {
        ServiceCatalog(pricesCheckedDate: "2026-10-18", services: [
            service(id: "netflix", name: "Netflix", aliases: ["netflix", "netflix.com"], category: .streaming,
                    plans: [plan("Standard", 149), plan("Premium", 219)]),
            service(id: "spotify", name: "Spotify", aliases: ["spotify", "spotify.com"], category: .musikk,
                    plans: [plan("Individual", 139)]),
            service(id: "claude", name: "Claude", aliases: ["claude.ai", "anthropic"], category: .ai,
                    plans: [plan("Pro", 20, "USD"), plan("Pro (årlig)", 200, "USD", .yearly)]),
            service(id: "microsoft-365", name: "Microsoft 365", aliases: ["microsoft 365", "microsoft365"], category: .programvare,
                    plans: [plan("Personal (årlig)", 1189, "NOK", .yearly)]),
            service(id: "hbo-max", name: "Max", aliases: ["max", "hbo max"], category: .streaming,
                    plans: [plan("Standard", 149)]),
            service(id: "patreon", name: "Patreon", aliases: ["patreon"], category: .annet, plans: [])
        ])
    }

    /// Transaksjon med enkle standardverdier.
    static func transaction(
        _ date: Date,
        _ amount: Decimal,
        _ text: String,
        currency: String = "NOK"
    ) -> StatementTransaction {
        StatementTransaction(date: date, amount: amount, currencyCode: currency, text: text)
    }

    /// Like mange trekk som `amounts` har, en gang i måneden fra og med `start`.
    static func monthly(
        _ text: String,
        amounts: [Decimal],
        from start: Date,
        currency: String = "NOK"
    ) -> [StatementTransaction] {
        amounts.enumerated().map { offset, amount in
            let date = calendar.date(byAdding: .month, value: offset, to: start)!
            return transaction(date, amount, text, currency: currency)
        }
    }

    static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
