import Foundation
import Testing
@testable import Subtrack

/// Hver test lager sin egen ruter, så de ikke deler kø med appen eller hverandre.
@MainActor
struct AddSubscriptionRouterTests {

    @Test func startsWithoutPendingDrafts() {
        let router = AddSubscriptionRouter()

        #expect(router.pendingDrafts.isEmpty)
        #expect(!router.hasPendingDrafts)
    }

    @Test func dequeueOnEmptyQueueReturnsNil() {
        let router = AddSubscriptionRouter()

        #expect(router.dequeue() == nil)
        #expect(!router.hasPendingDrafts)
    }

    @Test func enqueueMakesDraftsPending() {
        let router = AddSubscriptionRouter()
        let draft = SubscriptionDraft(source: .shortcut, name: "Netflix")

        router.enqueue(draft)

        #expect(router.hasPendingDrafts)
        #expect(router.pendingDrafts == [draft])
    }

    @Test func draftsAreDequeuedInTheOrderTheyCame() {
        let router = AddSubscriptionRouter()
        let first = SubscriptionDraft(source: .shortcut, name: "Netflix")
        let second = SubscriptionDraft(source: .shortcut, name: "Spotify")
        let third = SubscriptionDraft(source: .receipt, name: "Storytel")

        router.enqueue(first)
        router.enqueue(second)
        router.enqueue(third)

        #expect(router.dequeue() == first)
        #expect(router.pendingDrafts == [second, third])
        #expect(router.dequeue() == second)
        #expect(router.dequeue() == third)
        #expect(router.dequeue() == nil)
        #expect(!router.hasPendingDrafts)
    }
}
