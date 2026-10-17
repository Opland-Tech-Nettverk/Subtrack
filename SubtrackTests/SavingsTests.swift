import Foundation
import Testing
@testable import Subtrack

@MainActor
struct SavingsTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// 365 kr i året, så hver dag tilsvarer 1 kr.
    private func archived(cancelled: Date, trialEnd: Date? = nil, isActive: Bool = true) -> Subscription {
        let subscription = Subscription(
            name: "Test",
            price: 365,
            billingInterval: .yearly,
            trialEndDate: trialEnd,
            isActive: isActive
        )
        subscription.cancelledDate = cancelled
        return subscription
    }

    @Test func billingSubscriptionSavesFromTheCancellationDate() {
        let subscription = archived(cancelled: date(2026, 3, 1))

        #expect(subscription.savedSinceCancellation(now: date(2026, 3, 11), calendar: calendar) == 10)
        #expect(subscription.projectedYearlySavings == 365)
    }

    @Test func pausedSubscriptionSavesNothingWhenArchived() {
        // Pauset før arkivering: brukeren betalte ingenting fra før.
        let subscription = archived(cancelled: date(2026, 3, 1), isActive: false)

        #expect(subscription.savedSinceCancellation(now: date(2026, 6, 1), calendar: calendar) == 0)
        #expect(subscription.projectedYearlySavings == 0)
    }

    @Test func cancellingDuringTheTrialSavesFromTheTrialEnd() {
        let subscription = archived(cancelled: date(2026, 3, 1), trialEnd: date(2026, 3, 20))

        #expect(subscription.savedSinceCancellation(now: date(2026, 3, 11), calendar: calendar) == 0)
        #expect(subscription.savedSinceCancellation(now: date(2026, 3, 20), calendar: calendar) == 0)
        #expect(subscription.savedSinceCancellation(now: date(2026, 3, 30), calendar: calendar) == 10)
        #expect(subscription.projectedYearlySavings == 365)
    }

    @Test func trialThatEndedBeforeCancellationDoesNotDelaySavings() {
        let subscription = archived(cancelled: date(2026, 3, 1), trialEnd: date(2026, 2, 1))

        #expect(subscription.savedSinceCancellation(now: date(2026, 3, 11), calendar: calendar) == 10)
    }

    @Test func notCancelledSubscriptionProjectsNoSavings() {
        let subscription = Subscription(name: "Netflix", price: 149)

        #expect(subscription.projectedYearlySavings == 0)
    }
}
