import Foundation
import SwiftData
import WidgetKit

/// Deler en forenklet oversikt over kommende trekk med widgeten via App Groupen.
/// Widgeten kjører i en egen prosess og leser denne JSON-en i stedet for databasen.
/// Formatet må holdes i synk med `UpcomingRenewal` i SubtrackWidget-targetet.
enum WidgetSnapshotStore {
    static let appGroupID = "group.com.opland.subtrack"
    static let snapshotKey = "upcomingRenewals"
    static let widgetKind = "SubtrackWidget"

    /// Flere fornyelser per abonnement gjør at widgeten fortsatt har noe å vise
    /// når de nærmeste datoene passerer, selv om appen ikke åpnes på en stund.
    static let occurrencesPerSubscription = 3

    struct UpcomingRenewal: Codable {
        let name: String
        let price: Decimal
        let currencyCode: String
        let symbolName: String
        let colorHex: String?
        let renewalDate: Date
        let isTrialEnd: Bool
    }

    /// Kommende trekk for alle abonnement som koster penger nå, sortert etter dato.
    /// Skilt ut fra `update` så utvalget kan testes uten App Group og WidgetKit.
    static func renewals(for subscriptions: [Subscription]) -> [UpcomingRenewal] {
        subscriptions
            .filter(\.isBilling)
            .flatMap { subscription in
                subscription.upcomingRenewalDates(count: occurrencesPerSubscription).map { renewalDate in
                    UpcomingRenewal(
                        name: subscription.name,
                        price: subscription.price,
                        currencyCode: subscription.currencyCode,
                        symbolName: subscription.displaySymbolName,
                        colorHex: subscription.colorHex,
                        renewalDate: renewalDate,
                        isTrialEnd: subscription.isTrialEnd(renewalDate)
                    )
                }
            }
            .sorted { $0.renewalDate < $1.renewalDate }
    }

    static func update(with subscriptions: [Subscription]) {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = try? JSONEncoder().encode(renewals(for: subscriptions))
        else { return }

        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Henter alle abonnement fra konteksten (inkludert ulagrede endringer) og oppdaterer widgeten.
    static func update(using modelContext: ModelContext) {
        let subscriptions = (try? modelContext.fetch(FetchDescriptor<Subscription>())) ?? []
        update(with: subscriptions)
    }
}
