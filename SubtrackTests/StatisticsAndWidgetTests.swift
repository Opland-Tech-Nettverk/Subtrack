import Foundation
import Testing
@testable import Subtrack

@MainActor
struct StatisticsViewModelTests {

    /// Enkle tall: 1 EUR = 10 NOK og 1 EUR = 1 USD, altså 1 USD = 10 NOK.
    private let rates = ExchangeRates(
        base: "EUR",
        rates: ["NOK": 10, "USD": 1],
        rateDate: .now,
        fetchedAt: .now
    )

    @Test func groupsCostsByCategoryAndSortsMostExpensiveFirst() {
        let viewModel = StatisticsViewModel(
            subscriptions: [
                Subscription(name: "Netflix", price: 149, category: .streaming),
                Subscription(name: "HBO", price: 100, category: .streaming),
                Subscription(name: "Spotify", price: 129, category: .musikk)
            ],
            targetCurrency: "NOK",
            rates: rates
        )

        #expect(viewModel.categoryCosts.map(\.category) == [.streaming, .musikk])
        #expect(viewModel.categoryCosts.map(\.monthlyCost) == [249, 129])
        #expect(viewModel.hasData)
    }

    @Test func convertsForeignCurrenciesToTheTargetCurrency() {
        let viewModel = StatisticsViewModel(
            subscriptions: [Subscription(name: "ChatGPT", price: 20, currencyCode: "USD", category: .programvare)],
            targetCurrency: "NOK",
            rates: rates
        )
        #expect(viewModel.categoryCosts.first?.monthlyCost == 200)
        #expect(viewModel.excludedCount == 0)
    }

    @Test func countsSubscriptionsWithoutRateAsExcluded() {
        let viewModel = StatisticsViewModel(
            subscriptions: [
                Subscription(name: "Netflix", price: 149, category: .streaming),
                Subscription(name: "Ukjent", price: 5, currencyCode: "XYZ")
            ],
            targetCurrency: "NOK",
            rates: rates
        )
        #expect(viewModel.excludedCount == 1)
        #expect(viewModel.mostExpensiveSubscriptions.map(\.name) == ["Netflix"])
    }

    @Test func ignoresPausedAndCancelledSubscriptions() {
        let cancelled = Subscription(name: "Avsluttet", price: 500)
        cancelled.cancelledDate = .now
        let viewModel = StatisticsViewModel(
            subscriptions: [
                Subscription(name: "Pauset", price: 300, isActive: false),
                cancelled
            ],
            targetCurrency: "NOK",
            rates: rates
        )
        #expect(!viewModel.hasData)
        #expect(viewModel.excludedCount == 0)
    }

    @Test func usesMyShareAndMonthlyCostForYearlySubscriptions() {
        let viewModel = StatisticsViewModel(
            subscriptions: [Subscription(name: "Familie", price: 1200, billingInterval: .yearly, splitCount: 2)],
            targetCurrency: "NOK",
            rates: nil
        )
        #expect(viewModel.mostExpensiveSubscriptions.first?.monthlyCost == 50)
    }

    @Test func showsAtMostFiveMostExpensive() {
        let subscriptions = (1...8).map { Subscription(name: "Abo \($0)", price: Decimal($0 * 10)) }
        let viewModel = StatisticsViewModel(subscriptions: subscriptions, targetCurrency: "NOK", rates: nil)

        #expect(viewModel.mostExpensiveSubscriptions.count == 5)
        #expect(viewModel.mostExpensiveSubscriptions.first?.name == "Abo 8")
    }
}

@MainActor
struct WidgetSnapshotStoreTests {

    private func inDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: .now))!
    }

    @Test func includesSeveralUpcomingRenewalsPerSubscriptionSortedByDate() {
        let renewals = WidgetSnapshotStore.renewals(for: [
            Subscription(name: "Spotify", price: 129, nextRenewalDate: inDays(10)),
            Subscription(name: "Netflix", price: 149, nextRenewalDate: inDays(3))
        ])

        #expect(renewals.count == 2 * WidgetSnapshotStore.occurrencesPerSubscription)
        #expect(renewals.map(\.renewalDate) == renewals.map(\.renewalDate).sorted())
        #expect(renewals.first?.name == "Netflix")
    }

    @Test func skipsPausedAndCancelledSubscriptions() {
        let cancelled = Subscription(name: "Avsluttet", price: 100, nextRenewalDate: inDays(1))
        cancelled.cancelledDate = .now
        let renewals = WidgetSnapshotStore.renewals(for: [
            Subscription(name: "Pauset", price: 100, nextRenewalDate: inDays(2), isActive: false),
            cancelled
        ])
        #expect(renewals.isEmpty)
    }

    @Test func marksOnlyTheFirstPaymentAfterATrial() {
        let trialEnd = inDays(5)
        let renewals = WidgetSnapshotStore.renewals(for: [
            Subscription(name: "Prøve", price: 99, nextRenewalDate: trialEnd, trialEndDate: trialEnd)
        ])
        #expect(renewals.map(\.isTrialEnd) == [true, false, false])
    }

    @Test func usesTheCategoryIconWhenNoCustomIconIsSet() {
        let renewals = WidgetSnapshotStore.renewals(for: [
            Subscription(name: "Netflix", price: 149, nextRenewalDate: inDays(1), category: .streaming)
        ])
        #expect(renewals.first?.symbolName == SubscriptionCategory.streaming.defaultSymbolName)
    }

    /// Widgeten dekoder JSON-en med sin egen kopi av typen. Endres et feltnavn her,
    /// slutter widgeten stille å vise data - denne testen fanger det.
    @Test func jsonKeysMatchWhatTheWidgetDecodes() throws {
        let renewals = WidgetSnapshotStore.renewals(for: [
            Subscription(name: "Netflix", price: 149, nextRenewalDate: inDays(1), colorHex: "#FF453A")
        ])
        let data = try JSONEncoder().encode(renewals)
        let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let keys = Set(try #require(objects.first).keys)

        #expect(keys == ["name", "price", "currencyCode", "symbolName", "colorHex", "renewalDate", "isTrialEnd"])
    }
}
