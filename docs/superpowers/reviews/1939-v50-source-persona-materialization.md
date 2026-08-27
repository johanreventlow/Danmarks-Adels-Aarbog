# DAA 1939 v50: source-persona-materialisering og read-only dry-run

Dato: 2026-08-17

## Resultat

- 24 godkendte identitetsbeslutninger er materialiseret som 24 entydige
  source-persona-kandidater.
- 17 genuinely-new source records forbliver eksplicit uafklarede.
- De 24 targets består af 15 `matched`-ankre og 9 `database_only`-ankre.
- Alle 24 source-record-keys, target-record-keys, canonical person-id'er og
  source-persona-id'er er hver især entydige.
- Den levende databasekontrol fandt 543 matchede personankre, 0 manglende og
  0 kollisioner. Ingen af de 24 persona-targets havde mismatch.
- Ingen canonical person-create, update eller delete er autoriseret.

## Artefakter og hashes

- `source-persona-materialization-v1.json`:
  `07756ef4faf17561cf84095c5abe47919064d72ceecd3e1d9f725281ab0b172d`
- `source-persona-materialization-v1-report.md`:
  `2207df1950c6fcfe193b125ad7f44eb7284dd079f0ef20e873f7474017cef9ef`
- `database-preview-v2.json`:
  `17c0e8eea13cd006fa2746466387afab9e41e00e9fbcd78ee9fc854a39e36dab`
- `database-preview-v2-report.md`:
  `ecbc67792bcdf331023eeea2b70c013b4212183bbcbb1f8185c644b64d88f9a9`

Materialiseringen blev genbygget byteidentisk i en separat tempmappe.
Database-previewet blev kørt to gange mod databasen og var semantisk identisk,
når det forventeligt variable `snapshot_at` blev fjernet.

## Databasebevis

Kørslen brugte PostgreSQL 17.6, database `postgres`, source-id 3 / `daa:1939`.
Sessionen rapporterede `transaction_read_only=on`. Scriptet tillader kun den
lukkede read-only SQL-grammatik, afslutter transaktionen før lokale artefakter
skrives og indeholder ingen databasewriter.

Sammenligningen mod v1 ændrede kun identitetsstatussen: pending faldt fra 41 til
17. De øvrige observerede databaseforhold var stabile:

- narrativer: 0 inserts, 478 update-kandidater, 65 uændrede, 0 kollisioner;
- facts: 2175 eksisterende, heraf 2172 source-cited;
- relationer: 803 relationsrækker og 689 family-member-rækker;
- tre legacy-retirements er fortsat til stede.

Alle kandidatlister er ikke-skrivende (`authorized: false`).

## Gates og resterende blockers

- `source_persona_materialization_gate`: `GO`
- `database_write_gate`: `NO-GO`
- `dry_run_gate`: `NO-GO`
- `reimport_gate`: `NO-GO`

Blockers:

- `private.source_record` findes endnu ikke;
- `private.source_persona` / identitylaget findes endnu ikke;
- 23 eksisterende 1939-databaseposter er fortsat uden v50-baseline-mapping;
- 17 genuinely-new identiteter er fortsat uafklarede;
- provenance mangler for 130 facts, 94 ægteskaber og 81 relationer;
- production writer er ikke autoriseret eller implementeret.

## Verifikation

- Python: `1577 passed, 3 skipped`.
- R/testthat: `683 passed, 1 skipped, 0 failed, 0 warnings`.
- Fokuserede Python-tests: `19 passed`.
- Fokuserede R-tests: alle 11 testblokke bestået.
- `git diff --check`: bestået.

Konklusion: De 24 godkendte identiteter er nu sikkert forbundet med
importkonverteringen og kontrolleret mod den levende database. Resultatet er et
stærkere, reproducerbart preview, men ikke tilladelse til en egentlig reimport.
