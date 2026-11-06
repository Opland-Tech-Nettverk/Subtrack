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
            .sorted { lhs, rhs in
                lhs.monthlyCost == rhs.monthlyCost ? lhs.category.rawValue < rhs.category.rawValue : lhs.monthlyCost > rhs.monthlyCost
            }
    }

    /// Kategoriene med andel i hele prosent som summerer til 100, dyrest først.
    var categoryShares: [CategoryShare] {
        CategoryBreakdown.shares(from: categoryCosts)
    }

    /// De dyreste abonnementene per måned, høyest først.
    var mostExpensiveSubscriptions: [ConvertedSubscription] {
        mostExpensiveSubscriptions(limit: 5, in: nil)
    }

    /// De dyreste abonnementene per måned, høyest først, bare i én kategori når `category` er satt.
    func mostExpensiveSubscriptions(limit: Int, in category: SubscriptionCategory?) -> [ConvertedSubscription] {
        let candidates = category.map { category in
            convertedSubscriptions.filter { $0.category == category }
        } ?? convertedSubscriptions
        return Array(candidates.sorted { $0.monthlyCost > $1.monthlyCost }.prefix(limit))
    }

    /// Hva avsluttede abonnement har spart til nå, og hva de sparer per år fremover, omregnet til
    /// målvalutaen. Abonnement uten kurs utelates og telles i `excludedCount`.
    func savings(now: Date = .now, calendar: Calendar = .current) -> SavingsSummary {
        let cancelled = subscriptions.filter(\.isCancelled)
        let saved = CurrencyConverter.total(
            of: cancelled.map { ($0.savedSinceCancellation(now: now, calendar: calendar), $0.currencyCode) },
            in: targetCurrency,
            using: rates
        )
        let yearly = CurrencyConverter.total(
            of: cancelled.map { ($0.projectedYearlySavings, $0.currencyCode) },
            in: targetCurrency,
            using: rates
        )
        return SavingsSummary(
            total: saved.amount,
            yearly: yearly.amount,
            cancelledCount: cancelled.count,
            excludedCount: saved.excludedCount
        )
    }
}

/// Besparelsen fra avsluttede abonnement.
struct SavingsSummary: Equatable {
    let total: Decimal
    let yearly: Decimal
    let cancelledCount: Int
    let excludedCount: Int
}

extension Decimal {
    /// Swift Charts tegner med `Double`. Abonnementsbeløp er små nok til at presisjonstapet ikke merkes.
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
