import SwiftUI

/// Begrenser bredden på innholdet i en liste eller rullevisning og sentrerer det,
/// slik at rader ikke strekkes over hele skjermen på iPad. Selve rullevisningen fyller
/// fortsatt skjermen, så bakgrunn og rulling oppfører seg som vanlig. På iPhone er
/// skjermen smalere enn grensen, og ingenting endres.
private struct ReadableContentWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var containerWidth: CGFloat = 0

    private var horizontalMargin: CGFloat {
        max((containerWidth - maxWidth) / 2, 0)
    }

    func body(content: Content) -> some View {
        Group {
            // Bare når skjermen er bredere enn grensen: contentMargins erstatter listens
            // vanlige innrykk, så på iPhone ville radene ellers gått helt ut til kanten.
            if horizontalMargin > 0 {
                content.contentMargins(.horizontal, horizontalMargin, for: .scrollContent)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            containerWidth = width
        }
    }
}

extension View {
    func readableContentWidth(_ maxWidth: CGFloat = 720) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth))
    }
}
