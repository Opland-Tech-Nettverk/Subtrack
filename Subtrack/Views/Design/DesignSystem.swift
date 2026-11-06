import SwiftUI

/// Felles stil for appen («Lommebok»): nøytral bakgrunn, kort med myk kant, SF Pro Rounded til
/// tall og beløp, og hvert abonnement i sin egen farge. Alt her er ren stil, uten data.
enum DS {
    // `nonisolated`: konstantene brukes også som standardverdier i parametere og fra konformanser
    // SwiftUI kan kjøre utenfor hovedtråden. Appen er ellers isolert til MainActor som standard.
    nonisolated static let cardRadius: CGFloat = 22
    nonisolated static let rowRadius: CGFloat = 18
    nonisolated static let cardPadding: CGFloat = 16
}

// MARK: - Farger

extension Color {
    /// Bakgrunnen bak kortene. Systemets grupperte bakgrunn følger lys og mørk modus selv.
    static let canvas = Color(uiColor: .systemGroupedBackground)
    /// Flaten et kort tegnes på.
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    /// Den tynne kanten rundt kort. Primærfargen med lav dekning gir mørk kant i lys modus og lys i mørk.
    static let cardStroke = Color.primary.opacity(0.07)
}

// MARK: - Tall og tekst

extension Font {
    /// Beløp og andre tall: SF Pro Rounded med tall i fast bredde, så de ikke hopper når de teller.
    /// Følger Dynamic Type som tekststilen den bygger på.
    static func amount(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }

    /// Overskrifter i seksjoner og kort: avrundet, så de passer sammen med tallene.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// Beløp i en valuta, riktig formatert for brukerens språk.
enum Money {
    /// `whole` runder av til hele kroner, for store tall som ikke trenger øre.
    static func string(_ amount: Decimal, code: String, whole: Bool = false) -> String {
        if whole {
            return amount.formatted(.currency(code: code).precision(.fractionLength(0)))
        }
        return amount.formatted(.currency(code: code))
    }
}

/// Lar tall rulle når de endres, men står stille når brukeren har valgt «Reduser bevegelse».
struct NumericMotion: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText(value: value))
            .animation(reduceMotion ? nil : .smooth, value: value)
    }
}

/// Animerer endringer av `value`, men ikke når brukeren har valgt «Reduser bevegelse».
struct MotionAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func motion<Value: Equatable>(_ animation: Animation = .smooth, value: Value) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }

    /// Tall som ruller når `value` endres.
    func numericMotion(_ value: Decimal) -> some View {
        modifier(NumericMotion(value: value.doubleValue))
    }
}

// MARK: - Kort

private struct CardSurface: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.cardStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

private struct GlassCardSurface: ViewModifier {
    let radius: CGFloat
    @AppStorage(AppSettingsKeys.glassIntensity) private var glassIntensity: Double = 0.6

    func body(content: Content) -> some View {
        content
            .adjustableGlassBackground(intensity: glassIntensity, cornerRadius: radius)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.cardStroke, lineWidth: 1)
            }
    }
}

extension View {
    /// Et kort: dekkende flate, myk kant og litt dybde.
    func card(radius: CGFloat = DS.cardRadius) -> some View {
        modifier(CardSurface(radius: radius))
    }

    /// Et kort med glass: Liquid Glass på iOS 26 og material før det, med styrke fra innstillingene.
    func glassCard(radius: CGFloat = DS.cardRadius) -> some View {
        modifier(GlassCardSurface(radius: radius))
    }
}

/// Bakgrunnen til en rad i en liste, for `listRowBackground`. Samme kant som `card()`, uten skygge
/// (listen klipper den).
struct RowCardBackground: View {
    var radius: CGFloat = DS.rowRadius
    /// Fremhevet kant i aksentfargen, f.eks. for en valgt rad.
    var isHighlighted = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.surface)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isHighlighted ? Color.accentColor.opacity(0.45) : Color.cardStroke, lineWidth: isHighlighted ? 1.25 : 1)
            }
    }
}

extension View {
    /// En rad i en liste som eget kort: kortbakgrunn med luft mellom radene, uten skillelinje.
    /// Listen bør bruke `.insetGrouped` og skjult bakgrunn (`scrollContentBackground(.hidden)`).
    func cardRowStyle(isHighlighted: Bool = false) -> some View {
        listRowBackground(RowCardBackground(isHighlighted: isHighlighted).padding(.vertical, 4))
            .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .listRowSeparator(.hidden)
    }

