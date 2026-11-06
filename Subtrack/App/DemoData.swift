import SwiftUI
import SwiftData

/// Hva appen viser ved start i demomodus, til skjermbilder i CI. Startes med `-UITesting -DemoData`
/// og kan kombineres med `-DemoScreen <navn>` og `-DemoScroll <id>`. Fargemodus og tekststørrelse
/// settes utenfra med `simctl ui`. Bare DEBUG: i en release-bygg er alt her `nil` eller `false`.
enum DemoLaunch {
    /// Skjermen som skal åpnes: `overview`, `overview-day`, `detail`, `calendar`, `statistics`,
    /// `statistics-category` eller `empty` (ingen data). `nil` utenfor demomodus.
    static var screen: String? {
        #if DEBUG
        guard AppEnvironment.isDemo else { return nil }
        return UserDefaults.standard.string(forKey: "DemoScreen")
        #else
        return nil
        #endif
    }

    /// `id` på stedet skjermen ruller til ved start (`end` er bunnen). `nil` utenfor demomodus.
    static var scrollTarget: String? {
        #if DEBUG
        guard AppEnvironment.isDemo else { return nil }
        return UserDefaults.standard.string(forKey: "DemoScroll")
        #else
        return nil
        #endif
    }

    static var tab: AppTab? {
        switch screen {
        case "calendar": .calendar
        case "statistics", "statistics-category": .statistics
        default: nil
        }
    }

    static var opensDetail: Bool { screen == "detail" }

    /// `import-intro`, `import-loading` og `import-review` åpner importen av kontoutskrift direkte.
    static var opensImport: Bool { screen?.hasPrefix("import-") == true }

    /// Forslagene `import-review` viser, uten at noen fil er lest. `nil` ellers.
    static var statementAnalysis: StatementAnalysis? {
        #if DEBUG
        guard screen == "import-review" else { return nil }
        return DemoData.statementAnalysis()
        #else
        return nil
        #endif
    }
    static var selectsFirstDay: Bool { screen == "overview-day" }
    static var category: SubscriptionCategory? { screen == "statistics-category" ? .streaming : nil }

    /// Ruller en skjerm til `scrollTarget`. Venter litt, så listen har rukket å legge seg ut.
    @MainActor
    static func scroll(_ proxy: ScrollViewProxy) async {
        guard let target = scrollTarget else { return }
        try? await Task.sleep(for: .milliseconds(800))
        proxy.scrollTo(target, anchor: target == "end" ? .bottom : .top)
    }
}

#if DEBUG

enum DemoData {
    /// Forslag til importen av kontoutskrift, slik analysen av en fil med et halvt års betalinger kunne gitt.
    static func statementAnalysis(now: Date = .now, calendar: Calendar = .current) -> StatementAnalysis {
        func day(_ daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
        }
        func suggestion(
            _ name: String, _ price: Decimal, currency: String = "NOK", interval: BillingInterval = .monthly,
            confidence: SubscriptionSuggestion.Confidence = .high, lastCharge daysAgo: Int, charges: Int,
            category: SubscriptionCategory, symbol: String, color: String, similarTo: String? = nil
        ) -> SubscriptionSuggestion {
            let last = day(daysAgo)
            let next = interval.advanced(from: last, calendar: calendar)
            var draft = SubscriptionDraft(source: .bankStatement)
            draft.name = name
            draft.price = price
            draft.currencyCode = currency
            draft.interval = interval
            draft.kind = category
            draft.symbolName = symbol
            draft.colorHex = color
            draft.nextRenewalDate = next
            return SubscriptionSuggestion(
                id: name.lowercased(), name: name, price: price, currencyCode: currency, interval: interval,
                confidence: confidence, lastChargeDate: last, nextExpectedDate: next, chargeCount: charges,
                service: nil, draft: draft, similarTo: similarTo
            )
        }
        let suggestions = [
            suggestion("Netflix", 179, lastCharge: 12, charges: 6, category: .streaming, symbol: "play.tv", color: "#FF453A"),
            suggestion("Spotify Premium", 129, lastCharge: 20, charges: 6, category: .musikk, symbol: "music.note", color: "#30D158"),
            suggestion("Viaplay", 199, lastCharge: 8, charges: 6, category: .streaming, symbol: "play.tv", color: "#FF375F"),
            suggestion("iCloud+", 39, lastCharge: 3, charges: 6, category: .nettsky, symbol: "icloud", color: "#40C8E0"),
            suggestion("ChatGPT Plus", 20, currency: "USD", lastCharge: 17, charges: 5, category: .ai, symbol: "sparkles", color: "#30D158"),
            suggestion("Fitness", 349, lastCharge: 25, charges: 6, category: .trening, symbol: "figure.run", color: "#FF9F0A", similarTo: "Fitness24Seven"),
            suggestion("Bærum Svømmehall", 299, confidence: .medium, lastCharge: 30, charges: 4, category: .trening, symbol: "figure.run", color: "#40C8E0")
        ]
        return StatementAnalysis(
            transactionCount: 187, periodStart: day(180), periodEnd: day(2), periodDays: 178, suggestions: suggestions
        )
    }

