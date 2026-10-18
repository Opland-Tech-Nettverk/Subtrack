import Foundation

/// Rydder lagrede datoer fra før skjemaet begynte å lagre kl. 12, én gang per abonnement
/// per enhet. Ryddingen kjørte tidligere ved hver oppdatering, men en dato flyttet til kl. 12
/// i én tidssone kan ligge utenfor 06–18 i en tidssone 7 timer eller mer unna. Enhetene skrev
/// da hverandres datoer frem og tilbake via iCloud i det uendelige. Nye datoer lagres
/// allerede kl. 12 av skjemaet, så det er bare eldre data som trenger ryddingen.
///
/// Datoer som allerede ligger kl. 12 i en eller annen tidssone, røres ikke (se
/// `Subscription.normalizeStoredDates(calendar:)`). En enhet i en fjern tidssone flytter
/// derfor ikke en dato som skjemaet eller en annen enhet har satt, til en annen dag, og bare
/// den første enheten som ser en eldre dato, rydder den. Det å huske ryddede abonnement er
/// dermed en ekstra sikring som også holder antall skrivinger til iCloud nede.
///
/// Hvert abonnement huskes for seg, ikke enheten som helhet: på en ny enhet kan CloudKit
/// importere dataene litt etter litt, og en enhet med en eldre versjon av appen kan legge til
/// abonnement med datoer nær midnatt. Begge deler kommer etter første rydding og skal også
/// ryddes.
///
/// Kjente begrensninger:
/// - Enheten som rydder en eldre dato først, bestemmer dagen. En dato registrert nær midnatt
///   mens brukeren var på reise, kan derfor havne én dag feil.
/// - Rydder to enheter samme dato før de har sett hverandres endring, vinner den siste
///   skrivingen i iCloud. Begge resultatene ligger kl. 12, så ingen av dem ryddes på nytt.
/// - Endrer en eldre versjon et abonnement som allerede er ryddet her, ryddes det ikke igjen
///   her. Den enheten rydder det selv når den oppdateres, siden den ikke har ryddet det før.
/// - Eldre datoer som tilfeldigvis står på et helt kvarter (typisk valgt i datovelgeren,
///   omtrent 1 av 15), ryddes ikke, fordi de ikke kan skilles fra datoer som allerede er satt
///   til kl. 12. De oppfører seg som før ryddingen fantes. Å skille dem ville krevd et nytt
///   lagret felt.
enum StoredDateCleanup {
    /// UserDefaults-nøkkel for ID-ene (`uuidString`) til abonnement som er ryddet på denne
    /// enheten. ID-er til slettede abonnement blir liggende, men det er ufarlig: de tar lite
    /// plass, og å fjerne ID-er som mangler i listen ville ryddet abonnement på nytt når
    /// CloudKit bare har importert en del av dataene.
    static let cleanedIDsKey = "StoredDateCleanup.v1CleanedIDs"

    /// Kjører `normalizeStoredDates(calendar:)` på hvert abonnement som ikke er ryddet på
    /// denne enheten før. Returnerer `true` hvis minst ett abonnement ble merket som ryddet nå,
    /// også om ingen av datoene måtte flyttes.
    @discardableResult
    static func runIfNeeded(
        for subscriptions: [Subscription],
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> Bool {
        let done = Set(defaults.stringArray(forKey: cleanedIDsKey) ?? [])
        // Gjelder også arkiverte abonnement: ankeret brukes igjen hvis de gjenopprettes.
        let pending = subscriptions.filter { !done.contains($0.id.uuidString) }
        // Uten nye abonnement lagres ingenting. En tom liste på en ny enhet betyr bare at
        // CloudKit ennå ikke har importert dataene, og de ryddes når de kommer.
        guard !pending.isEmpty else { return false }
        for subscription in pending {
            subscription.normalizeStoredDates(calendar: calendar)
        }
        let cleaned = done.union(pending.map(\.id.uuidString))
        defaults.set(Array(cleaned), forKey: cleanedIDsKey)
        return true
    }
}
