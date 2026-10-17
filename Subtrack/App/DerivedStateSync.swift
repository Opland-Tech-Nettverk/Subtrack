import SwiftUI
import SwiftData

/// Holder datoer, widget og varsler i takt med dataene, fra ett sted i hele appen.
/// Visningene endrer bare modellene; denne fanger opp endringene og oppdaterer resten.
private struct DerivedStateSync: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
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
        for subscription in subscriptions where !subscription.isCancelled {
            subscription.advanceRenewalDateIfPast()
        }
        WidgetSnapshotStore.update(with: subscriptions)
        // Trygt å kalle mange ganger raskt etter hverandre: generasjonstelleren i
        // NotificationScheduler gjør at bare den siste planleggingen blir stående.
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