    /// Legger inn norske eksempelabonnement, med datoer regnet fra i dag så skjermbildene alltid
    /// viser trekk de neste ukene. Ingen logoer: bare SF Symbols og farger fra paletten.
    static func seed(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        func renewal(inDays days: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
            return RenewalCalculator.normalizedToNoon(day, calendar: calendar)
        }

        let active: [Subscription] = [
            Subscription(name: "iCloud+", price: 39, nextRenewalDate: renewal(inDays: 0), category: .nettsky, symbolName: "icloud", colorHex: "#40C8E0"),
            Subscription(name: "Netflix", price: 179, nextRenewalDate: renewal(inDays: 1), category: .streaming, symbolName: "play.tv", colorHex: "#FF453A"),
            Subscription(name: "SATS", price: 649, nextRenewalDate: renewal(inDays: 3), category: .trening, symbolName: "figure.run", colorHex: "#FF9F0A"),
            Subscription(name: "Spotify Familie", price: 279, nextRenewalDate: renewal(inDays: 4), category: .musikk, symbolName: "music.note", colorHex: "#30D158", splitCount: 3),
            Subscription(
                name: "Max", price: 119, nextRenewalDate: renewal(inDays: 5), trialEndDate: renewal(inDays: 5),
                category: .streaming, symbolName: "film", colorHex: "#5E5CE6"
            ),
            Subscription(name: "Storytel", price: 249, nextRenewalDate: renewal(inDays: 6), category: .boker, symbolName: "book", colorHex: "#BF5AF2"),
            Subscription(name: "Viaplay", price: 199, nextRenewalDate: renewal(inDays: 9), category: .streaming, symbolName: "play.tv", colorHex: "#FF375F"),
            Subscription(name: "Adobe Creative Cloud", price: 699, nextRenewalDate: renewal(inDays: 12), category: .programvare, symbolName: "terminal", colorHex: "#FF375F"),
            Subscription(
                name: "ChatGPT Plus", price: 20, currencyCode: "USD", nextRenewalDate: renewal(inDays: 14),
                category: .ai, symbolName: "sparkles", colorHex: "#30D158"
            ),
            Subscription(name: "Aftenposten", price: 449, nextRenewalDate: renewal(inDays: 17), category: .nyheter, symbolName: "newspaper", colorHex: "#8E8E93"),
            Subscription(name: "Xbox Game Pass", price: 129, nextRenewalDate: renewal(inDays: 22), category: .spill, symbolName: "gamecontroller", colorHex: "#30D158"),
            Subscription(
                name: "Microsoft 365 Familie", price: 899, billingInterval: .yearly, nextRenewalDate: renewal(inDays: 40),
                category: .programvare, symbolName: "terminal", colorHex: "#5E5CE6"
            ),
            Subscription(
                name: "Dropbox Plus", price: 1190, billingInterval: .yearly, nextRenewalDate: renewal(inDays: 150),
                category: .nettsky, symbolName: "icloud", colorHex: "#40C8E0"
            )
        ]

        let paused = Subscription(
            name: "YouTube Premium", price: 129, nextRenewalDate: renewal(inDays: 8),
            category: .streaming, isActive: false, symbolName: "play.tv", colorHex: "#FF453A"
        )

        func cancelled(_ name: String, price: Decimal, daysAgo: Int, category: SubscriptionCategory, symbol: String, color: String) -> Subscription {
            let subscription = Subscription(
                name: name, price: price, nextRenewalDate: renewal(inDays: 20), category: category,
                symbolName: symbol, colorHex: color
            )
            subscription.cancelledDate = calendar.date(byAdding: .day, value: -daysAgo, to: now)
            return subscription
        }

        let archived = [
            cancelled("HBO Max", price: 129, daysAgo: 75, category: .streaming, symbol: "film", color: "#BF5AF2"),
            cancelled("Strim", price: 99, daysAgo: 21, category: .streaming, symbol: "play.tv", color: "#FF9F0A"),
            cancelled("Fitness24Seven", price: 349, daysAgo: 130, category: .trening, symbol: "figure.run", color: "#FF453A")
        ]

        for subscription in active + [paused] + archived {
            context.insert(subscription)
        }
    }
}

#endif
