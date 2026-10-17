import Foundation

/// Rene, testbare funksjoner for kostnadsberegning og fornyelsesdatoer.
/// Holdes uavhengig av SwiftData/SwiftUI slik at den er enkel å enhetsteste.
enum RenewalCalculator {
    /// Regner om en pris og et faktureringsintervall til kostnad per måned.
    static func monthlyCost(price: Decimal, interval: BillingInterval) -> Decimal {
        price * interval.cyclesPerYear / 12
    }

    /// Regner om en pris og et faktureringsintervall til kostnad per år.
    static func yearlyCost(price: Decimal, interval: BillingInterval) -> Decimal {
        price * interval.cyclesPerYear
    }

    /// Brukerens del av en pris som deles likt på `splitCount` personer (inkludert brukeren).
    /// Verdier under 1 behandles som 1, så en ugyldig verdi aldri gir deling på null.
    static func share(of price: Decimal, splitCount: Int) -> Decimal {
        price / Decimal(max(splitCount, 1))
    }

    /// Hva et avsluttet abonnement ville kostet fra avslutningsdagen til i dag:
    /// årskostnaden fordelt på dager. Gir en jevn økning i stedet for hopp ved hver fornyelse.
    static func savings(
        yearlyCost: Decimal,
        since cancelledDate: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Decimal {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: cancelledDate),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return yearlyCost * Decimal(max(days, 0)) / 365
    }

    /// Sikkerhetstak så en ugyldig kalenderberegning aldri kan gi en evig løkke.
    private static let maxOccurrenceIndex = 10_000

    /// Fornyelse nr. `index` (0 = ankeret selv), regnet direkte fra ankeret.
    static func occurrence(
        _ index: Int,
        anchor: Date,
        interval: BillingInterval,
        calendar: Calendar = .current
    ) -> Date {
        interval.advanced(from: anchor, by: index, calendar: calendar)
    }

    /// Indeksen til første fornyelse fra ankeret som ikke ligger før `referenceDate`.
    private static func firstOccurrenceIndex(
        anchor: Date,
        interval: BillingInterval,
        onOrAfter referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        var index = 0
        while index < maxOccurrenceIndex,
              occurrence(index, anchor: anchor, interval: interval, calendar: calendar) < referenceDate {
            index += 1
        }
        return index
    }

    /// Første fornyelse fra ankeret som ikke ligger før `referenceDate`. Brukes til å
    /// holde `nextRenewalDate` oppdatert når brukeren ikke har åpnet appen på en stund.
    static func advanceToFuture(
        anchor: Date,
        interval: BillingInterval,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let index = firstOccurrenceIndex(anchor: anchor, interval: interval, onOrAfter: referenceDate, calendar: calendar)
        return occurrence(index, anchor: anchor, interval: interval, calendar: calendar)
    }

    /// De neste `count` fornyelsene i ankerets rytme, fra og med `startDate`.
    static func upcomingRenewalDates(
        anchor: Date,
        interval: BillingInterval,
        onOrAfter startDate: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        let first = firstOccurrenceIndex(anchor: anchor, interval: interval, onOrAfter: startDate, calendar: calendar)
        return (first..<(first + count)).map {
            occurrence($0, anchor: anchor, interval: interval, calendar: calendar)
        }
    }

    /// Varseltidspunkt for slutten av en prøveperiode. Slutter prøveperioden før det
    /// foretrukne varselet rekker å gå, prøver vi dagen før og så samme morgen - et
    /// glemt prøveperiode-varsel er dyrere for brukeren enn et litt sent et.
    /// Returnerer `nil` bare hvis alle alternativene allerede er passert.
    static func trialReminderDate(
        trialEndDate: Date,
        preferredDaysBefore: Int,
        after now: Date,
        hour: Int = 9,
        calendar: Calendar = .current
    ) -> Date? {
        let fallbacks = [preferredDaysBefore, 1, 0].filter { $0 <= preferredDaysBefore }
        return fallbacks
            .compactMap { reminderDate(nextRenewalDate: trialEndDate, daysBefore: $0, hour: hour, calendar: calendar) }
            .first { $0 > now }
    }

    /// Tidspunktet et varsel skal utløses: `daysBefore` dager før `nextRenewalDate`, klokken `hour`.
    /// Returnerer `nil` hvis datoberegningen skulle feile (bør i praksis aldri skje).
    static func reminderDate(
        nextRenewalDate: Date,
        daysBefore: Int,
        hour: Int = 9,
        calendar: Calendar = .current
    ) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: nextRenewalDate) else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = 0
        return calendar.date(from: components)
    }
}
