import Foundation

/// Forslagene brukeren går gjennom, og hvilke som er huket av. Ren verdi uten visning, så den kan testes.
/// Sikre forslag er huket av på forhånd; middels sikre er det ikke.
struct SuggestionSelection: Equatable {
    private(set) var suggestions: [SubscriptionSuggestion]
    private(set) var selectedIDs: Set<String>

    init(suggestions: [SubscriptionSuggestion]) {
        self.suggestions = suggestions
        self.selectedIDs = Set(suggestions.filter { $0.confidence == .high }.map(\.id))
    }

    var selectedCount: Int { selectedIDs.count }
    var isEmpty: Bool { suggestions.isEmpty }

    func isSelected(_ id: String) -> Bool {
        selectedIDs.contains(id)
    }

    mutating func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else if suggestions.contains(where: { $0.id == id }) {
            selectedIDs.insert(id)
        }
    }

    /// Tar forslaget ut av listen, f.eks. etter at det er lagret fra skjemaet.
    mutating func remove(_ id: String) {
        suggestions.removeAll { $0.id == id }
        selectedIDs.remove(id)
    }

    /// Gir de valgte forslagene og tar dem ut av listen i samme steg. Et nytt kall gir derfor ingenting,
    /// så de samme abonnementene aldri kan legges inn to ganger, f.eks. ved et dobbelt trykk.
    mutating func takeSelected() -> [SubscriptionSuggestion] {
        let taken = suggestions.filter { selectedIDs.contains($0.id) }
        suggestions.removeAll { selectedIDs.contains($0.id) }
        selectedIDs.removeAll()
        return taken
    }
}
