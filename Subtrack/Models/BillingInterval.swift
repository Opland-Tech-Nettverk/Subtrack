import Foundation

/// Hvor ofte et abonnement fornyes. Lagres som rawValue-tekst i `Subscription.billingIntervalCode`.
/// Codable trengs fortsatt for det utfasede feltet `Subscription.billingInterval`.
enum BillingInterval: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case quarterly
    case yearly

    var id: Self { self }

    var displayName: String {
        switch self {
        case .weekly: "Ukentlig"
        case .monthly: "Månedlig"
        case .quarterly: "Kvartalsvis"
        case .yearly: "Årlig"
        }
    }

    /// Antall faktureringer per år, brukt til å regne om til måneds-/årskostnad.
    var cyclesPerYear: Decimal {
        switch self {
        case .weekly: 52
        case .monthly: 12
        case .quarterly: 4
        case .yearly: 1
        }
    }

    /// Legger til `count` faktureringsperioder på en dato i ett steg. Å legge til flere
    /// perioder samtidig (i stedet for én og én) unngår at f.eks. den 31. "krymper" til
    /// den 28. etter februar og blir værende der.
    func advanced(from date: Date, by count: Int = 1, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly:
            calendar.date(byAdding: .day, value: 7 * count, to: date) ?? date
        case .monthly:
            calendar.date(byAdding: .month, value: count, to: date) ?? date
        case .quarterly:
            calendar.date(byAdding: .month, value: 3 * count, to: date) ?? date
        case .yearly:
            calendar.date(byAdding: .year, value: count, to: date) ?? date
        }
    }
}
