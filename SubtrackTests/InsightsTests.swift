import Foundation
import Testing
@testable import Subtrack

/// Tester for logikken bak oversikten, kalenderen og statistikken: gruppering etter tid,
/// neste 30 dager, kostnad framover, kalenderrutenett, fremdrift og kategoriandeler.
@MainActor
struct InsightsTests {

    /// Mandag som første ukedag, som i Norge. UTC gjør testene uavhengige av maskinens tidssone.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Kl. 12, slik fornyelsesdatoer lagres i appen.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Onsdag 4. november 2026. Uka går fra mandag 2. til søndag 8., og måneden slutter 30.
    private var now: Date { date(2026, 11, 4, hour: 9) }

    private func subscription(
        _ name: String,
        price: Decimal = 100,
        currency: String = "NOK",
        interval: BillingInterval = .monthly,
        renews: Date,
        split: Int = 1,
        isActive: Bool = true
    ) -> Subscription {
        Subscription(
            name: name,
            price: price,
            currencyCode: currency,
            billingInterval: interval,
            nextRenewalDate: renews,
            isActive: isActive,
            splitCount: split
        )
    }

    private let onlyNOK: (Decimal, String) -> Decimal? = { amount, code in code == "NOK" ? amount : nil }

    // MARK: - Gruppering

    @Test func groupsRenewalsByWeekMonthAndLater() {
        func group(_ day: Date) -> RenewalGroup {
            RenewalGrouping.group(forRenewalOn: day, now: now, calendar: calendar)
        }
        #expect(group(date(2026, 11, 4)) == .thisWeek)
        #expect(group(date(2026, 11, 8)) == .thisWeek)
        #expect(group(date(2026, 11, 9)) == .thisMonth)
        #expect(group(date(2026, 11, 30)) == .thisMonth)
        #expect(group(date(2026, 12, 1)) == .later)
        #expect(group(date(2027, 3, 1)) == .later)
    }

    @Test func overdueRenewalsCountAsThisWeek() {
        #expect(RenewalGrouping.group(forRenewalOn: date(2026, 10, 20), now: now, calendar: calendar) == .thisWeek)
    }

    @Test func pausedSubscriptionsGetTheirOwnGroup() {
        let paused = subscription("Pauset", renews: date(2026, 11, 5), isActive: false)
        #expect(RenewalGrouping.group(for: paused, now: now, calendar: calendar) == .paused)
    }

    @Test func sectionsKeepOrderAndSkipEmptyGroups() {
        let a = subscription("A", renews: date(2026, 11, 5))
        let b = subscription("B", renews: date(2026, 11, 7))
        let c = subscription("C", renews: date(2026, 12, 20))
        let d = subscription("D", renews: date(2026, 11, 6), isActive: false)

        let sections = RenewalGrouping.sections([a, b, c, d], now: now, calendar: calendar)

        #expect(sections.map(\.group) == [.thisWeek, .later, .paused])
        #expect(sections[0].subscriptions.map(\.name) == ["A", "B"])
        #expect(sections[1].subscriptions.map(\.name) == ["C"])
        #expect(sections[2].subscriptions.map(\.name) == ["D"])
    }

    // MARK: - Neste 30 dager

    @Test func stripCoversThirtyDaysInWeeksOfSeven() {
        let strip = ChargeSchedule.upcomingStrip(
            subscriptions: [], now: now, calendar: calendar, convert: onlyNOK
        )
        #expect(strip.days.count == 30)
        #expect(strip.weeks.map { $0.days.count } == [7, 7, 7, 7, 2])
        #expect(strip.days.first?.date == calendar.startOfDay(for: now))
        #expect(strip.chargeCount == 0)
    }

