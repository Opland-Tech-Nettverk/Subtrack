import Foundation
import Testing
@testable import Subtrack

struct ReceiptInboxTests {

    // MARK: - Hjelpere

    private let fileManager = FileManager.default

    /// Hver test får en egen, tom mappe som ryddes bort til slutt.
    private func withInbox(_ body: (ReceiptInbox, URL) throws -> Void) throws {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ReceiptInboxTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory.deletingLastPathComponent()) }
        try body(ReceiptInbox(directory: directory), directory)
    }

    private func makeDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Skriver en fil for hånd, slik en eldre eller annen utvidelse kunne gjort det.
    @discardableResult
    private func writeFile(
        in directory: URL,
        id: UUID = UUID(),
        text: String = "Netflix 149,00 kr",
        kind: String = "text",
        createdAt: String,
        modified: Date? = nil
    ) throws -> URL {
        try makeDirectory(directory)
        let json = """
        {"id":"\(id.uuidString)","text":"\(text)","kind":"\(kind)","createdAt":"\(createdAt)"}
        """
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        try Data(json.utf8).write(to: url)
        if let modified {
            try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    private func writeRaw(_ text: String, named name: String, in directory: URL, modified: Date? = nil) throws -> URL {
        try makeDirectory(directory)
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        if let modified {
            try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    private func files(in directory: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    // MARK: - Lese og slette

    @Test func readsAFileWrittenInTheDocumentedShape() throws {
        try withInbox { inbox, directory in
            let id = UUID()
            try writeFile(in: directory, id: id, text: "Spotify 109,00 kr", kind: "pdf", createdAt: iso(now.addingTimeInterval(-60)))

            let items = inbox.entries(now: now)

            #expect(items.count == 1)
            #expect(items[0].item.id == id)
            #expect(items[0].item.text == "Spotify 109,00 kr")
            #expect(items[0].item.kind == .pdf)
            #expect(items[0].item.createdAt == now.addingTimeInterval(-60))
        }
    }

    @Test func entriesDoesNotDeleteButDrainDoes() throws {
        try withInbox { inbox, directory in
            try writeFile(in: directory, createdAt: iso(now))

            #expect(inbox.entries(now: now).count == 1)
            #expect(files(in: directory).count == 1)

            let drained = inbox.drain(now: now)

            #expect(drained.count == 1)
            #expect(files(in: directory).isEmpty)
            #expect(inbox.drain(now: now).isEmpty)
        }
    }

    @Test func removeDeletesOnlyThatFile() throws {
        try withInbox { inbox, directory in
            try writeFile(in: directory, text: "A", createdAt: iso(now))
            try writeFile(in: directory, text: "B", createdAt: iso(now.addingTimeInterval(1)))
            let entries = inbox.entries(now: now)

            inbox.remove(entries[0])

            #expect(files(in: directory).count == 1)
            #expect(inbox.entries(now: now).map(\.item.text) == ["B"])
        }
    }

    @Test func itemsComeOldestFirst() throws {
        try withInbox { inbox, directory in
            try writeFile(in: directory, text: "tredje", createdAt: iso(now.addingTimeInterval(-10)))
            try writeFile(in: directory, text: "første", createdAt: iso(now.addingTimeInterval(-300)))
            try writeFile(in: directory, text: "andre", createdAt: iso(now.addingTimeInterval(-100)))

            #expect(inbox.drain(now: now).map(\.text) == ["første", "andre", "tredje"])
        }
    }

    @Test func missingDirectoryGivesNothing() throws {
        try withInbox { inbox, _ in
            #expect(inbox.entries(now: now).isEmpty)
            #expect(inbox.drain(now: now).isEmpty)
        }
    }

    @Test func unknownKindIsReadAsText() throws {
        try withInbox { inbox, directory in
            try writeFile(in: directory, kind: "webpage", createdAt: iso(now))

            #expect(inbox.entries(now: now).first?.item.kind == .text)
        }
    }

    @Test func fractionalSecondsInTheDateAreAccepted() throws {
        try withInbox { inbox, directory in
            try writeFile(in: directory, createdAt: "2026-11-06T14:19:25.123Z")
            let late = ISO8601DateFormatter().date(from: "2026-11-06T15:00:00Z")!

            #expect(inbox.entries(now: late).count == 1)
        }
    }

    // MARK: - Ødelagte filer

    @Test func oldCorruptFilesAreDeletedWithoutCrashing() throws {
        try withInbox { inbox, directory in
            let old = now.addingTimeInterval(-3_600)
            try writeRaw("ikke json i det hele tatt", named: "a.json", in: directory, modified: old)
            try writeRaw("{\"id\":\"ikke-en-uuid\",\"text\":\"x\"}", named: "b.json", in: directory, modified: old)
            try writeRaw("", named: "c.json", in: directory, modified: old)
            try writeFile(in: directory, text: "ok", createdAt: iso(now))

            let items = inbox.drain(now: now)

            #expect(items.map(\.text) == ["ok"])
            #expect(files(in: directory).isEmpty)
        }
    }

    @Test func aFileThatIsStillBeingWrittenIsLeftAlone() throws {
        try withInbox { inbox, directory in
            // Halvskrevet og endret for 5 sekunder siden: skal ikke vises og ikke slettes ennå.
            let url = try writeRaw("{\"id\":\"\(UUID().uuidString)\",\"text\":\"Netfl", named: "partial.json", in: directory, modified: now.addingTimeInterval(-5))

            #expect(inbox.entries(now: now).isEmpty)
            #expect(fileManager.fileExists(atPath: url.path))

            // Blir skrevet ferdig, og er gyldig neste gang appen leser.
            let id = UUID()
            let complete = """
            {"id":"\(id.uuidString)","text":"Netflix 149,00 kr","kind":"text","createdAt":"\(iso(now))"}
            """
            try Data(complete.utf8).write(to: url)
            try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: url.path)

            #expect(inbox.entries(now: now).map(\.item.id) == [id])
        }
    }

    @Test func aPartialFileThatNeverGetsFinishedIsEventuallyDeleted() throws {
        try withInbox { inbox, directory in
            let url = try writeRaw("{\"id\":", named: "partial.json", in: directory, modified: now.addingTimeInterval(-5))

            #expect(inbox.entries(now: now).isEmpty)
            #expect(fileManager.fileExists(atPath: url.path))

            let later = now.addingTimeInterval(ReceiptInbox.partialFileGrace + 10)

            #expect(inbox.entries(now: later).isEmpty)
            #expect(!fileManager.fileExists(atPath: url.path))
        }
    }

    @Test func temporaryAndForeignFilesAreIgnored() throws {
        try withInbox { inbox, directory in
            let tmp = try writeRaw("{\"id\":", named: "\(UUID().uuidString).tmp", in: directory, modified: now)
            let other = try writeRaw("hei", named: "notat.txt", in: directory, modified: now.addingTimeInterval(-100_000))
            try writeFile(in: directory, createdAt: iso(now))

            #expect(inbox.drain(now: now).count == 1)
            #expect(fileManager.fileExists(atPath: tmp.path))
            #expect(fileManager.fileExists(atPath: other.path))
        }
    }

    @Test func oldTemporaryFilesAreCleanedUp() throws {
        try withInbox { inbox, directory in
            let tmp = try writeRaw("{}", named: "\(UUID().uuidString).tmp", in: directory, modified: now.addingTimeInterval(-ReceiptInbox.maxAge - 10))

            #expect(inbox.entries(now: now).isEmpty)
            #expect(!fileManager.fileExists(atPath: tmp.path))
        }
    }

    @Test func oversizedFilesAreNeverRead() throws {
        try withInbox { inbox, directory in
            let old = now.addingTimeInterval(-3_600)
            let huge = String(repeating: "x", count: ReceiptInbox.maxFileSize + 1)
            let url = try writeRaw(huge, named: "huge.json", in: directory, modified: old)

            #expect(inbox.entries(now: now).isEmpty)
            #expect(!fileManager.fileExists(atPath: url.path))
        }
    }

    // MARK: - Opprydding etter 7 dager

    @Test func filesOlderThanSevenDaysAreDeletedWithoutBeingShown() throws {
        try withInbox { inbox, directory in
            let eightDays = now.addingTimeInterval(-8 * 24 * 3_600)
            let sixDays = now.addingTimeInterval(-6 * 24 * 3_600)
            let old = try writeFile(in: directory, text: "gammel", createdAt: iso(eightDays), modified: now)
            try writeFile(in: directory, text: "ny nok", createdAt: iso(sixDays))

            let items = inbox.entries(now: now)

            #expect(items.map(\.item.text) == ["ny nok"])
            #expect(!fileManager.fileExists(atPath: old.path))
        }
    }

    @Test func emptyTextFilesAreDeleted() throws {
        try withInbox { inbox, directory in
            let url = try writeFile(in: directory, text: "   ", createdAt: iso(now))

            #expect(inbox.entries(now: now).isEmpty)
            #expect(!fileManager.fileExists(atPath: url.path))
        }
    }

    @Test func overlongTextInAFileIsCut() throws {
        try withInbox { inbox, directory in
            let long = String(repeating: "a", count: ReceiptInbox.maxTextLength + 500)
            try writeFile(in: directory, text: long, createdAt: iso(now))

            #expect(inbox.entries(now: now).first?.item.text.count == ReceiptInbox.maxTextLength)
        }
    }

    // MARK: - Skriving

    @Test func writtenItemCanBeReadBack() throws {
        try withInbox { inbox, directory in
            let written = try inbox.write(text: "  Netflix 149,00 kr \n", kind: .image, now: now)

            let items = inbox.drain(now: now)

            #expect(items == [written])
            #expect(written.text == "Netflix 149,00 kr")
            #expect(written.kind == .image)
            #expect(written.createdAt == now)
            #expect(files(in: directory).isEmpty)
        }
    }

    @Test func writerUsesTheDocumentedFileShape() throws {
        try withInbox { inbox, directory in
            let item = try inbox.write(text: "Hei", kind: .pdf, now: now)

            let url = directory.appendingPathComponent("\(item.id.uuidString).json")
            let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])

            #expect(Set(object.keys) == ["id", "text", "kind", "createdAt"])
            #expect(object["id"] as? String == item.id.uuidString)
            #expect(object["text"] as? String == "Hei")
            #expect(object["kind"] as? String == "pdf")
            #expect(object["createdAt"] as? String == iso(now))
        }
    }

    @Test func writerCapsTheTextAtTwentyThousandCharacters() throws {
        try withInbox { inbox, _ in
            let written = try inbox.write(text: String(repeating: "å", count: 25_000), kind: .text, now: now)

            #expect(written.text.count == 20_000)
            #expect(inbox.drain(now: now).first?.text.count == 20_000)
        }
    }

    @Test func writerCapsOnUnicodeScalarsSoCombiningMarksCannotMakeAnOversizedFile() throws {
        try withInbox { inbox, directory in
            // «e» + kombinerende aksent er én grafemklynge, men to skalarer.
            let text = String(repeating: "e\u{0301}", count: 15_000)

            let written = try inbox.write(text: text, kind: .text, now: now)

            #expect(written.text.unicodeScalars.count == ReceiptInbox.maxTextLength)
            #expect(inbox.drain(now: now).count == 1)
        }
    }

    @Test func fileWithAFutureCreatedAtIsStillPurgedByItsModificationDate() throws {
        try withInbox { inbox, directory in
            let future = now.addingTimeInterval(30 * 24 * 3_600)
            let url = try writeFile(in: directory, createdAt: iso(future), modified: now.addingTimeInterval(-8 * 24 * 3_600))

            #expect(inbox.entries(now: now).isEmpty)
            #expect(!fileManager.fileExists(atPath: url.path))
        }
    }

    @Test func writerRejectsEmptyText() throws {
        try withInbox { inbox, directory in
            #expect(throws: ReceiptInbox.WriteError.emptyText) {
                try inbox.write(text: " \n\t ", kind: .text)
            }
            #expect(files(in: directory).isEmpty)
        }
    }

    @Test func writerLeavesNoTemporaryFileBehind() throws {
        try withInbox { inbox, directory in
            try inbox.write(text: "A", kind: .text)
            try inbox.write(text: "B", kind: .text)

            let names = files(in: directory)
            #expect(names.count == 2)
            #expect(names.allSatisfy { $0.hasSuffix(".json") })
        }
    }

    @Test func writtenFileAndFolderAreExcludedFromBackup() throws {
        try withInbox { inbox, directory in
            let item = try inbox.write(text: "Hei", kind: .text)

            let folder = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            let file = try directory
                .appendingPathComponent("\(item.id.uuidString).json")
                .resourceValues(forKeys: [.isExcludedFromBackupKey])

            #expect(folder.isExcludedFromBackup == true)
            #expect(file.isExcludedFromBackup == true)
        }
    }

    @Test func appGroupInboxPointsAtTheInboxFolder() {
        // I simulatoren uten signering finnes kanskje ingen App Group; da er svaret nil.
        if let inbox = ReceiptInbox.appGroup() {
            #expect(inbox.directory.lastPathComponent == "Inbox")
        }
        #expect(ReceiptInbox.appGroupIdentifier == "group.com.opland.subtrack")
    }
}
