import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query private var subscriptions: [Subscription]
    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Kategorien brukeren har trykket på. Viser abonnementene i den og filtrerer «Dyreste».
    @State private var selectedCategory: SubscriptionCategory? = DemoLaunch.category
    /// Vinkelen diagrammet melder når brukeren trykker på en sektor.
    @State private var selectedAngle: Double?
    /// Måneden brukeren har trykket på i «Kostnad framover».
    @State private var selectedMonth: Date?

    /// Bytter til Oversikt-fanen. Settes av `MainTabView`; tom som standard for forhåndsvisninger.
    private let showOverview: () -> Void

    // Egen init, så den er synlig fra andre filer selv om de øvrige egenskapene er private.
    init(showOverview: @escaping () -> Void = {}) {
        self.showOverview = showOverview
    }

    private var viewModel: StatisticsViewModel {
        StatisticsViewModel(subscriptions: subscriptions, targetCurrency: mainCurrency, rates: exchangeRates.rates)
    }

    private func whole(_ amount: Decimal) -> String {
        Money.string(amount, code: mainCurrency, whole: true)
    }

    var body: some View {
        // Bygges én gang her og sendes videre til seksjonene, i stedet for at hver av dem
        // leser den beregnede `self.viewModel` og lager sin egen kopi.
        let viewModel = self.viewModel

        NavigationStack {
            Group {
                if viewModel.hasData {
                    ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            savingsCard(viewModel)
                            categorySection(viewModel)
                            mostExpensiveSection(viewModel)
                                .id("expensive")
                            forwardCostSection
                                .id("forward")
                            if viewModel.excludedCount > 0 {
                                Text("\(viewModel.excludedCount) abonnement uten valutakurs er ikke tatt med.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                    }
                    .task { await DemoLaunch.scroll(proxy) }
                    }
                    .background(Color.canvas)
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
                        // Fremhevet knapp med stor kontrollstørrelse: uten `.large` ble den bare
                        // ca. 28 pt høy her, mens stor kontrollstørrelse gir minst 44 pt høyde.
                        Button("Gå til Oversikt", action: showOverview)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                } else {
                    // Det finnes abonnementer, men alle er pauset eller avsluttet.
                    ContentUnavailableView {
                        Label("Ingen aktive abonnementer", systemImage: "pause.circle")
                    } description: {
                        Text("Pausede og avsluttede abonnementer tas ikke med i statistikken.")
                    } actions: {
                        Button("Gå til Oversikt", action: showOverview)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
            .navigationTitle("Statistikk")
        }
    }

    // MARK: - Spart totalt

    private func savingsCard(_ viewModel: StatisticsViewModel) -> some View {
        let savings = viewModel.savings()
        return VStack(alignment: .leading, spacing: 6) {
            Label("Spart totalt", systemImage: "leaf.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            CountingAmount(amount: savings.total, currencyCode: mainCurrency)
            if savings.cancelledCount == 0 {
                Text("Avslutt et abonnement, så ser du her hva du sparer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(whole(savings.yearly)) per år fremover, fra \(savings.cancelledCount) avsluttede")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if savings.excludedCount > 0 {
                Text("\(savings.excludedCount) abonnement uten valutakurs er ikke tatt med")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.savings.opacity(0.2), Color.savings.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Kategorier

    private func categorySection(_ viewModel: StatisticsViewModel) -> some View {
        let costs = viewModel.categoryCosts
        let shares = viewModel.categoryShares
        let total = costs.reduce(Decimal(0)) { $0 + $1.monthlyCost }

        return VStack(alignment: .leading, spacing: 14) {
            Text("Kostnad per kategori")
                .font(.rounded(.title3))
                .accessibilityAddTraits(.isHeader)

            Chart(costs) { item in
                SectorMark(
                    angle: .value("Kostnad", item.monthlyCost.doubleValue),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                // Faste farger per kategori i stedet for diagrammets egen legende: legenden
                // spiste hele høyden ved store tekststørrelser. Listen under fungerer som legende.
                .foregroundStyle(item.category.chartColor)
                .cornerRadius(5)
                .opacity(selectedCategory == nil || selectedCategory == item.category ? 1 : 0.3)
            }
            .chartAngleSelection(value: $selectedAngle)
            .frame(height: 230)
            .overlay { donutCenter(costs: costs, shares: shares, total: total) }
            .motion(.smooth, value: selectedCategory)
            .accessibilityHidden(true) // Listen under gir samme informasjon i tekstform for VoiceOver.
            .onChange(of: selectedAngle) { _, angle in
                guard let angle,
                      let category = CategoryBreakdown.category(atAngleValue: angle, in: costs)
                else { return }
                selectedCategory = category
            }

            // Tekstlig oversikt: eksakte tall, og et trykk viser abonnementene i kategorien.
            VStack(spacing: 6) {
                ForEach(shares) { share in
                    CategoryRow(
                        share: share,
                        currencyCode: mainCurrency,
                        isSelected: selectedCategory == share.category,
                        members: selectedCategory == share.category
                            ? viewModel.mostExpensiveSubscriptions(limit: 20, in: share.category)
                            : []
                    ) {
                        withAnimation(reduceMotion ? nil : .smooth) {
                            selectedCategory = selectedCategory == share.category ? nil : share.category
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .card()
        .sensoryFeedback(.selection, trigger: selectedCategory)
    }

    @ViewBuilder
    private func donutCenter(costs: [CategoryCost], shares: [CategoryShare], total: Decimal) -> some View {
        VStack(spacing: 2) {
            if let selectedCategory, let share = shares.first(where: { $0.category == selectedCategory }) {
                Text(selectedCategory.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(whole(share.monthlyCost))
                    .font(.amount(.title3, weight: .bold))
                Text((Double(share.percent) / 100).formatted(.percent.precision(.fractionLength(0))))
                    .font(.amount(.caption))
                    .foregroundStyle(.secondary)
            } else {
                Text("Per måned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(whole(total))
                    .font(.amount(.title3, weight: .bold))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: 130)
        .allowsHitTesting(false)
    }

    // MARK: - Dyreste

    private func mostExpensiveSection(_ viewModel: StatisticsViewModel) -> some View {
        let items = viewModel.mostExpensiveSubscriptions(limit: 5, in: selectedCategory)
        let maxCost = items.first?.monthlyCost ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dyreste abonnement")
                    .font(.rounded(.title3))
                    .accessibilityAddTraits(.isHeader)
                if let selectedCategory {
                    Text("Bare \(selectedCategory.displayName.lowercased())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // Navn og beløp ligger inni raden, oppå stolpen, så de aldri overlapper den.
            VStack(spacing: 8) {
                ForEach(items) { item in
                    ExpensiveRow(
                        item: item,
                        subscription: subscriptions.first { $0.id == item.id },
                        fraction: maxCost > 0 ? min(max(item.monthlyCost.doubleValue / maxCost.doubleValue, 0), 1) : 0,
                        currencyCode: mainCurrency
                    )
                }
            }
            .motion(.smooth, value: selectedCategory)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .card()
    }

    // MARK: - Kostnad framover

    private var forwardCostSection: some View {
        let result = ForwardCost.months(of: subscriptions) { amount, code in
            CurrencyConverter.convert(amount, from: code, to: mainCurrency, using: exchangeRates.rates)
        }
        let highlighted = result.months.first { $0.monthStart == selectedMonth } ?? result.peak

        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Kostnad framover", trailing: whole(result.total))
            Text("De neste 12 månedene, med årlige trekk der de faller.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let highlighted {
                VStack(alignment: .leading, spacing: 2) {
                    Text(highlighted.monthStart.formatted(.dateTime.month(.wide).year()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(whole(highlighted.total))
                        .font(.amount(.title2, weight: .bold))
                        .numericMotion(highlighted.total)
                    Text(highlighted.chargeCount == 1 ? "1 trekk" : "\(highlighted.chargeCount) trekk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            let maxTotal = result.months.map(\.total).max() ?? 0
            HStack(alignment: .bottom, spacing: dynamicTypeSize.isAccessibilitySize ? 2 : 5) {
                ForEach(result.months) { month in
                    MonthBar(
                        month: month,
                        fraction: maxTotal > 0 ? month.total.doubleValue / maxTotal.doubleValue : 0,
                        isHighlighted: month.id == highlighted?.id,
                        currencyCode: mainCurrency
                    ) {
                        selectedMonth = selectedMonth == month.monthStart ? nil : month.monthStart
                    }
                }
            }
            .motion(.smooth, value: selectedMonth)

            if result.excludedCount > 0 {
                Text("\(result.excludedCount) trekk uten valutakurs er ikke tatt med.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Den første måneden teller bare trekk fra og med i dag.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .card()
        .sensoryFeedback(.selection, trigger: selectedMonth)
    }
}

// MARK: - Deler

/// Beløp som teller opp fra null første gang kortet vises, og ruller når det endres.
/// Står stille ved «Reduser bevegelse».
private struct CountingAmount: View {
    let amount: Decimal
    let currencyCode: String

    @State private var shown: Decimal = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 42

    var body: some View {
        Text(Money.string(shown, code: currencyCode, whole: true))
            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.savings)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .numericMotion(shown)
            .onAppear { update() }
            .onChange(of: amount) { update() }
    }

    private func update() {
        if reduceMotion {
            shown = amount
        } else {
            withAnimation(.smooth(duration: 1.1)) { shown = amount }
        }
    }
}

/// En kategori i listen under diagrammet: ikon, navn, andel og beløp. Trykk viser abonnementene.
private struct CategoryRow: View {
    let share: CategoryShare
    let currencyCode: String
    let isSelected: Bool
    let members: [ConvertedSubscription]
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var percentText: String {
        (Double(share.percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    SubscriptionTile(
                        symbolName: share.category.defaultSymbolName,
                        color: share.category.chartColor,
                        size: 34
                    )
                    Text(share.category.displayName)
                        .font(.subheadline.weight(.semibold))
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 8)
                    }
                    HStack(spacing: 10) {
                        Text(percentText)
                            .font(.amount(.subheadline, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text(Money.string(share.monthlyCost, code: currencyCode, whole: true))
                            .font(.amount(.subheadline))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(isSelected ? "Skjuler abonnementene i kategorien." : "Viser abonnementene i kategorien.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected {
                VStack(spacing: 6) {
                    ForEach(members) { member in
                        HStack {
                            Text(member.name)
                                .font(.subheadline)
                            Spacer(minLength: 8)
                            Text(Money.string(member.monthlyCost, code: currencyCode))
                                .font(.amount(.subheadline, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.leading, 56)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(share.category.chartColor.opacity(0.12))
            }
        }
    }
}

/// Et av de dyreste abonnementene: en stolpe i abonnementets farge som viser kostnaden relativt
/// til det dyreste, med ikon, navn og beløp inni raden.
private struct ExpensiveRow: View {
    let item: ConvertedSubscription
    let subscription: Subscription?
    let fraction: Double
    let currencyCode: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var color: Color { subscription?.displayColor ?? Color.accentColor }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            SubscriptionTile(
                symbolName: subscription?.displaySymbolName ?? item.category.defaultSymbolName,
                color: color,
                size: 30
            )
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            Text(Money.string(item.monthlyCost, code: currencyCode))
                .font(.amount(.subheadline))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.26))
                    .frame(width: max(proxy.size.width * fraction, 30))
            }
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// En måned i «Kostnad framover». Stolpehøyden er relativ til den dyreste måneden.
private struct MonthBar: View {
    let month: MonthCost
    let fraction: Double
    let isHighlighted: Bool
    let currencyCode: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let maxBarHeight: CGFloat = 110

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(isHighlighted ? 1 : 0.42))
                    .frame(height: max(4, maxBarHeight * fraction))
                Text(month.monthStart.formatted(.dateTime.month(.narrow)))
                    .font(.caption2.weight(isHighlighted ? .bold : .regular))
                    .foregroundStyle(isHighlighted ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: maxBarHeight + 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(month.monthStart.formatted(.dateTime.month(.wide).year()))
        .accessibilityValue(Money.string(month.total, code: currencyCode, whole: true))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
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
        case .nyheter: .brown
        case .boker: .green
        case .spill: .chartYellow
        case .ai: .indigo
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
