import Foundation

/// Tolker priser slik folk faktisk skriver dem, og avviser alt annet i stedet for å gjette.
///
/// Regler:
/// - Mellomrom ignoreres ("1 000").
/// - Siste komma eller punktum er desimalskilletegn hvis det følges av 1–2 siffer.
/// - Øvrige skilletegn er tusenskilletegn og må stå foran grupper på nøyaktig 3 siffer
///   ("1.234,50", "1,234.50", "12.345").
/// - Alt annet, f.eks. bokstaver eller "1,2,3", gir `nil`.
enum PriceParser {
    static func parse(_ input: String) -> Decimal? {
        let cleaned = input.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty,
              cleaned.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "," || $0 == "." })
        else { return nil }

        var groups = cleaned
            .split(omittingEmptySubsequences: false) { $0 == "," || $0 == "." }
            .map(String.init)
        guard groups.allSatisfy({ !$0.isEmpty }) else { return nil }

        var fraction = ""
        if groups.count > 1, let last = groups.last, last.count <= 2 {
            fraction = last
            groups.removeLast()
        }

        if groups.count > 1 {
            guard groups[0].count <= 3, groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }

        let normalized = groups.joined() + (fraction.isEmpty ? "" : "." + fraction)
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
