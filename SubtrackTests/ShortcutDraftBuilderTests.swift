import AppIntents
import Foundation
import Testing
@testable import Subtrack

@MainActor
struct ShortcutDraftBuilderTests {

    // MARK: - Hjelpere

    private var standard: CatalogPlan { CatalogPlan(label: "Standard", price: 149, currencyCode: "NOK", interval: .monthly) }
    private var premium: CatalogPlan { CatalogPlan(label: "Premium", price: 219, currencyCode: "NOK", interval: .monthly) }
    private var premiumPlus: CatalogPlan { CatalogPlan(label: "Premium Plus", price: 299, currencyCode: "NOK", interval: .monthly) }
    private var yearly: CatalogPlan { CatalogPlan(label: "Årlig", price: 1490, currencyCode: "NOK", interval: .yearly) }

    private func makeService(
        id: String,
        name: String,
        aliases: [String] = [],
        plans: [CatalogPlan] = []
    ) -> CatalogService {
        CatalogService(
            id: id,
            name: name,
            aliases: aliases,
            category: .streaming,
            symbolName: "play.tv",
            colorHex: "#FF453A",
            cancelURL: "https://example.com/avslutt",
            plans: plans
        )
    }

    private func makeCatalog(_ services: [CatalogService]) -> ServiceCatalog {
        ServiceCatalog(pricesCheckedDate: "2026-10-18", services: services)
    }

    /// Katalog med én tjeneste, "Flimmer" (alias "flimmer.no"), med Standard, Premium,
    /// Premium Plus og en årsplan, i den rekkefølgen.
    private var flimmerCatalog: ServiceCatalog {
        makeCatalog([
            makeService(
                id: "flimmer",
                name: "Flimmer",
                aliases: ["flimmer.no"],
                plans: [standard, premium, premiumPlus, yearly]
            )
        ])
    }

    private func draft(
        _ name: String,
        price: Double? = nil,
        interval: BillingInterval? = nil,
        category: SubscriptionCategory? = nil,
        nextRenewalDate: Date? = nil,
        // `nil` i stedet for `.bundled` som standardverdi: standardverdier evalueres utenfor
        // hovedaktøren i test-targeten, mens `ServiceCatalog.bundled` er bundet til den.
        catalog: ServiceCatalog? = nil
    ) -> SubscriptionDraft {
        ShortcutDraftBuilder.makeDraft(
            name: name,
            price: price,
            interval: interval,
            category: category,
            nextRenewalDate: nextRenewalDate,
            catalog: catalog ?? .bundled
        )
    }

    // MARK: - Katalogoppslag

    @Test func exactNameUsesCatalogNameAndFirstPlan() throws {
        let netflix = try #require(ServiceCatalog.bundled.service(id: "netflix"))
        let plan = try #require(netflix.plans.first)

        let result = draft("  nETFLIX ")

        #expect(result.source == .shortcut)
        #expect(result.name == "Netflix")
        #expect(result.catalogServiceID == "netflix")
        #expect(result.price == plan.price)
        #expect(result.currencyCode == plan.currencyCode)
        #expect(result.interval == plan.interval)
        #expect(result.kind == netflix.category)
        #expect(result.symbolName == netflix.symbolName)
        #expect(result.colorHex == netflix.colorHex)
        #expect(result.cancelURLString == netflix.cancelURL)
    }

    @Test(arguments: [
        ("netflix.com", "netflix", "Netflix"),
        ("SpotifySE", "spotify", "Spotify"),
        ("Spotify P", "spotify", "Spotify")
    ])
    func aliasUsesCatalogName(input: String, serviceID: String, expectedName: String) throws {
        let service = try #require(ServiceCatalog.bundled.service(id: serviceID))
        #expect(service.aliases.contains { $0.caseInsensitiveCompare(input) == .orderedSame })

        let result = draft(input)

        #expect(result.name == expectedName)
        #expect(result.catalogServiceID == serviceID)
        #expect(result.price == service.plans.first?.price)
    }

    @Test func exactMatchIgnoresDiacritics() {
        let catalog = makeCatalog([makeService(id: "kino", name: "Kino Ålesund", plans: [standard])])

        let result = draft("kino alesund", catalog: catalog)

        #expect(result.name == "Kino Ålesund")
        #expect(result.catalogServiceID == "kino")
    }

    @Test func unknownNameIsKeptWithoutCatalogFields() {
        let result = draft("  Hagelaget Knerten  ")

        #expect(result.source == .shortcut)
        #expect(result.name == "Hagelaget Knerten")
        #expect(result.catalogServiceID == nil)
        #expect(result.price == nil)
        #expect(result.currencyCode == nil)
        #expect(result.interval == nil)
        #expect(result.kind == nil)
        #expect(result.symbolName == nil)
        #expect(result.colorHex == nil)
        #expect(result.cancelURLString == nil)
        #expect(result.note == nil)
    }

    @Test func whitespaceOnlyNameGivesNoName() {
        let result = draft(" \n\t ", price: 99)

        #expect(result.name == nil)
        #expect(result.catalogServiceID == nil)
        #expect(result.price == 99)
    }

    // MARK: - Sikkert treff i et lengre navn

