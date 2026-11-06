import Foundation

/// Et delvis utfylt nytt abonnement som brukeren går gjennom i skjemaet før det lagres.
/// Felt som er `nil`, beholder skjemaets standardverdi.
nonisolated struct SubscriptionDraft: Identifiable, Equatable {
    nonisolated enum Source: String, Equatable {
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
    /// Filen i innboksen (delt kvittering) utkastet kom fra. Filen slettes først når skjemaet er lagret eller
    /// forkastet, så en kvittering ikke går tapt hvis appen avsluttes før brukeren er ferdig.
    var receiptInboxID: UUID? = nil
}

extension SubscriptionDraft {
    /// Skjemaet må la brukeren velge intervall når utkastet ikke har noe («Velg intervall»), i stedet for å
    /// vise Månedlig. Gjelder utkast fra kvittering, snarvei og katalogtjenester uten fast pris.
    nonisolated var needsIntervalChoice: Bool { interval == nil }
}
