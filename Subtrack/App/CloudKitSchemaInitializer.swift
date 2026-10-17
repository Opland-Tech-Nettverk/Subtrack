#if DEBUG
import CoreData
import SwiftData

/// Oppretter CloudKit-skjemaet i utviklingsmiljøet med *alle* felt, også valgfrie felt
/// som ingen abonnement har brukt ennå. CloudKit lager ellers bare felt den har sett data
/// i, og da ville f.eks. prøveperioder feilet i produksjon. Finnes bare i debug-bygg og
/// kjøres kun med launch-argumentet `-InitializeCloudKitSchema`.
/// Fremgangsmåten følger Apples "Syncing model data across a person's devices".
enum CloudKitSchemaInitializer {
    static let containerIdentifier = "iCloud.com.opland.subtrack"
    static let launchArgument = "-InitializeCloudKitSchema"

    // nonisolated så Error-konformansen ikke blir bundet til MainActor.
    nonisolated private enum SchemaError: Error {
        /// Core Data klarte ikke å lage en modell fra SwiftData-typene.
        case couldNotBuildModel
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }

        do {
            // autoreleasepool sørger for at Core Data-stacken er borte før SwiftData starter.
            try autoreleasepool {
                let description = NSPersistentStoreDescription(url: ModelConfiguration().url)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: containerIdentifier
                )
                description.shouldAddStoreAsynchronously = false

                // `return` her ville bare forlatt closuren og skrevet ut "initialisert" likevel.
                guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [Subscription.self]) else {
                    throw SchemaError.couldNotBuildModel
                }
                let container = NSPersistentCloudKitContainer(name: "Subtrack", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]

                var loadError: Error?
                container.loadPersistentStores { _, error in loadError = error }
                if let loadError { throw loadError }

                try container.initializeCloudKitSchema()

                if let store = container.persistentStoreCoordinator.persistentStores.first {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
            print("CLOUDKIT_SCHEMA: initialisert")
        } catch {
            print("CLOUDKIT_SCHEMA: feilet - \(error)")
        }
    }
}
#endif
