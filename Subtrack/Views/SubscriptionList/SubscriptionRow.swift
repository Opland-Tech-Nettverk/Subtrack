import SwiftUI

struct SubscriptionRow: View {
    let subscription: Subscription

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var daysUntilRenewal: Int {
        subscription.daysUntilRenewal()
    }

    private var renewalText: String {
        guard subscription.isActive else { return "Pauset" }
        if subscription.isInTrial() {
            return switch daysUntilRenewal {
            case ..<1: "Prøve slutter i dag"
            case 1: "Prøve slutter i morgen"
            default: "Prøve slutter om \(daysUntilRenewal) dager"
            }
        }
        return switch daysUntilRenewal {
        case ..<0: "Forfalt"
        case 0: "I dag"
        case 1: "I morgen"
        default: "Om \(daysUntilRenewal) dager"
        }
    }

    private var intervalText: String {
        let interval = subscription.interval.displayName
        return subscription.isShared ? "\(interval) · delt på \(subscription.splitCount)" : interval
    }

    var body: some View {
        AdaptiveRowLayout(isStacked: dynamicTypeSize.isAccessibilitySize) {
            SubscriptionIcon(
                symbolName: subscription.displaySymbolName,
                color: subscription.isActive ? subscription.displayColor : .gray
            )
        } title: {
            Text(subscription.name)
                .font(.body.weight(.medium))
            Text(intervalText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } detail: {
            // Delte abonnement viser brukerens del, slik at raden stemmer med totalene.
            Text(subscription.myShare.formatted(.currency(code: subscription.currencyCode)))
                .font(.body.weight(.medium))
            Text(renewalText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(subscription.isActive ? 1 : 0.5)
        .accessibilityElement(children: .combine)
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
            VStack(alignment: .leading, spacing: 6) {
                icon
                VStack(alignment: .leading, spacing: 2) { title }
                VStack(alignment: .leading, spacing: 2) { detail }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) { title }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) { detail }
            }
        }
    }
}

/// Rundt ikon som vokser med tekststørrelsen, men med et tak så det ikke tar over raden.
struct SubscriptionIcon: View {
    let symbolName: String
    let color: Color

    @ScaledMetric(relativeTo: .title3) private var diameter: CGFloat = 36

    private var cappedDiameter: CGFloat { min(diameter, 64) }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: cappedDiameter * 0.5))
            .foregroundStyle(.white)
            .frame(width: cappedDiameter, height: cappedDiameter)
            .background(color, in: Circle())
            // Ikonet er pynt; navnet sier hva raden er. Ellers leser VoiceOver f.eks. «Grid View».
            .accessibilityHidden(true)
    }
}

#Preview {
    List {
        SubscriptionRow(subscription: Subscription(name: "Netflix", price: 149, billingInterval: .monthly, category: .streaming))
        SubscriptionRow(subscription: Subscription(name: "Spotify Family", price: 279, category: .musikk, splitCount: 3))
        SubscriptionRow(subscription: Subscription(name: "Fitness24", price: 399, billingInterval: .monthly, category: .trening, isActive: false))
    }
}
