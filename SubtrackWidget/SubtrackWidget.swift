import WidgetKit
import SwiftUI
import UIKit

/// Speiler `WidgetSnapshotStore.UpcomingRenewal` i app-targetet. Appen og widgeten
/// er separate prosesser som bare deler JSON-formatet - endres feltene her, må
/// tilsvarende endring gjøres i appen.
struct UpcomingRenewal: Codable, Identifiable {
    let name: String
    let price: Decimal
    let currencyCode: String
    let symbolName: String
    /// Valgfri så data skrevet av eldre app-versjoner fortsatt kan leses.
    let colorHex: String?
    let renewalDate: Date
    /// Valgfri av samme grunn som `colorHex`; `nil` behandles som en vanlig fornyelse.
    let isTrialEnd: Bool?

    var id: String { "\(name)-\(renewalDate.timeIntervalSince1970)" }

    var color: Color {
        colorHex.flatMap(Color.palette(hex:)) ?? .accentColor
    }
}

// Samme som i app-targetet; de to targetene deler ikke kildefiler.
extension Color {
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        // Tilordning i stedet for self.init(...): Xcode-previews klarer ikke å kompilere
        // delegerende init i denne filen.
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// Speiler `SubscriptionAppearance.color(forHex:)` i app-targetet: oransje, grønn og turkis
// får bare ca. 2:1 mot hvit bakgrunn og får en mørkere variant i lys modus (over 4:1).
// Mørk modus bruker den lagrede fargen. Begrunnelsen står i appen. Endres fargene eller
// verdiene her, må samme endring gjøres i appen.
private extension Color {
    static func palette(hex: String) -> Color? {
        let digits = (hex.hasPrefix("#") ? String(hex.dropFirst()) : hex).uppercased()
        return switch digits {
        case "FF9F0A": Color.adaptive(light: 0xC75C00, dark: 0xFF9F0A)
        case "30D158": Color.adaptive(light: 0x248A3D, dark: 0x30D158)
        case "40C8E0": Color.adaptive(light: 0x008299, dark: 0x40C8E0)
        default: Color(hex: hex)
        }
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            Color.rgbColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func rgbColor(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum RenewalSnapshotReader {
    private static let appGroupID = "group.com.opland.subtrack"
    private static let snapshotKey = "upcomingRenewals"

    static func load() -> [UpcomingRenewal] {
        guard
            let data = UserDefaults(suiteName: appGroupID)?.data(forKey: snapshotKey),
            let renewals = try? JSONDecoder().decode([UpcomingRenewal].self, from: data)
        else { return [] }
        return renewals
    }
}

/// Summen av trekkene resten av måneden, bare når de alle er i samme valuta.
struct MonthSum {
    let amount: Decimal
    let currencyCode: String
    let count: Int
}

struct RenewalEntry: TimelineEntry {
    let date: Date
    let renewals: [UpcomingRenewal]
    var monthSum: MonthSum? = nil
}

struct Provider: TimelineProvider {
    /// Hvor mange døgn frem tidslinjen bygges. Etterpå ber widgeten om en ny.
    private let daysInTimeline = 7

    func placeholder(in context: Context) -> RenewalEntry {
        entry(for: .now, from: UpcomingRenewal.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (RenewalEntry) -> Void) {
        let renewals = context.isPreview ? UpcomingRenewal.samples : RenewalSnapshotReader.load()
        completion(entry(for: .now, from: renewals))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RenewalEntry>) -> Void) {
        let renewals = RenewalSnapshotReader.load()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)

        // Én oppføring per midnatt, så "om X dager" teller ned uten at appen må åpnes.
        let entries = (0..<daysInTimeline).compactMap { offset -> RenewalEntry? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { return nil }
            return entry(for: offset == 0 ? .now : day, from: renewals)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    func entry(for date: Date, from renewals: [UpcomingRenewal]) -> RenewalEntry {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let upcoming = renewals.filter { calendar.startOfDay(for: $0.renewalDate) >= startOfDay }

        // Resten av måneden. Øyeblikksbildet har bare noen få trekk per abonnement, men nok til en måned.
        let thisMonth = upcoming.filter { calendar.isDate($0.renewalDate, equalTo: date, toGranularity: .month) }
        let currencies = Set(thisMonth.map(\.currencyCode))
        var monthSum: MonthSum?
        if currencies.count == 1, let currencyCode = currencies.first {
            monthSum = MonthSum(
                amount: thisMonth.reduce(Decimal(0)) { $0 + $1.price },
                currencyCode: currencyCode,
                count: thisMonth.count
            )
        }
        return RenewalEntry(date: date, renewals: Array(upcoming.prefix(3)), monthSum: monthSum)
    }
}

/// Forskjellen mellom i dag og trekkdatoen, som tekst.
private func dueText(for renewal: UpcomingRenewal, from referenceDate: Date) -> String {
    let calendar = Calendar.current
    let days = calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: referenceDate),
        to: calendar.startOfDay(for: renewal.renewalDate)
    ).day ?? 0

    if renewal.isTrialEnd == true {
        return switch days {
        case ..<1: "Prøve slutter i dag"
        case 1: "Prøve slutter i morgen"
        default: "Prøve slutter om \(days) dager"
        }
    }
    return switch days {
    case ..<1: "I dag"
    case 1: "I morgen"
    default: "Om \(days) dager"
    }
}

/// Ikonflisen fra appen: abonnementets farge med en myk gradient og et hvitt symbol.
private struct WidgetTile: View {
    let symbolName: String
    let color: Color
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        shape
            .fill(color)
            .overlay {
                shape.fill(LinearGradient(
                    colors: [.white.opacity(0.28), .white.opacity(0), .black.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

struct SubtrackWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: RenewalEntry

    private var isLarge: Bool {
        family == .systemMedium
    }

    /// Widgeten har fast størrelse, så ved store tekststørrelser vises færre rader
    /// i stedet for at innholdet kuttes.
    private var maxListRows: Int {
        dynamicTypeSize >= .xLarge ? 1 : 2
    }

    var body: some View {
        Group {
            if let next = entry.renewals.first {
                if isLarge {
                    HStack(alignment: .top, spacing: 16) {
                        NextCharge(renewal: next, referenceDate: entry.date, monthSum: nil)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(entry.renewals.dropFirst().prefix(maxListRows)) { renewal in
                                CompactRow(renewal: renewal, referenceDate: entry.date)
                            }
                            Spacer(minLength: 0)
                            MonthFooter(monthSum: entry.monthSum)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        NextCharge(renewal: next, referenceDate: entry.date, monthSum: entry.monthSum)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Neste trekk", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("Ingen kommende trekk")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Det neste trekket, stort: ikon, navn, beløp og når det trekkes. Med summen for måneden nederst i den lille widgeten.
private struct NextCharge: View {
    let renewal: UpcomingRenewal
    let referenceDate: Date
    let monthSum: MonthSum?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Neste trekk", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                WidgetTile(symbolName: renewal.symbolName, color: renewal.color, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(renewal.name)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .lineLimit(1)
                    Text(dueText(for: renewal, from: referenceDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(renewal.price.formatted(.currency(code: renewal.currencyCode).precision(.fractionLength(0...2))))
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            if monthSum != nil {
                MonthFooter(monthSum: monthSum)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Et trekk til i listen på den mellomstore widgeten.
private struct CompactRow: View {
    let renewal: UpcomingRenewal
    let referenceDate: Date

    var body: some View {
        HStack(spacing: 8) {
            WidgetTile(symbolName: renewal.symbolName, color: renewal.color, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(renewal.name)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text(dueText(for: renewal, from: referenceDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(renewal.price.formatted(.currency(code: renewal.currencyCode).precision(.fractionLength(0...2))))
                .font(.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit())
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// «Resten av måneden» med summen av trekkene, når den er kjent.
private struct MonthFooter: View {
    let monthSum: MonthSum?

    var body: some View {
        if let monthSum {
            VStack(alignment: .leading, spacing: 0) {
                Text("Resten av måneden")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(monthSum.amount.formatted(.currency(code: monthSum.currencyCode).precision(.fractionLength(0))))
                    .font(.system(.footnote, design: .rounded, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct SubtrackWidget: Widget {
    let kind = "SubtrackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SubtrackWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    // Svak gradient i fargen til neste trekk, over widgetens vanlige bakgrunn.
                    let color = entry.renewals.first?.color ?? Color.accentColor
                    ZStack {
                        Rectangle().fill(.fill.tertiary)
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
        }
        .configurationDisplayName("Neste trekk")
        .description("Viser neste trekk og hva som trekkes resten av måneden.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension UpcomingRenewal {
    static let samples: [UpcomingRenewal] = [
        UpcomingRenewal(name: "Netflix", price: 149, currencyCode: "NOK", symbolName: "play.tv", colorHex: "#FF453A", renewalDate: .now.addingTimeInterval(86_400), isTrialEnd: true),
        UpcomingRenewal(name: "Spotify", price: 129, currencyCode: "NOK", symbolName: "music.note", colorHex: "#30D158", renewalDate: .now.addingTimeInterval(86_400 * 4), isTrialEnd: false),
        UpcomingRenewal(name: "iCloud+", price: 39, currencyCode: "NOK", symbolName: "icloud", colorHex: nil, renewalDate: .now.addingTimeInterval(86_400 * 9), isTrialEnd: nil)
    ]
}

#Preview("Liten", as: .systemSmall) {
    SubtrackWidget()
} timeline: {
    Provider().entry(for: .now, from: UpcomingRenewal.samples)
    RenewalEntry(date: .now, renewals: [])
}

#Preview("Mellomstor", as: .systemMedium) {
    SubtrackWidget()
} timeline: {
    Provider().entry(for: .now, from: UpcomingRenewal.samples)
}
