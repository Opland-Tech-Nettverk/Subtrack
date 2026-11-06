import SwiftUI

/// Et abonnement som kort i listen: ikonflis med fremdriftsring mot neste trekk, navn og intervall,
/// merker for prøveperiode, pauset og utenlandsk valuta, og beløp med tid til neste trekk.
struct SubscriptionRow: View {
    let subscription: Subscription
    /// Beløpet omregnet til hovedvalutaen, f.eks. «≈ 215 kr», når abonnementet har en annen valuta.
    var approximateText: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var daysUntilRenewal: Int {
        subscription.daysUntilRenewal()
    }

    private var isDueToday: Bool {
        subscription.isActive && daysUntilRenewal <= 0 && !subscription.isInTrial()
    }

    private var intervalText: String {
        let interval = subscription.interval.displayName
        return subscription.isShared ? "\(interval) · delt på \(subscription.splitCount)" : interval
    }

    var body: some View {
        AdaptiveRowLayout(isStacked: dynamicTypeSize.isAccessibilitySize) {
            SubscriptionTile(
                symbolName: subscription.displaySymbolName,
                color: Color.tile(for: subscription),
                progress: subscription.isActive ? subscription.renewalProgress() : nil,
                isDimmed: !subscription.isActive
            )
        } title: {
            // Bare ikonet dempes for pausede abonnement. Demping av hele raden ga sekundærteksten
            // bare ca. 2:1 kontrast; merket «Pauset» forteller det samme, også til VoiceOver.
            Text(subscription.name)
                .font(.body.weight(.semibold))
            Text(intervalText)
                .font(.caption)
                .foregroundStyle(.secondary)
            badges
        } detail: {
            // Delte abonnement viser brukerens del, slik at raden stemmer med totalene.
            Text(Money.string(subscription.myShare, code: subscription.currencyCode))
                .font(.amount(.body))
                .foregroundStyle(subscription.isActive ? HierarchicalShapeStyle.primary : .secondary)
            if subscription.isActive {
                renewalLabel
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badges: some View {
        let showsTrial = subscription.isActive && subscription.isInTrial()
        if showsTrial || !subscription.isActive || approximateText != nil {
            HStack(spacing: 4) {
                if !subscription.isActive {
                    Badge(text: "Pauset", symbol: "pause.fill", tint: .gray)
                }
                if showsTrial {
                    Badge(text: "Prøve", symbol: "hourglass", tint: .orange)
                }
                if let approximateText {
                    Badge(text: approximateText, symbol: "arrow.left.arrow.right", tint: .teal)
                }
            }
        }
    }

    /// «Om 5 dager». Dagens trekk får en pulserende prikk, men ikke med «Reduser bevegelse».
    @ViewBuilder
    private var renewalLabel: some View {
        if isDueToday {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .accessibilityHidden(true)
                Text(subscription.renewalDescription())
                    .font(.caption.weight(.semibold))
            }
        } else {
            Text(subscription.renewalDescription())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Rad med ikon, tittel og detaljer. Vanligvis side om side; ved tilgjengelighetsstørrelser
/// stables alt under hverandre, så navn og beløp får hele bredden i stedet for å deles med bindestrek.
struct AdaptiveRowLayout<Icon: View, Title: View, Detail: View>: View {
    let isStacked: Bool
    @ViewBuilder let icon: Icon
    @ViewBuilder let title: Title
    @ViewBuilder let detail: Detail

    var body: some View {
        if isStacked {
            VStack(alignment: .leading, spacing: 8) {
                icon
                VStack(alignment: .leading, spacing: 2) { title }
                VStack(alignment: .leading, spacing: 2) { detail }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 3) { title }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) { detail }
            }
        }
    }
}

#Preview {
    List {
        SubscriptionRow(subscription: Subscription(name: "Netflix", price: 149, billingInterval: .monthly, category: .streaming, colorHex: "#FF453A"))
        SubscriptionRow(subscription: Subscription(name: "Spotify Family", price: 279, category: .musikk, colorHex: "#30D158", splitCount: 3))
        SubscriptionRow(subscription: Subscription(name: "ChatGPT Plus", price: 20, currencyCode: "USD", category: .ai), approximateText: "≈ 215 kr")
        SubscriptionRow(subscription: Subscription(name: "Fitness24", price: 399, billingInterval: .monthly, category: .trening, isActive: false))
    }
}
