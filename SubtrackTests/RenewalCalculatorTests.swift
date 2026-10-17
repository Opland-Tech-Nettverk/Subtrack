import Foundation
import Testing
@testable import Subtrack

struct RenewalCalculatorTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dateTime(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func monthlyCostForMonthlySubscription() {
        let cost = RenewalCalculator.monthlyCost(price: 99, interval: .monthly)
        #expect(cost == 99)
    }

    @Test func monthlyCostForYearlySubscription() {
        let cost = RenewalCalculator.monthlyCost(price: 1200, interval: .yearly)
        #expect(cost == 100)
    }

    @Test func monthlyCostForWeeklySubscription() {
        let cost = RenewalCalculator.monthlyCost(price: 60, interval: .weekly)
        #expect(cost == 260)
    }

    @Test func yearlyCostForMonthlySubscription() {
        let cost = RenewalCalculator.yearlyCost(price: 99, interval: .monthly)
        #expect(cost == 1188)
    }

    @Test func yearlyCostForQuarterlySubscription() {
        let cost = RenewalCalculator.yearlyCost(price: 300, interval: .quarterly)
        #expect(cost == 1200)
    }

    @Test(arguments: [(300, 1, 300), (300, 3, 100), (279, 2, 139.5)] as [(Decimal, Int, Decimal)])
    func shareSplitsPriceEqually(price: Decimal, splitCount: Int, expected: Decimal) {
        #expect(RenewalCalculator.share(of: price, splitCount: splitCount) == expected)
    }

    @Test func shareTreatsInvalidSplitCountAsNotShared() {
        #expect(RenewalCalculator.share(of: 149, splitCount: 0) == 149)
        #expect(RenewalCalculator.share(of: 149, splitCount: -2) == 149)
    }

    @MainActor
    @Test func sharedSubscriptionCostsUseMyShare() {
        let subscription = Subscription(name: "Familie", price: 300, billingInterval: .monthly, splitCount: 3)
        #expect(subscription.isShared)
        #expect(subscription.myShare == 100)
        #expect(subscription.monthlyCost == 100)
        #expect(subscription.yearlyCost == 1200)
    }

    @Test func advanceToFutureSkipsMultipleMissedMonths() {
        let next = RenewalCalculator.advanceToFuture(
            anchor: date(2026, 1, 15),
            interval: .monthly,
            referenceDate: date(2026, 4, 1),
            calendar: calendar
        )
        #expect(next == date(2026, 4, 15))
    }

    @Test func advanceToFutureKeepsDateWhenAlreadyInFuture() {
        let futureRenewal = date(2026, 6, 1)
        let next = RenewalCalculator.advanceToFuture(
            anchor: futureRenewal,
            interval: .monthly,
            referenceDate: date(2026, 1, 1),
            calendar: calendar
        )
        #expect(next == futureRenewal)
    }

    @Test func advanceToFutureHandlesYearlyInterval() {
        let next = RenewalCalculator.advanceToFuture(
            anchor: date(2023, 3, 10),
            interval: .yearly,
            referenceDate: date(2026, 1, 1),
            calendar: calendar
        )
        #expect(next == date(2026, 3, 10))
    }

    @Test func endOfMonthAnchorReturnsToThe31stAfterFebruary() {
        let dates = RenewalCalculator.upcomingRenewalDates(
            anchor: date(2026, 1, 31),
            interval: .monthly,
            onOrAfter: date(2026, 1, 31),
            count: 4,
            calendar: calendar
        )
        // Hver fornyelse regnes fra ankeret, så februar klemmes til 28. uten å smitte videre.
        #expect(dates == [date(2026, 1, 31), date(2026, 2, 28), date(2026, 3, 31), date(2026, 4, 30)])
    }

    @Test func advanceToFutureFromEndOfMonthAnchorDoesNotDrift() {
        let next = RenewalCalculator.advanceToFuture(
            anchor: date(2026, 1, 31),
            interval: .monthly,
            referenceDate: date(2026, 3, 15),
            calendar: calendar
        )
        #expect(next == date(2026, 3, 31))
    }

    @Test func upcomingRenewalDatesStartAtCurrentRenewal() {
        // Ankeret er 31. jan, men neste fornyelse er allerede flyttet til 28. feb.
        let dates = RenewalCalculator.upcomingRenewalDates(
            anchor: date(2026, 1, 31),
            interval: .monthly,
            onOrAfter: date(2026, 2, 28),
            count: 2,
            calendar: calendar
        )
        #expect(dates == [date(2026, 2, 28), date(2026, 3, 31)])
    }

    @Test func upcomingRenewalDatesReturnsEmptyForZeroCount() {
        let dates = RenewalCalculator.upcomingRenewalDates(
            anchor: date(2026, 1, 1),
            interval: .weekly,
            onOrAfter: date(2026, 1, 1),
            count: 0,
            calendar: calendar
        )
        #expect(dates.isEmpty)
    }

    @Test func trialReminderUsesPreferredDaysWhenPossible() {
        let reminder = RenewalCalculator.trialReminderDate(
            trialEndDate: date(2026, 5, 15),
            preferredDaysBefore: 3,
            after: dateTime(2026, 5, 1, 12),
            calendar: calendar
        )
        #expect(reminder == dateTime(2026, 5, 12, 9))
    }

    @Test func trialReminderFallsBackToTheDayBefore() {
        let reminder = RenewalCalculator.trialReminderDate(
            trialEndDate: date(2026, 5, 15),
            preferredDaysBefore: 3,
            after: dateTime(2026, 5, 13, 10),
            calendar: calendar
        )
        #expect(reminder == dateTime(2026, 5, 14, 9))
    }

    @Test func trialReminderFallsBackToTheSameMorning() {
        let reminder = RenewalCalculator.trialReminderDate(
            trialEndDate: date(2026, 5, 15),
            preferredDaysBefore: 3,
            after: dateTime(2026, 5, 14, 10),
            calendar: calendar
        )
        #expect(reminder == dateTime(2026, 5, 15, 9))
    }

    @Test func trialReminderIsNilWhenEveryOptionHasPassed() {
        let reminder = RenewalCalculator.trialReminderDate(
            trialEndDate: date(2026, 5, 15),
            preferredDaysBefore: 3,
            after: dateTime(2026, 5, 15, 10),
            calendar: calendar
        )
        #expect(reminder == nil)
    }

    @Test func reminderDateSubtractsDaysAndSetsHour() {
        let renewal = date(2026, 5, 15)
        let reminder = RenewalCalculator.reminderDate(
            nextRenewalDate: renewal,
            daysBefore: 3,
            hour: 9,
            calendar: calendar
        )
        #expect(reminder == dateTime(2026, 5, 12, 9))
    }

    @Test func reminderDateCrossesMonthBoundary() {
        let renewal = date(2026, 3, 1)
        let reminder = RenewalCalculator.reminderDate(
            nextRenewalDate: renewal,
            daysBefore: 3,
            hour: 9,
            calendar: calendar
        )
        #expect(reminder == dateTime(2026, 2, 26, 9))
    }
}
