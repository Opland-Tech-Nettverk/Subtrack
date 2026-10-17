import Foundation
import Testing
import UserNotifications
@testable import Subtrack

@MainActor
struct NotificationSchedulerTests {

    private let now = Date.now

    private func subscription(daysUntilRenewal: Int, reminderDaysBefore: Int = 3, isActive: Bool = true) -> Subscription {
        Subscription(
            name: "Test \(daysUntilRenewal)",
            price: 100,
            billingInterval: .monthly,
            nextRenewalDate: now.addingTimeInterval(TimeInterval(daysUntilRenewal) * 86_400),
            isActive: isActive,
            reminderDaysBefore: reminderDaysBefore
        )
    }

    @Test func staysWithinBudgetAndKeepsTheNearestReminders() {
        // 25 abonnement x 6 fornyelser = 150 kandidater, langt over budsjettet.
        let subscriptions = (10..<35).map { subscription(daysUntilRenewal: $0) }

        let reminders = NotificationScheduler.plannedReminders(for: subscriptions, now: now, limit: 60)

        #expect(reminders.count == 60)
        #expect(reminders.map(\.triggerDate) == reminders.map(\.triggerDate).sorted())
        // Alle 25 abonnementenes aller første varsel er de nærmeste, og må være med.
        let firstOccurrences = reminders.filter { $0.identifier.hasSuffix("#0") }
        #expect(firstOccurrences.count == 25)
    }

    @Test func trialEndGetsItsOwnWordingAndStillFiresWhenTheTrialIsShort() {
        // Prøveperioden slutter om 2 dager, men varsel er satt til 3 dager før.
        let trialEnd = now.addingTimeInterval(2 * 86_400)
        let trial = Subscription(
            name: "Netflix",
            price: 149,
            nextRenewalDate: trialEnd,
            trialEndDate: trialEnd,
            reminderDaysBefore: 3
        )

        let reminders = NotificationScheduler.plannedReminders(for: [trial], now: now)
        let first = reminders.first { $0.identifier.hasSuffix("#0") }

        #expect(first?.title == "Prøveperioden for Netflix slutter snart")
        #expect(first?.triggerDate == RenewalCalculator.reminderDate(nextRenewalDate: trialEnd, daysBefore: 1))
        // Senere fornyelser er vanlige betalinger.
        let second = reminders.first { $0.identifier.hasSuffix("#1") }
        #expect(second?.title == "Netflix fornyes snart")
    }

    @Test func skipsPausedSubscriptions() {
        let reminders = NotificationScheduler.plannedReminders(
            for: [subscription(daysUntilRenewal: 10, isActive: false)],
            now: now
        )
        #expect(reminders.isEmpty)
    }

    @Test func fallsBackWhenTheLeadTimeHasPassed() {
        // Fornyes i morgen, varsel 3 dager før -> det foretrukne varselet er allerede passert,
        // så det kommer dagen før eller samme morgen i stedet.
        let renewing = fixedSubscription(renewal: osloDate(2026, 10, 19, 12))
        let reminders = NotificationScheduler.plannedReminders(for: [renewing], now: fixedNow, calendar: oslo)

        let first = firstReminder(in: reminders)
        let fallbacks = [1, 0].compactMap {
            RenewalCalculator.reminderDate(nextRenewalDate: renewing.nextRenewalDate, daysBefore: $0, calendar: oslo)
        }
        #expect(first.map { fallbacks.contains($0.triggerDate) } == true)
        #expect(reminders.allSatisfy { $0.triggerDate > fixedNow })
        #expect(reminders.count == NotificationScheduler.occurrencesPerSubscription)
    }

    @Test func remindersCarryTheCancelLinkWhenSet() {
        let withLink = subscription(daysUntilRenewal: 10)
        withLink.cancelURLString = "https://www.netflix.com/cancelplan"
        let withoutLink = subscription(daysUntilRenewal: 11)

        let reminders = NotificationScheduler.plannedReminders(for: [withLink, withoutLink], now: now)

        let linked = reminders.filter { $0.identifier.hasPrefix(withLink.id.uuidString) }
        let unlinked = reminders.filter { $0.identifier.hasPrefix(withoutLink.id.uuidString) }
        #expect(!linked.isEmpty)
        #expect(linked.allSatisfy { $0.cancelURL?.absoluteString == "https://www.netflix.com/cancelplan" })
        #expect(unlinked.allSatisfy { $0.cancelURL == nil })
    }

