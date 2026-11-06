import Foundation
import Testing
@testable import Subtrack

@MainActor
struct MerchantNormalizerTests {

    private func decimal(_ text: String) -> Decimal {
        BankStatementTestSupport.decimal(text)
    }

    // MARK: - Nøkkel

    @Test(arguments: [
        ("*1234 14.08 NOK 364.80 NETFLIX.COM Kurs: 1.0000", "netflix com"),
        ("*1234 21.04 USD 20.00 CLAUDE.AI SUBSCRIPTION Kurs: 10.0800", "claude ai subscription"),
        // Referansen «P3A91B2C» er ulik for hver betaling og tas ikke med.
        ("Visa 100591 Varekjøp SPOTIFY P3A91B2C", "spotify"),
        ("Telenor KID 123456789012 Ref 998877", "telenor"),
        ("Varekjøp REMA 1000 STORO Dato 12.09 kl. 10.47", "rema 1000 storo"),
        ("PAYPAL *SPOTIFY", "spotify"),
        ("Vipps*Kiosken", "kiosken"),
        ("GOOGLE YouTube 1234567", "google youtube"),
        ("Valutakurs: 9,8431 DROPBOX", "dropbox")
    ])
    func keyRemovesWhatTheBankAddsAroundTheName(text: String, expected: String) {
        #expect(MerchantNormalizer.key(for: text) == expected)
    }

    @Test func sameMerchantWithDifferentPrefixesGivesTheSameKey() {
        let a = MerchantNormalizer.key(for: "*1234 14.08 NOK 149.00 NETFLIX.COM Kurs: 1.0000")
        let b = MerchantNormalizer.key(for: "*1234 14.09 NOK 149.00 NETFLIX.COM Kurs: 1.0000")
        #expect(a == b)
        #expect(!a.isEmpty)
    }

    @Test func keyIsEmptyWhenOnlyNoiseIsLeft() {
        #expect(MerchantNormalizer.key(for: "*1234 14.08 NOK 149.00 Kurs: 1.0000").isEmpty)
    }

    // MARK: - Originalvaluta

    @Test(arguments: [
        ("*1234 21.04 USD 20.00 CLAUDE.AI SUBSCRIPTION Kurs: 10.0800", "20", "USD"),
        ("*1234 14.08 NOK 364.80 NETFLIX.COM Kurs: 1.0000", "364.80", "NOK"),
        ("Kjøp 25,00 EUR Dropbox", "25", "EUR"),
        ("Kortkjøp USD 20.00 Claude.ai Kurs 10,0800", "20", "USD"),
        ("*1234 14.08 usd 299,50 Shop", "299.50", "USD")
    ])
    func findsTheAmountInTheOriginalCurrency(text: String, amount: String, currency: String) {
        let merchant = MerchantNormalizer.normalize(text)
        #expect(merchant.originalAmount == decimal(amount))
        #expect(merchant.originalCurrency == currency)
    }

    @Test func hasNoOriginalAmountWhenTheTextHasNone() {
        let merchant = MerchantNormalizer.normalize("Varekjøp REMA 1000 STORO Dato 12.09 kl. 10.47")
        #expect(merchant.originalAmount == nil)
        #expect(merchant.originalCurrency == nil)
    }

    // MARK: - Visningsnavn

    @Test(arguments: [
        ("NETFLIX.COM", "Netflix.com"),
        ("CLAUDE.AI SUBSCRIPTION", "Claude.ai Subscription"),
        ("*1234 14.08 NOK 449.00 Fitness24Seven Kurs: 1.0000", "Fitness24Seven"),
        ("Kari Nordmann", "Kari Nordmann"),
        ("Visa 100591 Varekjøp Ålesund Treningssenter", "Ålesund Treningssenter"),
        ("GOOGLE YouTube 1234567", "GOOGLE YouTube"),
        ("Telenor Ref 1234567890", "Telenor"),
        ("TELENOR KID 123456789012", "Telenor"),
        ("Husleie 1234.56.78901", "Husleie"),
        ("*1234 Fitness24Seven AB 12345", "Fitness24Seven AB")
    ])
    func displayNameKeepsLettersAndCapitalizesShoutingText(text: String, expected: String) {
        #expect(MerchantNormalizer.displayName(for: text) == expected)
    }

    // MARK: - Referanser

    @Test(arguments: [
        ("p3a91b2c", true), ("1234567", true), ("12345", true), ("1234.56.78901", true), ("1a2b3c", true),
        ("ref", true), ("KID", true), ("Ref:", true), ("kidnr", true),
        ("Fitness24Seven", false), ("1000", false), ("365", false), ("Netflix", false), ("Claude.ai", false),
        ("24seven", false), ("b2b", false)
    ])
    func recognizesReferenceTokens(token: String, expected: Bool) {
        #expect(MerchantNormalizer.isReferenceToken(token) == expected)
    }
}
