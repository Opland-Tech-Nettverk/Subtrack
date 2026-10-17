# Subtrack

Subtrack er en iOS-app som gir deg oversikt over abonnementene dine: hva de koster, når de fornyes, og hva du har spart på dem du har sagt opp.

> **Merk:** Koden er åpen for innsyn, men er **ikke åpen kildekode**. Du kan lese den, men ikke bruke, kopiere, endre eller distribuere den uten skriftlig tillatelse. Se [Lisens](#lisens).

## Funksjoner

- **Oversikt over abonnement** med pris, intervall (ukentlig, månedlig, kvartalsvis, årlig) og neste fornyelse. Kan sorteres etter fornyelse, pris, navn eller kategori, og søkes i.
- **Flere valutaer.** Abonnement kan legges inn i 30 valutaer og regnes om til hovedvalutaen din. Kursene hentes fra [Frankfurter](https://frankfurter.dev) (Den europeiske sentralbanken).
- **Delte abonnement.** Del kostnaden likt med andre, for eksempel et familieabonnement. Totaler og statistikk bruker din andel.
- **Gratis prøveperioder.** Du får varsel før første betaling, så du rekker å si opp.
- **Påminnelser** før hver fornyelse, med en knapp som åpner avslutningssiden direkte fra varselet.
- **Pause og arkiv.** Sett abonnement på pause, eller avslutt dem. Da ser du hvor mye du har spart siden.
- **Statistikk.** Kostnad per kategori og de dyreste abonnementene.
- **Widget.** «Neste trekk» på Hjem-skjermen i liten og middels størrelse.
- **iCloud-synk** mellom enhetene dine med CloudKit.

## Teknologi

- Swift og SwiftUI
- SwiftData med CloudKit-synk og versjonert skjema
- WidgetKit med App Group for data delt med widgeten
- UserNotifications for lokale varsler
- Swift Charts
- Swift Testing for enhetstester og XCTest for UI-tester

Appen har ingen avhengigheter til tredjepartsbiblioteker, ingen sporing og ingen analyse.

## Krav

- iOS / iPadOS 17 eller nyere
- Xcode 27 eller nyere

## Prosjektstruktur

```
Subtrack/
  App/          Oppstart, database, synk av widget og varsler, feilskjerm
  Models/       SwiftData-modellen og det versjonerte skjemaet
  Services/     Datoer, valuta, prisfelt, varsler og widget-data
  Views/        Oversikt, skjema, statistikk, innstillinger og delte komponenter
SubtrackWidget/ Widget-utvidelsen
SubtrackTests/  Enhetstester
SubtrackUITests/ UI-tester
```

## Personvern

- Abonnementene dine lagres på enheten og i din egen private iCloud-database. Vi ser dem aldri.
- Det eneste appen sender over nettet, er en forespørsel om valutakurser til Frankfurter. Den inneholder ingen personopplysninger, men som ved all nettrafikk ser tjenesten IP-adressen til enheten.

## Bidrag og tilbakemeldinger

Feilrapporter og forslag tas gjerne imot som [issues](../../issues).

Vi tar for tiden ikke imot pull requests. Kode som sendes inn, må kunne lisensieres til oss, og det har vi ingen ordning for ennå.

## Lisens

Copyright © 2026 Opland Tech Nettverk. Alle rettigheter forbeholdt.

Kildekoden er gjort offentlig kun for innsyn. Det er ikke gitt noen rett til å bruke, kopiere, endre, bygge, distribuere eller selge koden eller deler av den. Navnet «Subtrack» og appikonet er heller ikke lisensiert. Se [LICENSE](LICENSE) for de fullstendige vilkårene.

Ønsker du å bruke koden til noe, ta kontakt for skriftlig tillatelse.
