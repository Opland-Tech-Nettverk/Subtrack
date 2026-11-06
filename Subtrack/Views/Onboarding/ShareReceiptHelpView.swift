import SwiftUI

/// Forklarer hvordan en kvittering deles til Subtrack. Vises som ark fra tom-tilstanden og som en side
/// i Innstillinger, så veibeskrivelsen alltid er til å finne.
struct ShareReceiptHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ShareReceiptHelpContent()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ferdig") { dismiss() }
                    }
                }
        }
    }
}

/// Selve veibeskrivelsen, uten egen navigasjon, så den kan brukes både i arket og i Innstillinger.
struct ShareReceiptHelpContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Del en kvittering")
                    .font(.rounded(.title))
                step(1, "Åpne kvitteringen i Mail, Safari, Filer eller Bilder. Du kan dele teksten, en PDF eller et skjermbilde.")
                step(2, "Trykk på del-knappen og velg SubTrack. Står den ikke blant appene, velg «Mer» og slå den på.")
                step(3, "Åpne SubTrack. Skjemaet er fylt ut, så du ser over og lagrer. Det som ikke stod i kvitteringen, står tomt.")
                Label("Teksten leses bare på telefonen. Den ligger kryptert og utenfor sikkerhetskopien til du åpner SubTrack, slettes senest etter 7 dager, og ingenting legges inn før du har godkjent det.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.canvas)
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
