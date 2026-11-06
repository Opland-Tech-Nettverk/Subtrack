import Foundation
import Testing
@testable import Subtrack

@MainActor
struct CSVTokenizerTests {

    // MARK: - Skilletegn

    @Test(arguments: [
        ("Dato;Forklaring;Ut fra konto\n01.01.2026;Netflix;149,00", ";"),
        ("Date,Description,Amount\n2026-01-01,Netflix,-149.00", ","),
        ("Dato\tTekst\tBeløp\n01.01.2026\tNetflix\t-149,00", "\t"),
        // Komma som desimaltegn teller ikke mot semikolon.
        ("Dato;Tekst;Beløp\n01.01.2026;A;1,5\n02.01.2026;B;2,5", ";"),
        // Skilletegn i anførselstegn teller ikke.
        ("Dato,Tekst,Beløp\n\"01;01;2026\",\"A;B;C\",\"-1,5\"", ",")
    ])
    func detectsTheDelimiter(text: String, expected: String) {
        #expect(CSVTokenizer.detectDelimiter(in: text) == Character(expected))
    }

    @Test func usesSemicolonWhenThereIsNoDelimiterAtAll() {
        #expect(CSVTokenizer.detectDelimiter(in: "bare tekst") == ";")
    }

    // MARK: - Felt og rader

    @Test func splitsRowsAndFields() {
        #expect(CSVTokenizer.parse("a;b;c\nd;e;f") == [["a", "b", "c"], ["d", "e", "f"]])
    }

    @Test func understandsQuotedFieldsWithDelimiters() {
        #expect(CSVTokenizer.parse(#""a;b";c"#, delimiter: ";") == [["a;b", "c"]])
    }

    @Test func understandsEscapedQuotes() {
        #expect(CSVTokenizer.parse(#""he said ""hi""";x"#, delimiter: ";") == [[#"he said "hi""#, "x"]])
    }

    @Test func keepsFieldsOverSeveralLinesInOneRow() {
        let rows = CSVTokenizer.parse("a;\"linje 1\nlinje 2\";c\nd;e;f")
        #expect(rows == [["a", "linje 1\nlinje 2", "c"], ["d", "e", "f"]])
    }

    @Test func dropsTrailingDelimiters() {
        #expect(CSVTokenizer.parse("a;b;c;\nd;e;f;") == [["a", "b", "c"], ["d", "e", "f"]])
        #expect(CSVTokenizer.parse("a;b;;;\nc;d;;;") == [["a", "b"], ["c", "d"]])
    }

    @Test func keepsEmptyFieldsInTheMiddle() {
        #expect(CSVTokenizer.parse("a;;c;d") == [["a", "", "c", "d"]])
    }

    @Test func skipsBlankRows() {
        #expect(CSVTokenizer.parse("a;b\n\n;;\nc;d\n") == [["a", "b"], ["c", "d"]])
    }

    @Test func trimsSpacesAroundFields() {
        #expect(CSVTokenizer.parse(" a ; b ;c", delimiter: ";") == [["a", "b", "c"]])
    }

    @Test func handlesAFinalRowWithoutLineBreak() {
        #expect(CSVTokenizer.parse("a;b\nc;d") == [["a", "b"], ["c", "d"]])
    }

    @Test func emptyTextGivesNoRows() {
        #expect(CSVTokenizer.parse("") == [])
        #expect(CSVTokenizer.parse("\n\n") == [])
    }

    @Test func quotedAmountsWithCommaDecimals() {
        let rows = CSVTokenizer.parse("Dato,Beløp\n14.10.2026,\"-1 299,00\"")
        #expect(rows == [["Dato", "Beløp"], ["14.10.2026", "-1 299,00"]])
    }

    @Test func parsesTheSpareBank1FixtureWithTrailingSemicolons() throws {
        let text = StatementDecoder.decode(try BankStatementTestSupport.fixtureData("sparebank1.csv"))
        let rows = CSVTokenizer.parse(text)
        #expect(rows.first == ["Dato", "Beskrivelse", "Rentedato", "Inn", "Ut", "Til konto", "Fra konto"])
        // Den tomme «Til konto» står midt i raden og beholdes.
        #expect(rows[1].count == 7)
    }

    @Test func parsesTheHandelsbankenFixtureWithFieldsOverSeveralLines() throws {
        let text = StatementDecoder.decode(try BankStatementTestSupport.fixtureData("handelsbanken-v2.csv"))
        let rows = CSVTokenizer.parse(text)
        let netflix = rows.first { $0.contains("NETFLIX.COM\nSTOCKHOLM") }
        #expect(netflix != nil)
        #expect(netflix?.first == "14.04.2026")
    }

    @Test func parsesTheCommaSeparatedRevolutFixture() throws {
        let text = StatementDecoder.decode(try BankStatementTestSupport.fixtureData("revolut.csv"))
        let rows = CSVTokenizer.parse(text)
        #expect(rows.first?.count == 10)
        #expect(rows.first?[2] == "Started Date")
    }
}