    // MARK: - Faste datoer

    private var oslo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    private func osloDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        oslo.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Søndag 18. oktober 2026 kl. 14:00 i Oslo.
    private var fixedNow: Date { osloDate(2026, 10, 18, 14) }

    private func fixedSubscription(renewal: Date, trialEnd: Date? = nil) -> Subscription {
        Subscription(
            name: "Fast",
            price: 100,
            billingInterval: .monthly,
            nextRenewalDate: renewal,
            trialEndDate: trialEnd,
            reminderDaysBefore: 3
        )
    }

    private func firstReminder(in reminders: [PlannedReminder]) -> PlannedReminder? {
        reminders.first { $0.identifier.hasSuffix("#0") }
    }

    @Test func renewalTomorrowFallsBackToTheDayBeforeOrTheSameMorning() {
        let renewing = fixedSubscription(renewal: osloDate(2026, 10, 19, 12))

        // Klokken 08:00 rekker vi fortsatt kl. 09:00 dagen før.
        let morning = NotificationScheduler.plannedReminders(for: [renewing], now: osloDate(2026, 10, 18, 8), calendar: oslo)
        #expect(firstReminder(in: morning)?.triggerDate == osloDate(2026, 10, 18, 9))

        // Klokken 14:00 er det passert, så varselet kommer samme morgen.
        let afternoon = NotificationScheduler.plannedReminders(for: [renewing], now: fixedNow, calendar: oslo)
        let first = firstReminder(in: afternoon)
        #expect(first?.triggerDate == osloDate(2026, 10, 19, 9))
        #expect(first?.renewalDate == osloDate(2026, 10, 19, 12))
        #expect(first?.renewalKey == "\(renewing.id.uuidString)|2026-10-19")
    }

    @Test func noFallbackForARenewalThatWasAlreadyNotified() {
        let renewing = fixedSubscription(renewal: osloDate(2026, 10, 19, 12))
        let key = NotificationScheduler.renewalKey(for: renewing, renewalDate: renewing.nextRenewalDate, calendar: oslo)

        let reminders = NotificationScheduler.plannedReminders(
            for: [renewing],
            now: fixedNow,
            alreadyNotified: [key],
            calendar: oslo
        )

        #expect(firstReminder(in: reminders) == nil)
        // Senere fornyelser har egne nøkler og varsles som vanlig.
        #expect(reminders.count == NotificationScheduler.occurrencesPerSubscription - 1)
    }

    @Test func preferredLeadTimeIsUsedWhenItIsStillAhead() {
        // Fornyes om 10 dager: varsel nøyaktig 3 dager før kl. 09:00. 25. oktober er dagen
        // sommertiden slutter, og det skal ikke flytte klokkeslettet.
        let renewing = fixedSubscription(renewal: osloDate(2026, 10, 28, 12))
        let key = NotificationScheduler.renewalKey(for: renewing, renewalDate: renewing.nextRenewalDate, calendar: oslo)

        // `alreadyNotified` gjelder bare reservetidspunktene.
        for notified in [Set<String>(), Set([key])] {
            let reminders = NotificationScheduler.plannedReminders(
                for: [renewing],
                now: fixedNow,
                alreadyNotified: notified,
                calendar: oslo
            )
            #expect(firstReminder(in: reminders)?.triggerDate == osloDate(2026, 10, 25, 9))
        }
    }

    @Test func shortTrialFallsBackOnlyOnce() {
        let trialEnd = osloDate(2026, 10, 20, 12)
        let trial = fixedSubscription(renewal: trialEnd, trialEnd: trialEnd)

        let reminders = NotificationScheduler.plannedReminders(for: [trial], now: fixedNow, calendar: oslo)
        let first = firstReminder(in: reminders)
        #expect(first?.title == "Prøveperioden for Fast slutter snart")
        #expect(first?.triggerDate == osloDate(2026, 10, 19, 9))

        // Varselet dagen før har gått: ikke et nytt samme morgen.
        let key = NotificationScheduler.renewalKey(for: trial, renewalDate: trialEnd, calendar: oslo)
        let afterwards = NotificationScheduler.plannedReminders(
            for: [trial],
            now: osloDate(2026, 10, 19, 10),
            alreadyNotified: [key],
            calendar: oslo
        )
        #expect(firstReminder(in: afterwards) == nil)
    }

