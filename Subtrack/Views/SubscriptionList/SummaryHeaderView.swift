import SwiftUI

/// Hero-kortet øverst i oversikten: hva alt koster per måned og per år for det som faktisk
/// koster penger nå (ikke pauset eller avsluttet), omregnet til hovedvalutaen. Bakgrunnen har
/// en svak gradient fra fargene til de dyreste abonnementene.
struct SummaryHeaderView: View {
    let subscriptions: [Subscription]

    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 44

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

    /// Abonnementet som trekkes først.
    private var nextCharge: Subscription? {
        activeSubscriptions.min { $0.nextRenewalDate < $1.nextRenewalDate }
    }

    /// Fargene til de dyreste abonnementene, dyrest først. Uten kurs regnes abonnementet som 0.
    private var gradientColors: [Color] {
        let ranked = activeSubscriptions.sorted { lhs, rhs in
            let l = CurrencyConverter.convert(lhs.monthlyCost, from: lhs.currencyCode, to: mainCurrency, using: exchangeRates.rates)
            let r = CurrencyConverter.convert(rhs.monthlyCost, from: rhs.currencyCode, to: mainCurrency, using: exchangeRates.rates)
            return (l ?? 0) > (r ?? 0)
        }
        let colors = ranked.prefix(3).map(\.displayColor)
        return colors.isEmpty ? [Color.accentColor] : colors
    }

    private var background: some View {
        let opacities: [Double] = [0.28, 0.2, 0.12]
        let stops = gradientColors.enumerated().map { index, color in
            color.opacity(opacities[min(index, opacities.count - 1)])
        }
        // Minst to farger i en gradient; med én farge går den ut mot en svakere variant.
        let gradientStops = stops.count > 1 ? stops : [stops[0], stops[0].opacity(0.4)]
        return RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
            .fill(LinearGradient(colors: gradientStops, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Per måned")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(Money.string(totalMonthly.amount, code: mainCurrency, whole: true))
                .font(.system(size: heroSize, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .numericMotion(totalMonthly.amount)

            secondaryRow

            if let conversionNote {
                Text(conversionNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background { background }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var secondaryRow: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            fact(title: "Per år", value: Money.string(totalYearly.amount, code: mainCurrency, whole: true))
            if let nextCharge {
                if !stacked {
                    Spacer(minLength: 0)
                }
                fact(
                    title: "Neste trekk",
                    value: "\(nextCharge.name) · \(nextCharge.renewalDescription().lowercasedFirst)",
                    alignment: stacked ? .leading : .trailing
                )
            }
        }
    }

    private func fact(title: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.amount(.callout))
                .lineLimit(2)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        }
    }
}

private extension String {
    /// «I morgen» blir «i morgen», så det passer midt i en setning.
    var lowercasedFirst: String {
        prefix(1).lowercased() + dropFirst()
    }
}

#Preview {
    List {
        SummaryHeaderView(subscriptions: [
            Subscription(name: "Netflix", price: 149, billingInterval: .monthly, colorHex: "#FF453A"),
            Subscription(name: "Spotify", price: 12, currencyCode: "USD", billingInterval: .monthly, colorHex: "#30D158")
        ])
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
    .environment(ExchangeRateStore())
}
