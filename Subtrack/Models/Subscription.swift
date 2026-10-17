import Foundation
import SwiftData

// CloudKit krever at hvert felt enten er valgfritt eller har en standardverdi,
// derfor har alle ikke-valgfrie felt en standardverdi her (init setter likevel alt).
// Merk: Når skjemaet er publisert til CloudKit Production, kan felt bare legges til -
// aldri gis nytt navn, endres type på eller slettes.
@Model
final class Subscription {
    var id: UUID = UUID()
    var name: String = ""
    var price: Decimal = 0
    var currencyCode: String = "NOK"
    /// Utfaset: leses bare som reserve når `billingIntervalCode` mangler eller er ukjent.
    /// Skrives fortsatt sammen med koden, så eldre app-versjoner som bare kjenner dette
    /// feltet viser riktig intervall. Må bli i skjemaet fordi felt ikke kan fjernes fra CloudKit.
    /// Bruk `interval` i stedet.
    private var billingInterval: BillingInterval = BillingInterval.monthly
    var nextRenewalDate: Date = Date.now
    /// Datoen fornyelsesrytmen regnes fra. Alle fornyelser beregnes direkte fra denne,
    /// slik at den 31. ikke permanent blir den 28. etter februar. Valgfri slik at
    /// eksisterende data migreres automatisk; `nil` betyr "bruk `nextRenewalDate`".
    var billingAnchorDate: Date?
    /// Når en gratis prøveperiode slutter og første betaling skjer. `nil` = ingen prøveperiode.
    var trialEndDate: Date?
    /// Utfaset: leses bare som reserve når `categoryCode` mangler eller er ukjent.
    /// Skrives fortsatt sammen med koden, så eldre app-versjoner som bare kjenner dette
    /// feltet viser riktig kategori. Må bli i skjemaet fordi felt ikke kan fjernes fra CloudKit.
    /// Bruk `kind` i stedet.
    private var category: SubscriptionCategory = SubscriptionCategory.annet
    var note: String?
    var isActive: Bool = true
    /// Antall dager før fornyelse appen skal varsle brukeren.
    var reminderDaysBefore: Int = 3
    /// Valgfritt eget SF Symbol-navn. Faller tilbake til kategoriens standardikon når nil.
    var symbolName: String?
    /// Valgfri egen farge, lagret som hex-streng (f.eks. "#FF9500").
    var colorHex: String?
    /// Antall personer kostnaden deles likt på, inkludert brukeren. 1 = ikke delt.
    var splitCount: Int = 1
    /// Valgfri nettadresse der abonnementet avsluttes. Lagres som tekst og tolkes via `cancelURL`.
    var cancelURLString: String?
    /// Når abonnementet ble avsluttet og flyttet til arkivet. `nil` = ikke avsluttet.
    var cancelledDate: Date?

    // Kategori og intervall lagres som ren tekst (rawValue) i stedet for som enum, slik at
    // en eldre versjon av appen ikke krasjer når den leser en verdi den ikke kjenner.
    // Gi aldri eksisterende rawValues nytt navn. Nye enum-tilfeller er trygge: eldre
    // versjoner faller da tilbake til det utfasede feltet (se `legacyCategories`).
    /// `SubscriptionCategory.rawValue`. `nil` = lagret før feltet fantes; bruk det utfasede `category`.
    var categoryCode: String?
    /// `BillingInterval.rawValue`. `nil` = lagret før feltet fantes; bruk det utfasede `billingInterval`.
    var billingIntervalCode: String?

    init(
        name: String,
        price: Decimal,
        currencyCode: String = "NOK",
        billingInterval: BillingInterval = .monthly,
        nextRenewalDate: Date = .now,
        trialEndDate: Date? = nil,
        category: SubscriptionCategory = .annet,
        note: String? = nil,
        isActive: Bool = true,
        reminderDaysBefore: Int = 3,
        symbolName: String? = nil,
        colorHex: String? = nil,
        splitCount: Int = 1,
        cancelURLString: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.price = price
        self.currencyCode = currencyCode
        self.nextRenewalDate = nextRenewalDate
        self.billingAnchorDate = nextRenewalDate
        self.trialEndDate = trialEndDate
        self.note = note
        self.isActive = isActive
        self.reminderDaysBefore = reminderDaysBefore
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.splitCount = splitCount
        self.cancelURLString = cancelURLString
        // Går via de beregnede egenskapene, slik at både tekstkodene og de utfasede
        // feltene får verdien.
        self.interval = billingInterval
        self.kind = category
    }

    /// Abonnementets kategori. Bruk denne, ikke det utfasede `category`.
    var kind: SubscriptionCategory {
        get { Self.resolve(code: categoryCode, legacy: category) }
        set {
            categoryCode = newValue.rawValue
            // Eldre versjoner leser bare det utfasede feltet. Uten dette ville de vist
            // «Annet» for alt som er lagret av denne versjonen.
            category = Self.legacyCategories.contains(newValue) ? newValue : .annet
        }
    }

