import SwiftUI
import UIKit

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
        IconOption(symbolName: "sparkles", name: "AI")
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

    /// Grønn for «spart»-beløp. Systemgrønn (#30D158) gir bare ca. 2:1 mot hvit bakgrunn,
    /// så i lys modus brukes en mørkere grønn (#1B7D33, ca. 5,2:1 mot hvit og 4,7:1 mot
    /// gruppert bakgrunn) som holder kravet på 4,5:1 for tekst. I mørk modus er systemgrønn
    /// lesbar (ca. 8:1 mot mørk bakgrunn) og beholdes.
    static let savings = Color.adaptive(light: 0x1B7D33, dark: 0x30D158)

    /// Farge som bytter mellom to RGB-verdier etter lys/mørk modus.
    /// `nonisolated` så closuren ikke arver hovedaktøren; UIKit kan løse fargen hvor som helst.
    nonisolated fileprivate static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            Color.rgbColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    nonisolated private static func rgbColor(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension SubscriptionAppearance {
    /// Fargen et abonnement vises med. Paletten bruker iOS' mørk modus-farger, og oransje,
    /// grønn og turkis er så lyse at den fargede sirkelen bare får ca. 2:1 mot hvit
    /// bakgrunn. I lys modus får de derfor en mørkere variant (over 4:1 mot bakgrunnen,
    /// kravet for grafikk er 3:1), og det hvite ikonet får da også ca. 4,2–4,5:1.
    /// Mørk modus beholder den lagrede fargen: sirkelen får over 6:1 mot de mørke
    /// bakgrunnene, mens det hvite ikonet på den bare får ca. 2:1. Det godtas fordi ikonet
    /// er dekorativt (skjult for VoiceOver) og navnet bærer betydningen. Indigo, lilla,
    /// rosa, rød og grå klarer 3:1 allerede (3,3–5,1:1) og brukes som de er.
    ///
    /// Selve hex-verdien endres ikke: den er lagret i brukerdata og brukes til å finne
    /// valgt farge i `colors`.
    nonisolated static func color(forHex hex: String) -> Color? {
        let digits = (hex.hasPrefix("#") ? String(hex.dropFirst()) : hex).uppercased()
        return switch digits {
        case "FF9F0A": Color.adaptive(light: 0xC75C00, dark: 0xFF9F0A) // Oransje, ca. 4,2:1
        case "30D158": Color.adaptive(light: 0x248A3D, dark: 0x30D158) // Grønn, ca. 4,4:1
        case "40C8E0": Color.adaptive(light: 0x008299, dark: 0x40C8E0) // Turkis, ca. 4,5:1
        default: Color(hex: hex)
        }
    }
}

extension Subscription {
    var displaySymbolName: String {
        symbolName ?? kind.defaultSymbolName
    }

    var displayColor: Color {
        colorHex.flatMap(SubscriptionAppearance.color(forHex:)) ?? .accentColor
    }
}
