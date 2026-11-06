import SwiftUI

/// Detaljsiden til et abonnement: toppen i abonnementets farge, nedtelling til neste trekk,
/// pris per trekk, måned og år, lenke for oppsigelse og knapper for pause og avslutt.
/// Endringer går gjennom funksjonene fra oversikten, så de får samme haptikk, angre-banner og
/// VoiceOver-beskjed som sveipene i listen.
struct SubscriptionDetailView: View {
    let subscription: Subscription
    let onEdit: () -> Void
    let onTogglePause: () -> Void
    let onArchive: () -> Void

    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var priceSize: CGFloat = 38

    private var color: Color { Color.tile(for: subscription) }

    private var unitText: String {
        switch subscription.interval {
        case .weekly: "per uke"
        case .monthly: "per måned"
        case .quarterly: "per kvartal"
        case .yearly: "per år"
        }
    }

    private var isTrial: Bool { subscription.isActive && subscription.isInTrial() }

    /// Beløpet omregnet til hovedvalutaen, når abonnementet har en annen valuta og kursen er kjent.
    private func converted(_ amount: Decimal) -> String? {
        guard subscription.currencyCode != mainCurrency,
              let value = CurrencyConverter.convert(
                  amount, from: subscription.currencyCode, to: mainCurrency, using: exchangeRates.rates
              )
        else { return nil }
        return Money.string(value, code: mainCurrency)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    header
                    costCard
                    scheduleCard
                    cancelCard
                    if let note = subscription.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        noteCard(note)
                    }
                    actions
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .task { await DemoLaunch.scroll(proxy) }
        }
        .background(alignment: .top) {
            // Toppen i abonnementets farge: en myk gradient som går ut mot bakgrunnen.
            LinearGradient(
                colors: [color.opacity(0.38), color.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 380)
            .ignoresSafeArea(edges: .top)
        }
        .background(Color.canvas)
        .navigationTitle(subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Rediger", action: onEdit)
            }
        }
    }

    // MARK: - Toppen

    private var header: some View {
        VStack(spacing: 10) {
            SubscriptionTile(
                symbolName: subscription.displaySymbolName,
                color: color,
                progress: subscription.isActive ? subscription.renewalProgress() : nil,
                isDimmed: !subscription.isActive,
                size: 72
            )
            .padding(.top, 8)

            Text(subscription.name)
                .font(.rounded(.title))
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Text(subscription.kind.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !subscription.isActive {
                    Badge(text: "Pauset", symbol: "pause.fill", tint: .gray)
                }
                if isTrial {
                    Badge(text: "Prøveperiode", symbol: "hourglass", tint: .orange)
                }
            }

            VStack(spacing: 0) {
                Text(Money.string(subscription.myShare, code: subscription.currencyCode))
                    .font(.system(size: priceSize, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(subscription.isShared ? "\(unitText), din del" : unitText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if subscription.isActive {
                countdown
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var countdown: some View {
        VStack(spacing: 2) {
            Label(subscription.renewalDescription(), systemImage: "calendar")
                .font(.headline)
            Text(subscription.nextRenewalDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.cardStroke, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Kort

    private var costCard: some View {
        DetailCard(title: "Kostnad") {
            if subscription.isShared {
                InfoRow(label: "Full pris", value: Money.string(subscription.price, code: subscription.currencyCode))
                InfoRow(label: "Delt på", value: "\(subscription.splitCount) personer")
            }
            InfoRow(label: "Per trekk", value: Money.string(subscription.myShare, code: subscription.currencyCode))
            InfoRow(
                label: "Per måned",
                value: Money.string(subscription.monthlyCost, code: subscription.currencyCode),
                secondary: converted(subscription.monthlyCost).map { "≈ \($0)" }
            )
            InfoRow(
                label: "Per år",
                value: Money.string(subscription.yearlyCost, code: subscription.currencyCode),
                secondary: converted(subscription.yearlyCost).map { "≈ \($0)" }
            )
        }
    }

    private var scheduleCard: some View {
        DetailCard(title: "Kommende trekk") {
            if !subscription.isActive {
                Text("Abonnementet er pauset, så ingenting trekkes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subscription.upcomingRenewalDates(count: 3), id: \.self) { date in
                    InfoRow(
                        label: date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide)),
                        value: Money.string(subscription.myShare, code: subscription.currencyCode),
                        secondary: subscription.isTrialEnd(date) ? "Første betaling etter prøven" : nil
                    )
                }
                InfoRow(label: "Påminnelse", value: reminderText)
            }
        }
    }

    private var reminderText: String {
        switch subscription.reminderDaysBefore {
        case 0: "Samme dag"
        case 1: "1 dag før"
        default: "\(subscription.reminderDaysBefore) dager før"
        }
    }

    private var cancelCard: some View {
        DetailCard(title: "Si opp") {
            if let url = subscription.cancelURL {
                Link(destination: url) {
                    HStack {
                        Label("Gå til oppsigelsen", systemImage: "arrow.up.right.square")
                            .font(.body.weight(.medium))
                        Spacer(minLength: 8)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                Text(url.host() ?? url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ingen lenke for oppsigelse er lagt inn.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Legg til lenke", action: onEdit)
                    .font(.body.weight(.medium))
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    private func noteCard(_ note: String) -> some View {
        DetailCard(title: "Notat") {
            Text(note)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Knapper

    private var actions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button(action: onTogglePause) {
                Label(
                    subscription.isActive ? "Pause" : "Gjenoppta",
                    systemImage: subscription.isActive ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button(role: .destructive) {
                onArchive()
                dismiss()
            } label: {
                Label("Avslutt", systemImage: "archivebox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .padding(.top, 4)
    }
}

/// Et kort på detaljsiden, med overskrift og innhold under hverandre.
private struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.rounded(.headline))
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .card()
    }
}

/// Navn til venstre og verdi til høyre, med en valgfri forklaring under verdien. Stables ved store tekststørrelser.
private struct InfoRow: View {
    let label: String
    let value: String
    var secondary: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 1) {
                Text(value)
                    .font(.amount(.body))
                if let secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
