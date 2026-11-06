import Foundation
import ImageIO
import PDFKit
import UIKit
import Vision

// Henter tekst ut av PDF-er og bilder. Brukes av delingsutvidelsen og enhetstestes i appen.
// Bare Apples egne rammeverk, og ingenting her lagrer bildet eller PDF-en: alt leses fra en fil som kalleren
// eier, og det som kommer ut er tekst. Alle funksjonene er synkrone og tunge (OCR tar sekunder), så kall dem
// fra en bakgrunnsoppgave. De er `nonisolated` fordi begge targets har MainActor som standard.

nonisolated enum ReceiptTextExtraction {
    /// Lengste side i pikslene bildet skaleres ned til før OCR. Utvidelsen har ca. 120 MB minne, og et
    /// ferdig dekodet bilde koster 4 byte per piksel. 3 500 piksler gir under 25 MB for et skjermbilde.
    static let maxImageDimension = 3_500
    /// Så mange sider leses fra en PDF med tekst. En kvittering er kort.
    static let maxPDFPages = 20
    /// Samme grense som innboksen.
    static let maxTextLength = ReceiptInbox.maxTextLength
    /// Bredden første PDF-side tegnes med når den må leses med OCR.
    static let pdfOCRWidth: CGFloat = 1_600

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

    private static func firstPageImage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = pdfOCRWidth / bounds.width
        let size = CGSize(width: pdfOCRWidth, height: min(bounds.height * scale, CGFloat(maxImageDimension)))
        return page.thumbnail(of: size, for: .mediaBox).cgImage
    }

    // MARK: - Bilde

    /// Teksten i et bilde, funnet med OCR. nil hvis filen ikke er et bilde eller ingen tekst ble funnet.
    static func text(fromImageAt url: URL) -> String? {
        guard let image = downscaledImage(at: url) else { return nil }
        return recognizeText(in: image)
    }

    /// Dekoder bildet direkte i redusert størrelse, uten først å lage hele bildet i full oppløsning.
    static func downscaledImage(at url: URL, maxDimension: Int = maxImageDimension) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
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
