import Foundation
import Testing
@testable import Subtrack

@MainActor
struct RecurringChargeDetectorTests {

    private typealias Support = BankStatementTestSupport

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Support.day(year, month, day)
    }

    private func detect(
        _ transactions: [StatementTransaction],
        existing: [String] = [],
        now: Date? = nil
    ) -> [SubscriptionSuggestion] {
        RecurringChargeDetector.detect(
            transactions: transactions,
            catalog: Support.catalog,
            existingNames: existing,
            now: now ?? Support.now,
            calendar: Support.calendar
        )
    }

    /// Trekk med like mange dager mellom hver, fra og med `start`.
    private func every(
        _ days: Int,
        count: Int,
        text: String,
        amount: Decimal,
        from start: Date,
        currency: String = "NOK"
    ) -> [StatementTransaction] {
        (0..<count).map { index in
            let date = Support.calendar.date(byAdding: .day, value: days * index, to: start)!
            return Support.transaction(date, amount, text, currency: currency)
        }
    }

    // MARK: - Månedlig

    @Test func monthlyWithVaryingNOKAmountsIsASuggestion() {
        let transactions = Support.monthly(
            "Fooservice AB",
            amounts: ["201.60", "205.10", "203.00", "207.40"].map(Support.decimal),
            from: day(2026, 6, 10)
        )
        let suggestions = detect(transactions)
        #expect(suggestions.count == 1)
        let suggestion = suggestions.first
        #expect(suggestion?.name == "Fooservice AB")
        #expect(suggestion?.interval == .monthly)
        #expect(suggestion?.currencyCode == "NOK")
        // Siste beløp når det ikke er noe bedre å gå på.
        #expect(suggestion?.price == Support.decimal("207.40"))
        #expect(suggestion?.chargeCount == 4)
        #expect(suggestion?.lastChargeDate == day(2026, 9, 10))
        // 10. oktober er før «i dag» (20. oktober), så neste trekk er 10. november.
        #expect(suggestion?.nextExpectedDate == day(2026, 11, 10))
    }

    @Test func nextExpectedDateIsOneIntervalAfterTheLastChargeAndNeverInThePast() {
        let transactions = Support.monthly("Fooservice AB", amounts: [100, 100, 100], from: day(2026, 1, 14))
        // Utskriften slutter med serien, så den regnes ikke som avsluttet. Siste trekk 14. mars.
        // 20. oktober er «i dag», så neste trekk er 14. november.
        let suggestion = detect(transactions, now: day(2026, 10, 20)).first
        #expect(suggestion?.lastChargeDate == day(2026, 3, 14))
        #expect(suggestion?.nextExpectedDate == day(2026, 11, 14))
        // Er den neste datoen etter i dag, er det rett etter siste trekk.
        let recent = detect(transactions, now: day(2026, 3, 20)).first
        #expect(recent?.nextExpectedDate == day(2026, 4, 14))
    }

    @Test func moreChargesThanTheMinimumGiveHighConfidenceAndTheMinimumGivesMedium() {
        let three = Support.monthly("Fooservice AB", amounts: [100, 100, 100], from: day(2026, 6, 10))
        let four = Support.monthly("Barservice AB", amounts: [100, 100, 100, 100], from: day(2026, 6, 10))
        #expect(detect(three).first?.confidence == .medium)
        #expect(detect(four).first?.confidence == .high)
    }

    @Test func oneMissingMonthIsToleratedWhenThereAreEnoughCharges() {
        var transactions = Support.monthly("Fooservice AB", amounts: [100, 100], from: day(2026, 1, 10))
        // Mars mangler i utskriften.
        transactions += Support.monthly("Fooservice AB", amounts: [100, 100, 100], from: day(2026, 4, 10))
        #expect(detect(transactions).first?.interval == .monthly)
    }

    @Test func twoMonthlyChargesAreNotEnough() {
        let transactions = Support.monthly("Fooservice AB", amounts: [100, 100], from: day(2026, 8, 10))
        #expect(detect(transactions).isEmpty)
    }


    // MARK: - Avsluttede serier

    @Test func aSeriesThatStoppedLongBeforeTheEndOfTheStatementIsNotSuggested() {
        // Netflix januar til mai, så sluttet trekkene. Utskriften varer til oktober.
        let netflix = Support.monthly("NETFLIX.COM", amounts: [149, 149, 149, 149, 149], from: day(2026, 1, 14))
        let laterPurchase = Support.transaction(day(2026, 10, 14), 312.50, "REMA 1000 STORO")
        #expect(detect(netflix).map(\.name) == ["Netflix"])
        #expect(detect(netflix + [laterPurchase]).isEmpty)
    }

    @Test func aSeriesIsStillRunningUpToOneAndAHalfIntervalsAfterTheLastCharge() {
        let series = Support.monthly("Fooservice AB", amounts: [100, 100, 100, 100], from: day(2026, 1, 10))
        // Siste trekk 10. april. 45 dager etter er 25. mai; 46 dager etter er 26. mai.
        let withinLimit = Support.transaction(day(2026, 5, 25), 50, "Kiosken")
        let beyondLimit = Support.transaction(day(2026, 5, 26), 50, "Kiosken")
        #expect(detect(series + [withinLimit]).map(\.name) == ["Fooservice AB"])
        #expect(detect(series + [beyondLimit]).isEmpty)
    }

    @Test func anOldStatementIsNotTreatedAsAllEnded() {
        // Hele utskriften er fra i fjor, men serien varer til slutten av den.
        let series = Support.monthly("NETFLIX.COM", amounts: [149, 149, 149], from: day(2025, 1, 14))
        #expect(detect(series, now: day(2026, 10, 20)).map(\.name) == ["Netflix"])
    }

    // MARK: - Prisendringer

    @Test func aPriceIncreaseInTheMiddleKeepsTheSeriesAndUsesTheLatestPrice() {
        // Netflix 129 kr og så 149 kr. Regnet mot medianen alene ville +15 % falt utenfor ±10 %.
        let transactions = Support.monthly("NETFLIX.COM", amounts: [129, 129, 129, 149, 149, 149], from: day(2026, 1, 14))
        let suggestion = detect(transactions).first
        #expect(suggestion?.name == "Netflix")
        #expect(suggestion?.price == 149)
        #expect(suggestion?.chargeCount == 6)
        #expect(suggestion?.confidence == .high)
    }

    @Test func aPriceIncreaseInTheLastMonthKeepsTheSeries() {
        let transactions = Support.monthly("SPOTIFY.COM", amounts: [119, 119, 119, 119, 139], from: day(2026, 1, 3))
        let suggestion = detect(transactions).first
        #expect(suggestion?.name == "Spotify")
        #expect(suggestion?.price == 139)
    }

    @Test func aPriceIncreaseForAnUnknownMerchantUsesTheLatestAmount() {
        let transactions = Support.monthly("Fooservice AB", amounts: [100, 100, 100, 115, 115], from: day(2026, 1, 10))
        let suggestion = detect(transactions).first
        #expect(suggestion?.price == 115)
        #expect(suggestion?.currencyCode == "NOK")
    }

    @Test func aPriceDropIsAlsoOnePriceChange() {
        let transactions = Support.monthly("Fooservice AB", amounts: [199, 199, 199, 149, 149], from: day(2026, 1, 10))
        #expect(detect(transactions).first?.price == 149)
    }

    @Test func moreThanTwoPriceLevelsAreNotASeries() {
        let transactions = Support.monthly("Fooservice AB", amounts: [100, 150, 100, 150, 100], from: day(2026, 1, 10))
        #expect(detect(transactions).isEmpty)
        let threeLevels = Support.monthly("Barservice AB", amounts: [100, 100, 130, 130, 170, 170], from: day(2026, 1, 10))
        #expect(detect(threeLevels).isEmpty)
    }

    @Test func aSingleHugeLastChargeIsNotANewPrice() {
        let transactions = Support.monthly("Fooservice AB", amounts: [100, 100, 100, 100, 5000], from: day(2026, 1, 10))
        #expect(detect(transactions).isEmpty)
    }

    // MARK: - Navn som ligner et eksisterende abonnement

    @Test func similarNamesCountAsExistingSubscriptions() {
        let telenor = Support.monthly("TELENOR NORGE AS", amounts: [599, 599, 599, 599], from: day(2026, 1, 20))
        let gym = Support.monthly("Fitness24seven AB 12345", amounts: [399, 399, 399, 399], from: day(2026, 1, 5))
        let insurance = Support.monthly("GJENSIDIGE FORSIKRING ASA", amounts: [820, 820, 820, 820], from: day(2026, 1, 1))
        let all = telenor + gym + insurance
        #expect(detect(all).count == 3)
        #expect(detect(all, existing: ["Telenor"]).count == 2)
        #expect(detect(all, existing: ["telenor mobil"]).count == 2)
        #expect(detect(all, existing: ["Fitness24Seven"]).count == 2)
        #expect(detect(all, existing: ["Gjensidige"]).count == 2)
        #expect(detect(all, existing: ["Telenor", "Fitness24Seven", "Gjensidige"]).isEmpty)
        // Et annet navn er ikke det samme abonnementet.
        #expect(detect(all, existing: ["Telia", "Fitnessworld", "If forsikring"]).count == 3)
    }

    // MARK: - Navn uten referansenumre

    @Test func suggestedNamesHaveNoReferenceOrAccountNumbers() {
        let withReference = Support.monthly("GOOGLE YouTube 1234567", amounts: [169, 169, 169], from: day(2026, 1, 6))
        let withKid = Support.monthly("Telenor KID 123456789012 Ref 998877", amounts: [599, 599, 599], from: day(2026, 1, 20))
        let withAccount = Support.monthly("Husleie 1234.56.78901", amounts: [9000, 9000, 9000], from: day(2026, 1, 1))
        let names = Set(detect(withReference + withKid + withAccount).map(\.name))
        #expect(names == ["GOOGLE YouTube", "Telenor", "Husleie"])
    }

    // MARK: - Foreign currency og katalog

    @Test func foreignChargesWithAFixedOriginalAmountUseThatAmountAndCurrency() {
        // Kronebeløpet svinger mer enn 10 % med kursen, men USD 20 er likt hver gang.
        let amounts: [(String, Decimal)] = [
            ("*1234 10.04 USD 20.00 ACMEAPP.COM Kurs: 8.0000", 160),
            ("*1234 10.05 USD 20.00 ACMEAPP.COM Kurs: 10.0800", 201.6),
            ("*1234 10.06 USD 20.00 ACMEAPP.COM Kurs: 12.0000", 240)
        ]
        let transactions = zip(amounts, [day(2026, 4, 10), day(2026, 5, 10), day(2026, 6, 10)]).map { pair, date in
            Support.transaction(date, pair.1, pair.0)
        }
        let suggestion = detect(transactions).first
        #expect(suggestion?.price == 20)
        #expect(suggestion?.currencyCode == "USD")
        #expect(suggestion?.interval == .monthly)
        #expect(suggestion?.name == "Acmeapp.com")
    }

    @Test func varyingAmountsWithoutAFixedOriginalAreNotASuggestion() {
        let transactions = Support.monthly("Fooservice AB", amounts: [100, 180, 90, 300], from: day(2026, 6, 10))
        #expect(detect(transactions).isEmpty)
    }

    @Test func catalogMatchUsesThePlanPriceWhenCloseEnough() {
        // Netflix Standard er 149 kr. 151 er innenfor ±10 %.
        let transactions = Support.monthly("*1234 NETFLIX.COM", amounts: [151, 151, 151], from: day(2026, 6, 14))
        let suggestion = detect(transactions).first
        #expect(suggestion?.name == "Netflix")
        #expect(suggestion?.price == 149)
        #expect(suggestion?.currencyCode == "NOK")
        #expect(suggestion?.service?.id == "netflix")
        // Sikkert katalogtreff gir høy sikkerhet også med minste antall trekk.
        #expect(suggestion?.confidence == .high)
    }

    @Test func catalogMatchWithAnOffPlanPriceKeepsTheChargedAmount() {
        let transactions = Support.monthly("NETFLIX.COM", amounts: [89, 89, 89], from: day(2026, 6, 14))
        let suggestion = detect(transactions).first
        #expect(suggestion?.name == "Netflix")
        #expect(suggestion?.price == 89)
    }

    @Test func catalogUSDPlanIsUsedForAForeignChargeWithAFixedOriginalAmount() {
        let amounts: [Decimal] = [201.6, 205.0, 207.3, 206.2]
        let texts = [
            "*1234 21.04 USD 20.00 CLAUDE.AI SUBSCRIPTION Kurs: 10.0800",
            "*1234 21.05 USD 20.00 CLAUDE.AI SUBSCRIPTION Kurs: 10.2500",
            "*1234 21.06 USD 20.00 CLAUDE.AI SUBSCRIPTION Kurs: 10.3650",
            "*1234 21.07 USD 20.00 CLAUDE.AI SUBSCRIPTION Kurs: 10.3100"
        ]
        let dates = [day(2026, 4, 21), day(2026, 5, 21), day(2026, 6, 21), day(2026, 7, 21)]
        let transactions = (0..<4).map { Support.transaction(dates[$0], amounts[$0], texts[$0]) }
        let suggestion = detect(transactions).first
        #expect(suggestion?.name == "Claude")
        #expect(suggestion?.price == 20)
        #expect(suggestion?.currencyCode == "USD")
        #expect(suggestion?.draft.catalogServiceID == "claude")
    }

    @Test func catalogServiceWithoutPlansIsKeptWithoutACatalogPrice() {
        let transactions = Support.monthly("PATREON MEMBERSHIP", amounts: [55, 55, 55], from: day(2026, 6, 5))
        let suggestion = detect(transactions).first
        #expect(suggestion?.name == "Patreon")
        #expect(suggestion?.price == 55)
        #expect(suggestion?.draft.kind == .annet)
    }

    @Test func aShortAliasDoesNotNameAnUnrelatedMerchantAfterTheCatalogService() {
        // «max» er et kort alias og gir bare et usikkert treff.
        let transactions = Support.monthly("MAX BURGER OSLO", amounts: [199, 199, 199, 199], from: day(2026, 6, 3))
        let suggestion = detect(transactions).first
        #expect(suggestion?.name == "Max Burger Oslo")
        #expect(suggestion?.service == nil)
    }

    @Test func differentSpellingsOfACatalogServiceAreOneSuggestion() {
        let transactions = [
            Support.transaction(day(2026, 6, 14), 149, "*1234 14.06 NOK 149.00 NETFLIX.COM Kurs: 1.0000"),
            Support.transaction(day(2026, 7, 14), 149, "Visa 100591 Varekjøp Netflix International"),
            Support.transaction(day(2026, 8, 14), 149, "Netflix.com")
        ]
        let suggestions = detect(transactions)
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.chargeCount == 3)
    }

    // MARK: - Andre intervaller

    @Test func weeklyNeedsThreeCharges() {
        let four = every(7, count: 4, text: "Ukeavis AS", amount: 59, from: day(2026, 9, 1))
        let two = every(7, count: 2, text: "Ukeavis AS", amount: 59, from: day(2026, 9, 1))
        #expect(detect(four).first?.interval == .weekly)
        #expect(detect(two).isEmpty)
    }

    @Test func quarterlyAndYearlyNeedTwoCharges() {
        let quarterly = every(91, count: 2, text: "Kvartalsavis AS", amount: 399, from: day(2026, 1, 15))
        let yearly = every(365, count: 2, text: "Årsavis AS", amount: 1190, from: day(2025, 3, 1))
        #expect(detect(quarterly).first?.interval == .quarterly)
        #expect(detect(yearly).first?.interval == .yearly)
        #expect(detect(quarterly).first?.confidence == .medium)
    }

    @Test func yearlyCatalogServiceIsHighConfidenceAndUsesThePlan() {
        let transactions = every(365, count: 2, text: "MICROSOFT 365 PERSONAL", amount: 1189, from: day(2025, 2, 10))
        let suggestion = detect(transactions).first
        #expect(suggestion?.name == "Microsoft 365")
        #expect(suggestion?.interval == .yearly)
        #expect(suggestion?.price == 1189)
        #expect(suggestion?.confidence == .high)
    }

    @Test func gapsOutsideEveryBandAreNotASuggestion() {
        // 14 dager og 45 dager ligger mellom ukentlig og månedlig.
        #expect(detect(every(14, count: 4, text: "Annenhver AS", amount: 100, from: day(2026, 6, 1))).isEmpty)
        #expect(detect(every(45, count: 4, text: "Femtenhver AS", amount: 100, from: day(2026, 1, 1))).isEmpty)
    }

    // MARK: - Ikke abonnement

    @Test func irregularPurchasesAreNotASuggestion() {
        // Dagligvare: ulike dager og ulike beløp.
        let dates = [day(2026, 6, 2), day(2026, 6, 5), day(2026, 6, 13), day(2026, 6, 14), day(2026, 6, 27), day(2026, 7, 9)]
        let amounts: [Decimal] = [412.30, 88.50, 650, 129.90, 301.10, 77]
        let transactions = zip(dates, amounts).map { Support.transaction($0, $1, "REMA 1000 STORO") }
        #expect(detect(transactions).isEmpty)
    }

    @Test func regularVisitsWithVaryingAmountsAreNotASuggestion() {
        let transactions = Support.monthly("KIWI MAJORSTUEN", amounts: [412, 88, 650, 129], from: day(2026, 6, 14))
        #expect(detect(transactions).isEmpty)
    }

    @Test func irregularGapsWithTheSameAmountAreNotASuggestion() {
        let dates = [day(2026, 6, 1), day(2026, 6, 3), day(2026, 7, 2), day(2026, 7, 20)]
        let transactions = dates.map { Support.transaction($0, 99, "Kiosken") }
        #expect(detect(transactions).isEmpty)
    }

    @Test func twoChargesOnTheSameDayCountAsOne() {
        var transactions = Support.monthly("Fooservice AB", amounts: [100, 100], from: day(2026, 6, 10))
        transactions.append(Support.transaction(day(2026, 6, 10), 100, "Fooservice AB"))
        transactions.append(Support.transaction(day(2026, 8, 10), 100, "Fooservice AB"))
        let suggestion = detect(transactions).first
        #expect(suggestion?.chargeCount == 3)
        #expect(suggestion?.interval == .monthly)
    }

    @Test func aSingleChargeIsNotASuggestion() {
        #expect(detect([Support.transaction(day(2026, 6, 10), 100, "Fooservice AB")]).isEmpty)
        #expect(detect([]).isEmpty)
    }

    @Test func transactionsWithoutAMerchantAreIgnored() {
        let transactions = Support.monthly("*1234 14.08 NOK 149.00 Kurs: 1.0000", amounts: [149, 149, 149], from: day(2026, 6, 14))
        #expect(detect(transactions).isEmpty)
    }

    // MARK: - Dubletter mot eksisterende abonnementer

    @Test func suggestionsForExistingSubscriptionsAreLeftOut() {
        let transactions = Support.monthly("NETFLIX.COM", amounts: [149, 149, 149], from: day(2026, 6, 14))
            + Support.monthly("Fooservice AB", amounts: [100, 100, 100], from: day(2026, 6, 10))
        #expect(detect(transactions).count == 2)
        #expect(detect(transactions, existing: ["Netflix"]).map(\.name) == ["Fooservice AB"])
        // Samme katalogtjeneste, selv med et annet navn.
        #expect(detect(transactions, existing: ["Netflix Familie"]).map(\.name) == ["Fooservice AB"])
        // Samme navn, uten katalogen, og uavhengig av store og små bokstaver.
        #expect(detect(transactions, existing: ["fooservice ab"]).map(\.name) == ["Netflix"])
        #expect(detect(transactions, existing: ["Netflix", "Fooservice AB"]).isEmpty)
        #expect(detect(transactions, existing: ["Spotify"]).count == 2)
    }

    // MARK: - Rekkefølge og utkast

    @Test func highConfidenceComesFirstThenByName() {
        let medium = Support.monthly("Aaaservice AB", amounts: [100, 100, 100], from: day(2026, 6, 10))
        let highB = Support.monthly("Zzzservice AB", amounts: [100, 100, 100, 100], from: day(2026, 6, 11))
        let highA = Support.monthly("Mmmservice AB", amounts: [100, 100, 100, 100], from: day(2026, 6, 12))
        let suggestions = detect(medium + highB + highA)
        #expect(suggestions.map(\.name) == ["Mmmservice AB", "Zzzservice AB", "Aaaservice AB"])
        #expect(suggestions.map(\.confidence) == [.high, .high, .medium])
    }

    @Test func theDraftIsFilledFromTheSuggestionAndTheCatalog() {
        let transactions = Support.monthly("NETFLIX.COM", amounts: [149, 149, 149], from: day(2026, 6, 14))
        let suggestion = detect(transactions).first
        let draft = suggestion?.draft
        #expect(draft?.source == .bankStatement)
        #expect(draft?.name == "Netflix")
        #expect(draft?.price == 149)
        #expect(draft?.currencyCode == "NOK")
        #expect(draft?.interval == .monthly)
        #expect(draft?.kind == .streaming)
        #expect(draft?.catalogServiceID == "netflix")
        #expect(draft?.cancelURLString == "https://example.com/avslutt")
        #expect(draft?.nextRenewalDate == suggestion?.nextExpectedDate)
    }

    @Test func theDraftForAnUnknownMerchantOnlyHasWhatTheStatementShows() {
        let transactions = Support.monthly("Fooservice AB", amounts: [100, 100, 100], from: day(2026, 6, 10))
        let draft = detect(transactions).first?.draft
        #expect(draft?.name == "Fooservice AB")
        #expect(draft?.kind == nil)
        #expect(draft?.catalogServiceID == nil)
        #expect(draft?.symbolName == nil)
    }

    @Test func makeSubscriptionFollowsTheDraft() {
        let transactions = Support.monthly("NETFLIX.COM", amounts: [149, 149, 149], from: day(2026, 6, 14))
        let subscription = detect(transactions).first?.makeSubscription()
        #expect(subscription?.name == "Netflix")
        #expect(subscription?.price == 149)
        #expect(subscription?.currencyCode == "NOK")
        #expect(subscription?.interval == .monthly)
        #expect(subscription?.kind == .streaming)
        #expect(subscription?.cancelURLString == "https://example.com/avslutt")
    }
}

@MainActor
struct SubscriptionNameMatcherTests {

    @Test(arguments: [
        ("Telenor", "TELENOR NORGE AS"),
        ("telenor", "Telenor Norge"),
        ("Fitness24Seven", "Fitness24seven AB 12345"),
        ("Gjensidige", "GJENSIDIGE FORSIKRING ASA"),
        ("Spotify", "SPOTIFYSE"),
        ("Netflix", "NETFLIX.COM"),
        ("Åsane Treningssenter", "ASANE TRENINGSSENTER AS"),
        ("Telenor Mobil", "Telenor Norge AS")
    ])
    func similarNamesMatch(first: String, second: String) {
        #expect(SubscriptionNameMatcher.matches(first, second))
        #expect(SubscriptionNameMatcher.matches(second, first))
    }

    @Test(arguments: [
        ("Telenor", "Telia"),
        ("Apple Music", "Apple One"),
        ("Max", "Maxbo"),
        ("", "Telenor"),
        ("AS", "Telenor AS")
    ])
    func differentNamesDoNotMatch(first: String, second: String) {
        #expect(!SubscriptionNameMatcher.matches(first, second))
    }
}
