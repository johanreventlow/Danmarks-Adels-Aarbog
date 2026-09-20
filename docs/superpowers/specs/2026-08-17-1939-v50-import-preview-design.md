# DAA 1939 v50 Import Preview Design

**Dato:** 2026-08-17

**Status:** Godkendt design. Implementering følger den separate plan.

## Formål

v50 afslutter reconciliation af de 546 historiske 1939-poster mod 592
materialiserede source records. Næste skridt er at forbinde dette resultat med
importkonverteringen og vise den forventede databasevirkning, før en egentlig
reimport kan godkendes.

Previewet skal kontrollere personer, relationer, narrativer og provenance uden
at skrive til databasen. Det er ikke en produktionsloader og giver ikke i sig
selv reimport- eller cutover-GO.

## Beslutning

Der bygges en ny, fail-closed previewvej ved siden af den gamle `load_daa.R`.
Den gamle loader ændres eller kaldes ikke, fordi dens dry-run udfører
midlertidige writes i en rollback-transaktion og tager loader-låse.

Previewet består af to deterministiske trin:

1. En DB-fri Python-konvertering fremstiller en hashbundet import-preview fra
   v50 og de eksakte forgængerartefakter.
2. Et R-script åbner en Supabase/PostgreSQL-session, sætter read-only før
   kontrolforespørgsler og sammenligner previewet med den aktuelle database.

Begge trin er rapporterende. De må ikke oprette person-ID'er, indsætte,
opdatere, slette, kalde mutations-RPC'er eller oprette temp-tabeller.

## Autoritative input

Den lokale konvertering modtager alle stier eksplicit og hashbinder mindst:

- `source-record-reconciliation-v50.json`;
- v50 reconciliation-rapporten;
- `source-record-ledger-v3-ditlev.json`;
- `boundary-materialization-v3-ditlev.json`;
- `clean_1939_v3.json`;
- den Calamari-rendition, som ledger/materialisering henviser til.

Konverteringen afviser ukendte schema-versioner, forkerte SHA-256-værdier,
duplikerede keys, stale forgængere, span-/verbatim-drift og mismatch mellem
v50, ledger og materialisering. Output oprettes eksklusivt og må ikke
overskrive en eksisterende fil.

## Lokal klassifikation

v50's new-record-side er det autoritative kilderecordlag. Den lokale preview
skal føre hver record præcis én gang til en af disse klasser:

- **mapped_existing:** accepteret 1:1-forbindelse fra en aktiv historisk
  `record_key` til en v50 source record;
- **retired_legacy:** historisk post, som v50 eksplicit har pensioneret som
  duplicate eller fragment;
- **genuinely_new_pending:** accepteret ny source record uden historisk ejer;
- **source_only_structural:** accepteret strukturel kontekst uden person;
- **source_only_cross_reference:** accepteret krydshenvisning uden person.

Med de aktuelt godkendte v50-bytes forventes 543 `mapped_existing`, 3
`retired_legacy`, 41 `genuinely_new_pending`, 6 strukturelle og 2
krydshenvisninger. Tallene er assertions, ikke løse forventninger: ændrede tal
uden en ny understøttet version får konverteringen til at stoppe.

De 41 genuinely-new records bliver source-record-kandidater. De må ikke blive
kanoniske personer, før separat kildepersona-, identitets- og
fortolkningsprovenance findes. De otte ikke-personposter må aldrig foreslå
personoprettelse.

## Person- og indholdspreview

For hver `mapped_existing` record må det historiske `clean_1939_v3`-payload
bruges som kandidatmateriale, men ikke som ny sandhed. Hvert narrativ, faktum,
ægteskab og strukturel relation klassificeres mod den nye source record:

- `source_bound_literal`: det deklarerede kildeudsnit kan genfindes ordret i
  den hashbundne v50-verbatimtekst;
- `missing_provenance`: intet ikke-tomt kildeudsnit er deklareret;
- `nonliteral_provenance`: et deklareret udsnit findes ikke ordret i den nye
  verbatimtekst;
- `legacy_structure_pending_revalidation`: relationen kommer fra historisk
  parserstruktur uden tilstrækkeligt, præcist positivt source-anker;
- `retired_source_record`: payload tilhører en v50-pensioneret post.

Kun `source_bound_literal` er automatisk kvalificeret til en senere
importplan. De øvrige klasser parkeres synligt. Klassifikationen må ikke gætte
et alternativt span, normalisere OCR-tekst for at skabe et match eller bruge
navnelighed som identitetsbevis.

Narrativet rapporteres som en source-record-tekstændring med gamle og nye
hashes. Det erstatter ikke automatisk et redaktionelt narrativ i databasen.

## Preview-bundle

Den DB-frie konvertering skriver et lukket JSON-bundle med:

- schema- og generatorversion;
- SHA-256 for alle input;
- deterministiske optællinger og sortering;
- alle 592 source records med record kind, source span, verbatimtekst og
  disposition;
