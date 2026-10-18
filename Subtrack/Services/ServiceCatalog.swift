import Foundation

/// En fast prisplan for en tjeneste i katalogen, f.eks. «Standard 149 kr/mnd».
struct CatalogPlan: Decodable, Equatable, Identifiable {
    let label: String
    /// Leses fra en tekst i JSON ("149.00", punktum som desimaltegn) så beløpet ikke rundes av via `Double`.
    let price: Decimal
    let currencyCode: String
    let interval: BillingInterval
    var id: String { label }
}

// `init(from:)` står i en utvidelse så den automatiske medlemsvise initialisereren beholdes.
extension CatalogPlan {
    private enum CodingKeys: String, CodingKey {
        case label, price, currencyCode, interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let priceText = try container.decode(String.self, forKey: .price)
        // `Decimal(string:)` godtar tekst som bare starter med et tall ("12abc"), så formatet sjekkes først.
        guard
            priceText.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil,
            let price = Decimal(string: priceText, locale: Locale(identifier: "en_US_POSIX"))
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .price,
                in: container,
                debugDescription: "Ugyldig pris \"\(priceText)\". Forventet f.eks. \"149.00\"."
            )
        }
        self.init(
            label: try container.decode(String.self, forKey: .label),
            price: price,
            currencyCode: try container.decode(String.self, forKey: .currencyCode),
            interval: try container.decode(BillingInterval.self, forKey: .interval)
        )
    }
}

/// En kjent tjeneste med navn, utseende, avslutningslenke og vanlige priser.
struct CatalogService: Decodable, Equatable, Identifiable {
    /// Fast ID med små bokstaver, f.eks. "netflix" eller "tv2-play".
    let id: String
    let name: String
    /// Tekst slik tjenesten står i kontoutskrifter og kvitteringer, f.eks. "netflix.com".
    let aliases: [String]
    let category: SubscriptionCategory
    let symbolName: String
    let colorHex: String
    let cancelURL: String?
    /// Kan være tom for tjenester uten fast pris.
    let plans: [CatalogPlan]

    /// Utkast for skjemaet. `plan == nil` bruker første plan, om noen.
    func draft(plan: CatalogPlan? = nil) -> SubscriptionDraft {
        let chosenPlan = plan ?? plans.first
        var draft = SubscriptionDraft(source: .catalog)
        draft.name = name
        draft.price = chosenPlan?.price
        draft.currencyCode = chosenPlan?.currencyCode
        draft.interval = chosenPlan?.interval
        draft.kind = category
        draft.symbolName = symbolName
        draft.colorHex = colorHex
        draft.cancelURLString = cancelURL
        draft.catalogServiceID = id
        return draft
    }
}

/// Et treff i katalogen for en tekst fra kontoutskrift eller kvittering.
struct CatalogMatch: Equatable {
    /// `.high` når aliaset som traff er langt nok til at det neppe er tilfeldig (minst 5 tegn).
    enum Confidence: Equatable { case high, medium }
    let service: CatalogService
    let confidence: Confidence
}

/// Katalogen over kjente tjenester. Rene funksjoner for søk og gjenkjenning.
struct ServiceCatalog: Decodable, Equatable {
    /// Datoen prisene sist ble sjekket, "yyyy-MM-dd".
    let pricesCheckedDate: String
    let services: [CatalogService]

    /// Ferdig renset tekst per tjeneste, regnet ut én gang. Samme rekkefølge som `services`.
    private let index: [IndexedService]
    /// `pricesCheckedDate` tolket én gang, så skjemaet ikke lager en `DateFormatter` per visning.
    private let checkedDate: Date?

    init(pricesCheckedDate: String, services: [CatalogService]) {
        self.pricesCheckedDate = pricesCheckedDate
        self.services = services
        self.index = services.map(IndexedService.init)
        self.checkedDate = Self.parseCheckedDate(pricesCheckedDate)
    }

