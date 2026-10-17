import SwiftUI

/// Ikonene og fargene brukeren kan velge for et abonnement. Navnene brukes av VoiceOver.
enum SubscriptionAppearance {
    struct IconOption: Identifiable {
        let symbolName: String
        let name: String
        var id: String { symbolName }
    }

    struct ColorOption: Identifiable {
        let hex: String
        let name: String
        var id: String { hex }
    }

    static let icons: [IconOption] = [
        IconOption(symbolName: "play.tv", name: "TV"),
        IconOption(symbolName: "film", name: "Film"),
        IconOption(symbolName: "music.note", name: "Musikk"),
        IconOption(symbolName: "headphones", name: "Hodetelefoner"),
        IconOption(symbolName: "gamecontroller", name: "Spill"),
        IconOption(symbolName: "newspaper", name: "Avis"),
        IconOption(symbolName: "book", name: "Bok"),
        IconOption(symbolName: "terminal", name: "Programvare"),
        IconOption(symbolName: "icloud", name: "Nettsky"),
        IconOption(symbolName: "figure.run", name: "Trening"),
        IconOption(symbolName: "heart", name: "Helse"),
        IconOption(symbolName: "cart", name: "Handel"),
        IconOption(symbolName: "car", name: "Bil"),
        IconOption(symbolName: "house", name: "Hjem"),
        IconOption(symbolName: "phone", name: "Mobil"),
        IconOption(symbolName: "wifi", name: "Internett"),
        IconOption(symbolName: "bolt", name: "Strøm"),
        IconOption(symbolName: "sparkles", name: "Annet")
    ]

    // Ingen egen blå: "Standard" er appens blå aksentfarge.
    static let colors: [ColorOption] = [
        ColorOption(hex: "#5E5CE6", name: "Indigo"),
        ColorOption(hex: "#BF5AF2", name: "Lilla"),
        ColorOption(hex: "#FF375F", name: "Rosa"),
        ColorOption(hex: "#FF453A", name: "Rød"),
        ColorOption(hex: "#FF9F0A", name: "Oransje"),
        ColorOption(hex: "#30D158", name: "Grønn"),
        ColorOption(hex: "#40C8E0", name: "Turkis"),
        ColorOption(hex: "#8E8E93", name: "Grå")
    ]
}

extension Color {
    /// Lager en farge fra en hex-streng som "#FF9F0A". Returnerer `nil` for ugyldig format.
    /// `nonisolated` fordi den er ren beregning og trygt kan kalles fra hvilken som helst tråd.
    nonisolated init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Subscription {
    var displaySymbolName: String {
        symbolName ?? category.defaultSymbolName
    }

    var displayColor: Color {
        colorHex.flatMap(Color.init(hex:)) ?? .accentColor
    }
}
