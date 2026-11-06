import Foundation

/// Leser innboksen med delte kvitteringer, gjør dem om til utkast og legger dem i køen til
/// `AddSubscriptionRouter`. Kalles hver gang appen blir aktiv. Brukeren ser utkastene i skjemaet og
/// godkjenner dem selv: ingenting legges inn i databasen herfra.
@MainActor
final class ReceiptInboxProcessor {
    static let shared = ReceiptInboxProcessor()

    private let inbox: () -> ReceiptInbox?
    private let makeDraft: (String) async -> SubscriptionDraft
    private let router: AddSubscriptionRouter

    /// Appen kan bli aktiv flere ganger mens en kvittering fortsatt tolkes. Da skal ingenting leses to ganger.
    private var isProcessing = false
    /// Kvitteringer som er tatt imot i denne økten. Står en fil igjen (sletting feilet), lages ikke et utkast til.
    private var handledIDs: Set<UUID> = []

    init(
        inbox: @escaping () -> ReceiptInbox? = { ReceiptInbox.appGroup() },
        makeDraft: @escaping (String) async -> SubscriptionDraft = { text in
            await ReceiptParser.draft(fromReceiptText: text)
        },
        router: AddSubscriptionRouter = .shared
    ) {
        self.inbox = inbox
        self.makeDraft = makeDraft
        self.router = router
    }

    /// Antall nye utkast som ble lagt i køen. Et kall mens et annet pågår, gjør ingenting og gir 0.
    /// Rekkefølgen er eldste kvittering først. Filen slettes først når utkastet ligger i køen, så en kvittering
    /// ikke går tapt hvis appen avsluttes underveis (verste fall er at den vises to ganger).
    @discardableResult
    func processInbox(now: Date = Date()) async -> Int {
        guard !isProcessing, let inbox = inbox() else { return 0 }
        isProcessing = true
        defer { isProcessing = false }

        var enqueued = 0
        for entry in inbox.entries(now: now) {
            if handledIDs.contains(entry.item.id) {
                inbox.remove(entry)
                continue
            }
            handledIDs.insert(entry.item.id)
            let draft = await makeDraft(entry.item.text)
            router.enqueue(draft)
            inbox.remove(entry)
            enqueued += 1
        }
        return enqueued
    }
}
