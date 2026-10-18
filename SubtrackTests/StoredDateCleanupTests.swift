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
    private var auckland: Calendar { calendar("Pacific/Auckland") }

    private func date(in calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func osloDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        date(in: oslo, year, month, day, hour, minute, second)
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

    // Enhet A (Oslo) rydder først og flytter 23:01:17 til 12:00 Oslo. Enhet B ligger mer enn
    // 6 timer unna, så 12:00 Oslo ligger utenfor B sitt vindu (06-18). Tidligere flyttet B
    // derfor datoen én gang til kl. 12 hos seg. Nå ligger 12:00 Oslo på et kvarter og regnes
    // som allerede ryddet, så B merker abonnementet som ryddet uten å endre noe. Datoene blir
    // liggende nøyaktig på 12:00 Oslo uansett hvor mange ganger enhetene kjører.
    //
    // Klokkeslettet hos B (utenfor vinduet, så den gamle regelen ville flyttet datoen):
    // - Tokyo, januar: 12:00 Oslo = 20:00 Tokyo.
    // - Tokyo, juli:   12:00 Oslo = 19:00 Tokyo.
    // - Los Angeles, januar: 12:00 Oslo = 03:00 LA.
    // - Los Angeles, juli:   12:00 Oslo = 03:00 LA.

    @Test func noPingPongBetweenOsloAndTokyoInWinter() {
        assertNoPingPong(otherDevice: tokyo, month: 1, expectedOtherDeviceHour: 20)
    }

    @Test func noPingPongBetweenOsloAndTokyoInSummer() {
        assertNoPingPong(otherDevice: tokyo, month: 7, expectedOtherDeviceHour: 19)
    }

    @Test func noPingPongBetweenOsloAndLosAngelesInWinter() {
        assertNoPingPong(otherDevice: losAngeles, month: 1, expectedOtherDeviceHour: 3)
    }

    @Test func noPingPongBetweenOsloAndLosAngelesInSummer() {
        assertNoPingPong(otherDevice: losAngeles, month: 7, expectedOtherDeviceHour: 3)
    }

    /// Simulerer to enheter med hver sine innstillinger og tidssoner som deler samme
    /// abonnement via iCloud, og kjører dem annenhver gang.
    private func assertNoPingPong(
        otherDevice: Calendar,
        month: Int,
        expectedOtherDeviceHour: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let (defaultsA, suiteA) = makeDefaults()
        let (defaultsB, suiteB) = makeDefaults()
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }
        let original = osloDate(2026, month, 15, 23, 1, 17)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: original, trialEndDate: original)
        var results: [Bool] = []

        results.append(StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaultsA, calendar: oslo))
        let osloNoon = osloDate(2026, month, 15, 12, 0)
        #expect(storedDates(subscription) == [osloNoon, osloNoon, osloNoon], sourceLocation: sourceLocation)
        // Utenfor B sitt vindu: uten kvarterregelen ville B flyttet datoen.
        #expect(otherDevice.component(.hour, from: osloNoon) == expectedOtherDeviceHour, sourceLocation: sourceLocation)

        results.append(StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaultsB, calendar: otherDevice))
        #expect(storedDates(subscription) == [osloNoon, osloNoon, osloNoon], sourceLocation: sourceLocation)

        for _ in 0..<3 {
            results.append(StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaultsA, calendar: oslo))
            results.append(StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaultsB, calendar: otherDevice))
            #expect(storedDates(subscription) == [osloNoon, osloNoon, osloNoon], sourceLocation: sourceLocation)
        }

        // Hver enhet merket abonnementet nøyaktig én gang. B merket det uten å endre noe.
        #expect(results == [true, true, false, false, false, false, false, false], sourceLocation: sourceLocation)
        #expect(cleanedIDs(defaultsA) == [subscription.id.uuidString], sourceLocation: sourceLocation)
        #expect(cleanedIDs(defaultsB) == [subscription.id.uuidString], sourceLocation: sourceLocation)
        // Fortsatt samme dag som opprinnelig registrert i Oslo.
        #expect(oslo.isDate(subscription.nextRenewalDate, inSameDayAs: original), sourceLocation: sourceLocation)
    }

    @Test func normalizingIsStableAcrossZonesEvenWithoutBookkeeping() {
        // Selv uten at hver enhet husker hva den har ryddet, flyttes datoen bare én gang:
        // etter første rydding ligger den på et kvarter, og andre tidssoner lar den være.
        // Tidligere flyttet hver tidssone den til kl. 12 hos seg, i en evig runddans.
        let original = osloDate(2026, 1, 15, 23, 1, 17)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: original, trialEndDate: original)

        subscription.normalizeStoredDates(calendar: oslo)

        let osloNoon = osloDate(2026, 1, 15, 12, 0)
        #expect(storedDates(subscription) == [osloNoon, osloNoon, osloNoon])

        for zone in [tokyo, losAngeles, auckland, oslo, tokyo] {
            subscription.normalizeStoredDates(calendar: zone)
            #expect(storedDates(subscription) == [osloNoon, osloNoon, osloNoon])
        }
    }

    // MARK: - Rapporterte tilfeller

    @Test func aucklandTwelveHoursAwayLeavesOsloNoonAlone() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Januar: Oslo UTC+1, Auckland UTC+13 (sommertid). 12:00 Oslo 15. jan er 00:00
        // Auckland 16. jan. Den gamle regelen ville flyttet datoen til 12:00 Auckland
        // 16. jan, altså 00:00 Oslo 16. jan - én dag feil.
        let osloNoon = osloDate(2026, 1, 15, 12, 0)
        #expect(auckland.component(.hour, from: osloNoon) == 0)
        #expect(auckland.component(.day, from: osloNoon) == 16)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: osloNoon, trialEndDate: osloNoon)

        let didRun = StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaults, calendar: auckland)

        // Merket som ryddet, men ingen dato er endret.
        #expect(didRun)
        #expect(cleanedIDs(defaults) == [subscription.id.uuidString])
        #expect(storedDates(subscription) == [osloNoon, osloNoon, osloNoon])
        #expect(oslo.component(.day, from: subscription.nextRenewalDate) == 15)
        #expect(oslo.component(.month, from: subscription.nextRenewalDate) == 1)
    }

    @Test func threeDevicesKeepTheDayOfALegacyDate() {
        let (defaultsOslo, suiteOslo) = makeDefaults()
        let (defaultsTokyo, suiteTokyo) = makeDefaults()
        let (defaultsLosAngeles, suiteLosAngeles) = makeDefaults()
        defer {
            defaultsOslo.removePersistentDomain(forName: suiteOslo)
            defaultsTokyo.removePersistentDomain(forName: suiteTokyo)
            defaultsLosAngeles.removePersistentDomain(forName: suiteLosAngeles)
        }
        // Med den gamle regelen: 12:00 Oslo -> 12:00 Tokyo 14. nov -> 12:00 LA 13. nov,
        // altså 21:00 Oslo 13. nov. Datoen gled én dag bakover.
        let original = osloDate(2026, 11, 14, 23, 1, 17)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: original, trialEndDate: original)
        let devices: [(defaults: UserDefaults, calendar: Calendar)] = [
            (defaultsOslo, oslo),
            (defaultsTokyo, tokyo),
            (defaultsLosAngeles, losAngeles),
        ]

        let results = devices.map { device in
            StoredDateCleanup.runIfNeeded(for: [subscription], defaults: device.defaults, calendar: device.calendar)
        }
        let laterResults = devices.map { device in
            StoredDateCleanup.runIfNeeded(for: [subscription], defaults: device.defaults, calendar: device.calendar)
        }

        let osloNoon = osloDate(2026, 11, 14, 12, 0)
        #expect(results == [true, true, true])
        #expect(laterResults == [false, false, false])
        #expect(storedDates(subscription) == [osloNoon, osloNoon, osloNoon])
        #expect(oslo.component(.day, from: subscription.nextRenewalDate) == 14)
        #expect(oslo.component(.month, from: subscription.nextRenewalDate) == 11)
    }

    @Test func formSavedNoonFromAnotherZoneIsNotTouched() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Lagret av skjemaet i Tokyo: 12:00 Tokyo er 04:00 i Oslo, utenfor Oslo sitt vindu.
        let tokyoNoon = RenewalCalculator.normalizedToNoon(date(in: tokyo, 2026, 1, 15, 9, 41, 17), calendar: tokyo)
        #expect(tokyoNoon == date(in: tokyo, 2026, 1, 15, 12, 0))
        #expect(oslo.component(.hour, from: tokyoNoon) == 4)
        let subscription = Subscription(name: "Netflix", price: 149, nextRenewalDate: tokyoNoon, trialEndDate: tokyoNoon)

        let didRun = StoredDateCleanup.runIfNeeded(for: [subscription], defaults: defaults, calendar: oslo)

        #expect(didRun)
        #expect(storedDates(subscription) == [tokyoNoon, tokyoNoon, tokyoNoon])
    }
}
