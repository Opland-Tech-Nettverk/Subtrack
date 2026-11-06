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

    @Test func imagesOverThePixelBudgetAreDownscaledWhileDecoding() throws {
        let url = temporaryURL("png")
        try makeReceiptImage(size: CGSize(width: 3_000, height: 2_000)).pngData()!.write(to: url)
        defer { try? fileManager.removeItem(at: url) }

        let image = try #require(ReceiptTextExtraction.downscaledImage(at: url, maxPixels: 1_000_000))

        #expect(image.width * image.height <= 1_000_000)
        // Sideforholdet er bevart.
        #expect(abs(Double(image.width) / Double(image.height) - 1.5) < 0.01)
    }

    @Test func aSquareImageGetsTheSamePixelBudgetAsANarrowOne() throws {
        let square = temporaryURL("png")
        let narrow = temporaryURL("png")
        try makeReceiptImage(size: CGSize(width: 3_000, height: 3_000)).pngData()!.write(to: square)
        try makeReceiptImage(size: CGSize(width: 6_000, height: 1_500)).pngData()!.write(to: narrow)
        defer {
            try? fileManager.removeItem(at: square)
            try? fileManager.removeItem(at: narrow)
        }

        let squareImage = try #require(ReceiptTextExtraction.downscaledImage(at: square, maxPixels: 4_000_000))
        let narrowImage = try #require(ReceiptTextExtraction.downscaledImage(at: narrow, maxPixels: 4_000_000))

        #expect(squareImage.width * squareImage.height <= 4_000_000)
        #expect(narrowImage.width * narrowImage.height <= 4_000_000)
    }

    @Test func theDefaultPixelBudgetKeepsTheBitmapWellUnderFortyMegabytes() {
        #expect(ReceiptTextExtraction.maxImagePixels * 4 <= 40_000_000)
        #expect(ReceiptTextExtraction.thumbnailDimension(width: 8_000, height: 6_000, maxPixels: 6_000_000) == 2_828)
        // En lang skjermdump får færre piksler i bredden enn en kvadratisk, men samme totalbudsjett.
        let tall = ReceiptTextExtraction.thumbnailDimension(width: 1_290, height: 12_000, maxPixels: 6_000_000)
        let tallWidth = Int(Double(tall) * 1_290 / 12_000)
        #expect(tallWidth * tall <= 6_000_000)
    }

    @Test func smallImagesAreNotEnlarged() throws {
        let url = try makeImageFile()
        defer { try? fileManager.removeItem(at: url) }

        let image = try #require(ReceiptTextExtraction.downscaledImage(at: url))

        #expect(image.width == 1_300)
        #expect(image.height == 500)
    }

    // MARK: - Sidebilde for OCR

    private func firstPage(ofPDFAt url: URL) throws -> PDFPage {
        try #require(PDFDocument(url: url)?.page(at: 0))
    }

    @Test func aScannedPageIsRenderedAtScaleOneWithTheOCRWidth() throws {
        let url = try makeScannedPDF()
        defer { try? fileManager.removeItem(at: url) }

        let image = try #require(ReceiptTextExtraction.firstPageImage(try firstPage(ofPDFAt: url)))

        // 612 punkter bredt gir 1 600 piksler, uansett skjermens skala. Med skjermskala 3 ville det vært 1 836.
        #expect(image.width == ReceiptTextExtraction.pdfOCRWidth)
        #expect(image.width * image.height <= ReceiptTextExtraction.maxImagePixels)
    }

    /// Rammen rundt de mørke pikslene i bildet, i piksler.
    private func darkBounds(of image: CGImage) throws -> CGRect {
        let width = image.width
        let height = image.height
        // Tegner om til 8 bit gråtone, så testen ikke avhenger av hvordan bildet er lagret.
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drew)

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        try #require(maxX >= minX, "Fant ingen mørke piksler")
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @Test func thePageContentIsEnlargedAndNotJustTheBitmap() throws {
        // En svart firkant på 100 x 100 punkter på en side som er 612 punkter bred. Med 1 600 piksler i bredden er
        // skalaen 2,61, så firkanten skal bli ca. 261 piksler. Tegnes siden 1:1 midt i bildet (slik
        // `getDrawingTransform` alene gjør, siden den aldri forstørrer), blir den 100 piksler, og OCR av
        // 10 punkters tekst blir for liten til å leses.
        let url = temporaryURL("pdf")
        defer { try? fileManager.removeItem(at: url) }
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: url) { context in
            context.beginPage()
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 10, y: 10, width: 100, height: 100))
        }

        let image = try #require(ReceiptTextExtraction.firstPageImage(try firstPage(ofPDFAt: url)))
        let square = try darkBounds(of: image)

        let expected = 100.0 * Double(ReceiptTextExtraction.pdfOCRWidth) / 612.0
        #expect(abs(square.width - expected) <= 3, "Firkanten er \(square.width) piksler bred, forventet ca. \(expected)")
        #expect(abs(square.height - expected) <= 3)
        // Plasseringen er skalert også: 10 punkter fra kanten blir ca. 26 piksler, og toppen av siden er øverst.
        #expect(abs(square.minX - 10.0 * Double(ReceiptTextExtraction.pdfOCRWidth) / 612.0) <= 3)
        #expect(abs(square.minY - 10.0 * Double(ReceiptTextExtraction.pdfOCRWidth) / 612.0) <= 3)
    }

    @Test func tenPointTextOnAPageIsReadWithOCR() throws {
        let url = temporaryURL("pdf")
        defer { try? fileManager.removeItem(at: url) }
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: url) { context in
            context.beginPage()
            let font = UIFont.systemFont(ofSize: 10)
            let lines = ["Netflix kvittering", "Abonnement Standard", "Totalt 149,00 kr"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: CGPoint(x: 50, y: 60 + CGFloat(index) * 16),
                    withAttributes: [.font: font, .foregroundColor: UIColor.black]
                )
            }
        }

        let image = try #require(ReceiptTextExtraction.firstPageImage(try firstPage(ofPDFAt: url)))
        let text = try #require(ReceiptTextExtraction.recognizeText(in: image))

        #expect(text.localizedCaseInsensitiveContains("Netflix"))
        #expect(text.contains("149"))
    }

    @Test func aVeryTallPageStaysWithinThePixelBudget() throws {
        let url = temporaryURL("pdf")
        defer { try? fileManager.removeItem(at: url) }
        let rect = CGRect(x: 0, y: 0, width: 612, height: 4_000)
        try UIGraphicsPDFRenderer(bounds: rect).writePDF(to: url) { context in
            context.beginPage()
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 10, y: 10, width: 100, height: 100))
        }

        let image = try #require(ReceiptTextExtraction.firstPageImage(try firstPage(ofPDFAt: url)))

        #expect(Double(image.width * image.height) <= Double(ReceiptTextExtraction.maxImagePixels) * 1.001)
        #expect(image.width < ReceiptTextExtraction.pdfOCRWidth)
        // Sideforholdet er bevart (612 x 4 000).
        #expect(abs(Double(image.height) / Double(image.width) - 4_000.0 / 612.0) < 0.05)
    }

    @Test func theRenderedPageSizeFollowsTheRequestedWidthAndBudget() throws {
        let url = try makeScannedPDF()
        defer { try? fileManager.removeItem(at: url) }
        let page = try firstPage(ofPDFAt: url)

        let narrow = try #require(ReceiptTextExtraction.firstPageImage(page, width: 400))
        let capped = try #require(ReceiptTextExtraction.firstPageImage(page, width: 1_600, maxPixels: 500_000))

        #expect(narrow.width == 400)
        #expect(capped.width * capped.height <= 500_000 + 2_000)
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
