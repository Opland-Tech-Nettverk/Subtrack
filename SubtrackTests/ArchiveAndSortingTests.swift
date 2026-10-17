import Foundation
import Testing
@testable import Subtrack

@MainActor
struct ArchiveAndSortingTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Besparelse

    @Test func savingsSpreadsTheYearlyCostOverDays() {
        let saved = RenewalCalculator.savings(
            yearlyCost: 365,
            since: date(2026, 1, 1),
            now: date(2026, 1, 31),
            calendar: calendar
        )
        #expect(saved == 30)
    }

    @Test func savingsIsZeroOnTheDayOfCancellationAndForFutureDates() {
        #expect(RenewalCalculator.savings(yearlyCost: 1200, since: date(2026, 5, 1), now: date(2026, 5, 1), calendar: calendar) == 0)
        #expect(RenewalCalculator.savings(yearlyCost: 1200, since: date(2026, 6, 1), now: date(2026, 5, 1), calendar: calendar) == 0)
    }

    @Test func cancelledSubscriptionSavesItsShareAndIsNotBilled() {
        let subscription = Subscription(name: "Familie", price: 365, billingInterval: .yearly, splitCount: 1)
        subscription.cancelledDate = date(2026, 3, 1)

        #expect(subscription.isCancelled)
        #expect(!subscription.isBilling)
        #expect(subscription.savedSinceCancellation(now: date(2026, 3, 11), calendar: calendar) == 10)
    }

    @Test func notCancelledSubscriptionHasNoSavings() {
        let subscription = Subscription(name: "Netflix", price: 149)
        #expect(subscription.isBilling)
        #expect(subscription.savedSinceCancellation() == 0)
    }

    @Test func cancelledSubscriptionsGetNoReminders() {
        let subscription = Subscription(
            name: "Avsluttet",
            price: 100,
            nextRenewalDate: Date.now.addingTimeInterval(10 * 86_400)
        )
        subscription.cancelledDate = .now
        #expect(NotificationScheduler.plannedReminders(for: [subscription]).isEmpty)
    }

    @Test func advanceRenewalDateIfPastMovesOnlyPastDates() {
        let past = Subscription(name: "Gammel", price: 100, billingInterval: .monthly, nextRenewalDate: date(2026, 1, 15))
        past.advanceRenewalDateIfPast(now: date(2026, 3, 20), calendar: calendar)
        #expect(past.nextRenewalDate == date(2026, 4, 15))

        let future = Subscription(name: "Ny", price: 100, billingInterval: .monthly, nextRenewalDate: date(2026, 4, 1))
        future.advanceRenewalDateIfPast(now: date(2026, 3, 20), calendar: calendar)
        #expect(future.nextRenewalDate == date(2026, 4, 1))
    }

    // MARK: - Sortering

    private var samples: [Subscription] {
        [
            Subscription(name: "spotify", price: 129, nextRenewalDate: date(2026, 5, 3), category: .musikk),
            Subscription(name: "Adobe", price: 699, nextRenewalDate: date(2026, 5, 10), category: .programvare),
            Subscription(name: "Netflix", price: 149, nextRenewalDate: date(2026, 5, 1), category: .streaming),
            Subscription(name: "Apple Music", price: 129, nextRenewalDate: date(2026, 5, 2), category: .musikk)
        ]
    }

    private func names(_ order: SubscriptionSortOrder, costs: ((Subscription) -> Decimal?)? = nil) -> [String] {
        order.sorted(samples, monthlyCost: costs ?? { $0.monthlyCost }).map(\.name)
    }

    @Test func sortsByNextRenewal() {
        #expect(names(.renewal) == ["Netflix", "Apple Music", "spotify", "Adobe"])
    }

    @Test func sortsByPriceHighestFirstWithRenewalAsTieBreaker() {
        #expect(names(.price) == ["Adobe", "Netflix", "Apple Music", "spotify"])
    }

    @Test func sortsByNameIgnoringCase() {
        #expect(names(.name) == ["Adobe", "Apple Music", "Netflix", "spotify"])
    }

    @Test func sortsByCategoryThenRenewal() {
        // Musikk < Programvare < Streaming alfabetisk.
        #expect(names(.category) == ["Apple Music", "spotify", "Adobe", "Netflix"])
    }

    @Test func priceSortPutsSubscriptionsWithoutRateLast() {
        let result = names(.price) { $0.name == "Adobe" ? nil : $0.monthlyCost }
        #expect(result.last == "Adobe")
    }

    // MARK: - Søk

    @Test(arguments: [
        ("net", true),
        ("NETFLIX", true),
        ("streaming", true),
        ("Strøm", false),
        ("", true),
        ("   ", true),
        ("spotify", false)
    ])
    func searchMatchesNameAndCategory(query: String, expected: Bool) {
        let subscription = Subscription(name: "Netflix", price: 149, category: .streaming)
        #expect(subscription.matches(searchText: query) == expected)
    }
}
