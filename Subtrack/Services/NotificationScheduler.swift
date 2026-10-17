import Foundation
import OSLog
import SwiftData
import UserNotifications

/// Et varsel som skal planlegges, uavhengig av UserNotifications slik at utvelgelsen kan testes.
struct PlannedReminder: Equatable {
    let identifier: String
    /// Identifiserer fornyelsen varselet gjelder, se `NotificationScheduler.renewalKey`.
    /// Stabil selv om fornyelsens nummer i rekken (`identifier`) endrer seg.
    let renewalKey: String
    let renewalDate: Date
    let triggerDate: Date
    let title: String
    let body: String
    /// Når satt, får varselet en «Avslutt abonnement»-knapp som åpner denne.
    let cancelURL: URL?
}

/// Planlegger lokale varsler for abonnementsfornyelser.
///
/// iOS tillater maks 64 ventende lokale varsler per app, og vekker ikke appen for å
/// planlegge nye. Vi planlegger derfor de nærmeste varslene på tvers av *alle*
/// abonnement, innenfor et felles budsjett, og planlegger alt på nytt hver gang
/// appen åpnes eller et abonnement endres. Har brukeren mange abonnement, er det
/// varslene lengst frem i tid som faller bort - aldri de nærmeste.
enum NotificationScheduler {
    /// Litt under iOS-grensen på 64, så vi aldri treffer den.
    static let maxPendingReminders = 60
    /// Hvor mange fremtidige fornyelser vi vurderer per abonnement.
    static let occurrencesPerSubscription = 6

    /// Øker for hver omplanlegging, slik at en eldre kjøring som fortsatt legger til
    /// varsler kan avbryte seg selv i stedet for å overskrive en nyere.
    private static var generation = 0

    private static let logger = Logger(subsystem: "com.opland.subtrack", category: "Notifications")

    /// Varselkategori og knapp for varsler der abonnementet har en avslutningslenke.
    static let cancelLinkCategory = "renewal-with-cancel-link"
    static let openCancelLinkAction = "open-cancel-link"
    static let cancelURLKey = "cancelURL"

