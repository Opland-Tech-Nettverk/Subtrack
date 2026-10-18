import AppIntents

// Egne typer for snarveien, så `BillingInterval` og `SubscriptionCategory` slipper å bli `AppEnum`.
// `AppEnum` arver `Sendable` og `SendableMetatype`, så samsvaret kan ikke være bundet til
// hovedaktøren, som er standard i app-targeten. Typene er derfor `nonisolated`, og `value` er
// en ren `switch` som ikke kaller kode på hovedaktøren. Rå verdier og visningsnavn er de samme
// som i modellen; `ShortcutDraftBuilderTests` sjekker at ingen tilfeller mangler.

/// Intervallene snarveien «Legg til abonnement» kan velge mellom.
nonisolated enum ShortcutIntervalOption: String, AppEnum {
    case weekly
    case monthly
    case quarterly
    case yearly

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Intervall"

    static let caseDisplayRepresentations: [ShortcutIntervalOption: DisplayRepresentation] = [
        .weekly: "Ukentlig",
        .monthly: "Månedlig",
        .quarterly: "Kvartalsvis",
        .yearly: "Årlig"
    ]

    var value: BillingInterval {
        switch self {
        case .weekly: .weekly
        case .monthly: .monthly
        case .quarterly: .quarterly
        case .yearly: .yearly
        }
    }
}

/// Kategoriene snarveien «Legg til abonnement» kan velge mellom.
nonisolated enum ShortcutCategoryOption: String, AppEnum {
    case streaming
    case musikk
    case programvare
    case trening
    case nettsky
    case nyheter
    case boker
    case spill
    case ai
    case annet

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kategori"

    static let caseDisplayRepresentations: [ShortcutCategoryOption: DisplayRepresentation] = [
        .streaming: "Streaming",
        .musikk: "Musikk",
        .programvare: "Programvare",
        .trening: "Trening",
        .nettsky: "Nettsky",
        .nyheter: "Nyheter",
        .boker: "Bøker og lydbøker",
        .spill: "Spill",
        .ai: "AI",
        .annet: "Annet"
    ]

    var value: SubscriptionCategory {
        switch self {
        case .streaming: .streaming
        case .musikk: .musikk
        case .programvare: .programvare
        case .trening: .trening
        case .nettsky: .nettsky
        case .nyheter: .nyheter
        case .boker: .boker
        case .spill: .spill
        case .ai: .ai
        case .annet: .annet
        }
    }
}
