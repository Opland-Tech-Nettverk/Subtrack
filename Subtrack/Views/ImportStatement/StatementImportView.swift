import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Import av abonnementer fra en kontoutskrift: først en forklaring, så valg av fil, og så en liste
/// med forslag brukeren går gjennom. Filen leses bare i minnet. Ingenting fra den lagres, logges
/// eller sendes noe sted; det som blir lagret, er abonnementene brukeren selv godkjenner.
struct StatementImportView: View {
    /// Kalles i stedet for å lukke seg selv når forslag er lagt inn. Brukes av Innstillinger, som da
    /// lukker seg selv også, så brukeren ser abonnementene i oversikten.
    let onAdded: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Query private var subscriptions: [Subscription]

    @State private var phase: Phase = .intro
    @State private var isPickingFile = false
    /// Økes for hver fil som leses, så oversikten over forslag starter på nytt når en ny fil velges.
    @State private var generation = 0

    private enum Phase {
        case intro
        case loading
        case review(StatementAnalysis)
        case failed(StatementImportError)
    }

    init(onAdded: (() -> Void)? = nil) {
        self.onAdded = onAdded
    }

    /// Filtyper nettbankene eksporterer: CSV, tabulatorseparert og ren tekst (DNB lager `.txt`).
    private static let allowedTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Importer fra kontoutskrift")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Lukk") { dismiss() }
                    }
                }
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: Self.allowedTypes) { result in
            read(result)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro:
            StatementImportIntroView { isPickingFile = true }
        case .loading:
            ProgressView("Leser filen …")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("importLoading")
        case .review(let analysis):
            StatementReviewView(
                analysis: analysis,
                onChooseAnotherFile: { isPickingFile = true },
                onAdded: finish
            )
            .id(generation)
        case .failed(let error):
            StatementImportFailureView(error: error) { isPickingFile = true }
        }
    }

    private func finish() {
        if let onAdded {
            onAdded()
        } else {
            dismiss()
        }
    }

    /// Leser filen og finner forslag, utenfor hovedtråden mens det vises en fremdriftsindikator. Bytene og
    /// transaksjonene forsvinner når analysen er ferdig; bare forslagene og antallet beholdes, i minnet,
    /// til skjermen lukkes. Det som sendes til bakgrunnsoppgaven, er bare verdier (adressen til filen,
    /// katalogen og navnene), ingenting som hører til hovedaktøren.
    private func read(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            phase = .failed(.unreadable)
            return
        }
        // Abonnementer som er avsluttet, regnes ikke som eksisterende: trekk som fortsetter, bør vises.
        let existingNames = subscriptions.filter { !$0.isCancelled }.map(\.name)
        let catalog = ServiceCatalog.bundled
        let accessing = url.startAccessingSecurityScopedResource()
        phase = .loading
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.analyze(fileAt: url, catalog: catalog, existingNames: existingNames)
            }.value
            if accessing { url.stopAccessingSecurityScopedResource() }
            switch outcome {
            case .success(let analysis):
                generation += 1
                phase = .review(analysis)
            case .failure(let error):
                phase = .failed(error)
            }
        }
    }

    /// Selve lesingen. `nonisolated` og statisk, så den ikke fanger noe fra visningen.
    private nonisolated static func analyze(
        fileAt url: URL,
        catalog: ServiceCatalog,
        existingNames: [String]
    ) -> Result<StatementAnalysis, StatementImportError> {
        guard let data = try? Data(contentsOf: url) else {
            return .failure(.unreadable)
        }
        do {
            return .success(try StatementImporter.analyze(data: data, catalog: catalog, existingNames: existingNames))
        } catch let error as StatementImportError {
            return .failure(error)
        } catch {
            return .failure(.unreadable)
        }
    }
}

/// Forklaringen før filen velges: hvordan man eksporterer fra nettbanken, og at filen bare leses på telefonen.
private struct StatementImportIntroView: View {
    let chooseFile: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Finn abonnementer i kontoutskriften din. Subtrack leter etter betalinger som kommer igjen, for eksempel hver måned, og foreslår dem som abonnementer.")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Slik gjør du")
                        .font(.headline)
                    stepRow(number: 1, text: "Logg inn i nettbanken og eksporter kontoutskriften som CSV-fil (noen banker kaller den tekstfil). Velg gjerne de siste 6 til 12 månedene: jo lengre periode, jo bedre forslag.")
                    stepRow(number: 2, text: "Trykk på «Velg fil» og velg filen. Den kan ligge i Filer, iCloud Drive eller en annen mappe.")
                    stepRow(number: 3, text: "Se gjennom forslagene. Ingenting legges inn før du har godkjent det.")
                }

                Label {
                    Text("Filen leses bare på telefonen. Den lagres ikke, sendes ikke noe sted, og forsvinner når du lukker denne skjermen. Bare abonnementene du velger å legge til, blir lagret.")
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.tint)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Appen kjenner igjen kolonnene i filen fra overskriftene. Fungerer ikke filen din, send gjerne en tilbakemelding via TestFlight eller GitHub, uten innholdet i filen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: chooseFile) {
                Text("Velg fil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .frame(maxWidth: 640)
            .accessibilityIdentifier("importChooseFile")
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Steg \(number). \(text)")
    }
}

/// Filen kunne ikke leses. Sier hva som mangler, og ber om CSV.
private struct StatementImportFailureView: View {
    let error: StatementImportError
    let chooseAnotherFile: () -> Void

    private var message: String {
        switch error {
        case .unreadable:
            return "Filen er tom eller kunne ikke leses. Eksporter kontoutskriften som CSV-fil fra nettbanken og prøv igjen."
        case .missingColumns(let columns):
            let list = columns.joined(separator: ", ")
            return "Fant ikke kolonnene: \(list). Subtrack trenger kolonner for dato, tekst og beløp. Eksporter kontoutskriften som CSV-fil fra nettbanken og prøv igjen."
        case .noTransactions:
            return "Filen har riktige kolonner, men ingen utgående betalinger Subtrack kunne lese. Sjekk at filen er en kontoutskrift med utgifter, og eksporter den som CSV-fil."
        }
    }

    var body: some View {
        ContentUnavailableView {
            Label("Kunne ikke lese filen", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Velg en annen fil", action: chooseAnotherFile)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("importChooseAnotherFile")
        }
    }
}
