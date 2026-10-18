import Foundation
import Testing
@testable import Subtrack

@MainActor
struct ServiceCatalogTests {

    // MARK: - Hjelpere

    private func makeService(
        id: String,
        name: String,
        aliases: [String] = [],
        category: SubscriptionCategory = .streaming,
        plans: [CatalogPlan] = []
    ) -> CatalogService {
        CatalogService(
            id: id,
            name: name,
            aliases: aliases,
            category: category,
            symbolName: "play.tv",
            colorHex: "#FF453A",
            cancelURL: nil,
            plans: plans
        )
    }

    private func makeCatalog(_ services: [CatalogService]) -> ServiceCatalog {
        ServiceCatalog(pricesCheckedDate: "2026-10-18", services: services)
    }

    private func json(price: String = "\"149.90\"", category: String = "streaming") -> Data {
        Data("""
        {
          "pricesCheckedDate": "2026-10-18",
          "services": [
            {
              "id": "netflix",
              "name": "Netflix",
              "aliases": ["netflix.com", "netflix"],
              "category": "\(category)",
              "symbolName": "play.tv",
              "colorHex": "#FF453A",
              "cancelURL": "https://www.netflix.com/cancelplan",
              "plans": [
                { "label": "Standard", "price": \(price), "currencyCode": "NOK", "interval": "monthly" }
              ]
            },
            {
              "id": "patreon",
              "name": "Patreon",
              "aliases": ["patreon"],
              "category": "annet",
              "symbolName": "heart",
              "colorHex": "#FF9F0A",
              "plans": []
            }
          ]
        }
        """.utf8)
    }

    // MARK: - Lasting

