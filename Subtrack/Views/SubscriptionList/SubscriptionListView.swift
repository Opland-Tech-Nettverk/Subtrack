import SwiftUI
import SwiftData

struct SubscriptionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @AppStorage(AppSettingsKeys.sortOrder) private var sortOrder: SubscriptionSortOrder = .renewal
    @Query(sort: \Subscription.nextRenewalDate) private var subscriptions: [Subscription]

    @State private var editingSubscription: Subscription?
    @State private var isAddingSubscription = false
    @State private var isShowingSettings = false
    @State private var searchText = ""
    // Økes for å utløse haptisk tilbakemelding.
    @State private var pauseFeedbackTrigger = 0
    @State private var archiveFeedbackTrigger = 0

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var archivedSubscriptions: [Subscription] {
        subscriptions.filter(\.isCancelled)
    }

    /// Abonnementene som vises i listen: ikke avsluttede, filtrert på søk og sortert.
    private var visibleSubscriptions: [Subscription] {
        let current = subscriptions.filter { !$0.isCancelled && $0.matches(searchText: searchText) }
        return sortOrder.sorted(current) { subscription in
            CurrencyConverter.convert(
                subscription.monthlyCost,
                from: subscription.currencyCode,
                to: mainCurrency,
                using: exchangeRates.rates
            )
        }
    }

    /// Ved sortering på kategori får hver kategori sin egen seksjon; ellers én felles.
    private var sections: [(title: String, subscriptions: [Subscription])] {
        let visible = visibleSubscriptions
        guard sortOrder == .category else {
            return visible.isEmpty ? [] : [("Abonnementer", visible)]
        }
        var result: [(title: String, subscriptions: [Subscription])] = []
        for subscription in visible {
            let title = subscription.kind.displayName
            if result.last?.title == title {
                result[result.count - 1].subscriptions.append(subscription)
            } else {
                result.append((title, [subscription]))
            }
        }
        return result
    }

    private var totalSaved: Decimal {
        CurrencyConverter.total(
            of: archivedSubscriptions.map { ($0.savedSinceCancellation(), $0.currencyCode) },
            in: mainCurrency,
            using: exchangeRates.rates
        ).amount
    }

    var body: some View {
        NavigationStack {
            Group {
                if subscriptions.isEmpty {
                    EmptyStateView()
                } else {
                    list
                }
            }
            .navigationTitle("Subtrack")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Innstillinger", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sorter etter", selection: $sortOrder) {
                            ForEach(SubscriptionSortOrder.allCases) { order in
                                Label(order.displayName, systemImage: order.symbolName).tag(order)
                            }
                        }
                    } label: {
                        Label("Sorter", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingSubscription = true
                    } label: {
                        Label("Legg til", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingSubscription) {
                SubscriptionFormView()
            }
            .sheet(item: $editingSubscription) { subscription in
                SubscriptionFormView(subscriptionToEdit: subscription)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: pauseFeedbackTrigger)
            .sensoryFeedback(.impact(weight: .medium), trigger: archiveFeedbackTrigger)
            // Kjør hver gang appen blir aktiv, ikke bare første gang: med iCloud-synk kan
            // abonnement ha endret seg på en annen enhet mens appen lå i bakgrunnen.
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                refreshDerivedState()
            }
            // Abonnement lagt til eller slettet via synk mens appen er åpen.
            .onChange(of: subscriptions.map(\.id)) {
                refreshDerivedState()
            }
        }
    }

    private var list: some View {
        List {
            if !isSearching {
                Section {
                    SummaryHeaderView(subscriptions: subscriptions)
                        .accessibilityIdentifier("summary")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.subscriptions) { subscription in
                        row(for: subscription)
                    }
                }
            }

            if !isSearching && !archivedSubscriptions.isEmpty {
                Section {
                    NavigationLink {
                        ArchivedSubscriptionsView()
                    } label: {
                        LabeledContent {
                            Text("spart \(totalSaved.formatted(.currency(code: mainCurrency)))")
                                .foregroundStyle(.green)
                        } label: {
                            Label("Avsluttede (\(archivedSubscriptions.count))", systemImage: "archivebox")
                        }
                    }
                }
            }
        }
        .readableContentWidth()
        .searchable(text: $searchText, prompt: "Søk i navn eller kategori")
        .overlay {
            if isSearching && sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .animation(.smooth, value: sortOrder)
    }

    private func row(for subscription: Subscription) -> some View {
        SubscriptionRow(subscription: subscription)
            .accessibilityIdentifier("subscription.\(subscription.name)")
            .contentShape(Rectangle())
            .onTapGesture { editingSubscription = subscription }
            .swipeActions(edge: .trailing) {
                // Avslutt flytter til arkivet i stedet for å slette, så det kan angres
                // og besparelsen vises. Sletting for godt skjer fra arkivet.
                Button {
                    archive(subscription)
                } label: {
                    Label("Avslutt", systemImage: "archivebox")
                }
                .tint(.red)
                Button("Rediger") {
                    editingSubscription = subscription
                }
                .tint(.blue)
            }
            .swipeActions(edge: .leading) {
                Button(subscription.isActive ? "Pause" : "Gjenoppta") {
                    withAnimation(.smooth) {
                        subscription.isActive.toggle()
                    }
                    pauseFeedbackTrigger += 1
                    WidgetSnapshotStore.update(with: subscriptions)
                    Task { await NotificationScheduler.reschedule(for: subscriptions) }
                }
                .tint(subscription.isActive ? .orange : .green)
            }
    }

    private func archive(_ subscription: Subscription) {
        withAnimation(.smooth) {
            subscription.cancelledDate = .now
        }
        archiveFeedbackTrigger += 1
        WidgetSnapshotStore.update(with: subscriptions)
        Task { await NotificationScheduler.reschedule(for: subscriptions) }
    }

    /// Holder datoer, widget og varsler i takt med dataene.
    private func refreshDerivedState() {
        for subscription in subscriptions where !subscription.isCancelled {
            subscription.advanceRenewalDateIfPast()
        }
        WidgetSnapshotStore.update(with: subscriptions)
        Task { await NotificationScheduler.reschedule(for: subscriptions) }
    }
}

#Preview("Tom") {
    SubscriptionListView()
        .modelContainer(for: Subscription.self, inMemory: true)
        .environment(ExchangeRateStore())
}

#Preview("Med data") {
    let container = try! ModelContainer(for: Subscription.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let calendar = Calendar.current
    let cancelled = Subscription(name: "HBO Max", price: 129, category: .streaming)
    cancelled.cancelledDate = calendar.date(byAdding: .month, value: -2, to: .now)
    for subscription in [
        Subscription(name: "Netflix", price: 149, nextRenewalDate: calendar.date(byAdding: .day, value: 2, to: .now)!, category: .streaming),
        Subscription(name: "Spotify Family", price: 279, nextRenewalDate: calendar.date(byAdding: .day, value: 9, to: .now)!, category: .musikk, splitCount: 3),
        Subscription(name: "Adobe Creative Cloud", price: 699, nextRenewalDate: calendar.date(byAdding: .day, value: 20, to: .now)!, category: .programvare),
        Subscription(name: "iCloud+", price: 39, nextRenewalDate: calendar.date(byAdding: .day, value: 25, to: .now)!, category: .nettsky),
        cancelled
    ] {
        container.mainContext.insert(subscription)
    }
    return MainTabView()
        .modelContainer(container)
        .environment(ExchangeRateStore())
}
