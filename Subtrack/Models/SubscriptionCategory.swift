import Foundation

/// Kategori for et abonnement. Lagres som rawValue-tekst i `Subscription.categoryCode`.
/// Codable trengs fortsatt for det utfasede feltet `Subscription.category`.
enum SubscriptionCategory: String, Codable, CaseIterable, Identifiable {
    case streaming
    case musikk
    case programvare
    case trening
    case nettsky
    case annet

    var id: Self { self }

    var displayName: String {
        switch self {
        case .streaming: "Streaming"
        case .musikk: "Musikk"
        case .programvare: "Programvare"
        case .trening: "Trening"
        case .nettsky: "Nettsky"
        case .annet: "Annet"
        }
    }

    /// Standard SF Symbol for kategorien, brukt når abonnementet ikke har eget ikon.
    var defaultSymbolName: String {
        switch self {
        case .streaming: "play.tv"
        case .musikk: "music.note"
        case .programvare: "terminal"
        case .trening: "figure.run"
        case .nettsky: "icloud"
        case .annet: "square.grid.2x2"
        }
    }
}