    // Verdiene eldre app-versjoner kjenner. Bare disse kan skrives til de utfasede feltene,
    // ellers krasjer eldre versjoner når de leser en ukjent verdi. IKKE legg nye tilfeller
    // til her - nye kategorier og intervaller skrives som reserveverdien i stedet.
    private static let legacyCategories: Set<SubscriptionCategory> = [
        .streaming, .musikk, .programvare, .trening, .nettsky, .annet
    ]
    private static let legacyIntervals: Set<BillingInterval> = [.weekly, .monthly, .quarterly, .yearly]

    /// Hvor ofte abonnementet fornyes. Bruk denne, ikke det utfasede `billingInterval`.
    var interval: BillingInterval {
        get { Self.resolve(code: billingIntervalCode, legacy: billingInterval) }
        set {
            billingIntervalCode = newValue.rawValue
            // Eldre versjoner leser bare det utfasede feltet. Uten dette ville et årlig
            // abonnement vist som månedlig der, og totalen blitt 12 ganger for høy.
            billingInterval = Self.legacyIntervals.contains(newValue) ? newValue : .monthly
        }
    }

    /// Tolker en lagret tekstkode. Mangler koden, eller er den ukjent (f.eks. skrevet av
    /// en nyere versjon av appen), brukes den utfasede verdien i stedet.
    static func resolve<Value: RawRepresentable>(code: String?, legacy: Value) -> Value where Value.RawValue == String {
        code.flatMap(Value.init(rawValue:)) ?? legacy
    }

    var cancelURL: URL? {
        cancelURLString.flatMap(CancelLink.url(from:))
    }

    var isCancelled: Bool { cancelledDate != nil }

    /// Om abonnementet faktisk koster penger nå: verken pauset eller avsluttet.
    /// Brukes for totaler, statistikk, varsler og widget.
    var isBilling: Bool { isActive && !isCancelled }

    /// Hva brukeren har spart siden abonnementet ble avsluttet, i abonnementets valuta.
    func savedSinceCancellation(now: Date = .now, calendar: Calendar = .current) -> Decimal {
        guard let cancelledDate else { return 0 }
        return RenewalCalculator.savings(yearlyCost: yearlyCost, since: cancelledDate, now: now, calendar: calendar)
    }

    var scheduleAnchor: Date {
        billingAnchorDate ?? nextRenewalDate
    }

    /// Om prøveperioden fortsatt pågår (slutter i dag eller senere).
    func isInTrial(calendar: Calendar = .current, today: Date = .now) -> Bool {
        guard let trialEndDate else { return false }
        return calendar.startOfDay(for: trialEndDate) >= calendar.startOfDay(for: today)
    }

    /// Om en gitt fornyelse er den første betalingen etter prøveperioden.
    func isTrialEnd(_ renewalDate: Date, calendar: Calendar = .current) -> Bool {
        guard let trialEndDate else { return false }
        return calendar.isDate(trialEndDate, inSameDayAs: renewalDate)
    }

    /// Flytter en passert fornyelsesdato frem til neste fremtidige forekomst,
    /// f.eks. hvis appen ikke er åpnet på en stund eller abonnementet gjenopptas.
    func advanceRenewalDateIfPast(now: Date = .now, calendar: Calendar = .current) {
        // Sammenlign på dato, ikke klokkeslett: en fornyelse i dag er ikke "passert"
        // bare fordi klokken er forbi tidspunktet den ble registrert.
        let startOfToday = calendar.startOfDay(for: now)
        guard nextRenewalDate < startOfToday else { return }
        // Eldre abonnement fra før ankerdatoen fantes får den lagret nå.
        billingAnchorDate = scheduleAnchor
        nextRenewalDate = RenewalCalculator.advanceToFuture(
            anchor: scheduleAnchor,
            interval: interval,
            referenceDate: startOfToday,
            calendar: calendar
        )
    }

    /// De neste `count` fornyelsene, fra og med `nextRenewalDate`.
    func upcomingRenewalDates(count: Int, calendar: Calendar = .current) -> [Date] {
        RenewalCalculator.upcomingRenewalDates(
            anchor: scheduleAnchor,
            interval: interval,
            onOrAfter: nextRenewalDate,
            count: count,
            calendar: calendar
        )
    }

    var isShared: Bool { splitCount > 1 }

    /// Brukerens del av hvert trekk. Lik `price` når abonnementet ikke er delt.
    var myShare: Decimal {
        RenewalCalculator.share(of: price, splitCount: splitCount)
    }

    /// Hva brukerens del koster omregnet til per måned. Brukes i totaler og statistikk.
    var monthlyCost: Decimal {
        RenewalCalculator.monthlyCost(price: myShare, interval: interval)
    }

    /// Hva brukerens del koster omregnet til per år.
    var yearlyCost: Decimal {
        RenewalCalculator.yearlyCost(price: myShare, interval: interval)
    }

    /// Antall dager til neste fornyelse, regnet fra starten av i dag.
    func daysUntilRenewal(calendar: Calendar = .current, today: Date = .now) -> Int {
        let startOfToday = calendar.startOfDay(for: today)
        let startOfRenewal = calendar.startOfDay(for: nextRenewalDate)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfRenewal).day ?? 0
    }
}