    @Test func stripPlacesChargesOnTheirDayAndSumsPerWeek() {
        let monthly = subscription("Månedlig", price: 100, renews: date(2026, 11, 10))
        let weekly = subscription("Ukentlig", price: 10, interval: .weekly, renews: date(2026, 11, 5))

        let strip = ChargeSchedule.upcomingStrip(
            subscriptions: [monthly, weekly], now: now, calendar: calendar, convert: onlyNOK
        )

        // Ukentlig: dag 1, 8, 15, 22 og 29. Månedlig: dag 6. Neste månedlige trekk ligger utenfor.
        #expect(strip.chargeCount == 6)
        #expect(strip.weeks.map(\.total) == [110, 10, 10, 10, 10])
        #expect(strip.total == 150)
        #expect(strip.days[6].charges.map(\.subscription.name) == ["Månedlig"])
        #expect(strip.days[0].hasCharges == false)
    }

    @Test func stripUsesTheUsersShareAndSkipsPausedAndUnconvertible() {
        let shared = subscription("Delt", price: 200, renews: date(2026, 11, 6), split: 2)
        let paused = subscription("Pauset", price: 500, renews: date(2026, 11, 6), isActive: false)
        let foreign = subscription("Utenlandsk", price: 20, currency: "USD", renews: date(2026, 11, 7))

        let strip = ChargeSchedule.upcomingStrip(
            subscriptions: [shared, paused, foreign], now: now, calendar: calendar, convert: onlyNOK
        )

        #expect(strip.total == 100)
        #expect(strip.excludedCount == 1)
        #expect(strip.chargeCount == 2)
    }

    @Test func stripIncludesTodayEvenWhenTheTimeHasPassed() {
        let today = subscription("I dag", renews: date(2026, 11, 4, hour: 8))
        let strip = ChargeSchedule.upcomingStrip(
            subscriptions: [today], now: now, calendar: calendar, convert: onlyNOK
        )
        #expect(strip.days[0].charges.count == 1)
    }

    @Test func trialEndIsMarkedOnTheCharge() {
        let trial = Subscription(
            name: "Prøve", price: 100, nextRenewalDate: date(2026, 11, 8), trialEndDate: date(2026, 11, 8)
        )
        let charges = ChargeSchedule.occurrences(
            of: [trial], from: now, through: date(2026, 12, 31), calendar: calendar
        )
        #expect(charges.first?.isTrialEnd == true)
        #expect(charges.dropFirst().allSatisfy { !$0.isTrialEnd })
    }

    // MARK: - Kostnad framover

    @Test func forwardCostSpansTwelveCalendarMonths() {
        let monthly = subscription("Månedlig", price: 100, renews: date(2026, 11, 10))
        let result = ForwardCost.months(of: [monthly], now: now, calendar: calendar, convert: onlyNOK)

        #expect(result.months.count == 12)
        #expect(result.months.first?.monthStart == date(2026, 11, 1, hour: 0))
        #expect(result.months.last?.monthStart == date(2027, 10, 1, hour: 0))
        #expect(result.months.allSatisfy { $0.total == 100 })
        #expect(result.total == 1200)
    }

    @Test func forwardCostCountsOnlyFromTodayInTheFirstMonth() {
        // Trukket 2. november, altså før i dag: bare de neste elleve trekkene teller.
        let monthly = subscription("Månedlig", price: 100, renews: date(2026, 11, 2))
        let result = ForwardCost.months(of: [monthly], now: now, calendar: calendar, convert: onlyNOK)

        #expect(result.months.first?.total == 0)
        #expect(result.months.dropFirst().allSatisfy { $0.total == 100 })
        #expect(result.total == 1100)
    }

    @Test func forwardCostShowsAnnualChargesAsPeaks() {
        let monthly = subscription("Månedlig", price: 100, renews: date(2026, 11, 10))
        let yearly = subscription("Årlig", price: 1200, interval: .yearly, renews: date(2026, 12, 15))
        let result = ForwardCost.months(of: [monthly, yearly], now: now, calendar: calendar, convert: onlyNOK)

        #expect(result.peak?.monthStart == date(2026, 12, 1, hour: 0))
        #expect(result.peak?.total == 1300)
        #expect(result.total == 2400)
    }

    @Test func forwardCostCountsUnconvertibleChargesAsExcluded() {
        let foreign = subscription("Utenlandsk", price: 20, currency: "USD", renews: date(2026, 11, 10))
        let result = ForwardCost.months(of: [foreign], now: now, calendar: calendar, convert: onlyNOK)
        #expect(result.total == 0)
        #expect(result.excludedCount == 12)
        #expect(result.peak == nil)
    }

