import Foundation
import Testing
@testable import Subtrack

@MainActor
struct NotificationSchedulerTests {

    private let now = Date.now

    private func subscription(daysUntilRenewal: Int, reminderDaysBefore: Int = 3, isActive: Bool = true) -> Subscription {
        Subscription(
            name: "Test \(daysUntilRenewal)",
            price: 100,
            billingInterval: .monthly,
            nextRenewalDate: now.addingTimeInterval(TimeInterval(daysUntilRenewal) * 86_400),
            isActive: isActive,
            reminderDaysBefore: reminderDaysBefore
        )
    }

    @Test func staysWithinBudgetAndKeepsTheNearestReminders() {
        // 25 abonnement x 6 fornyelser = 150 kandidater, langt over budsjettet.
        let subscriptions = (10..<35).map { subscription(daysUntilRenewal: $0) }

        let reminders = NotificationScheduler.plannedReminders(for: subscriptions, now: now, limit: 60)

        #expect(reminders.count == 60)
        #expect(reminders.map(\.triggerDate) == reminders.map(\.triggerDate).sorted())
        // Alle 25 abonnementenes aller første varsel er de nærmeste, og må være med.
        let firstOccurrences = reminders.filter { $0.identifier.hasSuffix("#0") }
        #expect(firstOccurrences.count == 25)
    }

    @Test func trialEndGetsItsOwnWordingAndStillFiresWhenTheTrialIsShort() {
        // Prøveperioden slutter om 2 dager, men varsel er satt til 3 dager før.
        let trialEnd = now.addingTimeInterval(2 * 86_400)
        let trial = Subscription(
            name: "Netflix",
            price: 149,
            nextRenewalDate: trialEnd,
            trialEndDate: trialEnd,
            reminderDaysBefore: 3
        )

        let reminders = NotificationScheduler.plannedReminders(for: [trial], now: now)
        let first = reminders.first { $0.identifier.hasSuffix("#0") }

        #expect(first?.title == "Prøveperioden for Netflix slutter snart")
        #expect(first?.triggerDate == RenewalCalculator.reminderDate(nextRenewalDate: trialEnd, daysBefore: 1))
        // Senere fornyelser er vanlige betalinger.
        let second = reminders.first { $0.identifier.hasSuffix("#1") }
        #expect(second?.title == "Netflix fornyes snart")
    }

    @Test func skipsPausedSubscriptions() {
        let reminders = NotificationScheduler.plannedReminders(
            for: [subscription(daysUntilRenewal: 10, isActive: false)],
            now: now
        )
        #expect(reminders.isEmpty)
    }

    @Test func skipsRemindersThatWouldFireInThePast() {
        // Fornyes om 1 dag, varsel 3 dager før -> første varsel er allerede passert.
        let reminders = NotificationScheduler.plannedReminders(
            for: [subscription(daysUntilRenewal: 1, reminderDaysBefore: 3)],
            now: now
        )
        #expect(!reminders.contains { $0.identifier.hasSuffix("#0") })
        #expect(reminders.allSatisfy { $0.triggerDate > now })
        #expect(reminders.count == NotificationScheduler.occurrencesPerSubscription - 1)
    }

    @Test func remindersCarryTheCancelLinkWhenSet() {
        let withLink = subscription(daysUntilRenewal: 10)
        withLink.cancelURLString = "https://www.netflix.com/cancelplan"
        let withoutLink = subscription(daysUntilRenewal: 11)

        let reminders = NotificationScheduler.plannedReminders(for: [withLink, withoutLink], now: now)

        let linked = reminders.filter { $0.identifier.hasPrefix(withLink.id.uuidString) }
        let unlinked = reminders.filter { $0.identifier.hasPrefix(withoutLink.id.uuidString) }
        #expect(!linked.isEmpty)
        #expect(linked.allSatisfy { $0.cancelURL?.absoluteString == "https://www.netflix.com/cancelplan" })
        #expect(unlinked.allSatisfy { $0.cancelURL == nil })
    }
}
