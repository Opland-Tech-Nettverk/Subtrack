import SwiftUI
import SwiftData

/// Avsluttede abonnement, med hva hvert av dem har spart siden det ble avsluttet.
struct ArchivedSubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subscription.name) private var subscriptions: [Subscription]

    @State private var subscriptionPendingDeletion: Subscription?
    @State private var restoreFeedbackTrigger = 0
    @State private var deleteFeedbackTrigger = 0

    private var archived: [Subscription] {
        subscriptions
            .filter(\.isCancelled)
            .sorted { ($0.cancelledDate ?? .distantPast) > ($1.cancelledDate ?? .distantPast) }
    }

    var body: some View {
        Group {
            if archived.isEmpty {
                ContentUnavailableView(
                    "Ingen avsluttede abonnement",
                    systemImage: "archivebox",
                    description: Text("Når du avslutter et abonnement, havner det her, så du ser hva du har spart.")
                )
            } else {
                list
            }
        }
        .navigationTitle("Avsluttede")
        .confirmationDialog(
            "Slette \(subscriptionPendingDeletion?.name ?? "abonnementet") for godt?",
            isPresented: Binding(
                get: { subscriptionPendingDeletion != nil },
                set: { isPresented in if !isPresented { subscriptionPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Slett", role: .destructive) {
                if let subscription = subscriptionPendingDeletion {
                    modelContext.delete(subscription)
                    deleteFeedbackTrigger += 1
                }
                subscriptionPendingDeletion = nil
            }
            Button("Avbryt", role: .cancel) {
                subscriptionPendingDeletion = nil
            }
        } message: {
            Text("Det du har spart på dette abonnementet blir også borte. Dette kan ikke angres.")
        }
        .sensoryFeedback(.success, trigger: restoreFeedbackTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteFeedbackTrigger)
    }

    private var list: some View {
        List {
            Section {
                TotalSavingsView(subscriptions: archived)
                    .bareRowStyle()
            }

            Section {
                ForEach(archived) { subscription in
                    ArchivedRow(subscription: subscription)
                        .cardRowStyle()
                        .swipeActions(edge: .leading) {
                            Button("Gjenoppta") { restore(subscription) }
                                .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Slett", role: .destructive) {
                                subscriptionPendingDeletion = subscription
                            }
                        }
                        // Samme handlinger som sveipene, for dem som ikke oppdager eller kan sveipe.
                        .contextMenu {
                            Button {
                                restore(subscription)
                            } label: {
                                Label("Gjenoppta", systemImage: "arrow.uturn.backward")
                            }
                            Button(role: .destructive) {
                                // Går via bekreftelsen, akkurat som sveipet.
                                subscriptionPendingDeletion = subscription
                            } label: {
                                Label("Slett for godt", systemImage: "trash")
                            }
                        }
                }
            } footer: {
                Text("Sveip, eller hold inne på et abonnement, for å gjenoppta eller slette det for godt.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .listSectionSpacing(14)
        .readableContentWidth()
    }

    private func restore(_ subscription: Subscription) {
        withAnimation(.smooth) {
            subscription.cancelledDate = nil
            subscription.advanceRenewalDateIfPast()
        }
        restoreFeedbackTrigger += 1
        // Widget og varsler oppdateres av `keepsDerivedStateInSync()`, også ved sletting.
    }
}

/// Total besparelse for alle avsluttede abonnement, omregnet til hovedvalutaen.
private struct TotalSavingsView: View {
    let subscriptions: [Subscription]

    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @Environment(ExchangeRateStore.self) private var exchangeRates

    private var total: ConvertedTotal {
        CurrencyConverter.total(
            of: subscriptions.map { ($0.savedSinceCancellation(), $0.currencyCode) },
            in: mainCurrency,
            using: exchangeRates.rates
        )
    }

    private var yearlySavings: ConvertedTotal {
        CurrencyConverter.total(
            // Abonnement som var pauset da de ble avsluttet, sparer ingenting fremover.
            of: subscriptions.map { ($0.projectedYearlySavings, $0.currencyCode) },
            in: mainCurrency,
            using: exchangeRates.rates
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("Spart så langt")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(Money.string(total.amount, code: mainCurrency))
                .font(.amount(.largeTitle, weight: .bold))
                .foregroundStyle(Color.savings)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .numericMotion(total.amount)
            Text("\(Money.string(yearlySavings.amount, code: mainCurrency, whole: true)) per år fremover")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if total.excludedCount > 0 {
                Text("\(total.excludedCount) abonnement uten valutakurs er ikke tatt med")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
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
}

private struct ArchivedRow: View {
    let subscription: Subscription

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AdaptiveRowLayout(isStacked: dynamicTypeSize.isAccessibilitySize) {
            SubscriptionTile(symbolName: subscription.displaySymbolName, color: .gray)
        } title: {
            Text(subscription.name)
                .font(.body.weight(.semibold))
            if let cancelledDate = subscription.cancelledDate {
                Text("Avsluttet \(cancelledDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } detail: {
            Text(Money.string(subscription.savedSinceCancellation(), code: subscription.currencyCode))
                .font(.amount(.body))
                .foregroundStyle(Color.savings)
            Text("spart")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = try! ModelContainer(for: Subscription.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let netflix = Subscription(name: "Netflix", price: 149, category: .streaming)
    netflix.cancelledDate = Calendar.current.date(byAdding: .month, value: -3, to: .now)
    let gym = Subscription(name: "Fitness24", price: 399, category: .trening)
    gym.cancelledDate = Calendar.current.date(byAdding: .day, value: -20, to: .now)
    container.mainContext.insert(netflix)
    container.mainContext.insert(gym)

    return NavigationStack {
        ArchivedSubscriptionsView()
    }
    .modelContainer(container)
    .environment(ExchangeRateStore())
}
