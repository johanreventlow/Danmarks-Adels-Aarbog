# Problem 2 — Fase 4 prod-cutover runbook

**Status:** Forberedt, IKKE udført. Prod-anvendelse kræver eksplicit bruger-godkendelse der navngiver
prod-målet. **Prod har INGEN backup** — Trin 0 (dump) er den eneste rollback.

**Formål:** Anvend Problem 2 DB-laget (forældrefamilie-slot + konkurrerende påstande) på prod, så det
evidensbaserede slægtskabs-lag er live. Låser op for senere load af den divergerende 1939-stamtavle.

## Forudsætninger (verificér på prod FØR noget anvendes)

Kør read-only mod prod (kræver bruger-godkendelse der navngiver prod):

```sql
-- (a) SINGLE-EDITION: kun DAA 2018-20 har data. KRITISK — backfillen aborter ellers, men bekræft manuelt.
SELECT id, udgave, aar, slags FROM source ORDER BY id;
-- Forvent: én reel udgave-source (DAA 2018-20). Ekstra tomme/hjælpe-sources OK hvis de ikke har barn-rækker.

-- (b) INGEN dublet-fødselsfamilier (EXCLUDE-prætjek fejler ellers)
SELECT count(*) FROM (SELECT person_id FROM family_member WHERE rolle='barn' GROUP BY person_id HAVING count(*)>1) t;
-- Forvent: 0

-- (c) Umigreret baseline (objekt-kolonner findes ikke endnu)
SELECT exists(select 1 from information_schema.columns where table_name='assertion' and column_name='objekt_type');
-- Forvent: false

-- (d) Barn-rækker med kilde <> DAA 2018-20 (multi-edition-lækage — backfillen ville aborte)
SELECT count(*) FROM family_member fm JOIN person_external_id pe ON pe.person_id=fm.person_id
  JOIN source s ON s.id=pe.source_id WHERE fm.rolle='barn' AND s.udgave IS DISTINCT FROM 'DAA 2018-20';
-- Forvent: 0
```

## Trin 0 — BACKUP (obligatorisk, ingen anden rollback)

```bash
# Fuld dump af public-skema (INDEHOLDER LEVENDE-PII → gem sikkert, IKKE i git)
pg_dump "<prod-conn> sslmode=require" --schema=public -Fc \
  -f ~/daa-prod-backup-$(date +%Y%m%d-%H%M).dump
# Verificér dumpet er ikke-tomt + gendannbart (test-restore til en engangs-lokal DB anbefales).
```

## Trin 1 — Anvend skema-migration (DDL + funktioner, INGEN backfill)

```bash
psql "<prod-conn> sslmode=require" -v ON_ERROR_STOP=1 -f db-migrations.sql
```
- Idempotent (CREATE OR REPLACE / IF NOT EXISTS / ON CONFLICT). Tilføjer: assertion.objekt-kolonner+indeks,
  vocab 'forældrefamilie', EXCLUDE family_member barn-slot (fail-closed prætjek), alle red_*-RPC'er +
  helper + konflikt-view. **Indeholder IKKE backfillen** (flyttet til Trin 2).
- EXCLUDE-prætjekket aborter hvis forudsætning (b) fejler → afklar dubletter først.

## Trin 2 — Backfill (DELIBERAT, kun efter single-edition er bekræftet)

```bash
psql "<prod-conn> sslmode=require" -v ON_ERROR_STOP=1 -f db-backfill-foraeldrefamilie.sql
```
- Har egen **multi-edition-abort** (external_id-baseret) ud over STRICT-kildeopslag — men forudsætning (a)+(d)
  SKAL alligevel være bekræftet manuelt. Idempotent (NOT EXISTS). Forventet output: "Backfill færdig …".

## Trin 3 — Verificér (db-verify)

```bash
psql "<prod-conn> sslmode=require" -f db-verify.sql 2>&1 | grep -iE "OK:|SPRINGER|ERROR"
```
- Forventede grønne Problem 2-linjer: forældre-konflikt, forældre-undo, mutator-slot-vedligehold,
  **forældre-backfill-komplethed + P1-drift** (nu IKKE skippet, da slots findes). Ingen ERROR.
- NB: db-verify seeder/rydder negativ-id-fixtures — sikkert, men kør bevidst mod prod.

## Trin 4 — Sikkerheds-advisors (efter DDL)

Kør Supabase `get_advisors(security)` (el. tjek manuelt): alle nye funktioner er
`SECURITY DEFINER SET search_path=public`; `red_foraeldre_konflikt`-view er `security_invoker=true`;
slot arver person-gatede fact/assertion/conclusion-RLS (ingen ny tabel). Verificér ingen nye
security-fund (search_path, RLS-huller) — jf. [[koer-get-advisors-efter-ddl]].

## Trin 5 — Loadere fremadrettet

Efter migrationen kræver load_daa.R/load_presens.R den migrerede base (member_evidence skriver
objekt-kolonner). Fremtidige udgave-loads lander born-evidens-komplette.

## Rollback

Ingen anden vej end Trin 0-dumpet:
```bash
# gendan public-skema fra backup (DESTRUKTIV — kun ved fejlet cutover)
pg_restore "<prod-conn> sslmode=require" --clean --if-exists --schema=public ~/daa-prod-backup-*.dump
```
Bemærk: migrationen er additiv (nye kolonner/funktioner/constraint) + backfillen additiv (nye evidens-rækker);
en fejlet cutover efterlader ikke ødelagt eksisterende data, men EXCLUDE-constrainten kan blokere efterfølgende
skrivninger hvis dubletter opstod — dumpet er den sikre nulstilling.

## Efter cutover (SEPARAT, senere gate)

Load af den divergerende **1939-stamtavle** til prod (Problem 2's egentlige mål) er en selvstændig
bruger-godkendt handling: udtrukket korpus indeholder levende-PII (gitignoreret); load som ny source →
samme_som-collapse i UI → importér rival-forældre-påstande → adjudicér. IKKE del af denne cutover.

## Lokal rehearsal (udført 2026-07-16)

- Migration + backfill på ren single-edition-bed m. edge-cases: 3 barn→3 slots; subtyper (adopteret/pleje)
  backfyldes IKKE; partnerløs-familie-barn får slot (backfill kræver ikke partner); 0 P1-brud.
- Backfill single-edition→succes; **multi-edition→ABORT** (0 slots) — DB-L3 fail-open lukket.
- Alle Problem 2 db-verify-blokke grønne mod daa_test2.
- **Ægte real-scale prod-dump-rehearsal er IKKE kørt** (kræver prod-adgang) — anbefales: test-restore
  Trin 0-dumpet lokalt + kør Trin 1-3 mod dén kopi før prod-kørsel.
