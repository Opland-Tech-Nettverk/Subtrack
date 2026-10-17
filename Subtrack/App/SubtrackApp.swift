import SwiftUI
import SwiftData
import UserNotifications

@main
struct SubtrackApp: App {
    // Holdt som en egen, sterk referanse siden UNUserNotificationCenter.delegate er svak.
    private let notificationDelegate = NotificationDelegate()
    @State private var exchangeRates = ExchangeRateStore()
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationScheduler.registerCategories()
        #if DEBUG
        CloudKitSchemaInitializer.runIfRequested()
        #endif
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(exchangeRates)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    Task { await exchangeRates.refreshIfNeeded() }
                }
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        // UI-tester starter med en tom database i minnet, så de aldri rører ekte data eller iCloud.
        let configuration = AppEnvironment.isUITesting
            ? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            // Synkroniserer automatisk med iCloud når appen har iCloud/CloudKit-capability:
            // SwiftData finner containeren i entitlements. Uten den lagres alt bare lokalt.
            : ModelConfiguration()
        do {
            return try ModelContainer(for: Subscription.self, configurations: configuration)
        } catch {
            fatalError("Kunne ikke åpne databasen: \(error)")
        }
    }
}

/// Hvordan appen er startet.
enum AppEnvironment {
    /// Satt av UI-testene med oppstartsparameteren `-UITesting`.
    nonisolated static let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
}
