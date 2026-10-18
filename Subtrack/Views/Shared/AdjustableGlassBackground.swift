import SwiftUI

/// En bakgrunn inspirert av Liquid Glass der "styrken" kan justeres av brukeren.
///
/// Apples ekte Liquid Glass-API (`glassEffect`) har ingen skala for hvor sterk
/// effekten er - bare en variant (regular/clear), en tint og om den er interaktiv.
/// For å gi brukeren en reell justerbar styrke blander vi derfor mellom en
/// helt matt kortbunn (styrke 0) og full glasseffekt (styrke 1): jo høyere styrke,
/// jo mer gjennomsiktig blir den matte bunnen, og jo mer av bakgrunnen slipper
/// gjennom glasset.
///
/// På iOS 17-25 (før Liquid Glass fantes) brukes et vanlig SwiftUI-material
/// i stedet, slik at effekten fortsatt er justerbar, bare ikke "ekte" glass.
///
/// Merk: Apple mener Liquid Glass først og fremst for navigasjons- og kontrollaget
/// (verktøylinjer, faner, knapper), ikke for innhold i lister. Her brukes det likevel
/// på oppsummeringskortene i listene, etter eget ønske, og styrken er brukerstyrt.
struct AdjustableGlassBackground: ViewModifier {
    let intensity: Double
    var cornerRadius: CGFloat = 20

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Hvor mye av den matte bunnen som alltid blir liggende igjen ved full styrke,
    /// slik at teksten på kortet er lesbar i både lys og mørk modus.
    private static let minimumBaseOpacity: Double = 0.15

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    // Når brukeren har skrudd på "Reduser gjennomsiktighet" i Innstillinger,
    // skal overflaten være matt uansett hva glass-styrke-slideren står på.
    private var effectiveIntensity: Double {
        reduceTransparency ? 0 : min(max(intensity, 0), 1)
    }

    /// Styrken med en myk kurve (ease-out), slik at slideren gir synlig endring
    /// allerede i den nedre delen i stedet for at alt skjer helt mot slutten.
    private var easedIntensity: Double {
        let value = effectiveIntensity
        return value * (2 - value)
    }

    /// Den matte bunnen tones ut fra helt dekkende (styrke 0) ned til en svak tint (styrke 1).
    private var baseOpacity: Double {
        1 - easedIntensity * (1 - Self.minimumBaseOpacity)
    }

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                // Matt kortbunn. Ved styrke 0 er den helt dekkende og kortet ser ut som
                // et vanlig kort; ved høyere styrke slipper den bakgrunnen gjennom.
                // Skyggen tones ut sammen med bunnen, så den ikke skinner gjennom glasset.
                shape
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    .opacity(baseOpacity)

                // Ved styrke 0 (eller med "Reduser gjennomsiktighet") tegnes ikke glasset i det hele tatt.
                if effectiveIntensity > 0 {
                    glassLayer
                        .opacity(easedIntensity)
                }
            }
        }
    }

    @ViewBuilder
    private var glassLayer: some View {
        if #available(iOS 26, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape
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
        Text("Styrke 0").padding().adjustableGlassBackground(intensity: 0)
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
