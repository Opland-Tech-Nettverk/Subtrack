import Foundation
import Observation

/// Utkast som venter på å bli vist i skjemaet, f.eks. fra snarveien «Legg til abonnement».
/// Finnes én gang, fordi App Intents kjører utenfor visningshierarkiet. Utkastene vises
/// ett om gangen, og aldri over et ark som allerede er åpent.
@Observable
final class AddSubscriptionRouter {
    static let shared = AddSubscriptionRouter()

    /// Utkast i den rekkefølgen de kom.
    private(set) var pendingDrafts: [SubscriptionDraft] = []

    var hasPendingDrafts: Bool { !pendingDrafts.isEmpty }

    func enqueue(_ draft: SubscriptionDraft) {
        pendingDrafts.append(draft)
    }

    /// Tar ut og returnerer det eldste utkastet, eller nil.
    func dequeue() -> SubscriptionDraft? {
        pendingDrafts.isEmpty ? nil : pendingDrafts.removeFirst()
    }
}
