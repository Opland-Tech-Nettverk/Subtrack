import Foundation
import Testing
@testable import Subtrack

/// Tester den delen av tilleggstolkingen som ikke trenger Foundation Models: validering, sammenslåing og
/// nedkorting av teksten. Selve modellkallet kan bare prøves på en enhet med Apple Intelligence.
@MainActor
struct ReceiptEnrichmentTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var now: Date { date(2026, 10, 20) }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private let catalog = ServiceCatalog.bundled

    private func validated(_ candidate: ReceiptModelCandidate) -> ReceiptModelCandidate {
        ReceiptEnrichment.validated(candidate, now: now, calendar: calendar)
    }

    private func merge(
        _ rules: ReceiptFields,
        _ candidate: ReceiptModelCandidate,
        text: String
    ) -> ReceiptFields {
        ReceiptEnrichment.merge(rules, with: candidate, sourceText: text, catalog: catalog, now: now, calendar: calendar)
    }

    // MARK: - Validering

    @Test func validCandidateIsKept() {
        let candidate = ReceiptModelCandidate(
            name: "  Brannvakt Pluss ",
            price: Decimal(string: "149.00"),
            currencyCode: "nok",
            interval: .monthly,
            nextRenewalDate: date(2026, 11, 15)
        )

        let result = validated(candidate)

        #expect(result.name == "Brannvakt Pluss")
        #expect(result.price == Decimal(string: "149.00"))
        #expect(result.currencyCode == "NOK")
        #expect(result.interval == .monthly)
        #expect(result.nextRenewalDate == date(2026, 11, 15))
    }

    @Test(arguments: ["0", "-5", "0.00", "2000000"])
    func nonPositiveOrAbsurdAmountsAreDropped(amount: String) {
        let candidate = ReceiptEnrichment.candidate(
            name: nil, amountText: amount, currencyCode: "NOK", interval: nil, dateText: nil,
            now: now, calendar: calendar
        )

        let result = validated(candidate)

        #expect(result.price == nil)
        #expect(result.currencyCode == nil)
    }

    @Test(arguments: ["XXX", "KR", "", "BTC"])
    func unsupportedCurrencyDropsTheAmount(code: String) {
        let candidate = ReceiptModelCandidate(price: 100, currencyCode: code)

        let result = validated(candidate)

        #expect(result.price == nil)
        #expect(result.currencyCode == nil)
    }

    @Test func amountWithoutCurrencyIsDropped() {
        #expect(validated(ReceiptModelCandidate(price: 100, currencyCode: nil)).price == nil)
    }

    @Test func implausibleDatesAreDropped() {
        // Mer enn en dag tilbake, og mer enn tre år fram.
        #expect(validated(ReceiptModelCandidate(nextRenewalDate: date(2026, 10, 1))).nextRenewalDate == nil)
        #expect(validated(ReceiptModelCandidate(nextRenewalDate: date(2030, 1, 1))).nextRenewalDate == nil)
        // I går, i dag og om to år er greit.
        #expect(validated(ReceiptModelCandidate(nextRenewalDate: date(2026, 10, 19))).nextRenewalDate == date(2026, 10, 19))
        #expect(validated(ReceiptModelCandidate(nextRenewalDate: date(2028, 10, 20))).nextRenewalDate == date(2028, 10, 20))
    }

    @Test(arguments: ["", " ", "1", "12345", String(repeating: "a", count: 61)])
    func unusableNamesAreDropped(name: String) {
        #expect(validated(ReceiptModelCandidate(name: name)).name == nil)
    }

    @Test func modelAnswersAreConvertedToTypedValues() {
        let candidate = ReceiptEnrichment.candidate(
            name: "Netflix", amountText: "1 299,00", currencyCode: "NOK", interval: .yearly, dateText: "2026-11-15",
            now: now, calendar: calendar
        )

        #expect(candidate.price == Decimal(string: "1299.00"))
        #expect(candidate.nextRenewalDate == date(2026, 11, 15))
        #expect(candidate.interval == .yearly)
    }

    @Test(arguments: ["15.11.2026", "2026-13-01", "2026-02-31", "tomorrow", "", "2026-11"])
    func malformedDateTextGivesNoDate(text: String) {
        let candidate = ReceiptEnrichment.candidate(
            name: nil, amountText: nil, currencyCode: nil, interval: nil, dateText: text,
            now: now, calendar: calendar
        )

        #expect(candidate.nextRenewalDate == nil)
    }

    // MARK: - Sammenslåing

    private let receipt = """
    Fra: Brannvakt Pluss <kvittering@brannvakt.no>
    Abonnement: Brannvakt Pluss
    Delsum 100,00 kr
    Beløp 125,00 kr
    """

    @Test func rulesWinForTheAmountOnConflict() {
        var rules = ReceiptFields()
        rules.price = Decimal(string: "125.00")
        rules.currencyCode = "NOK"
        let model = ReceiptModelCandidate(price: Decimal(string: "100.00"), currencyCode: "NOK")

        let result = merge(rules, model, text: receipt)

        #expect(result.price == Decimal(string: "125.00"))
        #expect(result.currencyCode == "NOK")
    }

    @Test func modelFillsAnAmountTheRulesCouldNotChoose() {
        let model = ReceiptModelCandidate(price: Decimal(string: "125.00"), currencyCode: "NOK")

        let result = merge(ReceiptFields(), model, text: receipt)

        #expect(result.price == Decimal(string: "125.00"))
        #expect(result.currencyCode == "NOK")
    }

    @Test func modelAmountThatIsNotInTheTextIsRejected() {
        let model = ReceiptModelCandidate(price: Decimal(string: "999.00"), currencyCode: "NOK")

        let result = merge(ReceiptFields(), model, text: receipt)

        #expect(result.price == nil)
    }

    @Test func modelAmountInAnotherCurrencyThanTheTextIsRejected() {
        let model = ReceiptModelCandidate(price: Decimal(string: "125.00"), currencyCode: "USD")

        let result = merge(ReceiptFields(), model, text: receipt)

        #expect(result.price == nil)
    }

    @Test func modelFillsIntervalAndDateButNeverOverwritesRules() {
        var rules = ReceiptFields()
        rules.interval = .yearly
        let model = ReceiptModelCandidate(interval: .monthly, nextRenewalDate: date(2026, 11, 15))

        let result = merge(rules, model, text: "Fornyes 15. november 2026\nBetales månedlig")

        #expect(result.interval == .yearly)
        #expect(result.nextRenewalDate == date(2026, 11, 15))
    }

    @Test func modelNameIsUsedOnlyWhenItStandsInTheText() {
        let invented = merge(ReceiptFields(), ReceiptModelCandidate(name: "Totally Made Up"), text: receipt)
        let real = merge(ReceiptFields(), ReceiptModelCandidate(name: "Brannvakt Pluss"), text: receipt)

        #expect(invented.name == nil)
        #expect(real.name == "Brannvakt Pluss")
        #expect(real.catalogServiceID == nil)
    }

    @Test func modelNameIsMatchedAgainstTheCatalog() {
        var rules = ReceiptFields()
        rules.name = "Apple"

        let result = merge(rules, ReceiptModelCandidate(name: "Spotify"), text: "Apple\nSpotify Premium\n109,00 kr")

        #expect(result.name == "Spotify")
        #expect(result.catalogServiceID == "spotify")
    }

    @Test func rulesCatalogMatchWinsOverTheModelName() {
        var rules = ReceiptFields()
        rules.name = "Netflix"
        rules.catalogServiceID = "netflix"

        let result = merge(rules, ReceiptModelCandidate(name: "Spotify"), text: "Netflix och Spotify")

        #expect(result.name == "Netflix")
        #expect(result.catalogServiceID == "netflix")
    }

    @Test func invalidModelValuesChangeNothing() {
        let model = ReceiptModelCandidate(
            name: "1",
            price: -10,
            currencyCode: "NOK",
            interval: nil,
            nextRenewalDate: date(1999, 1, 1)
        )

        let result = merge(ReceiptFields(), model, text: receipt)

        #expect(result.name == nil)
        #expect(result.price == nil)
        #expect(result.nextRenewalDate == nil)
    }

    // MARK: - Grunnlag i teksten (fix 2 og 3)

    private let tieReceipt = """
    Totalt 149,00 kr
    Sum 129,00 kr
    MVA 25 % 29,80 kr
    """

    @Test func modelCannotPickTheVatAmountWhenTheRulesAreInDoubt() {
        #expect(ReceiptParser.bestAmount(in: tieReceipt) == nil)
        let model = ReceiptModelCandidate(price: Decimal(string: "29.80"), currencyCode: "NOK")

        let result = merge(ReceiptFields(), model, text: tieReceipt)

        #expect(result.price == nil)
    }

    @Test func modelCanChooseBetweenTheAmountsTheRulesWereInDoubtAbout() {
        let model = ReceiptModelCandidate(price: Decimal(string: "149.00"), currencyCode: "NOK")

        let result = merge(ReceiptFields(), model, text: tieReceipt)

        #expect(result.price == Decimal(string: "149.00"))
    }

    @Test(arguments: ["Rabatt 20,00 kr", "Delsum 100,00 kr", "Refusjon 49,00 kr", "Saldo 12,00 kr"])
    func modelCannotPickDiscardedAmounts(discarded: String) {
        let text = "Totalt 149,00 kr\nSum 129,00 kr\n\(discarded)"
        let price = ReceiptParser.amounts(inLine: discarded).first!.price

        let result = merge(ReceiptFields(), ReceiptModelCandidate(price: price, currencyCode: "NOK"), text: text)

        #expect(result.price == nil)
    }

    @Test func modelIntervalMustBeNamedInTheText() {
        let model = ReceiptModelCandidate(interval: .monthly)

        #expect(merge(ReceiptFields(), model, text: "Brannvakt Pluss\nTotalt 149,00 kr").interval == nil)
        #expect(merge(ReceiptFields(), model, text: "Brannvakt Pluss\nBetales månedlig").interval == .monthly)
    }

    @Test func modelCannotInventAnIntervalTheTextDoesNotName() {
        let model = ReceiptModelCandidate(interval: .yearly)

        let result = merge(ReceiptFields(), model, text: "Billed monthly. Total 99 kr")

        #expect(result.interval == nil)
    }

    @Test func modelDateMustStandInTheTextWithARenewalPhrase() {
        let model = ReceiptModelCandidate(nextRenewalDate: date(2026, 11, 15))

        // Datoen står ikke i teksten (modellen har regnet den ut).
        #expect(merge(ReceiptFields(), model, text: "Kjøpsdato 15. oktober 2026\nNeste trekk i neste måned").nextRenewalDate == nil)
        // Datoen står i teksten, men ikke som fornyelse.
        #expect(merge(ReceiptFields(), model, text: "Kjøpsdato 15. november 2026\nTotalt 99,00 kr").nextRenewalDate == nil)
        // Datoen står i teksten og teksten har et fornyelsesord.
        let grounded = merge(ReceiptFields(), model, text: "Kjøpsdato 15. november 2026\nFornyes automatisk. Totalt 99,00 kr")
        #expect(grounded.nextRenewalDate == date(2026, 11, 15))
    }

    @Test func ambiguousSlashDateFromTheModelIsRejected() {
        // 03/04/2027 kan være 3. april eller 4. mars; reglene lar den stå tom, og modellen får ikke velge.
        let model = ReceiptModelCandidate(nextRenewalDate: date(2027, 4, 3))

        let result = merge(ReceiptFields(), model, text: "Renews on 03/04/2027")

        #expect(result.nextRenewalDate == nil)
    }

    // MARK: - Nedkorting av teksten

    @Test func shortTextIsOnlyCleaned() {
        #expect(ReceiptEnrichment.trimmedInput("A\u{00A0}B\r\nC") == "A B\nC")
    }

    @Test func longTextIsCutToTheLimitAndKeepsTheImportantLines() {
        let filler = (0..<300).map { "Fyllrad nummer \($0) uten noe interessant" }.joined(separator: "\n")
        let text = "Fra: Netflix <info@netflix.com>\n" + filler + "\nTotalt 149,00 kr\nNeste trekk 15.11.2026"

        let result = ReceiptEnrichment.trimmedInput(text, limit: 2_000)

        #expect(result.count <= 2_000)
        #expect(result.hasPrefix("Fra: Netflix"))
        #expect(result.contains("Totalt 149,00 kr"))
        #expect(result.contains("Neste trekk 15.11.2026"))
        #expect(result.range(of: "Totalt")!.lowerBound > result.range(of: "Fyllrad nummer 0 ")!.lowerBound)
    }

    @Test func repeatedLinesAreKeptOnce() {
        let text = String(repeating: "Samme linje\n", count: 600) + "Totalt 99,00 kr"

        let result = ReceiptEnrichment.trimmedInput(text, limit: 200)

        #expect(result.components(separatedBy: "Samme linje").count == 2)
        #expect(result.contains("Totalt 99,00 kr"))
    }

    @Test func defaultLimitFitsTheContextWindow() {
        let text = (0..<400).map { "Linje \($0) lorem ipsum dolor sit amet consectetur" }.joined(separator: "\n")

        let result = ReceiptEnrichment.trimmedInput(text)

        #expect(result.count <= ReceiptEnrichment.maxModelInputLength)
    }
}
