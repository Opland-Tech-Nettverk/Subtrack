import Foundation
import Testing
@testable import Subtrack

@MainActor
struct DraftSheetTrackerTests {

    private func draft(_ name: String) -> SubscriptionDraft {
        SubscriptionDraft(source: .receipt, name: name, receiptInboxID: UUID())
    }

    @Test func startsFreeAndHasNothingToFinish() {
        var tracker = DraftSheetTracker()

        let finished = tracker.dismissed()

        #expect(tracker.isFree)
        #expect(finished == nil)
    }

    @Test func aSheetThatHasBeenPresentedBlocksTheNextUntilItIsFullyDismissed() {
        var tracker = DraftSheetTracker()

        tracker.presented(draft("A"))

        // Under lukkeanimasjonen er `item`-bindingen nil, men `onDismiss` har ikke kommet. Neste utkast venter.
        #expect(!tracker.isFree)
    }

    @Test func dismissalFinishesTheDraftThatWasShown() throws {
        var tracker = DraftSheetTracker()
        let shown = draft("A")
        tracker.presented(shown)

        let result = tracker.dismissed()
        let finished = try #require(result)

        #expect(finished.id == shown.id)
        #expect(tracker.isFree)
    }

    @Test func theNextDraftIsNeverFinishedByThePreviousSheetsDismissal() throws {
        // A er lagret, B er klar mens A fortsatt lukkes. Visningen venter på `isFree`, så B vises først etter at
        // A er meldt lukket, og A er det som ferdigbehandles. B sin fil røres ikke.
        var tracker = DraftSheetTracker()
        let a = draft("A")
        let b = draft("B")
        tracker.presented(a)
        #expect(!tracker.isFree, "B skal ikke vises mens A lukkes")

        let dismissedA = tracker.dismissed()
        let finishedByA = try #require(dismissedA)
        #expect(finishedByA.id == a.id)

        #expect(tracker.isFree)
        tracker.presented(b)
        let dismissedB = tracker.dismissed()
        let finishedByB = try #require(dismissedB)
        #expect(finishedByB.id == b.id)
    }

    @Test func dismissalIsReportedOnlyOnce() {
        var tracker = DraftSheetTracker()
        tracker.presented(draft("A"))

        let first = tracker.dismissed()
        let second = tracker.dismissed()

        #expect(first != nil)
        #expect(second == nil)
    }

    @Test func aFailedSaveKeepsTheFileEvenThoughTheSheetCloses() {
        var tracker = DraftSheetTracker()
        tracker.presented(draft("A"))

        tracker.saveFailed()
        let finished = tracker.dismissed()

        #expect(finished == nil)
        #expect(tracker.isFree)
    }

    @Test func aFailedSaveDoesNotAffectTheNextDraft() throws {
        var tracker = DraftSheetTracker()
        tracker.presented(draft("A"))
        tracker.saveFailed()
        _ = tracker.dismissed()

        let b = draft("B")
        tracker.presented(b)

        let result = tracker.dismissed()
        let finished = try #require(result)
        #expect(finished.id == b.id)
    }
}
