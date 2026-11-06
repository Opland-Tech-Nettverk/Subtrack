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
        let choices = ReceiptShareSource.orderedChoices(from: [["public.heic", "public.jpeg"], ["public.rtf", "public.utf8-plain-text"]])

        #expect(choices == [
            ReceiptShareSource.Choice(index: 0, kind: .image, typeIdentifier: "public.heic"),
            ReceiptShareSource.Choice(index: 1, kind: .text, typeIdentifier: "public.utf8-plain-text")
        ])
    }

    @Test func aLinkSharedWithAReceiptIsSkipped() {
        // Kvittering og lenke fra en bankapp eller nettbutikk: lenken er et eget vedlegg uten tekst å lese.
        let choices = ReceiptShareSource.orderedChoices(from: [["com.adobe.pdf"], ["public.url"]])

        #expect(choices.map(\.kind) == [.pdf])
    }

    @Test func aLinkThatAlsoRegistersItsAddressAsTextIsNotAReceipt() {
        // Safari og andre registrerer adressen både som URL og ren tekst. Det er en nettside, ikke en kvittering.
        let choices = ReceiptShareSource.orderedChoices(from: [["public.url", "public.utf8-plain-text"]])

        #expect(choices.isEmpty)
    }

    @Test func textSharedWithALinkIsStillRead() {
        let choices = ReceiptShareSource.orderedChoices(from: [["public.utf8-plain-text"], ["public.url"]])

        #expect(choices == [ReceiptShareSource.Choice(index: 0, kind: .text, typeIdentifier: "public.utf8-plain-text")])
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
