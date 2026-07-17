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
2. Kør Trin 1-1b-2-3 mod kopien → bekræft grønt (lokalt kan redaktion-profilen seedes, så OGSÅ de
   rolle-gatede verify-blokke bliver grønne — se Trin 3). Trin 1b (db-rls.sql) skal med, så F-01/F-02
   også rehearses.
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
-- (f) F-02c BLAST-RADIUS (mål FØR Trin 1b): antal family-scoped fakta/noter der bliver SKJULT fordi
--     familien har mindst ét levende medlem (bevidst GDPR-fail-close; en historisk vielse mellem to
--     afdøde skjules hvis et levende barn er i samme family). Kør på GATE 0-kopien for at kende tabet.
SELECT
  (SELECT count(*) FROM fact f WHERE f.subjekt_type='family'
     AND EXISTS (SELECT 1 FROM family_member m JOIN person p ON p.id=m.person_id
                 WHERE m.family_id=f.subjekt_id AND coalesce(p.levende,true)=true)) AS skjulte_family_fakta,
  (SELECT count(*) FROM note n WHERE n.target_type='family'
     AND EXISTS (SELECT 1 FROM family_member m JOIN person p ON p.id=m.person_id
                 WHERE m.family_id=n.target_id AND coalesce(p.levende,true)=true)) AS skjulte_family_noter;
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
- **Inkluderer nu OGSÅ (samme fil, additivt):** A1 dato-hærdning (`assertion.date_certainty`-kolonne + CHECK,
  faktavokabular) og **K2 staging-gate** (`person.staged`-kolonne + `red_publicer_udgave(source_id)`-RPC).
- `LC_ALL=C` → fejl printes `ERROR:` (ikke dansk `FEJL:`), så fejl ikke overses.

## Trin 1b — RLS/grants (db-rls.sql) — deployer F-01 + F-02

