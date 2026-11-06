import SwiftUI

/// «Neste 30 dager»: én kolonne per uke med sum, og en prikk per dag. Dager med trekk har en
/// farget prikk (abonnementets farge). Et trykk på en dag viser trekkene den dagen.
struct UpcomingStripView: View {
    let subscriptions: [Subscription]

    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay: Date?

    private var strip: UpcomingStrip {
        ChargeSchedule.upcomingStrip(subscriptions: subscriptions) { amount, code in
            CurrencyConverter.convert(amount, from: code, to: mainCurrency, using: exchangeRates.rates)
        }
    }

    var body: some View {
        let strip = self.strip
        let selected = strip.days.first { $0.date == selectedDay && $0.hasCharges }

        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "Neste 30 dager",
                trailing: strip.chargeCount == 0 ? nil : Money.string(strip.total, code: mainCurrency, whole: true)
            )

            if strip.chargeCount == 0 {
                Text("Ingen trekk de neste 30 dagene.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(strip.weeks) { week in
                            WeekCell(week: week, currencyCode: mainCurrency, selectedDay: selectedDay) { day in
                                toggle(day)
                            }
                        }
                    }
                }
                // Skyggen til ikonene klippes ikke bort i kanten.
                .scrollClipDisabled()

                if let selected {
                    DayChargesView(day: selected, currencyCode: mainCurrency)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }

            if strip.excludedCount > 0 {
                Text("\(strip.excludedCount) trekk uten valutakurs er ikke tatt med i summene.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .sensoryFeedback(.selection, trigger: selectedDay)
        .accessibilityElement(children: .contain)
        .onAppear {
            // Skjermbilder i CI (bare demomodus): velger første dag med trekk.
            if DemoLaunch.selectsFirstDay, selectedDay == nil {
                selectedDay = self.strip.days.first { $0.hasCharges }?.date
            }
        }
    }

    private func toggle(_ day: ChargeDay) {
        guard day.hasCharges else { return }
        withAnimation(reduceMotion ? nil : .smooth) {
            selectedDay = selectedDay == day.date ? nil : day.date
        }
    }
}

/// Én uke i stripen: datoene, summen og sju dagsprikker.
private struct WeekCell: View {
    let week: ChargeWeek
    let currencyCode: String
    let selectedDay: Date?
    let onSelect: (ChargeDay) -> Void

    @ScaledMetric(relativeTo: .caption) private var dayWidth: CGFloat = 22

    private var rangeText: String {
        let calendar = Calendar.current
        let first = week.firstDay
        let last = week.lastDay
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            let day = first.formatted(.dateTime.day())
            return "\(day)–\(last.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return "\(first.formatted(.dateTime.day().month(.abbreviated)))–\(last.formatted(.dateTime.day().month(.abbreviated)))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if week.chargeCount == 0 {
                Text("Ingen trekk")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 24, alignment: .leading)
            } else {
                Text(Money.string(week.total, code: currencyCode, whole: true))
                    .font(.amount(.title3, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 2) {
                ForEach(week.days) { day in
                    DayDot(day: day, width: dayWidth, isSelected: day.date == selectedDay) {
                        onSelect(day)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// En dag i stripen. Dager uten trekk er en liten grå prikk; dager med trekk er en farget
/// prikk, og to overlappende ved flere trekk.
private struct DayDot: View {
    let day: ChargeDay
    let width: CGFloat
    let isSelected: Bool
    let action: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(day.date) }

    private var accessibilityText: String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard day.hasCharges else { return "\(date), ingen trekk" }
        let names = day.charges.map(\.subscription.name).formatted()
        return "\(date), \(day.charges.count) trekk: \(names)"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                dot
                    .frame(height: 16)
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.primary : Color.secondary)
            }
            .frame(width: width, height: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!day.hasCharges)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(day.hasCharges ? "Viser trekkene denne dagen." : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var dot: some View {
        if let first = day.charges.first {
            ZStack {
                if day.charges.count > 1, let second = day.charges.dropFirst().first {
                    Circle()
                        .fill(second.subscription.displayColor)
                        .frame(width: 12, height: 12)
                        .offset(x: 4)
                }
                Circle()
                    .fill(first.subscription.displayColor)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().strokeBorder(Color.surface, lineWidth: 1.5) }
                    .offset(x: day.charges.count > 1 ? -3 : 0)
            }
        } else {
            Circle()
                .fill(Color.primary.opacity(isToday ? 0.45 : 0.18))
                .frame(width: 5, height: 5)
        }
    }
}

/// Trekkene på en valgt dag.
private struct DayChargesView: View {
    let day: ChargeDay
    let currencyCode: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(day.charges) { charge in
                let subscription = charge.subscription
                HStack(spacing: 10) {
                    SubscriptionTile(
                        symbolName: subscription.displaySymbolName,
                        color: subscription.displayColor,
                        size: 30
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        Text(subscription.name)
                            .font(.subheadline.weight(.semibold))
                        if charge.isTrialEnd {
                            Text("Prøveperioden slutter")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Money.string(subscription.myShare, code: subscription.currencyCode))
                        .font(.amount(.subheadline))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 2)
    }
}
