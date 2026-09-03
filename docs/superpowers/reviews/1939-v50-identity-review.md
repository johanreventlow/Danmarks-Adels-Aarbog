# DAA 1939 v50 identity review — resultat

**Dato:** 2026-08-17

**Udfald:** Den read-only databaseprofil og den lokale kandidatpakke er
komplette og reproducerbare. Reviewpakken har `GO`; identitetsafgørelse og
reimport er fortsat `NO-GO`.

## Sikkerhedsgrænse

- Supabase-profileringen kørte mod PostgreSQL 17.6 med
  `transaction_read_only=on`.
- De 23 deklarerede record-key/person-ID-par blev genvalideret mod databasen.
- Transaktionen blev rullet tilbage, og forbindelsen blev lukket før den lokale
  profilfil blev skrevet.
- Ingen identitetsbeslutning, personoprettelse, merge, migration eller anden
  databaseændring blev udført.
- `canonical_mutations_authorized` er `false` i både profil og manifest.

## Databaseprofiler

Det private profiludtræk dækker præcis de 23 eksisterende 1939-personposter
uden v50-baseline-mapping:

- 23 source-narrativer;
- 60 facts med assertion-/citationprovenance;
- 43 relationer;
- 7 familier med medlemmer.

Profileringen viste, at enkelte historiske stubposter deler narrativfragmenter,
som ikke svarer til stubpersonens navn. Narrativoverlap alene er derfor ikke
identitetsbevis.

## Kandidatmanifest

Manifestet dækker præcis:

- 41 genuinely-new v50 source records;
- 23 eksisterende kandidatprofiler;
- 9 konservative review-kandidatlinks;
- 32 source records uden kvalificeret kandidat;
- 0 subjects med flere kandidater;
- 0 kandidatprofiler foreslået til flere source records.

Alle ni links er `unresolved`. Evidensen består af exact-offset literal name,
vital fact, narrativ og i nogle tilfælde familie-/relationsnavn. Signalcounts i
den endelige pakke er 34 literal fact-values, 16 literal name-signaler, 8
narrativoverlap, 4 familienavne og 1 relationsnavn.

Under audit blev to generelle fejlklasser fundet og lukket:

1. Et navn kunne først matches på en titel-/gods-hale, og en generisk titel
   kunne tælle som corroboration. Navnematch kræver nu præfiks fra personnavnets
   første token, og kun vitale facts tæller i den gate.
2. Personer nævnt som søn/efterkommer inde i en anden persons record kunne
   først blive kandidat. En principal-placement-gate kræver nu navn før første
   slægtskabs-overgang eller et narrativ, der begynder ved recordets start med
   stærk vital evidens.

## Reproducerbarhed

Ignorerede private artefakter:

- `work/task22-1939-v50-identity-review/database-profiles-v1.json`
  (`67398a6f7faadb42e284ac77769c3261f69eacf37ac1c1ebc2ef5da1a76df9f1`);
- `work/task22-1939-v50-identity-review/identity-review-v1.json`
  (`4c0ce614293c375c9dd0015b70f749e40284cfcbb9ca3537a60f3bb2f109baa6`);
- `work/task22-1939-v50-identity-review/identity-review-v1-report.md`
  (`889c49cd42daf8cbe67c92c687d1cac2c2f65b65ef742b878c3897450d6b04ad`).

En ren genbygning til tempstier var byteidentisk for både JSON og Markdown.
Realdata-testen låser den eksakte 41/23-dækning og de ni nuværende par, mens
unit tests afviser SHA-, schema-, coverage-, pair- og linked-payload-drift.

## Næste trin

De ni links kan nu gennemgås menneskeligt i én lille batch. En godkendelse skal
materialiseres som separat, versionsstyret source-persona identity decision med
record-key-provenance; reviewmanifestet må ikke selv ændres til `accepted`.

De øvrige 32 records er ikke dermed bevist nye personer. Nogle er oversigter,
embedded mentions eller kan have kandidater uden for de 23 profiler. Før
personoprettelse kræves en bredere kanonisk søgning eller en eksplicit
human-afgørelse. Først efter identitetslaget kan en writer-/migrationsplan
fastlægge staged person-create, source-record-indsættelser og replay/rollback.
