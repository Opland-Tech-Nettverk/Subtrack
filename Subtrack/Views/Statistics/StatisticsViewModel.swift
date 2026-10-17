import Foundation

/// Kostnad per måned for én kategori, klar til å plottes i et sektordiagram.
struct CategoryCost: Identifiable {
    let category: SubscriptionCategory
    let monthlyCost: Decimal

    var id: SubscriptionCategory { category }
}

/// Et abonnement med månedskostnad omregnet til målvalutaen, så alle kan sammenlignes.
struct ConvertedSubscription: Identifiable {
    let id: UUID
    let name: String
    let category: SubscriptionCategory
    let monthlyCost: Decimal
}

/// Henter ut og aggregerer data fra abonnementslisten til en form Swift Charts kan tegne direkte.
/// Alle beløp regnes om til `targetCurrency`; abonnement uten kurs utelates og telles i `excludedCount`.
struct StatisticsViewModel {
    let subscriptions: [Subscription]
    let targetCurrency: String
    let rates: ExchangeRates?

    private var activeSubscriptions: [Subscription] {
        subscriptions.filter(\.isBilling)
    }

    private var convertedSubscriptions: [ConvertedSubscription] {
        activeSubscriptions.compactMap { subscription in
            guard let monthlyCost = CurrencyConverter.convert(
                subscription.monthlyCost,
                from: subscription.currencyCode,
                to: targetCurrency,
                using: rates
            ) else { return nil }

            return ConvertedSubscription(
                id: subscription.id,
                name: subscription.name,
                category: subscription.kind,
                monthlyCost: monthlyCost
            )
        }
    }

    var hasData: Bool {
        !convertedSubscriptions.isEmpty
    }

    var excludedCount: Int {
        activeSubscriptions.count - convertedSubscriptions.count
    }

    /// Kostnad per kategori per måned, sortert fra dyrest til billigst.
    var categoryCosts: [CategoryCost] {
        Dictionary(grouping: convertedSubscriptions, by: \.category)
            .map { category, subscriptions in
                CategoryCost(
                    category: category,
                    monthlyCost: subscriptions.reduce(Decimal(0)) { $0 + $1.monthlyCost }
                )
            }
            .sorted { $0.monthlyCost > $1.monthlyCost }
    }

    /// De dyreste abonnementene per måned, høyest først.
    var mostExpensiveSubscriptions: [ConvertedSubscription] {
        Array(convertedSubscriptions.sorted { $0.monthlyCost > $1.monthlyCost }.prefix(5))
    }
}

extension Decimal {
    /// Swift Charts tegner med `Double`. Abonnementsbeløp er små nok til at presisjonstapet ikke merkes.
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
