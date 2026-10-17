import Foundation

/// Tolker lenken brukeren skriver inn for å avslutte et abonnement.
enum CancelLink {
    /// Gjør om tekst til en åpnbar nettadresse. Mangler `https://`, legges det til,
    /// slik at "netflix.com/cancel" også fungerer. Returnerer `nil` for tom eller ugyldig tekst.
    /// `nonisolated` fordi den kalles fra SwiftData-modellen, som ikke er bundet til hovedtråden.
    nonisolated static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard
            let components = URLComponents(string: withScheme),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            // Ellers tolkes f.eks. "mailto:hei@example.com" som bruker:passord@example.com.
            components.user == nil,
            components.password == nil,
            let host = components.host,
            host.contains("."),
            !host.hasPrefix("."),
            !host.hasSuffix(".")
        else { return nil }
        return components.url
    }
}
