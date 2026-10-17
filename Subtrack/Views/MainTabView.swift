import SwiftUI
import SwiftData

/// Appens rot-navigasjon: oversikten over abonnement og statistikkskjermen.
struct MainTabView: View {
    var body: some View {
        TabView {
            SubscriptionListView()
                .tabItem {
                    Label("Oversikt", systemImage: "list.bullet")
                }

            StatisticsView()
                .tabItem {
                    Label("Statistikk", systemImage: "chart.pie")
                }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: Subscription.self, inMemory: true)
        .environment(ExchangeRateStore())
}
