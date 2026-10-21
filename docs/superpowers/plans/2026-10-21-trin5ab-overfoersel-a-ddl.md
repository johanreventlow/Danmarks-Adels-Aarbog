# Overførsel af 5a + 5b (2018-20) — plan A: fase 0 og DDL-ceremonien (GO 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (**native**) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent-drevet udførelse er udelukket for Task 0 og 4-7: scriptene ligger i `~/.private/`, og testene rører restores med persondata. Task 1-3 (repo-filer, syntetiske baser) må gives til en subagent, men aldrig med adgang til `~/.private/`, `work*/` eller en restore.

**Goal:** Byg og øv den fail-closed DDL-ceremoni, der deployer 5a+5b's DDL i prod (spec §5, §6.1, §8 GO 1 og DDL-fortrydelsen). Planen er færdig ved `REHEARSAL_OK (DDL)` på en lokal stand-in af prod, inklusive afbruds- og fortrydelsesøvelse, grønne repo-tests i CI og en committed runbook. Selve kørslen i prod (fase 0 → D0 → GO 1 → DDL → probe → D1) er projektejerens bagefter.

**Architecture:** Formen er trin 4's ceremoni (`~/.private/2018-20-overfoersel/`) og omsegmenteringens DDL-script (`~/.private/omseg-prod/04-ddl.sh`). En ny privat mappe `~/.private/5ab-overfoersel/` med én `lib.zsh` og små zsh-scripts. Hver skrivende eller målende handling er én lib-funktion, som rehearsal kalder lokalt og prod-scriptene kalder mod prod (samme bytes). De to nye målinger (katalog- og ACL-fingeraftryk) og fortrydelsens objektliste er **repo-filer** med CI-tests, så plan B og GO 1 binder de samme bytes. Plan B (datadelen: nøglede digests, svaroverførsel, pakke, genspil, GO 2) skrives, når D1 findes, og bygger videre i samme private mappe.

**Tech Stack:** zsh (`/bin/zsh -f`), psql/pg_dump/pg_restore 17 (`/opt/homebrew/opt/postgresql@17/bin`), Python 3 (`/usr/bin/python3 -I`), bash-testscripts mod PostgreSQL 17 (lokalt og CI-jobbet `writer-1939-v50-db`), Supabase Session pooler.

