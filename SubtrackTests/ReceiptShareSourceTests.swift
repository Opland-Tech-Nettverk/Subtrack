import Foundation
import Testing
@testable import Subtrack

struct ReceiptShareSourceTests {

    @Test(arguments: [
        ("public.utf8-plain-text", ReceiptInboxKind.text),
        ("public.plain-text", .text),
        ("com.adobe.pdf", .pdf),
        ("public.jpeg", .image),
        ("public.png", .image),
        ("public.heic", .image)
    ])
    func classifiesSupportedTypes(identifier: String, expected: ReceiptInboxKind) {
        #expect(ReceiptShareSource.kind(forTypeIdentifier: identifier) == expected)
    }

    @Test(arguments: ["public.url", "public.html", "public.movie", "com.apple.property-list", "not.a.real.type", "public.zip-archive"])
    func rejectsWebPagesAndOtherTypes(identifier: String) {
        #expect(ReceiptShareSource.kind(forTypeIdentifier: identifier) == nil)
    }

    @Test func attachmentsComeBeforeTheTextThatFollowsThem() {
        let choices = ReceiptShareSource.orderedChoices(from: [["public.utf8-plain-text"], ["com.adobe.pdf"]])

        #expect(choices.map(\.kind) == [.pdf, .text])
        #expect(choices.map(\.index) == [1, 0])
    }

    @Test func pdfComesBeforeImageAndImageBeforeText() {
        let choices = ReceiptShareSource.orderedChoices(from: [["public.jpeg"], ["public.utf8-plain-text"], ["com.adobe.pdf"]])

        #expect(choices.map(\.kind) == [.pdf, .image, .text])
    }

    @Test func eachAttachmentGivesOneChoiceWithItsFirstSupportedType() {
        let choices = ReceiptShareSource.orderedChoices(from: [["public.url", "public.utf8-plain-text"], ["public.heic", "public.jpeg"]])

        #expect(choices == [
            ReceiptShareSource.Choice(index: 1, kind: .image, typeIdentifier: "public.heic"),
            ReceiptShareSource.Choice(index: 0, kind: .text, typeIdentifier: "public.utf8-plain-text")
        ])
    }

    @Test func firstAttachmentComesFirstWithinTheSameKind() {
        let choices = ReceiptShareSource.orderedChoices(from: [["public.png"], ["public.jpeg"]])

        #expect(choices.map(\.index) == [0, 1])
    }

    @Test func nothingSupportedGivesNoChoices() {
        #expect(ReceiptShareSource.orderedChoices(from: []).isEmpty)
        #expect(ReceiptShareSource.orderedChoices(from: [["public.url"], ["public.html"]]).isEmpty)
    }
}
