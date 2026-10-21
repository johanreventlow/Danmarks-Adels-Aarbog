# Overførsel af 5a + 5b (2018-20) — plan A: fase 0 og DDL-ceremonien (GO 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (**native**) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent-drevet udførelse er udelukket for Task 0 og 4-7: scriptene ligger i `~/.private/`, og testene rører restores med persondata. Task 1-3 (repo-filer, syntetiske baser) må gives til en subagent, men aldrig med adgang til `~/.private/`, `work*/` eller en restore.

**Goal:** Byg og øv den fail-closed DDL-ceremoni, der deployer 5a+5b's DDL i prod (spec §5, §6.1, §8 GO 1 og DDL-fortrydelsen). Planen er færdig ved `REHEARSAL_OK (DDL)` på en lokal stand-in af prod, inklusive afbruds- og fortrydelsesøvelse, grønne repo-tests i CI og en committed runbook. Selve kørslen i prod (fase 0 → D0 → GO 1 → DDL → probe → D1) er projektejerens bagefter.

**Architecture:** Formen er trin 4's ceremoni (`~/.private/2018-20-overfoersel/`) og omsegmenteringens DDL-script (`~/.private/omseg-prod/04-ddl.sh`). En ny privat mappe `~/.private/5ab-overfoersel/` med én `lib.zsh` og små zsh-scripts. Hver skrivende eller målende handling er én lib-funktion, som rehearsal kalder lokalt og prod-scriptene kalder mod prod (samme bytes). De to nye målinger (katalog- og ACL-fingeraftryk) og fortrydelsens objektliste er **repo-filer** med CI-tests, så plan B og GO 1 binder de samme bytes. Plan B (datadelen: nøglede digests, svaroverførsel, pakke, genspil, GO 2) skrives, når D1 findes, og bygger videre i samme private mappe.

**Tech Stack:** zsh (`/bin/zsh -f`), psql/pg_dump/pg_restore 17 (`/opt/homebrew/opt/postgresql@17/bin`), Python 3 (`/usr/bin/python3 -I`), bash-testscripts mod PostgreSQL 17 (lokalt og CI-jobbet `writer-1939-v50-db`), Supabase Session pooler.

**Spec:** `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (§2, §5, §6.1, §8, §9 DDL-delen, §10 DDL-delen). Forudsætningsleddet er merget (#251, `e8039c69`). Forlæg: `~/.private/2018-20-overfoersel/lib.zsh` (forbindelse, skrivepause, dump, `undo_restore`, `reconcile_grants`, `chars_json`, GO-inventar), `~/.private/omseg-prod/04-ddl.sh` + `lib.zsh` (`schema_fingerprint`, DDL-gaten, genkørsel), `docs/runbooks/transfer-2018-20-prod.md`.

## Roadmap-adgangskrav

Som spec §1. Plan A leverer DDL-halvdelen: efter projektejerens GO 1 har prod 5a/5b-DDL'en, og D1 findes som fortrydelsespunkt og udgangspunkt for plan B's arbejdskørsel. Ingen data skrives. Rækken »Source persona, identitetskandidater og webkø« i `status.md` løftes først ved plan B's `VERIFY_OK`. **Repo-fodaftryk:** 3 SQL/Python-filer, 2 testfiler, én CI-linje pr. job, runbook og docs.

## Global Constraints

- **Ingen prod fra AI-sessionen.** Prod rammes kun af projektejeren i egen shell: `! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh <script> …` (hukommelse »prod-skrivning-via-brugerens-shell«). Undtagelse: `get_advisors(security)` via Supabase-MCP, kun på projektejerens ja i samme tur, og kun lint-navne og antal skrives ned.
- **Skrivepause:** prod redigeres ikke fra 2026-10-20 til data-ceremonien (projektejeren). Plan A's `00-freeze.sh begin` gør pausen formel før D0. Pausen ophæves **ikke** i plan A; den løber videre til plan B's `VERIFY_OK` (eller en fortrydelse).
- **Ingen kildetekst, navne, noter eller aktør-uuid** på stdout, i chat, repo eller commits. Kun tal, koder og hashes. psql-stderr til 0600-filer; derfra udtrækkes kun en kode, der matcher `^[A-Z][A-Z_]+$`.
- **Privat layout:** `~/.private/5ab-overfoersel/` (0700; filer 0600, scripts 0700). Kørselstilstand i `…/prod/` eller `…/standin-<base>/` (vælges af `DAA_STANDIN_DB`).
- **Konventioner (som trin 4):** `/bin/zsh -f` med `assert_no_rcs`, `emulate -R zsh`, `set -euo pipefail`, `umask 077`, `setopt POSIX_TRAPS`. Alle `PG*` ryddes; `PGTZ=UTC`; kun Session pooleren (`*.pooler.supabase.com:5432`). Skrivende scripts kræver præcis `--jeg-mener-det`; ukendte argumenter giver exit 2. Python kun som `/usr/bin/env -u PYTHONOPTIMIZE -u PYTHONPATH -u PYTHONHOME -u PYTHONSTARTUP /usr/bin/python3 -I`, fejl med `raise SystemExit("KODE")`, aldrig `assert`. Læse-kun psql med `PGOPTIONS='-c default_transaction_read_only=on'`.
- **Lokale baser** matcher `^daa5ab_ddl_(standin|rehearsal|d0check|d1check)_[0-9]{14}(_[a-z0-9]+)?$`. Bevisbaserne (`daa2018f_20261001133125`, `daa5b_bevis_20261010093638`, `daa5b_2a_bevis_20261011185524`, `daa5b_2b_i_bevis_…`, `daa5b_2b_ii_bevis_…`, `daa5b_navnv3_bevis_…`, `daa5b_2b_iii_bevis_…`, `daa244_bevis_20261020222244`) og `~/.private/5a/` ændres og slettes aldrig; de er plan B's input. Planen dropper ingen lokale baser; de noteres til oprydning (sletning kun efter måling og ja).
- **Repo-tests:** synthetic baser med præfiks fra argumentet (`t5ab_*` lokalt, `ci_ddl_*` i CI); droppes ved grøn kørsel, efterlades ved rød.
- **Commits:** én pr. task, `type(151): …` på dansk, afsluttet med `Claude-Session: https://claude.ai/code/session_014CxSBLeSAQHZznEhPJ3Y6M`. Ingen push uden ja. Privat kode committes aldrig.
- **Lokal CI før push** (hukommelse »kør hele CI-jobbet lokalt«): jobbene `python` og `writer-1939-v50-db` køres hele med runneren fra #251 (disposable cluster på 55432, server-env sat for dblink).