**Spec:** `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (§2, §5, §6.1, §8, §9 DDL-delen, §10 DDL-delen). Forudsætningsleddet er merget (#251, `e8039c69`). Forlæg: `~/.private/2018-20-overfoersel/lib.zsh` (forbindelse, skrivepause, dump, `undo_restore`, `reconcile_grants`, `chars_json`, GO-inventar), `~/.private/omseg-prod/04-ddl.sh` + `lib.zsh` (`schema_fingerprint`, DDL-gaten, genkørsel), `docs/runbooks/transfer-2018-20-prod.md`.

## Roadmap-adgangskrav

Som spec §1. Plan A leverer DDL-halvdelen: efter projektejerens GO 1 har prod 5a/5b-DDL'en, og D1 findes som fortrydelsespunkt og udgangspunkt for plan B's arbejdskørsel. Ingen kildedata skrives (DDL'en tilføjer kun tre promotion-regler, I8). Rækken »Source persona, identitetskandidater og webkø« i `status.md` løftes først ved plan B's `VERIFY_OK`. **Repo-fodaftryk:** 3 SQL-filer, 1 Python-værktøj, 1 referencefil, 3 testfiler (2 i CI, 1 kun lokalt), én CI-linje i hvert af to jobs, runbook og docs.

## Global Constraints

- **Ingen prod fra AI-sessionen.** Prod rammes kun af projektejeren i egen shell: `! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh <script> …` (hukommelse »prod-skrivning-via-brugerens-shell«). Undtagelse: `get_advisors(security)` via Supabase-MCP, kun på projektejerens ja i samme tur; der skrives antal pr. (lint, objektnavn) ned (objektnavne er skemaobjekter, ikke persondata).
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
| §5/§7: »det kanoniske lag er lig rodbasens« | Gælder før DDL'en. DDL'en ændrer `interpretation_promotion_rule` (I8), så plan B's »kanonisk delta 0« måles mod D1's efter-DDL-baseline, ikke mod rodbasen. |
| §5, §6.1: ACL-fingeraftryk sammenlignes mellem prod og restore | Prod har objekter og default-ACL'er, en lokal restore ikke har (Supabase-skemaer, `FOR ROLE postgres`). Fingeraftrykkene deles i en portabel del (prod ↔ lokal) og en prod-lokal del (kun prod mod prod over tid). |
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
- **I8 DDL'en skriver kun forventede data.** DDL'en indsætter promotion-reglerne `relation-marriage-v1`/`relation-parent-v1`/`relation-child-v1` og tilføjer `rule_mode` med default til eksisterende regelrækker, så driftsbaselinens `canonical_sha256` og `transfer_untouched_hash.sql` **ændrer sig**. Kravet er: trin 4's tre digests uændrede; tabelhash-deltaet ligger inden for `references/transfer-5ab-ddl-allowed-data-delta.txt` (`DATA_DELTA_OK`); nye tabeller er tomme. Prod sammenlignes efter DDL'en med **D0** (sine egne før-målinger), ikke med rehearsalens tal: DDL-indsatte regelrækker får `created_at DEFAULT now()` (`schema.sql:1368`, `:1384`), og idempotente `INSERT … ON CONFLICT DO NOTHING` på identity-tabeller (`slaegt`, `lineage_scheme*`, `db-migrations.sql` ~l. 6755-6808) bruger sekvensværdier ved hver apply (efterprøvet 21/10). Derfor er `canonical_sha256`, `transfer_restore_hash.sql` og `transfer_untouched_hash.sql` efter DDL'en rene tilstandsfelter, der måles og bindes i D1-kvitteringen som plan B's udgangspunkt; de sammenlignes aldrig på tværs af baser.

## Review Focus

1. **Prods miljø har objekter, en lokal restore ikke har** (Supabase-skemaer som `auth`/`storage`/`realtime`, `pg_default_acl` `FOR ROLE postgres` og andre roller). Forventet: alle sammenligninger mellem prod og en lokal base bruger kun fingeraftrykkenes **portable** del; den **prod-lokale** del sammenlignes kun prod mod prod (preflight → før skrivning → efter skrivning → efter fortrydelse). Test: Task 6 Step 4 (stand-in, hvis "prod"-side har et ekstra skema og en default-ACL for en anden rolle: ceremonien går igennem, og den lokale del ændrer sig ikke over DDL'en).
2. **Forbindelsen dør midt i `db-migrations.sql` i prod.** Forventet: `04` med `DAA_DDL_GENKOERSEL=ja` gør det færdigt, og fingeraftrykkene bliver rehearsalens. Test: Task 3 (fire afbrudspunkter) og Task 6 Step 3 (`DAA_FAULT=ddl:after_migrations` og `ddl:in_5a_cutover` mod stand-in).
3. **Åbne rettigheder i afbrudsvinduet.** Migrationsfilen kører sætning for sætning. Med Supabases default privileges får en ny `public`-funktion `EXECUTE` til `anon`/`authenticated` ved `CREATE`, og `REVOKE` kommer først i en senere sætning (fx `red_identity_candidate_input`, `db-migrations.sql` ~l. 18693) eller i `db-rls.sql`. Forventet: vinduet måles ved hvert afbrudspunkt (antal funktioner, som `anon` kan kalde, men som A1 ikke tillader) og lukkes af genkørslen; efter fuld apply er `m`-matrixen og `relrowsecurity` lig rehearsalens. Runbooken siger, at et afbrudt `04` skal køres igen straks eller fortrydes. Test: Task 3 (punkt 4 ligger netop i et sådant vindue).
4. **Fortrydelsens DROP-liste rammer for lidt eller for meget.** Nye funktioner bag triggere på eksisterende tabeller, nye kolonner på eksisterende tabeller, og objekter, som DDL'en selv **fjerner** (fx `red_source_persona_queue(text,bigint,uuid,integer)`, 5-arguments-`red_afgoer_source_persona`, constraints på `interpretation_promotion_rule`). Forventet: listen dropper kun nye objekter; `pg_restore --clean` genskaber de ændrede og de fjernede; efter fortrydelsen er portabel katalog/ACL, restore-hash og den prod-lokale del lig fase 0's. Test: Task 2 (enhedstests), Task 3 (`removed_by_ddl`) og Task 5 Step 3-4.
5. **Genkørsel af `04` efter commit** (projektejeren kører det to gange). Forventet: `ALREADY_APPLIED`, intet skrevet, `ddl.json` uændret. Test: Task 6 Step 2.

---

## Filoversigt

Repo (committes):

| Fil | Ansvar |
| --- | --- |
| `.claude/skills/daa-extract/scripts/transfer_catalog_fingerprint.sql` | Læse-kun katalogliste, delt i portabel del (`public`/`private`, restore-stabil) og prod-lokal del (andre skemaer, `storage`-politikker) |
| `.claude/skills/daa-extract/scripts/transfer_acl_fingerprint.sql` | Læse-kun ACL-liste, delt i portabel del (grants til `PUBLIC`/`anon`/`authenticated`/`service_role`, privilegiematrix) og prod-lokal del (`pg_default_acl`) |
| `.claude/skills/daa-extract/scripts/transfer_table_hashes.sql` | Læse-kun: én linje `schema.tabel=<sha256>` pr. tabel i `public`/`private` (rækker som `to_jsonb` sorteret på primærnøglen) — grundlaget for I8's tilladte delta |
| `.claude/skills/daa-extract/scripts/transfer_ddl.py` | `prefix` (afbrudsfil ved et navngivet punkt), `removal-sql` (fortrydelsens DROP-transaktion) og `data-delta` (I8) |
| `.claude/skills/daa-extract/scripts/test_transfer_ddl.py` | Enhedstests for `transfer_ddl.py` (pytest, CI-jobbet `python`) |
| `tests/sql/test-transfer-fingerprints.sh` | Fingeraftrykkenes følsomhed og stabilitet på frisk schema (CI-jobbet `writer-1939-v50-db`; billig) |
| `tests/sql/test-transfer-5ab-ddl-upgrade.sh` | Kun lokalt (som #251's opgraderingstest): fra `b42266e` med emulerede default privileges — idempotens, fire afbrudspunkter, åbne rettigheder, I8-delta, DROP-listen |
| `.github/workflows/ci.yml` | `test_transfer_ddl.py` i `python`; `test-transfer-fingerprints.sh` i `writer-1939-v50-db` |
| `docs/runbooks/transfer-5ab-ddl-prod.md` | Autoritativ DDL-ceremoni: kommandoer, GO 1-pakke, stopregler, fortrydelse |
| `docs/decisions.md`, `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md` | 5a-afgørelsen, errata, statuslinje |

Private (`~/.private/5ab-overfoersel/`, aldrig i git):

| Fil | Ansvar |
| --- | --- |
| `lib.zsh` | Kopi af trin 4's `lib.zsh` (forbindelse, pause, dump, `undo_restore`, `reconcile_grants`, `chars_json`, GO-inventar) + nye funktioner: `measure_fingerprints`, `measure_data`, `emulate_default_acl`, `step_ddl`, `undo_ddl`, `ddl_state`. Trin 4's data-funktioner (`step_decide`, `step_bind`, R-kald) fjernes |
| `koer.zsh` | Indgang; vælger prod eller stand-in og logger exitkode (som trin 4) |
| `00-freeze.sh` | `begin` / `end` (som trin 4; `end` kræver plan B's `verify-ok.json` eller `undo-ok.json`) |
| `01-preflight.sh` | Fase 0 (spec §5), læse-kun → `preflight.json` (`PREFLIGHT_OK`) |
| `02-dump.sh` | `d0` / `d1`: dump + restoreverifikation + kvittering |
| `03-rehearsal-ddl.sh` | Lokal: restore af D0, emulerede default privileges, apply ×2, `db-verify.sql`, fire afbrudsøvelser, fortrydelsesøvelse → `REHEARSAL_OK` (DDL) + GO-hashfil |
| `04-ddl.sh` | `--jeg-mener-det`: `step_ddl` mod prod → `ddl.json` (`DDL_OK`) |
| `05-probe-ddl.sh` | Læse-kun probe efter DDL → `ddl-verify.json` (`DDL_VERIFY_OK`) |
| `09-undo-ddl.sh` | `--jeg-mener-det`: `undo_ddl` mod prod → `undo-ok.json` (`UNDO_OK`) |
| `rollback-preflight.sql` | Kopieret fra trin 4 |
| `expected-new-relations.txt` | Task 3's nye relationer (fase 0's gate 5) |

### GO 1-inventar (eksakt mængde; endelig liste skrives i runbooken i Task 7)

- **Privat (11):** `lib.zsh`, `koer.zsh`, `00-freeze.sh`, `01-preflight.sh`, `02-dump.sh`, `03-rehearsal-ddl.sh`, `04-ddl.sh`, `05-probe-ddl.sh`, `09-undo-ddl.sh`, `rollback-preflight.sql`, `expected-new-relations.txt`.
- **Repo (12):** `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`, og under `.claude/skills/daa-extract/scripts/`: `transfer_catalog_fingerprint.sql`, `transfer_acl_fingerprint.sql`, `transfer_table_hashes.sql`, `transfer_ddl.py`, `transfer_restore_hash.sql`, `transfer_untouched_hash.sql`, `transfer_baseline.sql`, `interpretation_transfer_digests.sql`, `clause_evidence_target_identity.sql`.
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

- [ ] **Step 2: #251's opgraderingsprøve fra prods rigtige træ**

```bash
bash tests/sql/test-indholds-id-upgrade.sh t5ab_up b42266e > "$WS/up.log" 2>&1; tail -2 "$WS/up.log"
```

Forventet: `DETERMINISM_OK` og `UPGRADE_OK` (testen kalder selv determinismetesten med `upgrade:b42266e`). Rød ⇒ STOP: forudsætningsleddet er ikke bevist på prods vej, og planen venter på en rettelse (egen PR).

- [ ] **Step 3: Værktøj og stand-in-grundlag**

`pg_dump --version` (17.x), lokal `server_version_num` (17xxxx), `fdesetup status` (On). Stand-in-grundlaget er `daa2018f_20261001133125` (= prods indhold efter 2026-10-05, spec §2): kør trin 4's digests (`-v src=1`) og baselinen mod den læse-kun og sammenlign med Konstanterne.

Forventet: de tre digests samt `schema_sha256`, `canonical_sha256` og `clause_set_sha256` som i tabellen. Prøv desuden check-restorens kommando (Task 5) på `daa-prod-20261005102433.dump` og noter fejllisten (forventet kun `supabase_vault` som i omsegmenteringen; FK'er til `auth.users`, fx `schema.sql:2738`, skal genskabes, ellers mangler `k`-linjer: STOP og ret auth-shimmen). Afviger de, er basen ikke en gyldig stand-in: STOP og spørg (alternativet er en restore af `daa-prod-20261005102433.dump`, som er taget før trin 4's data).

---

### Task 1: Fingeraftryk og tabelhashes (repo)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_catalog_fingerprint.sql`
- Create: `.claude/skills/daa-extract/scripts/transfer_acl_fingerprint.sql`
- Create: `.claude/skills/daa-extract/scripts/transfer_table_hashes.sql`
- Create: `tests/sql/test-transfer-fingerprints.sh`
- Modify: `.github/workflows/ci.yml` (`bash tests/sql/test-transfer-fingerprints.sh ci_fp` i `writer-1939-v50-db`, samme trin som `test-indholds-id-determinism.sh`)

