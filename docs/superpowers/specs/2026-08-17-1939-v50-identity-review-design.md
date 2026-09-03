# DAA 1939 v50 Identity Review Design

**Dato:** 2026-08-17

**Status:** Godkendt retning. Review-only; ingen databaseændringer.

## Formål

Den lokale v50-importpreview indeholder 41 source records, som er accepteret
som ægte nye i source-record-laget, men som endnu ikke må oprette kanoniske
personer. Den skrivebeskyttede databasesammenligning fandt samtidig 23
eksisterende 1939-personer, hvis historiske record keys ikke er forbundet med
v50-baselinen.

Næste trin skal afgøre, om nogle af de 41 records beskriver nogle af de 23
eksisterende personer. Resultatet er en menneskelig reviewpakke, ikke en
identitetsafgørelse, mergeordre eller importplan.

## Beslutning

Arbejdet opdeles i to deterministiske, read-only trin:

1. Et R-script profilerer præcis de 23 databasepersoner fra det hashbundne
   databasepreview. Det læser kun eksisterende 1939-provenance, narrativer,
   facts og relationer i en eksplicit read-only transaktion.
2. En Python-builder sammenholder de 41 source records med profiludtrækket og
   fremstiller et lukket review-manifest med positive, kildebundne signaler.

Ingen kandidat får status `same`, `different` eller `accepted`. Alle subjects
forbliver `pending`, også når ét match ser stærkt ud.

## Autoritative input

Reviewet hashbinder:

- `import-preview-v1.json` med de 41 genuinely-new source records;
- `database-preview-v1.json` med de præcise 23 database-only record keys og
  person-ID'er;
- det nye read-only databaseprofiludtræk;
- `linked_clean_1939_v2.json`, alene som historisk source-record-payload for
  de 23 deklarerede record keys.

Builderen afviser drift i schema, SHA, record-key/person-ID-par, coverage,
duplikerede keys og uventede kandidater uden for de deklarerede 41/23-sæt.

## Databaseprofil

Profiludtrækket må kun indeholde data, som allerede er knyttet til en af de 23
personer eller deres deklarerede 1939-record key:

- person-ID, record key og databasevisningsnavn;
- eksisterende 1939 source-narrativ med stabil rækkeidentitet;
- source-citerede facts med felt, rå værdi og kildehenvisning;
- eksisterende relationer/family membership med rolle og modpartsvisning;
- eksplicitte counts for editorial/source ownership.

Data fra andre udgaver må ikke blive identitetsbevis uden tydelig provenance.
Scriptet genbruger den eksisterende SQL-whitelist og read-only bootstrap. Det
må ikke oprette temp-tabeller eller kalde mutationer.

## Positive signaler

Et kandidatlink må kun oprettes, hvis mindst ét reproducerbart signal findes:

- et diskriminerende navn eller navnefølge findes ordret i v50-verbatimteksten;
- en source-citeret dato eller anden rå source-værdi findes ordret i samme
  tekst og er knyttet til kandidatpersonen;
- en navngiven ægtefælle/forælder/barn fra eksisterende source-provenance
  findes ordret i samme tekst;
- den historiske 1939 source-recordtekst overlapper v50-recorden med et
  dokumenteret, tilstrækkeligt langt ordret tekststykke.

Hvert literal-signal gemmer nøjagtige tegn-offsets i v50-recorden og den
konkrete profil-/legacy-kilde, som signalet kommer fra.

Normalisering må bruges til at finde forslag til efterfølgende literal
verifikation, men må aldrig stå alene som evidens. OCR-tolerante eller fuzzy
signaler kan vises som `presentation_only` og må ikke oprette et kandidatlink.

## Ambiguitet og negative regler

- Et kort eller hyppigt fornavn alene er ikke diskriminerende og giver intet
  kandidatlink.
- En dato alene giver ikke et identitetslink, medmindre den er usædvanlig og
  ledsages af et andet uafhængigt, source-bundet signal; i v1 parkeres
  dato-alene derfor uden link.
- Hvis samme signal peger på flere databasepersoner, listes alle konkurrerende
  kandidater symmetrisk og subject forbliver pending.
- Fravær af et signal er ikke evidens for `different` eller `new person`.
- Et match mod en af de 23 udelukker ikke en ukendt bedre kanonisk kandidat;
  manifestet siger derfor kun `review_candidate`.

## Output

Det ignorerede bundle under `work/task22-1939-v50-identity-review/` indeholder:

- inputhashes, schema- og generatorversion;
- præcis 41 subjects i source order;
- præcis 23 candidate profiles;
- nul eller flere review-only links med source-bound evidence;
- konkurrerende kandidater og signalernes eksakte offsets;
- subjects uden kandidat, stadig eksplicit listet;
- `review_state: pending`, `review_only: true` og
  `canonical_mutations_authorized: false` på topniveau;
- counts for coverage, links, signaltyper, ambiguity og unlinked subjects.

En Markdown-rapport gengiver samme information uden at ændre manifestet.

## Gates

Manifest-build er `GO`, når alle 41 og 23 er dækket præcis én gang, alle links
har reproducerbar positiv evidens, og alle inputs er hashbundet.

Reimport er fortsat `NO-GO`. En senere identitetsafgørelse kræver separat,
versionsstyret human beslutning med `record_key`-provenance. Først derefter kan
en writer-plan afgøre, hvilke source personas der genbruger eksisterende
personer, og hvilke der eventuelt må oprette nye staged personer.

## Test

Testene skal mindst bevise:

- eksakt 41/23-coverage og deterministisk byteidentisk rebuild;
- fail-closed SHA-, schema-, coverage- og key/person-drift;
- ingen link fra kort fællesnavn, dato alene eller fuzzy-only signal;
- eksakte literal offsets og kildehenvisninger;
- symmetriske competitor-lister ved tvetydighed;
- alle review states er pending og nul canonical mutationer er autoriseret;
- databaseprofilering starter read-only før første domænequery og afslutter
  med rollback/disconnect på både succes og fejl.