    @Test func confidentMatchKeepsUserNameAndUsesNamedPlan() {
        let result = draft("Flimmer Premium", catalog: flimmerCatalog)

        #expect(result.name == "Flimmer Premium")
        #expect(result.catalogServiceID == "flimmer")
        #expect(result.kind == .streaming)
        #expect(result.symbolName == "play.tv")
        #expect(result.cancelURLString == "https://example.com/avslutt")
        #expect(result.price == 219)
        #expect(result.interval == .monthly)
    }

    @Test func longestPlanNameWins() {
        let result = draft("Flimmer Premium Plus", catalog: flimmerCatalog)

        #expect(result.price == 299)
    }

    @Test func planNameMatchesWithoutDiacritics() {
        let result = draft("flimmer arlig", catalog: flimmerCatalog)

        #expect(result.price == 1490)
        #expect(result.interval == .yearly)
    }

    @Test func confidentMatchWithoutPlanNameLeavesPriceEmpty() {
        let result = draft("Flimmer via mobilabonnementet", catalog: flimmerCatalog)

        #expect(result.name == "Flimmer via mobilabonnementet")
        #expect(result.catalogServiceID == "flimmer")
        #expect(result.symbolName == "play.tv")
        #expect(result.price == nil)
        #expect(result.currencyCode == nil)
        #expect(result.interval == nil)
    }

    @Test func shortAliasInLongerNameIsIgnored() {
        // "max" er under 5 tegn, så treffet er `.medium` og brukes ikke.
        let catalog = makeCatalog([makeService(id: "max", name: "Max", aliases: ["max"], plans: [standard])])

        let result = draft("Max Hjemmekino", catalog: catalog)

        #expect(result.name == "Max Hjemmekino")
        #expect(result.catalogServiceID == nil)
        #expect(result.price == nil)
        #expect(result.symbolName == nil)
    }

    // MARK: - Parametere vinner

    @Test func parametersOverrideCatalog() {
        let result = draft("Flimmer", price: 199, category: .annet, catalog: flimmerCatalog)

        #expect(result.name == "Flimmer")
        #expect(result.price == 199)
        #expect(result.kind == .annet)
        // Planen gir fortsatt valuta og intervall.
        #expect(result.currencyCode == "NOK")
        #expect(result.interval == .monthly)
    }

    @Test func intervalPicksPlanWithSameInterval() {
        let result = draft("Flimmer", interval: .yearly, catalog: flimmerCatalog)

        #expect(result.interval == .yearly)
        #expect(result.price == 1490)
        #expect(result.currencyCode == "NOK")
    }

    @Test func intervalWithoutMatchingPlanLeavesPriceEmpty() {
        let result = draft("Flimmer", interval: .weekly, catalog: flimmerCatalog)

        #expect(result.catalogServiceID == "flimmer")
        #expect(result.interval == .weekly)
        #expect(result.price == nil)
        #expect(result.currencyCode == nil)
    }

    @Test func priceAndIntervalOverrideTogether() {
        let result = draft("Flimmer", price: 1200, interval: .yearly, catalog: flimmerCatalog)

        #expect(result.price == 1200)
        #expect(result.interval == .yearly)
        #expect(result.currencyCode == "NOK")
    }

    // MARK: - Pris og dato

    @Test func priceHasNoBinaryNoise() {
        let result = draft("Hagelaget Knerten", price: 149.9)

        #expect(result.price == Decimal(string: "149.9"))
    }

    @Test(arguments: [0.0, -149.0, Double.nan, Double.infinity, -Double.infinity])
    func invalidPriceIsIgnored(price: Double) {
        #expect(draft("Hagelaget Knerten", price: price).price == nil)
        // Med katalogtreff beholdes planens pris.
        #expect(draft("Flimmer", price: price, catalog: flimmerCatalog).price == 149)
    }

    @Test func nextRenewalDatePassesThrough() {
        let date = Date(timeIntervalSince1970: 1_800_000_123.456)

        #expect(draft("Hagelaget Knerten", nextRenewalDate: date).nextRenewalDate == date)
        #expect(draft("Flimmer", nextRenewalDate: date, catalog: flimmerCatalog).nextRenewalDate == date)
        #expect(draft("Flimmer", catalog: flimmerCatalog).nextRenewalDate == nil)
    }

    // MARK: - Valg i snarveien

    @Test func everyIntervalOptionMapsToModel() {
        for option in ShortcutIntervalOption.allCases {
            #expect(option.value.rawValue == option.rawValue)
            #expect(ShortcutIntervalOption.caseDisplayRepresentations[option]?.title.key == option.value.displayName)
        }
    }

    @Test func everyIntervalHasOption() {
        for interval in BillingInterval.allCases {
            #expect(ShortcutIntervalOption(rawValue: interval.rawValue)?.value == interval)
        }
        #expect(ShortcutIntervalOption.allCases.count == BillingInterval.allCases.count)
    }

    @Test func everyCategoryOptionMapsToModel() {
        for option in ShortcutCategoryOption.allCases {
            #expect(option.value.rawValue == option.rawValue)
            #expect(ShortcutCategoryOption.caseDisplayRepresentations[option]?.title.key == option.value.displayName)
        }
    }

    @Test func everyCategoryHasOption() {
        for category in SubscriptionCategory.allCases {
            #expect(ShortcutCategoryOption(rawValue: category.rawValue)?.value == category)
        }
        #expect(ShortcutCategoryOption.allCases.count == SubscriptionCategory.allCases.count)
    }
}