    @Test func firedRemindersAreRememberedForAWeek() {
        let scheduled = [
            "fired": NotificationScheduler.ScheduledTrigger(
                triggerDate: osloDate(2026, 10, 18, 9),
                renewalDate: osloDate(2026, 10, 21, 12)
            ),
            "pending": NotificationScheduler.ScheduledTrigger(
                triggerDate: osloDate(2026, 10, 19, 9),
                renewalDate: osloDate(2026, 10, 22, 12)
            )
        ]
        let notified = [
            "recent": osloDate(2026, 10, 14, 12),
            "old": osloDate(2026, 10, 1, 12)
        ]

        let result = NotificationScheduler.updatedNotifiedRenewals(scheduled: scheduled, notified: notified, now: fixedNow)

        #expect(result == ["fired": osloDate(2026, 10, 21, 12), "recent": osloDate(2026, 10, 14, 12)])
    }

    @Test func aFiredReminderIsNotFollowedByAFallbackOnTheNextRun() {
        // Fornyes 22. oktober: varselet 3 dager før (19. oktober kl. 09:00) ligger fortsatt foran.
        let renewing = fixedSubscription(renewal: osloDate(2026, 10, 22, 12))
        let key = NotificationScheduler.renewalKey(for: renewing, renewalDate: renewing.nextRenewalDate, calendar: oslo)

        // Første kjøring: planlegg og lagre planen slik `reschedule` gjør.
        let firstPlan = NotificationScheduler.plannedReminders(for: [renewing], now: fixedNow, calendar: oslo)
        #expect(firstReminder(in: firstPlan)?.triggerDate == osloDate(2026, 10, 19, 9))
        let scheduled = NotificationScheduler.scheduledTriggers(for: firstPlan)

        // Neste kjøring, etter at varselet har gått.
        let later = osloDate(2026, 10, 19, 10)
        let notified = NotificationScheduler.updatedNotifiedRenewals(scheduled: scheduled, notified: [:], now: later)
        #expect(notified[key] == renewing.nextRenewalDate)

        // Uten bokføringen ville det kommet et reservevarsel dagen før.
        let untracked = NotificationScheduler.plannedReminders(for: [renewing], now: later, calendar: oslo)
        #expect(firstReminder(in: untracked)?.triggerDate == osloDate(2026, 10, 21, 9))

        let secondPlan = NotificationScheduler.plannedReminders(
            for: [renewing],
            now: later,
            alreadyNotified: Set(notified.keys),
            calendar: oslo
        )
        #expect(firstReminder(in: secondPlan) == nil)
        #expect(secondPlan.count == NotificationScheduler.occurrencesPerSubscription - 1)
    }

    @Test func seedsRenewalsAnOlderVersionHasAlreadyNotifiedAbout() {
        // Fornyes i morgen med varsel 3 dager før: en eldre versjon varslet 16. oktober.
        let notifiedBefore = fixedSubscription(renewal: osloDate(2026, 10, 19, 12))
        // Fornyes om 10 dager: varselet har ikke gått ennå.
        let upcoming = fixedSubscription(renewal: osloDate(2026, 10, 28, 12))
        // Pausede abonnement varsles ikke.
        let paused = fixedSubscription(renewal: osloDate(2026, 10, 19, 12))
        paused.isActive = false
        // Fornyelsen i går er over og trenger ikke huskes.
        let passed = fixedSubscription(renewal: osloDate(2026, 10, 17, 12))

        let seeded = NotificationScheduler.renewalsNotifiedBeforeTracking(
            for: [notifiedBefore, upcoming, paused, passed],
            now: fixedNow,
            calendar: oslo
        )

        let key = NotificationScheduler.renewalKey(for: notifiedBefore, renewalDate: notifiedBefore.nextRenewalDate, calendar: oslo)
        #expect(seeded == [key: osloDate(2026, 10, 19, 12)])

        // Ikke et reservevarsel samme morgen for et trekk det allerede er varslet om.
        let reminders = NotificationScheduler.plannedReminders(
            for: [notifiedBefore],
            now: fixedNow,
            alreadyNotified: Set(seeded.keys),
            calendar: oslo
        )
        #expect(firstReminder(in: reminders) == nil)
        #expect(reminders.count == NotificationScheduler.occurrencesPerSubscription - 1)
    }

