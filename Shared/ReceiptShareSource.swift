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

    /// Tekst først, så PDF, så bilde. Innen samme slag vinner det første vedlegget. `providers` har type-
    /// identifikatorene til hvert vedlegg, i den rekkefølgen vedlegget selv oppgir dem.
    static func choose(from providers: [[String]]) -> Choice? {
        for wanted in [ReceiptInboxKind.text, .pdf, .image] {
            for (index, identifiers) in providers.enumerated() {
                for identifier in identifiers where kind(forTypeIdentifier: identifier) == wanted {
                    return Choice(index: index, kind: wanted, typeIdentifier: identifier)
                }
            }
        }
        return nil
    }
}
