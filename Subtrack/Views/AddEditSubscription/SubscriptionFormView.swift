import SwiftUI
import SwiftData

/// Skjema for å legge til et nytt abonnement eller redigere et eksisterende.
/// Bruker lokal @State ("utkast") i stedet for å binde direkte til modellen,
/// slik at "Avbryt" faktisk forkaster endringer i stedet for å lagre dem.
struct SubscriptionFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency

    /// Abonnementet som redigeres. `nil` betyr at vi lager et nytt.
    var subscriptionToEdit: Subscription?

    @State private var name = ""
    @State private var priceText = ""
    @State private var currencyCode = "NOK"
    @State private var billingInterval: BillingInterval = .monthly
    @State private var nextRenewalDate = Date.now
    /// Når på, er `nextRenewalDate` datoen prøveperioden slutter og første betaling skjer.
    @State private var hasTrial = false
    @State private var category: SubscriptionCategory = .annet
    @State private var note = ""
    @State private var isActive = true
    @State private var reminderDaysBefore = 3
    @State private var symbolName: String?
    @State private var colorHex: String?
    @State private var splitCount = 1
    @State private var cancelLinkText = ""
    /// Økes ved lagring for å utløse haptisk tilbakemelding.
    @State private var saveFeedbackTrigger = 0
    /// Utkastet slik det var da skjemaet ble lastet. `nil` betyr at det ikke er lastet ennå.
    @State private var initialSnapshot: Draft?
    @State private var showsDiscardConfirmation = false

    /// Alle feltene i skjemaet, slik at vi kan se om brukeren har endret noe.
    private struct Draft: Equatable {
        var name: String
        var priceText: String
        var currencyCode: String
        var billingInterval: BillingInterval
        var nextRenewalDate: Date
        var hasTrial: Bool
        var category: SubscriptionCategory
        var note: String
        var isActive: Bool
        var reminderDaysBefore: Int
        var symbolName: String?
        var colorHex: String?
        var splitCount: Int
        var cancelLinkText: String
    }

    private var currentSnapshot: Draft {
        Draft(
            name: name,
            priceText: priceText,
            currencyCode: currencyCode,
            billingInterval: billingInterval,
            nextRenewalDate: nextRenewalDate,
            hasTrial: hasTrial,
            category: category,
            note: note,
            isActive: isActive,
            reminderDaysBefore: reminderDaysBefore,
            symbolName: symbolName,
            colorHex: colorHex,
            splitCount: splitCount,
            cancelLinkText: cancelLinkText
        )
    }

    private var hasUnsavedChanges: Bool {
        initialSnapshot != nil && currentSnapshot != initialSnapshot
    }

    private var isEditing: Bool { subscriptionToEdit != nil }

    private var cancelURL: URL? {
        CancelLink.url(from: cancelLinkText)
    }

    private var showsCancelLinkError: Bool {
        !cancelLinkText.trimmingCharacters(in: .whitespaces).isEmpty && cancelURL == nil
    }

    // Tar med abonnementets nåværende valuta selv om den ikke støttes,
    // slik at eldre abonnement med fritekst-valuta fortsatt vises riktig.
    private var currencyOptions: [String] {
        CurrencyConverter.supportedCurrencies.contains(currencyCode)
            ? CurrencyConverter.supportedCurrencies
            : [currencyCode] + CurrencyConverter.supportedCurrencies
    }

    private var price: Decimal? {
        PriceParser.parse(priceText)
    }

    private var showsPriceError: Bool {
        !priceText.trimmingCharacters(in: .whitespaces).isEmpty && (price ?? 0) <= 0
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (price ?? 0) > 0 && !showsCancelLinkError
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Navn", text: $name)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Pris", text: $priceText)
                            .keyboardType(.decimalPad)
                        if showsPriceError {
                            Text("Skriv inn en gyldig pris, f.eks. 149,90")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    Picker("Valuta", selection: $currencyCode) {
                        ForEach(currencyOptions, id: \.self) { code in
                            Text("\(code) – \(CurrencyConverter.displayName(for: code))").tag(code)
                        }
                    }
                    Picker("Intervall", selection: $billingInterval) {
                        ForEach(BillingInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    Toggle("Gratis prøveperiode", isOn: $hasTrial)
                    DatePicker(
                        hasTrial ? "Prøveperioden slutter" : "Neste fornyelse",
                        selection: $nextRenewalDate,
                        displayedComponents: .date
                    )
                } header: {
                    Text("Abonnement")
                } footer: {
                    if hasTrial {
                        Text("Første betaling skjer når prøveperioden slutter. Du får et varsel før det, slik at du rekker å avslutte.")
                    }
                }

                Section {
                    Stepper(
                        splitCount == 1 ? "Ikke delt" : "Delt på \(splitCount) personer",
                        value: $splitCount,
                        in: 1...20
                    )
                } header: {
                    Text("Deling")
                } footer: {
                    if splitCount > 1, let price {
                        let share = RenewalCalculator.share(of: price, splitCount: splitCount)
                        Text("Din del: \(share.formatted(.currency(code: currencyCode))) \(billingInterval.displayName.lowercased()). Totaler og statistikk bruker din del.")
                    } else {
                        Text("Del kostnaden likt med andre, f.eks. et familieabonnement. Antallet inkluderer deg.")
                    }
                }

                Section("Kategori") {
                    Picker("Kategori", selection: $category) {
                        ForEach(SubscriptionCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.defaultSymbolName)
                                .tag(category)
                        }
                    }
                }

                Section("Utseende") {
                    AppearancePicker(
                        category: category,
                        symbolName: $symbolName,
                        colorHex: $colorHex
                    )
                }

                Section("Varsel") {
                    Stepper(
                        "Varsle \(reminderDaysBefore) \(reminderDaysBefore == 1 ? "dag" : "dager") før",
                        value: $reminderDaysBefore,
                        in: 0...30
                    )
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Lenke, f.eks. netflix.com/cancel", text: $cancelLinkText)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if showsCancelLinkError {
                            Text("Skriv inn en gyldig nettadresse")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    if let cancelURL {
                        Link(destination: cancelURL) {
                            Label("Åpne avslutningsside", systemImage: "arrow.up.right.square")
                        }
                    }
                } header: {
                    Text("Avslutte")
                } footer: {
                    Text("Varselet får en knapp som åpner denne siden, så du raskt kan si opp.")
                }

                Section("Notat") {
                    TextField("Valgfritt notat", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Toggle("Aktiv", isOn: $isActive)
                }
            }
            .navigationTitle(isEditing ? "Rediger abonnement" : "Nytt abonnement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        if hasUnsavedChanges {
                            showsDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    // Festet til knappen, slik at den vises som popover fra "Avbryt" på iPad.
                    .confirmationDialog(
                        "Forkaste endringene?",
                        isPresented: $showsDiscardConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Forkast endringer", role: .destructive) { dismiss() }
                        Button("Fortsett å redigere", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: loadExistingValues)
            // Hindrer at et utfylt skjema forsvinner ved et utilsiktet sveip nedover.
            .interactiveDismissDisabled(hasUnsavedChanges)
            .sensoryFeedback(.success, trigger: saveFeedbackTrigger)
        }
    }

    private func loadExistingValues() {
        // .onAppear kan kjøre flere ganger - da skal ikke brukerens utkast overskrives.
        guard initialSnapshot == nil else { return }
        if let subscription = subscriptionToEdit {
            name = subscription.name
            priceText = subscription.price.formatted(.number.grouping(.never))
            currencyCode = subscription.currencyCode
            billingInterval = subscription.interval
            nextRenewalDate = subscription.nextRenewalDate
            hasTrial = subscription.isInTrial()
            category = subscription.kind
            note = subscription.note ?? ""
            isActive = subscription.isActive
            reminderDaysBefore = subscription.reminderDaysBefore
            symbolName = subscription.symbolName
            colorHex = subscription.colorHex
            splitCount = subscription.splitCount
            cancelLinkText = subscription.cancelURLString ?? ""
        } else {
            currencyCode = mainCurrency
        }
        initialSnapshot = currentSnapshot
    }

    private func save() {
        guard let price else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteToSave = trimmedNote.isEmpty ? nil : trimmedNote
        // Lagres i tolket form, f.eks. "https://netflix.com/cancel".
        let cancelURLToSave = cancelURL?.absoluteString
        // DatePicker viser bare datoen, men beholder klokkeslettet skjemaet ble åpnet.
        // Lagres kl. 12, så datoen er den samme uansett tidspunkt for lagringen.
        let renewalDate = RenewalCalculator.normalizedToNoon(nextRenewalDate)

        let subscription: Subscription
        if let existing = subscriptionToEdit {
            subscription = existing
            // Sammenlign på dag, siden det er alt skjemaet viser. Er dagen uendret, beholdes
            // lagret dato og anker nøyaktig som de er - ellers ville eldre datoer med et annet
            // klokkeslett telt som endret, og en "klemt" dato (f.eks. 28. feb for en
            // 31.-fornyelse) blitt det nye ankeret. Sammenlign med verdiene skjemaet ble åpnet
            // med, ikke de lagrede: synk eller iCloud kan ha flyttet datoen mens skjemaet var
            // åpent (f.eks. over midnatt), og da ville en uendret dato i utkastet overskrevet
            // den nyere og blitt nytt anker.
            let loadedDate = initialSnapshot?.nextRenewalDate ?? existing.nextRenewalDate
            let dateChanged = !Calendar.current.isDate(nextRenewalDate, inSameDayAs: loadedDate)
            let intervalChanged = billingInterval != (initialSnapshot?.billingInterval ?? existing.interval)
            let trialToggled = hasTrial != (initialSnapshot?.hasTrial ?? existing.isInTrial())
            if dateChanged {
                subscription.nextRenewalDate = renewalDate
                subscription.billingAnchorDate = renewalDate
            } else if intervalChanged {
                // Nytt intervall gir ny rytme, regnet fra den lagrede fornyelsesdatoen.
                subscription.billingAnchorDate = subscription.nextRenewalDate
            }
            subscription.name = name
            subscription.price = price
            subscription.currencyCode = currencyCode
            subscription.interval = billingInterval
            // Samme regel for prøveperioden: uendret dato og bryter beholder den lagrede
            // sluttdatoen, også en som allerede er passert.
            if dateChanged || trialToggled {
                subscription.trialEndDate = hasTrial ? subscription.nextRenewalDate : nil
            }
            subscription.kind = category
            subscription.note = noteToSave
            subscription.isActive = isActive
            subscription.reminderDaysBefore = reminderDaysBefore
            subscription.symbolName = symbolName
            subscription.colorHex = colorHex
            subscription.splitCount = splitCount
            subscription.cancelURLString = cancelURLToSave
        } else {
            subscription = Subscription(
                name: name,
                price: price,
                currencyCode: currencyCode,
                billingInterval: billingInterval,
                nextRenewalDate: renewalDate,
                trialEndDate: hasTrial ? renewalDate : nil,
                category: category,
                note: noteToSave,
                isActive: isActive,
                reminderDaysBefore: reminderDaysBefore,
                symbolName: symbolName,
                colorHex: colorHex,
                splitCount: splitCount,
                cancelURLString: cancelURLToSave
            )
            modelContext.insert(subscription)
        }
        // En passert dato flyttes frem med en gang, så abonnementet ikke vises som
        // "Forfalt" frem til neste gang appen blir aktiv.
        subscription.advanceRenewalDateIfPast()

        // Widgeten og varslene oppdateres av `keepsDerivedStateInSync()` når modellen endres.
        Task {
            // Spør om varseltillatelse her, i den konteksten der brukeren nettopp
            // har bedt om å bli varslet - ikke uoppfordret ved appens aller første oppstart.
            await NotificationScheduler.requestAuthorizationIfNeeded()
            // Bevisst ny planlegging etter spørsmålet: synk-modifikatoren kan allerede ha
            // planlagt varslene før tillatelsen ble gitt, og da ble ingen av dem lagt inn.
            await NotificationScheduler.reschedule(using: modelContext)
        }
        saveFeedbackTrigger += 1
        dismiss()
    }
}

