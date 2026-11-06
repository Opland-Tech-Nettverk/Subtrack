import Foundation
import OSLog
import SwiftData
import WidgetKit

/// Deler en forenklet oversikt over kommende trekk med widgeten via App Groupen.
/// Widgeten kjører i en egen prosess og leser denne JSON-en i stedet for databasen.
/// Formatet må holdes i synk med `UpcomingRenewal` i SubtrackWidget-targetet.
enum WidgetSnapshotStore {
    static let appGroupID = "group.com.opland.subtrack"
    static let snapshotKey = "upcomingRenewals"
    static let widgetKind = "SubtrackWidget"

    /// Minst så mange fornyelser per abonnement, så widgeten fortsatt har noe å vise når de
    /// nærmeste datoene passerer, selv om appen ikke åpnes på en stund. Abonnement som trekkes
    /// oftere, får alle trekk fram til slutten av neste måned (se `horizonDate`), så summen av
    /// resten av måneden blir riktig også for ukentlige abonnement.
    static let occurrencesPerSubscription = 3

    private static let logger = Logger(subsystem: "com.opland.subtrack", category: "Widget")

    struct UpcomingRenewal: Codable {
        let name: String
        let price: Decimal
        /// Brukerens del av trekket (`myShare`). Valgfri så øyeblikksbilder fra eldre versjoner av appen
        /// fortsatt kan leses; widgeten bruker `price` når den mangler.
        let share: Decimal?
        let currencyCode: String
        let symbolName: String
        let colorHex: String?
        let renewalDate: Date
        let isTrialEnd: Bool
    }

    /// Kommende trekk for alle abonnement som koster penger nå, sortert etter dato.
    /// Skilt ut fra `update` så utvalget kan testes uten App Group og WidgetKit.
    static func renewals(
        for subscriptions: [Subscription],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [UpcomingRenewal] {
        let horizon = horizonDate(from: now, calendar: calendar)
        return subscriptions
            .filter(\.isBilling)
            .flatMap { subscription -> [UpcomingRenewal] in
                let withinHorizon = ChargeSchedule.occurrences(
                    of: [subscription], from: now, through: horizon, calendar: calendar
                ).map(\.date)
                let dates = withinHorizon.count >= occurrencesPerSubscription
                    ? withinHorizon
                    : subscription.upcomingRenewalDates(count: occurrencesPerSubscription, calendar: calendar)
                return dates.map { renewalDate in
                    UpcomingRenewal(
                        name: subscription.name,
                        price: subscription.price,
                        share: subscription.myShare,
                        currencyCode: subscription.currencyCode,
                        symbolName: subscription.displaySymbolName,
                        colorHex: subscription.colorHex,
                        renewalDate: renewalDate,
                        isTrialEnd: subscription.isTrialEnd(renewalDate, calendar: calendar)
                    )
                }
            }
            .sorted { $0.renewalDate < $1.renewalDate }
    }

    /// Siste dag i måneden etter denne: lagrede trekk rekker fram dit.
    static func horizonDate(from now: Date, calendar: Calendar = .current) -> Date {
        let firstOfMonthAfterNext = MonthGrid.monthStart(offsetBy: 2, from: now, calendar: calendar)
        return calendar.date(byAdding: .day, value: -1, to: firstOfMonthAfterNext) ?? now
    }

    static func update(with subscriptions: [Subscription]) {
        // UI-testene bruker en database i minnet, men App Groupen er simulatorens ekte.
        // Testdataene skal ikke overskrive det widgeten viser.
        guard !AppEnvironment.isUITesting else { return }
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            logger.error("Fant ikke App Groupen \(Self.appGroupID, privacy: .public); widgeten oppdateres ikke")
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(renewals(for: subscriptions))
        } catch {
            logger.error("Kunne ikke kode widget-data: \(error.localizedDescription, privacy: .public)")
            return
        }

        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Henter alle abonnement fra konteksten (inkludert ulagrede endringer) og oppdaterer widgeten.
    static func update(using modelContext: ModelContext) {
        let subscriptions: [Subscription]
        do {
            subscriptions = try modelContext.fetch(FetchDescriptor<Subscription>())
        } catch {
            // En tom liste ville tømt widgeten, så behold forrige øyeblikksbilde i stedet.
            logger.error("Kunne ikke hente abonnement for widgeten: \(error.localizedDescription, privacy: .public)")
            return
        }
        update(with: subscriptions)
    }
}
