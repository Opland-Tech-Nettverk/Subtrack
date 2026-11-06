import Foundation
import PDFKit
import Testing
import UIKit
@testable import Subtrack

@MainActor
struct ReceiptTextExtractionTests {

    // MARK: - Hjelpere

    private let fileManager = FileManager.default

    private func temporaryURL(_ pathExtension: String) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("ReceiptTextExtractionTests-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private let receiptLines = ["Netflix", "Totalt 149,00 kr", "Neste trekk 15.11.2026"]

    private func drawReceipt(in rect: CGRect) {
        UIColor.white.setFill()
        UIRectFill(rect)
        let font = UIFont.boldSystemFont(ofSize: 64)
        for (index, line) in receiptLines.enumerated() {
            (line as NSString).draw(
                at: CGPoint(x: 60, y: 60 + CGFloat(index) * 120),
                withAttributes: [.font: font, .foregroundColor: UIColor.black]
            )
        }
    }

    /// PDF med ekte tekstlag.
    private func makeTextPDF() throws -> URL {
        let url = temporaryURL("pdf")
        let rect = CGRect(x: 0, y: 0, width: 612, height: 792)
        try UIGraphicsPDFRenderer(bounds: rect).writePDF(to: url) { context in
            context.beginPage()
            let font = UIFont.systemFont(ofSize: 18)
            for (index, line) in receiptLines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 40 + CGFloat(index) * 30), withAttributes: [.font: font])
            }
        }
        return url
    }

    private func makeReceiptImage(size: CGSize = CGSize(width: 1_300, height: 500)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            drawReceipt(in: CGRect(origin: .zero, size: size))
        }
    }

    private func makeImageFile() throws -> URL {
        let url = temporaryURL("png")
        try makeReceiptImage().pngData()!.write(to: url)
        return url
    }

    /// PDF som bare er et bilde av en kvittering, uten tekstlag (en skannet PDF).
    private func makeScannedPDF() throws -> URL {
        let url = temporaryURL("pdf")
        let image = makeReceiptImage(size: CGSize(width: 1_224, height: 792))
        let rect = CGRect(x: 0, y: 0, width: 612, height: 396)
        try UIGraphicsPDFRenderer(bounds: rect).writePDF(to: url) { context in
            context.beginPage()
            image.draw(in: rect)
        }
        return url
    }

    // MARK: - PDF

    @Test func readsTheTextLayerOfAPDF() throws {
        let url = try makeTextPDF()
        defer { try? fileManager.removeItem(at: url) }

        let text = try #require(ReceiptTextExtraction.text(fromPDFAt: url))

        #expect(text.contains("Netflix"))
        #expect(text.contains("Totalt 149,00 kr"))
    }

    @Test func aScannedPDFHasNoTextLayer() throws {
        let url = try makeScannedPDF()
        defer { try? fileManager.removeItem(at: url) }

        #expect(ReceiptTextExtraction.text(fromPDFAt: url) == nil)
    }

    @Test func aScannedPDFIsReadWithOCROnTheFirstPage() throws {
        let url = try makeScannedPDF()
        defer { try? fileManager.removeItem(at: url) }

        let text = try #require(ReceiptTextExtraction.textOrOCR(fromPDFAt: url))

        #expect(text.localizedCaseInsensitiveContains("Netflix"))
        #expect(text.contains("149"))
    }

    @Test func aTextPDFDoesNotNeedOCR() throws {
        let url = try makeTextPDF()
        defer { try? fileManager.removeItem(at: url) }

        #expect(ReceiptTextExtraction.textOrOCR(fromPDFAt: url) == ReceiptTextExtraction.text(fromPDFAt: url))
    }

    @Test func aFileThatIsNotAPDFGivesNothing() throws {
        let url = temporaryURL("pdf")
        try Data("ikke en pdf".utf8).write(to: url)
        defer { try? fileManager.removeItem(at: url) }

        #expect(ReceiptTextExtraction.text(fromPDFAt: url) == nil)
        #expect(ReceiptTextExtraction.textOrOCR(fromPDFAt: url) == nil)
    }

    // MARK: - Bilde

    @Test func readsTextFromAnImageWithOCR() throws {
        let url = try makeImageFile()
        defer { try? fileManager.removeItem(at: url) }

        let text = try #require(ReceiptTextExtraction.text(fromImageAt: url))

        #expect(text.localizedCaseInsensitiveContains("Netflix"))
        #expect(text.contains("149"))
    }

    @Test func aFileThatIsNotAnImageGivesNothing() throws {
        let url = temporaryURL("png")
        try Data("ikke et bilde".utf8).write(to: url)
        defer { try? fileManager.removeItem(at: url) }

        #expect(ReceiptTextExtraction.text(fromImageAt: url) == nil)
    }

    @Test func bigImagesAreDownscaledWhileDecoding() throws {
        let url = temporaryURL("png")
        try makeReceiptImage(size: CGSize(width: 6_000, height: 400)).pngData()!.write(to: url)
        defer { try? fileManager.removeItem(at: url) }

        let image = try #require(ReceiptTextExtraction.downscaledImage(at: url, maxDimension: 1_500))

        #expect(max(image.width, image.height) == 1_500)
    }

    @Test func smallImagesAreNotEnlarged() throws {
        let url = try makeImageFile()
        defer { try? fileManager.removeItem(at: url) }

        let image = try #require(ReceiptTextExtraction.downscaledImage(at: url, maxDimension: ReceiptTextExtraction.maxImageDimension))

        #expect(image.width <= 1_300)
    }

    // MARK: - Språk og tekstbehandling

    @Test func norwegianIsUsedWhenVisionSupportsIt() {
        #expect(ReceiptTextExtraction.recognitionLanguages(supported: ["en-US", "nb-NO", "de-DE"]) == ["nb-NO", "en-US"])
        #expect(ReceiptTextExtraction.recognitionLanguages(supported: ["no", "en-US"]) == ["no", "en-US"])
        #expect(ReceiptTextExtraction.recognitionLanguages(supported: ["nn-NO"]) == ["nn-NO"])
    }

    @Test func languageDetectionIsAutomaticWhenNorwegianIsNotSupported() {
        #expect(ReceiptTextExtraction.recognitionLanguages(supported: ["en-US", "de-DE", "sv-SE"]) == nil)
        #expect(ReceiptTextExtraction.recognitionLanguages(supported: []) == nil)
    }

    @Test func recognizedLinesAreJoinedInReadingOrder() {
        let lines = [
            ReceiptTextExtraction.RecognizedLine(text: "109,00 kr", midX: 0.8, midY: 0.50),
            ReceiptTextExtraction.RecognizedLine(text: "Spotify", midX: 0.3, midY: 0.90),
            ReceiptTextExtraction.RecognizedLine(text: "Totalt", midX: 0.2, midY: 0.505),
            ReceiptTextExtraction.RecognizedLine(text: "Månedlig", midX: 0.3, midY: 0.70)
        ]

        #expect(ReceiptTextExtraction.joinInReadingOrder(lines) == "Spotify\nMånedlig\nTotalt 109,00 kr")
    }

    @Test func normalizedTextIsTrimmedAndCappedAtTheInboxLimit() {
        #expect(ReceiptTextExtraction.normalized("  \n\t ") == nil)
        #expect(ReceiptTextExtraction.normalized("  Hei \n") == "Hei")
        let long = String(repeating: "a", count: ReceiptInbox.maxTextLength + 100)
        #expect(ReceiptTextExtraction.normalized(long)?.count == ReceiptInbox.maxTextLength)
    }
}
