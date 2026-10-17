import Foundation
import SwiftData

// Versjonert skjema for databasen. V1 er utgangspunktet: dagens modell, slik byggene
// til og med 6 har skrevet den, inkludert de utfasede feltene `category` og `billingInterval`.
//
// Slik lages V2 senere:
// 1. Frys en kopi av dagens `Subscription` inne i `SubtrackSchemaV1` (f.eks.
//    `SubtrackSchemaV1.Subscription`), slik at V1 alltid beskriver det som ligger på disk.
// 2. Legg til `SubtrackSchemaV2` med den nye modellen og `Schema.Version(2, 0, 0)`.
// 3. Legg V2 til i `schemas` og et `MigrationStage.lightweight(fromVersion:toVersion:)` i `stages`.
//
// Med CloudKit-synk er bare lette (additive) endringer lov: nye felt som er valgfrie eller
// har en standardverdi. Aldri egne (custom) steg som gir felt nytt navn eller fjerner dem -
// eldre versjoner på andre enheter leser fortsatt de samme postene.

// nonisolated fordi target-et er bundet til MainActor som standard, mens kravene i
// VersionedSchema og SchemaMigrationPlan ikke er det.
nonisolated enum SubtrackSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Subscription.self]
    }
}

nonisolated enum SubtrackMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SubtrackSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
