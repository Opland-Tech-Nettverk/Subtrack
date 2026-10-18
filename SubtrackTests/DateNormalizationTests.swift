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

    private var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    /// Eldre datoer i testene har sekunder, så de aldri havner på et kvarter ved et uhell
    /// (`RenewalCalculator.isOnQuarterHour`) og slutter å prøve ryddingen.
    private func osloDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        oslo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    @Test func movesDatesNearMidnightToNoonTheSameDay() {
        let lateEvening = osloDate(2026, 1, 15, 23, 1, 17)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: lateEvening, trialEndDate: lateEvening)

        subscription.normalizeStoredDates(calendar: oslo)

        let noon = osloDate(2026, 1, 15, 12, 0)
        #expect(subscription.nextRenewalDate == noon)
        #expect(subscription.billingAnchorDate == noon)
        #expect(subscription.trialEndDate == noon)
    }

    @Test func leavesDaytimeDatesUntouched() {
        // Sekunder med vilje, så datoen ikke ligger på et kvarter og faktisk prøves mot vinduet.
        let afternoon = osloDate(2026, 1, 15, 14, 3, 27)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: afternoon, trialEndDate: afternoon)

        subscription.normalizeStoredDates(calendar: oslo)

        #expect(subscription.nextRenewalDate == afternoon)
        #expect(subscription.billingAnchorDate == afternoon)
        #expect(subscription.trialEndDate == afternoon)
    }

    @Test func leavesMissingAnchorAndCancelledDateAlone() {
        // Abonnement lagret før ankerdatoen fantes.
        let subscription = Subscription(name: "Spotify", price: 129, nextRenewalDate: osloDate(2026, 1, 15, 0, 41, 32))
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
            nextRenewalDate: osloDate(2026, 1, 31, 23, 1, 17)
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
        // fornyelsen 28. feb før `nextRenewalDate` kl. 17:31 og ville blitt hoppet over.
        let subscription = Subscription(
            name: "Nettsky",
            price: 29,
            billingInterval: .monthly,
            nextRenewalDate: osloDate(2026, 2, 28, 17, 31, 5)
        )
        subscription.billingAnchorDate = osloDate(2026, 1, 31, 18, 31, 5)

        subscription.normalizeStoredDates(calendar: oslo)

        #expect(subscription.nextRenewalDate == osloDate(2026, 2, 28, 12, 0))
        #expect(subscription.billingAnchorDate == osloDate(2026, 1, 31, 12, 0))
        #expect(subscription.upcomingRenewalDates(count: 2, calendar: oslo) == [
            osloDate(2026, 2, 28, 12, 0),
            osloDate(2026, 3, 31, 12, 0)
        ])
    }

    @Test func movesQuarterHourRenewalTogetherWithLegacyAnchor() {
        // `nextRenewalDate` ligger på et kvarter og avgjør derfor ikke om datoene flyttes.
        // Ankeret er en eldre dato utenfor vinduet, så begge flyttes likevel til kl. 12 -
        // ellers ville fornyelsen 28. feb kl. 12 havnet før 17:30 og blitt hoppet over.
        let subscription = Subscription(
            name: "Nettsky",
            price: 29,
            billingInterval: .monthly,
            nextRenewalDate: osloDate(2026, 2, 28, 17, 30)
        )
        subscription.billingAnchorDate = osloDate(2026, 1, 31, 18, 31, 5)

        subscription.normalizeStoredDates(calendar: oslo)

        #expect(subscription.nextRenewalDate == osloDate(2026, 2, 28, 12, 0))
        #expect(subscription.billingAnchorDate == osloDate(2026, 1, 31, 12, 0))
        #expect(subscription.upcomingRenewalDates(count: 2, calendar: oslo) == [
            osloDate(2026, 2, 28, 12, 0),
            osloDate(2026, 3, 31, 12, 0)
        ])
    }

    @Test func leavesDatesOnAQuarterHourUntouched() {
        // 23:00:00 ligger utenfor vinduet, men på et kvarter: datoen regnes som allerede
        // satt til kl. 12 i en annen tidssone (23:00 i Oslo er 12:00 på Hawaii samme dag)
        // og skal ikke flyttes.
        let quarterHour = osloDate(2026, 1, 15, 23, 0)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: quarterHour, trialEndDate: quarterHour)

        subscription.normalizeStoredDates(calendar: oslo)

        #expect(subscription.nextRenewalDate == quarterHour)
        #expect(subscription.billingAnchorDate == quarterHour)
        #expect(subscription.trialEndDate == quarterHour)
    }

    @Test func leavesNoonFromAnotherTimeZoneUntouched() {
        // Lagret av skjemaet i Tokyo: 12:00 Tokyo er 04:00 i Oslo, utenfor vinduet.
        let tokyoNoon = RenewalCalculator.normalizedToNoon(
            tokyo.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 9, minute: 41, second: 17))!,
            calendar: tokyo
        )
        #expect(oslo.component(.hour, from: tokyoNoon) == 4)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: tokyoNoon, trialEndDate: tokyoNoon)

        subscription.normalizeStoredDates(calendar: oslo)

        #expect(subscription.nextRenewalDate == tokyoNoon)
        #expect(subscription.billingAnchorDate == tokyoNoon)
        #expect(subscription.trialEndDate == tokyoNoon)
    }

    @Test func trialEndOnAQuarterHourIsSkippedOnItsOwn() {
        // Prøveperioden vurderes for seg: den ligger på et kvarter og røres ikke, mens
        // fornyelsen er en eldre dato og flyttes.
        let legacy = osloDate(2026, 1, 15, 23, 1, 17)
        let trialEnd = osloDate(2026, 1, 20, 23, 0)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: legacy, trialEndDate: trialEnd)

        subscription.normalizeStoredDates(calendar: oslo)

        let noon = osloDate(2026, 1, 15, 12, 0)
        #expect(subscription.nextRenewalDate == noon)
        #expect(subscription.billingAnchorDate == noon)
        #expect(subscription.trialEndDate == trialEnd)
    }

    @Test func secondPassChangesNothing() {
        let lateEvening = osloDate(2026, 1, 15, 22, 8, 43)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: lateEvening, trialEndDate: lateEvening)
        subscription.normalizeStoredDates(calendar: oslo)
        let firstPass = [subscription.nextRenewalDate, subscription.billingAnchorDate, subscription.trialEndDate]

        subscription.normalizeStoredDates(calendar: oslo)

        #expect([subscription.nextRenewalDate, subscription.billingAnchorDate, subscription.trialEndDate] == firstPass)
    }
}
