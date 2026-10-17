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

    @Test func renewalReminderReportsWhetherItFellBack() {
        let preferred = RenewalCalculator.reminderDate(
            forRenewal: date(2026, 5, 15),
            preferredDaysBefore: 3,
            after: dateTime(2026, 5, 1, 12),
            calendar: calendar
        )
        #expect(preferred?.date == dateTime(2026, 5, 12, 9))
        #expect(preferred?.isFallback == false)

        let fallback = RenewalCalculator.reminderDate(
            forRenewal: date(2026, 5, 15),
            preferredDaysBefore: 3,
            after: dateTime(2026, 5, 13, 10),
            calendar: calendar
        )
        #expect(fallback?.date == dateTime(2026, 5, 14, 9))
        #expect(fallback?.isFallback == true)
    }

    // MARK: - Klokkeslett midt på dagen

    private var oslo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    private func osloDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        oslo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func normalizedToNoonKeepsTheDayLateInTheEvening() {
        let normalized = RenewalCalculator.normalizedToNoon(osloDate(2026, 5, 15, 23, 30), calendar: oslo)
        #expect(normalized == osloDate(2026, 5, 15, 12, 0))
    }

    @Test func normalizedToNoonKeepsTheDayJustAfterMidnight() {
        let normalized = RenewalCalculator.normalizedToNoon(osloDate(2026, 5, 15, 0, 15), calendar: oslo)
        #expect(normalized == osloDate(2026, 5, 15, 12, 0))
    }

    @Test func normalizedToNoonKeepsTheDayWhenDaylightSavingChanges() {
        // Sommertid starter 29. mars og slutter 25. oktober 2026 i Norge.
        for (month, day) in [(3, 29), (10, 25)] {
            for (hour, minute) in [(0, 15), (23, 30)] {
                let original = osloDate(2026, month, day, hour, minute)
                let normalized = RenewalCalculator.normalizedToNoon(original, calendar: oslo)
                #expect(normalized == osloDate(2026, month, day, 12, 0))
                #expect(oslo.isDate(normalized, inSameDayAs: original))
                #expect(oslo.component(.hour, from: normalized) == 12)
            }
        }
    }

    // MARK: - Klokkeslett nær midnatt

    private var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    @Test(arguments: [(0, 41), (5, 59), (18, 0), (23, 1)] as [(Int, Int)])
    func normalizedToNoonIfNearMidnightMovesNightTimesToNoonTheSameDay(hour: Int, minute: Int) {
        let original = osloDate(2026, 1, 15, hour, minute)
        let normalized = RenewalCalculator.normalizedToNoonIfNearMidnight(original, calendar: oslo)
        #expect(normalized == osloDate(2026, 1, 15, 12, 0))
    }

    @Test(arguments: [(6, 0), (12, 0), (14, 0), (17, 59)] as [(Int, Int)])
    func normalizedToNoonIfNearMidnightLeavesDaytimeUnchanged(hour: Int, minute: Int) {
        let original = osloDate(2026, 1, 15, hour, minute)
        #expect(RenewalCalculator.normalizedToNoonIfNearMidnight(original, calendar: oslo) == original)
    }

    @Test func normalizedToNoonIfNearMidnightIsIdempotent() {
        for (hour, minute) in [(0, 41), (5, 59), (6, 0), (17, 59), (18, 0), (22, 8), (23, 1)] {
            let once = RenewalCalculator.normalizedToNoonIfNearMidnight(osloDate(2026, 1, 15, hour, minute), calendar: oslo)
            let twice = RenewalCalculator.normalizedToNoonIfNearMidnight(once, calendar: oslo)
            #expect(twice == once)
        }
    }

    @Test func normalizedToNoonIfNearMidnightDoesNotPingPongBetweenTimeZones() {
        // Vintertid (Oslo UTC+1, London UTC+0) og sommertid (Oslo UTC+2, London UTC+1).
        for (month, hour, minute) in [(1, 23, 1), (1, 0, 41), (7, 23, 1), (7, 0, 41)] {
            let normalizedInOslo = RenewalCalculator.normalizedToNoonIfNearMidnight(
                osloDate(2026, month, 15, hour, minute),
                calendar: oslo
            )
            #expect(normalizedInOslo == osloDate(2026, month, 15, 12, 0))
            // 12:00 i Oslo er 11:00 i London - innenfor vinduet, så London lar datoen være.
            #expect(RenewalCalculator.normalizedToNoonIfNearMidnight(normalizedInOslo, calendar: london) == normalizedInOslo)
            #expect(london.component(.hour, from: normalizedInOslo) == 11)

            // Og motsatt vei: 12:00 i London er 13:00 i Oslo.
            let normalizedInLondon = RenewalCalculator.normalizedToNoon(normalizedInOslo, calendar: london)
            #expect(RenewalCalculator.normalizedToNoonIfNearMidnight(normalizedInLondon, calendar: oslo) == normalizedInLondon)
        }
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
