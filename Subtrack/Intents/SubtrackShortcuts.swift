import AppIntents

/// Snarveiene som er klare i Snarveier, Spotlight og Siri uten oppsett.
/// Hver frase må inneholde appnavnet. Siri følger Siri-språket, så de norske frasene
/// virker med norsk Siri.
///
/// `nonisolated` av samme grunn som `AddSubscriptionIntent`: kravene i `AppShortcutsProvider`
/// kan ikke være bundet til hovedaktøren.
nonisolated struct SubtrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddSubscriptionIntent(),
            phrases: [
                "Legg til abonnement i \(.applicationName)",
                "Nytt abonnement i \(.applicationName)",
                "Registrer et abonnement i \(.applicationName)"
            ],
            shortTitle: "Legg til abonnement",
            systemImageName: "plus.circle"
        )
    }
}
