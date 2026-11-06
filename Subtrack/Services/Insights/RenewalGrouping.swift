import Foundation

/// Tidsvinduene abonnementene grupperes i på oversikten, sortert på neste fornyelse.
enum RenewalGroup: Int, CaseIterable, Identifiable {
    case thisWeek, thisMonth, later, paused

    var id: Self { self }

    var title: String {
        switch self {
        case .thisWeek: "Denne uka"
        case .thisMonth: "Denne måneden"
        case .later: "Senere"
        case .paused: "Pauset"
        }
    }
}

struct RenewalGroupSection: Identifiable {
    let group: RenewalGroup
    let subscriptions: [Subscription]

    var id: RenewalGroup { group }
}

enum RenewalGrouping {
    /// Hvilken gruppe en fornyelsesdato hører til. «Denne uka» er resten av kalenderuka
    /// (også forfalte datoer), «Denne måneden» resten av måneden etter det, og alt annet er «Senere».
    static func group(forRenewalOn date: Date, now: Date = .now, calendar: Calendar = .current) -> RenewalGroup {
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), date < week.end {
            return .thisWeek
        }
        if let month = calendar.dateInterval(of: .month, for: now), date < month.end {
            return .thisMonth
        }
        return .later
    }

    static func group(for subscription: Subscription, now: Date = .now, calendar: Calendar = .current) -> RenewalGroup {
        guard subscription.isActive else { return .paused }
        return group(forRenewalOn: subscription.nextRenewalDate, now: now, calendar: calendar)
    }

    /// Deler abonnementene i grupper og beholder rekkefølgen innen hver gruppe. Tomme grupper utelates.
    static func sections(
        _ subscriptions: [Subscription],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [RenewalGroupSection] {
        let grouped = Dictionary(grouping: subscriptions) { group(for: $0, now: now, calendar: calendar) }
        return RenewalGroup.allCases.compactMap { group in
            guard let members = grouped[group], !members.isEmpty else { return nil }
            return RenewalGroupSection(group: group, subscriptions: members)
        }
    }
}
