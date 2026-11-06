import Foundation

enum RenewalProgress {
    /// Hvor langt perioden fram mot neste trekk har kommet, fra 0 (rett etter forrige trekk)
    /// til 1 (trekkes i dag eller er forfalt). Regnet i hele dager.
    static func fraction(
        nextRenewal: Date,
        interval: BillingInterval,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double {
        let end = calendar.startOfDay(for: nextRenewal)
        let start = calendar.startOfDay(for: interval.advanced(from: nextRenewal, by: -1, calendar: calendar))
        let today = calendar.startOfDay(for: now)
        let total = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        guard total > 0 else { return 1 }
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return min(max(Double(elapsed) / Double(total), 0), 1)
    }
}

extension Subscription {
    /// Fremdriften mot neste trekk, se `RenewalProgress.fraction`.
    func renewalProgress(now: Date = .now, calendar: Calendar = .current) -> Double {
        RenewalProgress.fraction(nextRenewal: nextRenewalDate, interval: interval, now: now, calendar: calendar)
    }
}