- de 543 aktive baseline-to-target-forbindelser;
- de tre pensioneringer;
- de 41 pending nye source records;
- de otte source-only records;
- kandidatpayload med provenanceklassifikation pr. fakta-/relationsobjekt;
- en eksplicit `canonical_mutations_authorized: false`.

En ledsagende Markdown-rapport giver menneskeligt overblik. Bundle og rapport
ligger under det ignorerede `work/`-område og er ikke produktionsinput.

## Skrivebeskyttet databasesammenligning

Databasepreviewet bruger en direkte forbindelse eller Supavisor session mode,
ikke transaction-poolerens port 6543. Efter forbindelse startes en eksplicit
read-only transaktion, og scriptet verificerer både
`transaction_read_only = on` og den forventede databaseidentitet, før andre
forespørgsler køres. Der sættes korte statement- og lock-timeouts.

Kun `SELECT`, `SHOW` og read-only metadataforespørgsler er tilladt. Scriptet
må ikke bruge DDL, DML, `COPY FROM`, temp-tabeller, advisory locks,
mutationsfunktioner eller den gamle loader. Transaktionen afsluttes med
rollback også ved succes, og forbindelsen lukkes i alle fejlveje.

Databasepreviewet læser de aktuelle rækker, som senere import ville berøre,
herunder:

- source/edition og `person_external_id` for 1939;
- de matchende kanoniske personer;
- narrativer, facts, familier, family members og øvrige relevante relationer;
- private source-record-/provenancetabeller, hvis de er installeret;
- redaktionel ændringshistorik, hvor den findes og er nødvendig for at undgå
  overskrivning af beskyttet arbejde.

Schema- eller kolonnedrift afvises synligt. Manglende private tabeller bliver
ikke fortolket som tomme tabeller, men som en særskilt
`database_capability_blocker`.

## Forventet databasevirkning

Dry-run-rapporten opdeler resultatet i:

- entydigt eksisterende, manglende og kolliderende personankre;
- source-record inserts/updates/retirements, som en fremtidig writer ville
  skulle udføre;
- narrativforskelle uden automatisk mutationsret;
- sikre kontra parkerede fact-kandidater;
- sikre kontra parkerede relationskandidater;
- eksisterende databasefakta/relationer, som ikke er dækket af previewet og
  derfor ikke må slettes stiltiende;
- redaktionelt beskyttede eller identitetsmæssigt tvetydige rækker;
- canonical person creates/updates/deletes, som i denne fase skal være `0`
  autoriserede.

Rapporten viser både rå counts og stabile nøgler for alle blokeringer. Den må
gerne beregne et hypotetisk ændringssæt, men hvert element bærer
`authorized: false` eller en eksplicit senere gate; rapporten er aldrig selv en
skriveordre.

## GO/NO-GO

Previewet er `GO` som kontrolkørsel, når input er eksakte, alle records er
bogført, read-only-kontrakten er bevist, og databaseaflæsningen er komplet.

Det er fortsat `NO-GO` for egentlig reimport, hvis blot én af følgende findes:

- tvetydigt eller manglende personanker;
- uafklaret genuinely-new identitet;
- provenanceklassificeret som missing/nonliteral/pending;
- databasecapability- eller schemadrift;
- uforklaret eksisterende canonical række, der ville blive overskrevet eller
  forældreløs;
- et ikke-tomt forventet canonical mutationssæt uden særskilt godkendt writer,
  replay og rollback-plan.

## Test og verifikation

Implementeringen udvikles test-first. Testene skal mindst bevise:

- eksakt realdata-klassifikation og deterministisk byteidentisk rebuild;
- afvisning af hver inputhash-, key-, span-, owner- og schema-mutation;
- ingen personoprettelse fra genuinely-new, structural eller cross-reference;
- literal/missing/nonliteral provenanceklassifikation;
- parkering af legacy relationer uden positivt anker;
- eksklusiv outputoprettelse og oprydning ved delvis fejl;
- databaseforbindelse sættes read-only før første domænequery;
- skriverettede SQL-kald kan ikke passere query-adapteren;
- read-only-status, databaseidentitet, schema og capabilities verificeres;
- databasefejl producerer en ufuldstændig/NO-GO rapport, aldrig et grønt
  stiltiende fravalg.

Den virkelige kørsel skal bevare preview-bundle og rapport under `work/` med
inputhashes, database-serverversion, kilde-id, snapshot-tid og alle
optællinger. Ingen credentials må skrives til artefakter eller testoutput.

## Afgrænsning

Dette arbejde implementerer preview og kontrol, ikke databasewriter,
promotion, canonical materialisering, cutover, deploy eller sletning. En senere
skriveplan kræver særskilt designgodkendelse baseret på previewets konkrete
blokeringer og ændringssæt.
