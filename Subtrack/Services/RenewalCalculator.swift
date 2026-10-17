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

    /// Samme kalenderdag klokken 12:00. Datoer lagres som et tidspunkt, og en fornyelse
    /// registrert 23:30 ville vist en annen dato i en annen tidssone (f.eks. på reise eller
    /// på en annen enhet via iCloud). Midt på dagen gir samme dato så lenge tidssonene ligger
    /// inntil 11 timer fra hverandre, og påvirkes ikke av sommertid, som skifter om natten.
    static func normalizedToNoon(_ date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? date
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

    /// Varseltidspunkt for en fornyelse. Helst `preferredDaysBefore` dager før klokken `hour`;
    /// er det allerede passert, prøver vi dagen før og så samme morgen - et litt sent varsel
    /// er bedre enn ingen varsel. `isFallback` er `true` når et av reservetidspunktene ble
    /// brukt, så kalleren kan la være å varsle på nytt om en fornyelse det allerede er
    /// varslet om. Returnerer `nil` bare hvis alle alternativene allerede er passert.
    static func reminderDate(
        forRenewal renewalDate: Date,
        preferredDaysBefore: Int,
        after now: Date,
        hour: Int = 9,
        calendar: Calendar = .current
    ) -> (date: Date, isFallback: Bool)? {
        // Aldri tidligere enn brukeren har bedt om, f.eks. ikke dagen før når varselet er satt til samme dag.
        let candidates = [preferredDaysBefore, 1, 0].filter { $0 <= preferredDaysBefore }
        for (index, daysBefore) in candidates.enumerated() {
            guard let date = reminderDate(nextRenewalDate: renewalDate, daysBefore: daysBefore, hour: hour, calendar: calendar),
                  date > now else { continue }
            return (date, index > 0)
        }
        return nil
    }

    /// Varseltidspunkt for slutten av en prøveperiode, med samme reserver som
    /// `reminderDate(forRenewal:preferredDaysBefore:after:hour:calendar:)`.
    /// Returnerer `nil` bare hvis alle alternativene allerede er passert.
    static func trialReminderDate(
        trialEndDate: Date,
        preferredDaysBefore: Int,
        after now: Date,
        hour: Int = 9,
        calendar: Calendar = .current
    ) -> Date? {
        reminderDate(
            forRenewal: trialEndDate,
            preferredDaysBefore: preferredDaysBefore,
            after: now,
            hour: hour,
            calendar: calendar
        )?.date
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
