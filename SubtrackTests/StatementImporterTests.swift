import Foundation
import Testing
@testable import Subtrack

/// En testfil og det Claude-trekket den skal gi. Resten av innholdet er likt i alle filene:
/// Netflix 149 kr hver 14., Spotify 139 kr hver 3. og Claude USD 20 hver 21. i måneden,
/// 35 dagligvarekjøp og 4 Vipps-betalinger uten rytme, og lønn som innbetaling.
struct StatementFixtureCase: Sendable, CustomTestStringConvertible {
    let fileName: String
    /// «20» når filen har USD-beløpet (DNB, SpareBank 1 og Revolut), ellers siste kronebeløp.
    let claudePrice: String
    let claudeCurrency: String
    var testDescription: String { fileName }
}

let statementFixtureCases: [StatementFixtureCase] = [
    StatementFixtureCase(fileName: "dnb.txt", claudePrice: "20", claudeCurrency: "USD"),
    StatementFixtureCase(fileName: "sparebank1.csv", claudePrice: "20", claudeCurrency: "USD"),
    StatementFixtureCase(fileName: "nordea.csv", claudePrice: "206.20", claudeCurrency: "NOK"),
    StatementFixtureCase(fileName: "handelsbanken-v1.csv", claudePrice: "206.20", claudeCurrency: "NOK"),
    StatementFixtureCase(fileName: "handelsbanken-v2.csv", claudePrice: "206.20", claudeCurrency: "NOK"),
    StatementFixtureCase(fileName: "bulder.csv", claudePrice: "206.20", claudeCurrency: "NOK"),
    StatementFixtureCase(fileName: "revolut.csv", claudePrice: "20", claudeCurrency: "USD")
]

@MainActor
struct StatementImporterTests {

    private typealias Support = BankStatementTestSupport

    private func analyze(_ fileName: String, existing: [String] = []) throws -> StatementAnalysis {
        try StatementImporter.analyze(
            data: try Support.fixtureData(fileName),
            catalog: Support.catalog,
            existingNames: existing,
            now: Support.now,
            calendar: Support.calendar
        )
    }

    // MARK: - Testfilene

    @Test(arguments: statementFixtureCases)
    func readsEveryOutgoingPaymentAndNothingElse(fixture: StatementFixtureCase) throws {
        let analysis = try analyze(fixture.fileName)
        // 7 + 6 + 6 + 35 + 4. Lønn, reservasjoner, bunnlinjer og saldo er ikke med.
        #expect(analysis.transactionCount == 58)
        #expect(analysis.periodStart == Support.day(2026, 4, 2))
        #expect(analysis.periodEnd == Support.day(2026, 10, 14))
        #expect(analysis.periodDays == 195)
        #expect(!analysis.isShortPeriod)
    }

    @Test(arguments: statementFixtureCases)
    func findsTheThreeSubscriptionsAndNothingElse(fixture: StatementFixtureCase) throws {
        let analysis = try analyze(fixture.fileName)
        #expect(Set(analysis.suggestions.map(\.name)) == ["Netflix", "Spotify", "Claude"])
        #expect(analysis.suggestions.count == 3)
        #expect(analysis.suggestions.allSatisfy { $0.confidence == .high && $0.interval == .monthly })
    }

    @Test(arguments: statementFixtureCases)
    func suggestionsHaveTheRightPriceAndDates(fixture: StatementFixtureCase) throws {
        let analysis = try analyze(fixture.fileName)
        let byName = Dictionary(uniqueKeysWithValues: analysis.suggestions.map { ($0.name, $0) })

        let netflix = try #require(byName["Netflix"])
        #expect(netflix.price == 149)
        #expect(netflix.currencyCode == "NOK")
        #expect(netflix.chargeCount == 7)
        #expect(netflix.lastChargeDate == Support.day(2026, 10, 14))
        #expect(netflix.nextExpectedDate == Support.day(2026, 11, 14))

        let spotify = try #require(byName["Spotify"])
        #expect(spotify.price == 139)
        #expect(spotify.currencyCode == "NOK")
        #expect(spotify.chargeCount == 6)
        #expect(spotify.lastChargeDate == Support.day(2026, 10, 3))

        let claude = try #require(byName["Claude"])
        #expect(claude.price == Support.decimal(fixture.claudePrice))
        #expect(claude.currencyCode == fixture.claudeCurrency)
        #expect(claude.chargeCount == 6)
        #expect(claude.lastChargeDate == Support.day(2026, 9, 21))
    }

    @Test(arguments: statementFixtureCases)
    func existingSubscriptionsAreLeftOut(fixture: StatementFixtureCase) throws {
        let analysis = try analyze(fixture.fileName, existing: ["Netflix", "Claude.ai"])
        #expect(analysis.suggestions.map(\.name) == ["Spotify"])
        // Det som ble lest, påvirkes ikke.
        #expect(analysis.transactionCount == 58)
    }

