import Foundation
import Observation
import UniformTypeIdentifiers

/// Leser det som ble delt, henter ut teksten og legger den i innboksen.
@Observable
final class ShareViewModel {
    enum Failure: Equatable {
        /// Filen kunne ikke åpnes eller leses.
        case unreadable
        /// Filen ble lest, men det var ingen tekst i den.
        case noText
        /// Teksten kunne ikke legges i innboksen (App Group mangler, disken er full e.l.).
        case cannotSave
    }

    enum State: Equatable {
        case reading
        case done
        case failed(Failure)
    }

    private(set) var state: State = .reading

    private let providers: [NSItemProvider]
    private let finish: () -> Void
    private var hasStarted = false

    /// `finish` lukker utvidelsen.
    init(providers: [NSItemProvider], finish: @escaping () -> Void) {
        self.providers = providers
        self.finish = finish
    }

    func dismiss() {
        finish()
    }

    /// Kjøres én gang når skjermen vises.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        guard let choice = ReceiptShareSource.choose(from: providers.map(\.registeredTypeIdentifiers)) else {
            state = .failed(.unreadable)
            return
        }
        let provider = providers[choice.index]

        let text: String?
        switch choice.kind {
        case .text:
            text = await ShareItemLoader.text(from: provider)
        case .pdf, .image:
            guard let file = await ShareItemLoader.copyOfFile(from: provider, typeIdentifier: choice.typeIdentifier) else {
                state = .failed(.unreadable)
                return
            }
            // Kopien er midlertidig og slettes uansett utfall. Bare teksten lever videre.
            defer { try? FileManager.default.removeItem(at: file) }
            text = await ShareItemLoader.extractText(from: file, kind: choice.kind)
        }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .failed(.noText)
            return
        }

        guard let inbox = ReceiptInbox.appGroup() else {
            state = .failed(.cannotSave)
            return
        }
        // Rydder bort gamle kvitteringer samtidig, så teksten ikke blir liggende i mer enn 7 dager hos den
        // som aldri åpner appen.
        _ = inbox.entries()
        do {
            try inbox.write(text: text, kind: choice.kind)
            state = .done
        } catch {
            state = .failed(.cannotSave)
        }
    }
}

/// Tung og blokkerende lasting, utenfor hovedaktøren. `nonisolated` så closurene ikke arver MainActor.
nonisolated enum ShareItemLoader {
    static func text(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString).map { $0 as String })
            }
        }
    }

    /// Filen leveres bare mens lukningen kjører, så den kopieres til en midlertidig fil (disk, ikke minne).
    static func copyOfFile(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// PDF-tekst eller OCR, på en egen oppgave så hovedtråden er fri mens Vision jobber.
    static func extractText(from file: URL, kind: ReceiptInboxKind) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            switch kind {
            case .pdf: ReceiptTextExtraction.textOrOCR(fromPDFAt: file)
            case .image: ReceiptTextExtraction.text(fromImageAt: file)
            case .text: nil
            }
        }.value
    }
}
