# DAA 1939 v50 production-writer readiness

Dato: 2026-08-18. Scope: Tasks 1-8 og forberedelsen af Task 9 i
production-writer-planen. Ingen production apply, reversal eller cutover er
udført.

## Konklusion

Writerens to uafhængige Task 8-rehearsals er grønne. En fuld lokal
produktionsbackup er desuden oprettet, katalogkontrolleret og prøverestaureret;
writerens rollback-dry-run er efterfølgende kørt mod en helt frisk restore af
netop denne backup. Det er ikke production authorization. Task 9-10 forbliver
hårdt gatede, og production-status er fortsat **NO-GO**, indtil brugeren har
set den eksakte reviewpakke og særskilt godkendt production apply.

Restore-testen fandt, at Supabase har `pgcrypto` i schemaet `extensions`.
Writer- og promotionfunktionernes faste `search_path` er derfor gjort
kompatibel med dette faktiske layout. Regressionen var rød med
`function digest(text, unknown) does not exist` før rettelsen og grøn efter.

## Autoritative artefakter

| Artefakt | SHA-256 | Indhold |
|---|---|---|
| `provenance-review-v1.json` | `b984c5f8fedd2d2d47f8b854929419cad88e7ec80bccb4ae41dc451c1b5e124a` | 130 facts, 94 marriages, 81 relationships |
| `provenance-proposals-v1.json` | `69990415adf331c1f8fd91ad6ac3b373025ace6a723cf24666bae63f11a2e7d0` | konservativt forslag |
| `provenance-decisions-v1.json` | `d45f34829d9c350446d59a4671e7688a6c62ec8c1ae7cd9b9598f1473c4f6c68` | 305 `retain_source_only`, 0 unresolved |
| `production-write-manifest-v1.json` | `8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f` | 543 ankre, 8 creates, 305 evidence, 0 canonical delta |
| manifest content | `8c6a9f56af7f1e75e1b961f561cc2118478ac4d9e08f838c9e5279938c545f03` | canonical manifestindhold |
| database preview fix3 A | `279fcb9969f9a4371d995e97c4fffa55589289bcc34a000c03e2bdca29714e6c` | låst database-preview |
| Calamari rendition | `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37` | rå tekstbinding |

Alle Task 25-artefakter ligger under ignoreret `work/`. Credentialscan fandt
0 hits. `load_daa.R` er ikke ændret og har SHA-256
`ee2db8f899dda34ab0b6f121c8a66f8f67acd655d1f0337104c9a1ce23984867`.

## Semantik og forventet delta

- De otte nye personer får databasegenererede IDs, er `staged=true` og er ikke
  offentligt synlige før særskilt cutover.
- Hver person får source record, occurrence, observation, mention,
  source-persona, persona-mention, accepteret identity og draft-narrativ.
- De 305 parkerede objekter bevares som privat source-only evidens. Der
  promoveres ingen canonical facts, marriages eller relations i denne batch.
- Authorization binder database, source, principal, manifest, preview,
  expected counts, nonce, expiry og alle 313 eksakte JSON-payloads.
- Identisk replay returnerer `already_applied`; ændret payload, forkert
  database eller cross-batch reversal afvises.
- Reversal er logisk: external IDs og narrativer fjernes, identities
  supersedes, evidens/journal bevares append-only, og personerne bliver staged
  tombstones med status `reimport_1939_reversed`.

## Reproducerbar dry-run

Den faktiske rollback-dry-run blev kørt i den isolerede lokale PostgreSQL
17-database `daa1939_real_dryrun1`:

```bash
DAA_REIMPORT_ACTOR_ID=11111111-1111-4111-8111-111111111111 \
PGDATABASE=daa1939_real_dryrun1 PGHOST=/tmp PGPORT=5432 \
PGUSER=johanreventlow PGPASSWORD='' \
Rscript .claude/skills/daa-extract/scripts/apply_reimport_1939_v50.R \
  --manifest work/task25-1939-v50-production-writer/production-write-manifest-v1.json \
  --manifest-sha256 8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f \
  --preview-sha256 279fcb9969f9a4371d995e97c4fffa55589289bcc34a000c03e2bdca29714e6c \
  --dry-run
```

Resultat: `status=finalized`, otte DB-returnerede fixture-ID'er, `committed=false`.
Efter rollback var authorization, batches, events, source records,
observations, personas og external IDs alle 0. Dry-run er en virkelig
SQL-write-transaktion med rollback, ikke en read-only query.

## Frisk verifikation

