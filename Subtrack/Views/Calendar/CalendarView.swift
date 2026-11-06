import SwiftUI
import SwiftData

/// Kalenderfanen: en måned om gangen med prikker på trekkdagene, og en tidslinje over månedens
/// trekk med totalsum. Et trykk på en dag viser bare den dagens trekk.
struct CalendarView: View {
    @Query private var subscriptions: [Subscription]
    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Starten av måneden som vises.
    @State private var month = MonthGrid.monthStart(offsetBy: 0, from: .now)
    @State private var selectedDay: Date?

    private var calendar: Calendar { .current }

    private var billing: [Subscription] {
        subscriptions.filter(\.isBilling)
    }

    private var charges: [ChargeOccurrence] {
        MonthGrid.charges(of: billing, inMonthOf: month)
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(month, equalTo: .now, toGranularity: .month)
    }

    private func convert(_ charge: ChargeOccurrence) -> Decimal? {
        CurrencyConverter.convert(
            charge.subscription.myShare,
            from: charge.subscription.currencyCode,
            to: mainCurrency,
            using: exchangeRates.rates
        )
    }

    var body: some View {
        let charges = self.charges
        let byDay = Dictionary(grouping: charges) { calendar.startOfDay(for: $0.date) }

        NavigationStack {
            Group {
                if billing.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen trekk å vise", systemImage: "calendar")
                    } description: {
                        Text("Når du har lagt inn abonnementer, ser du her hvilke dager de trekkes.")
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 16) {
                                monthCard(byDay: byDay)
                                timeline(charges: charges)
                                    .id("timeline")
                                Color.clear.frame(height: 1).id("end")
                            }
                            .frame(maxWidth: 640)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                            .frame(maxWidth: .infinity)
                        }
                        .task { await DemoLaunch.scroll(proxy) }
                    }
                }
            }
            .background(Color.canvas)
            .navigationTitle("Kalender")
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
        .sensoryFeedback(.selection, trigger: month)
    }

    // MARK: - Måneden

    private func monthCard(byDay: [Date: [ChargeOccurrence]]) -> some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            let cells = MonthGrid.cells(for: month)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            date: day,
                            charges: byDay[day] ?? [],
                            isSelected: day == selectedDay
                        ) {
                            withAnimation(.smooth) {
                                selectedDay = selectedDay == day ? nil : day
                            }
                        }
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .motion(.smooth, value: month)
        }
        .padding(DS.cardPadding)
        .glassCard()
    }

    private var monthHeader: some View {
        HStack(spacing: 4) {
            Text(month.formatted(.dateTime.month(.wide).year()).capitalizedFirst)
                .font(.rounded(.title3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if !isCurrentMonth {
                Button("I dag") { changeMonth(to: MonthGrid.monthStart(offsetBy: 0, from: .now)) }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            Button {
                changeMonth(to: MonthGrid.monthStart(offsetBy: -1, from: month))
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Forrige måned")
            Button {
                changeMonth(to: MonthGrid.monthStart(offsetBy: 1, from: month))
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Neste måned")
        }
        .font(.body.weight(.semibold))
    }

    private func changeMonth(to newMonth: Date) {
        selectedDay = nil
        month = newMonth
    }

    private var weekdayHeader: some View {
        // Kalenderens første ukedag styrer rekkefølgen, så uka starter på mandag i Norge.
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }

    // MARK: - Tidslinjen

    private func timeline(charges: [ChargeOccurrence]) -> some View {
        let visible = selectedDay.map { day in
            charges.filter { calendar.isDate($0.date, inSameDayAs: day) }
        } ?? charges
        var total = Decimal(0)
        var excluded = 0
        for charge in visible {
            if let amount = convert(charge) { total += amount } else { excluded += 1 }
        }

        return VStack(alignment: .leading, spacing: 14) {
            timelineHeader(total: total, count: visible.count)

            if visible.isEmpty {
                Text(selectedDay == nil ? "Ingen trekk denne måneden." : "Ingen trekk denne dagen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, charge in
                        TimelineRow(
                            charge: charge,
                            isLast: index == visible.count - 1,
                            showsDate: index == 0 || !calendar.isDate(visible[index - 1].date, inSameDayAs: charge.date)
                        )
                    }
                }
            }

            if excluded > 0 {
                Text("\(excluded) trekk uten valutakurs er ikke tatt med i summen.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .card()
    }

    private func timelineHeader(total: Decimal, count: Int) -> some View {
        let title: String
        if let selectedDay {
            title = selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))
        } else {
            title = "Trekk i \(month.formatted(.dateTime.month(.wide)))"
        }
        return VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title: title, trailing: count == 0 ? nil : Money.string(total, code: mainCurrency, whole: true))
            if selectedDay != nil {
                Button("Vis hele måneden") {
                    withAnimation(.smooth) { selectedDay = nil }
                }
                .font(.subheadline)
                .frame(minHeight: 44, alignment: .leading)
            } else if count > 0 {
                Text("\(count) trekk, samlet \(Money.string(total, code: mainCurrency, whole: true)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension Date {
    /// Dagens nummer uten ordenstegn: «6» i stedet for «6.».
    var dayNumberText: String {
        String(Calendar.current.component(.day, from: self))
    }
}

private extension String {
    /// «november 2026» blir «November 2026».
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// En dag i månedsrutenettet: dagens nummer og opptil tre prikker i abonnementenes farger.
private struct DayCell: View {
    let date: Date
    let charges: [ChargeOccurrence]
    let isSelected: Bool
    let action: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var accessibilityText: String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard !charges.isEmpty else { return text }
        let names = charges.map(\.subscription.name).formatted()
        return "\(text), \(charges.count) trekk: \(names)"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(date.dayNumberText)
                    .font(.amount(.callout, weight: isToday ? .bold : .regular))
                    .frame(minWidth: 30, minHeight: 30)
                    .background {
                        if isToday {
                            Circle().fill(Color.accentColor.opacity(0.2))
                        }
                    }
                    .overlay {
                        if isToday {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(charges.prefix(3).enumerated()), id: \.offset) { _, charge in
                        Circle()
                            .fill(charge.subscription.displayColor)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Et trekk på tidslinjen: dato til venstre, en linje med prikk i abonnementets farge, og navn og beløp.
private struct TimelineRow: View {
    let charge: ChargeOccurrence
    let isLast: Bool
    let showsDate: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var dateColumnWidth: CGFloat = 44

    private var subscription: Subscription { charge.subscription }
    private var isPast: Bool { Calendar.current.startOfDay(for: charge.date) < Calendar.current.startOfDay(for: .now) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                if showsDate {
                    Text(charge.date.dayNumberText)
                        .font(.amount(.title3, weight: .bold))
                    Text(charge.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: min(dateColumnWidth, 90))
            .accessibilityHidden(true)

            // Linjen fyller radens høyde (se `fixedSize` under); prikken ligger øverst på den.
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 2)
                        .padding(.top, 14)
                }
                Circle()
                    .fill(subscription.displayColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 8)
            }
            .frame(width: 10)
            .accessibilityHidden(true)

            content
                .padding(.bottom, isLast ? 0 : 16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isPast ? 0.65 : 1)
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            SubscriptionTile(symbolName: subscription.displaySymbolName, color: subscription.displayColor, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(subscription.name)
                    .font(.subheadline.weight(.semibold))
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 6)
            }
            Text(Money.string(subscription.myShare, code: subscription.currencyCode))
                .font(.amount(.subheadline))
        }
    }

    private var detailText: String {
        let date = charge.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if charge.isTrialEnd { return "Første betaling etter prøven" }
        return isPast ? "Trukket \(date)" : subscription.interval.displayName
    }
}

#Preview {
    let container = try! ModelContainer(for: Subscription.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let calendar = Calendar.current
    for subscription in [
        Subscription(name: "Netflix", price: 149, nextRenewalDate: calendar.date(byAdding: .day, value: 2, to: .now)!, category: .streaming, colorHex: "#FF453A"),
        Subscription(name: "Spotify", price: 129, nextRenewalDate: calendar.date(byAdding: .day, value: 9, to: .now)!, category: .musikk, colorHex: "#30D158"),
        Subscription(name: "iCloud+", price: 39, nextRenewalDate: calendar.date(byAdding: .day, value: 9, to: .now)!, category: .nettsky, colorHex: "#40C8E0")
    ] {
        container.mainContext.insert(subscription)
    }
    return CalendarView()
        .modelContainer(container)
        .environment(ExchangeRateStore())
}
