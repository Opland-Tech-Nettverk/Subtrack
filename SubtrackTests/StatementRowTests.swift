import Foundation
import Testing
@testable import Subtrack

@MainActor
struct StatementRowTests {

    private var calendar: Calendar { BankStatementTestSupport.calendar }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        BankStatementTestSupport.day(year, month, day)
    }

    private func decimal(_ text: String) -> Decimal {
        BankStatementTestSupport.decimal(text)
    }

    private let dnb = StatementLayout(
        headerRowIndex: 0,
        dateColumn: 0,
        textColumn: 1,
        amount: .outgoingIncoming(outgoing: 3, incoming: 4),
        currencyColumn: nil
    )
    private let nordea = StatementLayout(
        headerRowIndex: 0,
        dateColumn: 0,
        textColumn: 5,
        amount: .single(column: 1),
        currencyColumn: 6
    )

    // MARK: - Datoer

    @Test(arguments: [
        ("14.10.2026", [2026, 10, 14]),
        ("2026-10-14", [2026, 10, 14]),
        ("2026/10/14", [2026, 10, 14]),
        ("14.10.26", [2026, 10, 14]),
        ("1.2.2026", [2026, 2, 1]),
        ("2026-10-14 08:12:33", [2026, 10, 14]),
        ("2026-10-14T08:12:33", [2026, 10, 14]),
        ("  14.10.2026  ", [2026, 10, 14])
    ])
    func parsesDates(text: String, expected: [Int]) {
        #expect(StatementValues.date(from: text, calendar: calendar) == day(expected[0], expected[1], expected[2]))
    }

    @Test(arguments: ["", "Reservert", "31.02.2026", "14.13.2026", "2026-10", "14.10", "abc", "1.2.3", "14/10/26", "0.0.2026"])
    func rejectsInvalidDates(text: String) {
        #expect(StatementValues.date(from: text, calendar: calendar) == nil)
    }

    @Test func datesAreAtNoon() {
        let date = StatementValues.date(from: "14.10.2026", calendar: calendar)!
        #expect(calendar.component(.hour, from: date) == 12)
    }

    // MARK: - Beløp

    @Test(arguments: [
        ("149,00", "149"),
        ("149", "149"),
        ("1 299,00", "1299"),
        ("1\u{00A0}299,00", "1299"),
        ("1\u{202F}299,00", "1299"),
        ("-149.00", "-149"),
        ("-1 299,50", "-1299.5"),
        ("1,234.50", "1234.5"),
        ("1.234,50", "1234.5"),
        ("149,00 NOK", "149"),
        ("NOK 149,00", "149"),
        ("149 kr", "149"),
        ("−20,00", "-20"),
        ("(50,00)", "-50"),
        ("149,00-", "-149"),
        ("1.299", "1299"),
        ("1.234.567", "1234567"),
        ("1,234,567", "1234567"),
        ("0.125", "0.125"),
        ("12,5", "12.5"),
        ("+500,00", "500"),
        ("20.00", "20")
    ])
    func parsesAmounts(text: String, expected: String) {
        #expect(StatementValues.amount(from: text) == decimal(expected))
    }

    @Test(arguments: ["", "Saldo", "abc", "-", ",", "Reservert", "149 abc"])
    func rejectsNonAmounts(text: String) {
        #expect(StatementValues.amount(from: text) == nil)
    }

    // MARK: - Rader

    @Test func outgoingColumnGivesAPositiveAmount() {
        let row = ["14.10.2026", "Netflix.com", "14.10.2026", "149,00", ""]
        let transaction = StatementRow.transaction(from: row, layout: dnb, calendar: calendar)
        #expect(transaction == StatementTransaction(date: day(2026, 10, 14), amount: 149, currencyCode: "NOK", text: "Netflix.com"))
    }

    @Test func signInTheOutColumnIsNotTrusted() {
        let row = ["14.10.2026", "Netflix.com", "14.10.2026", "-149,00", ""]
        #expect(StatementRow.transaction(from: row, layout: dnb, calendar: calendar)?.amount == 149)
    }

    @Test func incomingRowsAreSkipped() {
        let row = ["25.09.2026", "Lønn", "25.09.2026", "", "45 000,00"]
        #expect(StatementRow.transaction(from: row, layout: dnb, calendar: calendar) == nil)
    }

    @Test func singleColumnUsesNegativeForOutgoing() {
        let outgoing = ["2026/10/14", "-149,00", "", "", "", "Netflix.com", "NOK", "Kortkjøp"]
        let incoming = ["2026/09/25", "45000,00", "", "", "", "Lønn", "NOK", "Overføring"]
        #expect(StatementRow.transaction(from: outgoing, layout: nordea, calendar: calendar)?.amount == 149)
        #expect(StatementRow.transaction(from: incoming, layout: nordea, calendar: calendar) == nil)
    }

    @Test func reservedRowsAreSkipped() {
        let noDate = ["Reservert", "-89,00", "", "", "", "Kiosken", "NOK", "Kortkjøp"]
        let reservedMarker = ["2026/10/15", "-89,00", "", "", "", "Reservert", "NOK", "Kortkjøp"]
        #expect(StatementRow.transaction(from: noDate, layout: nordea, calendar: calendar) == nil)
        #expect(StatementRow.transaction(from: reservedMarker, layout: nordea, calendar: calendar) == nil)
    }

    @Test func footerAndBalanceRowsAreSkipped() {
        #expect(StatementRow.transaction(from: ["Sum utgående", "", "", "1 953,00"], layout: dnb, calendar: calendar) == nil)
        #expect(StatementRow.transaction(from: ["Utgående saldo", "", "", "", "12 345,67"], layout: dnb, calendar: calendar) == nil)
        #expect(StatementRow.transaction(from: [], layout: dnb, calendar: calendar) == nil)
    }

    @Test func rowsWithoutTextOrAmountAreSkipped() {
        #expect(StatementRow.transaction(from: ["14.10.2026", "", "", "149,00"], layout: dnb, calendar: calendar) == nil)
        #expect(StatementRow.transaction(from: ["14.10.2026", "Netflix", "", ""], layout: dnb, calendar: calendar) == nil)
        #expect(StatementRow.transaction(from: ["14.10.2026", "Netflix"], layout: dnb, calendar: calendar) == nil)
        #expect(StatementRow.transaction(from: ["14.10.2026", "Netflix", "", "0,00"], layout: dnb, calendar: calendar) == nil)
    }

    @Test func textLinesAndSpacesAreCollapsed() {
        let row = ["14.10.2026", "NETFLIX.COM\n  STOCKHOLM", "", "149,00"]
        #expect(StatementRow.transaction(from: row, layout: dnb, calendar: calendar)?.text == "NETFLIX.COM STOCKHOLM")
    }

    @Test func currencyComesFromTheCurrencyColumn() {
        let usd = ["2026/10/14", "-20,00", "", "", "", "Claude", "USD", ""]
        let unknown = ["2026/10/14", "-20,00", "", "", "", "Claude", "XXX", ""]
        let empty = ["2026/10/14", "-20,00", "", "", "", "Claude", "", ""]
        #expect(StatementRow.transaction(from: usd, layout: nordea, calendar: calendar)?.currencyCode == "USD")
        #expect(StatementRow.transaction(from: unknown, layout: nordea, calendar: calendar)?.currencyCode == "NOK")
        #expect(StatementRow.transaction(from: empty, layout: nordea, calendar: calendar)?.currencyCode == "NOK")
    }

    @Test(arguments: ["PENDING", "DECLINED", "REVERTED", "FAILED", "Pending", "Avvist", "Venter", "Cancelled"])
    func rowsThatAreNotCompletedAreSkipped(status: String) {
        let layout = StatementLayout(
            headerRowIndex: 0,
            dateColumn: 0,
            textColumn: 1,
            amount: .single(column: 2),
            currencyColumn: nil,
            statusColumn: 3
        )
        let row = ["2026-10-14", "Netflix", "-149.00", status]
        #expect(StatementRow.transaction(from: row, layout: layout, calendar: calendar) == nil)
    }

    @Test(arguments: ["COMPLETED", "Booked", "Bokført", ""])
    func completedRowsAndRowsWithoutStatusAreKept(status: String) {
        let layout = StatementLayout(
            headerRowIndex: 0,
            dateColumn: 0,
            textColumn: 1,
            amount: .single(column: 2),
            currencyColumn: nil,
            statusColumn: 3
        )
        let row = ["2026-10-14", "Netflix", "-149.00", status]
        #expect(StatementRow.transaction(from: row, layout: layout, calendar: calendar)?.amount == 149)
    }

    @Test func transactionsStartAfterTheHeaderRow() {
        let layout = StatementLayout(
            headerRowIndex: 1,
            dateColumn: 0,
            textColumn: 1,
            amount: .single(column: 2),
            currencyColumn: nil
        )
        let rows = [
            ["Kontoutskrift"],
            ["Dato", "Tekst", "Beløp"],
            ["14.10.2026", "Netflix", "-149,00"],
            ["15.10.2026", "Lønn", "100,00"],
            ["16.10.2026", "Spotify", "-139,00"]
        ]
        let transactions = StatementRow.transactions(in: rows, layout: layout, calendar: calendar)
        #expect(transactions.map(\.text) == ["Netflix", "Spotify"])
    }
}
