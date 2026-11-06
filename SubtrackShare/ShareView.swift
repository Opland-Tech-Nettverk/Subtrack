import SwiftUI

/// Skjermen utvidelsen viser: leser, ferdig eller feil. Enkel og rolig, i samme ånd som appen.
struct ShareView: View {
    let model: ShareViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            if model.state == .reading {
                Button("Avbryt") {
                    model.cancel()
                }
                .controlSize(.large)
                .accessibilityIdentifier("share.cancel")
            } else if model.state != .cancelled {
                Button {
                    model.dismiss()
                } label: {
                    Text("Ferdig")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("share.done")
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .reading:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Leser kvitteringen …")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        case .done:
            message(
                symbol: "checkmark.circle.fill",
                color: .green,
                title: "Lagt klar i SubTrack.",
                detail: "Åpne SubTrack for å fullføre."
            )
        case .cancelled:
            EmptyView()
        case .failed(let failure):
            message(symbol: "exclamationmark.triangle.fill", color: .orange, title: failure.title, detail: failure.detail)
        }
    }

    private func message(symbol: String, color: Color, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private extension ShareViewModel.Failure {
    var title: String {
        switch self {
        case .unreadable: "Kunne ikke lese filen."
        case .noText: "Fant ingen tekst."
        case .cannotSave: "Kunne ikke legge den klar."
        }
    }

    var detail: String {
        switch self {
        case .unreadable:
            "Del teksten i kvitteringen, en PDF eller et bilde av den."
        case .noText(.pdf):
            "PDF-en er låst eller har ingen tekst som kan leses. Del teksten i kvitteringen i stedet."
        case .noText(.image):
            "Prøv et skarpere bilde, eller del teksten i kvitteringen i stedet."
        case .noText(.text):
            "Teksten du delte, er tom."
        case .cannotSave:
            "Prøv igjen. Hjelper det ikke, åpne SubTrack og prøv på nytt."
        }
    }
}
