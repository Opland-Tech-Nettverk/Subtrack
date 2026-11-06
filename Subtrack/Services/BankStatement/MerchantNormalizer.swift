import Foundation

/// Mottakeren i en betaling, renset for det banken legger rundt navnet.
nonisolated struct NormalizedMerchant: Equatable {
    /// Små bokstaver uten kortprefiks, datoer, beløp og referansenumre. Lik nøkkel betyr samme mottaker.
    let key: String
    /// Navnet slik det kan vises, med originale bokstaver, f.eks. "Fitness24Seven".
    let displayName: String
    /// Beløpet i originalvaluta der teksten har det, f.eks. 20 fra "USD 20.00".
    let originalAmount: Decimal?
    let originalCurrency: String?
}

/// Renser teksten i en betaling: fjerner kortprefiks (`*1234 14.08 NOK 364.80 … Kurs: 1.0000`,
/// `Visa 100591`, `Varekjøp`, `Dato 12.09 kl. 10.47`, `Valutakurs:`) og henter ut beløpet i originalvaluta.
/// Selve rensingen deles med katalogoppslaget (`MerchantText`).
/// `nonisolated` fordi den er ren beregning uten tilknytning til brukergrensesnittet.
nonisolated enum MerchantNormalizer {
    static func normalize(_ text: String) -> NormalizedMerchant {
        let original = originalAmount(in: text)
        return NormalizedMerchant(
            key: key(for: text),
            displayName: displayName(for: text),
            originalAmount: original?.amount,
            originalCurrency: original?.currency
        )
    }

    /// Nøkkelen for gruppering: som `MerchantText.normalized`, men uten referanse-, KID- og
    /// kontonumre, som er ulike for hver betaling.
    static func key(for text: String) -> String {
        strippingReferences(MerchantText.normalized(text).split(separator: " ").map(String.init))
            .joined(separator: " ")
    }

    /// Ordene uten referanser. Det siste ordet i et navn tas aldri bort: består teksten bare av
    /// ord som ser ut som referanser («KID»), beholdes det siste av dem som har bokstaver.
    static func strippingReferences(_ tokens: [String]) -> [String] {
        let kept = tokens.filter { !isReferenceToken($0) }
        if kept.isEmpty, let fallback = tokens.last(where: { $0.contains { $0.isLetter } }) {
            return [fallback]
        }
        return kept
    }

    /// Om et ord ser ut som en referanse, KID eller et kontonummer og ikke som en del av navnet:
    /// ordene «ref» og «kid», tall på fem siffer eller mer (også med punktum, f.eks. «1234.56.78901»),
    /// og ord på minst seks tegn med minst tre siffer som skifter mellom bokstaver og siffer minst to
    /// ganger («p3a91b2c»). «Fitness24Seven», «Office365», «Bet365», «123inkt» og «Rema 1000» er navn.
    static func isReferenceToken(_ token: String) -> Bool {
        let word = token.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if ["ref", "kid", "kidnr", "fakt", "faktura", "fakturanr"].contains(word) {
            return true
        }
        let digits = token.filter { $0.isNumber }.count
        let letters = token.filter { $0.isLetter }.count
        if letters == 0 {
            return digits >= 5
        }
        return token.count >= 6 && digits >= 3 && letterDigitSwitches(in: token) >= 2
    }

    /// Hvor mange ganger ordet skifter mellom bokstav og siffer: «office365» 1, «p3a91b2c» 7.
    private static func letterDigitSwitches(in token: String) -> Int {
        var switches = 0
        var previous: Bool?
        for character in token {
            let isDigit: Bool
            if character.isNumber {
                isDigit = true
            } else if character.isLetter {
                isDigit = false
            } else {
                continue
            }
            if let previous, previous != isDigit { switches += 1 }
            previous = isDigit
        }
        return switches
    }

    /// Navnet til visning. Skrives bare med store bokstaver i banken, gjøres det om til «Stor forbokstav».
    /// Referanse-, KID- og kontonumre tas ikke med, siden navnet kan bli lagret.
    static func displayName(for text: String) -> String {
        let words = strippingReferences(
            MerchantText.cleaned(text)
                .split(separator: " ")
                .map(String.init)
                .filter { word in word.contains { $0.isLetter || $0.isNumber } }
        )
        let cleaned = words.joined(separator: " ")
        let letters = cleaned.filter { $0.isLetter }
        if !letters.isEmpty, letters == letters.uppercased() {
            return words
                .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
                .joined(separator: " ")
        }
        return cleaned
    }

    /// Valuta og beløp slik det står i teksten, i begge rekkefølger («USD 20.00», «25,00 EUR»).
    /// Første treff med valuta foran beløpet vinner, siden en dato («14.08») ellers ligner på et beløp.
    static func originalAmount(in text: String) -> (amount: Decimal, currency: String)? {
        let range = NSRange(text.startIndex..., in: text)
        for (expression, currencyGroup, amountGroup) in [(currencyFirst, 1, 2), (amountFirst, 2, 1)] {
            guard let match = expression.firstMatch(in: text, range: range),
                  let currencyRange = Range(match.range(at: currencyGroup), in: text),
                  let amountRange = Range(match.range(at: amountGroup), in: text),
                  let amount = StatementValues.amount(from: String(text[amountRange])),
                  amount > 0
            else { continue }
            return (amount, String(text[currencyRange]).uppercased())
        }
        return nil
    }

    private static let currencyAlternatives = CurrencyConverter.supportedCurrencies.joined(separator: "|")
    private static let amountPattern = #"\d+(?:[.,]\d+)*"#

    private static let currencyFirst: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b("# + currencyAlternatives + #")\s+("# + amountPattern + #")\b"#,
            options: [.caseInsensitive]
        )
    }()

    private static let amountFirst: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b("# + amountPattern + #")\s+("# + currencyAlternatives + #")\b"#,
            options: [.caseInsensitive]
        )
    }()
}