    /// En rad som fyller bredden uten egen bakgrunn, for kort som tegner seg selv (hero, stripe).
    func bareRowStyle() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

/// Overskrift over en gruppe, med en valgfri tekst til høyre (f.eks. en sum).
struct SectionTitle: View {
    let title: String
    var trailing: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let trailing {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                titleText
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                Text(trailing)
                    .font(.amount(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .textCase(nil)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } else {
            titleText
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.rounded(.title3))
            .foregroundStyle(Color.primary)
    }
}

// MARK: - Merker

/// Liten kapsel med valgfritt symbol, brukt for prøveperiode, pauset, valuta og delt kostnad.
/// Teksten er alltid primærfarge, så kontrasten er god uansett hvilken farge merket har; fargen
/// ligger i symbolet og den svake bakgrunnen.
struct Badge: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.primary.opacity(0.85))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.16), in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Ikonflis

extension Color {
    /// Fargen til et abonnement i en liste: sin egen farge, eller grå når det er pauset.
    static func tile(for subscription: Subscription) -> Color {
        subscription.isActive ? subscription.displayColor : .gray
    }
}

/// Abonnementets ikon på en avrundet flis i abonnementets farge (med en myk gradient), og
/// eventuelt en ring rundt som viser hvor langt det er til neste trekk.
struct SubscriptionTile: View {
    let symbolName: String
    let color: Color
    /// 0...1 for ringen rundt flisa, eller `nil` uten ring.
    var progress: Double? = nil
    var isDimmed = false
    /// Setter av plass til ringen også uten fremdrift, så fliser står likt på tvers av rader.
    var reservesRing = false

    @ScaledMetric private var tileSide: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        symbolName: String, color: Color, progress: Double? = nil, isDimmed: Bool = false,
        reservesRing: Bool = false, size: CGFloat = 40
    ) {
        self.reservesRing = reservesRing
        self.symbolName = symbolName
        self.color = color
        self.progress = progress
        self.isDimmed = isDimmed
        _tileSide = ScaledMetric(wrappedValue: size, relativeTo: .title3)
    }

    /// Flisa vokser med tekststørrelsen, men med et tak så den ikke tar over raden.
    private var side: CGFloat { min(tileSide, 76) }
    private var ringWidth: CGFloat { max(2.5, side * 0.07) }
    private var ringGap: CGFloat { 3 }
    private var outerSide: CGFloat {
        (progress == nil && !reservesRing) ? side : side + 2 * (ringWidth + ringGap)
    }

    var body: some View {
        ZStack {
            if progress != nil || reservesRing {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: ringWidth)
            }
            if let progress {
                Circle()
                    .trim(from: 0, to: max(progress, 0.015))
                    .stroke(color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .smooth, value: progress)
            }
            tile
        }
        .frame(width: outerSide, height: outerSide)
        .opacity(isDimmed ? 0.55 : 1)
        // Ikonet er pynt; navnet sier hva det er. Ellers leser VoiceOver f.eks. «Grid View».
        .accessibilityHidden(true)
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
        return shape
            .fill(color)
            .overlay {
                // Lys fra toppen og litt skygge nederst gir flisa dybde uten å endre selve fargen.
                shape.fill(LinearGradient(
                    colors: [.white.opacity(0.28), .white.opacity(0), .black.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
            }
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: side * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .frame(width: side, height: side)
            .shadow(color: color.opacity(0.3), radius: 5, y: 2)
    }
}

// MARK: - Tekst om fornyelse

extension Subscription {
    /// «I dag», «I morgen», «Om 5 dager», og tilsvarende for prøveperioder og pauser.
    func renewalDescription(now: Date = .now) -> String {
        guard isActive else { return "Pauset" }
        let days = daysUntilRenewal(today: now)
        if isInTrial(today: now) {
            return switch days {
            case ..<1: "Prøve slutter i dag"
            case 1: "Prøve slutter i morgen"
            default: "Prøve slutter om \(days) dager"
            }
        }
        return switch days {
        case ..<0: "Forfalt"
        case 0: "I dag"
        case 1: "I morgen"
        default: "Om \(days) dager"
        }
    }
}
