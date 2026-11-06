import XCTest

/// Tester hovedflytene slik en bruker opplever dem. Appen startes med `-UITesting`,
/// så hver test begynner med en tom database i minnet uten iCloud og uten varseldialog.
final class SubtrackUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.opland.subtrack")
        // "-sortOrder renewal" overstyrer @AppStorage-verdien, så sorteringen er forutsigbar.
        // "-UITestingNoAnimations" slår av UIKit-animasjoner i appen, så den lettere regnes som
        // rolig mens pluss-menyen er åpen (iOS 27 melder ellers ikke ferdig animasjon på 60 sekunder).
        app.launchArguments = ["-UITesting", "-UITestingNoAnimations", "-sortOrder", "renewal"]
        app.launch()
    }

    // MARK: - Hjelpere

    /// Åpner skjemaet for et nytt abonnement. Uten abonnement i listen går det direkte via kortet
    /// i den tomme tilstanden, uten pluss-menyen. Ellers er «Legg til» en meny med «Legg til selv»
    /// og «Importer fra kontoutskrift». Testene som må gjennom menyen, får lengre tid.
    private func openAddForm() {
        let card = app.buttons["onboarding.add"]
        if card.waitForExistence(timeout: 2) {
            card.tap()
            return
        }
        app.buttons["Legg til"].tap()
        let manual = app.buttons["Legg til selv"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
    }

    private func addSubscription(name: String, price: String) {
        openAddForm()

        let nameField = app.textFields["Navn"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        // Navn som finnes i katalogen (f.eks. "Netflix") gir en forslagsrad mellom Navn og Pris.
        // Raden trykkes ikke, så navnet endres ikke. Pris finnes på merkelappen og ikke på
        // posisjonen, og XCUITest ruller til feltet om det skulle havne utenfor skjermen.
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
    func testEmptyStateOffersTheThreeEntryPoints() {
        XCTAssertTrue(app.buttons["onboarding.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.importStatement"].exists)
        XCTAssertTrue(app.buttons["onboarding.shareReceipt"].exists)
    }

    @MainActor
    func testAddMenuOffersStatementImport() {
        // Pluss-menyen holder appen opptatt lenge på iOS 27; se `openAddForm`.
        executionTimeAllowance = 600
        app.buttons["Legg til"].tap()
        let importItem = app.buttons["Importer fra kontoutskrift"]
        XCTAssertTrue(importItem.waitForExistence(timeout: 5))
        importItem.tap()
        XCTAssertTrue(app.buttons["importChooseFile"].waitForExistence(timeout: 5), "Forklaringen skulle vært åpnet")
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
        openAddForm()
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
    func testCatalogSuggestionFillsTheForm() {
        openAddForm()

        let nameField = app.textFields["Navn"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("netf")

        let suggestion = app.buttons["catalogSuggestion.netflix"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "Netflix skulle vært foreslått fra katalogen")
        suggestion.tap()

        XCTAssertEqual(nameField.value as? String, "Netflix")
        // Et tomt felt viser plassholderen "Pris" som verdi, så sjekk at det står et tall der.
        let priceValue = app.textFields["Pris"].value as? String ?? ""
        XCTAssertTrue(priceValue.contains(where: \.isNumber), "Prisen skulle vært fylt ut: \(priceValue)")
        // Forslaget skjules når navnet er fylt ut.
        XCTAssertTrue(waitForDisappearance(of: suggestion))

        app.buttons["Lagre"].tap()
        XCTAssertTrue(row(named: "Netflix").waitForExistence(timeout: 5), "Netflix skulle vært i listen etter lagring")
    }

    @MainActor
    func testShortcutDraftOpensPrefilledForm() {
        // Starter appen på nytt som om snarveien «Legg til abonnement» ble kjørt med navnet
        // "netflix". Navnet finnes i katalogen, så skjemaet får katalognavnet og prisen derfra.
        app.terminate()
        app.launchArguments += ["-UITestingShortcutDraft", "netflix"]
        app.launch()

        let nameField = app.textFields["Navn"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Skjemaet skulle vært åpnet med utkastet fra snarveien")
        XCTAssertEqual(nameField.value as? String, "Netflix")
        // Prisen fra katalogens første plan (Standard). Et tomt felt ville vist plassholderen
        // "Pris" som verdi, så en lik sammenligning fanger også det.
        XCTAssertEqual(app.textFields["Pris"].value as? String, "149")

        app.buttons["Lagre"].tap()
        XCTAssertTrue(row(named: "Netflix").waitForExistence(timeout: 5), "Netflix skulle vært i listen etter lagring")
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
    func testArchivingFromTheFormOnTheDetailPageKeepsTheUndoBanner() {
        addSubscription(name: "Netflix", price: "149")

        // Detaljsiden, så Rediger, så Avslutt abonnement og bekreftelsen.
        row(named: "Netflix").tap()
        let edit = app.buttons["Rediger"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        // Knappen ligger nederst i skjemaet og finnes ikke i hierarkiet før det er rullet dit.
        let archive = app.buttons["Avslutt abonnement"]
        for _ in 0..<6 where !archive.exists || !archive.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        let confirm = app.alerts.buttons["Avslutt"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        // Detaljsiden er borte, og angre-banneret står på listen.
        XCTAssertTrue(undoArchiveButton.waitForExistence(timeout: 5), "Angre-banneret skulle vært synlig på listen")
        XCTAssertFalse(app.buttons["Pause"].exists, "Detaljsiden skulle vært lukket")
    }

    @MainActor
    func testSearchFiltersTheList() {
        executionTimeAllowance = 600
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
