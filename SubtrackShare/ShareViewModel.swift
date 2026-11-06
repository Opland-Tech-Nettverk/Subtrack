import Foundation
import Observation
import UniformTypeIdentifiers

/// Leser det som ble delt, henter ut teksten og legger den i innboksen.
@Observable
final class ShareViewModel {
    enum Failure: Equatable {
        /// Filen kunne ikke åpnes eller leses.
        case unreadable
        /// Innholdet ble lest, men det var ingen tekst i det. `kind` sier hva som ble delt.
        case noText(ReceiptInboxKind)
        /// Teksten kunne ikke legges i innboksen (App Group mangler, disken er full e.l.).
        case cannotSave
    }

    enum State: Equatable {
        case reading
        case done
        case failed(Failure)
        /// Brukeren avbrøt (Avbryt eller sveip ned). Forespørselen er avbrutt, og ingenting skrives.
        case cancelled
    }

    private(set) var state: State = .reading

    private let providers: [NSItemProvider]
    private let finish: () -> Void
    private let cancelRequest: () -> Void
    private var hasStarted = false
    private var workTask: Task<Void, Never>?

    /// `finish` lukker utvidelsen etter at brukeren har sett resultatet. `cancelRequest` avbryter den.
    init(providers: [NSItemProvider], finish: @escaping () -> Void, cancelRequest: @escaping () -> Void) {
        self.providers = providers
        self.finish = finish
        self.cancelRequest = cancelRequest
    }

    func dismiss() {
        finish()
    }

    /// Brukeren trykket Avbryt mens kvitteringen leses. Ingenting skrives til innboksen.
    func cancel() {
        // Ut av .reading først, så `cancelIfReading` (som kommer når skjermen forsvinner etter Avbryt) ikke
        // avbryter forespørselen en gang til, og så arbeidet ikke kan sette en annen tilstand etterpå.
        guard state == .reading else { return }
        state = .cancelled
        workTask?.cancel()
        cancelRequest()
    }

    /// Skjermen forsvant (brukeren sveipet den ned) mens kvitteringen fortsatt ble lest: avbryt arbeidet og
    /// forespørselen, så verten får beskjed og ingenting skrives til innboksen.
    func cancelIfReading() {
        cancel()
    }

    /// Kjøres én gang når skjermen vises.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        let work = Task { await run() }
        workTask = work
        await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private func run() async {
        // Rydder opp etter en tidligere kjøring som ble avsluttet av systemet midt i lesingen.
        ShareItemLoader.removeStaleTemporaryFiles()

        let choices = ReceiptShareSource.orderedChoices(from: providers.map(\.registeredTypeIdentifiers))
        guard !choices.isEmpty else {
            finishReading(.failed(.unreadable))
            return
        }

        // PDF og bilde først, så teksten som ofte bare er en tittel på vedlegget. Den første som gir tekst, brukes.
        var failure = Failure.unreadable
        for choice in choices {
            guard !Task.isCancelled else { return }
            let provider = providers[choice.index]

            let text: String?
            switch choice.kind {
            case .text:
                text = await ShareItemLoader.text(from: provider)
            case .pdf, .image:
                guard let file = await ShareItemLoader.copyOfFile(from: provider, typeIdentifier: choice.typeIdentifier) else {
                    continue
                }
                // Kopien er midlertidig og slettes uansett utfall. Bare teksten lever videre.
                defer { try? FileManager.default.removeItem(at: file) }
                text = await ShareItemLoader.extractText(from: file, kind: choice.kind)
            }

            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failure = .noText(choice.kind)
                continue
            }
            guard !Task.isCancelled else { return }
            save(text, kind: choice.kind)
            return
        }
        finishReading(.failed(failure))
    }

    private func save(_ text: String, kind: ReceiptInboxKind) {
        guard let inbox = ReceiptInbox.appGroup() else {
            finishReading(.failed(.cannotSave))
            return
        }
        // Rydder bort gamle kvitteringer samtidig, så teksten ikke blir liggende i mer enn 7 dager hos den
        // som aldri åpner appen.
        _ = inbox.entries()
        do {
            try inbox.write(text: text, kind: kind)
            finishReading(.done)
        } catch {
            finishReading(.failed(.cannotSave))
        }
    }

    /// Setter sluttilstanden, men bare hvis brukeren ikke har avbrutt i mellomtiden.
    private func finishReading(_ newState: State) {
        guard state == .reading else { return }
        state = newState
    }
}

/// Tung og blokkerende lasting, utenfor hovedaktøren. `nonisolated` så closurene ikke arver MainActor.
nonisolated enum ShareItemLoader {
    /// Egen mappe for kopiene, så den kan ryddes uten å røre noe annet i `tmp`.
    private static var temporaryFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SharedReceipt", isDirectory: true)
    }

    /// Sletter kopier som ble liggende igjen fordi utvidelsen ble avsluttet midt i lesingen. Bare filer eldre enn
    /// to minutter, så en annen kjøring som holder på akkurat nå, ikke mister filen sin.
    static func removeStaleTemporaryFiles(now: Date = Date(), olderThan age: TimeInterval = 120) {
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(
            at: temporaryFolder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for url in urls {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified.map({ now.timeIntervalSince($0) > age }) ?? true {
                try? fileManager.removeItem(at: url)
            }
        }
    }

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
                let folder = temporaryFolder
                let copy = folder
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
