# Problem 2 — Fase 4 prod-cutover runbook

**Status:** Forberedt, IKKE udført. Prod-anvendelse kræver eksplicit bruger-godkendelse der navngiver
prod-målet. **Prod har INGEN backup.** Reviewet af to fable-agenter (2026-07-16) — denne version
adresserer deres fund.

**Formål:** Anvend Problem 2 DB-laget (forældrefamilie-slot + konkurrerende påstande) på prod.

## Forbindelse (KRITISK)

Brug **Session pooler (port 5432, IPv4)** eller direkte forbindelse — IKKE transaction-pooleren
(6543): `pg_dump`/`pg_restore`/`--single-transaction` virker ikke pålideligt dér (ingen session-state).
Sæt password via `PGPASSWORD`/`~/.pgpass`, ALDRIG i conn-strengen på kommandolinjen (shell-history/ps).
Verificér basen er vågen (Supabase free-tier pauser efter 7 dages inaktivitet — pause under cutover er slem).

## Skrive-frys (obligatorisk)

Ingen redaktør-aktivitet fra Trin 0 til Trin 3 er grøn. Hele basen bruger `max(id)+1`-id-allokering
(race-følsom); en samtidig skrivning under backfillen kan give PK-kollision, og skrivninger mellem
dump og evt. rollback tabes. Kommunikér kort nedetid.

## GATE 0 — Rehearsal mod test-restore (OBLIGATORISK, ikke valgfri)

Uden backup er en utestet restore ikke en rollback. FØR prod røres:
1. Tag prod-dumpet (Trin 0 nedenfor) og `pg_restore` det til en **lokal engangs-DB**.
2. Kør Trin 1-3 mod kopien → bekræft grønt (lokalt kan redaktion-profilen seedes, så OGSÅ de
   rolle-gatede verify-blokke bliver grønne — se Trin 3).
3. **Øv rollbacken** mod kopien: kør `db-rollback-foraeldrefamilie.sql`, bekræft alle Problem 2-objekter
   væk + funktioner revertet. (Denne øvelse er allerede kørt lokalt 2026-07-16 mod syntetisk bed — gentag mod prod-dump-kopien.)

## Forudsætninger (verificér på prod FØR noget anvendes; read-only)

```sql
-- (a) SINGLE-EDITION: kun DAA 2018-20 har barn-data (KRITISK — backfillen fejl-citerer ellers).
SELECT id, udgave, aar, slags FROM source ORDER BY id;
-- (b) INGEN dublet-fødselsfamilier (EXCLUDE-prætjek + tekst-identisk med db-migrations.sql:~2009)
SELECT count(*) FROM (SELECT person_id FROM family_member WHERE rolle='barn' GROUP BY person_id HAVING count(*)>1) t;   -- =0
-- (c) umigreret baseline
SELECT exists(select 1 from information_schema.columns
              where table_schema='public' and table_name='assertion' and column_name='objekt_type');   -- =false
-- (d) barn-rækker m. kilde <> DAA 2018-20 (backfillen ville aborte — men bekræft manuelt)
SELECT count(*) FROM family_member fm JOIN person_external_id pe ON pe.person_id=fm.person_id
  JOIN source s ON s.id=pe.source_id WHERE fm.rolle='barn' AND s.udgave IS DISTINCT FROM 'DAA 2018-20';   -- =0
-- (e) barn-rækker UDEN external_id (multi-edition-abortens falsk-negativ; eyeball proveniens før Trin 2)
SELECT count(*) FROM family_member fm WHERE fm.rolle='barn'
  AND NOT EXISTS (SELECT 1 FROM person_external_id pe WHERE pe.person_id=fm.person_id);
```

## Trin 0 — BACKUP (obligatorisk, eneste rollback-kilde)

```bash
export PGPASSWORD='…'   # ikke i conn-strengen
pg_dump -h <session-pooler-host> -p 5432 -U <user> -d <db> --schema=public -Fc \
  -f ~/daa-prod-backup-$(date +%Y%m%d-%H%M).dump
chmod 600 ~/daa-prod-backup-*.dump          # PII: levende-persondata
# krypter (age/gpg) + notér sletningsfrist efter verificeret cutover. ALDRIG i git / docs/db-backups/.
```
GATE 0 (test-restore + rollback-øvelse) SKAL være grøn før Trin 1.

## Trin 1 — Skema-migration (DDL + funktioner, INGEN backfill)

```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> --single-transaction -v ON_ERROR_STOP=1 -f db-migrations.sql
```
- `--single-transaction` (husets deploy-procedure, database-current-state §4) → alt-eller-intet.
- Idempotent additiv: assertion.objekt-kolonner+indeks, vocab 'forældrefamilie', EXCLUDE (fail-closed
  prætjek), alle red_*-RPC'er + guardet helper + view. **Ingen backfill.** EXCLUDE-prætjek aborter ved (b)≠0.
- `LC_ALL=C` → fejl printes `ERROR:` (ikke dansk `FEJL:`), så fejl ikke overses.

