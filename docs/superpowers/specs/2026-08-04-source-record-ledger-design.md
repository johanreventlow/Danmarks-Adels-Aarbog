# Source-record-ledger for profile-pinnet extraction

## Formål og afgrænsning

Denne lille adapter lukker hullet mellem en menneskeligt accepteret
segmentering og `evidence_extract.prepare_batch`. Den opretter private,
versionsstabile source records og deres accepterede anchor-events, så et batch
kan referere til opaque `record_key` uden at gøre en kildepost til en kanonisk
person eller ændre databasen.

Den omfatter ikke modelkald, persona-/identitetsmatching, canonical
projektion, redaktionelle placements eller automatisk segmentering. Den
bevarer editionsisolering: 1939 og 2018-20 får aldrig samme source record.

## Dataflow

En privat review-fil er det eneste input. Hver accepteret række angiver:

- et menneskeligt udstedt, stabilt `acceptance_id`;
- source-id og rendition-id med den frosne rendition-hash;
- et eksplicit record-kind, verbatim tekst og præcis span;
- `decision_status: accepted` samt reviewer og beslutningsversion.

Adapteren læser en privat append-only ledger. For en hidtil ukendt
`acceptance_id` mintes et nyt UUID-baseret `record_key`; for en kendt ID
kontrolleres, at source, rendition-hash, record-kind, span og verbatim
teksthash er byte-identiske. Et mismatch er en fejl, ikke en remapning. Den
skriver derefter en evidence bundle med `source_records`,
`source_record_occurrences` og accepterede `source_record_anchor_events`.
Det bundle er input til et senere profile-pinnet batchmanifest.

Ingen record key må konstrueres af navn, side, nummer, OCR-position, teksthash
eller segmentets rækkefølge. De felter må udelukkende kontrollere, at den
menneskelige accept stadig peger på samme tekst.

## Fejl- og sikkerhedsregler

- En uaccepteret, manglende eller dublet `acceptance_id` stopper hele kørslen.
- En acceptance kan kun forekomme én gang pr. source/rendition i et input.
- En ledger kan ikke ændre en tidligere accepteret record; split, merge,
  rendition-skift eller forkastelse skal udtrykkes som nye versionsstyrede
  beslutninger og bliver ellers lagt på menneskeark.
- Krydshenvisninger valideres: hver accepteret anchor skal pege på en faktisk
  source record, og source-record-id samt record-key skal være unikke.
- Outputtet er privat. Kun hash, optællinger og opaque IDs må indgå i
  trackede rapporter; aldrig verbatim persontekst.

## Komponenter

1. `source_record_ledger.py` læser review-fil og eksisterende ledger, mint'er
   kun nye accepterede records og bygger et validerbart evidence bundle.
2. `evidence_contract.py` strammes, så bundle-validering kontrollerer
   source-record-form, unikke record keys og anchorens fremmednøgle.
3. En ny testfil dækker mintning, idempotens, drift, editionsadskillelse,
   dubletter og den genererede bundles krydshenvisninger.

Ledger og review-filer ligger i ignoreret `work/`; script og tests er den
trackede, reproducerbare kontrakt. Første brug bliver en tekstfri,
deterministisk acceptliste for 2018-piloten; 1939 får først en tilsvarende
acceptliste, når non-person segmenter er til stede.

## Acceptkriterier

- Samme review-fil og ledger giver byte-identisk bundle og ændrer ingen keys.
- En ny accepteret række får ét opaque key; en ændret eksisterende række
  fejler uden at ændre ledgeren.
- Manglende accepteret beslutning, duplicate IDs eller anchor uden source
  record fejler fail-closed.
- `prepare_batch` kan modtage de genererede records, og en påstået claim kan
  kun bruge den record key, der er accepteret for dens occurrence.
- Koden kører uden database- eller netværksadgang.
