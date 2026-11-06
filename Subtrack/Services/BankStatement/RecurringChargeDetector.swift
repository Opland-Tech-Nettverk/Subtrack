import Foundation

/// Et forslag til abonnement, funnet i trekk som kommer igjen på en kontoutskrift.
/// Bare i minnet: brukeren velger hvilke forslag som skal legges inn.
nonisolated struct SubscriptionSuggestion: Identifiable, Equatable {
    nonisolated enum Confidence: Equatable {
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
    /// Navnet på et eksisterende abonnement dette forslaget ligner på uten å være det samme, f.eks.
    /// «Fitness» for «Fitness24Seven». Slike forslag er ikke huket av på forhånd, og raden sier fra.
    var similarTo: String? = nil

    /// Abonnementet forslaget gir, slik skjemaet ville lagret det uten endringer.
    /// Bare på hovedaktøren, siden modellen hører til SwiftData.
    @MainActor
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
/// `nonisolated` og uten tilstand, så analysen kan kjøres utenfor hovedtråden.
nonisolated enum RecurringChargeDetector {
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

    /// Dager i ett intervall, brukt til å avgjøre om en serie er avsluttet.
    private static func nominalDays(for interval: BillingInterval) -> Int {
        switch interval {
        case .weekly: 7
        case .monthly: 30
        case .quarterly: 91
        case .yearly: 365
        }
    }

    /// Om beløpene (i tidsrekkefølge) ligger nær hverandre, eller deler seg i to grupper der den
    /// første gruppen kommer før den andre: en prisendring. Prisene i gruppene må ligge innenfor en
    /// faktor to, så ett enkeltstående stort kjøp på slutten ikke regnes som ny pris.
    private static func priceLevels(_ amounts: [Decimal]) -> PriceLevels? {
        guard amounts.count >= 2 else { return PriceLevels(latestLevelCount: amounts.count, changed: false) }
        if level(of: amounts[...]) != nil {
            return PriceLevels(latestLevelCount: amounts.count, changed: false)
        }
        var best: PriceLevels?
        for split in 1..<amounts.count {
            if let head = level(of: amounts[..<split]), let tail = level(of: amounts[split...]),
               head * 2 >= tail, tail * 2 >= head {
                let count = amounts.count - split
                if best == nil || count > best!.latestLevelCount {
                    best = PriceLevels(latestLevelCount: count, changed: true)
                }
            }
        }
        return best
    }

    /// Hvor mange trekk den siste prisen hviler på, og om prisen er endret i perioden.
    private nonisolated struct PriceLevels {
        let latestLevelCount: Int
        let changed: Bool
    }

    /// Medianbeløpet når alle beløpene ligger innenfor ±10 % av det, ellers nil.
    private static func level(of amounts: ArraySlice<Decimal>) -> Decimal? {
        let sorted = amounts.sorted()
        let reference = sorted[sorted.count / 2]
        let isCluster = sorted.allSatisfy { abs($0 - reference) <= reference * amountTolerance }
        return isCluster ? reference : nil
    }

    private static func minimumCharges(for interval: BillingInterval) -> Int {
        switch interval {
        case .weekly, .monthly: 3
        case .quarterly, .yearly: 2
        }
    }

    /// Ett trekk med beløpet i originalvaluta, der teksten har det. Ellers er det beløpet i kontoens valuta.
    private nonisolated struct Charge {
        let transaction: StatementTransaction
        let originalAmount: Decimal
        let originalCurrency: String
    }

    private nonisolated struct ChargeGroup {
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
        let existingServiceIDs = Set(existingNames.compactMap { catalog.match(merchantText: $0)?.service.id })
        // Siste dag i utskriften. En serie som stoppet lenge før den, er avsluttet.
        let statementEnd = transactions.map(\.date).max() ?? now

        // Samme tekst kommer igjen mange ganger; rensing og katalogoppslag gjøres én gang per tekst.
        var lookups: [String: (merchant: NormalizedMerchant, match: CatalogMatch?)] = [:]
        var groups: [String: ChargeGroup] = [:]
        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            let merchant: NormalizedMerchant
            let match: CatalogMatch?
            if let known = lookups[transaction.text] {
                merchant = known.merchant
                match = known.match
            } else {
                merchant = MerchantNormalizer.normalize(transaction.text)
                match = catalog.match(merchantText: transaction.text)
                lookups[transaction.text] = (merchant, match)
            }
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
            guard let suggestion = makeSuggestion(
                for: group,
                key: key,
                statementEnd: statementEnd,
                now: now,
                calendar: calendar
            ) else { continue }
            // Samme tjeneste i katalogen, eller samme navn (store og små bokstaver, aksenter og
            // selskapsendelser som «AS» og «Norge» teller ikke): forslaget vises ikke. Et navn som bare
            // ligner (et ord er med i det andre, som «Fitness» og «Fitness24Seven») vises, men uten
            // hake og med en merknad, siden det kan være et nytt abonnement hos samme leverandør.
            if let serviceID = suggestion.service?.id, existingServiceIDs.contains(serviceID) { continue }
            let names = [suggestion.name, group.displayName].filter { !$0.isEmpty }
            var similar: String?
            var isSame = false
            for existing in existingNames {
                for name in names {
                    switch SubscriptionNameMatcher.match(existing, name) {
                    case .same: isSame = true
                    case .similar: if similar == nil { similar = existing }
                    case nil: break
                    }
                }
            }
            if isSame { continue }
            var shown = suggestion
            shown.similarTo = similar
            suggestions.append(shown)
        }

        return suggestions.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence == .high }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func makeSuggestion(
        for group: ChargeGroup,
        key: String,
        statementEnd: Date,
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

        // En serie som sluttet for lenge siden, er avsluttet og foreslås ikke: mer enn halvannet
        // intervall mellom siste trekk og slutten av utskriften. Regnet fra utskriften og ikke fra i dag,
        // så en gammel fil ikke får alt til å se avsluttet ut.
        let daysSinceLastCharge = calendar.dateComponents([.day], from: latest.transaction.date, to: statementEnd).day ?? 0
        guard Double(daysSinceLastCharge) <= 1.5 * Double(nominalDays(for: interval)) else { return nil }

        // Beløpet må være omtrent likt i kontoens valuta, eller helt likt i originalvaluta (utenlandske
        // tjenester varierer i kroner med kursen).
        // Én prisendring tåles: først én pris og så en annen (Netflix 129 og så 149). Den siste prisen brukes.
        let currencies = Set(charges.map(\.transaction.currencyCode))
        let levels = currencies.count == 1 ? priceLevels(charges.map(\.transaction.amount)) : nil
        let isCloseInAccountCurrency = levels != nil
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
        var confidence: SubscriptionSuggestion.Confidence =
            (group.isCatalogMatch || charges.count > minimum) ? .high : .medium
        // En ny pris som bare hviler på ett trekk, og som ingen plan i katalogen bekrefter, kan være et
        // engangsbeløp (en oppgradering eller et tillegg). Da er forslaget ikke sikkert nok til å huke av.
        if let levels, levels.changed, levels.latestLevelCount == 1, plan == nil, !isFixedInOriginalCurrency {
            confidence = .medium
        }

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

/// Sammenligner navnet på et eksisterende abonnement med navnet på et forslag fra en kontoutskrift.
/// Store og små bokstaver, aksenter, selskapsendelser («AS», «ASA», «Norge», «Ltd» …) og referansenumre
/// teller ikke. Har navnene de samme ordene, er det samme abonnement («Telenor» og «TELENOR NORGE AS»).
/// Er alle ordene i det ene med i det andre, eller et ord er begynnelsen på et annet (minst fire tegn),
/// ligner de bare («Fitness» og «Fitness24Seven», «Forsikring» og «Gjensidige Forsikring»).
nonisolated enum SubscriptionNameMatcher {
    nonisolated enum Match: Equatable {
        case same, similar
    }

    private static let noiseWords: Set<String> = [
        "as", "asa", "ab", "ltd", "limited", "inc", "gmbh", "norge", "norway", "sverige", "no", "com", "the"
    ]

    static func words(_ text: String) -> [String] {
        let tokens = MerchantText.normalized(text).split(separator: " ").map(String.init)
        return MerchantNormalizer.strippingReferences(tokens).filter { !noiseWords.contains($0) }
    }

    static func match(_ first: String, _ second: String) -> Match? {
        let a = words(first)
        let b = words(second)
        guard !a.isEmpty, !b.isEmpty else { return nil }
        if Set(a) == Set(b) { return .same }
        return covers(a, b) || covers(b, a) ? .similar : nil
    }

    /// Alle ordene i `small` har et like eller beslektet ord i `big`.
    private static func covers(_ big: [String], _ small: [String]) -> Bool {
        small.allSatisfy { word in
            big.contains { other in
                other == word
                    || (min(other.count, word.count) >= 4 && (other.hasPrefix(word) || word.hasPrefix(other)))
            }
        }
    }
}
