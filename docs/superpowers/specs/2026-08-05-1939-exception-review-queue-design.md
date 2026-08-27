# 1939 undtagelseskø til evidensreview

## Status og formål

Dette design erstatter den obligatoriske gennemgang af alle 546 historiske
baseline-poster med en fail-closed undtagelseskø. Redaktøren skal kun arbejde
med poster, som systemet ikke kan afgøre med komplet, positiv og reproducerbar
evidens. Automatisk afgjorte poster forbliver synlige som statistik og kan
åbnes til stikprøvekontrol.

Den eksisterende V5-visning er ikke i sig selv en sikker klassifikation. Den
viser kandidater fra samme PDF-side, men sidefællesskab beviser ikke identitet.
På det nuværende private artefakt har 403 af 546 poster flere viste kandidater,
133 har ingen, og 153 indeholder gentagne kandidater som følge af sidespænd.

Leverancen er privat og lokal. Den skriver ikke til databasen, Supabase eller
Vercel og overskriver aldrig den eksisterende review-JSON.

## Faglig sikkerhedsgrænse

En baseline-post må kun klassificeres som automatisk afgjort, når alle disse
krav er opfyldt:

1. Der findes præcis én afgrænset kandidatpost.
2. Kandidaten har eksakte ankre i Calamari-teksten og den rå OCR.
3. Kandidatens PDF-sider stemmer med de verificerede kildeankre.
4. Kandidaten er positivt knyttet til baseline-posten; navn eller sidetal alene
   er ikke tilstrækkeligt.
5. Ingen anden baseline-post gør krav på samme kandidat.
6. Kandidatens tekstankre overlapper ikke en anden accepteret kandidat.
7. Der findes ingen konfliktmarkering, dubletmistanke eller strukturel
   uregelmæssighed.
8. Inputfiler, ekstraktionsprofil og beslutning er hash- og versionsbundet.

Hvis ét krav mangler, må posten ikke skjules som automatisk afgjort. En score
eller rangering må hjælpe redaktøren med at læse kandidater, men må aldrig
erstatte kravene.

## Klassifikation og stikprøve

En ren, deterministisk klassifikator placerer hver af de 546 unikke
`record_key`-værdier i præcis én gruppe:

- `auto_resolved`: alle faglige gates består;
- `human_required`: mindst én plausibel vej findes, men menneskelig semantisk
  vurdering er nødvendig;
- `source_blocked`: materialet er mangelfuldt eller ugyldigt, så posten ikke
  kan afgøres på det foreliggende grundlag.

Hver klassifikation bærer en stabil, maskinlæsbar årsagskode og en kort dansk
forklaring. Summen af de tre grupper skal altid være 546.

Fra `auto_resolved` vælges en reproducerbar, stratificeret stikprøve på fem
procent, dog mindst to poster fra hver forekommende post- eller regeltype.
Kildehashene bruges som deterministisk seed. En fejl i stikprøven blokerer den
berørte regelgruppe eller batch til genundersøgelse; den enkelte fejl må ikke
rettes isoleret, mens samme automatiske regel fortsætter uændret.

## Redaktørens arbejdsgang

Forsiden viser fire tal og indgange:

- Kræver din vurdering;
- Automatisk afgjort;
- Stikprøve;
- Afsluttet.

Den obligatoriske kø viser én sag ad gangen. Øverst forklares på almindeligt
dansk, hvorfor sagen er i køen. Den gamle baseline-tekst og *alle* deduplikerede
kandidater vises side om side, alle foldet ud fra start (ændret 2026-08-07;
tidligere blev kun de tre højest rangerede vist bag `Vis alle kandidater`).
Ingen kandidat skjules. Rangeringen er kun læsehjælp. Tekniske felter som hashes og
interne nøgler skjules under `Vis detaljer`.

Redaktøren vælger én af fire handlinger:

- `human_selected_candidate`: Denne kandidat er den rigtige kildepost.
- `no_candidate_fits`: Ingen af kandidaterne passer.
- `possible_duplicate`: Dette ser ud som en dublet.
- `undecidable`: Jeg kan ikke afgøre det.

Handlingerne er redaktionelle observationer, ikke promotionstatusser. Et
`human_selected_candidate` må først blive `accepteret`, efter at efterkontrollen
har etableret og valideret alle eksakte ankre og globale invariants.

