import Foundation

struct CategoryShare: Identifiable {
    let category: SubscriptionCategory
    let monthlyCost: Decimal
    /// Heltall i prosent. Summen av alle andelene er alltid 100 når det finnes kostnader.
    let percent: Int

    var id: SubscriptionCategory { category }
}

enum CategoryBreakdown {
    /// Andel per kategori i hele prosent som summerer til 100 (største rest-metoden),
    /// i samme rekkefølge som `costs`.
    static func shares(from costs: [CategoryCost]) -> [CategoryShare] {
        let total = costs.reduce(Decimal(0)) { $0 + $1.monthlyCost }
        guard total > 0 else {
            return costs.map { CategoryShare(category: $0.category, monthlyCost: $0.monthlyCost, percent: 0) }
        }
        let exact = costs.map { $0.monthlyCost.doubleValue / total.doubleValue * 100 }
        var percents = exact.map { Int($0.rounded(.down)) }
        let missing = 100 - percents.reduce(0, +)
        if missing > 0 {
            let order = exact.indices.sorted { lhs, rhs in
                let l = exact[lhs] - exact[lhs].rounded(.down)
                let r = exact[rhs] - exact[rhs].rounded(.down)
                return l == r ? lhs < rhs : l > r
            }
            for index in order.prefix(missing) {
                percents[index] += 1
            }
        }
        return costs.indices.map {
            CategoryShare(category: costs[$0].category, monthlyCost: costs[$0].monthlyCost, percent: percents[$0])
        }
    }

    /// Kategorien en vinkelverdi fra diagrammets valg faller i. Sektorene ligger i rekkefølgen i `costs`.
    static func category(atAngleValue value: Double, in costs: [CategoryCost]) -> SubscriptionCategory? {
        var running = 0.0
        for cost in costs {
            running += cost.monthlyCost.doubleValue
            if value <= running { return cost.category }
        }
        return nil
    }
}