- Fokuseret Task 1-3 Python: `33 passed in 0.12s`.
- Fokuseret Task 5 R: `PASS 20 assertions`.
- Fuld Python-suite: `1679 passed, 3 skipped in 7.76s`.
- Fuld R-suite: `810 passed, 2 skipped, 0 failed, 0 warnings in 6.1s`.
- PostgreSQL 17 migration fra planbase `4a02174`, RLS, SQL-contract og virkelig
  R-integration: exit 0; `PASS DAA 1939 v50 PostgreSQL integration`.
- Den fokuserede promotionkontrakt gennemførte både et gyldigt preview og en
  gyldig batch med `pgcrypto` i `extensions`, mod både en frisk database og
  produktionsrestoren; fixturens rækker var 0 efter rollback.
- Determinisme: decisions og manifest blev genbygget med
  `PYTHONHASHSEED=17` og `991`; begge var byteidentiske med de autoritative
  filer.
- `git diff --check`: grøn.

Integrationstesten dækker nul-delta efter rollback, 313 konkrete
provenancerækker, otte staged personer, append-only identity, identisk replay,
ændret-byte-afvisning, advisory-lock-race, staged visibility, sequence og
reversal. DB-fri failpointtests injicerer fejl ved begin-batch,
source-evidence, person-create og finalize og kræver præcis én rollback.

Den brede, historiske `db-verify.sql` er eksplicit **ikke** rapporteret som
grøn mod produktionsrestoren og er ikke Task 9-writer-gaten. Dens ældre
fixtures forudsætter en tom eller minimal database og kolliderer med den
restaurerede databases eksisterende `daa:1939`-nøgle, faste auth-UUID'er,
lineage-fixtures, storage-forudsætninger og sekvenstilstand. Task 9 bruger i
stedet de afgrænsede writer- og promotion-SQL-kontrakter, de fulde Python- og
R-suiter, Task 8's dobbelte rehearsal samt den virkelige rollback-dry-run mod
en frisk restore. Det er en bevidst disposition af legacy-verifierens kendte
begrænsning, ikke en påstand om at den er repareret eller passerer globalt.

## Lokal backup og realistisk restore-kontrol

Før enhver produktionsskrivning blev der oprettet en fuld lokal custom-format
PostgreSQL-backup:

- fil: `~/Backups/danmarksadelsaarbog/daa-production-before-1939-v50-2026-08-18.dump`
- størrelse: `3656690` bytes
- SHA-256: `634eef826b22b3443ac265b4bbbded31d3917be4fcbf7193e7172e7643b66032`
- filtilstand: `0600`; backupmappen er `0700`
- `pg_restore --list`: 867 katalogposter

Den permanente fil er komplet, inklusive Supabase Vault. Den lokale Homebrew
PostgreSQL mangler platformextensionen `supabase_vault`, så prøverestoren
udelod præcis de fire lokale platformposter for Vault (schema, extension,
extension-comment og Vault table data). De øvrige 863 katalogposter blev
restaureret. Dette ændrer ikke backupfilen.

Kontroltællingerne i restore matchede den read-only produktionssnapshot, bl.a.
1.804 personer, 1.160 external IDs, 7.191 facts, 2.031 relationer, 682 familier,
9.296 assertions og 8.574 citations. Projektets aktuelle migrationer og RLS
kunne anvendes på restoren. En efterfølgende rigtig writer-dry-run gav otte
lokale person-ID'er 1846-1853, `status=finalized` og `committed=false`.
Efter rollback var der fortsat 1.804 personer og præcis nul authorizations,
batches, write-events, nye source records, source personas og nye external
record keys.

Task 8 A/B havde desuden identisk normaliseret semantik, 543 eksisterende
ankre, 8 staged creates, 305 source-only operationer, 0 canonical mutationer
og en grøn reversal. Databasegenererede ID'er i en production apply afgøres af
den live sekvens ved apply-tidspunktet; de lokale restore-ID'er er derfor
kontrolevidens, ikke en forhåndsreservation.

## Gates og fejltilstande

Følgende er eksplicitte stoptilstande: forkert database/preview/manifest,
ukendt eller ændret elementpayload, forkert principal, udløbet eller genbrugt
authorization, counts/coverage mismatch, eksisterende external record-key,
duplicate persona, ikke-staged create, cross-batch reversal, concurrent writer
og enhver canonical delta (denne manifestversion har nul og RPC'en afviser
canonical writes).

Næste tilladte trin er at forelægge Task 9-reviewpakken med den eksakte live
databaseidentitet, recovery point, hashes og forventet delta. Først efter en ny
eksplicit brugerautorisation må migration/RLS, one-use apply-authorization og
én staged production apply køres. Task 10 cutover kræver en senere, separat
hard-gate-beslutning.
