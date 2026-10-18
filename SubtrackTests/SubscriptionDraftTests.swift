import Foundation
import Testing
@testable import Subtrack

@MainActor
struct SubscriptionDraftTests {

    @Test func optionalFieldsDefaultToNil() {
        let draft = SubscriptionDraft(source: .catalog)

        #expect(draft.source == .catalog)
        #expect(draft.name == nil)
        #expect(draft.price == nil)
        #expect(draft.currencyCode == nil)
        #expect(draft.interval == nil)
        #expect(draft.kind == nil)
        #expect(draft.nextRenewalDate == nil)
        #expect(draft.symbolName == nil)
        #expect(draft.colorHex == nil)
        #expect(draft.cancelURLString == nil)
        #expect(draft.note == nil)
        #expect(draft.catalogServiceID == nil)
    }

    @Test func eachDraftGetsItsOwnID() {
        let first = SubscriptionDraft(source: .shortcut, name: "Netflix")
        let second = SubscriptionDraft(source: .shortcut, name: "Netflix")

        #expect(first.id != second.id)
        // Ulik id gjør to ellers like utkast ulike, så skjemaet åpnes på nytt for hvert utkast.
        #expect(first != second)
    }

    @Test func equalityComparesAllFields() {
        let draft = SubscriptionDraft(source: .receipt, name: "Spotify", price: 129, interval: .monthly, kind: .musikk)
        var copy = draft

        #expect(copy == draft)

        copy.price = 139
        #expect(copy != draft)
    }
}
