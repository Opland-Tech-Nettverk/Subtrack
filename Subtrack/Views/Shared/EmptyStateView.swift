import SwiftUI

/// Vennlig melding som vises når brukeren ikke har lagt til noen abonnementer ennå.
struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "Ingen abonnementer ennå",
            systemImage: "creditcard",
            description: Text("Trykk på + for å legge til ditt første abonnement.")
        )
    }
}

#Preview {
    EmptyStateView()
}
