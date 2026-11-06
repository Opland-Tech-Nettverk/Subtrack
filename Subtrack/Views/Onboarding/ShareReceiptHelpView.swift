import SwiftUI

/// Forklarer hvordan en kvittering deles til Subtrack. Delingen selv hører til en egen funksjon;
/// denne skjermen viser bare veien dit.
struct ShareReceiptHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Del en kvittering")
                        .font(.rounded(.title))
                    step(1, "Åpne kvitteringen i Mail, Safari, Filer eller Bilder.")
                    step(2, "Trykk på del-knappen og velg Subtrack.")
                    step(3, "Åpne Subtrack, så er skjemaet fylt ut. Du ser over og lagrer.")
                    Label("Teksten leses bare på telefonen, og ingenting legges inn før du har godkjent det.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.amount(.headline, weight: .bold))
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
