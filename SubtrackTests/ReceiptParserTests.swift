import Foundation
import Testing
@testable import Subtrack

@MainActor
struct ReceiptParserTests {

    // MARK: - Hjelpere

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 20. oktober 2026, så datoer uten årstall får et kjent svar.
    private var now: Date { date(2026, 10, 20) }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func parse(_ text: String) -> ReceiptFields {
        ReceiptParser.parse(text, catalog: ServiceCatalog.bundled, now: now, calendar: calendar)
    }

    // MARK: - Typiske kvitteringer

    @Test func appleRenewalReceiptInNorwegian() {
        let fields = parse("""
        Fra: Apple <no_reply@email.apple.com>
        Emne: Din kvittering fra Apple

        Apple
        Abonnementet ditt er fornyet
        KVITTERING
        DATO 15.10.2026
        ORDRE-ID MX5ABC1234

        Spotify
        Premium Individual (Månedlig)
        Fornyes 15. november 2026
        109,00 kr

        SUBTOTAL 87,20 kr
        MVA 25 % 21,80 kr
        TOTALT 109,00 kr
        """)

        #expect(fields.name == "Spotify")
        #expect(fields.catalogServiceID == "spotify")
        #expect(fields.price == Decimal(string: "109.00"))
        #expect(fields.currencyCode == "NOK")
        #expect(fields.interval == .monthly)
        #expect(fields.nextRenewalDate == date(2026, 11, 15))
    }

    @Test func appleReceiptWithTwoServicesKeepsTheSenderAsName() {
        let fields = parse("""
        Fra: Apple <no_reply@email.apple.com>
        Emne: Din kvittering fra Apple

        Apple
        KVITTERING
        DATO 15.10.2026
        ORDRE-ID MX5ABC1234

        Spotify
        Premium Individual (Månedlig)
        109,00 kr
        iCloud+
        200 GB (Månedlig)
        39,00 kr

        TOTALT 148,00 kr
        """)

        #expect(fields.catalogServiceID == nil)
        #expect(fields.name == "Apple")
        #expect(fields.price == Decimal(string: "148.00"))
    }

    @Test func netflixReceiptInEnglish() {
        let fields = parse("""
        From: Netflix <info@mailer.netflix.com>
        Subject: Your Netflix receipt

        Hi Ola,
        Thanks for being a member. Your monthly payment was processed.
        Plan: Standard
        Next billing date: November 15, 2026
        Total: NOK 149.00
        """)

        #expect(fields.name == "Netflix")
        #expect(fields.catalogServiceID == "netflix")
        #expect(fields.price == Decimal(string: "149.00"))
        #expect(fields.currencyCode == "NOK")
        #expect(fields.interval == .monthly)
        #expect(fields.nextRenewalDate == date(2026, 11, 15))
    }

    @Test func netflixReceiptInNorwegian() {
        let fields = parse("""
        Fra: Netflix <info@mailer.netflix.com>
        Emne: Kvittering fra Netflix

        Hei Ola,
        Vi har trukket månedsbeløpet for abonnementet ditt.
        Beløp: 149,00 kr
        Neste betaling: 15.11.2026
        """)

        #expect(fields.catalogServiceID == "netflix")
        #expect(fields.price == Decimal(string: "149.00"))
        #expect(fields.currencyCode == "NOK")
        #expect(fields.interval == nil)
        #expect(fields.nextRenewalDate == date(2026, 11, 15))
    }

    @Test func spotifyReceiptInEuro() {
        let fields = parse("""
        From: Spotify <no-reply@spotify.com>
        Subject: Your receipt from Spotify

        Spotify Premium Individual
        €10.99 / month
        Total incl. VAT: €10.99
        Your subscription renews on 3 Dec 2026.
        """)

        #expect(fields.catalogServiceID == "spotify")
        #expect(fields.price == Decimal(string: "10.99"))
        #expect(fields.currencyCode == "EUR")
        #expect(fields.interval == .monthly)
        #expect(fields.nextRenewalDate == date(2026, 12, 3))
    }

    @Test func googlePlayReceiptInNorwegian() {
        let fields = parse("""
        Google Play
        Takk for kjøpet
        Ordrenummer: GPA.1234-5678-9012-34567
        Ordredato: 3. okt. 2026
        YouTube Premium
        Fornyes månedlig
        Pris: kr 169,00 per måned
        Totalt: kr 169,00
        Neste betaling: 3. nov. 2026
        """)

        #expect(fields.name == "YouTube Premium")
        #expect(fields.catalogServiceID == "youtube-premium")
        #expect(fields.price == Decimal(string: "169.00"))
        #expect(fields.currencyCode == "NOK")
        #expect(fields.interval == .monthly)
        #expect(fields.nextRenewalDate == date(2026, 11, 3))
    }

