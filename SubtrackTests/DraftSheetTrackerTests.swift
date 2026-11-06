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

        #expect(tracker.isFree)
        #expect(tracker.dismissed() == nil)
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

        let finished = try #require(tracker.dismissed())

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

        let finishedByA = try #require(tracker.dismissed())
        #expect(finishedByA.id == a.id)

        #expect(tracker.isFree)
        tracker.presented(b)
        let finishedByB = try #require(tracker.dismissed())
        #expect(finishedByB.id == b.id)
    }

    @Test func dismissalIsReportedOnlyOnce() {
        var tracker = DraftSheetTracker()
        tracker.presented(draft("A"))

        #expect(tracker.dismissed() != nil)
        #expect(tracker.dismissed() == nil)
    }

    @Test func aFailedSaveKeepsTheFileEvenThoughTheSheetCloses() {
        var tracker = DraftSheetTracker()
        tracker.presented(draft("A"))

        tracker.saveFailed()

        #expect(tracker.dismissed() == nil)
        #expect(tracker.isFree)
    }

    @Test func aFailedSaveDoesNotAffectTheNextDraft() throws {
        var tracker = DraftSheetTracker()
        tracker.presented(draft("A"))
        tracker.saveFailed()
        _ = tracker.dismissed()

        let b = draft("B")
        tracker.presented(b)

        #expect(try #require(tracker.dismissed()).id == b.id)
    }
}