**Interfaces:**
- Alle tre filer kører med `psql -X -Atq -f <fil>`, åbner selv `BEGIN READ ONLY` og sætter lokalt `search_path TO pg_catalog` (også ved `regprocedure`-cast), `TimeZone='UTC'`, `DateStyle='ISO, YMD'`, `IntervalStyle='postgres'`, `extra_float_digits=1` og `row_security=off` som de eksisterende `transfer_*`-filer. Linjerne printes sorteret `COLLATE "C"` og bærer delen som første felt (`P|…` portabel, `L|…` prod-lokal), så `p`-linjer kan forekomme i begge dele. Med `-v mode=digest` printer fingeraftryksfilerne i stedet præcis to linjer: `portable <sha256>` og `local <sha256>` (sha over delens linjer forbundet med `\n`; tom del ⇒ sha af tom streng).
- **Katalog, portabel del** (linjer `<art>|<identitet>|<md5>`), kun `public`/`private` og kun objekter, der ikke er ejet af en extension (`pg_depend.deptype='e'`):
  - `r` relation med `relkind IN ('r','p')`: `relpersistence`, `relrowsecurity`, `relforcerowsecurity`;
  - `v` view/matview: md5 af `pg_get_viewdef` + `reloptions` (fx `security_invoker`);
  - `c` kolonne `schema.tabel.kolonne`: `format_type`, `attnotnull`, `attidentity`, `attgenerated`, md5 af default;
  - `k` constraint `schema.tabel.navn`: md5 af `pg_get_constraintdef`;
  - `i` indeks: md5 af `indexdef`;
  - `f` funktion/procedure (`regprocedure`): md5 af `pg_get_functiondef`;
  - `t` trigger `schema.tabel.navn`: `tgenabled`, md5 af `pg_get_triggerdef`;
  - `p` policy `schema.tabel.navn`: `polcmd`, `polpermissive`, roller sorteret, md5 af `qual`/`with_check`;
  - `s` sekvens: type, increment, min, max, cycle, `owned` (0/1: ejet af en kolonne via `pg_depend.deptype IN ('a','i')`); aldrig `last_value`;
  - `y` brugerdefineret type (`typtype IN ('e','d','c')` og ikke en relations rækketype, ingen arraytyper): navn, enum-labels i rækkefølge / domænets basetype og constraints.
- **Katalog, prod-lokal del:** `n|<skema>|<antal relationer>|<antal funktioner>|<md5 af deres navne>` pr. andet skema end `public`, `private`, `pg_*` og `information_schema`; `p`-linjer for politikker på `storage.objects`.
- **ACL, portabel del:** `g|<art t/s/f/n>|<modtager>|<objekt>|<privilegium>` for modtagerne `PUBLIC`, `anon`, `authenticated`, `service_role` på objekter og skemaerne `public`/`private` (art `n`); `m|<rolle>|<regprocedure>|<0/1>` for `has_function_privilege(rolle, fn, 'EXECUTE')` over alle `public`-funktioner og rollerne `anon`, `authenticated`, `service_role`. Ingen grantor, ingen ejer.
- **ACL, prod-lokal del:** `d|<rolle>|<skema>|<objtype>|<modtager>|<privilegium>` fra `pg_default_acl`.
- `transfer_table_hashes.sql`: `schema.tabel=<sha256>` for hver tabel (`relkind IN ('r','p')`) i `public`/`private`, rækker som `to_jsonb(t)::text` sorteret `COLLATE "C"` på hele teksten (aldrig på tekstnøgler i lokalets orden). Med `-v omit=created_at` udelades nøglen `created_at` fra hver række (`to_jsonb(t) - 'created_at'`); I8's allow-listede tabeller sammenlignes kun sådan.

