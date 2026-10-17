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
}