```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> --single-transaction -v ON_ERROR_STOP=1 -f db-rls.sql
```
- **KRITISK:** db-rls.sql gen-anvendes IKKE af Trin 1 (migrations), men er hjem for sikkerhedsfixene
  der ellers ikke når prod: **F-01** (REVOKE af anon-EXECUTE på interne `_`-helpers, PR #42), **F-02**
  (auth_read fail-close på levende), **F-02c** (polymorf family/unknown fail-close) og **K2 staging-gate**
  (`person_offentlig` udvidet med `coalesce(staged,false)=false` → skjuler ny-udgave-poster; cascader til
  fact/relation/narrative via `entitet_offentlig`).
- Idempotent (alle policies `drop … if exists` + `create`; grants/revokes deklarative). Rører kun
  eksisterende tabeller/funktioner → kan køre før ELLER efter Trin 1; her efter for én sammenhængende deploy.
- **Produkt-konsekvens (F-02):** logget-ind bogmærke-brugere ser herefter samme som anon (kun afdøde).
  Bevidst indtil samtykke-/slægts-scope bygges (Codex-fund F-05). Bekræft at dette er ønsket før cutover.

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
  (nu IKKE skippet, da slots findes), **Task 8b (F-02 authenticated fail-close)**, **A1 dato-hærdning**
  (`OK: dato-hærdning A1 …`) og **K2 staging-gate** (`OK: K2 staging-gate …`) — de sidste to bruger kun
  negativ-id-fixtures + anon-RLS (INGEN redaktion-profil), så de kører OGSÅ på prod. Ingen UVENTEDE ERROR/FEJL.
  *Lokal rehearsal 2026-07-17 (frisk DB u. auth-shim/data): 26 asserts grønne inkl. A1+K2+F-02/F-02c; de 21
  ikke-grønne var alle miljø/data-afhængige (auth.users-FK, storage.buckets, tom-DB-data) — bekræftet i GATE 0.*
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

## Fase 2 — 1939-stamtavle-load til prod (SEPARAT, senere gate)

Selvstændig bruger-godkendt handling EFTER cutoveren er grøn (levende-PII, gitignoreret). IKKE del af
skema-cutoveren.

✅ **FORUDSÆTNING 1 (A4-gentagelse) — GJORT 2026-07-17:** artefaktet regenereret til konverter **v1.3.0**
(539 poster, **355 links**, 0 falske/0 modsigelser/0 re-pegede) og A4 dry-run kørt grønt mod isoleret tom
base (`daa_a4v13`, A1+K2 til stede): 355 barn-links = 355 slot-assertions (P1 holder), 948 assertions m.
date_min/max (matcher-input sikret), 539 narrative 0-null, GDPR-sweep 7 levende. Se plan-1939 §A4.

Rækkefølge (Fase 2 / Konvergens):

1. **Rehearsal-load mod prod-KOPI (K1, OBLIGATORISK):** load 1939 mod GATE 0-kopien (ikke prod), og test
   end-to-end at RLS + matcheren (`matchUdgaver.ts`) + collapse + offentlig UI virker sammen med de
   rigtige 2018-20-data. Bekræft at matcheren faktisk får `date_min/date_max` fra 1939-datoerne.
2. **Rigtig load MED `--staged` (K3):** `R_ENVIRON_USER=<prod-Renviron> Rscript load_daa.R \
   work_1939_stamtavle/clean_1939.json "DAA 1939" --staged` (aar=1939). `--staged` = alle 1939-poster
   skjult for anon indtil matchet (K2). Append-mode, ALDRIG `--reset`.
3. **Match-gennemgang (redaktør):** kør matcheren i redaktør-fladen → markér samme_som / ikke_samme_som
   for kandidat-parrene. Umatchede dubletter forbliver skjult (staged) — ingen dublette Conrad'er offentligt.
4. **Publicér:** når gennemgangen er færdig, kald `red_publicer_udgave(<1939-source-id>)` → rydder `staged`
   for udgavens poster + partner-stubs → 1939 bliver offentlig. (target: pr-person-afstaging ved review
   når matcher-UI wires; RPC'en er PoC-default = hele udgaven samlet.)

**Facit før publicering (fra `facit_1939.py`, ingen PII):** 539 poster; forælder-link-tal = **det
regenererede v1.3.0-artefakts** (v1.1.0-referencen var 364/67%, v1.3.0 forventes lavere pga. fail-closed
scope — bekræft ved A4-gentagelsen); GDPR-flag 7 (født ≥1926 u. død → `levende=TRUE`, skjult uafhængigt
af staging). Uopløste barn-links parkeres (staged, ikke publiceret).

## Rehearsal-log (lokalt, 2026-07-16)

- Migration + backfill på ren single-edition-bed m. edge-cases: subtyper backfyldes IKKE; partnerløs-
  familie-barn får slot; 0 P1-brud. Backfill single-edition→succes, multi-edition→ABORT (0 slots).
- Rollback-øvelse: migreret+backfyldt → down-script → alt væk, funktioner revertet.
- Helper-guard: intern kald (via gated funktioner) OK; direkte non-redaktion afvist.
- Alle Problem 2 db-verify-blokke grønne mod daa_test2 (m. seedet redaktion-profil).

**Rehearsal 2026-07-17 (efter A1+K2+linjenorm merget til main):** fuld cutover-kæde mod frisk DB (base =
daa_test2-skema u. A1+K2). Trin 1 (migrations, idempotent 2×) + 1b (rls) + 2 (backfill) kørte rent →
A1+K2 tilføjet korrekt (`date_certainty`, `person.staged`, `red_publicer_udgave`, `person_offentlig`
staged-klausul). Trin 3 db-verify: **26 asserts grønne** inkl. A1, K2, F-02, F-02c, media, helpers; 5
skippet + 21 fejl var ALLE miljø/data-afhængige (10× auth.users-FK, 3× storage.buckets, 8× tom-DB-data) —
ingen kode-bugs. Bekræfter cutover-kæden er kohærent efter K2.
**✅ CUTOVER UDFØRT 2026-07-17 mod prod `xjnvdhajfyrcytatnzos`:** GATE 0 grøn (49 asserts mod tro prod-kopi + rollback-øvelse); Trin 0 krypteret backup; Trin 1-4 committed + verificeret på prod (Problem 2 + A1 + K2; 566 forældrefamilie-slots; P1 holder; GDPR intakt; search_path/RLS ✓). Data uændret (923 pers, 566 barn-links, 0 staged). **Fase 2 (1939-load) udestår — separat godkendelse.**
- ~~**UDESTÅR:** real-scale prod-dump-rehearsal (GATE 0) — kræver prod-adgang + bruger-godkendelse.
