import OSLog
import SwiftUI
import SwiftData

/// Holder datoer, widget og varsler i takt med dataene, fra ett sted i hele appen.
/// Visningene endrer bare modellene; denne fanger opp endringene og oppdaterer resten.
private struct DerivedStateSync: ViewModifier {
    private static let logger = Logger(subsystem: "com.opland.subtrack", category: "Sync")

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    // @Query oppdateres også når CloudKit importerer endringer fra andre enheter, så
    // endringer gjort der mens appen er åpen her når også widgeten og varslene.
    @Query private var subscriptions: [Subscription]

    func body(content: Content) -> some View {
        content
            // Kjør hver gang appen blir aktiv, ikke bare første gang: datoer kan ha passert,
            // og abonnement kan ha endret seg på en annen enhet mens appen lå i bakgrunnen.
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                refresh()
            }
            // Alt som påvirker widgeten eller varslene, enten det er endret her eller via synk.
            .onChange(of: subscriptions.map(\.syncSignature)) {
                refresh()
            }
    }

    private func refresh() {
        // Eldre datoer nær midnatt flyttes til kl. 12 før datoene flyttes frem, så
        // fremflyttingen arver det nye klokkeslettet. Bare én gang per abonnement per enhet,
        // se `StoredDateCleanup` for hvorfor.
        if StoredDateCleanup.runIfNeeded(for: subscriptions) {
            // Ryddingen er allerede merket som gjort i UserDefaults, som lagres uavhengig av
            // SwiftData. Lagre endringene nå, så de ikke går tapt hvis appen avsluttes før
            // SwiftData lagrer av seg selv.
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("Kunne ikke lagre ryddede datoer: \(error.localizedDescription, privacy: .public)")
            }
        }
        for subscription in subscriptions where !subscription.isCancelled {
            subscription.advanceRenewalDateIfPast()
        }
        WidgetSnapshotStore.update(with: subscriptions)
        // Trygt å kalle mange ganger raskt etter hverandre: NotificationScheduler kjører
        // omplanleggingene etter tur og avbryter eldre, så bare den siste blir stående.
        Task { await NotificationScheduler.reschedule(for: subscriptions) }
    }
}

extension View {
    /// Holder datoer, widget og varsler i takt med abonnementene. Legges på roten av appen.
    func keepsDerivedStateInSync() -> some View {
        modifier(DerivedStateSync())
    }
}

extension Subscription {
    /// Alt ved et abonnement som påvirker widgeten eller varslene. Endres noe av dette,
    /// må widgeten og varslene oppdateres. Notatet er bevisst utelatt.
    struct SyncSignature: Hashable {
        let id: UUID
        let name: String
        let price: Decimal
        let currencyCode: String
        let interval: BillingInterval
        let kind: SubscriptionCategory
        let nextRenewalDate: Date
        let billingAnchorDate: Date?
        let trialEndDate: Date?
        let isActive: Bool
        let cancelledDate: Date?
        let reminderDaysBefore: Int
        let symbolName: String?
        let colorHex: String?
        let splitCount: Int
        let cancelURLString: String?
    }

    var syncSignature: SyncSignature {
        SyncSignature(
            id: id,
            name: name,
            price: price,
            currencyCode: currencyCode,
            interval: interval,
            kind: kind,
            nextRenewalDate: nextRenewalDate,
            billingAnchorDate: billingAnchorDate,
            trialEndDate: trialEndDate,
            isActive: isActive,
            cancelledDate: cancelledDate,
            reminderDaysBefore: reminderDaysBefore,
            symbolName: symbolName,
            colorHex: colorHex,
            splitCount: splitCount,
            cancelURLString: cancelURLString
        )
    }
}
