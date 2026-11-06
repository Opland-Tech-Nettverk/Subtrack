import Foundation

/// Et forslag til abonnement, funnet i trekk som kommer igjen på en kontoutskrift.
/// Bare i minnet: brukeren velger hvilke forslag som skal legges inn.
struct SubscriptionSuggestion: Identifiable, Equatable {
    enum Confidence: Equatable {
        case high, medium
    }

    /// Mottakeren trekkene er gruppert på. Lik for lik mottaker, så forslaget kan kjennes igjen.
    let id: String
    let name: String
    let price: Decimal
    let currencyCode: String
    let interval: BillingInterval
    let confidence: Confidence
    /// Dagen forslaget sist ble trukket.
    let lastChargeDate: Date
    /// Neste dato regnet fra siste trekk, aldri før dagen i dag.
    let nextExpectedDate: Date
    let chargeCount: Int
    let service: CatalogService?
    /// Utfylt utkast for skjemaet.
    let draft: SubscriptionDraft

    /// Abonnementet forslaget gir, slik skjemaet ville lagret det uten endringer.
    func makeSubscription() -> Subscription {
        let subscription = Subscription(
            name: draft.name ?? name,
            price: draft.price ?? price,
            currencyCode: draft.currencyCode ?? currencyCode,
            billingInterval: draft.interval ?? interval,
            nextRenewalDate: RenewalCalculator.normalizedToNoon(draft.nextRenewalDate ?? nextExpectedDate),
            category: draft.kind ?? .annet,
            symbolName: draft.symbolName,
            colorHex: draft.colorHex,
            cancelURLString: draft.cancelURLString
        )
        subscription.advanceRenewalDateIfPast()
        return subscription
    }
}

/// Finner abonnementer i betalinger fra en kontoutskrift: trekk fra samme mottaker som kommer igjen
/// med jevne mellomrom og omtrent samme beløp.
enum RecurringChargeDetector {
    /// Hvor langt unna medianen et beløp kan være og regnes som samme beløp.
    private static let amountTolerance: Decimal = Decimal(1) / Decimal(10)

    /// Avstander mellom trekk i dager som regnes som et intervall, og minste antall trekk.
    private static func band(for interval: BillingInterval) -> ClosedRange<Int> {
        switch interval {
        case .weekly: 6...8
        case .monthly: 27...33
        case .quarterly: 85...95
        case .yearly: 355...375
        }
    }

    private static func minimumCharges(for interval: BillingInterval) -> Int {
        switch interval {
        case .weekly, .monthly: 3
        case .quarterly, .yearly: 2
        }
    }

    /// Ett trekk med beløpet i originalvaluta, der teksten har det. Ellers er det beløpet i kontoens valuta.
    private struct Charge {
        let transaction: StatementTransaction
        let originalAmount: Decimal
        let originalCurrency: String
    }

    private struct ChargeGroup {
        var service: CatalogService?
        var isCatalogMatch = false
        var displayName = ""
        var charges: [Charge] = []
    }

    /// Forslagene, med de sikreste først. Forslag som allerede finnes som abonnement (`existingNames`),
    /// utelates: samme navn, eller samme tjeneste i katalogen.
    static func detect(
        transactions: [StatementTransaction],
        catalog: ServiceCatalog = .bundled,
        existingNames: [String] = [],
        now: Date = .now,
        calendar: Calendar = StatementValues.defaultCalendar
    ) -> [SubscriptionSuggestion] {
        let existingKeys = Set(existingNames.map(MerchantText.normalized))
        let existingServiceIDs = Set(existingNames.compactMap { catalog.match(merchantText: $0)?.service.id })

        var groups: [String: ChargeGroup] = [:]
        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            let merchant = MerchantNormalizer.normalize(transaction.text)
            let match = catalog.match(merchantText: transaction.text)
            // Bare et sikkert treff samler ulike skrivemåter i én gruppe. Et usikkert treff (kort
            // alias som «max») grupperes på teksten, så «Max Burger» ikke havner hos «Max».
            let isCatalogMatch = match?.confidence == .high
            let key = isCatalogMatch ? "catalog:\(match?.service.id ?? "")" : merchant.key
            guard !key.isEmpty else { continue }

            var group = groups[key] ?? ChargeGroup()
            group.isCatalogMatch = isCatalogMatch
            if group.service == nil, isCatalogMatch { group.service = match?.service }
            // Navnet fra den siste betalingen, i tilfelle skrivemåten har endret seg.
            if !merchant.displayName.isEmpty { group.displayName = merchant.displayName }
            group.charges.append(Charge(
                transaction: transaction,
                originalAmount: merchant.originalAmount ?? transaction.amount,
                originalCurrency: merchant.originalCurrency ?? transaction.currencyCode
            ))
            groups[key] = group
        }

        var suggestions: [SubscriptionSuggestion] = []
        for (key, group) in groups {
            guard let suggestion = makeSuggestion(for: group, key: key, now: now, calendar: calendar) else { continue }
            let nameKey = MerchantText.normalized(suggestion.name)
            if existingKeys.contains(nameKey) || existingKeys.contains(key) { continue }
            if let serviceID = suggestion.service?.id, existingServiceIDs.contains(serviceID) { continue }
            suggestions.append(suggestion)
        }