    @Test func encodingAndLayoutOfEveryBankAreRecognizedFromTheFileAlone() throws {
        let expected: [String: StatementLayout.Amount] = [
            "dnb.txt": .outgoingIncoming(outgoing: 3, incoming: 4),
            "sparebank1.csv": .outgoingIncoming(outgoing: 4, incoming: 3),
            "nordea.csv": .single(column: 1),
            "handelsbanken-v1.csv": .outgoingIncoming(outgoing: 4, incoming: 3),
            "handelsbanken-v2.csv": .outgoingIncoming(outgoing: 5, incoming: 4),
            "bulder.csv": .single(column: 2),
            "revolut.csv": .single(column: 5)
        ]
        for (fileName, amount) in expected {
            let rows = CSVTokenizer.parse(StatementDecoder.decode(try Support.fixtureData(fileName)))
            guard case .success(let layout) = StatementLayout.detect(in: rows) else {
                Issue.record("Fant ikke kolonnene i \(fileName)")
                continue
            }
            #expect(layout.amount == amount, "\(fileName)")
        }
    }

    @Test func revolutRowsThatAreDeclinedRevertedOrPendingAreIgnored() throws {
        let text = StatementDecoder.decode(try Support.fixtureData("revolut.csv"))
        for state in ["DECLINED", "REVERTED", "PENDING"] {
            #expect(text.contains(",\(state),"), "\(state) mangler i testfilen")
        }
        let analysis = try analyze("revolut.csv")
        // Netflix 7 og Spotify 6 trekk: de tre ikke gjennomførte radene er ikke med, og rytmen er hel.
        #expect(analysis.transactionCount == 58)
        #expect(analysis.periodEnd == Support.day(2026, 10, 14))
        let byName = Dictionary(uniqueKeysWithValues: analysis.suggestions.map { ($0.name, $0) })
        #expect(byName["Netflix"]?.chargeCount == 7)
        #expect(byName["Spotify"]?.chargeCount == 6)
    }

    @Test func theAnalysisCanRunOffTheMainActor() async throws {
        let data = try Support.fixtureData("dnb.txt")
        let catalog = Support.catalog
        let now = Support.now
        let calendar = Support.calendar
        let analysis = try await Task.detached { () throws -> StatementAnalysis in
            #expect(!Thread.current.isMainThread)
            return try StatementImporter.analyze(
                data: data,
                catalog: catalog,
                existingNames: [],
                now: now,
                calendar: calendar
            )
        }.value
        #expect(analysis.transactionCount == 58)
        #expect(analysis.suggestions.count == 3)
    }

    @Test func aLargeStatementIsReadInOnePass() throws {
        var lines = ["Dato;Tekst;Beløp"]
        for index in 0..<3000 {
            let day = 1 + index % 28
            let month = 1 + (index / 28) % 12
            lines.append(String(format: "%02d.%02d.2026;Varekjøp BUTIKK %d Dato 12.09 kl. 10.47;-%d,50", day, month, index % 40, 100 + index % 300))
        }
        for month in 1...12 {
            lines.append(String(format: "14.%02d.2026;*1234 14.%02d NOK 149.00 NETFLIX.COM Kurs: 1.0000;-149,00", month, month))
        }
        let data = Data(lines.joined(separator: "\n").utf8)
        let analysis = try StatementImporter.analyze(
            data: data,
            catalog: Support.catalog,
            now: Support.now,
            calendar: Support.calendar
        )
        #expect(analysis.transactionCount == 3012)
        #expect(analysis.suggestions.contains { $0.name == "Netflix" && $0.chargeCount == 12 })
    }

    // MARK: - Feil og grensetilfeller

    @Test func throwsWhenTheFileIsEmpty() {
        #expect(throws: StatementImportError.unreadable) {
            try StatementImporter.analyze(data: Data(), catalog: Support.catalog)
        }
    }

    @Test func saysWhichColumnsAreMissing() {
        let data = Data("Dato;Tekst\n14.10.2026;Netflix".utf8)
        #expect(throws: StatementImportError.missingColumns(["beløp"])) {
            try StatementImporter.analyze(data: data, catalog: Support.catalog)
        }
    }

    @Test func throwsWhenThereAreColumnsButNoPayments() {
        let data = Data("Dato;Tekst;Beløp\n14.10.2026;Lønn;45000,00\nSum;;45000,00".utf8)
        #expect(throws: StatementImportError.noTransactions) {
            try StatementImporter.analyze(data: data, catalog: Support.catalog)
        }
    }

    @Test func aShortPeriodIsFlaggedAndFindsNothing() throws {
        let data = Data("""
        Dato;Tekst;Beløp
        01.10.2026;Netflix.com;-149,00
        14.10.2026;REMA 1000;-312,50
        """.utf8)
        let analysis = try StatementImporter.analyze(
            data: data,
            catalog: Support.catalog,
            now: Support.now,
            calendar: Support.calendar
        )
        #expect(analysis.transactionCount == 2)
        #expect(analysis.periodDays == 13)
        #expect(analysis.isShortPeriod)
        #expect(analysis.suggestions.isEmpty)
    }

    @Test func aPeriodOfTwoMonthsIsNotShort() throws {
        let data = Data("""
        Dato;Tekst;Beløp
        01.08.2026;Kiosken;-10,00
        01.10.2026;Kiosken;-10,00
        """.utf8)
        let analysis = try StatementImporter.analyze(data: data, catalog: Support.catalog, calendar: Support.calendar)
        #expect(analysis.periodDays == 61)
        #expect(!analysis.isShortPeriod)
    }
}
