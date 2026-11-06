import Foundation

struct MonthCost: Identifiable {
    /// Starten av måneden.
    let monthStart: Date
    let total: Decimal
    let chargeCount: Int

    var id: Date { monthStart }
}

struct ForwardCostResult {
    let months: [MonthCost]
    let excludedCount: Int

    var total: Decimal { months.reduce(Decimal(0)) { $0 + $1.total } }
    /// Dyreste måned, eller `nil` når ingenting trekkes.
    var peak: MonthCost? {
        months.filter { $0.total > 0 }.max { $0.total < $1.total }
    }
}

enum ForwardCost {
    /// Hva abonnementene koster de neste `count` kalendermånedene, fra og med måneden `now` er i.
    /// Den første måneden teller bare trekk fra og med i dag. Brukerens del av hvert trekk (`myShare`)
    /// regnes om med `convert`; trekk uten kurs telles i `excludedCount`.
    static func months(
        of subscriptions: [Subscription],
        now: Date = .now,
        count: Int = 12,
        calendar: Calendar = .current,
        convert: (Decimal, String) -> Decimal?
    ) -> ForwardCostResult {
        guard count > 0 else { return ForwardCostResult(months: [], excludedCount: 0) }
        let firstMonth = MonthGrid.monthStart(offsetBy: 0, from: now, calendar: calendar)
        let monthStarts = (0..<count).map { MonthGrid.monthStart(offsetBy: $0, from: firstMonth, calendar: calendar) }
        guard
            let windowEnd = calendar.date(byAdding: .month, value: count, to: firstMonth),
            let lastDay = calendar.date(byAdding: .day, value: -1, to: windowEnd)
        else { return ForwardCostResult(months: [], excludedCount: 0) }

        let charges = ChargeSchedule.occurrences(of: subscriptions, from: now, through: lastDay, calendar: calendar)
        var totals = Array(repeating: Decimal(0), count: count)
        var counts = Array(repeating: 0, count: count)
        var excluded = 0
        for charge in charges {
            let monthStart = MonthGrid.monthStart(offsetBy: 0, from: charge.date, calendar: calendar)
            guard let index = monthStarts.firstIndex(of: monthStart) else { continue }
            if let amount = convert(charge.subscription.myShare, charge.subscription.currencyCode) {
                totals[index] += amount
                counts[index] += 1
            } else {
                excluded += 1
            }
        }
        let months = monthStarts.indices.map {
            MonthCost(monthStart: monthStarts[$0], total: totals[$0], chargeCount: counts[$0])
        }
        return ForwardCostResult(months: months, excludedCount: excluded)
    }
}