    @Test func norwegianServiceOutsideTheCatalogUsesSenderAndYearlyInterval() {
        let fields = parse("""
        Fra: Brannvakt Pluss <kvittering@brannvakt.no>
        Takk for din betaling
        Abonnement: Brannvakt Pluss
        Beløp å betale: 1 299,00 kr
        Gjelder per år
        Neste trekk 01.03.2027
        """)

        #expect(fields.name == "Brannvakt Pluss")
        #expect(fields.catalogServiceID == nil)
        #expect(fields.price == Decimal(string: "1299.00"))
        #expect(fields.currencyCode == "NOK")
        #expect(fields.interval == .yearly)
        #expect(fields.nextRenewalDate == date(2027, 3, 1))
    }

    @Test func englishReceiptOutsideTheCatalogWithDollarAndSlashDate() {
        let fields = parse("""
        From: "Acme Cloud" <billing@acme.io>
        Subject: Receipt

        Acme Cloud Pro, billed yearly
        Total: $29.00
        Renews on 03/15/2027
        """)

        #expect(fields.name == "Acme Cloud")
        #expect(fields.price == Decimal(string: "29.00"))
        #expect(fields.currencyCode == "USD")
        #expect(fields.interval == .yearly)
        #expect(fields.nextRenewalDate == date(2027, 3, 15))
    }

    // MARK: - Beløp

    @Test(arguments: [
        ("Totalt: 1 299,00 kr", "1299.00", "NOK"),
        ("Totalt: 1\u{00A0}299,00\u{00A0}kr", "1299.00", "NOK"),
        ("Totalt: 1\u{202F}299,00 NOK", "1299.00", "NOK"),
        ("Totalt: 1.299,00 kr", "1299.00", "NOK"),
        ("Totalt kr 1 299,-", "1299", "NOK"),
        ("Totalt 149,- kr", "149", "NOK"),
        ("Total: 1,299.00 USD", "1299.00", "USD"),
        ("Total: USD 9.99", "9.99", "USD"),
        ("Total: 9,99 EUR", "9.99", "EUR"),
        ("Total: £7.99", "7.99", "GBP"),
        ("Å betale: 99 kroner", "99", "NOK")
    ])
    func readsAmountsInCommonNotations(line: String, expected: String, currency: String) {
        let fields = parse(line)

        #expect(fields.price == Decimal(string: expected))
        #expect(fields.currencyCode == currency)
    }

    @Test func totalWinsOverSubtotalAndTax() {
        let fields = parse("""
        Delsum 100,00 kr
        MVA 25 % 25,00 kr
        Totalt inkl. mva 125,00 kr
        """)

        #expect(fields.price == Decimal(string: "125.00"))
    }

    @Test func totalOnTheLineAfterTheLabel() {
        let fields = parse("""
        Subtotal
        80,00 kr
        Total
        100,00 kr
        """)

        #expect(fields.price == Decimal(string: "100.00"))
    }

    @Test func lonelyAmountWithoutLabelIsUsed() {
        #expect(parse("Netflix Standard 149,00 kr").price == Decimal(string: "149.00"))
    }

    @Test func severalUnlabelledAmountsGiveNoAmount() {
        let fields = parse("""
        Vare 1: 49,00 kr
        Vare 2: 99,00 kr
        """)

        #expect(fields.price == nil)
        #expect(fields.currencyCode == nil)
    }

    @Test func freeTrialAmountIsNotUsed() {
        #expect(parse("Totalt 0,00 kr").price == nil)
    }

    @Test func numbersWithoutCurrencyAreNotAmounts() {
        #expect(parse("Totalt 149").price == nil)
        #expect(parse("Ordrenummer 123 456 789").price == nil)
    }

    @Test func lowercaseWordsAreNotCurrencyCodes() {
        // «try» er også koden for tyrkisk lire.
        #expect(parse("Try 3 months free").price == nil)
    }

    // MARK: - Intervall

    @Test(arguments: [
        ("149 kr per måned", BillingInterval.monthly),
        ("Betales månedlig", .monthly),
        ("149 kr/mnd", .monthly),
        ("Hver måned trekkes beløpet", .monthly),
        ("Billed monthly", .monthly),
        ("$9.99 / month", .monthly),
        ("Charged every month", .monthly),
        ("Årlig abonnement", .yearly),
        ("1 189 kr per år", .yearly),
        ("999 kr/år", .yearly),
        ("Billed annually", .yearly),
        ("Yearly plan", .yearly),
        ("Weekly plan", .weekly),
        ("Ukentlig trekk", .weekly),
        ("59 kr / uke", .weekly),
        ("Kvartalsvis betaling", .quarterly),
        ("Billed quarterly", .quarterly)
    ])
    func readsIntervalPhrases(text: String, expected: BillingInterval) {
        #expect(ReceiptParser.interval(in: text) == expected)
    }