- [ ] **Step 1: Skriv testen (fejler, filerne findes ikke)**

`tests/sql/test-transfer-fingerprints.sh <prefix>` bygger to **uafhængige** baser `<prefix>_a` og `<prefix>_b` fra HEAD (bootstrap, `schema.sql`, `db-rls.sql`) med Supabases default privileges emuleret før byggeriet:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
```

Påstande (hver giver `FP_TEST_FAIL: <navn>` og exit 1):
- `fp_same_content`: `_a` og `_b` (forskellige oid'er og navne) har ens portable digests og ens tabelhashes.
- `fp_function_body`: `CREATE OR REPLACE` af én `private`-funktion med ændret krop i `_b` ⇒ portabel katalog-digest ændret, ACL-digests uændrede.
- `fp_column`: `ALTER TABLE public.person ADD COLUMN t5ab_x int` ⇒ portabel katalog-digest ændret.
- `fp_rls`: `ALTER TABLE private.source_persona DISABLE ROW LEVEL SECURITY` ⇒ portabel katalog-digest ændret.
- `fp_view_option`: `ALTER VIEW` af et view med `security_invoker` til `security_invoker=false` ⇒ portabel katalog-digest ændret.
- `fp_grant`: `GRANT SELECT ON private.source_persona TO anon` ⇒ portabel ACL-digest ændret, katalog uændret.
- `fp_service_role`: `GRANT EXECUTE` på en `private`-funktion til `service_role` ⇒ portabel ACL-digest ændret.
- `fp_default_acl_is_local`: `ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT SELECT ON TABLES TO anon` ⇒ lokal ACL-digest ændret, portabel uændret.
- `fp_other_schema_is_local`: `CREATE SCHEMA t5ab_x; CREATE TABLE t5ab_x.t(i int)` ⇒ lokal katalog-digest ændret, portabel uændret.
- `fp_no_data`: en række i `public.person` og `nextval` ⇒ fingeraftrykkene uændrede; tabelhashen for `public.person` ændret, alle andre uændrede.
- `fp_lines_digest`: bash' `sha256` af delens linjer = `-v mode=digest`-værdien.

- [ ] **Step 2: Kør og se den fejle**

Run: `bash tests/sql/test-transfer-fingerprints.sh t5ab_fp > "$WS/t1.log" 2>&1; tail -3 "$WS/t1.log"`
Expected: psql `could not open file` / `FP_TEST_FAIL`.

- [ ] **Step 3: Skriv de tre SQL-filer efter Interfaces og tilføj CI-linjen**

- [ ] **Step 4: Kør og se den bestå**

Expected: sidste linje `FP_OK`; baserne droppet.

- [ ] **Step 5: Commit** `test(151): portable og prod-lokale fingeraftryk og tabelhashes til DDL-overførslen`

---

### Task 2: `transfer_ddl.py`: afbrudsfiler, DROP-liste og datadelta

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_ddl.py`
- Create: `.claude/skills/daa-extract/scripts/test_transfer_ddl.py`
- Modify: `.github/workflows/ci.yml` (testen tilføjes pytest-listen i jobbet `python`)

**Interfaces:**
- `prefix --migrations <sti> --point <punkt> --out <sti>`: skriver linjerne 1..N; N er markørlinjen. Markøren skal forekomme **præcis én gang**, ellers `PREFIX_MARKER`:
  - `after-153-commit`: linjen `COMMIT;`;
  - `in-5a-cutover`: linjen `-- END 5a-cutover`;
  - `in-function-window`: linjen `REVOKE ALL ON FUNCTION red_identity_candidate_input(bigint,jsonb) FROM PUBLIC,anon,authenticated;` minus én (funktionen er oprettet, `REVOKE` ikke kørt);
  - `before-rls`: hele filen (punktet ligger mellem filerne; kalderen springer `db-rls.sql` over).
  Udskriver `PREFIX_OK point=<p> lines=<N> sha256=<sha>`.
