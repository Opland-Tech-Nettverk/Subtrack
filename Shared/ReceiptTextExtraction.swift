import Foundation
import ImageIO
import PDFKit
import CoreGraphics
import Vision

// Henter tekst ut av PDF-er og bilder. Brukes av delingsutvidelsen og enhetstestes i appen.
// Bare Apples egne rammeverk, og ingenting her lagrer bildet eller PDF-en: alt leses fra en fil som kalleren
// eier, og det som kommer ut er tekst. Alle funksjonene er synkrone og tunge (OCR tar sekunder), så kall dem
// fra en bakgrunnsoppgave. De er `nonisolated` fordi begge targets har MainActor som standard.

nonisolated enum ReceiptTextExtraction {
    /// Mest piksler (bredde ganger høyde) et bilde har når Vision får det. Utvidelsen har ca. 120 MB minne, og et
    /// dekodet bilde koster 4 byte per piksel: 6 millioner piksler er 24 MB, så det er god plass til Vision selv.
    /// Grensen gjelder pikseltallet og ikke lengste side, for et kvadratisk bilde er mye dyrere enn et smalt.
    static let maxImagePixels = 6_000_000
    /// Så mange sider leses fra en PDF med tekst. En kvittering er kort.
    static let maxPDFPages = 20
    /// Samme grense som innboksen.
    static let maxTextLength = ReceiptInbox.maxTextLength
    /// Bredden første PDF-side tegnes med når den må leses med OCR (i piksler, ikke punkter).
    static let pdfOCRWidth = 1_600

    // MARK: - PDF

    /// Teksten i en PDF med tekstlag, eller nil hvis den ikke kan åpnes, er låst eller ikke har tekst.
    static func text(fromPDFAt url: URL) -> String? {
        guard let document = PDFDocument(url: url), !document.isLocked else { return nil }
        var parts: [String] = []
        for index in 0..<min(document.pageCount, maxPDFPages) {
            if let text = document.page(at: index)?.string {
                parts.append(text)
            }
        }
        return normalized(parts.joined(separator: "\n"))
    }

    /// PDF-tekst, og for en skannet PDF uten tekstlag: OCR av første side.
    static func textOrOCR(fromPDFAt url: URL) -> String? {
        if let text = text(fromPDFAt: url) { return text }
        guard let document = PDFDocument(url: url), !document.isLocked,
              let page = document.page(at: 0),
              let image = firstPageImage(page)
        else { return nil }
        return recognizeText(in: image)
    }

    /// Første PDF-side som bilde, tegnet i skala 1: nøyaktig `pdfOCRWidth` piksler bredt, men aldri over
    /// `maxPixels`. `PDFPage.thumbnail` bruker skjermens skala (3x på en iPhone), som gir et bilde på over
    /// 100 MB for en hel side, så siden tegnes selv i en `CGContext` med nøyaktig pikselstørrelse.
    static func firstPageImage(_ page: PDFPage, width: Int = pdfOCRWidth, maxPixels: Int = maxImagePixels) -> CGImage? {
        guard let pdfPage = page.pageRef else { return nil }
        let box = pdfPage.getBoxRect(.mediaBox)
        let rotated = pdfPage.rotationAngle % 180 != 0
        let pageWidth = rotated ? box.height : box.width
        let pageHeight = rotated ? box.width : box.height
        guard pageWidth > 0, pageHeight > 0 else { return nil }

        var scale = CGFloat(width) / pageWidth
        let pixels = pageWidth * scale * pageHeight * scale
        if pixels > CGFloat(maxPixels) {
            scale *= (CGFloat(maxPixels) / pixels).squareRoot()
        }
        let size = CGSize(
            // Det lille tillegget fjerner flyttallsfeil, så en side på 612 punkter blir nøyaktig 1 600 piksler.
            width: max(1, (pageWidth * scale + 0.0001).rounded(.down)),
            height: max(1, (pageHeight * scale + 0.0001).rounded(.down))
        )

        let rect = CGRect(origin: .zero, size: size)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        // Et CGContext har origo nede til venstre, som PDF. Konteksten skaleres først (her ligger skalaen, ofte 2,6),
        // og siden tegnes så 1:1 på et rektangel i punkter. `getDrawingTransform` skalerer bare ned, aldri opp,
        // så den får ikke ansvaret for størrelsen, bare for sidens rotasjon.
        context.scaleBy(x: scale, y: scale)
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        context.concatenate(pdfPage.getDrawingTransform(.mediaBox, rect: pageRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(pdfPage)
        return context.makeImage()
    }

    // MARK: - Bilde

    /// Teksten i et bilde, funnet med OCR. nil hvis filen ikke er et bilde eller ingen tekst ble funnet.
    static func text(fromImageAt url: URL) -> String? {
        guard let image = downscaledImage(at: url) else { return nil }
        return recognizeText(in: image)
    }

    /// Dekoder bildet direkte i redusert størrelse, uten først å lage hele bildet i full oppløsning. Bildet
    /// forstørres aldri, og har høyst `maxPixels` piksler.
    static func downscaledImage(at url: URL, maxPixels: Int = maxImagePixels) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { return nil }
        let maxDimension = thumbnailDimension(width: width, height: height, maxPixels: maxPixels)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// Lengste side bildet skal ha for å holde seg innenfor `maxPixels`, med uendret sideforhold. Bilder som
    /// allerede er små nok, beholder sin lengste side.
    static func thumbnailDimension(width: Int, height: Int, maxPixels: Int) -> Int {
        let longest = max(width, height)
        let pixels = width * height
        guard pixels > maxPixels else { return longest }
        let scale = (Double(maxPixels) / Double(pixels)).squareRoot()
        return max(1, Int((Double(longest) * scale).rounded(.down)))
    }

    /// Norsk hvis Vision støtter det, ellers automatisk språkgjenkjenning (Vision kjenner ikke alltid norsk).
    static func recognitionLanguages(supported: [String]) -> [String]? {
        let norwegian = supported.first { code in
            let lower = code.lowercased()
            return lower == "no" || lower.hasPrefix("nb") || lower.hasPrefix("no-") || lower.hasPrefix("nn")
        }
        guard let norwegian else { return nil }
        return supported.contains("en-US") ? [norwegian, "en-US"] : [norwegian]
    }

    static func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        if let languages = recognitionLanguages(supported: supported) {
            request.recognitionLanguages = languages
        } else {
            request.automaticallyDetectsLanguage = true
        }

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return RecognizedLine(text: text, midX: observation.boundingBox.midX, midY: observation.boundingBox.midY)
        }
        return normalized(joinInReadingOrder(lines))
    }

    // MARK: - Tekstbehandling

    nonisolated struct RecognizedLine: Equatable {
        var text: String
        /// Normalisert (0 til 1), med origo nede til venstre slik Vision gir det.
        var midX: Double
        var midY: Double
    }

    /// Setter linjer sammen ovenfra og ned. Linjer på samme høyde (innenfor `rowTolerance`) blir én linje fra
    /// venstre mot høyre, så «Totalt» og «109,00 kr» i en tabell blir stående sammen.
    static func joinInReadingOrder(_ lines: [RecognizedLine], rowTolerance: Double = 0.012) -> String {
        var rows: [[RecognizedLine]] = []
        for line in lines.sorted(by: { $0.midY > $1.midY }) {
            if let last = rows.last?.first, abs(last.midY - line.midY) <= rowTolerance {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
            .map { $0.sorted { $0.midX < $1.midX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    /// Kutter til `maxTextLength` tegn og gir nil for tekst som bare er mellomrom.
    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(maxTextLength)))
    }
}
