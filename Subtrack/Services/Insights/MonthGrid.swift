import Foundation

/// Rutenettet for en kalendermåned.
enum MonthGrid {
    /// Dagene i måneden som inneholder `month`, med `nil` som fyll foran første og etter siste dag,
    /// så antallet alltid er et helt antall uker. Første ukedag følger kalenderen (mandag i Norge).
    static func cells(for month: Date, calendar: Calendar = .current) -> [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: month),
            let dayCount = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    /// Starten av måneden som ligger `offset` måneder fra `date`.
    static func monthStart(offsetBy offset: Int, from date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        return calendar.date(byAdding: .month, value: offset, to: start) ?? start
    }

    /// Trekkene i hele måneden som inneholder `month`.
    static func charges(
        of subscriptions: [Subscription],
        inMonthOf month: Date,
        calendar: Calendar = .current
    ) -> [ChargeOccurrence] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else { return [] }
        return ChargeSchedule.occurrences(of: subscriptions, from: interval.start, through: last, calendar: calendar)
    }
}
