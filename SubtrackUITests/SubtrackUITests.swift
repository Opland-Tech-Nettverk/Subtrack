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

    private func row(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["subscription.\(name)"].firstMatch
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

        // Avslutt: flyttes til arkivet.
        row(named: "Netflix").swipeLeft()
        app.buttons["Avslutt"].tap()
        XCTAssertFalse(row(named: "Netflix").waitForExistence(timeout: 2))

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
}