/// Rutenett for å velge ikon og farge. `nil` betyr standard: kategoriens ikon og appens aksentfarge.
private struct AppearancePicker: View {
    let category: SubscriptionCategory
    @Binding var symbolName: String?
    @Binding var colorHex: String?

    private let columns = [GridItem(.adaptive(minimum: 44))]

    private var selectedColor: Color {
        colorHex.flatMap(Color.init(hex:)) ?? .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ikon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                iconCell(symbol: category.defaultSymbolName, name: "Standard for kategorien", value: nil)
                // Kategoriens standardikon finnes allerede som "Standard" over.
                ForEach(SubscriptionAppearance.icons.filter { $0.symbolName != category.defaultSymbolName }) { icon in
                    iconCell(symbol: icon.symbolName, name: icon.name, value: icon.symbolName)
                }
            }

            Text("Farge")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                SelectableCircle(isSelected: colorHex == nil, name: "Standard") {
                    colorHex = nil
                } content: {
                    Circle().fill(Color.accentColor)
                }
                ForEach(SubscriptionAppearance.colors) { option in
                    SelectableCircle(isSelected: colorHex == option.hex, name: option.name) {
                        colorHex = option.hex
                    } content: {
                        Circle().fill(Color(hex: option.hex) ?? .accentColor)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func iconCell(symbol: String, name: String, value: String?) -> some View {
        SelectableCircle(isSelected: (symbolName ?? category.defaultSymbolName) == symbol, name: name) {
            symbolName = value
        } content: {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(selectedColor, in: Circle())
        }
    }
}

private struct SelectableCircle<Content: View>: View {
    let isSelected: Bool
    let name: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .frame(width: 36, height: 36)
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: isSelected ? 2.5 : 0)
                        .padding(-4)
                }
                .frame(minWidth: 44, minHeight: 44)
        }
        // Uten .plain gjør Form hele raden til én knapp i stedet for én per rute.
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Nytt abonnement") {
    SubscriptionFormView()
        .modelContainer(for: Subscription.self, inMemory: true)
}

#Preview("Rediger abonnement") {
    SubscriptionFormView(subscriptionToEdit: Subscription(name: "Netflix", price: 149, category: .streaming))
        .modelContainer(for: Subscription.self, inMemory: true)
}
