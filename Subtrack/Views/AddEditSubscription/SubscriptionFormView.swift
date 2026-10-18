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
    /// Kalles når brukeren avslutter abonnementet fra skjemaet. Er den satt, står kalleren
    /// for selve avslutningen (dato, angre-banner, haptikk og VoiceOver-kunngjøring), og
    /// skjemaet bare lukkes. `nil` betyr at skjemaet avslutter abonnementet selv.
    var onArchive: ((Subscription) -> Void)? = nil

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
    /// Økes når abonnementet avsluttes fra skjemaet, for haptisk tilbakemelding.
    @State private var archiveFeedbackTrigger = 0
    /// Utkastet slik det var da skjemaet ble lastet. `nil` betyr at det ikke er lastet ennå.
    @State private var initialSnapshot: Draft?
    @State private var showsDiscardConfirmation = false
    @State private var showsArchiveConfirmation = false
    /// Settes én gang ved lasting, så seksjonen ikke forsvinner under
    /// lukkeanimasjonen når abonnementet nettopp er avsluttet.
    @State private var canArchive = false

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

    /// Lagret navn, siden ulagrede endringer i utkastet forkastes.
    private var archiveConfirmationTitle: Text {
        Text("Avslutte \(subscriptionToEdit?.name ?? "")?")
    }

    /// Nevner at ulagrede endringer forkastes, siden "Avslutt" ikke spør om dem slik "Avbryt" gjør.
    private var archiveConfirmationMessage: Text {
        if hasUnsavedChanges {
            return Text("Abonnementet flyttes til Avsluttede, så du ser hva du sparer. Du kan gjenoppta det senere. Endringene du ikke har lagret, blir forkastet.")
        }
        return Text("Abonnementet flyttes til Avsluttede, så du ser hva du sparer. Du kan gjenoppta det senere.")
    }

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
                    Text("Avslutningslenke")
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

                // Avslutning tilbys bare for et eksisterende abonnement som ikke allerede er avsluttet.
                // `canArchive` er fanget ved lasting, ikke lest live fra `isCancelled`.
                if canArchive, subscriptionToEdit != nil {
                    Section {
                        Button(role: .destructive) {
                            showsArchiveConfirmation = true
                        } label: {
                            Label("Avslutt abonnement", systemImage: "archivebox")
                        }
                    }
                }
            }
            // Varsel i stedet for bekreftelsesdialog: festet til knappen ble dialogen en smal
            // popover ved store tekststørrelser, der tittelen ble orddelt og meldingen kuttet.
            // Festet her, utenfor den betingede seksjonen, så den ikke forsvinner med den.
            .alert(
                archiveConfirmationTitle,
                isPresented: $showsArchiveConfirmation,
                presenting: subscriptionToEdit
            ) { subscription in
                Button("Avslutt", role: .destructive) { archive(subscription) }
                Button("Avbryt", role: .cancel) {}
            } message: { _ in
                archiveConfirmationMessage
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
            // Samme haptikk som når abonnementet avsluttes med sveip i listen.
            .sensoryFeedback(.impact(weight: .medium), trigger: archiveFeedbackTrigger)
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
            canArchive = !subscription.isCancelled
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

    /// Flytter abonnementet til Avsluttede, slik sveipehandlingen i listen gjør.
    /// Er `onArchive` satt, overlates avslutningen til kalleren (som setter `cancelledDate`,
    /// viser angre-banneret og gir haptikk og VoiceOver-kunngjøring), så den skjer på samme
    /// måte som fra listen. Ellers settes `cancelledDate` her, med egen haptikk.
    /// Uansett endres bare `cancelledDate`: andre ulagrede endringer i utkastet forkastes. Da
    /// gjør knappen nøyaktig det den sier, og avslutningen lagrer ikke halvferdige endringer.
    /// I motsetning til "Avbryt" kommer det ingen egen forkast-dialog; i stedet sier
    /// bekreftelsesvarselet fra om at ulagrede endringer forkastes. Programmatisk
    /// `dismiss()` hindres ikke av `interactiveDismissDisabled`, som bare gjelder sveip nedover.
    private func archive(_ subscription: Subscription) {
        if let onArchive {
            onArchive(subscription)
        } else {
            // Widgeten og varslene oppdateres av `keepsDerivedStateInSync()` når modellen endres.
            subscription.cancelledDate = .now
            archiveFeedbackTrigger += 1
        }
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
        colorHex.flatMap(SubscriptionAppearance.color(forHex:)) ?? .accentColor
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
                        Circle().fill(SubscriptionAppearance.color(forHex: option.hex) ?? .accentColor)
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
