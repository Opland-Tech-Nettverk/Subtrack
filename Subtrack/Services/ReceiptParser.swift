import Foundation

/// Det som er lest ut av en kvittering. Alle felt er valgfrie: det som ikke kan leses sikkert, står tomt.
/// `nonisolated` og `Sendable` så resultatet kan lages utenfor hovedtråden.
nonisolated struct ReceiptFields: Sendable {
    var name: String?
    /// Katalogtjenesten navnet ble gjenkjent som, om noen.
    var catalogServiceID: String?
    var price: Decimal?
    var currencyCode: String?
    var interval: BillingInterval?
    var nextRenewalDate: Date?

    /// Sant når alt skjemaet bryr seg om, er funnet. Da trengs det ikke noe mer tolking.
    var isComplete: Bool {
        name != nil && price != nil && currencyCode != nil && interval != nil && nextRenewalDate != nil
    }
}

/// Et beløp med valuta funnet i kvitteringsteksten.
nonisolated struct ReceiptAmount: Equatable, Sendable {
    let price: Decimal
    let currencyCode: String
}

/// Et beløp sammen med hvor sannsynlig det er at det er totalsummen. Høyere er mer sannsynlig.
nonisolated struct ReceiptAmountCandidate: Equatable, Sendable {
    let amount: ReceiptAmount
    let score: Int
    /// Linjen beløpet står på (og linjen foran hvis beløpet står alene). Brukes til å finne intervallet som hører til beløpet.
    let context: String
}