### Konstanter (målt 2026-10-21 fra trin 4's prod-filer)

| Navn | Værdi |
| --- | --- |
| `DAA_PROD_TARGET` | `71ca6e452cc7d596d8470807e29084cd9d99f8ac24155556afd635da84ffe0f0` (`clause_evidence_target_identity.sql`) |
| Trin 4's digests i prod 2026-10-05 (`interpretation_transfer_digests.sql`) | `proposal_digest` `bb808efeeecfe79153590a1707f545231b3915d9597db15ea06191acbdf44c8a`; `decision_digest` `33fc4b5618192b856f55cf2fc13ff1f470da080c4184e3bfc21f80ee531b414c`; `binding_digest` `5762ceaa9585ef282c8705909a45bea874771455eb6dbe2741db8a76ac8ede7d`; 3.739 / 676 / 622 |
| Driftsbaselinen (`transfer_baseline.sql`) | `schema_sha256` `12d8d841cf1f4b872b0eda2acf7990dcc2260bb58b3afbd4ed277735621e8902`; `canonical_sha256` `1137bce7a7f65a74b8d46a57951a4e4ca722155368e377d727ab1981be43ffbd`; `clause_set_sha256` `113a1d12550e0a4f4b0f0b8cce4e73a4a1e04311c2e93397b2fff8e7ac3d1fea` |
| Trin 4's skrivepause sluttede | `2026-10-05T11:03:06Z` (`freeze-end-20261005110306.json`); `verify-ok-20261005110306.json` sha `1e08e80a98a684c4da539e456e32c9d0b1ef97a0fe84aece64c3031db2f0ec0d` |
| Aktør | `actor_sha256` `3c4984c769aa63a4c4f81be7f001abf162f016eb72704656dcbc6618ceb71e59` (én `profiles.rolle='redaktion'`) |
| Prods DDL-træ | `b42266e` (omsegmenteringen 2026-09-28; ingen `db-migrations.sql`-ændring fra da til #236) |
| 149b-identiteter | 587 accepterede med `evidence->>'authority'='person_external_id'` |

Øvrige værdier (prods katalog- og ACL-fingeraftryk, `pg_default_acl`, locale, varigheder) måles i Task 0 og 4 og bindes i GO 1.

### Spec → virkeligheden (errata; bindes i `decisions.md` i Task 7)

| Spec siger | Virkeligheden og afgørelsen |
| --- | --- |
| §2: kæden er rod → 5a → del 1 → … | 5b del 1's base er en kopi af roden, ikke af 5a's (`relationspersonas-5b-del1-bevis.md`). 5a's bevisbase `daa5a_bevis_20261005223551` er droppet 17/10 (`drop-liste.txt`). 5a's 31 afgørelser (blind genbekræftelse af 149b: 24 × kandidat 1, 6 × `U`, 1 `web_detail`) findes kun i `~/.private/5a/`. **Projektejeren 2026-10-21: de 31 afgørelser overføres ikke**; 5a's kode deployes. 5a's identitetsvej bevises i prod af 5b's afgørelser, der går gennem samme `decide_source_persona_identity`. Kun webkøens `web_detail`-spor er ubrugt i prod. Påvirker plan B (§6.2's rækkefølgesætning, §6.3's 5a-række, §9's modenhed); plan A rører det ikke. |
| §2: »alle bevisbaser bevares« | 5a's er væk (ovenfor). Del 1's og 2a's lå i karantæne som `slet_1017__…`; **omdøbt tilbage** 2026-10-21. |
| §4 pkt. 6 / §10: opgradering »fra prods træ 2026-10-05« | #251's test startede fra `140a17b`, men prods seneste DDL er `b42266e` (28/9; 902 linjer nyere `db-migrations.sql`). Task 0 kører #251's opgraderings- og determinismetest fra `b42266e`; plan A's egen test (Task 3) bygger fra `b42266e`. Den egentlige opgraderingsprøve er rehearsal på D0. |
| §5: dump »krypteret« | Som trin 4 og omsegmenteringen (`database-current-state.md` l. 406, 483): 0600 uden for Git på en FileVault-krypteret disk (`fdesetup status`: On, målt 21/10). Ingen gpg-lag; det ville kræve dekryptering i fortrydelsens kritiske vej. |
| §6.1 trin 3, afbrudspunkt 3: »mellem en 5b-tabels oprettelse og dens RLS/REVOKE« | 5b-tabellernes RLS og `REVOKE` ligger i `db-rls.sql` (l. 22-38), ikke i migrationsfilen. Punktet er derfor: hele `db-migrations.sql` kørt, `db-rls.sql` ikke. |
| §7: udeladte felter | `decision_interpretation_id` tilføjes udeladelseslisten (plan B). |
| — (#251's udskudte minor) | `lower(visning_navn)` afhænger af `datctype`. Fase 0 måler `datcollate`/`datctype`/`datlocprovider` og tegnproben (`chars_json`, trin 4) og kræver dem lig trin 4's prod-preflight 2026-10-05. Plan B bruger målingen til sine `hash_gated`-skridt. |
| §5: »get_advisors gemmes som baseline« | Kun via projektejeren (dashboard) eller MCP på ja i turen; lint-navn + antal i `advisors-before.txt`. |

### Invarianter

- **I1 Samme bytes.** `step_ddl`, `measure_fingerprints`, `undo_ddl` er lib-funktioner; `03-rehearsal-ddl.sh` kalder dem lokalt, `04-ddl.sh`/`09-undo-ddl.sh` mod prod. Prefix-filerne til afbrudsøvelsen og fortrydelsens DROP-SQL laves af den samme repo-fil (`transfer_ddl.py`).
- **I2 Tilstand først.** `04` klassificerer prods katalog før første skrivning: lig preflightens ⇒ skriv; lig rehearsalens efter-fingeraftryk ⇒ `ALREADY_APPLIED` (exit 0, intet skrevet); andet ⇒ kun med `DAA_DDL_GENKOERSEL=ja` plus gate-markøren fra samme pause (et afbrudt `04`), ellers STOP.
- **I3 Hash-bundet.** Hvert prod-script verificerer GO-hashfilen (eksakt mængde), rent repo for inventarets stier og commit = `DAA_EXPECTED_COMMIT`, før første forbindelse.
- **I4 Lukket miljø.** I prod-tilstand afvises `DAA_FAULT`, `DAA_LOCAL_*`, `DAA_STANDIN_*` og `DAA_REIMPORT_ACTOR_ID` før forbindelse.
- **I5 Ingen PII ud.** stdout læses kun for markører; fingeraftrykkenes linjefiler indeholder kun objektnavne, rollenavne og md5'er (ingen data) og er 0600.
- **I6 Mål.** I prod skal mål-identiteten være `DAA_PROD_TARGET`; lokalt noget andet.
- **I7 Skrivepause.** Aktiv fra før D0's start. `04`'s første forsøg kræver restore-hash = D0-kvitteringens og 0 `change_set` med `created_at ≥ dump_start` (`NO_WRITE_SINCE_DUMP`). D1 tages i samme pause og kræver `DDL_VERIFY_OK` fra den.
- **I8 DDL skriver ingen data.** Trin 4's tre digests, driftsbaselinens `canonical_sha256` og `transfer_untouched_hash.sql` er uændrede over DDL'en (målt i rehearsal, krævet i prod).

## Review Focus

1. **Prods katalog afviger fra D0-restorens på en måde, rehearsal ikke ser** (fx Supabase-ejede objekter i `public`, extensions, eller en `pg_default_acl` for en anden rolle end den, der kører DDL'en). Forventet: fase 0 sammenligner prods katalog- og ACL-fingeraftryk med D0-restorens straks efter dumpet; afvigelse ⇒ `RESTORE_FINGERPRINT_DRIFT` før GO 1. Test: Task 5 Step 2 (restoreverifikationen) og Task 6 Step 4 (manipuleret default-ACL i stand-in ⇒ STOP).
2. **Forbindelsen dør midt i `db-migrations.sql` i prod.** Forventet: `04` med `DAA_DDL_GENKOERSEL=ja` gør det færdigt, og fingeraftrykkene bliver rehearsalens. Test: Task 3 (tre prefix-punkter i CI) og Task 6 Step 3 (`DAA_FAULT=ddl:after_migrations` og `ddl:in_5a_cutover` mod stand-in).
3. **Åbne rettigheder i afbrudsvinduet.** Mellem migrationer og `db-rls.sql` findes nye private tabeller uden RLS; med Supabases default privileges kan de have grants til `anon`/`authenticated`. Forventet: `anon` og `authenticated` har ingen `USAGE` på skemaet `private` i noget vindue, så rækkerne er ulæselige; efter fuld apply er ACL-fingeraftrykket rehearsalens. Test: Task 3 Step 1 (`has_table_privilege` + `has_schema_privilege` ved hvert punkt).
4. **Fortrydelsens DROP-liste rammer for lidt eller for meget.** En ny funktion, der bruges af en trigger på en eksisterende tabel, eller en ny kolonne på en eksisterende tabel. Forventet: listen indeholder kun objekter, der ikke findes i preflightens katalog; `pg_restore --clean` genskaber resten; efter fortrydelsen er katalog-, ACL- og restore-hash lig fase 0's. Test: Task 2 (enhedstests med trigger- og kolonnetilfældet) og Task 5 Step 4 (fortrydelsesøvelsen).
5. **Genkørsel af `04` efter commit** (projektejeren kører det to gange). Forventet: `ALREADY_APPLIED`, intet skrevet, `ddl.json` uændret. Test: Task 6 Step 2.

---

## Filoversigt

Repo (committes):

| Fil | Ansvar |
| --- | --- |
| `.claude/skills/daa-extract/scripts/transfer_catalog_fingerprint.sql` | Læse-kun: én linje pr. objekt i `public`/`private` (`art|identitet|md5(definition)`), restore-stabil (ingen oid'er, ejere eller ACL'er) |
| `.claude/skills/daa-extract/scripts/transfer_acl_fingerprint.sql` | Læse-kun: grants på objekter og skemaer, `pg_default_acl` og privilegiematrixen for `PUBLIC`/`anon`/`authenticated`/`service_role` |
| `.claude/skills/daa-extract/scripts/transfer_ddl.py` | `prefix` (afbrudsfil ved et navngivet punkt) og `removal-sql` (fortrydelsens DROP-transaktion ud fra to kataloglister) |
| `.claude/skills/daa-extract/scripts/test_transfer_ddl.py` | Enhedstests for `transfer_ddl.py` (pytest, CI-jobbet `python`) |
| `tests/sql/test-transfer-5ab-ddl.sh` | Integration fra `b42266e`: idempotens, tre afbrudspunkter, åbne rettigheder, DROP-listen, fingeraftrykkenes følsomhed (CI-jobbet `writer-1939-v50-db`) |
| `.github/workflows/ci.yml` | De to nye tests tilføjes de to jobs |
| `docs/runbooks/transfer-5ab-ddl-prod.md` | Autoritativ DDL-ceremoni: kommandoer, GO 1-pakke, stopregler, fortrydelse |
| `docs/decisions.md`, `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md` | 5a-afgørelsen, errata, statuslinje |

Private (`~/.private/5ab-overfoersel/`, aldrig i git):

| Fil | Ansvar |
| --- | --- |
| `lib.zsh` | Kopi af trin 4's `lib.zsh` (forbindelse, pause, dump, `undo_restore`, `reconcile_grants`, `chars_json`, GO-inventar) + nye funktioner: `measure_fingerprints`, `emulate_default_acl`, `step_ddl`, `undo_ddl`, `ddl_state`. Trin 4's data-funktioner (`step_decide`, `step_bind`, R-kald) fjernes |
| `koer.zsh` | Indgang; vælger prod eller stand-in og logger exitkode (som trin 4) |
| `00-freeze.sh` | `begin` / `end` (som trin 4; `end` kræver plan B's `verify-ok.json` eller `undo-ok.json`) |
| `01-preflight.sh` | Fase 0 (spec §5), læse-kun → `preflight.json` (`PREFLIGHT_OK`) |
| `02-dump.sh` | `d0` / `d1`: dump + restoreverifikation + kvittering |
| `03-rehearsal-ddl.sh` | Lokal: restore af D0, emulerede default privileges, apply ×2, `db-verify.sql`, tre afbrudsøvelser, fortrydelsesøvelse → `REHEARSAL_OK` (DDL) + GO-hashfil |
| `04-ddl.sh` | `--jeg-mener-det`: `step_ddl` mod prod → `ddl.json` (`DDL_OK`) |
| `05-probe-ddl.sh` | Læse-kun probe efter DDL → `ddl-verify.json` (`DDL_VERIFY_OK`) |
| `09-undo-ddl.sh` | `--jeg-mener-det`: `undo_ddl` mod prod → `undo-ok.json` (`UNDO_OK`) |
| `rollback-preflight.sql` | Kopieret fra trin 4 |

### GO 1-inventar (eksakt mængde; endelig liste skrives i runbooken i Task 7)

- **Privat (11):** `lib.zsh`, `koer.zsh`, `00-freeze.sh`, `01-preflight.sh`, `02-dump.sh`, `03-rehearsal-ddl.sh`, `04-ddl.sh`, `05-probe-ddl.sh`, `09-undo-ddl.sh`, `rollback-preflight.sql`, `expected-new-relations.txt`.
- **Repo (11):** `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`, og under `.claude/skills/daa-extract/scripts/`: `transfer_catalog_fingerprint.sql`, `transfer_acl_fingerprint.sql`, `transfer_ddl.py`, `transfer_restore_hash.sql`, `transfer_untouched_hash.sql`, `transfer_baseline.sql`, `interpretation_transfer_digests.sql`, `clause_evidence_target_identity.sql`.
- **Rapporter (bindes med sha i `go-env.txt`):** freeze-begin, `preflight.json`, D0-kvitteringen, `rehearsal-ddl.json`, `advisors-before.txt`.

---

### Task 0: Forudsætninger målt og input sikret

**Files:** ingen repo-ændringer; resultater i ledgeren.

- [ ] **Step 1: Bevisinput findes uændret**

```bash
psql -X -At -d postgres -c "SELECT datname FROM pg_database WHERE datname IN ('daa2018f_20261001133125','daa5b_bevis_20261010093638','daa5b_2a_bevis_20261011185524','daa5b_2b_i_bevis_20261012093656','daa5b_2b_ii_bevis_20261017132417','daa5b_navnv3_bevis_20261019200958','daa5b_2b_iii_bevis_20261020182757','daa244_bevis_20261020222244') ORDER BY 1" | wc -l
shasum -a 256 ~/.private/5a/IDENTITET.txt ~/.private/5a/g-rows.json | cut -c1-16
```

Forventet: `8`; `ada4e9fdee2fb19b`, `e7df4f4a67384f7b`. Afviger noget: STOP og spørg.

- [ ] **Step 2: #251's opgraderingsprøver fra prods rigtige træ**

```bash
bash tests/sql/test-indholds-id-upgrade.sh t5ab_up b42266e > "$WS/up.log" 2>&1; tail -1 "$WS/up.log"
bash tests/sql/test-indholds-id-determinism.sh t5ab_det upgrade:b42266e > "$WS/det.log" 2>&1; tail -1 "$WS/det.log"
```

Forventet: `UPGRADE_OK` og `DETERMINISM_OK`. Rød ⇒ STOP: forudsætningsleddet er ikke bevist på prods vej, og planen venter på en rettelse (egen PR).

- [ ] **Step 3: Værktøj og stand-in-grundlag**

`pg_dump --version` (17.x), lokal `server_version_num` (17xxxx), `fdesetup status` (On). Stand-in-grundlaget er `daa2018f_20261001133125` (= prods indhold efter 2026-10-05, spec §2): kør trin 4's digests og baselinen mod den læse-kun og sammenlign med Konstanterne.

Forventet: de tre digests og `canonical_sha256` som i tabellen. Afviger de, er basen ikke en gyldig stand-in: STOP og spørg (alternativet er en restore af `daa-prod-20261005102433.dump`, som er taget før trin 4's data).

---

### Task 1: Katalog- og ACL-fingeraftryk (repo)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_catalog_fingerprint.sql`
- Create: `.claude/skills/daa-extract/scripts/transfer_acl_fingerprint.sql`
- Create: `tests/sql/test-transfer-5ab-ddl.sh` (fingeraftryksdelen; Task 3 udvider)

**Interfaces:**
- Produces: begge SQL-filer kører læse-kun med `psql -X -Atq -f <fil>`, sætter selv `search_path TO pg_catalog` og `TimeZone='UTC'` lokalt i en `BEGIN READ ONLY … COMMIT`, og printer **linjer** sorteret `COLLATE "C"`. Med `-v mode=digest` printer de i stedet én linje: `sha256` (hex) over linjerne forbundet med `\n`.
- Katalogets linjeformat: `<art>|<identitet>|<md5>` med arterne `r` (relation: `relkind`, `relpersistence`), `c` (kolonne: `schema.tabel.kolonne`, `format_type`, `attnotnull`, `attidentity`, `attgenerated`, md5 af default), `k` (constraint: `schema.tabel.navn`, md5 af `pg_get_constraintdef`), `i` (indeks, md5 af `indexdef`), `f` (funktion/procedure: `regprocedure`, md5 af `pg_get_functiondef`), `v` (view/matview, md5 af `pg_get_viewdef`), `t` (trigger: `schema.tabel.navn`, `tgenabled`, md5 af `pg_get_triggerdef`), `p` (policy: `schema.tabel.navn`, `polcmd`, `polpermissive`, roller sorteret, md5 af `qual`/`with_check`), `s` (sekvens: type, increment, min, max, cycle; **ikke** `last_value`), `y` (type/enum: navn, enum-labels i rækkefølge). Kun skemaerne `public` og `private`; kun objekter, der ikke er ejet af en extension (`pg_depend.deptype='e'`).
- ACL-linjeformat: `g|<art t/s/f/n>|<modtager>|<objekt>|<privilegium>` (som trin 4's `GRANTS_LIST_SQL`, udvidet med `service_role` og skemaerne som art `n`), `d|<rolle>|<skema>|<objtype>|<modtager>|<privilegium>` fra `pg_default_acl` (aclexplode), `m|<rolle>|<regprocedure>|<0/1>` for `has_function_privilege(rolle, fn, 'EXECUTE')` over alle `public`-funktioner og rollerne `anon`, `authenticated`, `service_role` (`PUBLIC` dækkes af `g`-linjerne).

- [ ] **Step 1: Skriv testens fingeraftryksdel (fejler, filerne findes ikke)**

`tests/sql/test-transfer-5ab-ddl.sh <prefix>` bygger basen `<prefix>_p` som #251's opgraderingstest fra `b42266e` (bootstrap, `schema.sql`, `db-rls.sql`, `db-migrations.sql`, `db-rls.sql` fra træet). Supabases default privileges emuleres **før** byggeriet, så objekterne får dem som i prod:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
```

Påstande (hver giver `DDL_TEST_FAIL: <navn>` og exit 1):
- `fp_same_content`: `createdb -T <prefix>_p <prefix>_q` (andet navn) ⇒ katalog- og ACL-digest ens.
- `fp_function_body`: i `_q` ændres kroppen af én `private`-funktion med `CREATE OR REPLACE` ⇒ katalog-digest ændret, ACL-digest uændret.
- `fp_column`: `ALTER TABLE public.person ADD COLUMN t5ab_x int` ⇒ katalog-digest ændret.
- `fp_grant`: `GRANT SELECT ON private.source_persona TO anon` (som `db-rls.sql` har tilbagekaldt) ⇒ ACL-digest ændret, katalog-digest uændret.
- `fp_default_acl`: `ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT SELECT ON TABLES TO anon` ⇒ ACL-digest ændret.
- `fp_no_data`: `INSERT` af en række i `public.person` og `nextval` på en sekvens ⇒ begge digests uændrede.
- `fp_lines_digest`: `sha256` af linjerne (bash) = `-v mode=digest`-værdien.

- [ ] **Step 2: Kør og se den fejle**

Run: `bash tests/sql/test-transfer-5ab-ddl.sh t5ab > "$WS/t1.log" 2>&1; tail -3 "$WS/t1.log"`
Expected: fejl med psql `could not open file` / `DDL_TEST_FAIL`.

- [ ] **Step 3: Skriv de to SQL-filer efter Interfaces-blokken**

- [ ] **Step 4: Kør og se den bestå**

Expected: sidste linje `DDL_FINGERPRINT_OK`, `<prefix>_*` droppet.

- [ ] **Step 5: Commit** `test(151): katalog- og ACL-fingeraftryk til DDL-overførslen`

---

### Task 2: Afbrudsfiler og fortrydelsens DROP-liste (`transfer_ddl.py`)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_ddl.py`
- Create: `.claude/skills/daa-extract/scripts/test_transfer_ddl.py`
- Modify: `.github/workflows/ci.yml` (testen tilføjes pytest-listen i jobbet `python`)

**Interfaces:**
- `transfer_ddl.py prefix --migrations <sti> --point <punkt> --out <sti>`: skriver filens linjer 1..N, hvor N er den sidste linje i punktets markør. Punkterne og markørerne (præcis én forekomst kræves, ellers `PREFIX_MARKER`):
  - `after-153-commit`: første linje, der er præcis `COMMIT;`;
  - `in-5a-cutover`: linjen `-- END 5a-cutover`;
  - `before-rls`: hele filen (punktet ligger mellem filerne; `03`/testen springer `db-rls.sql` over).
  Udskriver `PREFIX_OK point=<p> lines=<N> sha256=<sha af outfilen>`.
- `transfer_ddl.py removal-sql --before <kataloglinjer> --after <kataloglinjer> --out <sti>`: objekter, hvis **identitet** (`art|identitet`, uden md5) findes i `after` men ikke i `before`. Kun arterne `r`, `v`, `f`, `s`, `y` giver en `DROP`; `c`, `k`, `i`, `t`, `p` på en **ny** relation følger med relationen og udelades; på en **eksisterende** relation udelades de også (de forsvinder, når `pg_restore --clean` genskaber relationen) men tælles i udskriften. Rækkefølge: views (`DROP VIEW|MATERIALIZED VIEW IF EXISTS … CASCADE`), funktioner (`DROP FUNCTION|PROCEDURE IF EXISTS <regprocedure> CASCADE`), tabeller (`DROP TABLE IF EXISTS … CASCADE`), sekvenser, typer; inden for en art sorteret `C`. Hele filen er `BEGIN; … COMMIT;`. En identitet, der ikke matcher `^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*(\(.*\))?$`, giver `REMOVAL_IDENTITY` (ingen fri tekst i genereret SQL). Udskriver `REMOVAL_OK drop=<n> skipped_existing=<m> sha256=<sha>`.

- [ ] **Step 1: Skriv enhedstestene (fejler, modulet findes ikke)**

`test_transfer_ddl.py` med:
- `test_prefix_after_153_commit_cuts_at_first_commit`: fil med `BEGIN;\nx;\nCOMMIT;\ny;\nCOMMIT;\n` ⇒ 3 linjer.
- `test_prefix_marker_must_be_unique`: to `-- END 5a-cutover` ⇒ `SystemExit("PREFIX_MARKER")`.
- `test_prefix_before_rls_is_whole_file`.
- `test_removal_new_table_drops_once_with_cascade`: `after` har `r|private.ny|…`, `c|private.ny.a|…`, `k|private.ny.fk|…` ⇒ præcis én `DROP TABLE IF EXISTS private.ny CASCADE;`.
- `test_removal_replaced_function_is_kept`: samme `f|private.g(integer)` med ny md5 ⇒ ingen DROP.
- `test_removal_new_overload_dropped`: `f|public.h(uuid,text)` ny, `f|public.h(uuid)` gammel ⇒ kun den nye droppes.
- `test_removal_column_on_existing_table_counted_not_dropped`: `c|public.person.ny_kol|…` ⇒ 0 DROP, `skipped_existing=1`.
- `test_removal_trigger_on_existing_table_with_new_function`: ny `f|private.trg_fn()` + ny `t|public.person.trg|…` ⇒ `DROP FUNCTION … CASCADE` og `skipped_existing=1`.
- `test_removal_order_views_functions_tables`.
- `test_removal_rejects_odd_identity`: `r|private.x; DROP|…` ⇒ `SystemExit("REMOVAL_IDENTITY")`.
- `test_removal_wrapped_in_one_transaction`.

- [ ] **Step 2: Kør og se dem fejle**

Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_transfer_ddl.py -q`
Expected: `ModuleNotFoundError` / 11 fejl.

- [ ] **Step 3: Implementér `transfer_ddl.py` efter Interfaces (stdlib alene, `raise SystemExit("KODE")`)**

- [ ] **Step 4: Kør og se dem bestå; tilføj filen til `python`-jobbets pytest-liste**

Expected: `11 passed`.

- [ ] **Step 5: Commit** `feat(151): afbrudsfiler og fortrydelsens DROP-liste til DDL-overførslen`

---

### Task 3: Integration fra prods træ: idempotens, afbrud, åbne rettigheder, DROP-listen

**Files:**
- Modify: `tests/sql/test-transfer-5ab-ddl.sh`
- Modify: `.github/workflows/ci.yml` (jobbet `writer-1939-v50-db`, samme trin som `test-indholds-id-determinism.sh`: `bash tests/sql/test-transfer-5ab-ddl.sh ci_ddl`)

**Interfaces:**
- Consumes: Task 1's to SQL-filer; Task 2's `prefix` og `removal-sql`.
- Produces: `DDL_REHEARSAL_SYNTH_OK` som testens sidste linje. Apply-proceduren i testen er bogstaveligt den, `step_ddl` bruger (Task 4): `psql -X -q -v ON_ERROR_STOP=1 -f db-migrations.sql`, `psql … --single-transaction -f db-rls.sql`, `psql … -c "NOTIFY pgrst, 'reload schema'"`.

- [ ] **Step 1: Skriv integrationspåstandene (fejler, fordi testen endnu kun har Task 1's del)**

Med `_p` fra Task 1 som skabelon (`createdb -T`):
- `full_apply`: `_u` får fuld apply ⇒ katalog `F1`, ACL `A1`; apply igen ⇒ `F1`/`A1` (`IDEMPOTENT`).
- `interrupt_<punkt>` for de tre punkter: `_i<n>` får prefix-filen (for `before-rls` hele migrationsfilen og ingen `db-rls.sql`), måler ved afbruddet `has_schema_privilege(r,'private','USAGE')` for `anon` og `authenticated` (skal være falsk) og antallet af private tabeller med `relrowsecurity=false` (rapporteres), får derefter fuld apply ⇒ `F1`/`A1`.
- `no_data_change`: trin 4's tre digests og `transfer_untouched_hash.sql` er ens i `_p` og `_u` (I8; syntetisk base har 0 rækker, så påstanden er strukturel).
- `removal_restores_identity_set`: `removal-sql --before <_p's linjer> --after <_u's linjer>` køres i `_u` (rc 0); derefter er mængden af identiteter (`art|identitet`) i `_u` lig `_p`'s, bortset fra `c`/`k`/`i`/`t`/`p` på eksisterende relationer, som skal være præcis `skipped_existing` stk. Listen skal indeholde `r|private.identity_control_run` og `f|public.red_register_identity_control_run(uuid,text)` (vagter mod en tom liste).
- `db_verify`: `db-verify.sql` grøn i `_u` (sidst; den seeder).

- [ ] **Step 2: Kør og se den fejle**

Run: `bash tests/sql/test-transfer-5ab-ddl.sh t5ab > "$WS/t3.log" 2>&1; tail -3 "$WS/t3.log"`
Expected: `DDL_TEST_FAIL: <første manglende påstand>`.

- [ ] **Step 3: Implementér påstandene; tilføj CI-linjen**

- [ ] **Step 4: Kør og se den bestå; kør derefter hele jobbene `python` og `writer-1939-v50-db` med den lokale runner**

Expected: `DDL_REHEARSAL_SYNTH_OK`; begge jobs grønne. Varigheden noteres (CI-minutbudget).

- [ ] **Step 5: Commit** `test(151): DDL-overførslen fra prods træ: afbrud, åbne rettigheder og DROP-listen`

---

### Task 4: Privat lib, skrivepause og fase 0 (`01-preflight.sh`)

**Files:** private: `lib.zsh`, `koer.zsh`, `00-freeze.sh`, `01-preflight.sh`, `rollback-preflight.sql`.

**Interfaces:**
- `lib.zsh` (kopi af trin 4's, renset for data-skridt) tilføjer:
  - `measure_fingerprints <runmappe> <præfiks>` → `<præfiks>-catalog.txt`, `<præfiks>-acl.txt` (0600) og `REPLY="<katalog-sha>|<acl-sha>"`, via Task 1's filer.
  - `emulate_default_acl <preflight.json>` (kun lokalt): for hver `d`-linje i preflightens ACL-liste, hvis rolle er prods DDL-rolle (`DAA_PROD_DDL_ROLE`, målt i fase 0 som `current_user`), udstedes `ALTER DEFAULT PRIVILEGES FOR ROLE current_user IN SCHEMA <skema> GRANT <priv> ON <objtype> TO <modtager>`. Rollenavne og privilegier valideres mod en fast liste; andet ⇒ `DEFAULT_ACL_LINE`.
  - `use_local_database` og `setup_connection` accepterer kun Global Constraints' basenavne.
- `01-preflight.sh` (læse-kun, ingen argumenter) → `preflight.json` med `status: PREFLIGHT_OK`. Gates i rækkefølge (stopkode i parentes):
  1. mål = `DAA_PROD_TARGET` i prod / ≠ i stand-in (`TARGET`);
  2. trin 4's tre digests og tal = Konstanterne (`TRANSFER_DRIFT`);
  3. 0 `change_set` med `created_at > '2026-10-05T11:03:06Z'` (`CHANGE_SINCE_TRANSFER`); i stand-in-tilstand: 0 efter basens oprettelse;
  4. driftsbaselinen = Konstanterne (`SCHEMA_DRIFT` / `CANONICAL_DRIFT` / `CLAUSE_SET_DRIFT`);
  5. ingen 5a/5b-tabeller: `to_regclass` er NULL for de 11 tabeller i `db-rls.sql`'s liste fra `source_persona_identity_candidate_run` til `relation_classification_event`, og for alle `r`-identiteter i Task 3's syntetiske DROP-liste (listen gemmes som `expected-new-relations.txt` i Task 4 Step 2) (`DDL_ALREADY_PRESENT`);
  6. `server_version_num ≥ 150000`, `private.narrative_record_contract_version() = 2`, 587 accepterede 149b-identiteter, præcis én redaktionsprofil med `actor_sha256` = Konstanten, `public.family.id` har `attidentity IN ('a','d')` (`PREMISE_<navn>`);
  7. locale: `datcollate`, `datctype`, `datlocprovider` og `chars_json`-hashen gemmes; i prod skal de være lig trin 4's preflight 2026-10-05 (`~/.private/2018-20-overfoersel/prod/`, filen findes i Task 4 Step 1) (`LOCALE_DRIFT`);
  8. `measure_fingerprints` (katalog, ACL) og `transfer_restore_hash.sql`, `transfer_untouched_hash.sql` gemmes; `current_user` gemmes som `ddl_role`.
- `00-freeze.sh begin|end`: som trin 4; `end` accepterer i plan A kun `--efter-fortrydelse` med `undo-ok.json` fra `09-undo-ddl.sh` (plan B tilføjer `--efter-verify`).

- [ ] **Step 1: Find trin 4's prod-preflight og noter dens locale- og tegnfelter (kun hashes)**

- [ ] **Step 2: Byg en stand-in**: `createdb -T daa2018f_20261001133125 daa5ab_ddl_standin_<UTC14>` og kør `01` mod den (`DAA_STANDIN_DB=…`). Forinden skrives `r`-identiteterne fra Task 3's syntetiske DROP-liste (kør `test-transfer-5ab-ddl.sh` med `KEEP_REMOVAL=<sti>`, som gemmer listen) til `~/.private/5ab-overfoersel/expected-new-relations.txt`; filen kommer i GO 1-inventaret.

Expected: `PREFLIGHT_OK`; gate 7's prod-sammenligning springes kun over i stand-in-tilstand og står som `locale_compared: false` i rapporten.

- [ ] **Step 3: Negativtests mod en kopi af stand-in'en (hver forventet STOP med koden)**

En `change_set`-række efter basens oprettelse ⇒ `CHANGE_SINCE_TRANSFER`; `CREATE TABLE private.interpretation_party(x int)` ⇒ `DDL_ALREADY_PRESENT`; én ændret `assertion.vaerdi_tekst` ⇒ `CANONICAL_DRIFT`; `DAA_FAULT=x` uden `DAA_STANDIN_DB` ⇒ `FAULT_IN_PROD` før forbindelse; et ukendt argument ⇒ exit 2.

- [ ] **Step 4: Ledger-linje** (privat kode committes ikke).

---

### Task 5: Dump og DDL-rehearsal (`02-dump.sh`, `03-rehearsal-ddl.sh`)

**Files:** private: `02-dump.sh`, `03-rehearsal-ddl.sh`, lib-funktionerne `step_ddl`, `undo_ddl`, `ddl_state`.

**Interfaces:**
- `step_ddl <runmappe>` (lib): fra `cd "$DAA_REPO"` apply-proceduren (Task 3 Produces), stderr til 0600-filer, `WARNING`-linjer skal være 0, `DAA_FAULT=ddl:after_migrations` / `ddl:in_5a_cutover` (kun lokalt) afbryder efter migrationerne / kører kun prefix-filen og returnerer `FAULT_INJECTED`.
- `ddl_state <preflight.json> <rehearsal-ddl.json>` → `PRE` (katalog = preflightens), `POST` (katalog og ACL = rehearsalens efter-fingeraftryk), `PARTIAL` (alt andet).
- `undo_ddl <runmappe> <dump> <preflight.json> <rehearsal-ddl.json>`: (a) aktuelt katalog måles; `removal-sql --before <preflightens katalog> --after <aktuelt>`; hver identitet i listen skal findes i rehearsalens fulde liste (`UNDO_LIST_UNEXPECTED`); kør som én transaktion; (b) `undo_restore` (trin 4's kommando); (c) `reconcile_grants` mod preflightens grant-linjer; (d) `NOTIFY pgrst, 'reload schema'`; (e) fejllistens hash + antal; restore-hash, katalog- og ACL-fingeraftryk = preflightens ⇒ `REPLY=UNDO_OK`, ellers `UNDO_<felt>_DRIFT`.
- `02-dump.sh d0|d1`: gates som trin 4 (`assert_freeze_active`; `d0` kræver `PREFLIGHT_OK` fra samme pause og `ddl_state = PRE`; `d1` kræver `DDL_VERIFY_OK` fra samme pause og `ddl_state = POST`). `pg_dump -Fc --no-owner` (læse-kun, med ACL'er). Restoreverifikation: restore til `daa5ab_ddl_<d0|d1>check_<UTC14>`; restore-hash og katalog-fingeraftryk skal være prods, målt straks efter dumpet; ACL-afvigelsen mellem prod og restoren gemmes som linjediff-antal (forventet 0 for objekt-grants; default-ACL'er findes ikke i restoren og sammenlignes ikke) (`RESTORE_FINGERPRINT_DRIFT`). Kvittering `daa-prod-<stamp>.dump.receipt.json` med dump-sha, start, restore-, uberørt-, katalog- og ACL-hash.
- `03-rehearsal-ddl.sh` (lokal; kræver D0-kvittering og preflight) → `rehearsal-ddl.json` med `status: REHEARSAL_OK`, og `go-hashes.txt`:
  - **R1** restore D0 → `…_a`; ACL-fingeraftryk = preflightens objekt-grants; `emulate_default_acl`; `step_ddl` ⇒ efter-fingeraftryk `F1`/`A1`, varighed; `step_ddl` igen ⇒ `F1`/`A1`; I8-målingerne uændrede; `db-verify.sql` grøn i en `createdb -T`-kopi (`…_v`), aldrig i `…_a`.
  - **R2** for hvert af de tre punkter: frisk restore → `…_i<n>` + emulering; prefix (eller `DAA_FAULT`); `anon`/`authenticated` uden `USAGE` på `private`; fuld `step_ddl` ⇒ `F1`/`A1`.
  - **R3** på `…_a`: `undo_ddl` mod D0 ⇒ `UNDO_OK`; listen (antal, sha) og fejllistens hash gemmes.
  - Rapporten binder: D0-sha og kvittering, preflight-sha, commit, sha for `db-migrations.sql`/`db-rls.sql`, `F1`, `A1`, varigheder, listens sha og antal, fejllistens hash, GO-hashfilens sha.

- [ ] **Step 1: Kør `02 d0` mod stand-in'en.** Expected: `DUMP_OK` og `DUMP_VERIFIED`.
- [ ] **Step 2: Negativtest af restoreverifikationen:** en grant ændret i stand-in'en efter dumpet (før målingen) ⇒ `RESTORE_FINGERPRINT_DRIFT`.
- [ ] **Step 3: Kør `03-rehearsal-ddl.sh`.** Expected: `REHEARSAL_OK`; tre afbrud ender i `F1`/`A1`; `db-verify` grøn.
- [ ] **Step 4: Fortrydelsens efterkrav brydes bevidst:** en ekstra tabel i `private` efter apply, som ikke er i rehearsalens liste ⇒ `UNDO_LIST_UNEXPECTED`; en grant til `anon` tilføjet efter restoren og før målingen fjernes af `reconcile_grants` (antal 1 i udskriften).
- [ ] **Step 5: Ledger-linje** med varigheder (restore, apply, undo).

---

### Task 6: Prod-scripts mod stand-in, fejlinjektion og angrebstests

**Files:** private: `04-ddl.sh`, `05-probe-ddl.sh`, `09-undo-ddl.sh`.

**Interfaces:**
- `04-ddl.sh --jeg-mener-det`: I3 (GO-hashes, rent repo, commit) → bundne rapporter (preflight, D0-kvittering, rehearsal; deres sha i miljøet som trin 4's `go-env.txt`) → `open_connection` → mål → pause aktiv fra før D0 → `NO_WRITE_SINCE_DUMP` → `ddl_state`: `PRE` ⇒ gate-markør skrives, `step_ddl`; `POST` ⇒ `ALREADY_APPLIED` (exit 0); `PARTIAL` ⇒ kun med `DAA_DDL_GENKOERSEL=ja` + gate-markøren fra samme pause, ellers STOP → efter apply: katalog/ACL = `F1`/`A1`, I8 uændret → `ddl.json` (`DDL_OK`). Sidste linje beder projektejeren køre `get_advisors(security)`.
- `05-probe-ddl.sh` (læse-kun, kan køres igen): `ddl_state = POST`; privilegiematrixen (`m`-linjerne) = rehearsalens; `anon` ser 0 rækker i de private tabeller (`ANON_PRIVATE_SQL` fra trin 4, udvidet med de nye tabeller); `advisors-after.txt` (projektejerens) har kun lint-navne, der også står i `advisors-before.txt`, eller som rehearsalen listede som forventede (`ADVISORS_NEW`) → `ddl-verify.json` (`DDL_VERIFY_OK`).
- `09-undo-ddl.sh --jeg-mener-det`: I3 + bundne rapporter → `undo_ddl` mod D0 → `undo-ok.json` (`UNDO_OK`). Kan køres igen efter et afbrud.

- [ ] **Step 1: Hele vejen mod en frisk stand-in:** `00 begin` → `01` → `02 d0` → `03` → `04` → `05` → `02 d1`. Expected: `PREFLIGHT_OK`, `DUMP_VERIFIED`, `REHEARSAL_OK`, `DDL_OK`, `DDL_VERIFY_OK`, `DUMP_VERIFIED` (d1).
- [ ] **Step 2: Genkørsel:** `04` igen ⇒ `ALREADY_APPLIED`, `ddl.json` byte-uændret.
- [ ] **Step 3: Fejlinjektion** på en anden frisk stand-in: `DAA_FAULT=ddl:after_migrations` ⇒ `FAULT_INJECTED`; `04` uden genkørselsflag ⇒ STOP (`PARTIAL`); med `DAA_DDL_GENKOERSEL=ja` ⇒ `DDL_OK` med `F1`/`A1`. Samme for `ddl:in_5a_cutover`.
- [ ] **Step 4: Angrebstests** (hver navngivet STOP før skrivning, intet ændret): forkert `DAA_EXPECTED_COMMIT`; snavset inventarfil; en linje for meget/for lidt i GO-hashfilen; manglende `--jeg-mener-det`; ukendt argument; `PGHOSTADDR`/`PGOPTIONS` arvet; `DAA_STANDIN_DB` + prod-`DAA_EXPECTED_TARGET`; en `change_set`-række efter D0 (`NO_WRITE_SINCE_DUMP`); stand-in med en ekstra default-ACL efter preflight (Review Focus 1) ⇒ `04` STOP på ACL før apply. Kør med en `HOME`, hvis `.Renviron` peger på `127.0.0.1:1`, så intet kan nå prod.
- [ ] **Step 5: Fortrydelse mod stand-in'en fra Step 1:** `09` ⇒ `UNDO_OK`; `00 end --efter-fortrydelse` ⇒ `FREEZE_END_OK`.
- [ ] **Step 6: Ledger-linje** med alle stopkoder set.

---

### Task 7: Runbook, beslutninger og status

**Files:**
- Create: `docs/runbooks/transfer-5ab-ddl-prod.md`
- Modify: `docs/decisions.md`, `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md`, `docs/README.md` (runbook-link)

- [ ] **Step 1: Runbook** i trin 4-runbookens form: forudsætninger, kommandoerne i rækkefølge med forventet udskrift, GO 1-pakken (eksakt inventar og `go-env.txt`), stopregler pr. stopkode, genkørsel efter afbrud, fortrydelse (`09`), og overgangen til plan B (D1-kvitteringen, pausen fortsætter).
- [ ] **Step 2: `decisions.md`:** ny post »BESLUTTET 2026-10-21: 5a's 31 kalibreringsafgørelser overføres ikke« med baggrund (5a ikke i kæden, base droppet, `~/.private/5a/` bevares), konsekvens (149b-koblingerne uændrede i prod; identitetsvejen bevises af 5b's afgørelser; `web_detail` ubrugt i prod) og planens errata-tabel i kort form. Ingen udgavenavne i nye permanente overflader.
- [ ] **Step 3: `status.md` og `changelog.md`:** én linje: plan A for 5a+5b-overførslen bygget og øvet på stand-in (`REHEARSAL_OK` DDL); prod uændret; næste skridt er fase 0 og GO 1.
- [ ] **Step 4: Commit** `docs(151): runbook for DDL-ceremonien og beslutning om 5a's kalibreringsafgørelser`

---

## Efter planen (ikke en del af den)

1. Push og draft-PR (projektejerens ja); CI kører på PR'en.
2. Projektejeren: fase 0 i prod (`00 begin`, `01`, `02 d0`), lokal `03` på netop det dump, `get_advisors` → GO 1 → `04` → `get_advisors` → `05` → `02 d1`.
3. Plan B skrives mod D1.
4. Oprydning af stand-in-, rehearsal- og check-baser: kun efter måling og ja.

## Ændringslog

- 2026-10-21: skrevet. Projektejerens valg samme dag: 5a's kalibreringsafgørelser overføres ikke (errata-tabellen).
