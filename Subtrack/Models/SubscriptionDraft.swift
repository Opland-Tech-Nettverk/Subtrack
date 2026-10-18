import Foundation

/// Et delvis utfylt nytt abonnement som brukeren går gjennom i skjemaet før det lagres.
/// Felt som er `nil`, beholder skjemaets standardverdi.
struct SubscriptionDraft: Identifiable, Equatable {
    enum Source: String, Equatable {
        case catalog, shortcut, receipt, bankStatement
    }

    var id = UUID()
    var source: Source
    var name: String? = nil
    var price: Decimal? = nil
    var currencyCode: String? = nil
    var interval: BillingInterval? = nil
    var kind: SubscriptionCategory? = nil
    var nextRenewalDate: Date? = nil
    var symbolName: String? = nil
    var colorHex: String? = nil
    var cancelURLString: String? = nil
    var note: String? = nil
    /// Katalogtjenesten utkastet kom fra, om noen. Brukes av skjemaet til å vise planvalg.
    var catalogServiceID: String? = nil
}