    /// Prøveperiode som slutter 20. oktober med varsel 3 dager før: det foretrukne
    /// tidspunktet (17. oktober kl. 09:00) er passert ved `fixedNow`.
    private func shortTrial() -> (subscription: Subscription, key: String) {
        let trialEnd = osloDate(2026, 10, 20, 12)
        let trial = fixedSubscription(renewal: trialEnd, trialEnd: trialEnd)
        return (trial, NotificationScheduler.renewalKey(for: trial, renewalDate: trialEnd, calendar: oslo))
    }

    @Test func aPendingTrialFallbackFromAnOlderVersionIsNotSeeded() {
        let (trial, key) = shortTrial()
        // Build 6 planla et reservevarsel dagen før, som ikke har gått ennå.
        let pending = [trial.id.uuidString: [osloDate(2026, 10, 19, 9)]]

        let seeded = NotificationScheduler.renewalsNotifiedBeforeTracking(
            for: [trial],
            now: fixedNow,
            pendingTriggers: pending,
            calendar: oslo
        )
        #expect(seeded[key] == nil)

        // Varselet erstattes av vårt eget, på samme tidspunkt, i stedet for å forsvinne.
        let reminders = NotificationScheduler.plannedReminders(
            for: [trial],
            now: fixedNow,
            alreadyNotified: Set(seeded.keys),
            calendar: oslo
        )
        let first = firstReminder(in: reminders)
        #expect(first?.triggerDate == osloDate(2026, 10, 19, 9))
        #expect(first?.renewalKey == key)
        #expect(first?.title == "Prøveperioden for Fast slutter snart")
    }

    @Test func aTrialWithoutPendingRemindersIsSeeded() {
        // Uten ventende varsler har build 6 allerede varslet, og vi antar som før at det gjelder.
        let (trial, key) = shortTrial()

        let seeded = NotificationScheduler.renewalsNotifiedBeforeTracking(
            for: [trial],
            now: fixedNow,
            pendingTriggers: [:],
            calendar: oslo
        )

        #expect(seeded == [key: osloDate(2026, 10, 20, 12)])
        let reminders = NotificationScheduler.plannedReminders(
            for: [trial],
            now: fixedNow,
            alreadyNotified: Set(seeded.keys),
            calendar: oslo
        )
        #expect(firstReminder(in: reminders) == nil)
    }

    @Test func unrelatedPendingTriggersDoNotPreventSeeding() {
        let (trial, key) = shortTrial()
        let other = fixedSubscription(renewal: osloDate(2026, 10, 28, 12))

        let unrelated: [[String: [Date]]] = [
            // Riktig tidspunkt, men for et annet abonnement.
            [other.id.uuidString: [osloDate(2026, 10, 19, 9)]],
            // Riktig abonnement, men et tidspunkt som ikke hører til denne fornyelsen.
            [trial.id.uuidString: [osloDate(2026, 10, 25, 9)]]
        ]
        for pending in unrelated {
            let seeded = NotificationScheduler.renewalsNotifiedBeforeTracking(
                for: [trial],
                now: fixedNow,
                pendingTriggers: pending,
                calendar: oslo
            )
            #expect(seeded == [key: osloDate(2026, 10, 20, 12)])
        }
    }

