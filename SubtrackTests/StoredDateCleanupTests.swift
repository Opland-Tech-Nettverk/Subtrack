import Foundation
import Testing
@testable import Subtrack

@MainActor
struct StoredDateCleanupTests {

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private var oslo: Calendar { calendar("Europe/Oslo") }
    private var tokyo: Calendar { calendar("Asia/Tokyo") }
    private var losAngeles: Calendar { calendar("America/Los_Angeles") }

    private func date(in calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func osloDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        date(in: oslo, year, month, day, hour, minute)
    }

    /// Egne innstillinger per test (og per simulert enhet), så `.standard` aldri røres.
    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "StoredDateCleanupTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func storedDates(_ subscription: Subscription) -> [Date?] {
        [subscription.nextRenewalDate, subscription.billingAnchorDate, subscription.trialEndDate]
    }

    private func cleanedIDs(_ defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: StoredDateCleanup.cleanedIDsKey) ?? [])
    }

    @Test func runsOnlyOncePerSubscription() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lateEvening = osloDate(2026, 1, 15, 23, 1)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: lateEvening)

        let firstRun = StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaults, calendar: oslo)

        let noon = osloDate(2026, 1, 15, 12, 0)
        #expect(firstRun)
        #expect(subscription.nextRenewalDate == noon)
        #expect(subscription.billingAnchorDate == noon)
        #expect(cleanedIDs(defaults).contains(subscription.id.uuidString))

        // Satt tilbake for hånd: andre kjøring skal ikke røre datoene.
        subscription.nextRenewalDate = lateEvening
        subscription.billingAnchorDate = lateEvening

        let secondRun = StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaults, calendar: oslo)

        #expect(!secondRun)
        #expect(subscription.nextRenewalDate == lateEvening)
        #expect(subscription.billingAnchorDate == lateEvening)
    }

    @Test func emptyListDoesNotMarkCleanupAsDone() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Ved første oppstart kan iCloud-dataene ennå ikke være lastet ned. Da lagres
        // ingenting, og abonnementene ryddes når de kommer.
        let emptyRun = StoredDateCleanup.runIfNeeded(for: [], defaults: defaults, calendar: oslo)

        #expect(!emptyRun)
        #expect(defaults.object(forKey: StoredDateCleanup.cleanedIDsKey) == nil)

        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: osloDate(2026, 1, 15, 23, 1))
        let laterRun = StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaults, calendar: oslo)

        #expect(laterRun)
        #expect(subscription.nextRenewalDate == osloDate(2026, 1, 15, 12, 0))
        #expect(cleanedIDs(defaults).contains(subscription.id.uuidString))
    }

    @Test func cleansArchivedSubscriptionsToo() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let active = Subscription(name: "Netflix", price: 149, nextRenewalDate: osloDate(2026, 1, 15, 23, 1))
        let archived = Subscription(name: "Spotify", price: 129, nextRenewalDate: osloDate(2026, 1, 20, 0, 41))
        let cancelled = osloDate(2026, 1, 10, 23, 30)
        archived.cancelledDate = cancelled

        let didRun = StoredDateCleanup.runIfNeeded(for: [active, archived], defaults: defaults, calendar: oslo)

        #expect(didRun)
        #expect(active.nextRenewalDate == osloDate(2026, 1, 15, 12, 0))
        #expect(archived.nextRenewalDate == osloDate(2026, 1, 20, 12, 0))
        #expect(archived.billingAnchorDate == osloDate(2026, 1, 20, 12, 0))
        // Avslutningsdatoen er et faktisk tidspunkt og skal ikke flyttes.
        #expect(archived.cancelledDate == cancelled)
        #expect(cleanedIDs(defaults) == Set([active.id.uuidString, archived.id.uuidString]))
    }

    @Test func cleansRecordsThatArriveLater() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lateEvening = osloDate(2026, 1, 15, 23, 1)
        let first = Subscription(name: "Netflix", price: 149, nextRenewalDate: lateEvening)

        let firstRun = StoredDateCleanup.runIfNeeded(for: [first], defaults: defaults, calendar: oslo)

        let noon = osloDate(2026, 1, 15, 12, 0)
        #expect(firstRun)
        #expect(first.nextRenewalDate == noon)

        // Kommer senere, f.eks. fordi CloudKit importerer litt etter litt, eller fordi en
        // eldre versjon av appen på en annen enhet har lagt det til.
        let arrivedLater = Subscription(name: "Spotify", price: 129, nextRenewalDate: lateEvening)
        // Satt tilbake for hånd: det første abonnementet er allerede ryddet og skal ikke røres.
        first.nextRenewalDate = lateEvening
        first.billingAnchorDate = lateEvening

        let secondRun = StoredDateCleanup.runIfNeeded(for: [first, arrivedLater], defaults: defaults, calendar: oslo)

        #expect(secondRun)
        #expect(arrivedLater.nextRenewalDate == noon)
        #expect(arrivedLater.billingAnchorDate == noon)
        #expect(first.nextRenewalDate == lateEvening)
        #expect(first.billingAnchorDate == lateEvening)
        #expect(cleanedIDs(defaults) == Set([first.id.uuidString, arrivedLater.id.uuidString]))
    }

    @Test func doesNothingWhenEveryRecordIsAlreadyCleaned() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let subscriptions = [
            Subscription(name: "Netflix", price: 149, nextRenewalDate: osloDate(2026, 1, 15, 23, 1)),
            Subscription(name: "Spotify", price: 129, nextRenewalDate: osloDate(2026, 1, 20, 12, 0)),
        ]

        let firstRun = StoredDateCleanup.runIfNeeded(for: subscriptions, defaults: defaults, calendar: oslo)
        let idsAfterFirstRun = cleanedIDs(defaults)
        let secondRun = StoredDateCleanup.runIfNeeded(for: subscriptions, defaults: defaults, calendar: oslo)

        #expect(firstRun)
        #expect(!secondRun)
        #expect(cleanedIDs(defaults) == idsAfterFirstRun)
        #expect(idsAfterFirstRun == Set(subscriptions.map { $0.id.uuidString }))
    }

    // MARK: - Ingen frem-og-tilbake mellom tidssoner

    // Enhet A (Oslo) rydder først og flytter 23:01 til 12:00 Oslo. Enhet B ligger mer enn
    // 6 timer unna, så 12:00 Oslo ligger utenfor B sitt vindu (06-18), og B flytter datoen
    // én gang til kl. 12 hos seg. Det er forventet: én begrenset skriving per enhet. Uten
    // at hver enhet husker hva den har ryddet, ville A flyttet den tilbake igjen, og slik
    // ville det fortsatt for alltid.
    //
    // Klokkeslettet i Oslo endres av B, men dagen gjør det ikke:
    // - Tokyo, januar: 12:00 Oslo = 20:00 Tokyo -> 12:00 Tokyo = 04:00 Oslo samme dag.
    // - Tokyo, juli:   12:00 Oslo = 19:00 Tokyo -> 12:00 Tokyo = 05:00 Oslo samme dag.
    // - Los Angeles, januar: 12:00 Oslo = 03:00 LA -> 12:00 LA = 21:00 Oslo samme dag.
    // - Los Angeles, juli:   12:00 Oslo = 03:00 LA -> 12:00 LA = 21:00 Oslo samme dag.

    @Test func noPingPongBetweenOsloAndTokyoInWinter() {
        assertNoPingPong(otherDevice: tokyo, month: 1, expectedOsloHourAfterOtherDevice: 4)
    }

    @Test func noPingPongBetweenOsloAndTokyoInSummer() {
        assertNoPingPong(otherDevice: tokyo, month: 7, expectedOsloHourAfterOtherDevice: 5)
    }

    @Test func noPingPongBetweenOsloAndLosAngelesInWinter() {
        assertNoPingPong(otherDevice: losAngeles, month: 1, expectedOsloHourAfterOtherDevice: 21)
    }

    @Test func noPingPongBetweenOsloAndLosAngelesInSummer() {
        assertNoPingPong(otherDevice: losAngeles, month: 7, expectedOsloHourAfterOtherDevice: 21)
    }

    /// Simulerer to enheter med hver sine innstillinger og tidssoner som deler samme
    /// abonnement via iCloud, og kjører dem annenhver gang.
    private func assertNoPingPong(
        otherDevice: Calendar,
        month: Int,
        expectedOsloHourAfterOtherDevice: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let (defaultsA, suiteA) = makeDefaults()
        let (defaultsB, suiteB) = makeDefaults()
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }
        let original = osloDate(2026, month, 15, 23, 1)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: original, trialEndDate: original)
        var results: [Bool] = []

        results.append(StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaultsA, calendar: oslo))
        let osloNoon = osloDate(2026, month, 15, 12, 0)
        #expect(storedDates(subscription) == [osloNoon, osloNoon, osloNoon], sourceLocation: sourceLocation)

        results.append(StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaultsB, calendar: otherDevice))
        let otherNoon = date(in: otherDevice, 2026, month, 15, 12, 0)
        #expect(storedDates(subscription) == [otherNoon, otherNoon, otherNoon], sourceLocation: sourceLocation)
        let afterBoth = storedDates(subscription)

        for _ in 0..<3 {
            results.append(StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaultsA, calendar: oslo))
            results.append(StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaultsB, calendar: otherDevice))
            #expect(storedDates(subscription) == afterBoth, sourceLocation: sourceLocation)
        }

        // Hver enhet ryddet nøyaktig én gang.
        #expect(results == [true, true, false, false, false, false, false, false], sourceLocation: sourceLocation)
        // Begge enhetene viser fortsatt samme dag som opprinnelig registrert i Oslo.
        #expect(oslo.isDate(subscription.nextRenewalDate, inSameDayAs: original), sourceLocation: sourceLocation)
        #expect(oslo.component(.hour, from: subscription.nextRenewalDate) == expectedOsloHourAfterOtherDevice, sourceLocation: sourceLocation)
        #expect(otherDevice.component(.day, from: subscription.nextRenewalDate) == 15, sourceLocation: sourceLocation)
        #expect(otherDevice.component(.month, from: subscription.nextRenewalDate) == month, sourceLocation: sourceLocation)
    }

    @Test func normalizingWithoutFlagKeepsMovingTheDateBetweenZones() {
        // Viser hvorfor ryddede abonnement må huskes: ellers flytter Oslo og Tokyo datoen hver sin vei
        // hver gang, og hver flytting er en ny skriving til iCloud.
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: osloDate(2026, 1, 15, 23, 1))

        subscription.normalizeStoredDates(calendar: oslo)
        let afterOslo = subscription.nextRenewalDate
        subscription.normalizeStoredDates(calendar: tokyo)
        let afterTokyo = subscription.nextRenewalDate
        subscription.normalizeStoredDates(calendar: oslo)
        let afterOsloAgain = subscription.nextRenewalDate

        #expect(afterTokyo != afterOslo)
        #expect(afterOsloAgain != afterTokyo)
        // 12:00 Oslo -> 12:00 Tokyo (04:00 Oslo) -> 12:00 Oslo: en evig runddans.
        #expect(afterOsloAgain == afterOslo)
    }
}
