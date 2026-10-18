import AppIntents
import Foundation

/// Snarveien «Legg til abonnement»: åpner appen med et utfylt skjema. Abonnementet lagres
/// ikke i bakgrunnen, så brukeren får samme validering, varseltillatelse og bekreftelse som
/// ellers, og ingen halvferdige abonnementer havner i databasen.
///
/// `nonisolated` fordi `AppIntent` arver `Sendable`, så samsvaret og de statiske kravene ikke
/// kan være bundet til hovedaktøren, som er standard i app-targeten. Bare `perform()` kjører
/// på hovedaktøren, der skjemaets ruter bor.
///
/// `@Parameter`-egenskapene er `@MainActor`: ellers arver de `nonisolated` fra typen, og det
/// godtar ikke kompilatoren for egenskaper med property wrapper (feil i Swift 6). `$name` osv.
/// arver fortsatt `nonisolated`, så nøkkelstiene i `parameterSummary` virker som før.
nonisolated struct AddSubscriptionIntent: AppIntent {
    static let title: LocalizedStringResource = "Legg til abonnement"

    // Typen må være valgfri som i kravet, ellers brukes standardverdien nil.
    static let description: IntentDescription? = IntentDescription("Åpner Subtrack med et nytt abonnement fylt ut.")

    /// Åpner appen før `perform()` kjører på iOS 17–25. Er utfaset fra iOS 26, men gir ingen
    /// advarsel så lenge minste versjon er under 26; da overtar `supportedModes` under.
    /// Fjernes når minste versjon blir iOS 26.
    static var openAppWhenRun: Bool { true }

    /// Appen kommer i forgrunnen før handlingen kjører (iOS 26 og nyere).
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    // Navnet kan ikke stå i Siri-frasen (bare `AppEntity` og `AppEnum` kan det), så Siri spør etter det.
    @MainActor @Parameter(title: "Navn", requestValueDialog: IntentDialog("Hva heter abonnementet?"))
    var name: String

    @MainActor @Parameter(title: "Pris")
    var price: Double?

    @MainActor @Parameter(title: "Fornyes")
    var interval: ShortcutIntervalOption?

    @MainActor @Parameter(title: "Kategori")
    var category: ShortcutCategoryOption?

    // Bare dato: skjemaet setter klokkeslettet til kl. 12 når abonnementet lagres.
    @MainActor @Parameter(title: "Neste fornyelse", kind: .date)
    var nextRenewalDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Legg til \(\.$name)") {
            \.$price
            \.$interval
            \.$category
            \.$nextRenewalDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let draft = ShortcutDraftBuilder.makeDraft(
            name: name,
            price: price,
            interval: interval?.value,
            category: category?.value,
            nextRenewalDate: nextRenewalDate
        )
        AddSubscriptionRouter.shared.enqueue(draft)
        return .result()
    }
}
