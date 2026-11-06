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

    @Test func textWinsOverPDFAndImage() {
        let choice = ReceiptShareSource.choose(from: [["public.jpeg"], ["com.adobe.pdf"], ["public.url", "public.utf8-plain-text"]])

        #expect(choice == ReceiptShareSource.Choice(index: 2, kind: .text, typeIdentifier: "public.utf8-plain-text"))
    }

    @Test func pdfWinsOverImage() {
        let choice = ReceiptShareSource.choose(from: [["public.png"], ["com.adobe.pdf"]])

        #expect(choice?.kind == .pdf)
        #expect(choice?.index == 1)
    }

    @Test func firstAttachmentWinsWithinTheSameKind() {
        let choice = ReceiptShareSource.choose(from: [["public.heic", "public.jpeg"], ["public.png"]])

        #expect(choice == ReceiptShareSource.Choice(index: 0, kind: .image, typeIdentifier: "public.heic"))
    }

    @Test func nothingSupportedGivesNoChoice() {
        #expect(ReceiptShareSource.choose(from: []) == nil)
        #expect(ReceiptShareSource.choose(from: [["public.url"], ["public.html"]]) == nil)
    }
}
