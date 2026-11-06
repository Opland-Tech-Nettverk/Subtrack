import Foundation

/// Følger med på hvilket utkast som har et ark åpent eller er i ferd med å lukkes, så riktig kvitteringsfil slettes
/// og neste utkast ikke vises for tidlig.
///
/// SwiftUI setter `item`-bindingen til nil så snart lukkingen starter, men kaller `onDismiss` først når animasjonen
/// (ca. 0,3 s) er ferdig. I mellomtiden kan neste utkast være klart. Vises det da, er det feil utkast som er
/// «sist vist» når `onDismiss` kommer, og filen til utkastet som nettopp er åpnet, slettes. Derfor vises ikke neste
/// utkast før `dismissed()` er kalt.
struct DraftSheetTracker {
    /// Utkastet som ble vist og ennå ikke er meldt lukket.
    private(set) var awaitingDismiss: SubscriptionDraft?
    /// Lagringen feilet: kvitteringsfilen skal bli stående, så kvitteringen kommer tilbake ved neste oppstart.
    private(set) var keepsFile = false

    /// Sant når ingen ark venter på å bli lukket, så et nytt utkast kan vises.
    var isFree: Bool { awaitingDismiss == nil }

    mutating func presented(_ draft: SubscriptionDraft) {
        awaitingDismiss = draft
        keepsFile = false
    }

    /// Lagringen av utkastet feilet. Filen slettes ikke når arket lukkes.
    mutating func saveFailed() {
        keepsFile = true
    }

    /// Arket er helt lukket. Gir utkastet som skal ferdigbehandles (filen slettes), eller nil hvis ingen ark ventet
    /// eller lagringen feilet.
    mutating func dismissed() -> SubscriptionDraft? {
        defer {
            awaitingDismiss = nil
            keepsFile = false
        }
        return keepsFile ? nil : awaitingDismiss
    }
}
