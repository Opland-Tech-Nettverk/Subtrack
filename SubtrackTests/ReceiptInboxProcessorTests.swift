import Foundation
import Testing
@testable import Subtrack

@MainActor
struct ReceiptInboxProcessorTests {

    // MARK: - Hjelpere

    private let fileManager = FileManager.default

    private func makeInbox() -> ReceiptInbox {
        ReceiptInbox(
            directory: fileManager.temporaryDirectory
                .appendingPathComponent("ReceiptInboxProcessorTests-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("Inbox", isDirectory: true)
        )
    }

    private func cleanUp(_ inbox: ReceiptInbox) {
        try? fileManager.removeItem(at: inbox.directory.deletingLastPathComponent())
    }

    private func files(in inbox: ReceiptInbox) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: inbox.directory.path)) ?? []).sorted()
    }

    /// Lager et utkast uten å tolke noe, og teller kallene.
    private final class DraftCounter {
        var texts: [String] = []
        func draft(for text: String) async -> SubscriptionDraft {
            texts.append(text)
            // Gir de andre kallene en sjanse til å starte mens dette står og venter.
            await Task.yield()
            return SubscriptionDraft(source: .receipt, name: text)
        }
    }

    // MARK: - Lese og sette i kø

    @Test func queuesOneDraftPerReceiptOldestFirstAndDeletesTheFiles() async throws {
        let inbox = makeInbox()
        defer { cleanUp(inbox) }
        let now = Date()
        try inbox.write(text: "første", kind: .text, now: now.addingTimeInterval(-20))
        try inbox.write(text: "andre", kind: .pdf, now: now.addingTimeInterval(-10))
        let router = AddSubscriptionRouter()
        let counter = DraftCounter()
        let processor = ReceiptInboxProcessor(inbox: { inbox }, makeDraft: { await counter.draft(for: $0) }, router: router)

        let count = await processor.processInbox(now: now)

        #expect(count == 2)
        #expect(router.pendingDrafts.map(\.name) == ["første", "andre"])
        #expect(files(in: inbox).isEmpty)
    }

    @Test func anEmptyInboxQueuesNothing() async {
        let inbox = makeInbox()
        let router = AddSubscriptionRouter()
        let processor = ReceiptInboxProcessor(inbox: { inbox }, makeDraft: { await DraftCounter().draft(for: $0) }, router: router)

        #expect(await processor.processInbox() == 0)
        #expect(!router.hasPendingDrafts)
    }

    @Test func aMissingAppGroupQueuesNothing() async {
        let router = AddSubscriptionRouter()
        let processor = ReceiptInboxProcessor(inbox: { nil }, makeDraft: { await DraftCounter().draft(for: $0) }, router: router)

        #expect(await processor.processInbox() == 0)
        #expect(!router.hasPendingDrafts)
    }

    @Test func corruptAndExpiredFilesAreNeverQueued() async throws {
        let inbox = makeInbox()
        defer { cleanUp(inbox) }
        let now = Date()
        try inbox.write(text: "gammel", kind: .text, now: now.addingTimeInterval(-8 * 24 * 3_600))
        try fileManager.createDirectory(at: inbox.directory, withIntermediateDirectories: true)
        let corrupt = inbox.directory.appendingPathComponent("corrupt.json")
        try Data("ikke json".utf8).write(to: corrupt)
        try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-3_600)], ofItemAtPath: corrupt.path)
        try inbox.write(text: "ny", kind: .text, now: now)
        let router = AddSubscriptionRouter()
        let processor = ReceiptInboxProcessor(inbox: { inbox }, makeDraft: { await DraftCounter().draft(for: $0) }, router: router)

        let count = await processor.processInbox(now: now)

        #expect(count == 1)
        #expect(router.pendingDrafts.map(\.name) == ["ny"])
    }

    // MARK: - Ikke to ganger

    @Test func twoRunsAtTheSameTimeQueueEachReceiptOnce() async throws {
        let inbox = makeInbox()
        defer { cleanUp(inbox) }
        try inbox.write(text: "kvittering", kind: .text)
        let router = AddSubscriptionRouter()
        let counter = DraftCounter()
        let processor = ReceiptInboxProcessor(inbox: { inbox }, makeDraft: { await counter.draft(for: $0) }, router: router)

        async let first = processor.processInbox()
        async let second = processor.processInbox()
        let total = await first + second

        #expect(total == 1)
        #expect(counter.texts == ["kvittering"])
        #expect(router.pendingDrafts.count == 1)
        #expect(files(in: inbox).isEmpty)
    }

    @Test func aReceiptWhoseFileCameBackIsNotQueuedAgain() async throws {
        let inbox = makeInbox()
        defer { cleanUp(inbox) }
        let item = try inbox.write(text: "kvittering", kind: .text)
        let router = AddSubscriptionRouter()
        let counter = DraftCounter()
        let processor = ReceiptInboxProcessor(inbox: { inbox }, makeDraft: { await counter.draft(for: $0) }, router: router)
        let file = inbox.directory.appendingPathComponent("\(item.id.uuidString).json")
        let saved = try Data(contentsOf: file)

        #expect(await processor.processInbox() == 1)
        // Som om slettingen feilet: filen med samme id ligger der igjen.
        try saved.write(to: file)
        let second = await processor.processInbox()

        #expect(second == 0)
        #expect(router.pendingDrafts.count == 1)
        #expect(files(in: inbox).isEmpty)
    }

    @Test func aNewReceiptAfterAnEarlierRunIsQueued() async throws {
        let inbox = makeInbox()
        defer { cleanUp(inbox) }
        let router = AddSubscriptionRouter()
        let counter = DraftCounter()
        let processor = ReceiptInboxProcessor(inbox: { inbox }, makeDraft: { await counter.draft(for: $0) }, router: router)

        try inbox.write(text: "en", kind: .text)
        #expect(await processor.processInbox() == 1)
        try inbox.write(text: "to", kind: .text)
        #expect(await processor.processInbox() == 1)

        #expect(router.pendingDrafts.map(\.name) == ["en", "to"])
    }

    // MARK: - Hele veien

    @Test func aSharedReceiptEndsUpAsAFilledInDraft() async throws {
        let inbox = makeInbox()
        defer { cleanUp(inbox) }
        try inbox.write(
            text: "From: Netflix <info@mailer.netflix.com>\nTotal: NOK 149.00\nBilled monthly",
            kind: .text
        )
        let router = AddSubscriptionRouter()
        let processor = ReceiptInboxProcessor(inbox: { inbox }, router: router)

        #expect(await processor.processInbox() == 1)

        let draft = try #require(router.dequeue())
        #expect(draft.source == .receipt)
        #expect(draft.name == "Netflix")
        #expect(draft.price == Decimal(string: "149.00"))
        #expect(draft.interval == .monthly)
        #expect(!draft.needsIntervalChoice)
    }

    // MARK: - Velg intervall

    @Test func aReceiptWithoutAnIntervalAsksTheUserToChoose() async {
        let draft = await ReceiptParser.draft(fromReceiptText: "Fra: Brannvakt Pluss <kvittering@brannvakt.no>\nTotalt 99,00 kr")

        #expect(draft.price == Decimal(string: "99.00"))
        #expect(draft.interval == nil)
        #expect(draft.needsIntervalChoice)
    }

    @Test func draftsWithAnIntervalDoNotAskForOne() {
        var draft = SubscriptionDraft(source: .shortcut, name: "Test")
        #expect(draft.needsIntervalChoice)

        draft.interval = .yearly

        #expect(!draft.needsIntervalChoice)
        #expect(!ServiceCatalog.bundled.service(id: "netflix")!.draft().needsIntervalChoice)
        // Katalogtjenester uten fast pris har heller ikke noe intervall.
        #expect(ServiceCatalog.bundled.service(id: "tidal")!.draft().needsIntervalChoice)
    }
}
