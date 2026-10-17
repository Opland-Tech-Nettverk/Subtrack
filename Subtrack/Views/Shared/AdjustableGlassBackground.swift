import SwiftUI

/// En bakgrunn inspirert av Liquid Glass der "styrken" kan justeres av brukeren.
///
/// Apples ekte Liquid Glass-API (`glassEffect`) har ingen skala for hvor sterk
/// effekten er - bare en variant (regular/clear), en tint og om den er interaktiv.
/// For å gi brukeren en reell justerbar styrke krysstoner vi derfor mellom en
/// helt matt bakgrunn (styrke 0) og full glasseffekt (styrke 1).
///
/// På iOS 17-25 (før Liquid Glass fantes) brukes et vanlig SwiftUI-material
/// i stedet, slik at effekten fortsatt er justerbar, bare ikke "ekte" glass.
struct AdjustableGlassBackground: ViewModifier {
    let intensity: Double
    var cornerRadius: CGFloat = 20

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Når brukeren har skrudd på "Reduser gjennomsiktighet" i Innstillinger,
    // skal overflaten være matt uansett hva glass-styrke-slideren står på.
    private var effectiveIntensity: Double {
        reduceTransparency ? 0 : min(max(intensity, 0), 1)
    }

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                // Denne kortbunnen er alltid synlig, uansett styrke, slik at kortet
                // ikke forsvinner helt når brukeren skrur glasseffekten helt ned.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

                glassLayer
                    .opacity(effectiveIntensity)
            }
        }
    }

    @ViewBuilder
    private var glassLayer: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

extension View {
    /// Legger på en bakgrunn inspirert av Liquid Glass, med styrke fra 0 (matt) til 1 (full glasseffekt).
    func adjustableGlassBackground(intensity: Double, cornerRadius: CGFloat = 20) -> some View {
        modifier(AdjustableGlassBackground(intensity: intensity, cornerRadius: cornerRadius))
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Styrke 0,2").padding().adjustableGlassBackground(intensity: 0.2)
        Text("Styrke 0,6").padding().adjustableGlassBackground(intensity: 0.6)
        Text("Styrke 1,0").padding().adjustableGlassBackground(intensity: 1.0)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
        LinearGradient(colors: [.blue, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    )
}
