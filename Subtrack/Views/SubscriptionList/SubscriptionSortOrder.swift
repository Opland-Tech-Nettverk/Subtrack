import Foundation

/// Hvordan abonnementslisten sorteres. Rå-verdien lagres i @AppStorage, så den må ikke endres.
enum SubscriptionSortOrder: String, CaseIterable, Identifiable {
    case renewal
    case price
    case name
    case category

    var id: Self { self }

    var displayName: String {
        switch self {
        case .renewal: "Neste fornyelse"
        case .price: "Pris"
        case .name: "Navn"
        case .category: "Kategori"
        }
    }

    var symbolName: String {
        switch self {
        case .renewal: "calendar"
        case .price: "creditcard"
        case .name: "textformat"
        case .category: "square.grid.2x2"
        }
    }

    /// Sorterer abonnementene. `monthlyCost` gir månedskostnaden i hovedvalutaen, slik at
    /// abonnement i ulike valutaer sammenlignes riktig. Abonnement uten kurs (`nil`) havner sist.
    func sorted(
        _ subscriptions: [Subscription],
        monthlyCost: (Subscription) -> Decimal?
    ) -> [Subscription] {
        switch self {
        case .renewal:
            return subscriptions.sorted { Self.byRenewal($0, $1) }
        case .price:
            // Beregner hver kostnad én gang i stedet for i hver sammenligning.
            let costs = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, monthlyCost($0)) })
            return subscriptions.sorted { lhs, rhs in
                switch (costs[lhs.id] ?? nil, costs[rhs.id] ?? nil) {
                case let (l?, r?) where l != r: l > r
                case (_?, nil): true
                case (nil, _?): false
                default: Self.byRenewal(lhs, rhs)
                }
            }
        case .name:
            return subscriptions.sorted { lhs, rhs in
                let result = lhs.name.localizedStandardCompare(rhs.name)
                return result == .orderedSame ? Self.byRenewal(lhs, rhs) : result == .orderedAscending
            }
        case .category:
            return subscriptions.sorted { lhs, rhs in
                let result = lhs.category.displayName.localizedStandardCompare(rhs.category.displayName)
                return result == .orderedSame ? Self.byRenewal(lhs, rhs) : result == .orderedAscending
            }
        }
    }

    private static func byRenewal(_ lhs: Subscription, _ rhs: Subscription) -> Bool {
        if lhs.nextRenewalDate != rhs.nextRenewalDate {
            return lhs.nextRenewalDate < rhs.nextRenewalDate
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

extension Subscription {
    /// Søk i navn og kategori, uten å skille på store/små bokstaver eller aksenter.
    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return name.localizedStandardContains(query) || category.displayName.localizedStandardContains(query)
    }
}
