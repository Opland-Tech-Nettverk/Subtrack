import Foundation
import Testing
@testable import Subtrack

@MainActor
struct StatementDecoderTests {

    @Test func decodesPlainUTF8() {
        let data = Data("Dato;Forklaring;Beløp ÆØÅ".utf8)
        #expect(StatementDecoder.decode(data) == "Dato;Forklaring;Beløp ÆØÅ")
    }

    @Test func removesUTF8ByteOrderMark() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("Dato;Beløp".utf8)
        let text = StatementDecoder.decode(data)
        #expect(text == "Dato;Beløp")
        #expect(!text.hasPrefix("\u{FEFF}"))
    }

    @Test func fallsBackToISO8859ForNorwegianLetters() {
        let original = "Varekjøp Ålesund æøå"
        let data = original.data(using: .isoLatin1)!
        // Bytene er ikke gyldig UTF-8, så avkodingen må bruke den eldre kodingen.
        #expect(String(data: data, encoding: .utf8) == nil)
        #expect(StatementDecoder.decode(data) == original)
    }

    @Test func decodesWindows1252CharactersThatISO8859LacksAsLatin1() {
        // Eurotegnet er 0x80 i Windows-1252.
        let original = "Betaling 12 € Kurs"
        let data = original.data(using: .windowsCP1252)!
        #expect(StatementDecoder.decode(data) == original)
    }

    @Test func decodesUTF16WithByteOrderMark() {
        let data = Data([0xFF, 0xFE]) + "Dato;Beløp".data(using: .utf16LittleEndian)!
        #expect(StatementDecoder.decode(data) == "Dato;Beløp")
    }

    @Test func normalizesAllLineBreaksToNewline() {
        let data = Data("a\r\nb\rc\nd".utf8)
        #expect(StatementDecoder.decode(data) == "a\nb\nc\nd")
    }

    @Test func emptyDataGivesEmptyText() {
        #expect(StatementDecoder.decode(Data()) == "")
    }

    @Test func decodesTheDNBFixtureWithByteOrderMarkAndWindowsLineBreaks() throws {
        let text = StatementDecoder.decode(try BankStatementTestSupport.fixtureData("dnb.txt"))
        #expect(text.hasPrefix("Dato;Forklaring;Rentedato;Ut fra konto;Inn på konto\n"))
        #expect(!text.contains("\r"))
    }

    @Test func decodesTheISO8859FixtureWithNorwegianLetters() throws {
        let text = StatementDecoder.decode(try BankStatementTestSupport.fixtureData("handelsbanken-v2.csv"))
        #expect(text.contains("Utført dato;Bokført dato;Tekst/KID;Melding/KID/Fakt.nr;Beløp inn;Beløp ut;Saldo"))
    }
}
