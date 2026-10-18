import SwiftUI
import SwiftData
import Accessibility

/// Oversikten over abonnementene. Endrer bare modellene: datoer, widget og varsler
/// holdes i takt av `keepsDerivedStateInSync()` på roten av appen.
struct SubscriptionListView: View {
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @AppStorage(AppSettingsKeys.sortOrder) private var sortOrder: SubscriptionSortOrder = .renewal
    @Query(sort: \Subscription.nextRenewalDate) private var subscriptions: [Subscription]

    @State private var editingSubscription: Subscription?
    @State private var isAddingSubscription = false
    @State private var isShowingSettings = false
    /// Utkastet fra `AddSubscriptionRouter` som vises i skjemaet nå, f.eks. fra snarveien.
    @State private var presentedDraft: SubscriptionDraft?
    /// Om oversikten er fanen som vises. Et utkast vises ikke fra en skjult fane; da venter
    /// det til fanen er byttet.
    @State private var isOnScreen = false
    @State private var searchText = ""
    // Økes for å utløse haptisk tilbakemelding.
    @State private var pauseFeedbackTrigger = 0
    @State private var archiveFeedbackTrigger = 0
    /// Sist avsluttede abonnement, som kan angres fra banneret nederst en liten stund.
    @State private var archiveNotice: ArchiveNotice?
    @State private var archiveNoticeDismissal: Task<Void, Never>?

    /// Navnet tas vare på for seg, så banneret aldri leser fra en modell som er slettet i mellomtiden.
    /// Avslutningstidspunktet skiller denne avslutningen fra en senere av samme abonnement.
    private struct ArchiveNotice {
        let subscription: Subscription
        let name: String
        let cancelledDate: Date
    }

    /// Banneret vises bare så lenge abonnementet fortsatt er avsluttet fra akkurat denne
    /// avslutningen. Er det gjenopptatt fra arkivet, slettet for godt eller avsluttet på nytt
    /// et annet sted, er det ingenting å angre her.
    private var visibleArchiveNotice: ArchiveNotice? {
        guard let archiveNotice,
              subscriptions.contains(where: {
                  $0 === archiveNotice.subscription && $0.cancelledDate == archiveNotice.cancelledDate
              })
        else { return nil }
        return archiveNotice
    }

    /// Lenge nok til å rekke å angre. Med VoiceOver tar det lengre tid å finne knappen.
    private var archiveNoticeDuration: Duration {
        voiceOverEnabled ? .seconds(10) : .seconds(5)
    }

    /// Felles for hele appen. Lesingen av køen i `body` spores av Observation, så visningen
    /// oppdateres når snarveien legger til et utkast.
    private var router: AddSubscriptionRouter { .shared }