    private enum CodingKeys: String, CodingKey {
        case pricesCheckedDate, services
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pricesCheckedDate: try container.decode(String.self, forKey: .pricesCheckedDate),
            services: try container.decode([CatalogService].self, forKey: .services)
        )
    }

    /// Katalogen som følger med appen (`ServiceCatalog.json` i app-bunten). Lastes én gang.
    /// Tom katalog (og assertionFailure i debug) hvis filen mangler eller ikke kan leses.
    static let bundled: ServiceCatalog = {
        let empty = ServiceCatalog(pricesCheckedDate: "", services: [])
        guard let url = Bundle.main.url(forResource: "ServiceCatalog", withExtension: "json") else {
            assertionFailure("ServiceCatalog.json mangler i app-bunten.")
            return empty
        }
        do {
            return try ServiceCatalog.load(from: Data(contentsOf: url))
        } catch {
            assertionFailure("Kunne ikke lese ServiceCatalog.json: \(error)")
            return empty
        }
    }()

    static func load(from data: Data) throws -> ServiceCatalog {
        try JSONDecoder().decode(ServiceCatalog.self, from: data)
    }

    /// Datoen prisene sist ble sjekket, eller nil om teksten ikke kan tolkes.
    var pricesCheckedDateValue: Date? { checkedDate }

    private static func parseCheckedDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        // Lokal tidssone så datoen vises som samme dag som i filen.
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// Søk på navn og alias. Uavhengig av store/små bokstaver og diakritiske tegn.
    /// Tomt resultat for søk under 2 tegn (etter trimming). Sortering: navnet starter med søket,
    /// deretter et ord i navnet starter med søket, deretter alias som inneholder søket.
    /// Innenfor samme gruppe beholdes rekkefølgen i katalogen.
    func search(_ query: String, limit: Int = 5) -> [CatalogService] {
        let key = Self.searchKey(query)
        guard key.count >= 2, limit > 0 else { return [] }

        var ranked: [(rank: Int, position: Int)] = []
        for (position, entry) in index.enumerated() {
            let rank: Int
            if entry.searchName.hasPrefix(key) {
                rank = 0
            } else if entry.nameWords.contains(where: { $0.hasPrefix(key) }) {
                rank = 1
            } else if entry.searchName.contains(key) || entry.searchAliases.contains(where: { $0.contains(key) }) {
                rank = 2
            } else {
                continue
            }
            ranked.append((rank: rank, position: position))
        }

        return ranked
            .sorted { ($0.rank, $0.position) < ($1.rank, $1.position) }
            .prefix(limit)
            .map { services[$0.position] }
    }

    func service(id: String) -> CatalogService? {
        services.first { $0.id == id }
    }

    /// Finner tjenesten i en tekst fra kontoutskrift eller kvittering, f.eks.
    /// "*1234 15.10 NOK 149.00 NETFLIX.COM Kurs: 1.0000". nil hvis ingen alias passer.
    ///
    /// Både teksten og aliasene (og navnet) renses med `MerchantText.normalized`. Et alias treffer
    /// bare som hele ord, så "max" treffer ikke "maxbo". Lengste alias vinner; ved likt lengde
    /// vinner tjenesten som står først i katalogen.
    func match(merchantText: String) -> CatalogMatch? {
        let normalized = MerchantText.normalized(merchantText)
        guard !normalized.isEmpty else { return nil }
        let padded = " \(normalized) "

        var best: (position: Int, key: String)?
        for (position, entry) in index.enumerated() {
            // Nøklene er sortert med lengste først, så første treff er tjenestens beste.
            guard let key = entry.matchKeys.first(where: { padded.contains(" \($0) ") }) else { continue }
            if key.count > (best?.key.count ?? 0) {
                best = (position: position, key: key)
            }
        }

        guard let best else { return nil }
        return CatalogMatch(
            service: services[best.position],
            confidence: best.key.count >= 5 ? .high : .medium
        )
    }

    /// Små bokstaver uten diakritiske tegn og uten mellomrom i endene. Brukes av søket.
    fileprivate static func searchKey(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private struct IndexedService: Equatable {
        let searchName: String
        let nameWords: [String]
        let searchAliases: [String]
        /// Navn og alias renset med `MerchantText.normalized`, lengste først.
        let matchKeys: [String]

        init(_ service: CatalogService) {
            searchName = ServiceCatalog.searchKey(service.name)
            nameWords = searchName
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
            searchAliases = service.aliases.map(ServiceCatalog.searchKey)

            // Nøkler under 3 tegn hoppes over: navn som "DN" og "VG+" ville ellers truffet
            // hvert ord "dn" eller "vg" i en kontoutskrift. Slike tjenester gjenkjennes via aliasene.
            var keys: [String] = []
            for text in [service.name] + service.aliases {
                let key = MerchantText.normalized(text)
                if key.count >= 3, !keys.contains(key) {
                    keys.append(key)
                }
            }
            // Stabil sortering: like lange nøkler beholder rekkefølgen.
            matchKeys = keys.enumerated()
                .sorted { ($1.element.count, $0.offset) < ($0.element.count, $1.offset) }
                .map(\.element)
        }
    }
}

