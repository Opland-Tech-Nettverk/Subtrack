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
    /// Kvitteringer som er satt i kø i denne økten. Filen blir stående til skjemaet er lagret eller forkastet, så
    /// den må ikke settes i kø en gang til før appen er startet på nytt.
    private var handledIDs: Set<UUID> = []

    init(
        inbox: @escaping () -> ReceiptInbox? = { ReceiptInbox.appGroup() },
        makeDraft: @escaping (String) async -> SubscriptionDraft = { text in
            await ReceiptParser.draft(fromReceiptText: text)
        },
        router: AddSubscriptionRouter? = nil
    ) {
        self.inbox = inbox
        self.makeDraft = makeDraft
        self.router = router ?? AddSubscriptionRouter.shared
    }

    /// Antall nye utkast som ble lagt i køen. Et kall mens et annet pågår, gjør ingenting og gir 0.
    /// Rekkefølgen er eldste kvittering først. Filen slettes ikke her: den slettes av `finish` når skjemaet er
    /// lagret eller forkastet. Avsluttes appen før det, ligger filen der ved neste oppstart, og kvitteringen vises
    /// på nytt. Filer eldre enn 7 dager slettes av innboksen uansett.
    @discardableResult
    func processInbox(now: Date = Date()) async -> Int {
        guard !isProcessing, let inbox = inbox() else { return 0 }
        isProcessing = true
        defer { isProcessing = false }

        var enqueued = 0
        for entry in inbox.entries(now: now) {
            guard !handledIDs.contains(entry.item.id) else { continue }
            handledIDs.insert(entry.item.id)
            var draft = await makeDraft(entry.item.text)
            draft.receiptInboxID = entry.item.id
            router.enqueue(draft)
            enqueued += 1
        }
        return enqueued
    }

    /// Sletter filen til en kvittering når brukeren er ferdig med utkastet (lagret eller forkastet).
    /// Utkast som ikke kom fra innboksen, gjør ingenting.
    func finish(_ draft: SubscriptionDraft) {
        guard let id = draft.receiptInboxID else { return }
        inbox()?.remove(id: id)
    }
}
