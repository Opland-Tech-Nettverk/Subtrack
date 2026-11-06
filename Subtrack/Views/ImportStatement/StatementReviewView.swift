import SwiftUI
import SwiftData

/// Forslagene fra kontoutskriften. Sikre forslag er huket av; middels sikre er det ikke. Et trykk på
/// raden åpner det utfylte skjemaet, og «Legg til valgte» legger inn alle som er huket av på én gang.
/// Forslagene ligger bare i minnet og forsvinner når skjermen lukkes.
struct StatementReviewView: View {
    let analysis: StatementAnalysis
    let onChooseAnotherFile: () -> Void
    /// Kalles når abonnementer er lagt inn og skjermen skal lukkes.
    let onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selection: SuggestionSelection
    @State private var editing: EditingSuggestion?
    /// Settes når «Legg til valgte» er trykket, så et dobbelt trykk ikke legger inn alt to ganger.
    @State private var isAdding = false
    @State private var addFeedbackTrigger = 0

    /// Forslaget som er åpnet i skjemaet. `id` er forslagets, så det kan tas ut av listen etter lagring.
    private struct EditingSuggestion: Identifiable {
        let id: String
        let draft: SubscriptionDraft
    }

    init(analysis: StatementAnalysis, onChooseAnotherFile: @escaping () -> Void, onAdded: @escaping () -> Void) {
        self.analysis = analysis
        self.onChooseAnotherFile = onChooseAnotherFile
        self.onAdded = onAdded
        // Bare de sikre er huket av på forhånd.
        _selection = State(initialValue: SuggestionSelection(suggestions: analysis.suggestions))
    }

    private var periodText: String {
        let start = analysis.periodStart.formatted(date: .abbreviated, time: .omitted)
        let end = analysis.periodEnd.formatted(date: .abbreviated, time: .omitted)
        let count = analysis.transactionCount
        return "Leste \(count) \(count == 1 ? "betaling" : "betalinger") fra \(start) til \(end)."
    }

    var body: some View {
        Group {
            if analysis.suggestions.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .sheet(item: $editing) { item in
            SubscriptionFormView(draft: item.draft, onSaved: { remove(item.id) })
        }
        // Alle forslag er tatt hånd om i skjemaet; da er det ingenting mer å gjøre her.
        .onChange(of: selection.isEmpty) {
            if selection.isEmpty && !analysis.suggestions.isEmpty && !isAdding {
                onAdded()
            }
        }
        .sensoryFeedback(.success, trigger: addFeedbackTrigger)
    }

    // MARK: - Ingen forslag

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Fant ingen abonnementer", systemImage: "magnifyingglass")
        } description: {
            VStack(spacing: 8) {
                Text(periodText)
                Text("Subtrack fant ingen betalinger som kommer igjen med jevne mellomrom og omtrent samme beløp.")
                if analysis.isShortPeriod {
                    Text("Perioden er kortere enn to måneder. En fil med flere måneder gir bedre forslag.")
                }
                Text("Du kan alltid legge til abonnementer for hånd med + i oversikten.")
            }
        } actions: {
            Button("Velg en annen fil", action: onChooseAnotherFile)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("importChooseAnotherFile")
            Button("Tilbake til oversikten", action: onAdded)
        }
    }

    // MARK: - Forslagene

    private var list: some View {
        List {
            Section {
                Text(periodText)
                    .font(.subheadline)
                if analysis.isShortPeriod {
                    Label("Perioden er kortere enn to måneder. Flere måneder gir bedre forslag.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(selection.suggestions) { suggestion in
                    row(for: suggestion)
                }
            } header: {
                Text("Forslag (\(selection.suggestions.count))")
            } footer: {
                Text("Sikre forslag er huket av. Trykk på et forslag for å se det og endre det før det legges inn.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: addSelected) {
                Text("Legg til valgte (\(selection.selectedCount))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selection.selectedCount == 0 || isAdding)
            .padding()
            .frame(maxWidth: 640)
            .background(.bar)
            .accessibilityIdentifier("importAddSelected")
        }
    }

    private func row(for suggestion: SubscriptionSuggestion) -> some View {
        let isSelected = selection.isSelected(suggestion.id)
        return HStack(spacing: 4) {
            Button {
                toggle(suggestion)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Velg \(suggestion.name)")
            .accessibilityValue(isSelected ? "Valgt" : "Ikke valgt")
            .accessibilityIdentifier("importSelect.\(suggestion.name)")

            Button {
                editing = EditingSuggestion(id: suggestion.id, draft: suggestion.draft)
            } label: {
                SuggestionRowContent(suggestion: suggestion, isStacked: dynamicTypeSize.isAccessibilitySize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Åpner skjemaet, så du kan endre abonnementet før det legges inn.")
            .accessibilityIdentifier("importRow.\(suggestion.name)")
        }
    }

    // MARK: - Handlinger

    private func toggle(_ suggestion: SubscriptionSuggestion) {
        selection.toggle(suggestion.id)
    }

    private func remove(_ id: String) {
        selection.remove(id)
    }

    /// Legger inn alle valgte forslag, slik skjemaet ville lagret dem uten endringer.
    private func addSelected() {
        // Bare ett trykk teller. De valgte tas ut av listen i samme steg, så selv et nytt kall før
        // arket er lukket, ikke har noe å legge inn.
        guard !isAdding else { return }
        let chosen = selection.takeSelected()
        guard !chosen.isEmpty else { return }
        isAdding = true
        for suggestion in chosen {
            modelContext.insert(suggestion.makeSubscription())
        }
        // Widgeten og varslene oppdateres av `keepsDerivedStateInSync()` når modellen endres. Som i skjemaet
        // spørres det om varseltillatelse her, i det øyeblikket brukeren har bedt om å bli varslet.
        Task {
            await NotificationScheduler.requestAuthorizationIfNeeded()
            await NotificationScheduler.reschedule(using: modelContext)
        }
        addFeedbackTrigger += 1
        onAdded()
    }
}

/// Innholdet i en rad: ikon, navn, intervall og siste trekk, og beløpet.
private struct SuggestionRowContent: View {
    let suggestion: SubscriptionSuggestion
    let isStacked: Bool

    private var symbolName: String {
        suggestion.draft.symbolName ?? suggestion.draft.kind?.defaultSymbolName ?? SubscriptionCategory.annet.defaultSymbolName
    }

    private var color: Color {
        suggestion.draft.colorHex.flatMap(SubscriptionAppearance.color(forHex:)) ?? .accentColor
    }

    private var lastChargeText: String {
        "Sist trukket \(suggestion.lastChargeDate.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private var priceText: String {
        suggestion.price.formatted(.currency(code: suggestion.currencyCode))
    }

    var body: some View {
        AdaptiveRowLayout(isStacked: isStacked) {
            SubscriptionIcon(symbolName: symbolName, color: color)
        } title: {
            Text(suggestion.name)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.primary)
            Text("\(suggestion.interval.displayName) · \(lastChargeText)")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        } detail: {
            Text(priceText)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.primary)
            if suggestion.confidence == .medium {
                Text("Middels sikker")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    /// Hele raden som én setning til VoiceOver.
    private var spokenText: String {
        var parts = [
            suggestion.name,
            "\(priceText) \(suggestion.interval.displayName.lowercased())",
            lastChargeText.lowercased()
        ]
        if suggestion.confidence == .medium {
            parts.append("middels sikker")
        }
        return parts.joined(separator: ", ")
    }
}