    // MARK: - Kalender

    @Test func monthGridStartsOnMondayAndFillsWholeWeeks() {
        let november = MonthGrid.cells(for: date(2026, 11, 15), calendar: calendar)
        // 1. november 2026 er en søndag: seks tomme ruter foran, 30 dager, fylt til 42.
        #expect(november.count == 42)
        #expect(november.prefix(6).allSatisfy { $0 == nil })
        #expect(november[6] == calendar.startOfDay(for: date(2026, 11, 1)))
        #expect(november.compactMap { $0 }.count == 30)

        // 1. februar 2027 er en mandag og måneden har 28 dager: akkurat fire uker.
        let february = MonthGrid.cells(for: date(2027, 2, 10), calendar: calendar)
        #expect(february.count == 28)
        #expect(february.first! == calendar.startOfDay(for: date(2027, 2, 1)))
    }

    @Test func monthStartMovesByWholeMonths() {
        #expect(MonthGrid.monthStart(offsetBy: 0, from: now, calendar: calendar) == date(2026, 11, 1, hour: 0))
        #expect(MonthGrid.monthStart(offsetBy: 2, from: now, calendar: calendar) == date(2027, 1, 1, hour: 0))
        #expect(MonthGrid.monthStart(offsetBy: -1, from: now, calendar: calendar) == date(2026, 10, 1, hour: 0))
    }

    @Test func monthChargesCoverTheWholeMonthIncludingEarlierDays() {
        // Ankeret er 3. november, og trekket i dag (4.) og senere i måneden hører til måneden.
        let weekly = subscription("Ukentlig", price: 10, interval: .weekly, renews: date(2026, 11, 3))
        let charges = MonthGrid.charges(of: [weekly], inMonthOf: now, calendar: calendar)
        // 3., 10., 17. og 24. november.
        #expect(charges.count == 4)
        #expect(charges.first?.date == date(2026, 11, 3))
    }

    // MARK: - Fremdrift

    @Test func progressRunsFromPreviousChargeToTheNext() {
        // Forrige trekk 20. oktober, neste 20. november (31 dager), i dag 4. november (15 dager inne).
        let fraction = RenewalProgress.fraction(
            nextRenewal: date(2026, 11, 20), interval: .monthly, now: now, calendar: calendar
        )
        #expect(abs(fraction - 15.0 / 31.0) < 0.0001)
    }

    @Test func progressIsFullOnTheDayAndCappedWhenOverdue() {
        let onTheDay = RenewalProgress.fraction(
            nextRenewal: date(2026, 11, 4), interval: .monthly, now: now, calendar: calendar
        )
        let overdue = RenewalProgress.fraction(
            nextRenewal: date(2026, 11, 1), interval: .monthly, now: now, calendar: calendar
        )
        #expect(onTheDay == 1)
        #expect(overdue == 1)
    }

    @Test func progressIsNearZeroRightAfterACharge() {
        let fraction = RenewalProgress.fraction(
            nextRenewal: date(2026, 12, 3), interval: .monthly, now: now, calendar: calendar
        )
        // Forrige trekk 3. november, i dag 4. november: én dag av 30.
        #expect(abs(fraction - 1.0 / 30.0) < 0.0001)
    }

    // MARK: - Kategoriandeler

    @Test func sharesAddUpToExactlyOneHundredPercent() {
        let costs = [
            CategoryCost(category: .streaming, monthlyCost: 1),
            CategoryCost(category: .musikk, monthlyCost: 1),
            CategoryCost(category: .spill, monthlyCost: 1)
        ]
        let shares = CategoryBreakdown.shares(from: costs)
        #expect(shares.map(\.percent).reduce(0, +) == 100)
        #expect(shares.map(\.percent) == [34, 33, 33])
        #expect(shares.map(\.category) == [.streaming, .musikk, .spill])
    }

    @Test func sharesFollowTheCosts() {
        let costs = [
            CategoryCost(category: .streaming, monthlyCost: 300),
            CategoryCost(category: .musikk, monthlyCost: 100)
        ]
        #expect(CategoryBreakdown.shares(from: costs).map(\.percent) == [75, 25])
    }