/// Regelbasert tolking av kvitteringstekst (delt tekst, PDF eller OCR av bilde) til et utkast.
///
/// Rene funksjoner uten tilgang til SwiftData eller UI. Usikre felt blir stående tomme i stedet for gjettet:
/// flere like gode beløp gir for eksempel ikke noe beløp, og to ulike intervaller gir ikke noe intervall.
nonisolated enum ReceiptParser {
    /// Lengre tekst kuttes. Samme grense som innboksen bruker når teksten lagres.
    static let maxInputLength = 20_000

    /// Leser ut det som kan leses sikkert. `now` og `calendar` kan byttes i tester.
    static func parse(
        _ text: String,
        catalog: ServiceCatalog,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReceiptFields {
        let cleaned = clean(text)
        let lines = cleaned
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        var fields = ReceiptFields()
        let identified = identifyService(lines: lines, catalog: catalog)
        fields.name = identified.name
        fields.catalogServiceID = identified.serviceID

        let amount = bestAmount(in: cleaned)
        if let amount {
            fields.price = amount.price
            fields.currencyCode = amount.currencyCode
        }
        // Står intervallet på samme linje som det valgte beløpet («1 188 kr (12 måneder)»), hører det til beløpet.
        // Ellers brukes det teksten sier som helhet.
        fields.interval = amount.flatMap { pairedInterval(for: $0, in: cleaned) } ?? interval(in: cleaned)
        fields.nextRenewalDate = renewalDate(in: cleaned, now: now, calendar: calendar)
        return fields
    }

    // MARK: - Rensing

    /// Normaliserer linjeskift og mellomrom (også hardt og smalt mellomrom, som epost og PDF er full av),
    /// fjerner usynlige tegn og kutter teksten til `maxInputLength`. Tomme linjer beholdes ikke etter rensing av ender.
    static func clean(_ text: String) -> String {
        var result = String(text.prefix(maxInputLength))
        result = result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for space in ["\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}", "\u{2002}", "\u{2003}", "\t"] {
            result = result.replacingOccurrences(of: space, with: " ")
        }
        for invisible in ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{00AD}"] {
            result = result.replacingOccurrences(of: invisible, with: "")
        }
        result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        return result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Navn

    /// Navn og eventuell katalogtjeneste. Rekkefølge: katalogtreff i toppen av teksten (avsender, emne og de første
    /// linjene), så ett entydig katalogtreff i resten av teksten (Apple- og Google-kvitteringer har tjenesten i
    /// innholdet, ikke i avsenderen), så avsenderen, så første linje.
    static func identifyService(lines allLines: [String], catalog: ServiceCatalog) -> (name: String?, serviceID: String?) {
        // E-postadresser og mottakerlinjer ut før katalogtreff: «ola@icloud.com» skal ikke gi iCloud+.
        let lines = matchableLines(allLines)
        let header = headerLines(lines).joined(separator: "\n")
        if let match = catalog.match(merchantText: header) {
            return (match.service.name, match.service.id)
        }

        // Bare sikre treff i resten av teksten, og bare hvis alle treffene er samme tjeneste.
        var found: [CatalogService] = []
        for line in lines {
            guard let match = catalog.match(merchantText: line), case .high = match.confidence else { continue }
            if !found.contains(where: { $0.id == match.service.id }) {
                found.append(match.service)
            }
        }
        if found.count == 1, let service = found.first {
            return (service.name, service.id)
        }

        if let sender = senderName(lines: allLines) {
            return (sender, nil)
        }
        return (firstLineName(lines: allLines), nil)
    }

    private static let senderKeys = ["fra:", "from:", "avsender:"]
    private static let emailAddress = regex(#"[^\s<>"'(),;:]+@([^\s<>"'(),;]+)"#)

    /// Postkassedomener folk har selv. En videresendt kvittering har brukerens egen adresse som avsender, og
    /// «icloud.com» ville truffet iCloud+. Ekte iCloud+-kvitteringer kommer fra apple.com.
    private static let personalMailDomains = [
        "icloud.com", "me.com", "mac.com", "gmail.com", "googlemail.com", "outlook.com", "hotmail.com",
        "live.com", "yahoo.com", "online.no", "proton.me", "protonmail.com"
    ]

    private static func isPersonalMailDomain(_ domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". >"))
        return personalMailDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Linjene som katalogen får se: uten e-postadresser. Resten av linjen beholdes, også `Til: Viaplay Norge AS`
    /// i en Vipps- eller bankbekreftelse. På avsenderlinjer beholdes domenet («info@mailer.netflix.com» gir
    /// «mailer.netflix.com»), men ikke når det er et personlig postkassedomene.
    static func matchableLines(_ lines: [String]) -> [String] {
        lines.map { line in
            let keepDomain = senderKeys.contains { line.lowercased().hasPrefix($0) }
            var result = line
            let matches = emailAddress.matches(in: line, range: NSRange(line.startIndex..., in: line))
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: result), let domainRange = Range(match.range(at: 1), in: line) else { continue }
                let domain = String(line[domainRange])
                let replacement = keepDomain && !isPersonalMailDomain(domain) ? domain : " "
                result.replaceSubrange(whole, with: replacement)
            }
            return result
        }
    }

    private static let headerKeys = ["fra:", "from:", "emne:", "subject:", "avsender:", "forhandler:", "merchant:"]

    private static func headerLines(_ lines: [String]) -> [String] {
        var result = Array(lines.prefix(6))
        for line in lines.dropFirst(6) {
            let lower = line.lowercased()
            if headerKeys.contains(where: { lower.hasPrefix($0) }) {
                result.append(line)
            }
        }
        return result
    }

    /// Visningsnavnet (eller domenet) fra en «Fra:»-linje.
    static func senderName(lines: [String]) -> String? {
        for line in lines {
            let lower = line.lowercased()
            for key in ["fra:", "from:", "avsender:"] where lower.hasPrefix(key) {
                let value = String(line.dropFirst(key.count))
                return senderName(fromHeaderValue: value)
            }
        }
        return nil
    }

    /// «Netflix <info@mailer.netflix.com>» gir «Netflix». «info@netflix.com» gir «Netflix» via domenet.
    /// Generiske avsendernavn som «no-reply» hoppes over.
    static func senderName(fromHeaderValue value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var display = ""
        var address = ""
        if let open = trimmed.firstIndex(of: "<") {
            display = String(trimmed[..<open])
            let rest = trimmed[trimmed.index(after: open)...]
            address = String(rest.prefix { $0 != ">" })
        } else if trimmed.contains("@") {
            address = trimmed
        } else {
            display = trimmed
        }

        display = display.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        if display.contains("@") {
            if address.isEmpty { address = display }
            display = ""
        }
        if isUsefulName(display) {
            return display
        }
        return domainName(fromAddress: address)
    }

    private static let genericSenderWords = [
        "noreply", "no-reply", "no_reply", "donotreply", "do-not-reply", "support", "billing",
        "receipt", "kvittering", "faktura", "invoice", "kundeservice", "notification", "orders",
        "info", "post", "mail", "email"
    ]

    private static func isUsefulName(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard name.contains(where: \.isLetter), name.count <= 50 else { return false }
        return !genericSenderWords.contains { lower == $0 || lower.contains("reply") }
    }

    private static let secondLevelLabels: Set<String> = ["co", "com", "org", "net", "ac", "gov"]

    /// «no-reply@mailer.netflix.com» gir «Netflix».
    private static func domainName(fromAddress address: String) -> String? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        let host = address[address.index(after: at)...]
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " >."))
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }

        var label = labels[labels.count - 2]
        if labels.count >= 3, secondLevelLabels.contains(label), labels[labels.count - 1].count == 2 {
            label = labels[labels.count - 3]
        }
        guard label.contains(where: \.isLetter) else { return nil }
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    private static let skippedLeadWords = [
        "hei", "hi", "hello", "hallo", "hey", "kjære", "dear", "takk", "thank", "thanks",
        "kvittering", "receipt", "faktura", "invoice", "ordrebekreftelse", "order", "ordre",
        "betalingsbekreftelse", "payment", "betaling", "your", "din", "ditt", "dine"
    ]

    /// Første linje som ser ut som et navn: kort, med bokstaver, og ikke en hilsen eller en dokumenttittel.
    static func firstLineName(lines: [String]) -> String? {
        for line in lines.prefix(5) {
            let lower = line.lowercased()
            if headerKeys.contains(where: { lower.hasPrefix($0) }) || lower.hasPrefix("til:") || lower.hasPrefix("to:") {
                continue
            }
            let firstWord = lower.prefix { $0.isLetter }
            if skippedLeadWords.contains(String(firstWord)) { continue }
            let name = line.trimmingCharacters(in: CharacterSet(charactersIn: " :.!,;"))
            guard name.first?.isLetter == true, name.count <= 50 else { continue }
            // Ikke «Ordrenummer: 12345» eller skjermbildestøy som «14:32 5G».
            if name.range(of: #":\s*\S*\d"#, options: .regularExpression) != nil { continue }
            if name.filter(\.isNumber).count * 10 > name.count * 3 { continue }
            return name
        }
        return nil
    }

    // MARK: - Beløp

    private static let numberPattern =
        #"(?:\d{1,3}(?: \d{3})+(?:[.,]\d{1,2})?|\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#

    /// Valutaer med bokstavkode (de samme som kursene støtter) og symbolene som er vanlige på kvitteringer.
    /// `$` tolkes som USD, `kr` og «,-» som NOK og `£` som GBP. Bokstavkodene må stå med store bokstaver, ellers
    /// ville «try 3 months» blitt 3 tyrkiske lira.
    private static let currencyAlternatives: String = {
        let codes = CurrencyConverter.supportedCurrencies.joined(separator: "|")
        return #"us\$|kroner|kr\.?|€|\$|£|(?-i:"# + codes + #")"#
    }()

    private static let amountAfter = try! NSRegularExpression(
        pattern: #"(?<![\d.,])("# + numberPattern + #") ?("# + currencyAlternatives + #"|,-)(?![\p{L}\d])"#,
        options: .caseInsensitive
    )

    private static let amountBefore = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\d])("# + currencyAlternatives + #") ?("# + numberPattern + #")(?!\d|[.,]\d)"#,
        options: .caseInsensitive
    )

    private static func currencyCode(forToken token: String) -> String? {
        let lower = token.lowercased()
        switch lower {
        case "kr", "kr.", "kroner", ",-": return "NOK"
        case "€": return "EUR"
        case "$", "us$": return "USD"
        case "£": return "GBP"
        default:
            let upper = lower.uppercased()
            return CurrencyConverter.supportedCurrencies.contains(upper) ? upper : nil
        }
    }

    /// Alle beløp med valuta på én linje, i den rekkefølgen de står. Beløp som er 0 eller ikke kan tolkes, tas ikke med.
    static func amounts(inLine line: String) -> [ReceiptAmount] {
        var found: [(location: Int, amount: ReceiptAmount)] = []
        let range = NSRange(line.startIndex..., in: line)

        func append(_ match: NSTextCheckingResult, numberGroup: Int, currencyGroup: Int) {
            guard
                let numberRange = Range(match.range(at: numberGroup), in: line),
                let currencyRange = Range(match.range(at: currencyGroup), in: line),
                let price = PriceParser.parse(String(line[numberRange])),
                price > 0,
                let code = currencyCode(forToken: String(line[currencyRange]))
            else { return }
            let amount = ReceiptAmount(price: price, currencyCode: code)
            // «kr 129,00 kr» gir to treff på samme sted; ett er nok.
            if !found.contains(where: { abs($0.location - match.range.location) < 12 && $0.amount == amount }) {
                found.append((match.range.location, amount))
            }
        }

        for match in amountAfter.matches(in: line, range: range) {
            append(match, numberGroup: 1, currencyGroup: 2)
        }
        for match in amountBefore.matches(in: line, range: range) {
            append(match, numberGroup: 2, currencyGroup: 1)
        }
        return found.sorted { $0.location < $1.location }.map(\.amount)
    }

    /// Linjen uten beløpene, brukt til å se om linjen sier hva beløpet er.
    private static func remainder(ofLine line: String) -> String {
        var result = line
        for expression in [amountAfter, amountBefore] {
            result = expression.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        return result
    }

    /// Alle beløp i teksten med en poengsum for hvor sannsynlig det er at de er det som skal betales.
    /// Står linjen bare med beløpet, brukes linjen foran som sammenheng («Totalt» på en linje, beløpet på neste).
    static func amountCandidates(in text: String) -> [ReceiptAmountCandidate] {
        var result: [ReceiptAmountCandidate] = []
        var previous: String?
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let found = amounts(inLine: line)
            if !found.isEmpty {
                let remaining = remainder(ofLine: line)
                let letters = remaining.filter(\.isLetter).count
                let context = letters < 3 ? ((previous ?? "") + " " + remaining) : remaining
                let score = score(context: context.lowercased())
                let lineContext = letters < 3 ? (previous ?? "") + " " + line : line
                result.append(contentsOf: found.map {
                    ReceiptAmountCandidate(amount: $0, score: score, context: lineContext)
                })
            }
            previous = line
        }
        return result
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let totalWords = regex(#"\b(?:totalt|total|sum)\b|å betale|amount due|total due|balance due|grand total|order total|you paid|du betalte|totalbeløp|betalingsbeløp"#)
    private static let inclusiveWords = regex(#"\b(?:inkl|incl|including|inklusive)\b"#)
    private static let taxWords = regex(#"\b(?:mva|vat|tax|moms|avgift)\b"#)

    private static let scoreRules: [(NSRegularExpression, Int)] = [
        (regex(#"å betale|amount due|total due|balance due|grand total|order total|you paid|du betalte|totalbeløp|betalingsbeløp"#), 12),
        (regex(#"\b(?:totalt|total|sum)\b"#), 10),
        (regex(#"\b(?:beløp|amount|price|pris|charged|belastet|trukket|betalt|paid|payment|betaling|billed|fakturert)\b"#), 5),
        (regex(#"\b(?:deretter|then|thereafter)\b"#), 3),
        (regex(#"\b(?:inkl|incl|including|inklusive)\b"#), 2),
        (regex(#"\b(?:ekskl|exkl|eks|excl|excluding)\b|før mva|before tax"#), -6),
        (regex(#"\b(?:subtotal|sub ?-?total|delsum|rabatt|discount|saldo|refund|refusjon|tilbakebetal\w*|credit|kreditt\w*|gebyr|fee|spar\w*|savings)\b|account balance"#), -20)
    ]

    /// Poengsum for en linje (små bokstaver). Over 0: ser ut som totalsum. Under -9: skal ikke brukes.
    private static func score(context: String) -> Int {
        let range = NSRange(context.startIndex..., in: context)
        var total = 0
        for (expression, weight) in scoreRules where expression.firstMatch(in: context, range: range) != nil {
            total += weight
        }
        // «MVA 25 % 21,80 kr» er ikke totalen, men «Totalt inkl. mva» er det.
        let hasTax = taxWords.firstMatch(in: context, range: range) != nil
        let hasTotal = totalWords.firstMatch(in: context, range: range) != nil
        let hasInclusive = inclusiveWords.firstMatch(in: context, range: range) != nil
        if hasTax, !hasTotal, !hasInclusive {
            total -= 20
        }
        return total
    }

    /// Sant for linjer som sier noe om beløp, intervall eller fornyelse. Brukes når teksten må kortes ned.
    static func mentionsMoneyOrDate(_ line: String) -> Bool {
        let lower = line.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        return !amounts(inLine: line).isEmpty
            || interval(in: line) != nil
            || score(context: lower) != 0
            || renewalKeywords.firstMatch(in: lower, range: range) != nil
    }

    /// Beløpene som har høyest poengsum og ikke er utelukket (delsum, mva, rabatt osv.), uten dubletter.
    /// Ett beløp betyr at det er totalen. Flere betyr at reglene ikke kan velge, og da er det bare disse
    /// modellen kan velge mellom.
    static func topAmounts(in text: String) -> [ReceiptAmount] {
        topCandidates(in: text).amounts
    }

    private static func topCandidates(in text: String) -> (amounts: [ReceiptAmount], leaders: [ReceiptAmountCandidate]) {
        let candidates = amountCandidates(in: text).filter { $0.score > -10 }
        guard let top = candidates.map(\.score).max() else { return ([], []) }

        var distinct: [ReceiptAmount] = []
        let leaders = candidates.filter { $0.score == top }
        for candidate in leaders where !distinct.contains(candidate.amount) {
            distinct.append(candidate.amount)
        }
        return (distinct, leaders)
    }

    /// Det mest sannsynlige totalbeløpet, eller nil hvis flere ulike beløp er like sannsynlige.
    static func bestAmount(in text: String) -> ReceiptAmount? {
        let amounts = topAmounts(in: text)
        return amounts.count == 1 ? amounts[0] : nil
    }

    /// Intervallet som står på samme linje som beløpet (eller på linjen foran, hvis beløpet står alene).
    private static func pairedInterval(for amount: ReceiptAmount, in text: String) -> BillingInterval? {
        let candidates = amountCandidates(in: text).filter { $0.amount == amount && $0.score > -10 }
        let leaders = topCandidates(in: text).leaders.filter { $0.amount == amount }
        for candidate in leaders + candidates {
            if let found = interval(in: candidate.context) { return found }
        }
        return nil
    }

    // MARK: - Intervall

    /// «a week», «a month» og «a year» teller bare rett etter et beløp («$9.99 a month»); ellers ville
    /// «a week before your trial ends» gitt ukentlig. «12 måneder» betyr årlig, men «12 måneders binding» gjør det ikke.
    private static let intervalRules: [(BillingInterval, NSRegularExpression)] = [
        (.weekly, regex(
            #"\b(?:ukentlig\w*|hver uke|hver 7\. dag|per uke|pr\.? uke|weekly|every week|each week|per week)\b|/ ?(?:uke|wk|week)\b|\d ?(?:kr|nok|usd|eur|gbp|sek|dkk|[€$£])? ?a week\b"#
        )),
        (.monthly, regex(
            #"\b(?:månedlig\w*|månedsabonnement\w*|månedspris\w*|hver måned|hver mnd\.?|hver md\.?|per måned|pr\.? måned|per mnd\.?|pr\.? mnd\.?|per md\.?|pr\.? md\.?|monthly|every month|each month|per month|per mo)\b|/ ?(?:måned|mnd|md|month|mo)\b|\d ?(?:kr|nok|usd|eur|gbp|sek|dkk|[€$£])? ?a month\b"#
        )),
        (.quarterly, regex(
            #"\b(?:kvartalsvis\w*|hvert kvartal|per kvartal|quarterly|each quarter|per quarter|every (?:3|three) months|every 3 mo|hver (?:3\.?|tredje) måned)\b|/ ?kvartal\b"#
        )),
        (.yearly, regex(
            #"\b(?:årlig\w*|årsabonnement\w*|årspris\w*|hvert år|per år|pr\.? år|annual|annually|yearly|every year|each year|per year)\b|/ ?(?:år|year|yr)\b|\d ?(?:kr|nok|usd|eur|gbp|sek|dkk|[€$£])? ?a year\b"#
        ))
    ]

    /// Intervallet kvitteringen sier, eller nil hvis den ikke sier noe eller sier flere ting.
    static func interval(in text: String) -> BillingInterval? {
        let found = intervalsMentioned(in: text)
        return found.count == 1 ? found[0] : nil
    }

    /// Alle intervaller teksten nevner, uten dubletter.
    static func intervalsMentioned(in text: String) -> [BillingInterval] {
        let lower = text.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        var found = intervalRules.filter { $0.1.firstMatch(in: lower, range: range) != nil }.map(\.0)
        if !found.contains(.yearly), mentionsTwelveMonthBilling(in: lower) {
            found.append(.yearly)
        }
        return found
    }

    /// «per 12 mnd», «(12 måneder)», «for 12 måneder», «billed 12 months». Teller ikke når «binding», «gratis»,
    /// «free», «garanti», «kampanje» (eller prøveperiode) står like før eller etter: «Bindingstid: 12 måneder» og
    /// «12 months free» sier ikke hvor ofte det trekkes.
    private static let twelveMonths = regex(
        #"(?:\bper|\bpr\.?|/|\(|\bfor|\bbilled) ?12 ?(?:måneder|mnd\.?|md\.?|months|mths)\b"#
    )
    private static let bindingWords = regex(#"binding|gratis|\bfree\b|garanti|kampanje|prøve|trial"#)

    private static func mentionsTwelveMonthBilling(in lower: String) -> Bool {
        let ns = lower as NSString
        for match in twelveMonths.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
            let start = max(0, match.range.location - 25)
            let end = min(ns.length, match.range.location + match.range.length + 30)
            let around = ns.substring(with: NSRange(location: start, length: end - start))
            if bindingWords.firstMatch(in: around, range: NSRange(location: 0, length: (around as NSString).length)) == nil {
                return true
            }
        }
        return false
    }

    // MARK: - Dato

    private static let renewalKeywords = regex(
        #"neste trekk|neste betaling|neste fornyelse|neste fakturadato|neste faktura|neste forfall|trekkes neste gang|\bfornyes\b|fornyelsesdato|\brenews\b|\bwill renew\b|auto-?renews|renewal date|next billing date|next billing|next payment(?: date)?|next charge|next renewal|your next bill"#
    )

    private static let monthNumbers: [String: Int] = {
        let names: [[String]] = [
            ["januar", "january", "jan"], ["februar", "february", "feb"], ["mars", "march", "mar"],
            ["april", "apr"], ["mai", "may"], ["juni", "june", "jun"], ["juli", "july", "jul"],
            ["august", "aug"], ["september", "sept", "sep"], ["oktober", "october", "okt", "oct"],
            ["november", "nov"], ["desember", "december", "des", "dec"]
        ]
        var map: [String: Int] = [:]
        for (index, spellings) in names.enumerated() {
            for spelling in spellings { map[spelling] = index + 1 }
        }
        return map
    }()

    private static let isoDate = regex(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#)
    private static let numericDate = regex(#"\b(\d{1,2})([./])(\d{1,2})\2(\d{4}|\d{2})\b"#)
    private static let dayMonthDate = regex(#"\b(\d{1,2})(?:st|nd|rd|th)?(?: of)?\.? ?([a-zæøå]{3,9})\.?(?:,? (\d{4}))?\b"#)
    private static let monthDayDate = regex(#"\b([a-zæøå]{3,9})\.? (\d{1,2})(?:st|nd|rd|th)?(?:,? (\d{4}))?\b"#)

    /// Datoen som står etter et fornyelsesord («neste trekk», «fornyes», «renews on», «next billing date»).
    /// Tall med punktum leses dag først (norsk). Med skråstrek leses dag først hvis det første tallet er over 12,
    /// måned først hvis det andre er det, og ellers står datoen tom. Uten årstall brukes neste forekomst fra `now`.
    static func renewalDate(in text: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let lower = text.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        for keyword in renewalKeywords.matches(in: lower, range: range) {
            guard let keywordRange = Range(keyword.range, in: lower) else { continue }
            var window = String(lower[keywordRange.upperBound...].prefix(80))
            if let blank = window.range(of: "\n\n") {
                window = String(window[..<blank.lowerBound])
            }
            window = window.replacingOccurrences(of: "\n", with: " ")
            if let date = firstDate(in: window, now: now, calendar: calendar) {
                return date
            }
        }
        return nil
    }

    private static func firstDate(in window: String, now: Date, calendar: Calendar) -> Date? {
        allDates(in: window, now: now, calendar: calendar).min { $0.location < $1.location }?.date
    }

    /// Alle datoer teksten sier utvetydig (se `renewalDate` for formatene), uten hensyn til fornyelsesord.
    /// Brukes til å sjekke at en dato fra modellen faktisk står i teksten.
    static func datesMentioned(in text: String, now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        allDates(in: text.lowercased().replacingOccurrences(of: "\n", with: " "), now: now, calendar: calendar).map(\.date)
    }

    /// Sant hvis teksten har et fornyelsesord («neste trekk», «fornyes», «renews», ...).
    static func hasRenewalPhrase(in text: String) -> Bool {
        let lower = text.lowercased()
        return renewalKeywords.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil
    }

    private static func allDates(in window: String, now: Date, calendar: Calendar) -> [(location: Int, date: Date)] {
        var found: [(location: Int, date: Date)] = []
        let range = NSRange(window.startIndex..., in: window)

        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            guard match.range(at: index).location != NSNotFound,
                  let r = Range(match.range(at: index), in: window) else { return nil }
            return String(window[r])
        }

        for match in isoDate.matches(in: window, range: range) {
            if let y = group(match, 1).flatMap({ Int($0) }),
               let m = group(match, 2).flatMap({ Int($0) }),
               let d = group(match, 3).flatMap({ Int($0) }),
               let date = makeDate(day: d, month: m, year: y, now: now, calendar: calendar) {
                found.append((match.range.location, date))
            }
        }

        for match in numericDate.matches(in: window, range: range) {
            guard let first = group(match, 1).flatMap({ Int($0) }),
                  let separator = group(match, 2),
                  let second = group(match, 3).flatMap({ Int($0) }),
                  let yearText = group(match, 4), var year = Int(yearText) else { continue }
            if yearText.count == 2 { year += 2000 }

            let day: Int, month: Int
            if separator == "." || first > 12 {
                day = first; month = second
            } else if second > 12 {
                day = second; month = first
            } else {
                continue
            }
            if let date = makeDate(day: day, month: month, year: year, now: now, calendar: calendar) {
                found.append((match.range.location, date))
            }
        }

        for match in dayMonthDate.matches(in: window, range: range) {
            guard let day = group(match, 1).flatMap({ Int($0) }),
                  let month = group(match, 2).flatMap({ monthNumbers[$0] }) else { continue }
            let year = group(match, 3).flatMap { Int($0) }
            if let date = makeDate(day: day, month: month, year: year, now: now, calendar: calendar) {
                found.append((match.range.location, date))
            }
        }

        for match in monthDayDate.matches(in: window, range: range) {
            guard let month = group(match, 1).flatMap({ monthNumbers[$0] }),
                  let day = group(match, 2).flatMap({ Int($0) }) else { continue }
            let year = group(match, 3).flatMap { Int($0) }
            if let date = makeDate(day: day, month: month, year: year, now: now, calendar: calendar) {
                found.append((match.range.location, date))
            }
        }

        return found
    }

    /// Kl. 12 på dagen (appen normaliserer datoer til kl. 12). nil for datoer som ikke finnes, f.eks. 31. februar.
    static func makeDate(day: Int, month: Int, year: Int?, now: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        func exact(_ year: Int) -> Date? {
            guard (2000...2100).contains(year),
                  let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
                  calendar.component(.day, from: date) == day,
                  calendar.component(.month, from: date) == month
            else { return nil }
            return date
        }

        if let year { return exact(year) }

        // Uten årstall: første forekomst som ikke er før i dag.
        let startOfToday = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: now)
        for candidateYear in [thisYear, thisYear + 1] {
            if let date = exact(candidateYear), date >= startOfToday { return date }
        }
        return nil
    }
}

// MARK: - Fra tolket kvittering til utkast

@MainActor
extension ReceiptFields {
    /// Utkastet skjemaet åpnes med. Beløpet på kvitteringen vinner over katalogprisen. Har kvitteringen intervall
    /// men ikke beløp, brukes katalogplanen med det intervallet, hvis den finnes. Ellers står feltene tomme.
    func draft(catalog: ServiceCatalog) -> SubscriptionDraft {
        let service = catalogServiceID.flatMap { catalog.service(id: $0) }
        var draft = service?.draft() ?? SubscriptionDraft(source: .receipt)
        draft.source = .receipt
        if let name { draft.name = name }
        if let nextRenewalDate { draft.nextRenewalDate = nextRenewalDate }

        if let price, let currencyCode {
            draft.price = price
            draft.currencyCode = currencyCode
            // Intervall fra kvitteringen, ellers fra en plan med omtrent samme beløp, ellers ingen.
            if let interval {
                draft.interval = interval
            } else if let plan = service?.plans.first(where: { Self.isClose(price, to: $0.price) && $0.currencyCode == currencyCode }) {
                draft.interval = plan.interval
            } else {
                draft.interval = nil
            }
        } else if let interval {
            if let plan = service?.plans.first(where: { $0.interval == interval }) {
                draft.price = plan.price
                draft.currencyCode = plan.currencyCode
                draft.interval = plan.interval
            } else {
                draft.price = nil
                draft.currencyCode = nil
                draft.interval = interval
            }
        }
        return draft
    }

    /// Innenfor ±10 %.
    private static func isClose(_ price: Decimal, to reference: Decimal) -> Bool {
        abs(price - reference) <= reference / 10
    }
}

extension ReceiptParser {
    /// Hele veien fra kvitteringstekst til utkast: regler, deretter (der den finnes) modellen på enheten, deretter
    /// utkast. Kalles av innboksen når appen blir aktiv. Kan avbrytes ved å avbryte oppgaven den kjører i.
    @MainActor
    static func draft(
        fromReceiptText text: String,
        catalog: ServiceCatalog? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> SubscriptionDraft {
        let catalog = catalog ?? ServiceCatalog.bundled
        let rules = parse(text, catalog: catalog, now: now, calendar: calendar)
        let fields = await ReceiptEnrichment.enrich(rules, text: text, catalog: catalog, now: now, calendar: calendar)
        return fields.draft(catalog: catalog)
    }
}
