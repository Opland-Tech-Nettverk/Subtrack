import SwiftUI

/// Viser total kostnad per måned og per år for alle aktive (ikke pausede) abonnement,
/// omregnet til brukerens hovedvaluta.
struct SummaryHeaderView: View {
    let subscriptions: [Subscription]

    @AppStorage(AppSettingsKeys.glassIntensity) private var glassIntensity: Double = 0.6
    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var activeSubscriptions: [Subscription] {
        subscriptions.filter(\.isBilling)
    }

    private var totalMonthly: ConvertedTotal {
        CurrencyConverter.total(
            of: activeSubscriptions.map { ($0.monthlyCost, $0.currencyCode) },
            in: mainCurrency,
            using: exchangeRates.rates
        )
    }

    private var totalYearly: ConvertedTotal {
        CurrencyConverter.total(
            of: activeSubscriptions.map { ($0.yearlyCost, $0.currencyCode) },
            in: mainCurrency,
            using: exchangeRates.rates
        )
    }

    private var hasForeignCurrency: Bool {
        activeSubscriptions.contains { $0.currencyCode != mainCurrency }
    }

    /// Forklaring under tallene, kun når noe faktisk er regnet om eller utelatt.
    private var conversionNote: String? {
        guard hasForeignCurrency else { return nil }
        let excluded = totalMonthly.excludedCount
        if excluded > 0 {
            return "\(excluded) abonnement uten valutakurs er ikke tatt med"
        }
        if let rates = exchangeRates.rates {
            return "Omregnet med kurs per \(rates.rateDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            // To kolonner blir for trangt ved tilgjengelighetsstørrelser; da stables de.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    SummaryColumn(title: "Per måned", amount: totalMonthly.amount, currencyCode: mainCurrency)
                    Divider()
                        .padding(.horizontal)
                    SummaryColumn(title: "Per år", amount: totalYearly.amount, currencyCode: mainCurrency)
                }
            } else {
                HStack {
                    SummaryColumn(title: "Per måned", amount: totalMonthly.amount, currencyCode: mainCurrency)
                    Divider()
                        .frame(height: 36)
                    SummaryColumn(title: "Per år", amount: totalYearly.amount, currencyCode: mainCurrency)
                }
            }

            if let conversionNote {
                Text(conversionNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .adjustableGlassBackground(intensity: glassIntensity)
        .accessibilityElement(children: .combine)
    }
}

private struct SummaryColumn: View {
    let title: String
    let amount: Decimal
    let currencyCode: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amount.formatted(.currency(code: currencyCode)))
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    List {
        SummaryHeaderView(subscriptions: [
            Subscription(name: "Netflix", price: 149, billingInterval: .monthly, category: .streaming),
            Subscription(name: "Spotify", price: 12, currencyCode: "USD", billingInterval: .monthly, category: .musikk)
        ])
    }
    .environment(ExchangeRateStore())
}
