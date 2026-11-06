import Foundation
import Testing
@testable import Subtrack

@MainActor
struct StatementLayoutTests {

    private func detectLayout(_ header: [String]) -> StatementLayout? {
        if case .success(let layout) = StatementLayout.detect(in: [header]) {
            return layout
        }
        return nil
    }

    // MARK: - Kjente oppbygninger

    @Test func dnbUsesOutAndInColumnsAndIgnoresInterestDate() {
        let layout = detectLayout(["Dato", "Forklaring", "Rentedato", "Ut fra konto", "Inn på konto"])
        #expect(layout == StatementLayout(
            headerRowIndex: 0,
            dateColumn: 0,
            textColumn: 1,
            amount: .outgoingIncoming(outgoing: 3, incoming: 4),
            currencyColumn: nil
        ))
    }

    @Test func spareBank1HasInAndOutColumns() {
        let layout = detectLayout(["Dato", "Beskrivelse", "Rentedato", "Inn", "Ut", "Til konto", "Fra konto"])
        #expect(layout?.dateColumn == 0)
        #expect(layout?.textColumn == 1)
        #expect(layout?.amount == .outgoingIncoming(outgoing: 4, incoming: 3))
    }

    @Test func nordeaHasOneAmountColumnAndCurrency() {
        let layout = detectLayout(["Bokføringsdato", "Beløp", "Avsender", "Mottaker", "Navn", "Tittel", "Valuta", "Betalingstype"])
        #expect(layout?.dateColumn == 0)
        #expect(layout?.textColumn == 5)
        #expect(layout?.amount == .single(column: 1))
        #expect(layout?.currencyColumn == 6)
    }

    @Test func handelsbankenV1() {
        let layout = detectLayout(["Bokført dato", "Utført dato", "Tekst", "Beløp inn", "Beløp ut"])
        #expect(layout?.dateColumn == 0)
        #expect(layout?.textColumn == 2)
        #expect(layout?.amount == .outgoingIncoming(outgoing: 4, incoming: 3))
    }

    @Test func handelsbankenV2PrefersTextAndBookedDate() {
        let layout = detectLayout(["Utført dato", "Bokført dato", "Tekst/KID", "Melding/KID/Fakt.nr", "Beløp inn", "Beløp ut", "Saldo"])
        #expect(layout?.dateColumn == 1)
        #expect(layout?.textColumn == 2)
        #expect(layout?.amount == .outgoingIncoming(outgoing: 5, incoming: 4))
    }

    @Test func revolut() {
        let layout = detectLayout(["Type", "Product", "Started Date", "Completed Date", "Description", "Amount", "Fee", "Currency", "State", "Balance"])
        #expect(layout?.dateColumn == 2)
        #expect(layout?.textColumn == 4)
        #expect(layout?.amount == .single(column: 5))
        #expect(layout?.currencyColumn == 7)
        #expect(layout?.statusColumn == 8)
    }

    @Test func statusColumnIsOptional() {
        #expect(detectLayout(["Dato", "Tekst", "Beløp"])?.statusColumn == nil)
        #expect(detectLayout(["Dato", "Tekst", "Beløp", "Status"])?.statusColumn == 3)
        #expect(detectLayout(["Dato", "Tekst", "Beløp", "State"])?.statusColumn == 3)
    }

    @Test func bulder() {
        let layout = detectLayout(["Dato", "Beskrivelse", "Beløp", "Saldo"])
        #expect(layout?.dateColumn == 0)
        #expect(layout?.textColumn == 1)
        #expect(layout?.amount == .single(column: 2))
    }

    @Test(arguments: [
        ["TransactionDate", "Text", "Amount"],
        ["Utført dato", "Melding/KID/Fakt.nr", "Beløp"],
        ["Bokført dato", "Tekst/KID", "Beløp ut"],
        ["Date", "Description", "Amount"],
        ["Dato", "Tittel", "Uttak"]
    ])
    func recognizesOtherHeaderNames(header: [String]) {
        #expect(detectLayout(header) != nil)
    }

    @Test func ignoresCaseAccentsAndExtraSpaces() {
        #expect(detectLayout(["  DATO ", "forklaring", "ut  fra   konto"]) != nil)
        #expect(detectLayout(["\u{FEFF}Dato", "Tekst", "Beløp"])?.dateColumn == 0)
    }

    @Test func outColumnIsEnoughWithoutAnInColumn() {
        let layout = detectLayout(["Dato", "Tekst", "Ut"])
        #expect(layout?.amount == .outgoingIncoming(outgoing: 2, incoming: nil))
    }

    // MARK: - Overskriftsraden

    @Test func findsTheHeaderRowAfterLinesAtTheTop() {
        let rows = [
            ["Kontoutskrift"],
            ["Konto 1234.56.78901"],
            ["Dato", "Tekst", "Beløp"],
            ["14.10.2026", "Netflix", "-149,00"]
        ]
        let result = StatementLayout.detect(in: rows)
        #expect(result == .success(StatementLayout(
            headerRowIndex: 2,
            dateColumn: 0,
            textColumn: 1,
            amount: .single(column: 2),
            currencyColumn: nil
        )))
    }

    // MARK: - Feil

    @Test func saysWhichColumnsAreMissing() {
        #expect(StatementLayout.detect(in: [["Dato", "Tekst"]]) == .failure(StatementLayoutError(missingColumns: ["beløp"])))
        #expect(StatementLayout.detect(in: [["Tekst", "Beløp"]]) == .failure(StatementLayoutError(missingColumns: ["dato"])))
        #expect(StatementLayout.detect(in: [["Dato", "Beløp"]])
            == .failure(StatementLayoutError(missingColumns: ["tekst (forklaring eller beskrivelse)"])))
    }

    @Test func listsAllColumnsWhenNothingIsRecognized() {
        let result = StatementLayout.detect(in: [["a", "b", "c"]])
        #expect(result == .failure(StatementLayoutError(missingColumns: ["dato", "tekst (forklaring eller beskrivelse)", "beløp"])))
    }

    @Test func interestDateAloneIsNotADate() {
        let result = StatementLayout.detect(in: [["Rentedato", "Tekst", "Beløp"]])
        #expect(result == .failure(StatementLayoutError(missingColumns: ["dato"])))
    }

    @Test func noRowsMeansAllColumnsAreMissing() {
        #expect(StatementLayout.detect(in: []) == .failure(
            StatementLayoutError(missingColumns: ["dato", "tekst (forklaring eller beskrivelse)", "beløp"])
        ))
    }

    // MARK: - Overskriftsnøkkel

    @Test func headerKey() {
        #expect(StatementLayout.headerKey("Bokføringsdato") == "bokforingsdato")
        #expect(StatementLayout.headerKey("  Inn  på konto ") == "inn pa konto")
        #expect(StatementLayout.headerKey("Beløp") == "belop")
        #expect(StatementLayout.headerKey("Tekst/KID") == "tekst/kid")
    }
}