    /// Et ark herfra er åpent. Et nytt utkast venter da til arket er lukket, så det brukeren
    /// holder på med, aldri blir erstattet.
    private var isShowingSheet: Bool {
        isAddingSubscription || editingSubscription != nil || isShowingSettings || presentedDraft != nil
    }

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
            // Hvert ark ser etter neste utkast når det er helt lukket, så utkast som kom
            // mens det var åpent, vises etterpå, ett om gangen.
            .sheet(isPresented: $isAddingSubscription, onDismiss: presentNextDraft) {
                SubscriptionFormView()
            }
            .sheet(item: $editingSubscription, onDismiss: presentNextDraft) { subscription in
                // Avslutt fra skjemaet går gjennom listen, så det får samme angre-banner,
                // VoiceOver-beskjed og haptikk som fra sveip og hurtigmeny. Banneret ligger
                // på listen og er synlig når arket har lukket seg.
                SubscriptionFormView(subscriptionToEdit: subscription, onArchive: { archive($0) })
            }
            .sheet(isPresented: $isShowingSettings, onDismiss: presentNextDraft) {
                SettingsView()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: pauseFeedbackTrigger)
            .sensoryFeedback(.impact(weight: .medium), trigger: archiveFeedbackTrigger)
        }
        // På navigasjonsstakken og ikke på listen, så utkastet også vises når arkivet er åpnet.
        .sheet(item: $presentedDraft, onDismiss: presentNextDraft) { draft in
            SubscriptionFormView(draft: draft)
        }
        // Køen går fra tom til ikke tom. Flere utkast etter hverandre vises via onDismiss over.
        .onChange(of: router.hasPendingDrafts) {
            presentNextDraft()
        }
        // Et utkast fra snarveien kommer ofte mens appen åpnes, før vinduet er aktivt.
        .onChange(of: scenePhase) {
            presentNextDraft()
        }
        // Bytte av fane gir onAppear og onDisappear her, men ikke det å åpne arkivet.
        .onAppear {
            isOnScreen = true
            presentNextDraft()
        }
        .onDisappear {
            isOnScreen = false
        }
    }

    /// Viser det eldste ventende utkastet, men bare når oversikten vises i et aktivt vindu og
    /// ingen ark er åpne. Med flere vinduer på iPad tar da ikke et vindu i bakgrunnen utkastet.
    private func presentNextDraft() {
        guard scenePhase == .active, isOnScreen, !isShowingSheet, let draft = router.dequeue() else { return }
        presentedDraft = draft
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
                                .foregroundStyle(Color.savings)
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
        .safeAreaInset(edge: .bottom) {
            if let notice = visibleArchiveNotice {
                undoBanner(for: notice)
            }
        }
        .animation(.smooth, value: sortOrder)
    }

    private func row(for subscription: Subscription) -> some View {
        // En ekte knapp, så VoiceOver sier «knapp» og raden markeres når man trykker.
        Button {
            editingSubscription = subscription
        } label: {
            SubscriptionRow(subscription: subscription)
                // Ellers farger knappen navnet med aksentfargen; raden skal se ut som før.
                // `Color.primary` og ikke `.primary`, som er hierarkisk og kan arve knappens farge.
                .foregroundStyle(Color.primary)
        }
        .accessibilityIdentifier("subscription.\(subscription.name)")
        .accessibilityHint("Åpner abonnementet for redigering.")
        // Ingen full sveip: Avslutt skal ikke skje ved et uhell, bare ved trykk på knappen.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
                togglePause(subscription)
            }
            .tint(subscription.isActive ? .orange : .green)
        }
        // De samme handlingene ved å holde inne, for dem som ikke finner sveipene.
        .contextMenu {
            Button {
                editingSubscription = subscription
            } label: {
                Label("Rediger", systemImage: "pencil")
            }
            Button {
                togglePause(subscription)
            } label: {
                Label(
                    subscription.isActive ? "Pause" : "Gjenoppta",
                    systemImage: subscription.isActive ? "pause" : "play"
                )
            }
            Button(role: .destructive) {
                archive(subscription)
            } label: {
                Label("Avslutt", systemImage: "archivebox")
            }
        }
    }

    /// Kort beskjed nederst etter at et abonnement er avsluttet, med mulighet til å angre.
    private func undoBanner(for notice: ArchiveNotice) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        return layout {
            Text("«\(notice.name)» er avsluttet")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Angre", action: undoArchive)
                .buttonStyle(UndoButtonStyle())
                .accessibilityIdentifier("undoArchive")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .frame(maxWidth: 720)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        // Uten bevegelse ved Reduser bevegelse: banneret tones bare inn og ut.
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    private func togglePause(_ subscription: Subscription) {
        withAnimation(.smooth) {
            subscription.isActive.toggle()
        }
        pauseFeedbackTrigger += 1
    }

    private func archive(_ subscription: Subscription) {
        let name = subscription.name
        // Samme verdi i modellen og i banneret, så banneret kjenner igjen akkurat denne avslutningen.
        let now = Date.now
        withAnimation(.smooth) {
            subscription.cancelledDate = now
            archiveNotice = ArchiveNotice(subscription: subscription, name: name, cancelledDate: now)
        }
        archiveFeedbackTrigger += 1
        // Raden forsvinner uten at noe annet sier fra, så VoiceOver får beskjed om hva som skjedde.
        // Høy prioritet, så beskjeden ikke avbrytes av at fokus flytter seg fra raden som forsvant.
        var announcement = AttributedString("\(name) er avsluttet")
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()

        // Et nytt avslutt erstatter forrige banner og starter nedtellingen på nytt.
        archiveNoticeDismissal?.cancel()
        let duration = archiveNoticeDuration
        archiveNoticeDismissal = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) {
                archiveNotice = nil
            }
        }
    }

    private func undoArchive() {
        archiveNoticeDismissal?.cancel()
        archiveNoticeDismissal = nil
        withAnimation(.smooth) {
            // Bare om abonnementet fortsatt finnes og er avsluttet fra denne avslutningen;
            // ellers er det ingenting å angre.
            if let notice = visibleArchiveNotice {
                notice.subscription.cancelledDate = nil
            }
            archiveNotice = nil
        }
    }
}

/// Angre-knappen i banneret: ser ut som en kapsel med aksentfarge, men trykkflaten er minst
/// 44 × 44 pt. Banneret forsvinner etter noen sekunder, så et bom skal ikke koste angringen.
/// Egen stil i stedet for `.bordered`, fordi trykkflaten da kan gjøres større enn kapselen
/// uten at kapselen selv blir høyere og gjør banneret klumpete.
private struct UndoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.tint.opacity(configuration.isPressed ? 0.25 : 0.15), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            // Utenfor kapselen, så hele flaten på minst 44 × 44 pt tar imot trykket.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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