    @Test func sharesAreZeroWithoutCosts() {
        #expect(CategoryBreakdown.shares(from: []).isEmpty)
        let zero = [CategoryCost(category: .annet, monthlyCost: 0)]
        #expect(CategoryBreakdown.shares(from: zero).map(\.percent) == [0])
    }

    // MARK: - Statistikk

    private let rates = ExchangeRates(base: "EUR", rates: ["NOK": 10, "USD": 1], rateDate: .now, fetchedAt: .now)

    @Test func mostExpensiveCanBeFilteredByCategory() {
        let viewModel = StatisticsViewModel(
            subscriptions: [
                Subscription(name: "Netflix", price: 149, category: .streaming),
                Subscription(name: "HBO", price: 100, category: .streaming),
                Subscription(name: "Adobe", price: 699, category: .programvare)
            ],
            targetCurrency: "NOK",
            rates: rates
        )
        #expect(viewModel.mostExpensiveSubscriptions(limit: 5, in: nil).map(\.name) == ["Adobe", "Netflix", "HBO"])
        #expect(viewModel.mostExpensiveSubscriptions(limit: 5, in: .streaming).map(\.name) == ["Netflix", "HBO"])
        #expect(viewModel.mostExpensiveSubscriptions(limit: 1, in: nil).map(\.name) == ["Adobe"])
        #expect(viewModel.mostExpensiveSubscriptions(limit: 5, in: .spill).isEmpty)
        // Den eksisterende egenskapen gir de fem dyreste.
        #expect(viewModel.mostExpensiveSubscriptions.count == 3)
    }

    @Test func categorySharesFollowTheViewModelCosts() {
        let viewModel = StatisticsViewModel(
            subscriptions: [
                Subscription(name: "Netflix", price: 300, category: .streaming),
                Subscription(name: "Spotify", price: 100, category: .musikk)
            ],
            targetCurrency: "NOK",
            rates: rates
        )
        #expect(viewModel.categoryShares.map(\.category) == [.streaming, .musikk])
        #expect(viewModel.categoryShares.map(\.percent) == [75, 25])
    }

    @Test func savingsSumsCancelledSubscriptionsInTheTargetCurrency() {
        let netflix = Subscription(name: "Netflix", price: 365, category: .streaming)
        netflix.cancelledDate = date(2026, 10, 5)
        let chatGPT = Subscription(name: "ChatGPT", price: 10, currencyCode: "USD", category: .ai)
        chatGPT.cancelledDate = date(2026, 10, 5)
        let active = Subscription(name: "Aktiv", price: 999)
        let paused = Subscription(name: "Pauset", price: 500, isActive: false)
        paused.cancelledDate = date(2026, 10, 5)

        let viewModel = StatisticsViewModel(
            subscriptions: [netflix, chatGPT, active, paused],
            targetCurrency: "NOK",
            rates: rates
        )
        let savings = viewModel.savings(now: date(2026, 11, 4), calendar: calendar)

        // Netflix: 365 per måned = 4 380 per år, 30 dager = 360. ChatGPT: 10 USD = 100 NOK per måned,
        // 1 200 NOK per år, 30 dager = 98,63. Pauset da det ble avsluttet: sparer ingenting.
        #expect(savings.cancelledCount == 3)
        #expect(abs(savings.yearly - 5580) < 0.001)
        #expect(savings.excludedCount == 0)
        #expect(savings.total > 458 && savings.total < 459)
    }

    @Test func chartAngleFindsTheCategoryUnderTheTap() {
        let costs = [
            CategoryCost(category: .streaming, monthlyCost: 300),
            CategoryCost(category: .musikk, monthlyCost: 100)
        ]
        #expect(CategoryBreakdown.category(atAngleValue: 0, in: costs) == .streaming)
        #expect(CategoryBreakdown.category(atAngleValue: 299, in: costs) == .streaming)
        #expect(CategoryBreakdown.category(atAngleValue: 350, in: costs) == .musikk)
        #expect(CategoryBreakdown.category(atAngleValue: 401, in: costs) == nil)
    }
}
