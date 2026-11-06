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

    /// Nøkkelen for gruppering: som `MerchantText.normalized`, men uten lange tall (referanse- og
    /// kortnumre på fem siffer eller mer), som er ulike for hver betaling.
    static func key(for text: String) -> String {
        MerchantText.normalized(text)
            .split(separator: " ")
            .filter { token in !(token.count >= 5 && token.allSatisfy { $0.isNumber }) }
            .joined(separator: " ")
    }

    /// Navnet til visning. Skrives bare med store bokstaver i banken, gjøres det om til «Stor forbokstav».
    static func displayName(for text: String) -> String {
        let cleaned = MerchantText.cleaned(text)
        let letters = cleaned.filter { $0.isLetter }
        if !letters.isEmpty, letters == letters.uppercased() {
            return cleaned
                .split(separator: " ")
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