    @Test func aPendingTriggerWithinTheSameMinuteCountsAsPending() {
        let (trial, key) = shortTrial()
        // Sekundene skal ikke spille noen rolle: 09:00:30 er samme varsel som 09:00.
        let halfAMinuteLate = oslo.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9, minute: 0, second: 30))!

        let seeded = NotificationScheduler.renewalsNotifiedBeforeTracking(
            for: [trial],
            now: fixedNow,
            pendingTriggers: [trial.id.uuidString: [halfAMinuteLate]],
            calendar: oslo
        )

        #expect(seeded[key] == nil)
    }

    // MARK: - Ventende varsler

    /// Kalendervarsler er i lokal tid, så forventet tidspunkt bygges i enhetens tidssone.
    private var localGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// 15. juni kl. 12:00 om `yearsAhead` år, langt fra sommertidsskiftene.
    private func localNoon(yearsAhead: Int, day: Int = 15) -> Date {
        let year = localGregorian.component(.year, from: .now) + yearsAhead
        return localGregorian.date(from: DateComponents(year: year, month: 6, day: day, hour: 12))!
    }

    private func pendingRequest(_ identifier: String, at date: Date) -> UNNotificationRequest {
        let components = localGregorian.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(
            identifier: identifier,
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    @Test func pendingTriggerDatesReadTheUUIDAndTheNextTriggerDate() {
        let uuid = UUID().uuidString
        let upcoming = localNoon(yearsAhead: 1)

        let result = NotificationScheduler.pendingTriggerDates(from: [pendingRequest("\(uuid)#0", at: upcoming)])

        let dates = result[uuid] ?? []
        #expect(dates.count == 1)
        #expect(dates.first.map { localGregorian.isDate($0, equalTo: upcoming, toGranularity: .minute) } == true)
    }

    @Test func pendingTriggerDatesAreGroupedBySubscription() {
        let uuid = UUID().uuidString
        let first = localNoon(yearsAhead: 1)
        let second = localNoon(yearsAhead: 1, day: 16)

        let result = NotificationScheduler.pendingTriggerDates(from: [
            pendingRequest("\(uuid)#0", at: first),
            pendingRequest("\(uuid)#1", at: second)
        ])

        #expect(Array(result.keys) == [uuid])
        let dates = result[uuid] ?? []
        #expect(dates.count == 2)
        // Rekkefølgen følger forespørslene.
        for (date, expected) in zip(dates, [first, second]) {
            #expect(localGregorian.isDate(date, equalTo: expected, toGranularity: .minute))
        }
    }

    @Test func pendingTriggerDatesSkipRequestsWithoutANextDate() {
        let uuid = UUID().uuidString
        let pastComponents = DateComponents(year: 2000, month: 6, day: 15, hour: 12, minute: 0)
        let past = UNNotificationRequest(
            identifier: "\(uuid)#0",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: pastComponents, repeats: false)
        )
        // Bare kalendervarsler kommer fra appen, så andre utløsere telles ikke.
        let timeInterval = UNNotificationRequest(
            identifier: "\(uuid)#1",
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )

        #expect(NotificationScheduler.pendingTriggerDates(from: [past]).isEmpty)
        #expect(NotificationScheduler.pendingTriggerDates(from: [timeInterval]).isEmpty)
        #expect(NotificationScheduler.pendingTriggerDates(from: [past, timeInterval])[uuid] == nil)
    }

    @Test func aSkippedRequestDoesNotHideTheOthers() {
        let uuid = UUID().uuidString
        let upcoming = localNoon(yearsAhead: 1)
        let timeInterval = UNNotificationRequest(
            identifier: "\(uuid)#0",
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )

        let result = NotificationScheduler.pendingTriggerDates(from: [timeInterval, pendingRequest("\(uuid)#1", at: upcoming)])

        let dates = result[uuid] ?? []
        #expect(dates.count == 1)
        #expect(dates.first.map { localGregorian.isDate($0, equalTo: upcoming, toGranularity: .minute) } == true)
    }

    @Test func renewalKeyUsesTheGregorianDayInTheCalendarsTimeZone() {
        let renewing = fixedSubscription(renewal: osloDate(2026, 10, 19, 12))
        func key(_ date: Date, _ calendar: Calendar) -> String {
            NotificationScheduler.renewalKey(for: renewing, renewalDate: date, calendar: calendar)
        }
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!

        // 00:30 i Oslo er 23:30 dagen før i London: nøkkelen følger kalenderens tidssone,
        // så samme tidspunkt kan gi ulik dag.
        let justAfterMidnight = oslo.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 0, minute: 30))!
        #expect(key(justAfterMidnight, oslo) == "\(renewing.id.uuidString)|2026-10-19")
        #expect(key(justAfterMidnight, london) == "\(renewing.id.uuidString)|2026-10-18")

        // Kl. 12 er det samme dag i begge.
        let noon = osloDate(2026, 10, 19, 12)
        #expect(key(noon, oslo) == key(noon, london))

        // Japansk kalender ville gitt år 8 (Reiwa), men nøkkelen er alltid gregoriansk.
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = oslo.timeZone
        #expect(key(noon, japanese) == key(noon, oslo))
    }
}
