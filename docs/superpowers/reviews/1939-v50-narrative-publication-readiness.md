# DAA 1939 v50 narrativ-publikation — production readiness

Dato: 2026-08-18. Scope: den snævre pakke, der publicerer de otte allerede
eksisterende `draft`-bindinger i `private.narrative_record_publication`
(person 1846-1853), som cutover-previewet anbefalede før cutover. Ingen
production apply og ingen cutover er udført i dette trin.

## Konklusion

**GO for at forberede én fremtidig, eksplicit autoriseret production-apply af
de otte narrativ-publikationer.** Den endelige real-DBI rehearsal er kørt mod
en frisk kopi af den produktionsækvivalente lokale restore, og 0-persistens er
bevist med byte-identiske før/efter-baselines. Production-status er fortsat
**NO-GO**, indtil brugeren særskilt har godkendt apply med de eksakte hashes
nedenfor. Cutover er uden for denne pakke og forbliver **NO-GO**.

## Hvad pakken gør

Publikationen ændrer udelukkende de otte bindingers `status` fra `draft` til
`published` via `public.red_publicer_narrative_record`; tabellens
valideringstrigger sætter `published_at`. Derefter returnerer den
record-specifikke offentlige bio-RPC provenance for de otte narrativer efter en
senere cutover. Forventet nul-delta: personer, facts, assertions, citations,
conclusions, relationer, familier, medlemskaber, external IDs, batches,
authorizations og write-events.

RPC'en er hærdet til formålet: en eksisterende binding publiceres kun, hvis
alle fire bindingsfelter matcher eksakt (`FOR UPDATE`-låst); enhver drift
fejler med `SOURCE_RECORD_PUBLICATION_BINDING_MISMATCH`, en allerede
publiceret binding med `SOURCE_RECORD_PUBLICATION_ALREADY_BOUND`, og
ny-publiceringsvejen for fremtidige narrativer er bevaret. Kun
`redaktion`-rollen kan kalde den.

## Autoritative artefakter

| Artefakt | SHA-256 |
|---|---|
| `narrative-publication-manifest-v1.json` (byte) | `d71908cf3a998d57602a91d936a2c1b19cf874da938bdef0d691fda9a2ac7654` |
| manifest content (kanonisk) | `36f3a18876ac2b8d8c4b96a63e7e236d0d18a3309d169794445b2ff99c0f1f6a` |
| rehearsal-output `narrative-publication-rehearsal-final.json` | `a7d903cf680dd4a1dae456802161fd069003b0997ae349c05a5ca6125ddbe841` |
| baseline før/efter (byte-identiske) | `14a20bd083bcb48db9fb839a1eb88c4fadd8a5eb227636ddc911d9cd9568c06e` |
| `db-migrations.sql` | `9a6e315a745f2670406d851a73f299592bcdcddb6c12a4691c712116d1434dc0` |
| `db-rls.sql` (uændret) | `356d7990b3db2cbf3b7091287f1fd18b193e99e66244d328bf5052a19444610a` |

Manifestet er låst til databaseidentitet `7642734024280108049`, source-batch
`560c39f8-5c87-4c0d-a768-025d97fa2974`, completion-batch
`0b0055f6-9ad4-4f09-8f23-b8976d8f1996`, de to input-hashes fra
cutover-previewet og name-completion-verifikationen, samt alle otte bindinger
felt for felt. `production_authorized=false`, `cutover_authorized=false`.
Alle work-artefakter ligger under ignoreret `work/`; credentialscan af de nye
scripts og manifestet fandt 0 hits.

## Endelig real-DBI rehearsal (0 persistens)

Kørt i `daa1939_narrative_publish_final1` — en frisk `createdb -T`-kopi af den
produktionsækvivalente restore (1.812 personer, begge batches `finalized`,
321 write-events, 8 `draft`-bindinger), lokal PostgreSQL 17 med cluster-id
`7657242220770903427`, forskelligt fra produktion. Kommandolinje og fuldt
resultat: `work/task25-1939-v50-production-writer/narrative-publication-rehearsal-final-report.md`.

- Resultat: exit 0, `status=dry_run_complete`, `committed=false`,
  `bindings_published=8`, de otte låste binding-ID'er i personorden.
- 0-persistens: samme baseline (fuld bindings-dump, batch-status og 17
  tabeltællinger) før og efter var **byte-identisk** (`cmp` grøn, samme
  SHA-256); alle 8 bindinger fortsat `draft` med `published_at IS NULL`.
- Previewens gateway har ingen commit-operation; succesvejen og alle fejlveje
  slutter i rollback. Dry-run er strukturel, ikke et flag.

Preflighten afviser navnet `postgres` uden prods cluster-id og kræver begge
batches `finalized` plus eksakt 8/8 draft-match, så den samme kommando kan
ikke ramme en forkert database.

## Frisk verifikation

- DB-fri R-kontrakt: `PASS 22 assertions` (manifestvalidering, kanonisk hash,
  gateway-orden, rollback på alle fejlveje, CLI-hash-afvisning).
- Fuld Python-suite: `1710 passed, 3 skipped`.
- Fuld R-suite inkl. ny testthat-wrapper:
  `FAIL 0 | WARN 2 | SKIP 2 | PASS 812`. Den ekstra warning er samme kendte,
  ufarlige `normalizePath("run-tests.R")`-mønster som name-completion-wrapperen.
- Schema/migration-paritet: `red_publicer_narrative_record` har md5(prosrc)
  `6e888307f3fb2465f19213649128df7d` ad alle tre veje — restore +
  migrations-increment (anvendt ×2, idempotent), frisk `schema.sql`-path og
  den eksisterende rehearsal-restore.
- `db-verify.sql`: den opdaterede Task 15-blok er grøn på en frisk
  schema-path-database (drift-afvisning uden mutation, eksakt draft→published,
  bevaret ny-publiceringsvej, rollback af testdata). Den senere, urelaterede
  `regen genskabte ikke visning_navn`-blok fejler identisk med **uændrede**
  HEAD-filer på en frisk database og er dermed præeksisterende; db-verify
  køres fortsat scoped, jf. `docs/database-current-state.md`.
- `git diff --check`: grøn.

## Gates og krævet fremtidig godkendelse

Stoptilstande: forkert database/cluster-id, ikke-finaliserede batches,
manglende eller ikke-draft bindinger, felt-drift i en binding, forkert
manifest-byte-hash eller kanonisk content-hash, manglende
`redaktion`-aktør.

Før en production apply skal en ny, eksplicit brugergodkendelse navngive:

1. produktionsdatabasen `postgres` / system identifier `7642734024280108049`;
2. en **ny umiddelbar backup** med eksakt sti, mode `0600`, bytestørrelse og
   SHA-256;
3. `db-migrations.sql` SHA-256
   `9a6e315a745f2670406d851a73f299592bcdcddb6c12a4691c712116d1434dc0`
   (DDL-increment med den hærdede RPC skal anvendes mod produktion før apply);
4. manifest-byte-SHA-256
   `d71908cf3a998d57602a91d936a2c1b19cf874da938bdef0d691fda9a2ac7654`;
5. præcis én publikations-apply af de otte bindinger, uden retry og uden
   cutover.

Indtil da er production apply **NO-GO**. Cutover kræver derefter sin egen,
separate hard-gate-beslutning og en genkørsel af cutover-previewet.