    @Test func decodesCatalog() throws {
        let catalog = try ServiceCatalog.load(from: json())
        #expect(catalog.pricesCheckedDate == "2026-10-18")
        #expect(catalog.services.map(\.id) == ["netflix", "patreon"])

        let netflix = try #require(catalog.service(id: "netflix"))
        #expect(netflix.name == "Netflix")
        #expect(netflix.aliases == ["netflix.com", "netflix"])
        #expect(netflix.category == .streaming)
        #expect(netflix.cancelURL == "https://www.netflix.com/cancelplan")
        #expect(netflix.plans == [
            CatalogPlan(label: "Standard", price: Decimal(string: "149.90")!, currencyCode: "NOK", interval: .monthly)
        ])

        let patreon = try #require(catalog.service(id: "patreon"))
        #expect(patreon.cancelURL == nil)
        #expect(patreon.plans.isEmpty)
        #expect(catalog.service(id: "finnes-ikke") == nil)
    }

    @Test func decodesPriceWithoutRounding() throws {
        let catalog = try ServiceCatalog.load(from: json(price: "\"149.90\""))
        let price = try #require(catalog.services.first?.plans.first?.price)
        #expect(price == Decimal(string: "149.90")!)
        #expect(price * 3 == Decimal(string: "449.70")!)
    }

    @Test(arguments: ["\"abc\"", "\"149,90\"", "\"12abc\"", "\"-5\"", "\"\"", "149.90"])
    func rejectsInvalidPrice(price: String) {
        #expect(throws: DecodingError.self) {
            try ServiceCatalog.load(from: json(price: price))
        }
    }

    @Test func rejectsUnknownCategory() {
        #expect(throws: DecodingError.self) {
            try ServiceCatalog.load(from: json(category: "ukjent"))
        }
    }

    @Test func parsesPricesCheckedDate() throws {
        let date = try #require(makeCatalog([]).pricesCheckedDateValue)
        let components = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        #expect(components.year == 2026)
        #expect(components.month == 10)
        #expect(components.day == 18)

        #expect(ServiceCatalog(pricesCheckedDate: "18.10.2026", services: []).pricesCheckedDateValue == nil)
        #expect(ServiceCatalog(pricesCheckedDate: "", services: []).pricesCheckedDateValue == nil)
    }

    // MARK: - Utkast

    @Test func draftUsesFirstPlanByDefault() {
        let standard = CatalogPlan(label: "Standard", price: Decimal(string: "149.00")!, currencyCode: "NOK", interval: .monthly)
        let premium = CatalogPlan(label: "Premium", price: Decimal(string: "1990.00")!, currencyCode: "NOK", interval: .yearly)
        let netflix = CatalogService(
            id: "netflix",
            name: "Netflix",
            aliases: ["netflix"],
            category: .streaming,
            symbolName: "play.tv",
            colorHex: "#FF453A",
            cancelURL: "https://www.netflix.com/cancelplan",
            plans: [standard, premium]
        )

        let draft = netflix.draft()
        #expect(draft.source == .catalog)
        #expect(draft.catalogServiceID == "netflix")
        #expect(draft.name == "Netflix")
        #expect(draft.price == Decimal(string: "149.00")!)
        #expect(draft.currencyCode == "NOK")
        #expect(draft.interval == .monthly)
        #expect(draft.kind == .streaming)
        #expect(draft.symbolName == "play.tv")
        #expect(draft.colorHex == "#FF453A")
        #expect(draft.cancelURLString == "https://www.netflix.com/cancelplan")

        let premiumDraft = netflix.draft(plan: premium)
        #expect(premiumDraft.price == Decimal(string: "1990.00")!)
        #expect(premiumDraft.interval == .yearly)
    }

    @Test func draftWithoutPlansLeavesPriceEmpty() {
        let draft = makeService(id: "patreon", name: "Patreon", category: .annet).draft()
        #expect(draft.name == "Patreon")
        #expect(draft.kind == .annet)
        #expect(draft.price == nil)
        #expect(draft.currencyCode == nil)
        #expect(draft.interval == nil)
        #expect(draft.cancelURLString == nil)
    }

    // MARK: - Søk

    @Test(arguments: ["", " ", "n", "  n  "])
    func searchNeedsAtLeastTwoCharacters(query: String) {
        let catalog = makeCatalog([makeService(id: "netflix", name: "Netflix")])
        #expect(catalog.search(query).isEmpty)
    }

    @Test(arguments: ["netf", "NETF", "  Netf ", "apen", "ÅPEN", "åpe"])
    func searchIgnoresCaseAndDiacritics(query: String) {
        let catalog = makeCatalog([
            makeService(id: "netflix", name: "Netflix"),
            makeService(id: "apen", name: "Åpen Kanal", aliases: ["apen kanal"])
        ])
        #expect(catalog.search(query).count == 1)
    }

    @Test func searchFindsAlias() {
        let catalog = makeCatalog([makeService(id: "max", name: "Max", aliases: ["hbo max", "hbomax"])])
        #expect(catalog.search("hbo").map(\.id) == ["max"])
        #expect(catalog.search("xyz").isEmpty)
    }

    @Test func searchOrdersNamePrefixThenWordPrefixThenAlias() {
        let catalog = makeCatalog([
            makeService(id: "alias", name: "Kanal", aliases: ["display pro"]),
            makeService(id: "word", name: "TV 2 Play"),
            makeService(id: "prefix", name: "Playstation Plus"),
            makeService(id: "other", name: "Netflix")
        ])
        #expect(catalog.search("pla").map(\.id) == ["prefix", "word", "alias"])
    }

    @Test func searchKeepsCatalogOrderWithinSameRank() {
        let catalog = makeCatalog([
            makeService(id: "b", name: "Spotify"),
            makeService(id: "a", name: "Sport Plus")
        ])
        #expect(catalog.search("sp").map(\.id) == ["b", "a"])
    }

    @Test func searchRespectsLimit() {
        let catalog = makeCatalog((1...8).map { makeService(id: "tjeneste-\($0)", name: "Tjeneste \($0)") })
        #expect(catalog.search("tjen").count == 5)
        #expect(catalog.search("tjen", limit: 2).map(\.id) == ["tjeneste-1", "tjeneste-2"])
        #expect(catalog.search("tjen", limit: 0).isEmpty)
    }

    // MARK: - Rensing av mottakertekst

    @Test(arguments: [
        ("*1234 15.10 NOK 149.00 NETFLIX.COM Kurs: 1.0000", "netflix com"),
        ("*5678 14.08 NOK 364.80 Max Kurs: 1.0000", "max"),
        ("Visa 100591 Usd 25,00 Spotify P2B3C Valutakurs: 9,8431", "spotify p2b3c"),
        ("Varekjøp SATS NORGE Dato 12.09 kl. 10.47", "sats norge"),
        ("PAYPAL *DISNEYPLUS", "disneyplus"),
        ("Vipps*TV 2 Play", "tv 2 play"),
        ("  Café   Ålesund!! ", "cafe alesund"),
        ("Disney+", "disney"),
        ("", "")
    ])
    func normalizesMerchantText(input: String, expected: String) {
        #expect(MerchantText.normalized(input) == expected)
    }

    // MARK: - Gjenkjenning

    @Test func matchFindsServiceInBankText() throws {
        let catalog = makeCatalog([
            makeService(id: "spotify", name: "Spotify", aliases: ["spotify"]),
            makeService(id: "netflix", name: "Netflix", aliases: ["netflix.com", "netflix"])
        ])
        let match = try #require(catalog.match(merchantText: "*1234 15.10 NOK 149.00 NETFLIX.COM Kurs: 1.0000"))
        #expect(match.service.id == "netflix")
        #expect(match.confidence == .high)
    }

    @Test func matchPrefersLongestAlias() throws {
        let catalog = makeCatalog([
            makeService(id: "disney", name: "Disney Kanal", aliases: ["disney"]),
            makeService(id: "disney-plus", name: "Disney+", aliases: ["disney plus", "disneyplus"])
        ])
        let match = try #require(catalog.match(merchantText: "PAYPAL *DISNEY PLUS"))
        #expect(match.service.id == "disney-plus")
        // Begge har "disney" (navnet "Disney+" renses til "disney"), så den første i katalogen vinner.
        #expect(catalog.match(merchantText: "Disney butikk")?.service.id == "disney")
    }

    @Test func matchRequiresWholeWords() {
        let catalog = makeCatalog([makeService(id: "max", name: "Max", aliases: ["max"])])
        #expect(catalog.match(merchantText: "Varekjøp MAXBO OSLO Dato 12.09") == nil)
        #expect(catalog.match(merchantText: "SUPERMAX AS") == nil)
        #expect(catalog.match(merchantText: "*1234 14.08 NOK 149.00 MAX Kurs: 1.0000")?.service.id == "max")
    }

    @Test func matchConfidenceDependsOnAliasLength() {
        let catalog = makeCatalog([
            makeService(id: "max", name: "Max Streaming", aliases: ["max"]),
            makeService(id: "xbox", name: "Xbox Game Pass", aliases: ["xbox"]),
            makeService(id: "tidal", name: "Tidal Musikk", aliases: ["tidal"])
        ])
        #expect(catalog.match(merchantText: "MAX")?.confidence == .medium)
        #expect(catalog.match(merchantText: "XBOX")?.confidence == .medium)
        #expect(catalog.match(merchantText: "TIDAL")?.confidence == .high)
    }

    @Test func matchUsesServiceName() {
        let catalog = makeCatalog([makeService(id: "storytel", name: "Storytel")])
        #expect(catalog.match(merchantText: "Visa 100591 Storytel AB")?.service.id == "storytel")
    }

    @Test func matchIgnoresShortNames() {
        let catalog = makeCatalog([makeService(id: "dn", name: "DN", aliases: ["dagens naeringsliv"])])
        #expect(catalog.match(merchantText: "DN BANK OVERFORING") == nil)
        #expect(catalog.match(merchantText: "DAGENS NAERINGSLIV AS")?.service.id == "dn")
    }

    @Test(arguments: ["REMA 1000 OSLO", "", "   ", "*1234 15.10 NOK 149.00 Kurs: 1.0000"])
    func matchReturnsNilWithoutHit(text: String) {
        let catalog = makeCatalog([
            makeService(id: "netflix", name: "Netflix", aliases: ["netflix.com"]),
            makeService(id: "max", name: "Max", aliases: ["max"])
        ])
        #expect(catalog.match(merchantText: text) == nil)
    }

    // MARK: - Katalogen som følger med appen

    @Test func bundledCatalogIsValid() throws {
        let catalog = ServiceCatalog.bundled
        #expect(!catalog.services.isEmpty)
        #expect(catalog.pricesCheckedDateValue != nil)

        let ids = catalog.services.map(\.id)
        #expect(Set(ids).count == ids.count, "Dupliserte ID-er")

        let icons = Set(SubscriptionAppearance.icons.map(\.symbolName))
        let colors = Set(SubscriptionAppearance.colors.map(\.hex))
        let currencies = Set(CurrencyConverter.supportedCurrencies)

        for service in catalog.services {
            #expect(
                service.id.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression) != nil,
                "Ugyldig ID: \(service.id)"
            )
            #expect(!service.name.trimmingCharacters(in: .whitespaces).isEmpty, "Tomt navn: \(service.id)")
            #expect(icons.contains(service.symbolName), "Ukjent ikon for \(service.id): \(service.symbolName)")
            #expect(colors.contains(service.colorHex), "Ukjent farge for \(service.id): \(service.colorHex)")
            if let cancelURL = service.cancelURL {
                #expect(CancelLink.url(from: cancelURL) != nil, "Ugyldig avslutningslenke for \(service.id)")
            }

            let labels = service.plans.map(\.label)
            #expect(Set(labels).count == labels.count, "Dupliserte planer for \(service.id)")
            for plan in service.plans {
                #expect(plan.price > 0, "Pris må være over 0: \(service.id) \(plan.label)")
                #expect(currencies.contains(plan.currencyCode), "Ukjent valuta for \(service.id): \(plan.currencyCode)")
            }

            for alias in service.aliases {
                #expect(
                    MerchantText.normalized(alias).count >= 3,
                    "For kort alias for \(service.id): \(alias)"
                )
            }
        }
    }

    @Test func bundledCatalogHasNoSharedAliases() {
        var owner: [String: String] = [:]
        for service in ServiceCatalog.bundled.services {
            let keys = Set(([service.name] + service.aliases).map(MerchantText.normalized))
            for key in keys {
                if let other = owner[key] {
                    Issue.record("\"\(key)\" brukes av både \(other) og \(service.id)")
                } else {
                    owner[key] = service.id
                }
            }
        }
    }

    @Test(arguments: ["netflix", "spotify"])
    func bundledCatalogContainsRequiredServices(id: String) throws {
        let service = try #require(ServiceCatalog.bundled.service(id: id))
        #expect(!service.plans.isEmpty)
    }

    @Test func bundledServicesMatchTheirOwnNames() {
        let catalog = ServiceCatalog.bundled
        for service in catalog.services {
            // Navn under 3 tegn ("DN", "VG+") brukes ikke til gjenkjenning; de har egne alias.
            guard MerchantText.normalized(service.name).count >= 3 else { continue }
            #expect(
                catalog.match(merchantText: service.name)?.service.id == service.id,
                "\(service.name) gjenkjennes ikke som \(service.id)"
            )
        }
    }
}
