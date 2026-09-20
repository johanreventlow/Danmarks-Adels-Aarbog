# 1939 — ankerbaseret rekonstruktion af segmentering

## Status og beslutning

Dette er en design-specifikation, ikke en produktionsgodkendelse. Den
eksisterende 1939-databaseversion og det private artefakt med 546 records er
et **kompletheds-kort**, ikke tekstligt eller faktuelt facit. Ingen
databaseprojektion, Supabase-mutation eller deploy indgår i denne ændring.

Målet er at rekonstruere 1939 fra den frosne Calamari-rendition med bedre
læsetekst uden at miste bogens struktur eller videreføre gamle fejl ukritisk.

## Konstateret udgangspunkt

Samme 1939-parserprofil giver to forskellige strukturelle resultater:

| Rendition | Nummererede | Stamfædre | Oversigter | Dubletter | Brugbare records |
|---|---:|---:|---:|---:|---:|
| Rå OCR, v2 | 505 | 23 | 25 | 7 | 546 |
| Calamari, v2 | 483 | 0 | 0 | 0 | 483 |

Calamari bevarer ikke de indryk/centreringssignaler, som den nuværende profil
bruger for linje-, afsnits- og strukturheaders. Alle 483 fundne poster havner
derfor i den kunstige gren `Stamme`; deres locators kan ikke sammenlignes med
de 546 historiske v2-locators. 23 Calamari-kandidater med nummereret
postform afvises af den nuværende navnesats-gate, mod én tilsvarende i rå OCR.

Ægtefæller er ikke selvstændige stamtavleposter i dette lag. De er relationer
inde i en persons kildetekst og forklarer derfor ikke faldet fra 546 til 483.

## Valgt arkitektur

Pipeline skal være en ankerbaseret hybrid:

```
Calamari tekst ─┐
               ├─> kandidatsegmenter ─> positive kildeankre ─> coverage-ledger
Rå OCR struktur ┤                                              ├─ accepteret
PDF-side        ┘                                              └─ menneskeark
```

1. **Kandidatsegmentering.** Calamari er primær rendition for ordret tekst.
   Rå OCR må kun levere strukturkandidater; den må ikke stiltiende erstatte
   Calamari-prosa.
2. **Positive ankre.** Hver kandidat skal have rendition-hash, eksakt
   Calamari-span, PDF-side og en dokumenteret strukturforbindelse til rå OCR
   eller PDF. Et manglende eller flertydigt led giver ikke en locator.
3. **Coverage-ledger.** Hver af de 546 historiske `record_key`s får
   præcis én tilstand: `accepteret`, `eksplicit_dublet` eller
   `menneskeark`. Der må ikke gættes en ækvivalens ud fra navn, løbenummer
   eller tekstlig lighed alene.
4. **Source records.** Kun accepterede kandidater bliver nye
   profile-pinnede source records. Stamfædre og oversigter er egne
   postklasser; de må ikke forsvinde eller presses ind som personer.

## Regler og fejlhåndtering

- Den nye Calamari-segmentering må ikke være grøn, før alle 546
  baseline-records er forklaret i coverage-ledgeren.
- Et automatisk match kræver én-til-én-forbindelse både fra gammel
  `record_key` til nyt kandidatanker og omvendt.
- De syv historisk kendte oversigtsdubletter markeres eksplicit; de tæller
  ikke som tabte personer og forfremmes ikke automatisk.
- De 22 manglende nummererede Calamari-poster må ikke løses ved at slække den
  generelle navnesats-regel. Hver ny accepteret headerregel skal have en
  minimal syntetisk regressionstest og en privat, konkret evidensprøve.
- En konflikt, manglende PDF-side, uafklaret rendition-bro eller
  locator-kollision går til menneskeark og blokerer den pågældende record.

## Implementeringsgrænser

Ændringen omfatter segmentering, den private coverage-ledger og deres
deterministiske validering. Den omfatter ikke:

- faktaudtræk med model,
- ændring eller sletning af eksisterende databaseposter,
- automatisk identitets- eller ægtefællepromovering,
- Supabase- eller Vercel-deploy.

Et nyt faktaudtræk kan først designes efter en dokumenteret grøn
coverage-ledger og særskilt godkendelse.

## Verifikation

Implementeringen skal bevise:

1. den frosne Calamari-inputhash og PDF-sider bruges i hvert anker;
2. Calamari kan repræsentere 505 nummererede kandidater samt 23 stamfædre og
   25 oversigter, eller at hver afvigelse står eksplicit i menneskeark;
3. nettotalen er 546 efter præcis syv eksplicitte dubletter;
4. alle accepterede nye locators er unikke og én-til-én mod
   baseline-`record_key`;
5. bevidst ændret span, side, rendition-hash, duplikat eller tvetydig bro
   fejler lukket.

Testdata i repository skal være syntetiske. Private OCR/PDF-udsnit og
coverage-output forbliver ignorerede arbejdsartefakter.
