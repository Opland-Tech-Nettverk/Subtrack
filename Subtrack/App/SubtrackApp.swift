import SwiftUI
import SwiftData
import UserNotifications
import OSLog

@main
struct SubtrackApp: App {
    // Holdt som en egen, sterk referanse siden UNUserNotificationCenter.delegate er svak.
    private let notificationDelegate = NotificationDelegate()
    @State private var exchangeRates = ExchangeRateStore()
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer
    private let databaseState: DatabaseState

    private static let logger = Logger(subsystem: "com.opland.subtrack", category: "Database")

    /// Alle containere åpnes med det versjonerte skjemaet, så fremtidige skjemaendringer
    /// kan migreres trygt. Se `SubtrackSchema.swift`.
    private static var schema: Schema {
        Schema(versionedSchema: SubtrackSchemaV1.self)
    }

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationScheduler.registerCategories()
        #if DEBUG
        CloudKitSchemaInitializer.runIfRequested()
        #endif
        let setup = Self.makeModelContainer()
        modelContainer = setup.container
        databaseState = setup.state
        Self.enqueueUITestShortcutDraftIfRequested()
    }

    /// UI-testene starter appen med `-UITestingShortcutDraft <navn>` for å late som snarveien
    /// «Legg til abonnement» ble kjørt. Utkastet lages på samme måte som i snarveien.
    private static func enqueueUITestShortcutDraftIfRequested() {
        guard AppEnvironment.isUITesting,
              let name = UserDefaults.standard.string(forKey: "UITestingShortcutDraft")
        else { return }
        let draft = ShortcutDraftBuilder.makeDraft(
            name: name,
            price: nil,
            interval: nil,
            category: nil,
            nextRenewalDate: nil
        )
        AddSubscriptionRouter.shared.enqueue(draft)
    }

    var body: some Scene {
        WindowGroup {
            switch databaseState {
            case .normal, .localOnly:
                MainTabView()
                    .keepsDerivedStateInSync()
                    .environment(exchangeRates)
                    .onChange(of: scenePhase, initial: true) { _, phase in
                        guard phase == .active else { return }
                        Task { await exchangeRates.refreshIfNeeded() }
                    }
            case .failed(let errorDescription):
                DatabaseErrorView(errorDescription: errorDescription)
                    .environment(exchangeRates)
            }
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer() -> (container: ModelContainer, state: DatabaseState) {
        // UI-tester starter med en tom database i minnet, så de aldri rører ekte data eller iCloud.
        if AppEnvironment.isUITesting {
            return (makeInMemoryContainer(), .normal)
        }

        // Synkroniserer automatisk med iCloud når appen har iCloud/CloudKit-capability:
        // SwiftData finner containeren i entitlements. Uten den lagres alt bare lokalt.
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: SubtrackMigrationPlan.self,
                configurations: ModelConfiguration()
            )
            return (container, .normal)
        } catch {
            logger.error("Kunne ikke åpne databasen med iCloud-synk: \(String(describing: error), privacy: .public)")
        }

        // Samme fil på disk, men uten CloudKit. Feil som skyldes iCloud stopper da ikke
        // appen, og brukeren ser fortsatt dataene sine.
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: SubtrackMigrationPlan.self,
                configurations: ModelConfiguration(cloudKitDatabase: .none)
            )
            logger.warning("Databasen er åpnet uten iCloud-synk. Endringer lagres bare lokalt.")
            return (container, .localOnly)
        } catch {
            // Databasen på disk blir aldri slettet eller overskrevet automatisk. Appen starter
            // med en tom database i minnet og viser en feilskjerm i stedet.
            logger.fault("Kunne ikke åpne databasen på disk: \(String(describing: error), privacy: .public)")
            return (makeInMemoryContainer(), .failed(String(describing: error)))
        }
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SubtrackMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            )
        } catch {
            // En database i minnet feiler bare hvis selve modellen er ugyldig. Da finnes ingen vei videre.
            fatalError("Kunne ikke opprette databasen i minnet: \(error)")
        }
    }
}

/// Hvordan databasen ble åpnet ved oppstart.
enum DatabaseState {
    /// Databasen på disk, med iCloud-synk hvis den er tilgjengelig.
    case normal
    /// Databasen på disk, men uten iCloud-synk fordi CloudKit-oppsettet feilet.
    case localOnly
    /// Databasen på disk kunne ikke åpnes. Inneholder den tekniske feilbeskrivelsen.
    case failed(String)
}

/// Hvordan appen er startet.
enum AppEnvironment {
    /// Satt av UI-testene med oppstartsparameteren `-UITesting`.
    nonisolated static let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
}
