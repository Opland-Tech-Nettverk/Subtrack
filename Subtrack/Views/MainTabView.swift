import SwiftUI
import SwiftData

/// Fanene i appens rot-navigasjon.
enum AppTab: Hashable {
    case overview, statistics
}

/// Appens rot-navigasjon: oversikten over abonnement og statistikkskjermen.
struct MainTabView: View {
    @State private var selectedTab: AppTab = .overview

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
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: Subscription.self, inMemory: true)
        .environment(ExchangeRateStore())
}
