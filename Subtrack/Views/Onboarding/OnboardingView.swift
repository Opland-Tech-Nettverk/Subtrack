import SwiftUI

/// Den tomme tilstanden og oppstarten: forklarer hva appen gjør og viser de tre måtene å få
/// abonnementene inn på. Vises i oversikten så lenge det ikke finnes noen abonnement.
struct OnboardingView: View {
    let addManually: () -> Void
    let importStatement: () -> Void
    let shareReceipt: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                VStack(spacing: 12) {
                    EntryCard(
                        symbolName: "plus",
                        color: Color.accentColor,
                        title: "Legg til selv",
                        subtitle: "Skriv inn navn og pris, eller velg en kjent tjeneste.",
                        identifier: "onboarding.add",
                        action: addManually
                    )
                    EntryCard(
                        symbolName: "doc.text.magnifyingglass",
                        color: Color(hex: "#FF9F0A") ?? .orange,
                        title: "Importer fra kontoutskrift",
                        subtitle: "Finn abonnementene i en fil fra nettbanken. Filen leses bare på telefonen.",
                        identifier: "onboarding.importStatement",
                        action: importStatement
                    )
                    EntryCard(
                        symbolName: "square.and.arrow.down",
                        color: Color(hex: "#30D158") ?? .green,
                        title: "Del en kvittering",
                        subtitle: "Del en e-post, en PDF eller et bilde med Subtrack, så fylles skjemaet ut.",
                        identifier: "onboarding.shareReceipt",
                        action: shareReceipt
                    )
                }
                Label("Alt blir på enheten din og i din egen iCloud.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            tiles
            VStack(spacing: 8) {
                Text("Ingen abonnementer ennå")
                    .font(.rounded(.title))
                    .multilineTextAlignment(.center)
                Text("Legg inn abonnementene dine, så ser du hva de koster og når de trekkes.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    /// Tre fliser i en liten bunke. Pynt: skjult for VoiceOver.
    private var tiles: some View {
        ZStack {
            SubscriptionTile(symbolName: "music.note", color: Color(hex: "#BF5AF2") ?? .purple, size: 64)
                .rotationEffect(.degrees(-12))
                .offset(x: -52, y: 8)
            SubscriptionTile(symbolName: "icloud", color: Color(hex: "#40C8E0") ?? .cyan, size: 64)
                .rotationEffect(.degrees(10))
                .offset(x: 52, y: 8)
            SubscriptionTile(symbolName: "play.tv", color: Color(hex: "#FF453A") ?? .red, progress: 0.7, size: 72)
        }
        .frame(height: 112)
        .accessibilityHidden(true)
    }
}

/// En av de tre inngangene, som et stort kort med ikon, tittel og forklaring.
private struct EntryCard: View {
    let symbolName: String
    let color: Color
    let title: String
    let subtitle: String
    let identifier: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 14))
            layout {
                SubscriptionTile(symbolName: symbolName, color: color, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .contentShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Tom tilstand") {
    NavigationStack {
        OnboardingView(addManually: {}, importStatement: {}, shareReceipt: {})
            .background(Color.canvas)
            .navigationTitle("Subtrack")
    }
}
