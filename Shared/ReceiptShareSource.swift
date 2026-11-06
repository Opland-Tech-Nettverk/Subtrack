import Foundation
import UniformTypeIdentifiers

/// Velger hva delingsutvidelsen skal lese når brukeren deler flere ting samtidig. Ren logikk over
/// type-identifikatorene, så den kan enhetstestes uten en ekte `NSItemProvider`.
nonisolated enum ReceiptShareSource {
    nonisolated struct Choice: Equatable {
        /// Plassen i listen med vedlegg.
        var index: Int
        var kind: ReceiptInboxKind
        /// Typen som skal lastes, f.eks. «com.adobe.pdf».
        var typeIdentifier: String
    }

    /// Hvilken type innhold en type-identifikator er: ren tekst, PDF eller bilde. Nettsider (HTML, URL) og
    /// alt annet gir nil, siden de ikke støttes.
    static func kind(forTypeIdentifier identifier: String) -> ReceiptInboxKind? {
        guard let type = UTType(identifier) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .plainText) { return .text }
        return nil
    }

    private static func isLink(_ identifier: String) -> Bool {
        UTType(identifier)?.conforms(to: .url) ?? false
    }

    /// Alt som kan leses, i den rekkefølgen det skal prøves: PDF, så bilde, så tekst. Teksten kommer sist fordi den
    /// ofte bare er en tittel som følger med filen (en nettleser eller bankapp deler «Kvittering 123» sammen med PDF-en).
    /// Innen samme slag kommer det første vedlegget først. Utvidelsen bruker den første som gir tekst.
    /// `providers` har type-identifikatorene til hvert vedlegg, i den rekkefølgen vedlegget selv oppgir dem.
    static func orderedChoices(from providers: [[String]]) -> [Choice] {
        var result: [Choice] = []
        for wanted in [ReceiptInboxKind.pdf, .image, .text] {
            for (index, identifiers) in providers.enumerated() {
                // En lenke registrerer ofte også ren tekst (adressen), men er ikke en kvittering.
                if wanted == .text, identifiers.contains(where: isLink) { continue }
                if let identifier = identifiers.first(where: { kind(forTypeIdentifier: $0) == wanted }) {
                    result.append(Choice(index: index, kind: wanted, typeIdentifier: identifier))
                }
            }
        }
        return result
    }
}
