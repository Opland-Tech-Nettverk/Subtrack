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

    /// Omplanleggingen som kjører nå, eller sist kjørte. En ny omplanlegging avbryter den og
    /// venter til den er helt ferdig før den selv starter, så et `add` fra en eldre kjøring
    /// aldri kan lande etter at en nyere har fjernet alle varslene.
    private static var currentReschedule: Task<Void, Never>?

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
    /// Nøkkelen bruker alltid gregoriansk år, måned og dag i tidssonen til `calendar`, så
    /// den ikke endres om brukeren bytter til f.eks. japansk eller buddhistisk kalender.
    static func renewalKey(for subscription: Subscription, renewalDate: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: renewalDate)
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
    ///
    /// Trygt å kalle mange ganger raskt etter hverandre: kjøringene går etter tur, og en ny
    /// avbryter den forrige, så bare den siste planleggingen blir stående.
    static func reschedule(for subscriptions: [Subscription]) async {
        let previous = currentReschedule
        previous?.cancel()
        // Arver MainActor herfra, som resten av appen.
        let task = Task {
            if let previous {
                await previous.value
            }
            guard !Task.isCancelled else { return }
            await performReschedule(for: subscriptions)
        }
        currentReschedule = task
        await task.value
    }

    /// Selve omplanleggingen. Kjøres bare fra `reschedule(for:)`, aldri to samtidig.
    private static func performReschedule(for subscriptions: [Subscription]) async {
        let center = UNUserNotificationCenter.current()
        let authorizationStatus = await center.notificationSettings().authorizationStatus
        guard !Task.isCancelled else { return }

        let now = Date.now
        var notified = loadNotifiedRenewals(now: now)
        if !UserDefaults.standard.bool(forKey: trackingStartedKey) {
            // Første kjøring med denne bokføringen: eldre versjoner har kanskje allerede varslet
            // om fornyelser som nærmer seg, uten at vi vet det. Ved en ny installasjon kjører
            // første omplanlegging ved oppstart uten abonnement, så da merkes ingenting.
            notified.merge(renewalsNotifiedBeforeTracking(for: subscriptions, now: now)) { current, _ in current }
            save(notified, forKey: notifiedRenewalsKey)
            UserDefaults.standard.set(true, forKey: trackingStartedKey)
        }

        let reminders = plannedReminders(for: subscriptions, now: now, alreadyNotified: Set(notified.keys))
        // Uten tillatelse vises ingen varsler. Lagres de likevel, ville de senere regnes som
        // sendt og hindret reservevarsler etter at brukeren slår varsler på.
        let scheduled = canDeliverNotifications(authorizationStatus) ? scheduledTriggers(for: reminders) : [:]
        save(scheduled, forKey: scheduledTriggersKey)

        // Appen planlegger ingen andre varsler enn disse, så det er trygt å fjerne alle.
        center.removeAllPendingNotificationRequests()

        for reminder in reminders {
            // En nyere omplanlegging venter på denne, så stopp i stedet for å legge til flere.
            guard !Task.isCancelled else { return }

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
    /// Settes første gang denne bokføringen kjører. Mangler den, kommer brukeren fra en
    /// eldre versjon (eller er ny), se `renewalsNotifiedBeforeTracking`. Et manglende
    /// `scheduledTriggersKey` kan ikke brukes til dette: det forblir tomt så lenge brukeren
    /// ikke har gitt tillatelse til varsler.
    private static let trackingStartedKey = "NotificationScheduler.trackingStarted"
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

    /// Fornyelser en eldre versjon av appen trolig allerede har varslet om: de som ikke er
    /// passert, men der det foretrukne varseltidspunktet er det. Brukes bare første gang
    /// bokføringen kjører, så brukere som oppdaterer ikke får et reservevarsel for samme trekk.
    /// Vi kan ikke vite det sikkert (f.eks. for et abonnement lagt inn etter at tidspunktet
    /// var passert), men går heller glipp av ett reservevarsel enn å varsle to ganger.
    static func renewalsNotifiedBeforeTracking(
        for subscriptions: [Subscription],
        now: Date,
        calendar: Calendar = .current
    ) -> [String: Date] {
        let startOfToday = calendar.startOfDay(for: now)
        var result: [String: Date] = [:]
        for subscription in subscriptions where subscription.isBilling {
            let renewals = subscription.upcomingRenewalDates(count: occurrencesPerSubscription, calendar: calendar)
            for renewalDate in renewals where renewalDate >= startOfToday {
                guard let preferred = RenewalCalculator.reminderDate(
                    nextRenewalDate: renewalDate,
                    daysBefore: subscription.reminderDaysBefore,
                    calendar: calendar
                ), preferred <= now else { continue }
                result[renewalKey(for: subscription, renewalDate: renewalDate, calendar: calendar)] = renewalDate
            }
        }
        return result
    }

    /// Om varsler faktisk vises med denne tillatelsen.
    private static func canDeliverNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
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

    /// Det som lagres om en plan, så neste omplanlegging vet hvilke varsler som har gått.
    static func scheduledTriggers(for reminders: [PlannedReminder]) -> [String: ScheduledTrigger] {
        Dictionary(
            reminders.map { ($0.renewalKey, ScheduledTrigger(triggerDate: $0.triggerDate, renewalDate: $0.renewalDate)) },
            uniquingKeysWith: { first, _ in first }
        )
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
