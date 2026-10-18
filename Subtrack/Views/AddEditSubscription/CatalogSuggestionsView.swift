import SwiftUI

/// Forslag fra tjenestekatalogen under navnefeltet. Et trykk fyller ut skjemaet.
/// Hvert forslag blir en egen rad i skjemaets seksjon, og en egen knapp for VoiceOver.
struct CatalogSuggestionsView: View {
    let services: [CatalogService]
    let onSelect: (CatalogService) -> Void

    var body: some View {
        ForEach(services) { service in
            CatalogSuggestionRow(service: service) {
                onSelect(service)
            }
        }
    }
}

private struct CatalogSuggestionRow: View {
    let service: CatalogService
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Første plans pris, eller kategorien for tjenester uten fast pris.
    private var detailText: String {
        service.plans.first.map(CatalogPriceText.short) ?? service.category.displayName
    }

    /// Samme som `detailText`, men uten forkortelser, så VoiceOver leser det naturlig.
    private var spokenDetailText: String {
        service.plans.first.map(CatalogPriceText.spoken) ?? service.category.displayName
    }

    /// Nevner bare det tjenesten faktisk fyller ut, f.eks. "Fyller ut pris, kategori og ikon."
    private var hintText: String {
        var parts: [String] = []
        if !service.plans.isEmpty { parts.append("pris") }
        parts += ["kategori", "ikon"]
        if service.cancelURL != nil { parts.append("avslutningslenke") }
        let list = parts.dropLast().joined(separator: ", ") + " og " + (parts.last ?? "")
        return "Fyller ut \(list)."
    }

    /// Side om side vanligvis; ved tilgjengelighetsstørrelser stables ikon og tekst,
    /// slik raden i listen gjør, så navnet får hele bredden.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        Button(action: action) {
            layout {
                SubscriptionIcon(
                    symbolName: service.symbolName,
                    color: SubscriptionAppearance.color(forHex: service.colorHex) ?? .accentColor
                )
                // Ellers farger knappen teksten med aksentfargen, med svak kontrast.
                // `Color.primary` og `Color.secondary` og ikke `.primary` og `.secondary`,
                // som er hierarkiske og kan arve knappens farge.
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityLabel("Fyll ut for \(service.name)")
        .accessibilityValue(spokenDetailText)
        .accessibilityHint(hintText)
        .accessibilityIdentifier("catalogSuggestion.\(service.id)")
    }
}

/// Tekst for prisen på en plan i katalogen.
/// `nonisolated` fordi den er ren beregning og kalles fra closures som ikke er bundet til hovedtråden.
nonisolated enum CatalogPriceText {
    /// Kort form til visning, f.eks. "149,00 kr/mnd".
    static func short(_ plan: CatalogPlan) -> String {
        "\(plan.price.formatted(.currency(code: plan.currencyCode)))/\(shortUnit(plan.interval))"
    }

    /// Lang form til VoiceOver, f.eks. "149,00 kr per måned".
    static func spoken(_ plan: CatalogPlan) -> String {
        "\(plan.price.formatted(.currency(code: plan.currencyCode))) per \(spokenUnit(plan.interval))"
    }

    private static func shortUnit(_ interval: BillingInterval) -> String {
        switch interval {
        case .weekly: "uke"
        case .monthly: "mnd"
        case .quarterly: "kvartal"
        case .yearly: "år"
        }
    }

    private static func spokenUnit(_ interval: BillingInterval) -> String {
        switch interval {
        case .weekly: "uke"
        case .monthly: "måned"
        case .quarterly: "kvartal"
        case .yearly: "år"
        }
    }
}
