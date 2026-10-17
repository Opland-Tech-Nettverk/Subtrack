import SwiftUI

/// Vises i stedet for appen når databasen på disk ikke kan åpnes. Dataene ligger urørt
/// på disk, så brukeren får vite at ingenting er slettet og hva som kan hjelpe.
struct DatabaseErrorView: View {
    let errorDescription: String

    var body: some View {
        ContentUnavailableView {
            Label("Kunne ikke åpne dataene dine", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Ingenting er slettet. Prøv å starte appen på nytt, oppdatere den til nyeste versjon og sjekke at enheten har ledig lagringsplass.")
        } actions: {
            DisclosureGroup("Tekniske detaljer") {
                ScrollView {
                    Text(errorDescription)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            .font(.footnote)
            .padding(.horizontal)
        }
    }
}

#Preview {
    DatabaseErrorView(errorDescription: "SwiftDataError(_error: SwiftData.SwiftDataError._Error.loadIssueModelContainer)")
}
