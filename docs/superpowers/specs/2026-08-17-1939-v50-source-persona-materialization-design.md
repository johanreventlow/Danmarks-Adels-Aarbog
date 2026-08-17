# DAA 1939 v50 Source-persona Materialization Design

**Dato:** 2026-08-17

**Status:** Godkendt gennem brugerens fortsættelse af den aftalte kritiske vej.

## Formål

De 24 eksplicit godkendte identitetsbeslutninger for ejerløse v50-source-records
skal omsættes til et deterministisk, hashbundet source-persona-preview og indgå
i en ny skrivebeskyttet databasesammenligning. Arbejdet må ikke skrive til
databasen, oprette kanoniske personer eller ændre den gamle `load_daa.R`.

## Append-only arkitektur

Det eksisterende import-preview v1 og database-preview v1 forbliver uændrede.
En ny Python-builder læser import-preview v1, database-preview v1 og alle fire
identitetsbatches. Den materialiserer ét source-persona-objekt pr. godkendt
source record og binder hvert objekt til source span, verbatimtekst,
beslutningshash, target-baseline-record og eksisterende canonical person-id.

En udvidet read-only R-komparator læser dette artefakt som et ekstra,
obligatorisk input til database-preview v2. Den samme direkte PostgreSQL-session
starter fortsat `BEGIN READ ONLY`, og alle domænequeries går gennem den
eksisterende SQL-whitelist. Ingen ny databasewriter implementeres.

## Materialiseringskontrakt

Builderen accepterer kun identitetsbatches med schema
`1939-v50-identity-decisions-v1`, `decision_gate: GO` og alle skrive-/reimport-
gates på `NO-GO`. Hver beslutning skal være `same`, være entydig globalt og
pege på præcis én post i import-previewets `genuinely_new_pending`.

Targetens baseline-record-key og canonical person-id skal stemme med et
entydigt `person_anchors.matched`-par i database-preview v1. Source span og
verbatimtekst kopieres fra import-previewet; de må ikke rekonstrueres fra navn
eller OCR-lighed.

`source_persona_id` og `persona_key` afledes deterministisk af source-id og
source-record-key. ID'et er previewidentitet, ikke tilladelse til at indsætte en
databasepost. Hver materialisering bærer inputhashes, beslutningsbatch,
candidate-evidence-hash og den oprindelige brugerbekræftelse.

Med de låste input forventes:

- 24 materialiserede source-personaer;
- 24 accepterede identitetslinks til 24 eksisterende canonical personer;
- 17 resterende `genuinely_new_pending`;
- 0 canonical person creates, updates eller deletes;
- `database_write_gate: NO-GO` og `reimport_gate: NO-GO`.

## Database-preview v2

Database-preview v2 genbruger alle eksisterende person-, narrativ-, fakta- og
relationsqueries. Før sammenligningen valideres source-persona-artefaktets hash,
source-id, import-preview-hash og lukkede schema.

Previewet tilføjer en `source_personas`-sektion med planlagt antal, resterende
uafklarede source records, canonical target-kontrol samt – når private tabeller
findes – existing/insert/collision counts. Manglende private evidenstabeller
forbliver synlige capability-blockers; de fortolkes aldrig som tomme tabeller.

Blokeringen `genuinely_new_identity_pending:41` erstattes af
`genuinely_new_identity_pending:17`. Alle øvrige provenance- og writerblockers
bevares. `dry_run_gate` kan kun være `GO`, hvis de krævede private tabeller kan
sammenlignes; `reimport_gate` forbliver altid `NO-GO` i denne fase.

## Test og verifikation

Implementeringen følger RED → GREEN. Python-tests skal bevise exact coverage,
hashbinding, deterministiske persona-ID'er, global injectivity og afvisning af
source-/target-/gate-drift. R-tests skal bevise, at materialiseringen valideres,
at 24/17-tallene rapporteres, at canonical mutations er nul, og at database-
sessionen fortsat er read-only før første domænequery.

Realdataartefakter skrives eksklusivt under `work/`, genbygges byteidentisk til
temp og sammenlignes mod en frisk, ikke-skrivende databasekørsel. Credentials
eller connection strings må ikke serialiseres.

## Afgrænsning

Dette er source-persona- og database-preview, ikke en writer. Der oprettes
ingen `source_record`, observation, mention, persona, identity event,
interpretation eller canonical række i databasen. En senere writer kræver
separat design, migrationskontrol, replay og udtrykkelig autorisation.
