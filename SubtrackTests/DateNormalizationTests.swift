import Foundation
import Testing
@testable import Subtrack

@MainActor
struct DateNormalizationTests {

    private var oslo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    private func osloDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        oslo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func movesDatesNearMidnightToNoonTheSameDay() {
        let lateEvening = osloDate(2026, 1, 15, 23, 1)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: lateEvening, trialEndDate: lateEvening)

        subscription.normalizeStoredDates(calendar: oslo)

        let noon = osloDate(2026, 1, 15, 12, 0)
        #expect(subscription.nextRenewalDate == noon)
        #expect(subscription.billingAnchorDate == noon)
        #expect(subscription.trialEndDate == noon)
    }

    @Test func leavesDaytimeDatesUntouched() {
        let afternoon = osloDate(2026, 1, 15, 14, 0)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: afternoon, trialEndDate: afternoon)

        subscription.normalizeStoredDates(calendar: oslo)

        #expect(subscription.nextRenewalDate == afternoon)
        #expect(subscription.billingAnchorDate == afternoon)
        #expect(subscription.trialEndDate == afternoon)
    }

    @Test func leavesMissingAnchorAndCancelledDateAlone() {
        // Abonnement lagret før ankerdatoen fantes.
        let subscription = Subscription(name: "Spotify", price: 129, nextRenewalDate: osloDate(2026, 1, 15, 0, 41))
        subscription.billingAnchorDate = nil
        let cancelled = osloDate(2026, 1, 10, 23, 30)
        subscription.cancelledDate = cancelled

        subscription.normalizeStoredDates(calendar: oslo)

        #expect(subscription.nextRenewalDate == osloDate(2026, 1, 15, 12, 0))
        #expect(subscription.billingAnchorDate == nil)
        #expect(subscription.trialEndDate == nil)
        #expect(subscription.cancelledDate == cancelled)
    }

    @Test func endOfMonthRhythmSurvivesNormalization() {
        let subscription = Subscription(
            name: "Nettsky",
            price: 29,
            billingInterval: .monthly,
            nextRenewalDate: osloDate(2026, 1, 31, 23, 1)
        )

        subscription.normalizeStoredDates(calendar: oslo)

        #expect(subscription.upcomingRenewalDates(count: 3, calendar: oslo) == [
            osloDate(2026, 1, 31, 12, 0),
            osloDate(2026, 2, 28, 12, 0),
            osloDate(2026, 3, 31, 12, 0)
        ])
    }

    @Test func movesAnchorAndNextRenewalTogether() {
        // Bare ankeret ligger utenfor vinduet. Flyttes det alene til kl. 12, havner
        // fornyelsen 28. feb før `nextRenewalDate` kl. 17:30 og ville blitt hoppet over.
        let subscription = Subscription(
            name: "Nettsky",
            price: 29,
            billingInterval: .monthly,
            nextRenewalDate: osloDate(2026, 2, 28, 17, 30)
        )
        subscription.billingAnchorDate = osloDate(2026, 1, 31, 18, 30)

        subscription.normalizeStoredDates(calendar: oslo)

        #expect(subscription.nextRenewalDate == osloDate(2026, 2, 28, 12, 0))
        #expect(subscription.billingAnchorDate == osloDate(2026, 1, 31, 12, 0))
        #expect(subscription.upcomingRenewalDates(count: 2, calendar: oslo) == [
            osloDate(2026, 2, 28, 12, 0),
            osloDate(2026, 3, 31, 12, 0)
        ])
    }

    @Test func secondPassChangesNothing() {
        let lateEvening = osloDate(2026, 1, 15, 22, 8)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: lateEvening, trialEndDate: lateEvening)
        subscription.normalizeStoredDates(calendar: oslo)
        let firstPass = [subscription.nextRenewalDate, subscription.billingAnchorDate, subscription.trialEndDate]

        subscription.normalizeStoredDates(calendar: oslo)

        #expect([subscription.nextRenewalDate, subscription.billingAnchorDate, subscription.trialEndDate] == firstPass)
    }
}
