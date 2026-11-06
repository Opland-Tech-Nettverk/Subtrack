import Foundation
import Testing
@testable import Subtrack

@MainActor
struct SuggestionSelectionTests {

    private func suggestion(_ id: String, _ confidence: SubscriptionSuggestion.Confidence) -> SubscriptionSuggestion {
        let date = BankStatementTestSupport.day(2026, 10, 14)
        return SubscriptionSuggestion(
            id: id,
            name: id,
            price: 100,
            currencyCode: "NOK",
            interval: .monthly,
            confidence: confidence,
            lastChargeDate: date,
            nextExpectedDate: date,
            chargeCount: 4,
            service: nil,
            draft: SubscriptionDraft(source: .bankStatement)
        )
    }

    private var selection: SuggestionSelection {
        SuggestionSelection(suggestions: [
            suggestion("a", .high),
            suggestion("b", .medium),
            suggestion("c", .high)
        ])
    }

    @Test func onlyHighConfidenceSuggestionsStartChecked() {
        let selection = selection
        #expect(selection.isSelected("a"))
        #expect(!selection.isSelected("b"))
        #expect(selection.isSelected("c"))
        #expect(selection.selectedCount == 2)
    }

    @Test func toggleChecksAndUnchecks() {
        var selection = selection
        selection.toggle("b")
        #expect(selection.isSelected("b"))
        selection.toggle("a")
        #expect(!selection.isSelected("a"))
        #expect(selection.selectedCount == 2)
        // Et ukjent forslag kan ikke velges.
        selection.toggle("x")
        #expect(!selection.isSelected("x"))
    }

    @Test func takingTheSelectedGivesThemOnceAndRemovesThemFromTheList() {
        var selection = selection
        let first = selection.takeSelected()
        #expect(first.map(\.id) == ["a", "c"])
        #expect(selection.suggestions.map(\.id) == ["b"])
        #expect(selection.selectedCount == 0)
    }

    @Test func aSecondTapOnAddFindsNothingToAddAgain() {
        // Det et dobbelt trykk på «Legg til valgte» ville gjort: samme valg to ganger.
        var selection = selection
        _ = selection.takeSelected()
        #expect(selection.takeSelected().isEmpty)
    }

    @Test func removingASuggestionAlsoUnchecksIt() {
        var selection = selection
        selection.remove("a")
        #expect(selection.suggestions.map(\.id) == ["b", "c"])
        #expect(!selection.isSelected("a"))
        #expect(selection.selectedCount == 1)
        #expect(selection.takeSelected().map(\.id) == ["c"])
    }

    @Test func isEmptyWhenEverythingIsTakenOrRemoved() {
        var selection = selection
        _ = selection.takeSelected()
        selection.remove("b")
        #expect(selection.isEmpty)
    }
}
