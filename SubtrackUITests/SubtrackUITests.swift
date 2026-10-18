import XCTest

/// Tester hovedflytene slik en bruker opplever dem. Appen startes med `-UITesting`,
/// så hver test begynner med en tom database i minnet uten iCloud og uten varseldialog.
final class SubtrackUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.opland.subtrack")
        // "-sortOrder renewal" overstyrer @AppStorage-verdien, så sorteringen er forutsigbar.
        app.launchArguments = ["-UITesting", "-sortOrder", "renewal"]
        app.launch()
    }

    // MARK: - Hjelpere

    private func addSubscription(name: String, price: String) {
        app.buttons["Legg til"].tap()

        let nameField = app.textFields["Navn"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        let priceField = app.textFields["Pris"]
        priceField.tap()
        priceField.typeText(price)

        app.buttons["Lagre"].tap()
        XCTAssertTrue(row(named: name).waitForExistence(timeout: 5), "\(name) skulle vært i listen etter lagring")
    }

    /// Raden er en knapp, men søket går på identifikatoren uansett elementtype,
    /// så det tåler at SwiftUI eksponerer den som knapp eller celle.
    private func row(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["subscription.\(name)"].firstMatch
    }

    /// Angre-knappen i banneret som vises en liten stund etter at et abonnement er avsluttet.
    private var undoArchiveButton: XCUIElement {
        app.buttons["undoArchive"]
    }

    /// Venter til elementet er borte. `waitForExistence` svarer med en gang om det fortsatt
    /// finnes, så det egner seg ikke til å vente på at noe forsvinner.
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Tester

    @MainActor
    func testShowsEmptyStateOnFirstLaunch() {
        XCTAssertTrue(app.staticTexts["Ingen abonnementer ennå"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddingASubscriptionShowsItInTheListAndSummary() {
        addSubscription(name: "Netflix", price: "149")

        let summary = app.descendants(matching: .any)["summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("149"), "Sammendraget skulle vist 149: \(summary.label)")
    }

    @MainActor
    func testSaveIsDisabledUntilNameAndValidPriceAreEntered() {
        app.buttons["Legg til"].tap()
        let save = app.buttons["Lagre"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)

        let nameField = app.textFields["Navn"]
        nameField.tap()
        nameField.typeText("Spotify")
        let priceField = app.textFields["Pris"]
        priceField.tap()
        priceField.typeText("1,2,3")

        XCTAssertTrue(app.staticTexts["Skriv inn en gyldig pris, f.eks. 149,90"].exists)
        XCTAssertFalse(save.isEnabled)

        // Skjemaet har endringer, så Avbryt må bekreftes før de forkastes.
        app.buttons["Avbryt"].tap()
        let discard = app.buttons["Forkast endringer"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.staticTexts["Ingen abonnementer ennå"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testArchivingAndRestoringASubscription() {
        addSubscription(name: "Netflix", price: "149")

        // Avslutt: flyttes til arkivet. Full sveip er slått av, så knappen må trykkes.
        row(named: "Netflix").swipeLeft()
        app.buttons["Avslutt"].tap()
        // Banneret sjekkes først, siden det forsvinner av seg selv etter noen sekunder.
        XCTAssertTrue(undoArchiveButton.waitForExistence(timeout: 2), "Angre-banneret skulle vist seg etter avslutt")
        XCTAssertTrue(waitForDisappearance(of: row(named: "Netflix")))

        let archiveLink = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Avsluttede'")).firstMatch
        XCTAssertTrue(archiveLink.waitForExistence(timeout: 5))
        archiveLink.tap()

        // Gjenoppta fra arkivet.
        let archivedRow = app.cells.containing(NSPredicate(format: "label CONTAINS 'Netflix'")).firstMatch
        XCTAssertTrue(archivedRow.waitForExistence(timeout: 5))
        archivedRow.swipeRight()
        app.buttons["Gjenoppta"].tap()
        XCTAssertTrue(app.staticTexts["Ingen avsluttede abonnement"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row(named: "Netflix").waitForExistence(timeout: 5))
        XCTAssertFalse(archiveLink.exists)
        // Abonnementet er ikke lenger avsluttet, så det er ingenting å angre.
        XCTAssertFalse(undoArchiveButton.exists)
    }

    @MainActor
    func testArchivingFromContextMenuCanBeUndone() {
        addSubscription(name: "Netflix", price: "149")

        // Hold inne raden for å få opp menyen, og avslutt derfra.
        row(named: "Netflix").press(forDuration: 1.0)
        let archiveItem = app.buttons["Avslutt"]
        XCTAssertTrue(archiveItem.waitForExistence(timeout: 5))
        archiveItem.tap()

        // Angre i banneret før det forsvinner av seg selv: raden er tilbake, og ingenting
        // ligger i arkivet. Banneret vises bare mens abonnementet er avsluttet.
        XCTAssertTrue(undoArchiveButton.waitForExistence(timeout: 2), "Angre-banneret skulle vist seg etter avslutt")
        undoArchiveButton.tap()
        XCTAssertTrue(row(named: "Netflix").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDisappearance(of: undoArchiveButton))
        let archiveLink = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Avsluttede'")).firstMatch
        XCTAssertTrue(waitForDisappearance(of: archiveLink))
    }

    @MainActor
    func testSearchFiltersTheList() {
        addSubscription(name: "Netflix", price: "149")
        addSubscription(name: "Spotify", price: "129")

        // Søkefeltet ligger skjult over listen til man drar ned.
        app.swipeDown()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("spo")

        XCTAssertTrue(row(named: "Spotify").waitForExistence(timeout: 5))
        XCTAssertFalse(row(named: "Netflix").exists)
    }

    @MainActor
    func testStatisticsTabShowsCategoryCosts() {
        addSubscription(name: "Netflix", price: "149")

        app.buttons["Statistikk"].tap()
        XCTAssertTrue(app.staticTexts["Kostnad per kategori"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dyreste abonnement"].exists)
    }

    @MainActor
    func testStatisticsEmptyStateLeadsToOverview() {
        app.buttons["Statistikk"].tap()
        let goToOverview = app.buttons["Gå til Oversikt"]
        XCTAssertTrue(goToOverview.waitForExistence(timeout: 5))

        goToOverview.tap()
        XCTAssertTrue(waitForDisappearance(of: goToOverview))
        XCTAssertTrue(app.navigationBars["Subtrack"].waitForExistence(timeout: 5))
    }
}
