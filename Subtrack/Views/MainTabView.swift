import SwiftUI
import SwiftData

/// Fanene i appens rot-navigasjon.
enum AppTab: Hashable {
    case overview, statistics
}

/// Appens rot-navigasjon: oversikten over abonnement og statistikkskjermen.
struct MainTabView: View {
    @State private var selectedTab: AppTab = .overview
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            SubscriptionListView()
                .tabItem {
                    Label("Oversikt", systemImage: "list.bullet")
                }
                .tag(AppTab.overview)

            StatisticsView(showOverview: { selectedTab = .overview })
                .tabItem {
                    Label("Statistikk", systemImage: "chart.pie")
                }
                .tag(AppTab.statistics)
        }
        // Utkast, f.eks. fra snarveien, vises i skjemaet fra oversikten. `initial` fanger
        // opp et utkast som kom før visningen ble vist.
        .onChange(of: AddSubscriptionRouter.shared.hasPendingDrafts, initial: true) {
            showOverviewIfDraftsArePending()
        }
        .onChange(of: scenePhase) {
            showOverviewIfDraftsArePending()
        }
    }

    /// Bare i det aktive vinduet, så et vindu i bakgrunnen på iPad ikke bytter fane.
    private func showOverviewIfDraftsArePending() {
        guard scenePhase == .active, AddSubscriptionRouter.shared.hasPendingDrafts else { return }
        selectedTab = .overview
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: Subscription.self, inMemory: true)
        .environment(ExchangeRateStore())
}