/// Rensing av mottakertekst fra kontoutskrifter og kvitteringer. Brukes av `match` og senere av CSV-importen.
enum MerchantText {
    /// Små bokstaver, uten diakritiske tegn, uten kortprefiks ("*1234 14.08 NOK 364.80 ", "Visa 100591 ",
    /// "Varekjøp ", "Dato 12.09 kl. 10.47", "Kurs: 1.0000", "Valutakurs: 9,8431", "PAYPAL *", "Vipps*"),
    /// tegnsetting erstattet med mellomrom, og mellomrom slått sammen.
    static func normalized(_ text: String) -> String {
        var result = text
            .lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for expression in removals {
            result = expression.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        return result
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    /// Mønstre for det bankene legger rundt mottakernavnet. Brukes i denne rekkefølgen,
    /// på tekst som allerede har små bokstaver og er uten diakritiske tegn (unntatt æ og ø).
    private static let removals: [NSRegularExpression] = {
        let number = #"\d+(?:[.,]\d+)*"#
        let currencies = CurrencyConverter.supportedCurrencies
            .map { $0.lowercased() }
            .joined(separator: "|")
        let patterns = [
            // Maskert kortnummer: "*1234".
            #"\*\d+"#,
            // Kortnummer etter korttype: "visa 100591".
            #"\b(?:visa|mastercard)\s+\d+"#,
            // Varekjøp med eller uten ø.
            #"\bvarekj[øo]p\b"#,
            // Valutakurs: "kurs: 1.0000", "valutakurs: 9,8431".
            #"\b(?:valuta)?kurs\b\s*:?\s*"# + number,
            // Dato og klokkeslett: "dato 12.09", "dato 12.09.2026", "kl. 10.47".
            #"\bdato\s+\d{1,2}\.\d{1,2}(?:\.\d{2,4})?\b"#,
            #"\bkl\b\.?\s*\d{1,2}[.:]\d{2}\b"#,
            // Valuta og beløp i begge rekkefølger: "nok 149.00", "25,00 usd".
            #"\b(?:"# + currencies + #")\s+"# + number + #"\b"#,
            #"\b"# + number + #"\s+(?:"# + currencies + #")\b"#,
            // Dato alene: "15.10", "15.10.26".
            #"\b\d{1,2}\.\d{1,2}(?:\.\d{2,4})?\b"#,
            // Betalingsformidlere foran mottakeren: "paypal *", "vipps*".
            #"\b(?:paypal|vipps)\s*\*"#
        ]
        // Mønstrene er faste og dekket av tester, så en feil her er en programmeringsfeil.
        return patterns.map { try! NSRegularExpression(pattern: $0) }
    }()
}