        return suggestions.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence == .high }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func makeSuggestion(
        for group: ChargeGroup,
        key: String,
        now: Date,
        calendar: Calendar
    ) -> SubscriptionSuggestion? {
        // Én betaling per dag: to kjøp samme dag gir ellers en avstand på 0 dager.
        var charges: [Charge] = []
        for charge in group.charges {
            if let last = charges.last, calendar.isDate(last.transaction.date, inSameDayAs: charge.transaction.date) {
                continue
            }
            charges.append(charge)
        }
        guard charges.count >= 2, let latest = charges.last else { return nil }

        let gaps: [Int] = zip(charges, charges.dropFirst()).map { pair in
            calendar.dateComponents([.day], from: pair.0.transaction.date, to: pair.1.transaction.date).day ?? 0
        }
        guard let interval = detectedInterval(forMedianGap: median(of: gaps)),
              charges.count >= minimumCharges(for: interval)
        else { return nil }

        // Avstandene må ligge nær intervallet. Én avvik tåles når det er nok trekk til å se det, f.eks.
        // en måned som mangler i utskriften.
        let inBand = gaps.filter { band(for: interval).contains($0) }.count
        let isRegular = inBand == gaps.count || (gaps.count >= 4 && Double(inBand) / Double(gaps.count) >= 0.75)
        guard isRegular else { return nil }

        // Beløpet må være omtrent likt i kontoens valuta, eller helt likt i originalvaluta (utenlandske
        // tjenester varierer i kroner med kursen).
        let currencies = Set(charges.map(\.transaction.currencyCode))
        let amounts = charges.map(\.transaction.amount).sorted()
        let reference = amounts[amounts.count / 2]
        let isCloseInAccountCurrency = currencies.count == 1
            && amounts.allSatisfy { abs($0 - reference) <= reference * amountTolerance }
        let isFixedInOriginalCurrency = Set(charges.map(\.originalCurrency)).count == 1
            && Set(charges.map(\.originalAmount)).count == 1
        guard isCloseInAccountCurrency || isFixedInOriginalCurrency else { return nil }

        let fixedOriginal: (Decimal, String)? = isFixedInOriginalCurrency ? (latest.originalAmount, latest.originalCurrency) : nil
        let lastCharge = (latest.transaction.amount, latest.transaction.currencyCode)
        let (price, currencyCode, plan) = chooseAmount(
            service: group.service,
            interval: interval,
            fixedOriginal: fixedOriginal,
            lastCharge: lastCharge
        )

        let minimum = minimumCharges(for: interval)
        let confidence: SubscriptionSuggestion.Confidence =
            (group.isCatalogMatch || charges.count > minimum) ? .high : .medium

        let nextExpected = nextDate(after: latest.transaction.date, interval: interval, now: now, calendar: calendar)
        let name = group.service?.name ?? group.displayName
        guard !name.isEmpty else { return nil }

        var draft = group.service?.draft(plan: plan) ?? SubscriptionDraft(source: .bankStatement)
        draft.source = .bankStatement
        draft.name = name
        draft.price = price
        draft.currencyCode = currencyCode
        draft.interval = interval
        draft.nextRenewalDate = nextExpected

        return SubscriptionSuggestion(
            id: key,
            name: name,
            price: price,
            currencyCode: currencyCode,
            interval: interval,
            confidence: confidence,
            lastChargeDate: latest.transaction.date,
            nextExpectedDate: nextExpected,
            chargeCount: charges.count,
            service: group.service,
            draft: draft
        )
    }

    /// Pris og valuta for forslaget:
    /// (a) treffer katalogen og en plan har samme valuta, samme intervall og omtrent samme beløp
    /// (±10 %), brukes planens pris og valuta;
    /// (b) ellers, står beløpet i originalvaluta likt i alle trekkene, brukes det med den valutaen,
    /// så årskostnaden ikke svinger med kursen;
    /// (c) ellers brukes det siste beløpet i kontoens valuta.
    private static func chooseAmount(
        service: CatalogService?,
        interval: BillingInterval,
        fixedOriginal: (Decimal, String)?,
        lastCharge: (Decimal, String)
    ) -> (Decimal, String, CatalogPlan?) {
        if let service {
            var candidates: [(Decimal, String)] = []
            if let fixedOriginal { candidates.append(fixedOriginal) }
            candidates.append(lastCharge)

            var best: (plan: CatalogPlan, distance: Decimal)?
            for candidate in candidates {
                for plan in service.plans where plan.interval == interval && plan.currencyCode == candidate.1 {
                    let distance = abs(plan.price - candidate.0)
                    guard distance <= plan.price * amountTolerance else { continue }
                    if best == nil || distance < best!.distance {
                        best = (plan, distance)
                    }
                }
            }
            if let best {
                return (best.plan.price, best.plan.currencyCode, best.plan)
            }
        }
        if let fixedOriginal {
            return (fixedOriginal.0, fixedOriginal.1, nil)
        }
        return (lastCharge.0, lastCharge.1, nil)
    }

    /// Intervallet medianen av avstandene tilsier, eller nil om den ikke ligger i noen av båndene.
    private static func detectedInterval(forMedianGap median: Double) -> BillingInterval? {
        let days = Int(median.rounded())
        return BillingInterval.allCases.first { band(for: $0).contains(days) }
    }

    private static func median(of values: [Int]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Double(sorted[middle - 1] + sorted[middle]) / 2
        }
        return Double(sorted[middle])
    }

    /// Neste forventede trekk: siste trekk pluss ett intervall, og videre frem til det ikke ligger før i dag.
    private static func nextDate(after last: Date, interval: BillingInterval, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        var count = 1
        var next = interval.advanced(from: last, by: count, calendar: calendar)
        while next < today && count < 1000 {
            count += 1
            next = interval.advanced(from: last, by: count, calendar: calendar)
        }
        return next
    }
}
