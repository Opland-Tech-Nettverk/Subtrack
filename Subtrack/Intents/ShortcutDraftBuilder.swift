import Foundation

/// Gjør parameterne fra snarveien «Legg til abonnement» om til et utkast for skjemaet.
/// Ren funksjon uten SwiftData og UI, så den kan testes direkte.
enum ShortcutDraftBuilder {
    /// Utkast fra snarveien. Finnes navnet i katalogen (likt navn eller alias, uten hensyn til
    /// store/små bokstaver og diakritiske tegn), brukes tjenestens utkast som grunnlag og
    /// katalognavnet; ellers brukerens navn. Parametere som er satt, vinner over katalogen.
    ///
    /// Er navnet ikke likt, men inneholder et sikkert katalogtreff (`match(merchantText:)` med
    /// `.high`), f.eks. "Netflix Premium", fylles ikon, farge, kategori og avslutningslenke ut
    /// fra tjenesten, og brukerens navn beholdes. Prisen fylles da bare ut når navnet også
    /// nevner en plan ("Premium"), fordi første plan ofte er feil for slike navn. Skjemaet
    /// viser planene uansett, så riktig pris er ett trykk unna. Treff med `.medium` (korte
    /// alias som "max") brukes ikke, fordi de lett treffer feil tjeneste.
    ///
    /// Er intervallet satt uten pris, brukes en plan med samme intervall, f.eks. årsplanen.
    /// Har tjenesten ingen slik plan, står prisen tom i stedet for å vise feil beløp.
    static func makeDraft(
        name: String,
        price: Double?,
        interval: BillingInterval?,
        category: SubscriptionCategory?,
        nextRenewalDate: Date?,
        catalog: ServiceCatalog = .bundled
    ) -> SubscriptionDraft {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var draft: SubscriptionDraft
        if let service = exactService(named: trimmedName, in: catalog) {
            draft = draftFromCatalog(service, plan: plan(in: service, interval: interval))
            draft.name = service.name
        } else if let match = catalog.match(merchantText: trimmedName), match.confidence == .high {
            let service = match.service
            draft = draftFromCatalog(service, plan: plan(in: service, namedIn: trimmedName, interval: interval))
            draft.name = trimmedName
        } else {
            draft = SubscriptionDraft(source: .shortcut)
            draft.name = trimmedName.isEmpty ? nil : trimmedName
        }

        if let price = decimalPrice(price) {
            draft.price = price
        }
        if let interval {
            draft.interval = interval
        }
        if let category {
            draft.kind = category
        }
        if let nextRenewalDate {
            draft.nextRenewalDate = nextRenewalDate
        }
        return draft
    }

    /// Tjenesten der navnet eller et alias er likt `name`, uten hensyn til store/små bokstaver
    /// og diakritiske tegn. Ved flere treff vinner den som står først i katalogen.
    private static func exactService(named name: String, in catalog: ServiceCatalog) -> CatalogService? {
        let key = comparisonKey(name)
        guard !key.isEmpty else { return nil }
        return catalog.services.first { service in
            comparisonKey(service.name) == key || service.aliases.contains { comparisonKey($0) == key }
        }
    }

    private static func comparisonKey(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Tjenestens utkast med `plan`, eller uten pris, valuta og intervall når ingen plan passer.
    private static func draftFromCatalog(_ service: CatalogService, plan: CatalogPlan?) -> SubscriptionDraft {
        var draft = service.draft(plan: plan)
        draft.source = .shortcut
        if plan == nil {
            // `draft(plan: nil)` velger første plan, som ikke passer her.
            draft.price = nil
            draft.currencyCode = nil
            draft.interval = nil
        }
        return draft
    }

    /// Første plan med intervallet, eller første plan når intervallet ikke er satt.
    private static func plan(in service: CatalogService, interval: BillingInterval?) -> CatalogPlan? {
        service.plans.first { interval == nil || $0.interval == interval }
    }

    /// Planen som navnet nevner, f.eks. "Premium" i "Netflix Premium". Lengste navn vinner,
    /// så "Premium Plus" velges foran "Premium". nil når navnet ikke nevner noen plan.
    private static func plan(in service: CatalogService, namedIn name: String, interval: BillingInterval?) -> CatalogPlan? {
        let paddedName = " \(MerchantText.normalized(name)) "
        let named = service.plans
            .filter { interval == nil || $0.interval == interval }
            .map { (plan: $0, key: MerchantText.normalized($0.label)) }
            .filter { !$0.key.isEmpty && paddedName.contains(" \($0.key) ") }
        // `max(by:)` beholder den første av like lange, altså katalogens rekkefølge.
        return named.max(by: { $0.key.count < $1.key.count })?.plan
    }

    /// Prisen som `Decimal` uten binær støy: 149.9 blir 149,9 og ikke 149,900000000000005.
    /// nil for null, negative og ikke-endelige verdier.
    private static func decimalPrice(_ price: Double?) -> Decimal? {
        guard let price, price.isFinite, price > 0 else { return nil }
        // `String(_:)` gir den korteste teksten som leses tilbake som samme `Double`.
        guard let value = Decimal(string: String(price), locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }
}