Et valg autosaves straks. Brugerfladen viser først en grøn kvittering, når
lagringen faktisk er lykkedes, og går derefter til næste sag. Forrige, Næste og
Fortryd bevares. Samme visning bruges til stikprøver, men markerer tydeligt, at
redaktøren kontrollerer en automatisk afgørelse.

## Komponenter og dataflow

Løsningen opdeles i fire afgrænsede enheder:

1. `classify_review_1939` modtager versionsbundne kandidater og evidenspas og
   producerer den komplette klassifikation med årsagskoder.
2. `sample_auto_resolved_1939` producerer den deterministiske, stratificerede
   stikprøve uden at ændre klassifikationerne.
3. HTML-generatoren bygger et selvstændigt, privat visningsartefakt. Den
   foretager ingen matching eller promotion.
4. Den eksisterende review-/coverage-validering importerer eksplicitte
   redaktørvalg, efterprøver ankre og skriver kun nye outputfiler eksklusivt.

Browserkoden bruger normale event listeners eller event delegation. Dynamiske
inline-`onclick`-attributter er forbudt. V5-fejlen skyldes, at et JSON-citeret
kandidat-id blev indsat i en allerede dobbeltciteret `onclick`-attribut, så
browseren kun læste handleren som `setTrack(`.

Kandidater deduplikeres efter en stabil kandidatidentitet, ikke efter sidetal
eller visningstekst. En kandidat, der spænder over to sider, vises derfor kun
én gang.

## Lokal lagring og eksport

Kladder lagres i browserens `localStorage` under en nøgle, der mindst omfatter
baseline-hash og review-schema-version. En kladde med forkert hash eller
version afvises synligt.

Eksporten indeholder:

- schema-version;
- baseline-, Calamari-, rå-OCR- og PDF-hash;
- ekstraktionsprofil og version;
- eksporttidspunkt;
- alle menneskelige beslutninger og deres stabile baseline-nøgle;
- eventuelt valgt kandidat-id, men ingen automatisk promotion.

Eksporten er den flytbare og varige kopi. `localStorage` er kun en lokal
arbejdskladde.

## Fejlhåndtering

- Manglende, fuldt eller defekt browserlager viser en vedvarende fejl og
  kræver eksport; brugerfladen må ikke vise `gemt`.
- Ukendt kandidat-id, forkert baseline-hash, overlappende ankre og
  dobbelttildeling af en kandidat afvises fail-closed.
- Poster uden gyldige kandidater viser den konkrete årsag og tilbyder ikke en
  falsk kandidatbeslutning.
- Hvis et menneskevalg ikke kan efterforankres, forbliver posten blokeret med
  den præcise valideringsfejl.
- Ingen fejlvej må falde tilbage til navn-, nummer- eller sidebaseret gæt.

## Test- og acceptkriterier

### Klassifikation

- Alle 546 baseline-poster findes i præcis én klassifikation.
- Hver manglende faglig gate tvinger posten ud af `auto_resolved`.
- Kandidatidentitet er globalt injektiv, og accepterede tekstankre overlapper
  ikke.
- Samme input giver identisk klassifikation og stikprøve.
- Kandidater over flere sider deduplikeres.

### Brugerflade

- Alle fire handlinger testes i en rigtig DOM.
- En regressionstest beviser, at kandidatknappen faktisk registrerer korrekt
  kandidat-id; tekstsøgning i genereret HTML er ikke tilstrækkelig.
- Autosave testes ved genindlæsning og gendannelse.
- Grøn kvittering vises kun efter vellykket `localStorage.setItem`.
- Forrige, Næste, Fortryd, filtre og automatisk fortsættelse testes.
- Eksport og genindlæsning bevarer beslutningerne identisk.

### Fail-closed scenarier

- Forkert baseline-hash, ukendt kandidat-id, overlappende ankre og
  dobbelttildeling afvises.
- Fejl fra `localStorage` er synlige og må ikke rapporteres som gemt.
- En fejl i stikprøven blokerer den relevante regelgruppe.

### Virkelig 1939-pilot

- Den private pilot rapporterer eksakte antal i hver kategori og stikprøve.
- Volrad-eksemplet viser Volrad-parserposten præcis én gang med korrekt
  parsergrænse og fungerende beslutningsknap; øvrige relevante kandidater på
  sagen forbliver tilgængelige.
- Fokuserede DOM-, klassifikations- og roundtrip-tests samt hele scriptsuiten
  rapporteres separat.
- Ingen database-, Supabase- eller Vercel-skrivning udføres.
