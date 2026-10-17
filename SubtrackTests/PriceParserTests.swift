import Foundation
import Testing
@testable import Subtrack

struct PriceParserTests {

    @Test(arguments: [
        ("149", Decimal(149)),
        ("149,90", Decimal(string: "149.90")!),
        ("149.90", Decimal(string: "149.90")!),
        ("0,5", Decimal(string: "0.5")!),
        ("1 000", Decimal(1000)),
        ("1\u{00A0}000", Decimal(1000)),
        ("1.234,50", Decimal(string: "1234.50")!),
        ("1,234.50", Decimal(string: "1234.50")!),
        ("12.345", Decimal(12345)),
        ("1.234.567", Decimal(1_234_567))
    ])
    func acceptsCommonFormats(input: String, expected: Decimal) {
        #expect(PriceParser.parse(input) == expected)
    }

    @Test(arguments: ["", " ", "12abc", "abc", "1,2,3", "12.34.56", ",5", "5,", "1,,5", "-5", "1234.567"])
    func rejectsAmbiguousOrInvalidInput(input: String) {
        #expect(PriceParser.parse(input) == nil)
    }
}
