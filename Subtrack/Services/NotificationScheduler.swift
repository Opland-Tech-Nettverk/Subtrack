import Foundation
import OSLog
import SwiftData
import UserNotifications

/// Et varsel som skal planlegges, uavhengig av UserNotifications slik at utvelgelsen kan testes.
struct PlannedReminder: Equatable {
    let identifier: String
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

    /// De nærmeste varslene på tvers av alle aktive abonnement, maks `limit` stykker.
    static func plannedReminders(
        for subscriptions: [Subscription],
        now: Date = .now,
        limit: Int = maxPendingReminders
    ) -> [PlannedReminder] {
        let candidates = subscriptions.filter(\.isBilling).flatMap { subscription in
            subscription.upcomingRenewalDates(count: occurrencesPerSubscription)
                .enumerated()
                .compactMap { occurrence, renewalDate -> PlannedReminder? in
                    let isTrialEnd = subscription.isTrialEnd(renewalDate)
                    let triggerDate = isTrialEnd
                        ? RenewalCalculator.trialReminderDate(
                            trialEndDate: renewalDate,
                            preferredDaysBefore: subscription.reminderDaysBefore,
                            after: now
                        )
                        : RenewalCalculator.reminderDate(
                            nextRenewalDate: renewalDate,
                            daysBefore: subscription.reminderDaysBefore
                        )
                    guard let triggerDate, triggerDate > now else { return nil }

                    let date = renewalDate.formatted(date: .abbreviated, time: .omitted)
                    let price = subscription.price.formatted(.currency(code: subscription.currencyCode))
                    return PlannedReminder(
                        identifier: "\(subscription.id.uuidString)#\(occurrence)",
                        triggerDate: triggerDate,
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
        let reminders = plannedReminders(for: subscriptions)

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
}