- `removal-sql --before <kataloglinjer> --after <kataloglinjer> --out <sti>`: kun den portable del bruges. Nye identiteter (`art|identitet`, uden md5, i `after` men ikke i `before`) af arterne `r`, `v`, `f`, `s`, `y` giver `DROP … IF EXISTS … CASCADE` i rækkefølgen views, funktioner/procedurer, tabeller, sekvenser, typer (inden for en art sorteret `C`). `c`/`k`/`i`/`t`/`p` på en ny relation følger med den; på en eksisterende relation udelades de og tælles som `skipped_existing`. Identiteter i `before` men ikke i `after` tælles som `removed_by_ddl` (genskabes af restoren). En ny sekvens, der er ejet af en kolonne (kataloglinjens `s`-felt `owned=1`, dvs. `pg_depend.deptype IN ('a','i')`; fx `public.family_id_seq`, som DDL'en skaber ved at gøre `family.id` til identity, `db-migrations.sql` ~l. 21962), droppes ikke (PG afviser det, også med `CASCADE`; efterprøvet 21/10) men tælles som `skipped_existing`; restoren af tabellen fjerner den. Identiteten skal matche `^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*(\([a-z0-9_ ,."\[\]]*\))?$`, ellers `REMOVAL_IDENTITY`. Filen er `BEGIN; … COMMIT;`. Udskriver `REMOVAL_OK drop=<n> skipped_existing=<m> removed_by_ddl=<k> sha256=<sha>`.
- `data-delta --before <tabelhashes> --after <tabelhashes> --allow <fil>`: tabeller med ændret hash eller kun i `before` skal stå i `--allow` (én `schema.tabel` pr. linje); tabeller kun i `after` (nye) er tilladt, hvis de er tomme i `after` (hash = tom-tabel-hashen fra filen). Ellers `DATA_DELTA_UNEXPECTED`. Udskriver `DATA_DELTA_OK changed=<n> new=<m>`.

- [ ] **Step 1: Skriv enhedstestene (fejler, modulet findes ikke)**

- `test_prefix_cuts_at_unique_commit`; `test_prefix_marker_must_be_unique` (to `COMMIT;` ⇒ `PREFIX_MARKER`); `test_prefix_function_window_is_line_before_revoke`; `test_prefix_before_rls_is_whole_file`.
- `test_removal_new_table_drops_once_with_cascade`; `test_removal_replaced_function_is_kept`; `test_removal_new_overload_dropped`; `test_removal_column_on_existing_table_counted_not_dropped`; `test_removal_trigger_on_existing_table_with_new_function`; `test_removal_counts_removed_by_ddl`; `test_removal_ignores_local_part` (`n`-linjer i input ⇒ ingen DROP); `test_removal_order_views_functions_tables`; `test_removal_rejects_odd_identity` (`r|private.x; DROP|…` og `f|public.g(int); DROP x)` ⇒ `REMOVAL_IDENTITY`); `test_removal_wrapped_in_one_transaction`.
- `test_data_delta_allowed_change_ok`; `test_data_delta_unlisted_change_fails`; `test_data_delta_new_nonempty_table_fails`; `test_data_delta_dropped_table_must_be_allowed`.
- `test_prefix_in_5a_cutover`; `test_removal_skips_owned_sequence`; `test_removal_accepts_real_regprocedures` (`f|public.x(timestamp with time zone,text[],"char",character varying)`).

- [ ] **Step 2: Kør og se dem fejle**

Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_transfer_ddl.py -q`
Expected: `ModuleNotFoundError`.

- [ ] **Step 3: Implementér efter Interfaces (stdlib alene, `raise SystemExit("KODE")`)**

- [ ] **Step 4: Kør og se dem bestå; tilføj filen til `python`-jobbets pytest-liste**

Expected: `21 passed`.

- [ ] **Step 5: Commit** `feat(151): afbrudsfiler, DROP-liste og datadelta til DDL-overførslen`

---

### Task 3: Lokal integration fra prods træ (`test-transfer-5ab-ddl-upgrade.sh`)

**Ruling (Opus-review MINOR):** testen bygger fra `b42266e` og laver omkring 8 fulde applies. `b42266e` er kun prods træ indtil GO 1, så testen køres lokalt som #251's opgraderingstest, ikke i CI. Spec §9's »overførslens tests grønne i CI« dækkes af Task 1 og 2.

**Files:**
- Create: `tests/sql/test-transfer-5ab-ddl-upgrade.sh`
- Create: `.claude/skills/daa-extract/references/transfer-5ab-ddl-allowed-data-delta.txt` (I8's tilladte ændrede tabeller: `private.interpretation_promotion_rule` (`rule_mode`, ~l. 21320), `private.interpretation_promotion_rule_line` (nye regler, ~l. 21413, 23734), `private.interpretation_promotion_batch` (`ADD COLUMN items_sha256`, ~l. 21620; den syntetiske base er tom, så kun D0-rehearsalen viser den); hver linje med en kommentar om, hvilken migrationsblok der skriver den)

**Interfaces:**
- Consumes: Task 1's tre SQL-filer; Task 2's `prefix`, `removal-sql`, `data-delta`.
- Produces: `DDL_UPGRADE_SYNTH_OK` som sidste linje. Med `KEEP_REMOVAL=<sti>` skrives DROP-listens `r`-identiteter (sorteret `C`) til stien. Apply-proceduren er bogstaveligt `step_ddl`'s (Task 5): `PGOPTIONS='-c lock_timeout=10s'`, `psql -X -q -v ON_ERROR_STOP=1 -f db-migrations.sql`, `psql … --single-transaction -f db-rls.sql`, `psql … -c "NOTIFY pgrst, 'reload schema'"`.

- [ ] **Step 1: Skriv påstandene (fejler, scriptet findes ikke)**

`_p` bygges som #251's opgraderingstest fra `b42266e` med default privileges emuleret før byggeriet (Task 1's tre sætninger) og bruges som skabelon (`createdb -T`):
- `full_apply`: `_u` får fuld apply ⇒ portabel katalog `F1` og ACL `A1`; apply igen ⇒ `F1`/`A1` (`IDEMPOTENT`).
- `interrupt_<punkt>` for de fire punkter: `_i<n>` får prefix-filen (for `before-rls` hele migrationsfilen og ingen `db-rls.sql`). Ved afbruddet måles og rapporteres `open_exec` = antal `m|anon|…|1`-linjer, der ikke findes i `A1`, og antal private tabeller uden `relrowsecurity`. For `in-function-window` skal `open_exec ≥ 1` (vagt: punktet ligger reelt i et vindue). Derefter fuld apply ⇒ `F1`/`A1`.
- `rls_after_apply`: alle tabeller i `private` har `relrowsecurity` i `_u`.
- `data_delta`: trin 4's tre digests (`-v src=1`) er ens i `_p` og `_u`; `data-delta --before <_p> --after <_u> --allow <referencefilen>` ⇒ `DATA_DELTA_OK`.
- `db_verify`: `db-verify.sql` grøn i `createdb -T _u _v` (aldrig i `_u`).
- `removal_restores_identity_set`: `removal-sql --before <_p> --after <_u>` køres i `_u` (rc 0). Derefter er `_u`'s identitetsmængde lig `_p`'s minus `removed_by_ddl`, plus `skipped_existing` (begge tal fra udskriften). Listen skal indeholde `r|private.identity_control_run` og `f|public.red_register_identity_control_run(uuid,text)`.
- `other_schemas_untouched`: den lokale katalogdel er ens i `_p` og `_u`.

- [ ] **Step 2: Kør og se den fejle** (`bash tests/sql/test-transfer-5ab-ddl-upgrade.sh t5ab > "$WS/t3.log" 2>&1; tail -3 "$WS/t3.log"`).

- [ ] **Step 3: Implementér.**

- [ ] **Step 4: Kør og se den bestå.** Expected: `DDL_UPGRADE_SYNTH_OK`. **Bemærk:** det er første gang, HEAD's migrationer køres fra prods træ under emulerede default privileges. Fejler ACL-porten (`EVIDENCE_PUBLIC_RED_ACL_UNCLASSIFIED`), en `REVOKE`-rækkefølge eller I8-deltaet her, er det en fejl i migrationen: STOP og ret den i en egen PR, før plan A fortsætter. Påstanden lempes aldrig, og allow-listen udvides kun med en kommentar om, hvilken blok der skriver tabellen, og efter et ja fra projektejeren.

- [ ] **Step 5: Kør de to CI-jobs `python` og `writer-1939-v50-db` med den lokale runner.** Expected: grønne.

- [ ] **Step 6: Commit** `test(151): DDL-overførslen fra prods træ: afbrud, åbne rettigheder, datadelta og DROP-listen`

---

### Task 4: Privat lib, skrivepause og fase 0 (`01-preflight.sh`)

**Files:** private: `lib.zsh`, `koer.zsh`, `00-freeze.sh`, `01-preflight.sh`, `rollback-preflight.sql`, `expected-new-relations.txt`.

**Interfaces:**
- `lib.zsh` (kopi af trin 4's, renset for data-skridt) tilføjer:
  - `measure_fingerprints <runmappe> <præfiks>` → `<præfiks>-catalog.txt`, `<præfiks>-acl.txt` (0600) og `REPLY="<katalog portabel>|<katalog lokal>|<acl portabel>|<acl lokal>"`.
  - `measure_data <runmappe> <præfiks>` → `<præfiks>-tables.txt` (Task 1), trin 4's digests med `-v src=1`, `transfer_baseline.sql`, `transfer_untouched_hash.sql`, `transfer_restore_hash.sql`.
  - `emulate_default_acl <preflight.json>` (kun lokalt): for hver `d`-linje med rollen `ddl_role` (prods `current_user`, målt i fase 0) udstedes `ALTER DEFAULT PRIVILEGES FOR ROLE current_user IN SCHEMA <skema> GRANT <priv> ON <objtype> TO <modtager>`. Linjer for andre roller påvirker ikke DDL'en og emuleres ikke. Default-ACL'er uden skema (`defaclnamespace=0`) for `ddl_role` stoppes i fase 0 (`DEFAULT_ACL_GLOBAL`), fordi de ikke kan emuleres som skemaregler. Rolle- og privilegienavne valideres mod en fast liste (`postgres`, `anon`, `authenticated`, `service_role`, `PUBLIC`; standardprivilegierne); andet ⇒ `DEFAULT_ACL_LINE`.
  - `reconcile_grants` udvides til `service_role` og skemagrants (portable `g`-linjer i stedet for trin 4's `GRANTS_LIST_SQL`).
  - `use_local_database` og `setup_connection` accepterer kun Global Constraints' basenavne. `step_ddl` sætter `PGOPTIONS='-c lock_timeout=10s'` for apply-kaldene (et låse-timeout giver `PARTIAL` og genkørsel).
- `01-preflight.sh` (læse-kun, ingen argumenter) → `preflight.json` med `status: PREFLIGHT_OK`. Gates i rækkefølge (stopkode i parentes):
  1. mål = `DAA_PROD_TARGET` i prod / ≠ i stand-in (`TARGET`);
  2. trin 4's tre digests og tal = Konstanterne; `interpretation_transfer_digests.sql` køres med `-v src=1` som i trin 4 (`TRANSFER_DRIFT`);
  3. 0 `change_set` med `created_at > '2026-10-05T11:03:06Z'` (`CHANGE_SINCE_TRANSFER`); i stand-in-tilstand: 0 efter basens oprettelse;
  4. driftsbaselinen = Konstanterne (`SCHEMA_DRIFT` / `CANONICAL_DRIFT` / `CLAUSE_SET_DRIFT`);
  5. ingen 5a/5b-tabeller: `to_regclass` er NULL for hver linje i `expected-new-relations.txt` (filen indeholder rene `schema.tabel`-navne; `r|`-præfikset fjernes, når den skrives) (`DDL_ALREADY_PRESENT`);
  6. `server_version_num ≥ 150000`, `private.narrative_record_contract_version() = 2`, 587 accepterede 149b-identiteter, præcis én redaktionsprofil med `actor_sha256` = Konstanten, `public.family.id` har `attidentity IN ('a','d')` (`PREMISE_<navn>`);
  7. locale: `datcollate`, `datctype`, `datlocprovider` og `chars_json`-hashen gemmes; i prod skal de være lig trin 4's preflight 2026-10-05 (`LOCALE_DRIFT`);
  8. `measure_fingerprints` (alle fire dele) og `measure_data` gemmes; `current_user` gemmes som `ddl_role`.
- `00-freeze.sh begin|end`: som trin 4; `end` accepterer i plan A kun `--efter-fortrydelse` med `undo-ok.json` fra `09-undo-ddl.sh` (plan B tilføjer `--efter-verify`).

- [ ] **Step 1: Find trin 4's prod-preflight og noter dens locale- og tegnfelter (kun hashes)**
- [ ] **Step 2: Byg en stand-in:** skriv `expected-new-relations.txt` med `KEEP_REMOVAL` fra Task 3; `createdb -T daa2018f_20261001133125 daa5ab_ddl_standin_<UTC14>`; kør `01` mod den (`DAA_STANDIN_DB=…`). Expected: `PREFLIGHT_OK`; gate 7's prod-sammenligning står som `locale_compared: false`.
- [ ] **Step 3: Negativtests mod en kopi af stand-in'en** (hver forventet STOP med koden): en `change_set`-række efter basens oprettelse ⇒ `CHANGE_SINCE_TRANSFER`; `CREATE TABLE private.interpretation_party(x int)` ⇒ `DDL_ALREADY_PRESENT`; én ændret `assertion.vaerdi_tekst` ⇒ `CANONICAL_DRIFT`; `DAA_FAULT=x` uden `DAA_STANDIN_DB` ⇒ `FAULT_IN_PROD` før forbindelse; et ukendt argument ⇒ exit 2.
- [ ] **Step 4: Ledger-linje** (privat kode committes ikke).

---

### Task 5: Dump og DDL-rehearsal (`02-dump.sh`, `03-rehearsal-ddl.sh`)

**Files:** private: `02-dump.sh`, `03-rehearsal-ddl.sh`, lib-funktionerne `step_ddl`, `undo_ddl`, `ddl_state`.

**Interfaces:**
- **Sammenligningsregel (Review Focus 1):** prod ↔ lokal sammenlignes kun på de portable dele, trin 4's digests og tabelhashes (allow-listede tabeller med `omit=created_at`). Tilstandsfelterne (`restore_hash`, `untouched_hash`, `canonical_sha256` efter DDL) sammenlignes aldrig på tværs af baser. De prod-lokale dele sammenlignes kun **i samme base og samme kørsel**: målt lige før og lige efter skrivningen i `04`/`09`/R1/R3 (skal være uændrede). Forskel mod preflight (Supabase ændrer selv `realtime`/`auth`/`storage` over dage) rapporteres, men stopper ikke.
- `step_ddl <runmappe>`: apply-proceduren fra Task 3 fra `cd "$DAA_REPO"`, stderr til 0600-filer, `WARNING`-linjer skal være 0; `DAA_FAULT=ddl:after_migrations` / `ddl:in_5a_cutover` (kun lokalt) afbryder efter migrationerne / kører kun prefix-filen og returnerer `FAULT_INJECTED`.
- `ddl_state <preflight.json> [<rehearsal-ddl.json>]`:
  - `PRE`: portabel katalog **og** portabel ACL = preflightens;
  - `POST` (kun med rapporten): portabel katalog/ACL = rehearsalens `F1`/`A1`;
  - ellers `PARTIAL` (med rapporten) eller `NOT_PRE` (uden). Afviger kun ACL, er stopkoden `ACL_DRIFT`.
- `undo_ddl <runmappe> <dump> <preflight.json> <rehearsal-ddl.json>`: (a) `removal-sql --before <preflightens katalog> --after <aktuelt>`; hver identitet i listen skal findes i rehearsalens fulde liste (`UNDO_LIST_UNEXPECTED`); én transaktion; (b) trin 4's `undo_restore`; (c) `reconcile_grants` (udvidet, Task 4) mod preflightens portable `g`-linjer; (d) `NOTIFY pgrst, 'reload schema'`; (e) fejllistens hash og antal; `ddl_state` = `PRE`, trin 4's digests og tabelhashes = D0-kvitteringens, og de lokale dele = målingen før (a) i samme kørsel ⇒ `UNDO_OK`, ellers `UNDO_<felt>_DRIFT`; (f) i prod: `get_advisors` efter restoren (spec §8), sammenlignet med `advisors-before.txt`.
- `02-dump.sh d0|d1`: gates som trin 4 (`assert_freeze_active`; `d0` kræver `PREFLIGHT_OK` fra samme pause og `ddl_state = PRE`; `d1` kræver `DDL_VERIFY_OK` fra samme pause og `ddl_state = POST`). `pg_dump -Fc --no-owner` (læse-kun, med ACL'er). Restoreverifikation: restore til `daa5ab_ddl_<d0|d1>check_<UTC14>`; check-restoren er `pg_restore --no-owner --dbname=<check> <dump>` med fejllisten normaliseret og hashet (forventet kun `supabase_vault`, målt i Task 0 Step 3); portabel katalog, portabel ACL, trin 4's digests og tabelhashes skal være prods, målt straks efter dumpet (`RESTORE_FINGERPRINT_DRIFT`). Kvittering med dump-sha, start og alle målinger inkl. tilstandsfelterne; for `d1` er de plan B's udgangspunkt.
- `03-rehearsal-ddl.sh` (lokal; kræver D0-kvittering og preflight) → `rehearsal-ddl.json` (`REHEARSAL_OK`) og `go-hashes.txt`:
  - **R1** restore D0 → `…_a`; portabel ACL = preflightens; `emulate_default_acl`; `step_ddl` ⇒ `F1`/`A1`, varighed; `step_ddl` igen ⇒ `F1`/`A1`; trin 4's digests uændrede og `data-delta` mod D0 med referencefilen ⇒ `DATA_DELTA_OK`; de lokale dele uændrede over apply; `db-verify.sql` grøn i `createdb -T …_a …_v`.
  - **R2** for hvert af de fire punkter: frisk restore → `…_i<n>` + emulering; prefix eller `DAA_FAULT`; `open_exec` rapporteres; fuld `step_ddl` ⇒ `F1`/`A1`.
  - **R3** på `…_a`: `undo_ddl` mod D0 ⇒ `UNDO_OK`; listen (antal, sha, `removed_by_ddl`) og fejllistens hash gemmes.
  - Rapporten binder: D0-sha og kvittering, preflight-sha, commit, sha for `db-migrations.sql`/`db-rls.sql`, `F1`, `A1`, `open_exec` pr. punkt, varigheder, listens sha og antal, fejllistens hash, GO-hashfilens sha.

- [ ] **Step 1: Kør `02 d0` mod stand-in'en.** Expected: `DUMP_OK` og `DUMP_VERIFIED`.
- [ ] **Step 2: Negativtest af restoreverifikationen:** en grant ændret i stand-in'en efter dumpet, før målingen ⇒ `RESTORE_FINGERPRINT_DRIFT`.
- [ ] **Step 3: Kør `03-rehearsal-ddl.sh`.** Expected: `REHEARSAL_OK`; fire afbrud ender i `F1`/`A1`; `db-verify` grøn; R3 `UNDO_OK`.
- [ ] **Step 4: Fortrydelsens efterkrav brydes bevidst:** en ekstra tabel i `private` efter apply, som ikke står i rehearsalens liste ⇒ `UNDO_LIST_UNEXPECTED`; en grant til `anon` og én til `service_role` tilføjet efter restoren, før målingen, fjernes af `reconcile_grants` (antal 2 i udskriften).
- [ ] **Step 5: Ledger-linje** med varigheder (restore, apply, undo) og `open_exec` pr. punkt.

---

### Task 6: Prod-scripts mod stand-in, fejlinjektion og angrebstests

**Files:** private: `04-ddl.sh`, `05-probe-ddl.sh`, `09-undo-ddl.sh`.

**Interfaces:**
- `04-ddl.sh --jeg-mener-det`: I3 → bundne rapporter (preflight, D0-kvittering, rehearsal; sha i `go-env.txt`) → `open_connection` → mål → pause aktiv fra før D0 → `NO_WRITE_SINCE_DUMP` → `ddl_state` med rapporten: `PRE` ⇒ gate-markør, `step_ddl`; `POST` ⇒ `ALREADY_APPLIED` (exit 0); `PARTIAL` ⇒ kun med `DAA_DDL_GENKOERSEL=ja` + gate-markøren fra samme pause, ellers STOP → efter apply: `ddl_state = POST`, trin 4's digests uændrede, `data-delta` D0 → prod ⇒ `DATA_DELTA_OK`, de lokale dele = målingen lige før skrivningen → `ddl.json` (`DDL_OK`). Sidste linje beder projektejeren køre `get_advisors(security)`.
- `05-probe-ddl.sh` (læse-kun, kan køres igen): `ddl_state = POST`; `anon` ser 0 rækker i de private tabeller (trin 4's `ANON_PRIVATE_SQL`, udvidet med `expected-new-relations.txt`); `advisors-after.txt` (projektejerens) sammenlignes med `advisors-before.txt` på antal pr. (lint, objekt); nye par skal være af lint-typer, projektejeren har godkendt for 5a/5b-objekter i `advisors-expected.txt` (skrives i runbooken ud fra rehearsalens nye objekter: lokalt findes ingen advisors, så listen er objektnavne + lint-type, godkendt før GO 1) (`ADVISORS_NEW`) → `ddl-verify.json` (`DDL_VERIFY_OK`).
- `09-undo-ddl.sh --jeg-mener-det`: I3 + bundne rapporter → `undo_ddl` mod D0 → `undo-ok.json` (`UNDO_OK`). Kan køres igen efter et afbrud.

- [ ] **Step 1: Hele vejen mod en frisk stand-in:** `00 begin` → `01` → `02 d0` → `03` → `04` → `05` → `02 d1`. Expected: `PREFLIGHT_OK`, `DUMP_VERIFIED`, `REHEARSAL_OK`, `DDL_OK`, `DDL_VERIFY_OK`, `DUMP_VERIFIED` (d1).
- [ ] **Step 2: Genkørsel:** `04` igen ⇒ `ALREADY_APPLIED`, `ddl.json` byte-uændret.
- [ ] **Step 3: Fejlinjektion** på en anden frisk stand-in: `DAA_FAULT=ddl:after_migrations` ⇒ `FAULT_INJECTED`; `04` uden genkørselsflag ⇒ STOP (`PARTIAL`); med `DAA_DDL_GENKOERSEL=ja` ⇒ `DDL_OK` med `F1`/`A1`. Samme for `ddl:in_5a_cutover`.
- [ ] **Step 4: Prod-miljøets ekstra objekter (Review Focus 1):** en stand-in, hvor der før `01` er oprettet et ekstra skema med en tabel og en `ALTER DEFAULT PRIVILEGES FOR ROLE <anden rolle>`, og hvor `03` køres på en restore, hvor netop de to ting er **fjernet** efter restoren (simulerer, at en lokal restore aldrig har prods lokale dele); hele vejen fra Step 1 går igennem, og de lokale dele er uændrede over DDL'en i stand-in'en. Derefter samme stand-in med en ny grant efter `01`: `04` ⇒ `ACL_DRIFT` før skrivning.
- [ ] **Step 5: Angrebstests** (hver navngivet STOP før skrivning, intet ændret): forkert `DAA_EXPECTED_COMMIT`; snavset inventarfil; en linje for meget/for lidt i GO-hashfilen; manglende `--jeg-mener-det`; ukendt argument; `PGHOSTADDR`/`PGOPTIONS` arvet; `DAA_STANDIN_DB` + prod-`DAA_EXPECTED_TARGET`; en `change_set`-række efter D0 (`NO_WRITE_SINCE_DUMP`). Kør med en `HOME`, hvis `.Renviron` peger på `127.0.0.1:1`, så intet kan nå prod.
- [ ] **Step 6: Fortrydelse mod stand-in'en fra Step 1:** `09` ⇒ `UNDO_OK` (advisors-skridtet står som `advisors: not_applicable` i stand-in); `00 end --efter-fortrydelse` ⇒ `FREEZE_END_OK`.
- [ ] **Step 7: Ledger-linje** med alle stopkoder set.

---

### Task 7: Runbook, beslutninger og status

**Files:**
- Create: `docs/runbooks/transfer-5ab-ddl-prod.md`
- Modify: `docs/decisions.md`, `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md`, `docs/README.md` (runbook-link)

- [ ] **Step 1: Runbook** i trin 4-runbookens form: forudsætninger, kommandoerne i rækkefølge med forventet udskrift, GO 1-pakken (eksakt inventar og `go-env.txt`), stopregler pr. stopkode, genkørsel efter afbrud (et afbrudt `04` køres igen straks eller fortrydes, fordi nye `public`-funktioner kan være kaldbare for `anon`, til deres `REVOKE` er kørt; rehearsalens `open_exec` pr. punkt citeres), fortrydelse (`09`), og overgangen til plan B (D1-kvitteringen, pausen fortsætter). PostgREST-reloaden (spec §10) kan ikke testes lokalt: efter `05` åbner projektejeren redaktørens identitetskø i webfladen, og den skal svare uden schema-cache-fejl (forventet tom kø). `advisors-expected.txt` skrives og godkendes her.
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
- 2026-10-21: Opus-review (NO-GO, 1 BLOCKER, 6 MAJOR, 8 MINOR) indarbejdet. B1 fingeraftryk delt i portabel og prod-lokal del (Task 1, 5); M1 I8 omskrevet med tilladt datadelta og efter-DDL-baseline (Invarianter, Task 2-3, 5); M2 `reconcile_grants` dækker `service_role` og skemagrants (Task 4, 5); M3 `PRE` kræver også ACL (Task 5); M4 DROP-listetestens ligning med `removed_by_ddl`, `db-verify` i kopi (Task 3); M5 fjerde afbrudspunkt i et funktionsvindue, `open_exec` måles, RLS asserteres (Task 2-3); M6 RLS-flag og `reloptions` i kataloget (Task 1). MINOR: `r` kun `relkind r/p`, præcis én markør, strammere identitets-regex, advisors pr. (lint, objekt), uafhængige baser i `fp_same_content`, upgrade-testen kun lokalt (ruling i Task 3), `lock_timeout`, determinismetesten ikke dobbelt. Efterprøvet mod koden før indarbejdning: regelrækkerne og `rule_mode` (`db-migrations.sql` ~l. 21413-21420, 23734), `transfer_baseline.sql`'s regeltabel, DDL'ens egne `DROP FUNCTION` (~l. 7374).
- 2026-10-21: Opus-review runde 2 (NO-GO, kun tekst: 2 BLOCKER, 4 MAJOR, 10 MINOR) indarbejdet. B1 prod sammenlignes efter DDL med D0, ikke med rehearsalens tal (`created_at DEFAULT now()` og sekvensforbrug ved `ON CONFLICT`; sidstnævnte efterprøvet lokalt); tilstandsfelter bindes i D1. B2 lokale dele sammenlignes kun i samme base og kørsel, aldrig mod preflight på tværs. M-a `interpretation_promotion_batch` på allow-listen. M-b kolonne-ejede sekvenser droppes ikke (efterprøvet: PG afviser DROP af identity-sekvens trods `CASCADE`). M-c tabelhashes sorteres `COLLATE "C"` på hele rækken; sessionsindstillinger låst. M-d lokale dele kun før/efter i samme kørsel. MINOR: testantal 21, ekstra regex-/cutover-/sekvenstests, `search_path` ved `regprocedure`, `y`-art præciseret, sektionsfelt `P|`/`L|`, global default-ACL stoppes, rolleliste med `postgres`, `r|`-præfiks fjernes, Task 0 tjekker alle tre baseline-felter og check-restorens fejlliste, advisors pr. (lint, objekt) med godkendt forventningsliste, advisors efter restore, PostgREST-reload verificeres i webfladen.
