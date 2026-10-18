import Foundation
import Testing
@testable import Subtrack

@MainActor
struct SubscriptionStorageTests {

    // MARK: - Tekstkoder

    @Test func initWritesStringCodes() {
        let subscription = Subscription(name: "Netflix", price: 149, billingInterval: .yearly, category: .streaming)

        #expect(subscription.categoryCode == "streaming")
        #expect(subscription.billingIntervalCode == "yearly")
        #expect(subscription.kind == .streaming)
        #expect(subscription.interval == .yearly)
    }

    @Test func settersUpdateStringCodes() {
        let subscription = Subscription(name: "Spotify", price: 129)

        subscription.kind = .musikk
        subscription.interval = .quarterly

        #expect(subscription.categoryCode == "musikk")
        #expect(subscription.billingIntervalCode == "quarterly")
        #expect(subscription.kind == .musikk)
        #expect(subscription.interval == .quarterly)
    }

    // MARK: - Utfasede felt for eldre versjoner

    /// Uten tekstkoden leser `kind`/`interval` det utfasede feltet, slik en eldre app-versjon
    /// gjør. Det viser om det utfasede feltet faktisk ble skrevet.
    @Test func initAlsoWritesLegacyFieldsForOlderVersions() {
        let subscription = Subscription(name: "Adobe", price: 6990, billingInterval: .yearly, category: .programvare)

        subscription.categoryCode = nil
        subscription.billingIntervalCode = nil

        #expect(subscription.kind == .programvare)
        #expect(subscription.interval == .yearly)
    }

    @Test func settersAlsoUpdateLegacyFields() {
        let subscription = Subscription(name: "Spotify", price: 129)
        subscription.kind = .musikk
        subscription.interval = .quarterly

        subscription.categoryCode = nil
        subscription.billingIntervalCode = nil

        #expect(subscription.kind == .musikk)
        #expect(subscription.interval == .quarterly)
    }

    // MARK: - Tolkning med reserve

    @Test func resolveUsesValidCode() {
        #expect(Subscription.resolve(code: "trening", legacy: SubscriptionCategory.annet) == .trening)
        #expect(Subscription.resolve(code: "weekly", legacy: BillingInterval.monthly) == .weekly)
    }

    @Test func resolveFallsBackToLegacyWhenCodeIsMissing() {
        // Data lagret før tekstfeltene fantes har ingen kode.
        #expect(Subscription.resolve(code: nil, legacy: SubscriptionCategory.nettsky) == .nettsky)
        #expect(Subscription.resolve(code: nil, legacy: BillingInterval.yearly) == .yearly)
    }

    @Test func resolveFallsBackToLegacyWhenCodeIsUnknown() {
        // F.eks. en kategori eller et intervall skrevet av en nyere versjon av appen.
        #expect(Subscription.resolve(code: "podcast", legacy: SubscriptionCategory.musikk) == .musikk)
        #expect(Subscription.resolve(code: "daily", legacy: BillingInterval.monthly) == .monthly)
    }

    // MARK: - Nye kategorier

    @Test(arguments: [SubscriptionCategory.nyheter, .boker, .spill, .ai])
    func newCategoryRoundTripsViaCode(category: SubscriptionCategory) {
        let subscription = Subscription(name: "Test", price: 99, category: category)

        #expect(subscription.categoryCode == category.rawValue)
        #expect(subscription.kind == category)

        subscription.kind = .streaming
        subscription.kind = category

        #expect(subscription.categoryCode == category.rawValue)
        #expect(subscription.kind == category)
    }

    /// Eldre versjoner kjenner ikke de nye kategoriene, så det utfasede feltet får «Annet».
    @Test(arguments: [SubscriptionCategory.nyheter, .boker, .spill, .ai])
    func newCategoryWritesAnnetToLegacyField(category: SubscriptionCategory) {
        let subscription = Subscription(name: "Test", price: 99, category: .streaming)
        subscription.kind = category

        subscription.categoryCode = nil

        #expect(subscription.kind == .annet)
    }

    @Test func unknownFutureCategoryCodeFallsBackToLegacyField() {
        let subscription = Subscription(name: "Test", price: 99, category: .musikk)

        subscription.categoryCode = "podkast"

        #expect(subscription.kind == .musikk)
    }

    @Test func newCategoriesComeBeforeAnnet() {
        let cases = SubscriptionCategory.allCases
        #expect(Array(cases.suffix(5)) == [.nyheter, .boker, .spill, .ai, .annet])
    }
}