    @Test func noIntervalWhenNothingIsSaid() {
        #expect(ReceiptParser.interval(in: "Takk for handelen. Totalt 149 kr") == nil)
    }

    @Test func noIntervalWhenTheTextSaysTwoThings() {
        #expect(ReceiptParser.interval(in: "Månedlig abonnement, årlig rabatt") == nil)
    }

    // MARK: - Dato

    @Test(arguments: [
        ("Neste trekk: 15.11.2026", 2026, 11, 15),
        ("Neste betaling 1. desember 2026", 2026, 12, 1),
        ("Fornyes 3 nov. 2026", 2026, 11, 3),
        ("Fornyelsesdato: 2026-12-24", 2026, 12, 24),
        ("Renews on November 15, 2026", 2026, 11, 15),
        ("Renews on Nov 15, 2026", 2026, 11, 15),
        ("Next billing date: 15 November 2026", 2026, 11, 15),
        ("Next billing date: 2026-11-15", 2026, 11, 15),
        ("Your next payment: 15/11/2026", 2026, 11, 15),
        ("Renews automatically on 11/15/2026", 2026, 11, 15),
        ("Neste fornyelse 15.11.26", 2026, 11, 15)
    ])
    func readsRenewalDates(text: String, year: Int, month: Int, day: Int) {
        #expect(ReceiptParser.renewalDate(in: text, now: now, calendar: calendar) == date(year, month, day))
    }

    @Test func dateWithoutYearUsesTheNextOccurrence() {
        #expect(ReceiptParser.renewalDate(in: "Fornyes 15. november", now: now, calendar: calendar) == date(2026, 11, 15))
        #expect(ReceiptParser.renewalDate(in: "Fornyes 5. januar", now: now, calendar: calendar) == date(2027, 1, 5))
    }

    @Test func dateOnTheLineAfterTheKeywordIsFound() {
        let text = "Neste trekk\n15.11.2026"

        #expect(ReceiptParser.renewalDate(in: text, now: now, calendar: calendar) == date(2026, 11, 15))
    }

    @Test func ambiguousSlashDateGivesNoDate() {
        #expect(ReceiptParser.renewalDate(in: "Renews on 03/04/2027", now: now, calendar: calendar) == nil)
    }

    @Test func impossibleDatesAreRejected() {
        #expect(ReceiptParser.renewalDate(in: "Neste trekk 31.02.2027", now: now, calendar: calendar) == nil)
        #expect(ReceiptParser.renewalDate(in: "Neste trekk 15.13.2027", now: now, calendar: calendar) == nil)
    }

    @Test func datesWithoutARenewalPhraseAreIgnored() {
        let fields = parse("""
        Kvittering
        DATO 15.10.2026
        Abonnementet ditt er fornyet
        Totalt 109,00 kr
        """)

        #expect(fields.nextRenewalDate == nil)
    }

    // MARK: - Navn

    @Test func senderNameFromHeaderValues() {
        #expect(ReceiptParser.senderName(fromHeaderValue: "Netflix <info@mailer.netflix.com>") == "Netflix")
        #expect(ReceiptParser.senderName(fromHeaderValue: "\"Acme Cloud\" <billing@acme.io>") == "Acme Cloud")
        #expect(ReceiptParser.senderName(fromHeaderValue: "no-reply@accounts.example.com") == "Example")
        #expect(ReceiptParser.senderName(fromHeaderValue: "No-Reply <noreply@tjenesten.co.uk>") == "Tjenesten")
        #expect(ReceiptParser.senderName(fromHeaderValue: "") == nil)
    }

    @Test func firstLineIsUsedWhenThereIsNoSender() {
        let fields = parse("""
        Brannvakt Pluss
        Beløp å betale: 99,00 kr
        """)

        #expect(fields.name == "Brannvakt Pluss")
        #expect(fields.catalogServiceID == nil)
    }

    @Test func greetingsAndTitlesAreNotUsedAsName() {
        let fields = parse("""
        Hei Ola,
        Kvittering
        Takk for handelen.
        """)

        #expect(fields.name == nil)
    }

