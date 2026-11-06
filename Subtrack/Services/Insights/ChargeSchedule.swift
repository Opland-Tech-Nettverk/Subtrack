import Foundation

/// Ett trekk: et abonnement og datoen det trekkes.
struct ChargeOccurrence: Identifiable {
    let subscription: Subscription
    let date: Date
    /// Om dette er første betaling etter en gratis prøveperiode.
    let isTrialEnd: Bool

    var id: String { "\(subscription.id.uuidString)-\(date.timeIntervalSince1970)" }
}

/// Trekkene på én dag.
struct ChargeDay: Identifiable {
    /// Starten av dagen.
    let date: Date
    let charges: [ChargeOccurrence]

    var id: Date { date }
    var hasCharges: Bool { !charges.isEmpty }
}

/// Trekkene i en periode på sju dager, med sum i hovedvalutaen.
struct ChargeWeek: Identifiable {
    let index: Int
    let days: [ChargeDay]
    /// Summen av trekkene som kunne regnes om. Se `UpcomingStrip.excludedCount`.
    let total: Decimal

    var id: Int { index }
    var firstDay: Date { days.first?.date ?? .now }
    var lastDay: Date { days.last?.date ?? .now }
    var chargeCount: Int { days.reduce(0) { $0 + $1.charges.count } }
}

/// Oversikten «neste 30 dager»: trekk per dag, gruppert i uker, med sum.
struct UpcomingStrip {
    let weeks: [ChargeWeek]
    let total: Decimal
    /// Trekk uten valutakurs, som ikke er med i summene.
    let excludedCount: Int

    var days: [ChargeDay] { weeks.flatMap(\.days) }
    var chargeCount: Int { weeks.reduce(0) { $0 + $1.chargeCount } }
}

/// Rene funksjoner som finner når abonnementene trekkes. Uavhengig av SwiftUI og SwiftData-kontekst.
enum ChargeSchedule {
    /// Alle trekk fra og med dagen `start` til og med dagen `end`, sortert etter dato og navn.
    /// Bare abonnement som koster penger nå (verken pauset eller avsluttet) tas med.
    /// Trekk regnes ut fra abonnementets anker, så en dato tidligere enn `nextRenewalDate`
    /// i samme måned også gir riktige trekk, men aldri før ankeret.
    static func occurrences(
        of subscriptions: [Subscription],
        from start: Date,
        through end: Date,
        calendar: Calendar = .current
    ) -> [ChargeOccurrence] {
        let startDay = calendar.startOfDay(for: start)
        guard
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)),
            endExclusive > startDay
        else { return [] }

        let spanDays = calendar.dateComponents([.day], from: startDay, to: endExclusive).day ?? 0
        var result: [ChargeOccurrence] = []

        for subscription in subscriptions where subscription.isBilling {
            let dates = RenewalCalculator.upcomingRenewalDates(
                anchor: subscription.scheduleAnchor,
                interval: subscription.interval,
                onOrAfter: startDay,
                count: maxCount(for: subscription.interval, spanDays: spanDays),
                calendar: calendar
            )
            for date in dates where date < endExclusive {
                result.append(ChargeOccurrence(
                    subscription: subscription,
                    date: date,
                    isTrialEnd: subscription.isTrialEnd(date, calendar: calendar)
                ))
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.subscription.name.localizedStandardCompare(rhs.subscription.name) == .orderedAscending
        }
    }

    /// Så mange trekk kan høyst falle i en periode, med en liten ekstra margin.
    private static func maxCount(for interval: BillingInterval, spanDays: Int) -> Int {
        let daysPerCycle = switch interval {
        case .weekly: 7
        case .monthly: 28
        case .quarterly: 89
        case .yearly: 365
        }
        return spanDays / daysPerCycle + 2
    }

    /// Trekkene de neste `days` dagene fra og med i dag, én oppføring per dag, delt i uker på sju dager.
    /// `convert` regner et beløp om til hovedvalutaen, eller gir `nil` når kurs mangler.
    /// Beløpet er brukerens del av trekket (`myShare`).
    static func upcomingStrip(
        subscriptions: [Subscription],
        now: Date = .now,
        days: Int = 30,
        calendar: Calendar = .current,
        convert: (Decimal, String) -> Decimal?
    ) -> UpcomingStrip {
        let today = calendar.startOfDay(for: now)
        guard days > 0, let last = calendar.date(byAdding: .day, value: days - 1, to: today) else {
            return UpcomingStrip(weeks: [], total: 0, excludedCount: 0)
        }
        let charges = occurrences(of: subscriptions, from: today, through: last, calendar: calendar)
        let chargesByDay = Dictionary(grouping: charges) { calendar.startOfDay(for: $0.date) }

        let allDays: [ChargeDay] = (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return ChargeDay(date: day, charges: chargesByDay[day] ?? [])
        }

        var excluded = 0
        var weeks: [ChargeWeek] = []
        var start = 0
        while start < allDays.count {
            let chunk = Array(allDays[start..<min(start + 7, allDays.count)])
            var total = Decimal(0)
            for charge in chunk.flatMap(\.charges) {
                if let amount = convert(charge.subscription.myShare, charge.subscription.currencyCode) {
                    total += amount
                } else {
                    excluded += 1
                }
            }
            weeks.append(ChargeWeek(index: weeks.count, days: chunk, total: total))
            start += 7
        }
        return UpcomingStrip(
            weeks: weeks,
            total: weeks.reduce(Decimal(0)) { $0 + $1.total },
            excludedCount: excluded
        )
    }
}
