import SwiftUI

/// Innstillinger for hovedvaluta og utseende.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKeys.glassIntensity) private var glassIntensity: Double = 0.6
    @AppStorage(AppSettingsKeys.mainCurrency) private var mainCurrency = AppSettingsKeys.defaultMainCurrency
    @Environment(ExchangeRateStore.self) private var exchangeRates

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Hovedvaluta", selection: $mainCurrency) {
                        ForEach(CurrencyConverter.supportedCurrencies, id: \.self) { code in
                            Text("\(code) – \(CurrencyConverter.displayName(for: code))").tag(code)
                        }
                    }
                } header: {
                    Text("Valuta")
                } footer: {
                    Text(currencyFooter)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Glass-styrke")
                            Spacer()
                            Text(glassIntensity, format: .percent.precision(.fractionLength(0)))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $glassIntensity, in: 0...1)
                            .accessibilityLabel("Glass-styrke")
                            .accessibilityValue(glassIntensity.formatted(.percent.precision(.fractionLength(0))))
                    }
                } header: {
                    Text("Utseende")
                } footer: {
                    Text("Styrer hvor gjennomsiktig og «glassaktig» kort og paneler i appen ser ut.")
                }
            }
            .navigationTitle("Innstillinger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
    }
}

private extension SettingsView {
    var currencyFooter: String {
        let explanation = "Totalsummer og statistikk regnes om til denne valutaen."
        guard let rates = exchangeRates.rates else {
            return "\(explanation) Kurser er ikke hentet ennå – det krever nett første gang."
        }
        let date = rates.rateDate.formatted(date: .abbreviated, time: .omitted)
        return "\(explanation) Kurser fra Den europeiske sentralbanken (via Frankfurter), per \(date)."
    }
}

#Preview {
    SettingsView()
        .environment(ExchangeRateStore())
}