## Trin 2 — Backfill (DELIBERAT, kun efter (a)+(d)+(e) bekræftet). Køres ÉN gang, straks efter Trin 1.

```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> -v ON_ERROR_STOP=1 -f db-backfill-foraeldrefamilie.sql
```
- Fail-closed: STRICT-kildeopslag + external_id-multi-edition-abort. Idempotent (NOT EXISTS). Forventet: "Backfill færdig …".

## Trin 3 — Verificér (db-verify) — REALISTISK prod-forventning

```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> -f db-verify.sql 2>&1 | grep -iE "OK:|SPRINGER|ERROR|FEJL"
```
- **db-verify.sql's header siger "Kør ikke mod prod-base"** — de rolle-gatede fixture-blokke
  (forældre-konflikt, forældre-undo, mutator-slot-vedligehold) kræver en redaktion-profil for test-UUID
  `…0001` (FK til `auth.users`), som IKKE findes på prod → de printer **SPRINGER OVER**, og H2-bookmark-
  blokken kaster en kendt ERROR. Det er FORVENTET på prod — beviset for de blokke ligger i GATE 0-rehearsal.
- **PÅ PROD forventes grønt KUN for de ugatede asserts:** `forældre-backfill-komplethed + P1-drift`
  (nu IKKE skippet, da slots findes). Ingen UVENTEDE ERROR/FEJL.
- NB: db-verify seeder/rydder negativ-id-fixtures + skriver/sletter test-rækker i `auth.users`/`bookmark`
  (db-verify.sql:~1106) — sikkert, men kør bevidst. Alternativ: kør FULD verify kun mod GATE 0-kopien,
  og kun de ugatede asserts mod prod.

## Trin 4 — Sikkerheds-advisors (efter DDL)

Kør Supabase `get_advisors(security)`. Forvent: alle nye funktioner `SECURITY DEFINER SET search_path=public`
+ `current_rolle()`-gated (INKL. helperen efter fable-fix); `red_foraeldre_konflikt` `security_invoker=true`;
slot arver person-gatede RLS (ingen ny tabel). **Verificér empirisk at helperen IKKE er anon-kaldbar**
(advisors fanger ikke nødvendigvis en manglende rolle-guard) — jf. [[koer-get-advisors-efter-ddl]].

## Trin 5 — Post-cutover

- Opdatér `docs/changelog.md` + `docs/database-current-state.md` §5.
- Ophæv skrive-frysen. Slet/afkrypter backup efter frist.

## Loadere fremadrettet

load_daa.R/load_presens.R (`member_evidence`) KRÆVER den migrerede base — fejler ellers atomisk med
"column objekt_type … does not exist". **NB ([[r-env-renviron-override-farlig]]):** R-loaderne læser
prod via `~/.Renviron` og kan IKKE omdirigeres via shell-env — pег ALDRIG en loader mod en lokal kopi
i troen på at env-vars redirecter; brug `R_ENVIRON_USER=<lokal .Renviron>` (verificér current_database).

## ROLLBACK (ved fejlet cutover — under skrive-frys, ingen writes tabt)

**Primær (kirurgisk, foretrukket):**
```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> -f db-rollback-foraeldrefamilie.sql
```
Atomisk (én transaktion): sletter backfill/slot-data, reverterer de tre objekt-refererende funktioner
til pre-Problem-2, dropper view/RPC'er/helper/EXCLUDE/objekt-kolonner/vocab. Rehearset mod migreret+
backfyldt bed (alt væk, funktioner revertet). Efterlader harmløs guard-død-kode i de 6 fakta-RPC'er.

**Nuklear sidste udvej (fuld restore — kun hvis basen er kompromitteret ud over Problem 2):**
```bash
# --clean alene er UTILSTRÆKKELIGT (dropper ikke Problem 2-objekter, dependency-fejl). Kør down-scriptet
# FØRST (fjerner de nye objekter/dependencies), DEREFTER:
pg_restore -d "host=<host> port=5432 user=<user> dbname=<db>" --clean --if-exists --no-owner ~/daa-prod-backup-<dato>.dump
```
Mister skrivninger foretaget efter Trin 0-dumpet (derfor skrive-frys).

## Efter cutover (SEPARAT, senere gate)

Load af divergerende **1939-stamtavle** til prod (Problem 2's egentlige mål) — selvstændig bruger-
godkendt handling (levende-PII, gitignoreret). IKKE del af denne cutover.

## Rehearsal-log (lokalt, 2026-07-16)

- Migration + backfill på ren single-edition-bed m. edge-cases: subtyper backfyldes IKKE; partnerløs-
  familie-barn får slot; 0 P1-brud. Backfill single-edition→succes, multi-edition→ABORT (0 slots).
- Rollback-øvelse: migreret+backfyldt → down-script → alt væk, funktioner revertet.
- Helper-guard: intern kald (via gated funktioner) OK; direkte non-redaktion afvist.
- Alle Problem 2 db-verify-blokke grønne mod daa_test2 (m. seedet redaktion-profil).
- **UDESTÅR:** real-scale prod-dump-rehearsal (GATE 0) — kræver prod-adgang + bruger-godkendelse.
