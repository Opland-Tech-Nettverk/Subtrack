import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query private var subscriptions: [Subscription]
    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Høyden per stolpe vokser med tekststørrelsen, så navn og beløp ikke overlapper.
    @ScaledMetric(relativeTo: .caption) private var barRowHeight: CGFloat = 44

    /// Bytter til Oversikt-fanen. Settes av `MainTabView`; tom som standard for forhåndsvisninger.
    private let showOverview: () -> Void

    // Egen init, så den er synlig fra andre filer selv om de øvrige egenskapene er private.
    init(showOverview: @escaping () -> Void = {}) {
        self.showOverview = showOverview
    }

    private var viewModel: StatisticsViewModel {
        StatisticsViewModel(subscriptions: subscriptions, targetCurrency: mainCurrency, rates: exchangeRates.rates)
    }

    var body: some View {
        // Bygges én gang her og sendes videre til seksjonene, i stedet for at hver av dem
        // leser den beregnede `self.viewModel` og lager sin egen kopi.
        let viewModel = self.viewModel

        NavigationStack {
            Group {
                if viewModel.hasData {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            categorySection(viewModel)
                            mostExpensiveSection(viewModel)
                            if viewModel.excludedCount > 0 {
                                Text("\(viewModel.excludedCount) abonnement uten valutakurs er ikke tatt med.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .readableContentWidth()
                } else if viewModel.excludedCount > 0 {
                    ContentUnavailableView(
                        "Mangler valutakurser",
                        systemImage: "wifi.slash",
                        description: Text("Koble til internett én gang, så regnes abonnementene om til \(mainCurrency).")
                    )
                } else if subscriptions.isEmpty {
                    // Statistikkfanen har ingen +-knapp, så vi viser vei til Oversikt i stedet.
                    ContentUnavailableView {
                        Label("Ingen abonnementer ennå", systemImage: "chart.pie")
                    } description: {
                        Text("Legg til abonnementer i Oversikt, så ser du her hva de koster per kategori.")
                    } actions: {
                        Button("Gå til Oversikt", action: showOverview)
                    }
                } else {
                    // Det finnes abonnementer, men alle er pauset eller avsluttet.
                    ContentUnavailableView {
                        Label("Ingen aktive abonnementer", systemImage: "pause.circle")
                    } description: {
                        Text("Pausede og avsluttede abonnementer tas ikke med i statistikken.")
                    } actions: {
                        Button("Gå til Oversikt", action: showOverview)
                    }
                }
            }
            .navigationTitle("Statistikk")
        }
    }

    private func categorySection(_ viewModel: StatisticsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kostnad per kategori")
                .font(.headline)

            Chart(viewModel.categoryCosts) { item in
                SectorMark(
                    angle: .value("Kostnad", item.monthlyCost.doubleValue),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                // Faste farger per kategori i stedet for diagrammets egen legende: legenden
                // spiste hele høyden ved store tekststørrelser. Listen under fungerer som legende.
                .foregroundStyle(item.category.chartColor)
                .cornerRadius(4)
            }
            .frame(height: 240)
            .accessibilityHidden(true) // Tallene under gir samme informasjon i tekstform for VoiceOver.

            // Tekstlig oversikt - gir eksakte tall og fungerer som VoiceOver-alternativ til selve diagrammet.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.categoryCosts) { item in
                    amountRow(
                        title: item.category.displayName,
                        amount: item.monthlyCost,
                        dotColor: item.category.chartColor
                    )
                }
            }
        }
    }

    /// Navn og beløp side om side, eller under hverandre ved tilgjengelighetsstørrelser.
    @ViewBuilder
    private func amountRow(title: String, amount: Decimal, dotColor: Color? = nil) -> some View {
        let amountText = Text(amount.formatted(.currency(code: mainCurrency)))
            .foregroundStyle(.secondary)
        let titleLabel = HStack(spacing: 8) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }
            Text(title)
        }

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    titleLabel
                    amountText
                }
            } else {
                HStack {
                    titleLabel
                    Spacer()
                    amountText
                }
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func mostExpensiveSection(_ viewModel: StatisticsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dyreste abonnement")
                .font(.headline)

            // Et liggende stolpediagram med navn på aksen blir uleselig ved de største
            // tekststørrelsene, så da vises en enkel liste i stedet.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.mostExpensiveSubscriptions) { subscription in
                        amountRow(title: subscription.name, amount: subscription.monthlyCost)
                    }
                }
            } else {
                mostExpensiveChart(viewModel)
            }
        }
    }

    private func mostExpensiveChart(_ viewModel: StatisticsViewModel) -> some View {
        Chart(viewModel.mostExpensiveSubscriptions) { subscription in
            BarMark(
                x: .value("Per måned", subscription.monthlyCost.doubleValue),
                y: .value("Navn", subscription.name)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .annotation(position: .trailing) {
                Text(subscription.monthlyCost.formatted(.currency(code: mainCurrency)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(subscription.name)
            .accessibilityValue(subscription.monthlyCost.formatted(.currency(code: mainCurrency)))
        }
        .frame(height: CGFloat(viewModel.mostExpensiveSubscriptions.count) * barRowHeight + 20)
    }
}

extension SubscriptionCategory {
    /// Fast farge per kategori i statistikken, så diagrammet og listen under alltid matcher.
    var chartColor: Color {
        switch self {
        case .streaming: .red
        case .musikk: .purple
        case .programvare: .blue
        case .trening: .orange
        case .nettsky: .cyan
        case .annet: .gray
        }
    }
}

#Preview("Tom") {
    StatisticsView()
        .modelContainer(for: Subscription.self, inMemory: true)
        .environment(ExchangeRateStore())
}

#Preview("Med data") {
    let container = try! ModelContainer(for: Subscription.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    for subscription in [
        Subscription(name: "Netflix", price: 149, category: .streaming),
        Subscription(name: "Spotify", price: 129, category: .musikk),
        Subscription(name: "Adobe Creative Cloud", price: 699, category: .programvare),
        Subscription(name: "Fitness24", price: 399, category: .trening)
    ] {
        container.mainContext.insert(subscription)
    }
    return StatisticsView()
        .modelContainer(container)
        .environment(ExchangeRateStore())
}