    @Test func catalogServiceInTheBodyIsFoundOnlyWhenUnambiguous() {
        let single = parse("""
        Hei,
        Din betaling er mottatt.
        Takk
        Ordre 1234
        Dato 15.10.2026
        Detaljer
        Storytel Unlimited
        219,00 kr
        """)

        #expect(single.catalogServiceID == "storytel")
    }

    // MARK: - Uten noe å lese

    @Test func emptyAndUnreadableTextGiveEmptyFields() {
        for text in ["", "   \n  ", "Hei, takk for handelen.", "\u{FEFF}\u{200B}"] {
            let fields = parse(text)

            #expect(fields.catalogServiceID == nil)
            #expect(fields.price == nil)
            #expect(fields.interval == nil)
            #expect(fields.nextRenewalDate == nil)
        }
    }

    @Test func veryLongTextIsCutAndStillParsed() {
        let padding = String(repeating: "Lorem ipsum dolor sit amet\n", count: 2_000)
        let fields = parse("Totalt 99,00 kr\n" + padding)

        #expect(fields.price == Decimal(string: "99.00"))
    }

    @Test func cleanNormalisesSpacesAndLineBreaks() {
        let cleaned = ReceiptParser.clean("  A\u{00A0}\u{00A0}B\r\nC\u{200B}D \r\n\r\n")

        #expect(cleaned == "A B\nCD")
    }

    // MARK: - Utkast

    @Test func draftFromCatalogReceiptUsesReceiptAmountOverCatalogPrice() {
        var fields = ReceiptFields()
        fields.name = "Netflix"
        fields.catalogServiceID = "netflix"
        fields.price = Decimal(string: "169.00")
        fields.currencyCode = "NOK"
        fields.nextRenewalDate = date(2026, 11, 15)

        let draft = fields.draft(catalog: ServiceCatalog.bundled)

        #expect(draft.source == .receipt)
        #expect(draft.name == "Netflix")
        #expect(draft.price == Decimal(string: "169.00"))
        #expect(draft.currencyCode == "NOK")
        // Beløpet passer ikke med noen plan, og kvitteringen sier ikke noe om intervallet.
        #expect(draft.interval == nil)
        #expect(draft.kind == .streaming)
        #expect(draft.catalogServiceID == "netflix")
        #expect(draft.cancelURLString != nil)
        #expect(draft.nextRenewalDate == date(2026, 11, 15))
    }

    @Test func draftTakesTheIntervalFromAPlanWithTheSameAmount() {
        var fields = ReceiptFields()
        fields.name = "Netflix"
        fields.catalogServiceID = "netflix"
        fields.price = Decimal(string: "149.00")
        fields.currencyCode = "NOK"

        let draft = fields.draft(catalog: ServiceCatalog.bundled)

        #expect(draft.interval == .monthly)
    }

    @Test func draftKeepsCatalogDefaultsWhenTheReceiptHasNoAmountOrInterval() {
        var fields = ReceiptFields()
        fields.name = "Netflix"
        fields.catalogServiceID = "netflix"

        let draft = fields.draft(catalog: ServiceCatalog.bundled)

        #expect(draft.price == Decimal(string: "149.00"))
        #expect(draft.interval == .monthly)
    }

    @Test func draftFindsThePlanForAnIntervalWithoutAmount() {
        var fields = ReceiptFields()
        fields.name = "Strava"
        fields.catalogServiceID = "strava"
        fields.interval = .yearly

        let draft = fields.draft(catalog: ServiceCatalog.bundled)

        #expect(draft.interval == .yearly)
        #expect(draft.price == Decimal(string: "799.00"))
    }

    @Test func draftWithoutCatalogLeavesUnknownFieldsEmpty() {
        var fields = ReceiptFields()
        fields.name = "Brannvakt Pluss"

        let draft = fields.draft(catalog: ServiceCatalog.bundled)

        #expect(draft.source == .receipt)
        #expect(draft.name == "Brannvakt Pluss")
        #expect(draft.price == nil)
        #expect(draft.currencyCode == nil)
        #expect(draft.interval == nil)
        #expect(draft.kind == nil)
        #expect(draft.catalogServiceID == nil)
    }

    @Test func fullPipelineWithoutModelGivesTheRuleBasedDraft() async {
        let draft = await ReceiptParser.draft(
            fromReceiptText: "From: Netflix <info@netflix.com>\nTotal: NOK 149.00\nBilled monthly",
            catalog: ServiceCatalog.bundled,
            now: now,
            calendar: calendar
        )

        #expect(draft.source == .receipt)
        #expect(draft.name == "Netflix")
        #expect(draft.price == Decimal(string: "149.00"))
        #expect(draft.interval == .monthly)
    }
}
