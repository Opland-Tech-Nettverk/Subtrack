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

struct RenewalEntry: TimelineEntry {
    let date: Date
    let renewals: [UpcomingRenewal]
}

struct Provider: TimelineProvider {
    /// Hvor mange døgn frem tidslinjen bygges. Etterpå ber widgeten om en ny.
    private let daysInTimeline = 7

    func placeholder(in context: Context) -> RenewalEntry {
        RenewalEntry(date: .now, renewals: UpcomingRenewal.samples)
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

    private func entry(for date: Date, from renewals: [UpcomingRenewal]) -> RenewalEntry {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let upcoming = renewals.filter { calendar.startOfDay(for: $0.renewalDate) >= startOfDay }
        return RenewalEntry(date: date, renewals: Array(upcoming.prefix(3)))
    }
}

struct SubtrackWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: RenewalEntry

    private var isSmall: Bool { family == .systemSmall }

    /// Widgeten har fast størrelse, så ved store tekststørrelser vises færre rader
    /// i stedet for at innholdet kuttes.
    private var maxRows: Int {
        if dynamicTypeSize.isAccessibilitySize { return isSmall ? 1 : 2 }
        if dynamicTypeSize >= .xLarge { return isSmall ? 1 : 3 }
        return isSmall ? 2 : 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Neste trekk")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if entry.renewals.isEmpty {
                Spacer(minLength: 0)
                Text("Ingen kommende trekk")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.renewals.prefix(maxRows)) { renewal in
                    RenewalRow(renewal: renewal, referenceDate: entry.date, showsPrice: !isSmall)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RenewalRow: View {
    let renewal: UpcomingRenewal
    let referenceDate: Date
    let showsPrice: Bool

    private var dueText: String {
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: renewal.symbolName)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(renewal.color, in: Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(renewal.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(dueText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if showsPrice {
                Spacer(minLength: 4)
                Text(renewal.price.formatted(.currency(code: renewal.currencyCode)))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SubtrackWidget: Widget {
    let kind = "SubtrackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SubtrackWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Neste trekk")
        .description("Viser abonnementene som fornyes snart.")
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
    RenewalEntry(date: .now, renewals: UpcomingRenewal.samples)
    RenewalEntry(date: .now, renewals: [])
}

#Preview("Mellomstor", as: .systemMedium) {
    SubtrackWidget()
} timeline: {
    RenewalEntry(date: .now, renewals: UpcomingRenewal.samples)
}
