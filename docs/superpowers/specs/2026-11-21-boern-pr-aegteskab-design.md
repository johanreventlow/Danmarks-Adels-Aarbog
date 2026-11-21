# Børn pr. ægteskab på personsiden, i bogens rækkefølge — design

Dato: 2026-11-21 · Størrelse: lille ændring (web-visning, ingen DB)

## Hvorfor

Personer med flere ægteskaber (fx Conrad Reventlow, gift med Anna Margrethe Gabel og
Sophie Amalie Hahn) viser i dag »Gift med« og »Børn« som to adskilte lister. Læseren kan
ikke se, hvilket barn der kommer fra hvilken hustru. Børnene står desuden i den rækkefølge,
databasen leverer dem, ikke nødvendigvis bogens.

## Mål

- Personsiden (`/person/<id>`): ved ≥ 2 ægteskaber grupperes »Børn« med en underoverskrift
  pr. ægteskab (»Med <ægtefælle>«). Børn uden kendt ægteskab samles sidst med samme note
  som stamtræet (`BOERN_UDEN_AEGTESKAB`).
- Børn sorteres i Aarbogens rækkefølge, både i grupperne og i den flade liste (ét ægteskab).
- Personside og stamtræ (`fokusTrae.ts`) bruger samme gruppering og sortering.

## Ikke-mål

- Ingen ændring af data, skema eller indlæsning.
- Mobil-appen (dev-only) røres ikke.
- »Gift med«-rækken ændres ikke (valgt tilgang A).

## Tilgange

- **A (valgt af projektejeren):** »Gift med« uændret; »Børn« får underoverskrift pr. ægteskab.
  Bevarer sidens struktur og læses som stamtræet.
- **B (fravalgt):** børn direkte under hver ægtefælle i »Gift med«, »Børn«-rækken forsvinder.
  Kompakt og bog-agtigt, men ændrer familieafsnittet mere.

## Bogens rækkefølge

Kilden er barnets stamtavlenummer (`person_external_id.nr` + `nr_label`, fx 14 / »15a«);
loaderen hentede netop børn via forælderens `nr_range`, så nummeret *er* bogens orden.
`family_member.ordinal` er kun ægteskabsnummer for partnere og bruges ikke.

Sorteringsnøgle pr. barn (projektejerens godkendte regel):
1. Nummeret i den udgave og linje, hvor forælderen selv står; nyeste udgave foretrækkes.
2. `nr_label` som tiebreak (»15a« før »15b«).
3. Børn uden nummer i den udgave, men med nummer i en ældre udgave, flettes ind lige før det
   første barn, der står efter dem i den ældre udgave (prod 21/11: Conrads 1939-børn nr. 1-2,
   Frederik 1792 og Charlotte Amalie 1793, findes ikke i 2018-20 og har ingen fødselsdato).
4. Resten: efter fødselsår, sidst; derefter navn (deterministisk).
5. Linje: den linje flest af børnene står i (lige: forælderens linje); 1939 blander legacy-koden
   »1939« og skemakoden IV i samme udgave (review I1). Et barn med flere numre i samme udgave
   bruger nummeret i den linje (review I2).

## Overladt til implementeringen

- Hvor sorteringsnøglen bor (forslag: ren funktion i `packages/core` over `RawExtId`-afledt
  indeks på modellen) og hvordan fokusTrae's grupperingslogik flyttes ud til fælles brug.
- Præcis markup/stil for underoverskriften (følg eksisterende `dtStil`/serif-mønstre).