    /// Må registreres ved oppstart for at knappen skal vises på varslene.
    static func registerCategories() {
        let openLink = UNNotificationAction(
            identifier: openCancelLinkAction,
            title: "Avslutt abonnement",
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "xmark.circle")
        )
        let category = UNNotificationCategory(
            identifier: cancelLinkCategory,
            actions: [openLink],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorizationIfNeeded() async {
        // Systemdialogen ville stoppet UI-testene.
        guard !AppEnvironment.isUITesting else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Stabil nøkkel for én fornyelse av et abonnement: `uuid|åååå-mm-dd`. Bygges fra
    /// kalenderkomponenter, ikke en formatter, så den ikke avhenger av språkinnstillinger.
    static func renewalKey(for subscription: Subscription, renewalDate: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: renewalDate)
        let day = String(format: "%04ld-%02ld-%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return "\(subscription.id.uuidString)|\(day)"
    }

    /// De nærmeste varslene på tvers av alle aktive abonnement, maks `limit` stykker.
    ///
    /// Er det foretrukne varseltidspunktet passert (f.eks. et nytt abonnement som fornyes
    /// i morgen med varsel 3 dager før), brukes et reservetidspunkt - men bare hvis
    /// fornyelsen ikke står i `alreadyNotified`. Ellers ville et varsel som gikk 3 dager før
    /// fått et nytt varsel dagen før neste gang appen åpnes.
    static func plannedReminders(
        for subscriptions: [Subscription],
        now: Date = .now,
        limit: Int = maxPendingReminders,
        alreadyNotified: Set<String> = [],
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        let candidates = subscriptions.filter(\.isBilling).flatMap { subscription in
            subscription.upcomingRenewalDates(count: occurrencesPerSubscription, calendar: calendar)
                .enumerated()
                .compactMap { occurrence, renewalDate -> PlannedReminder? in
                    let key = renewalKey(for: subscription, renewalDate: renewalDate, calendar: calendar)
                    guard let reminder = RenewalCalculator.reminderDate(
                        forRenewal: renewalDate,
                        preferredDaysBefore: subscription.reminderDaysBefore,
                        after: now,
                        calendar: calendar
                    ) else { return nil }
                    if reminder.isFallback && alreadyNotified.contains(key) { return nil }

                    let isTrialEnd = subscription.isTrialEnd(renewalDate, calendar: calendar)
                    let date = renewalDate.formatted(date: .abbreviated, time: .omitted)
                    let price = subscription.price.formatted(.currency(code: subscription.currencyCode))
                    return PlannedReminder(
                        identifier: "\(subscription.id.uuidString)#\(occurrence)",
                        renewalKey: key,
                        renewalDate: renewalDate,
                        triggerDate: reminder.date,
                        title: isTrialEnd
                            ? "Prøveperioden for \(subscription.name) slutter snart"
                            : "\(subscription.name) fornyes snart",
                        body: isTrialEnd
                            ? "Fra \(date) belastes du \(price). Avslutt før det hvis du ikke vil fortsette."
                            : "Fornyes \(date) for \(price).",
                        cancelURL: subscription.cancelURL
                    )
                }
        }
        return Array(candidates.sorted { $0.triggerDate < $1.triggerDate }.prefix(limit))
    }

    /// Erstatter alle planlagte varsler med de nærmeste for de gitte abonnementene.
    static func reschedule(for subscriptions: [Subscription]) async {
        generation += 1
        let currentGeneration = generation
        let now = Date.now
        let notified = loadNotifiedRenewals(now: now)
        let reminders = plannedReminders(for: subscriptions, now: now, alreadyNotified: Set(notified.keys))
        saveScheduledTriggers(for: reminders)

        let center = UNUserNotificationCenter.current()
        // Appen planlegger ingen andre varsler enn disse, så det er trygt å fjerne alle.
        center.removeAllPendingNotificationRequests()

        for reminder in reminders {
            guard currentGeneration == generation else { return }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            if let cancelURL = reminder.cancelURL {
                content.categoryIdentifier = cancelLinkCategory
                content.userInfo = [cancelURLKey: cancelURL.absoluteString]
            }

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.triggerDate
            )
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                // Ett varsel som feiler skal ikke stoppe resten.
                logger.error("Kunne ikke planlegge varsel \(reminder.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Henter alle abonnement fra konteksten (inkludert ulagrede endringer) og planlegger på nytt.
    static func reschedule(using modelContext: ModelContext) async {
        let subscriptions: [Subscription]
        do {
            subscriptions = try modelContext.fetch(FetchDescriptor<Subscription>())
        } catch {
            // En tom liste ville fjernet alle varslene, så behold de eksisterende i stedet.
            logger.error("Kunne ikke hente abonnement for varsler: \(error.localizedDescription, privacy: .public)")
            return
        }
        await reschedule(for: subscriptions)
    }

    // MARK: - Varsler som allerede har gått

    /// Et planlagt varsel, lagret så neste omplanlegging vet om det har gått.
    struct ScheduledTrigger: Codable, Equatable {
        let triggerDate: Date
        let renewalDate: Date
    }

    /// `[renewalKey: ScheduledTrigger]` for varslene som ble planlagt sist.
    private static let scheduledTriggersKey = "NotificationScheduler.scheduledTriggers"
    /// `[renewalKey: fornyelsesdato]` for fornyelser det allerede er varslet om.
    private static let notifiedRenewalsKey = "NotificationScheduler.notifiedRenewals"
    /// Hvor lenge en passert fornyelse huskes. Den trengs bare til fornyelsen er over,
    /// men litt slingringsmonn tåler en klokke eller tidssone som endres.
    private static let notifiedRetention: TimeInterval = 7 * 86_400

    /// Flytter varsler fra forrige plan som har gått (`triggerDate` ≤ `now`) over til de
    /// varslede, og glemmer fornyelser som ligger mer enn en uke tilbake.
    static func updatedNotifiedRenewals(
        scheduled: [String: ScheduledTrigger],
        notified: [String: Date],
        now: Date
    ) -> [String: Date] {
        var result = notified
        for (key, trigger) in scheduled where trigger.triggerDate <= now {
            result[key] = trigger.renewalDate
        }
        let cutoff = now.addingTimeInterval(-notifiedRetention)
        return result.filter { $0.value >= cutoff }
    }

    /// Fornyelser det allerede er varslet om, oppdatert med det som har gått siden sist.
    private static func loadNotifiedRenewals(now: Date) -> [String: Date] {
        let notified = updatedNotifiedRenewals(
            scheduled: load([String: ScheduledTrigger].self, forKey: scheduledTriggersKey) ?? [:],
            notified: load([String: Date].self, forKey: notifiedRenewalsKey) ?? [:],
            now: now
        )
        save(notified, forKey: notifiedRenewalsKey)
        return notified
    }

    private static func saveScheduledTriggers(for reminders: [PlannedReminder]) {
        let scheduled = Dictionary(
            reminders.map { ($0.renewalKey, ScheduledTrigger(triggerDate: $0.triggerDate, renewalDate: $0.renewalDate)) },
            uniquingKeysWith: { first, _ in first }
        )
        save(scheduled, forKey: scheduledTriggersKey)
    }

    /// Leser JSON fra UserDefaults. Mangler eller ugyldige data gir `nil`, så vi starter på nytt.
    private static func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error("Kunne ikke lese \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func save<Value: Encodable>(_ value: Value, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            logger.error("Kunne ikke lagre \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
