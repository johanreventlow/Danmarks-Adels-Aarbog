# Overførsel af 2018-20 — plan B: private ceremoni-scripts, rehearsal og runbook

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (**native**) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent-drevet udførelse er udelukket: alle scripts ligger i `~/.private/`, og hver test rører en restore med persondata. Ingen model uden for sessionen må læse dem uden projektejerens eksplicitte ja (se »Efter planen«).

**Goal:** Byg og øv den hash-bundne, fail-closed ceremoni, der fører pakken `07355ccc…` (3.739 forslag, 676 afgørelser, 622 bindinger) ind i prod. Planen er færdig ved `REHEARSAL_OK` på en lokal stand-in af prod, inklusive en øvet fortrydelse og grønne angrebstests, plus en committed runbook. Selve prod-kørslen er projektejerens GO bagefter.

**Architecture:** Formen er omsegmenteringens (`~/.private/omseg-prod/`, i prod 28/9) og 4.4's (`~/.private/147-44-prod/`). Ni små zsh-scripts (`00`-`05`, `07`-`09`) deler én `lib.zsh`. **Hver skrivende handling er én lib-funktion**, som `03-rehearsal` kalder mod en lokal base, og `04`/`07`/`08`/`05`/`09` kalder mod prod. Det er de samme bytes, der øves, og som kører (invariant I1). Motoren er tynd (spec beslutning 7): ingen trinmotor, intet `06-recover`. Tilstanden klassificeres altid først fra de tre digests (plan A), og et afbrud efter commit rettes ved restore (`09-undo`).

**Tech Stack:** zsh (`/bin/zsh -f`), psql/pg_dump/pg_restore 17 (`/opt/homebrew/opt/postgresql@17/bin`), Python 3 (`/usr/bin/python3 -I`), R (`Rscript --vanilla` i lukket miljø), Supabase Session pooler.

**Spec:** `docs/superpowers/specs/2026-10-03-trin4-2018-20-prod-overfoersel-design.md` (§4.3, §5-§9). Plan A: `docs/superpowers/plans/2026-10-04-trin4-2018-20-overfoersel-a-pakke.md` (ændringsloggen bærer plan B's gates). Forlæg: `~/.private/omseg-prod/lib.zsh` + `00`-`03`, `~/.private/147-44-prod/lib.zsh` (`r_bindings`, `run_r`, levende-SQL), `docs/runbooks/interpretation-proposal-prod-apply.md` (restore-kommandoen).

**Form (bevidst, efter 4.4-præcedensen):** Scriptene beskrives som **kontrakter**: indgange, vagtrækkefølge med stopkoder, udgange og exitkoder. Dertil kommer lib-signaturer og målbare forventninger. Fuld kode står kun for proben og for de små, nye lib-funktioner. 4.4's plan v3 med fulde zsh-kroppe gav plan-mod-plan-fejl i tre Codex-runder. Koden reviewes som kode, og en kontrakt uden kode er her ikke en pladsholder.

## Roadmap-adgangskrav

Som spec §1. Planen leverer ceremoniens værktøj og øvelse. Den løfter først rækken »Proposed-ingest, afgørelse, promotion« for 2018-20, når projektejeren har kørt ceremonien med `VERIFY_OK`. Den erstatter 4.4's motor (`06-recover`, #196-projektionen) som kørselsvej. **Repo-fodaftryk:** kun `.md`-filer (denne plan, runbook, status/changelog), så PR'en er docs-ren og bruger ingen CI-minutter.

## Global Constraints

- **Ingen prod fra AI-sessionen.** Prod rammes kun af projektejeren i egen shell: `! /bin/zsh -f ~/.private/2018-20-overfoersel/<script> …` (hukommelse »prod-skrivning-via-brugerens-shell«). Det gælder også den læse-kun probe i Task 1.
- **Ingen kildetekst, claim-værdier, noter eller aktør-uuid** på stdout, i chat, repo eller commits. Kun tal, koder og hashes. Al psql-stderr går til 0600-filer. Fra dem udtrækkes kun en fejlkode, der matcher `^[A-Z][A-Z_]+$` (`pg_error_code`). Øvrig tekst tælles, den printes aldrig.
- **Privat layout:** scripts og konstanter i `~/.private/2018-20-overfoersel/` (0700; filer 0600, scripts 0700). Kørselstilstand i `~/.private/2018-20-overfoersel/prod/` eller `…/standin-<base>/` (vælges af `DAA_STANDIN_DB`). Den genererede skrive-SQL ligger i `…/sql/07.sql` og `…/sql/08.sql`. Intet privat committes.
- **Konventioner (spec §6.1):**
  - `/bin/zsh -f` med `assert_no_rcs`, `emulate -R zsh`, `set -euo pipefail`, `umask 077` og `setopt POSIX_TRAPS`.
  - Alle `PG*` ryddes. `PGTZ=UTC`. Kun Session pooleren (`*.pooler.supabase.com:5432`).
  - Skrivende scripts kræver `--jeg-mener-det` (hukommelse »prod-wrapper-skal-kraeve-flag«). Ukendte argumenter giver exit 2.
  - Python kun som `PY=(/usr/bin/env -u PYTHONOPTIMIZE -u PYTHONPATH -u PYTHONHOME -u PYTHONSTARTUP /usr/bin/python3)` med `-I` og eksplicit `raise SystemExit`, aldrig `assert`.
  - R kun via `run_r` (`env -i` + allowlist + `--vanilla`).
  - Læse-kun psql med `PGOPTIONS='-c default_transaction_read_only=on'`.
- **Lokale baser** skal matche R-filernes mønster `^daa44_rehearsal_[a-z0-9_]+$`:
  - `daa44_rehearsal_transfer_probe_<UTC14>` (Task 1);
  - `daa44_rehearsal_transfer_standin_<UTC14>` (stand-in for prod);
  - `daa44_rehearsal_transfer_<UTC14>_r` (03's rehearsal).

  Restoren `daa2018f_20261001133125` ændres aldrig. Testbaser droppes ikke af planen; de noteres til oprydning (sletning kun efter måling og ja).
- **Kilden** er `source_id = 1`; plan A-filerne får `-v src=1`.
- **Commits:** én pr. task, kun `.md`-filer i repoet, `docs(147): …`, afsluttet med `Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb`. Ingen push uden ja.

### Konstanter (bundet i `lib.zsh`; målt 2026-10-04)

| Navn | Værdi |
| --- | --- |
| `DAA_PACK_SHA256` | `07355ccca68968e8744b0d32a5c3c3b4718a1aa0131ff1527ccd5ed67c5d64ae` |
| Pakkefiler (byte-SHA) | `pack-manifest.json` `37fb9b01cd87514c36180023f732e242a4cdf98902720c88c9b0b07867d6e76c`; `decisions-keyed.json` `c39a5f5c626cf505257046c477a1e2c3b1211f25253aac71575e41de96d8a028` |
| Genereret SQL (byte-SHA, deterministisk fra pakken) | `07.sql` `af7e51a7df35cfcf3ccc6e82635b9b1d844f0d33d5e83c6b34ffe129f5c87341`; `08.sql` `b903896f4cb1b42ef7656fa9565caffe81c594de02329a75ed111fb55c9c1635` |
| Forslagsmanifest | `~/.private/2018-20-fuld/proposal-manifest.json`, fil `a5aa8e675eefda67a99f84dc7a33c7c59141c438e83998b4a567fb2399a56a07` (= `DAA_PREVIEW_SHA256`), indhold `80f3e5c1e3f16058ce7292e2ce8258239c4efee897a8299aa6630cf52064e3e5`; 478 operationer, 3.739 claims, 3.787 links, 2.767 `principal` / 972 `other` |
| Eligibility-ledger | `~/.private/2018-20-fuld/ledger/eligibility-ledger-v1.json` `e620073c82adc13a28dd707748a26e8c07a88940a3c0daf5dd1ab82b9ef314a4`; alle 478 operationers poster `eligible` |
| Writer-profil (repo) | `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json` `96d24054dbd32356d97ae3ed5925f4a0338924901b1d418d42d0c6d23b34d610` |
| Genbrugte R-filer (kopieres uændret fra `~/.private/147-44-prod/`) | `01-role-probe-prod.R` `13b54702…b2304`, `03-proposal-dryrun-prod.R` `e2fdb5c2…d70dc`… se Task 2 Step 1 for fulde værdier |
| Pakkens baseline (drift-felter) | `schema_sha256` `12d8d841cf1f4b872b0eda2acf7990dcc2260bb58b3afbd4ed277735621e8902`, `canonical_sha256` `1137bce7a7f65a74b8d46a57951a4e4ca722155368e377d727ab1981be43ffbd`, `clause_set_sha256` `113a1d12550e0a4f4b0f0b8cce4e73a4a1e04311c2e93397b2fff8e7ac3d1fea` |
| Aktør | `actor_sha256` `3c4984c769aa63a4c4f81be7f001abf162f016eb72704656dcbc6618ceb71e59` = SHA-256 af den ene `profiles.rolle='redaktion'` (målt i restoren: 1 række, samme hash) |
| Levende-gate | 471 poster med `principal`-claims ⇒ `471\|471\|471\|471\|471` (målt i restoren); 7 poster med kun `other`-claims (heriblandt den ene uden persona) går med på ledgerets grundlag (spec beslutning 8) |
| Prods mål-identitet | `DAA_PROD_TARGET=71ca6e452cc7d596d8470807e29084cd9d99f8ac24155556afd635da84ffe0f0` (`clause_evidence_target_identity.sql`, som omsegmenteringen) |
| Lokale varigheder (plan A, `fef5ac2`) | pg_restore 2 s, dry-run 12 s, apply 13 s, `07` 15 s, `08` 3 s |

### Spec → virkelige filer (errata, så GO-inventaret kan bygges)

| Spec siger | Virkeligheden |
| --- | --- |
| `build_transfer_pack.py` | `transfer_pack.py build` |
| `transfer_decide.sql` | `transfer_pack.py decide-sql` / `bind-sql` → `sql/07.sql`, `sql/08.sql` (genereret én gang, byte-bundet) |
| katalogforespørgslen; »restore-hash-forespørgslen« | `transfer_restore_preconditions.sql`; `transfer_restore_hash.sql` |
| `decision_digest` over alle 3.739 | over de afgjorte (plan A-errata; `proposal_digest` tjekkes altid med) |
| §6.2: antal elementer, claims, links og roller »sammenlignes med pakkens« | Pakken bærer kun `manifest_content_sha256` og `n_interpretations` (3.739). **Ruling:** gaten er manifestets fil- og indholdshash plus claims = 3.739; resten håndhæves af serverens `finalize` mod autorisationens `expected_counts`, der tages fra manifestet |
| dumptilstand = pakkens | Ceremoniens dump har andre bytes end 1/10-dumpet. Gaten er de tre drift-felter (`TRANSFER_DRIFT`/`CLAUSE_SET_DRIFT`/`SCHEMA_DRIFT`), aldrig `dump_sha256`-lighed |
| §7's inventar (`00`-`05`, `07`, `08`, lib) | + `09-undo.sh` (**ruling:** spec §8.2 kræver »den kommando, rehearsalen har øvet«; kun et bundet script garanterer det; tallet 09 holder afstand til det fravalgte `06-recover`) + `rollback-preflight.sql` + `sql/07.sql` + `sql/08.sql` |

### Invarianter

- **I1 Samme bytes.** Hver skrivende eller målende handling er én lib-funktion:
  - `step_apply`, `step_decide`, `step_bind`, `step_verify` og `undo_restore`.
  - `03` kalder dem med en lokal forbindelse.
  - Prod-scriptene kalder dem med prods.
  - Ingen logik dubleres i scriptene.
- **I2 Tilstand først.** Hvert skrivende trin måler digests (`interpretation_transfer_digests.sql`) og klassificerer med `transfer_pack.py state`.
  - I trinnets **indgangstilstand** skriver det.
  - I dets **udgangstilstand** melder det `ALREADY_APPLIED` og skriver intet (exit 0). For `07` gælder det kun, hvis alle 676 aktuelle afgørelser bærer `decision_evidence->>'pack_sha256' = DAA_PACK_SHA256`.
  - I enhver anden tilstand er det STOP (exit 1).
- **I3 Hash-bundet.** Hvert prod-script verificerer GO-hashfilen (`verify_go_hashes`: mængden er eksakt, en linje for meget eller for lidt er STOP), at repo-filerne i inventaret er rene, og at commit = `DAA_EXPECTED_COMMIT`. Det sker før første forbindelse.
- **I4 Lukket miljø.** I prod-tilstand afvises `DAA_FAULT`, `DAA_LOCAL_*` og `DAA_REIMPORT_ACTOR_ID` **før** første forbindelse (`assert_prod_env_clean`). R kører kun via `run_r`. Den genererede SQL køres fra `cd "$DAA_REPO"`, fordi dens `\i` er cwd-relative.
- **I5 Ingen PII ud.** psql-stdout læses kun for OK-markører (`TRANSFER_07_OK …`); `NOTICE`-linjer som `TRANSFER_08 items=…` lander i 0600-stderr-filen og tælles derfra med et regex. R-logfiler er 0600 og greppes kun for markører.
- **I6 Aktør.** Aktøren læses i processen fra den forbundne base: præcis én `profiles.rolle='redaktion'`, og dens SHA-256 skal være pakkens. Den leveres til psql på **stdin** (`\set actor '…'`), aldrig i argv, miljø eller stdout.
- **I7 Mål.** I prod skal mål-identiteten være `DAA_PROD_TARGET`. Lokalt skal den være noget andet. `DAA_EXPECTED_TARGET` bindes i GO.
- **I8 Skrivepause.** Pausen skal være aktiv fra før dumpets start.
  - `02` måler restore-hash og uberørt-hash lige efter dumpet.
  - `04`'s første forsøg kræver restore-hash = `02`'s og 0 `change_set` med `created_at ≥ dump_start` (`NO_WRITE_SINCE_DUMP`).
  - Et genforsøg efter et afbrud kræver uberørt-hash = første forsøgs indgangsmåling. **Ruling:** restore-hashen flyttes lovligt af gatewayens profilrække og autorisationer, mens uberørt-hashen udelukker netop kædens tabeller; spec §6.2 »EMPTY ⇒ 04 køres igen« forudsætter et sådant genforsøg.

## Review Focus

1. **Prods locale klassificerer anderledes end Mac-restoren.** `lower()` og `[[:alnum:]]` i `interpretation_control_classification.sql` afhænger af `LC_CTYPE`. Forventet: proben fanger det på forhånd (Task 1, G2), og ellers giver `07` `MACHINE_PREMISE_DRIFT` uden at skrive. Test: Task 1 Step 4 (tegnprobe lokalt mod en base med en anden ctype), Task 8 Step 4 (manipuleret klassifikation ⇒ STOP, intet skrevet).
2. **Forbindelsen dør midt i `04`.** Afbrydes før gatewayens commit, er tilstanden `EMPTY`, og `04` kan køres igen. Afbrydes efter commit, er tilstanden `PROPOSED`, og `04` melder `ALREADY_APPLIED`. Alt andet ⇒ `09-undo`. Test: Task 8 Step 3 med `DAA_FAULT=apply:after_authorize` og `apply:after_execute`.
3. **`07`/`08` køres igen efter commit.** Forventet `ALREADY_APPLIED`, ingen skrivning og digests uændret. En `DECIDED` med et andet `pack_sha256` giver STOP. Test: Task 8 Step 2 og 4.
4. **Fortrydelse oven på en befolket base efterlader rester:** RLS-afhængige funktioner (`current_rolle()`, `media_object_synlig_anon(text)`) og sekvenser. Forventet: tilstanden er `EMPTY`, og restore-hash, katalog og baseline er lig prods målinger fra `01`/`02`. Den fulde fejlliste måles og bindes. Test: Task 7 (rehearsal) og Task 8 Step 5 (stand-in-fortrydelse).
5. **Arvet miljø slår en stopport fra** (`PGHOSTADDR`, `PGOPTIONS`, `DAA_REIMPORT_ACTOR_ID`, `DAA_FAULT`, `PYTHONOPTIMIZE`, en `.Renviron`, der peger forkert). Forventet: navngivet STOP før forbindelse eller uændret resultat. Test: Task 8 Step 6 (angrebstests, kørt med en `HOME`, hvis `.Renviron` peger på `127.0.0.1:1`, så intet kan nå prod).

---

## Filoversigt

Private (`~/.private/2018-20-overfoersel/`, aldrig i git):

| Fil | Ansvar |
| --- | --- |
| `lib.zsh` | Konstanter, miljø, forbindelse (prod/stand-in), mål, `sql_json`, målinger, tilstand, levende-gate, aktør, R, GO-inventar, skrivepause, kvitteringer, `step_*`, `undo_restore` |
| `probe.zsh` | Task 1: læse-kun probe (ikke en del af GO) |
| `probe-compare.py` | Task 1: sammenligner to probe-JSON'er gate for gate |
| `00-freeze.sh` | Skrivepause: `begin`; `end` med `verify-ok.json` / `undo-ok.json` / `--uden-skrivning` |
| `01-preflight.sh` | Læse-kun: rolleprobe, drift, skema, `EMPTY`, levende-gate, restore-forudsætninger, katalog, grants, tegnprobe → `preflight.json` |
| `02-dump.sh` | Dump + kvittering med restore-hash, uberørt-hash og tidsstempler |
| `03-rehearsal.sh` | Lokal restore af netop dagens dump: `04`→`07`→`08`→`05`, fortrydelsesøvelse, varigheder, GO-hashfil → `REHEARSAL_OK` |
| `04-apply.sh` | `--jeg-mener-det`: `step_apply` → `04-report.json` |
| `07-decide.sh` | `--jeg-mener-det`: `step_decide` → `decide.json` |
| `08-bind.sh` | `--jeg-mener-det`: `step_bind` → `bind.json` |
| `05-verify.sh` | Læse-kun: `step_verify` → `VERIFY_OK` (`verify-ok.json`) |
| `09-undo.sh` | `--jeg-mener-det`: `undo_restore` mod den forbundne base → `UNDO_OK` (`undo-ok.json`) |
| `01-role-probe-prod.R`, `03-proposal-dryrun-prod.R`, `04-proposal-apply-prod.R` | Kopieret byte-identisk fra `~/.private/147-44-prod/` |
| `rollback-preflight.sql` | Kopieret fra `~/.private/omseg-prod/` |
| `sql/07.sql`, `sql/08.sql` | Genereret af `transfer_pack.py` fra pakken, byte-bundet |

Repo (committes):

| Fil | Ansvar |
| --- | --- |
| `docs/superpowers/plans/2026-10-04-trin4-2018-20-overfoersel-b-ceremoni.md` | Denne plan + ændringslog |
| `docs/runbooks/transfer-2018-20-prod.md` | Autoritativ ceremoni: kommandoer, GO-pakke, stopregler, fortrydelse |
| `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md` | Kort statuslinje |

### GO-inventar (eksakt mængde, 33 linjer)

- **Privat (16):** `lib.zsh`, `00-freeze.sh`, `01-preflight.sh`, `02-dump.sh`, `03-rehearsal.sh`, `04-apply.sh`, `05-verify.sh`, `07-decide.sh`, `08-bind.sh`, `09-undo.sh`, de tre R-filer, `rollback-preflight.sql`, `sql/07.sql`, `sql/08.sql`.
- **Input (4):** `pack/pack-manifest.json`, `pack/decisions-keyed.json`, `proposal-manifest.json`, `eligibility-ledger-v1.json`.
- **Repo (13):**
  - SQL under `.claude/skills/daa-extract/scripts/`: `transfer_restore_hash.sql`, `transfer_restore_preconditions.sql`, `transfer_untouched_hash.sql`, `transfer_baseline.sql`, `interpretation_transfer_digests.sql`, `interpretation_decision_fingerprint.sql`, `interpretation_control_classification.sql`, `interpretation_promotion_targets_scoped.sql`, `interpretation_promotion_targets.sql`, `clause_evidence_target_identity.sql`.
  - Python og R: `transfer_pack.py`, `apply_reimport_helpers.R`.
  - Profilen: `references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json`.

Transitive inkluderinger er efterprøvet: scoped `\i`'er targets, og R-filerne `source()`'er `apply_reimport_helpers.R` og læser profil-JSON'en. Clean-tree-kontrollen dækker netop de 13 repo-stier.

---

### Task 0: Forudsætninger målt

**Files:** ingen ændringer.

- [ ] **Step 1: Pakke og genafspilning er de forventede**

```bash
O=~/.private/2018-20-overfoersel
shasum -a 256 $O/pack/pack-manifest.json $O/pack/decisions-keyed.json | cut -c1-16
/usr/bin/python3 -c "import json;r=json.load(open('$O/replay/replay.json'));print(r['status'],r['pack_sha256'][:16],r['code_head'])"
git -C /Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/147-pakke log --oneline -1 origin/main
```

Forventet: `37fb9b01cd87514c`, `c39a5f5c626cf505`; `PACK_REPLAY_OK 07355ccca68968e8 fef5ac2`; origin/main indeholder `f10ce3b` (plan A merget). Afviger noget: STOP og spørg.

- [ ] **Step 2: Lokale værktøjsversioner**

```bash
/opt/homebrew/opt/postgresql@17/bin/pg_dump --version; /opt/homebrew/opt/postgresql@17/bin/psql -X -At -h /tmp -d postgres -c "SHOW server_version_num"
```

Forventet: pg_dump 17.x og `17xxxx`. Tallene noteres i ændringsloggen; proben sammenligner dem med prods.

---

### Task 1: Lib-fundament og læse-kun prod-probe (gaten, der kan aflyse planen)

**Files:**
- Create: `~/.private/2018-20-overfoersel/lib.zsh` (fundament), `probe.zsh`, `probe-compare.py`

**Interfaces:**
- Produces (lib):
  - Fra `omseg-prod/lib.zsh`: `fail`, `usage_fail`, `expect_eq`, `require_file`, `require_sha`, `sha256_file`, `assert_no_rcs`, `private_layout`, `new_private_dir <mønster>`, `write_json <sti> <py-udtryk> <args…>` (O_EXCL, 0600), `json_get <sti> <a.b>`, `clear_pg_environment`, `open_connection` (prod eller `DAA_STANDIN_DB`), `readonly_psql`, `write_psql`, `target_identity` og `assert_expected_target`.
  - Fra 4.4: `assert_prod_env_clean`.
  - Nye: `sql_json <fil.sql> <ud.json>`, `pg_error_code <stderr-fil>`, `classify_state <digests.json>` (→ `EMPTY|PROPOSED|DECIDED|COMPLETE|MIXED`), `levende_sql` / `levende_counts` (→ `a|b|c|d|e`), `ledger_check` og `actor_check` (→ `1|<sha>`; aktøren selv forlader aldrig funktionen).
- Produces (konstanter, navne bruges af senere tasks):
  - **Faste absolutte stier**, upåvirket af `HOME`, så angrebstests med en test-`HOME` aldrig flytter input: `DAA_REPO`, `DAA_SQL_DIR`, `DAA_BASE=/Users/johanreventlow/.private/2018-20-overfoersel`, `DAA_PACK_DIR=$DAA_BASE/pack` og `DAA_MANIFEST`/`DAA_LEDGER` (stier under `/Users/johanreventlow/.private/2018-20-fuld/`).
  - **Hashes:** `DAA_PACK_SHA256`, `DAA_PACK_MANIFEST_SHA256`, `DAA_DECISIONS_SHA256`, `DAA_07_SQL_SHA256`, `DAA_08_SQL_SHA256`, `DAA_PREVIEW_SHA256` (= manifestets fil-hash), `DAA_MANIFEST_CONTENT_SHA256`, `DAA_LEDGER_SHA256`, `DAA_PROFILE_SHA256`, `DAA_ACTOR_SHA256`, `DAA_PROD_TARGET` og `DAA_BASELINE_{SCHEMA,CANONICAL,CLAUSE_SET}`. Alle værdier står i konstanttabellen ovenfor.
  - **Kørselstilstand:** `DAA_PRIVATE_DIR=$HOME/.private/2018-20-overfoersel/{prod|standin-<base>}` er den eneste sti, der følger `HOME`.
- Produces (data): `probe.json` (prod) og `probe.json` (lokal) med nøglerne i Step 3; `probe-compare.py` udskriver én linje pr. gate: `G<n> <navn> OK|AFVIGER|INFO`.

- [ ] **Step 1: Skriv lib-fundamentet**

Kopiér `omseg-prod/lib.zsh` linje 1-121 (konstanter, hjælpere, forbindelse, mål). Lav disse ændringer:
- `DAA_PRIVATE_DIR="$HOME/.private/2018-20-overfoersel/prod"`, eller `…/standin-$DAA_STANDIN_DB`.
- Stand-in-mønsteret skal være `^daa44_rehearsal_transfer_(standin|probe)_[0-9]{14}$`.
- Konstanterne er tabellen ovenfor.

Fjern omsegmenteringens profil-, ledger- og rendition-konstanter. Tilføj disse tre nye funktioner:

```zsh
# Prod afviser test-/fejlmiljø FØR forbindelse (4.4 R4-6). Kaldes af open_connection i prod-tilstand.
assert_prod_env_clean() {
  [[ -z "${DAA_FAULT:-}" ]] || fail "FAULT_IN_PROD"
  [[ -z "${DAA_REIMPORT_ACTOR_ID:-}" ]] || fail "ACTOR_ENV_INHERITED"
  (( ${#${(k)parameters[(I)DAA_LOCAL_*]}} == 0 )) || fail "LOCAL_ENV_IN_PROD"
}
# Plan A-filerne gemmer resultatet i en GUC og printer det som sidste linje (se plan A, Architecture).
sql_json() { # fil.sql ud.json
  ( cd "$DAA_REPO" && readonly_psql -v src=1 -f "$DAA_SQL_DIR/$1" ) 2>"$2.err" | /usr/bin/tail -1 > "$2" \
    || fail "$1 fejlede ($(pg_error_code "$2.err"))"
  /bin/chmod 600 "$2" "$2.err"
  "${PY[@]}" -I -c 'import json,sys; d=json.load(open(sys.argv[1])); raise SystemExit(0 if isinstance(d,dict) else "NOT_OBJECT")' "$2" \
    || fail "$1 gav ikke ét JSON-objekt"
}
# Kun en navngiven kode (vores RAISE-koder er VERSALER_MED_UNDERSTREG); aldrig meddelelsens øvrige tekst.
pg_error_code() {
  local c; c="$(/usr/bin/sed -nE 's/^(psql:[^:]*:[0-9]+: )?ERROR: +([A-Z][A-Z_]+)( .*)?$/\2/p' "$1" | /usr/bin/head -1)"
  print -r -- "${c:-UKENDT_FEJL_SE_$(/usr/bin/basename "$1")}"
}
```

`open_connection` kalder `assert_prod_env_clean`, når `DAA_STANDIN_DB` er tom, **før** `setup_connection`. Prod-grenen af `setup_connection` håndhæver desuden pooleren på shell-siden. Omsegmenteringens gjorde ikke, kun R-filerne. Kravet tjekkes, før `PGPASSWORD` eksporteres:

```zsh
[[ "$PGHOST" =~ '^[a-z0-9-]+\.pooler\.supabase\.com$' && "$PGPORT" == "5432" ]] || fail "POOLER_REQUIRED (kun Session pooleren)"
```

`setup_connection` sætter også `CTX_TARGET` (det aktuelle mål), som `run_r` sender videre. I prod er det `DAA_PROD_TARGET`; lokalt er det basens egen identitet (Task 7 Step 1).

Nedenstående hører også til fundamentet, fordi proben bruger dem:
- `classify_state`, med koden nedenfor.
- `levende_sql`, der genererer SQL'en fra manifestet med 4.4's mønster (`147-44-prod/lib.zsh` `preflight_manifest_sql`, `kind == "persona"`) over de poster, der har mindst én `principal`-claim (471).
- `ledger_check`, der er Python uden database. Krav:
  - ledgerets fil-hash = `DAA_LEDGER_SHA256`;
  - alle 478 operationers `source_record_key` har `status == "eligible"`;
  - `provenance.eligibility_ledger_sha256` = ledgerets hash.

  Ellers `LEDGER_GATE`.
- `actor_check`, der læser `count(*)` og SHA-256 af `id::text` for `profiles WHERE rolle='redaktion'`.

```zsh
classify_state() { # digests.json -> EMPTY|PROPOSED|DECIDED|COMPLETE|MIXED
  "${PY[@]}" -I "$DAA_SQL_DIR/transfer_pack.py" state --digests "$1" --pack-manifest "$DAA_PACK_DIR/pack-manifest.json" \
    || fail "tilstanden kunne ikke klassificeres"
}
```

- [ ] **Step 2: Skriv `probe.zsh`**

Kontrakt: ingen argumenter (ellers exit 2), læse-kun, stand-in-bevidst gennem `DAA_STANDIN_DB`. Skriver `$DAA_PRIVATE_DIR/probe-<UTC14>.json` (O_EXCL, 0600) og udskriver kun `PROBE_OK <sti> <sha256>`. Indhold:

| Nøgle | Kilde |
| --- | --- |
| `target` | `target_identity` |
| `server_version_num`, `datcollate`, `datctype`, `encoding` | `SHOW server_version_num`; `pg_database` for `current_database()`; `pg_encoding_to_char(encoding)` |
| `chars` | Én post pr. kodepunkt `cp → sha256(lower|alnum|stripped)[:16]` fra SQL'en nedenfor (kun tal og hex; i 0600-filen) |
| `data_codepoints` | Kodepunktmængden i `public.assertion.vaerdi_tekst`/`date_raw` (SQL nedenfor). Lokalt lægges manifestets claim-værdier til af `probe-compare.py` (Python, kun kodepunkter) |
| `assertion_chars_over_2fff` | SQL'en nedenfor |
| `baseline` | `sql_json transfer_baseline.sql` (alle fire felter) |
| `digests` + `state` | `sql_json interpretation_transfer_digests.sql`; `transfer_pack.py state --pack-manifest pack/pack-manifest.json` |
| `preconditions` | `sql_json transfer_restore_preconditions.sql` (`orphans`, `n_orphans_total`, `n_multi_column_fks`, `catalog_sha256`) |
| `restore_hash`, `untouched_hash` | `sql_json transfer_restore_hash.sql` / `transfer_untouched_hash.sql` |
| `actor` | `count(*)` og SHA-256 af `id::text` for `profiles WHERE rolle='redaktion'` |
| `timeouts` | `current_user`, `SHOW statement_timeout`, `idle_in_transaction_session_timeout`, `lock_timeout`, `rolconfig` for `current_user` (kun GUC-navn=værdi) |
| `levende` | `levende_counts` (Task 3 Step 1's generator; i proben kun læst) |
| `change_sets_since_2026_10_01` | `count(*) FROM public.change_set WHERE created_at >= '2026-10-01T13:30:17Z'` (1/10-dumpets start fra kvitteringen) |

Tegnproben (fuld kode; dækker Latin, græsk, kyrillisk, tegnsætning, hævede tal og tegnformer op til U+2FFF):

```sql
-- Pr. kodepunkt: hvad lower(), [[:alnum:]] og klassifikationens strip-udtryk giver. Én linje pr. cp,
-- så sammenligningen kan pege på de afvigende kodepunkter (kun tal), ikke bare sige "forskellig".
SELECT jsonb_object_agg(cp::text, left(encode(extensions.digest(convert_to(
         lower(chr(cp)) || '|' || (chr(cp) ~ '[[:alnum:]]')::int || '|' ||
         regexp_replace(lower(normalize(chr(cp), NFC)), '[^[:alnum:]]+', '', 'g'),
         'UTF8'), 'sha256'), 'hex'), 16))::text
  FROM generate_series(32, 12287) cp
 WHERE cp NOT BETWEEN 55296 AND 57343;
-- Datasidens kodepunkter (tal, ingen tekst).
SELECT coalesce(jsonb_agg(DISTINCT ascii(ch) ORDER BY ascii(ch)), '[]')::text
  FROM public.assertion a,
       regexp_split_to_table(coalesce(a.vaerdi_tekst,'') || coalesce(a.date_raw,''), '') ch
 WHERE ch <> '';
SELECT count(*) FROM public.assertion a,
       regexp_split_to_table(coalesce(a.vaerdi_tekst,'') || coalesce(a.date_raw,''), '') ch
 WHERE ch <> '' AND ascii(ch) > 12287;
```

Hele intervallet sammenlignes ikke: glibc og macOS' libc er uenige om skrifter, der er irrelevante for dansk tekst (fx georgisk og cherokee), og det ville give falsk STOP. **Gaten** er derfor, at intet kodepunkt i datamængden afviger. Datamængden er prods assertion-kodepunkter ∪ den lokale restores ∪ manifestets claim-værdier (Python, kun kodepunkter). Antallet af tegn > U+2FFF i manifestet skal være 0; ellers udvides intervallet, før proben køres i prod.

- [ ] **Step 3: Skriv `probe-compare.py`**

Den tager to probe-filer (prod, lokal) og pakkens manifest og udskriver én linje pr. gate. Exit 0, når alle G-gates er `OK`, ellers 1. Gates:

| Gate | Krav | Ved afvigelse |
| --- | --- | --- |
| G1 version | `server_version_num // 10000` ens (17) | STOP: `schema_sha256`/`catalog_sha256` er ikke sammenlignelige |
| G2 tegn | 0 afvigende kodepunkter (`chars` prod ≠ lokal) inden for datamængden; `assertion_chars_over_2fff` = 0 i begge. Afvigende kodepunkter uden for datamængden tælles som INFO | STOP: klassifikationen kan afvige mellem prod og restore. Udskriv de afvigende kodepunkter (tal) |
| G3 drift | prods `baseline` = pakkens på alle tre drift-felter; `n_interpretations_src` = 0 | STOP: spec beslutning 1 (kæden køres om på et nyt dump; uden for planen) |
| G4 tilstand | prods `state` = `EMPTY` | STOP |
| G5 katalog | `catalog_sha256` prod = lokal ren restore; `n_orphans_total` = 0 begge | STOP: fortrydelsesøvelsen kan ikke bevise troskab (spec §6.1 trin 4b) |
| G6 aktør | prod: 1 række, hash = pakkens | STOP: `07` ville give `TRANSFER_ACTOR_MISMATCH` |
| G7 timeouts | login-rollens `statement_timeout` = 0 eller ≥ 120 s (beslutning 4/10, se ændringsloggen); `idle_in_transaction_session_timeout` = 0 eller ≥ 600 s | STOP og spørg |
| G8 levende | prod = `471\|471\|471\|471\|471` | STOP: spec beslutning 8 |
| I1 uberørt siden 1/10 | `restore_hash`, `untouched_hash` prod = lokal; `change_sets_since_2026_10_01` | INFO: viser, om nogen har skrevet; G3 er gaten |

- [ ] **Step 4: Selvtest lokalt (to restorer, ingen prod)**

```bash
cd ~/.private/2018-20-overfoersel
X=(env -u PGHOSTADDR -u PGSERVICE -u PGSERVICEFILE -u PGHOST -u PGPORT -u PGUSER -u PGPASSWORD -u PGDATABASE)
for t in probe standin; do DB=daa44_rehearsal_transfer_${t}_$(/bin/date -u +%Y%m%d%H%M%S)
  $X /opt/homebrew/opt/postgresql@17/bin/createdb -h /tmp $DB
  $X /opt/homebrew/opt/postgresql@17/bin/pg_restore -h /tmp --clean --if-exists --no-owner --dbname=$DB ~/.private/2018-20-fuld/daa-prod-20261001133017.dump 2>/dev/null || true
  print -r -- $DB; done
DAA_STANDIN_DB=<probe-base> /bin/zsh -f probe.zsh > /dev/null; DAA_STANDIN_DB=<standin-base> /bin/zsh -f probe.zsh > /dev/null
/usr/bin/python3 -I probe-compare.py --prod standin-<standin-base>/probe-*.json --local standin-<probe-base>/probe-*.json --pack pack/pack-manifest.json
```

Forventet: G1-G8 `OK` (to ens restorer). Negativtests køres på **kopier** (`createdb -T <standin-base> daa44_rehearsal_transfer_standin_<nyt stempel>`):
- **G2:** en base oprettet med `createdb --locale=C -E UTF8 --template=template0` og samme restore skal give `G2 tegn AFVIGER` med æ/ø/å blandt de afvigende kodepunkter. Det beviser, at proben ser ctype. Uden `-E UTF8` bliver basen SQL_ASCII, og `chr(cp)` fejler over 127 i stedet for at afvige.
- **G3:** én række i en baseline-tabel ændres i kopien (`public.fact`; afviser en trigger det, en anden baseline-tabel) ⇒ `G3 drift AFVIGER`.

Kopierne noteres til oprydning; stand-in-basen forbliver ren til Task 8.

- [ ] **Step 5: Projektejeren kører proben i prod (læse-kun)**

Planen pauser her, til svaret foreligger. Kommando til projektejeren:

```
! /bin/zsh -f ~/.private/2018-20-overfoersel/probe.zsh
```

Derefter sammenligner jeg `prod/probe-*.json` med den lokale `probe`-base: `probe-compare.py --prod prod/probe-*.json --local standin-<probe-base>/probe-*.json --pack pack/pack-manifest.json`. Alle G-gates `OK`: fortsæt. Enhver G-afvigelse: STOP, fremlæg tallene og spørg. Planen omgår ikke en afvigelse.

- [ ] **Step 6: Notér i ændringsloggen og commit**

Kun gate-linjerne og tallene (versioner, ctype, timeouts, I1-info), ingen hashes ud over de første 16 tegn.

```bash
git add docs/superpowers/plans/2026-10-04-trin4-2018-20-overfoersel-b-ceremoni.md
git commit -m "docs(147): plan B — prod-proben målt (<resultat>)"
```

---

### Task 2: Skrivepause, dump, fortrydelseskommando og GO-inventar

**Files:**
- Modify: `lib.zsh` (+ inventar, skrivepause, kvittering, `undo_restore`, `r_bindings`, `run_r`)
- Create: `00-freeze.sh`, `02-dump.sh`, `09-undo.sh`; kopier af de tre R-filer og `rollback-preflight.sql`

**Interfaces:**
- Produces:
  - `GO_PRIVATE_FILES`, `GO_INPUT_FILES` og `GO_REPO_FILES` (inventaret ovenfor), `go_hashes_lines`, `verify_go_hashes`, `assert_repo_clean`, `repo_commit` og `assert_expected_commit` (omseg-mønster).
  - `assert_freeze_active <mål> [dump_start]`, `assert_freeze_report`, `assert_bound_report <navn> <sti> <sha> <status>`, `read_dump_receipt <sti>` (→ sti, start, sha, bytes, mål, restore_hash, untouched_hash), `write_marker <navn> <json-felter>` (O_EXCL, bundet til den aktive pause).
  - `undo_restore <db-navn> <dump> <stderr-fil>`, `r_bindings` og `run_r <log> <script> <args…>` (4.4 linje 480-536; `DAA_RUN_MODE` = `prod` | `local`).

- [ ] **Step 1: Kopiér de genbrugte filer byte-identisk og bekræft hashes**

```bash
cd ~/.private/2018-20-overfoersel && cp -p ~/.private/147-44-prod/{01-role-probe-prod.R,03-proposal-dryrun-prod.R,04-proposal-apply-prod.R} . && cp -p ~/.private/omseg-prod/rollback-preflight.sql . && chmod 600 *.R rollback-preflight.sql
shasum -a 256 01-role-probe-prod.R 03-proposal-dryrun-prod.R 04-proposal-apply-prod.R rollback-preflight.sql | cut -c1-64
```

Forventet: `13b54702d22a2ac4b30c46798fa7d139ab7ba4a66fba74fb4454aeeb8f9b2304`, `e2fdb5c25e2e403e8d8e754d7e66eeb4b6691a89150b46a44dd65cb8473824f9`, `5d5f55f80d6810836aa62ff5cc63431600525550a4e1d18426de92ef319d70dc`, `bcd9e1239e08358a0359154226aec48bd43391bafb28a1b6d88d5912ae197236`.

- [ ] **Step 2: `undo_restore` (fortrydelseskommandoen; den eneste i hele ceremonien)**

```zsh
# Spec §8.2 / runbook 4.4 l. 428: samme kommando i 03 (lokalt) og 09 (prod). Ingen --single-transaction:
# fejl ved DROP af RLS-afhængige funktioner er forventede og skal kunne fortsætte.
undo_restore() { # db dump stderr-fil
  "$DAA_PG_BIN/pg_restore" --clean --if-exists --no-owner --schema=private --schema=public \
    --dbname="$1" "$2" 2>"$3" || true
  /bin/chmod 600 "$3"
}
# Fejllisten normaliseret (linjenumre og TOC-numre fjernet), sorteret; dens hash bindes i rehearsal-rapporten.
undo_errors_sha256() {
  /usr/bin/grep -E '^pg_restore: (error|warning)' "$1" | /usr/bin/sed -E 's/[0-9]+; [0-9]+ [0-9]+/N/g' \
    | LC_ALL=C /usr/bin/sort | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}
```

- [ ] **Step 3: `00-freeze.sh`** (omseg-forlæg, tilpasset)

Kontrakt:
- `begin [--accepter-forbindelser <n>]` kræver `DAA_FREEZE_RESPONSIBLE` (ikke-følsom kode). Det skriver `freeze-active.json` og `freeze-begin-<ts>.json` med mål, `started_at` og forbindelsesantal.
- `end` kræver én af:
  - `verify-ok.json` (efter `05`);
  - `undo-ok.json` (efter `09`, med `--efter-fortrydelse`);
  - `--uden-skrivning`, som kun accepteres, når tilstanden er `EMPTY`, og restore-hashen = `02`'s (eller = `begin`'s, hvis intet dump er taget).
- Ukendte argumenter giver exit 2.

- [ ] **Step 4: `02-dump.sh`** (omseg-forlæg + målinger)

Kontrakt: ingen argumenter; skrivepausen skal være aktiv. Rækkefølgen er:
1. `START`.
2. `pg_dump -Fc --no-owner` læse-kun (ikke `--no-privileges`; ACL'erne skal med).
3. Kontrol af, at målet er uændret.
4. `sql_json transfer_restore_hash.sql` og `transfer_untouched_hash.sql`.

Kvitteringen `daa-prod-<ts>.dump.receipt.json` indeholder:

```
{status: DUMP_OK, dump_path, dump_start_utc, dump_sha256, dump_bytes,
 database_target_sha256, restore_hash, untouched_hash, measured_at_utc}
```

Udskrift: `DAA_DUMP_RECEIPT=…`, `DAA_DUMP_RECEIPT_SHA256=…` og `DUMP_OK bytes=… sha256=…`.

- [ ] **Step 5: `09-undo.sh`**

Kontrakt: `--jeg-mener-det` er påkrævet. Derudover kræves `DAA_DUMP_RECEIPT` + `_SHA256` og `DAA_PREFLIGHT_REPORT` + `_SHA256` (katalog-hashen), mens `DAA_REHEARSAL_REPORT` + `_SHA256` er valgfri (giver den forventede fejlliste). Vagtrækkefølgen er:
1. `assert_no_rcs`, flag og argumenter.
2. `verify_go_hashes`, `assert_repo_clean` og `assert_expected_commit`.
3. `open_connection` og målet = det forventede.
4. Skrivepausen er aktiv fra før dumpets start.
5. Dumpets byte-hash = kvitteringens.
6. `assert_restore_privileges` (`0|0|1|1|1|1`).
7. `undo_restore "$PGDATABASE" …`.

Efterkrav:
- tilstanden er `EMPTY`;
- `restore_hash` = kvitteringens (`UNDO_RESTORE_HASH`);
- `catalog_sha256` = preflightens (`UNDO_CATALOG`);
- baselinens drift-felter = pakkens (`UNDO_BASELINE`);
- `undo_errors_sha256` = rehearsalens. Afviger kun den, er det `UNDO_ERRORS_DIFFER`: STOP med alle tal, og projektejeren vurderer. Efterkravene er beviset; fejllisten er et varsel.

Alt OK: `undo-ok.json` (bundet til pausen) og `UNDO_OK`.

- [ ] **Step 6: Syntakstjek**

```bash
cd ~/.private/2018-20-overfoersel && for f in lib.zsh 00-freeze.sh 02-dump.sh 09-undo.sh probe.zsh; do /bin/zsh -n $f || print FEJL $f; done
for f in 00-freeze.sh 02-dump.sh 09-undo.sh; do /bin/zsh -f $f --ukendt >/dev/null 2>&1; print "$f exit=$?"; done
```

Forventet: ingen `FEJL`, og exit 2 for alle tre. Kun syntaks og argumenter; adfærden øves i Task 7-8. Intet commit (kun private filer).

---

### Task 3: `01-preflight.sh`

**Files:**
- Modify: `lib.zsh` (+ `grants_fingerprint`, `assert_restore_privileges` (omseg l. 330-340))
- Create: `01-preflight.sh`

**Interfaces:**
- Consumes: `levende_counts`, `ledger_check`, `actor_check`, `classify_state`, `sql_json` (Task 1), `run_r` (Task 2).
- Produces:
  - `preflight.json`: `{status: PREFLIGHT_OK, database_target_sha256, baseline, digests_state, preconditions, grants_sha256, chars, data_codepoints, server_version_num, datctype, levende, actor_ok, role_probe, restore_privileges, measured_at_utc}`.
  - Udskrift: `DAA_PREFLIGHT_REPORT=…`, `DAA_PREFLIGHT_REPORT_SHA256=…` og `PREFLIGHT_OK`.

- [ ] **Step 1: Vagtrækkefølge**

Hver vagt har sin stopkode:
1. `assert_no_rcs`; ingen argumenter.
2. `open_connection`; mål = forventet (`DAA_EXPECTED_TARGET` i GO; ved første kørsel `DAA_PROD_TARGET`).
3. `run_r role-probe.log 01-role-probe-prod.R`, der skal give `ROLE_PROBE_OK` (`ROLE_PROBE`).
4. Baselinens drift-felter = pakkens (`TRANSFER_DRIFT` / `CLAUSE_SET_DRIFT` / `SCHEMA_DRIFT` pr. felt), og `n_interpretations_src` = 0.
5. Tilstand `EMPTY` (`TRANSFER_STATE_NOT_EMPTY`).
6. `ledger_check` og `levende_counts` (`LEVENDE_GATE`).
7. `actor_check` (`ACTOR_GATE`).
8. Restore-forudsætninger: `n_orphans_total` = 0 (`ORPHANS`), `assert_restore_privileges` (`RESTORE_PRIVILEGES`), og `catalog_sha256` gemmes.
9. `grants_sha256`: SHA over sorterede `(grantee, schema, objekt, privilegium)` for `anon` og `authenticated` fra `information_schema.role_table_grants` og `role_routine_grants`.
10. Tegnproben (som Task 1) gemmes.

- [ ] **Step 2: Kør mod stand-in**

```bash
cd ~/.private/2018-20-overfoersel && DAA_STANDIN_DB=<standin-base> /bin/zsh -f 01-preflight.sh > standin-pf.out 2>&1; tail -1 standin-pf.out
```

Forventet: `PREFLIGHT_OK`. Rolleproben kører i stand-in med `DAA_CONNECTION_MODE=local`. Intet commit.

---

### Task 4: `step_apply` og `04-apply.sh`

**Files:**
- Modify: `lib.zsh` (+ `step_apply <runmappe>`, `timed <var> <cmd…>`)
- Create: `04-apply.sh`

**Interfaces:**
- Consumes: `run_r`, `sql_json`, `read_dump_receipt`, `assert_bound_report`.
- Produces: `04-report.json` (ikke `apply.json`: det navn skriver `04-proposal-apply-prod.R` selv i runmappen, med O_EXCL), der bindes af `07`/`05`:

```
{status: APPLY_OK|ALREADY_APPLIED, state_before, state_after: PROPOSED, proposal_digest,
 attempt: 1|n, restore_hash_entry, untouched_before, dryrun_seconds, apply_seconds,
 database_target_sha256, dump_receipt_sha256}
```

- [ ] **Step 1: `step_apply`**

`step_apply <runmappe>` kører i kalderens tilstandsmappe `STEP_STATE_DIR`: `DAA_PRIVATE_DIR` i prod og rehearsal-mappen i `03`. Rækkefølgen er:
1. Mål digests ⇒ tilstand. Er den `PROPOSED`: skriv `04-report.json` med `ALREADY_APPLIED` og returnér. Er den ikke `EMPTY`: `TRANSFER_STATE_NOT_EMPTY`.
2. Manifestets fil-hash = `DAA_PREVIEW_SHA256`, indholdshash = pakkens, og claims = 3.739 (`MANIFEST_BINDING`).
3. Mål `untouched_before` (`sql_json transfer_untouched_hash.sql`).
   - **Første forsøg** (der findes ingen `$STEP_STATE_DIR/apply-first.json`): `restore_hash` = kvitteringens, og 0 `change_set` siden `dump_start_utc` (`NO_WRITE_SINCE_DUMP`). Derefter skrives `apply-first.json` (O_EXCL) med `untouched_before`, kvitteringens SHA og skrivepausens `started_at`.
   - **Genforsøg:** `apply-first.json` skal høre til samme kvittering og samme pause, og `untouched_before` = dens (`NO_WRITE_SINCE_FIRST_ATTEMPT`).
4. `timed DRY run_r dryrun.log 03-proposal-dryrun-prod.R <manifest> <runmappe>`. Krav: `DRY_RUN_OK` og `status=finalized committed=FALSE` (`DRYRUN`).
5. `timed APP run_r apply.log 04-proposal-apply-prod.R <manifest> apply <runmappe>`. Krav: `APPLY_OK` og `committed=TRUE` (`APPLY`).
6. Mål digests: tilstand = `PROPOSED`, og `proposal_digest` = pakkens (`PROPOSAL_DIGEST_MISMATCH` ⇒ runbookens fortrydelse).
7. `04-report.json`.

- [ ] **Step 2: `04-apply.sh`**

Kontrakt: `--jeg-mener-det` er påkrævet, og intet andet. Miljøet skal indeholde `DAA_EXPECTED_TARGET`, `DAA_EXPECTED_COMMIT`, `DAA_GO_HASHES_FILE`, `DAA_FREEZE_REPORT`+SHA, `DAA_PREFLIGHT_REPORT`+SHA, `DAA_DUMP_RECEIPT`+SHA og `DAA_REHEARSAL_REPORT`+SHA (status `REHEARSAL_OK`). Vagterne er I3, I4, I7 og I8. Derefter `step_apply "$(new_private_dir apply-attempt-XXXXXX)"`. Udskrift: `DAA_APPLY_REPORT=…`, `_SHA256=…` og `APPLY_OK|ALREADY_APPLIED`. Exitkoder: 0 OK, 1 STOP, 2 brugsfejl.

---

### Task 5: `step_decide`, `step_bind`, `07-decide.sh`, `08-bind.sh`

**Files:**
- Modify: `lib.zsh` (+ `actor_value` (kun i processen), `run_transfer_sql`, `step_decide`, `step_bind`)
- Create: `sql/07.sql`, `sql/08.sql`, `07-decide.sh`, `08-bind.sh`

**Interfaces:**
- Produces: `decide.json` `{status: DECIDE_OK|ALREADY_APPLIED, state_after: DECIDED, decision_digest, n_decided: 676, n_pack_sha_tagged: 676, seconds}` og `bind.json` `{status: BIND_OK|ALREADY_APPLIED, state_after: COMPLETE, binding_digest, n_bindings: 622, items_notice: 622, seconds}`.

- [ ] **Step 1: Generér skrive-SQL'en én gang og bekræft byte-hashen**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog && mkdir -m 700 ~/.private/2018-20-overfoersel/sql
/usr/bin/python3 -I .claude/skills/daa-extract/scripts/transfer_pack.py decide-sql --pack-dir ~/.private/2018-20-overfoersel/pack --out ~/.private/2018-20-overfoersel/sql/07.sql
/usr/bin/python3 -I .claude/skills/daa-extract/scripts/transfer_pack.py bind-sql --pack-dir ~/.private/2018-20-overfoersel/pack --out ~/.private/2018-20-overfoersel/sql/08.sql
shasum -a 256 ~/.private/2018-20-overfoersel/sql/0[78].sql | cut -c1-64
```

Forventet: `af7e51a7…341` og `b903896f…635` (= genafspilningens). Afviger de, er pakken eller generatoren ændret: STOP.

- [ ] **Step 2: `run_transfer_sql` (aktør på stdin, kun koder ud)**

```zsh
run_transfer_sql() { # sql-fil forventet-sha runmappe ok-markør
  expect_eq "$1: byte-hash" "$(sha256_file "$1")" "$2"
  local actor; actor="$(actor_value)"        # 1 række; hash = pakkens; ellers fail ACTOR_GATE
  local t0=$SECONDS rc
  set +e
  ( cd "$DAA_REPO" && { print -r -- "\\set actor '$actor'"; print -r -- "\\set src 1"; \
      print -r -- "SET statement_timeout = '15min';"; print -r -- "SHOW statement_timeout;"; print -r -- "\\i $1"; } \
      | write_psql -f - ) > "$3/out.txt" 2> "$3/err.txt"
  rc=$?; set -e; unset actor
  /bin/chmod 600 "$3/out.txt" "$3/err.txt"
  REPLY_SECONDS=$(( SECONDS - t0 ))
  [[ $rc -eq 0 ]] || fail "$(pg_error_code "$3/err.txt") (psql rc=$rc; intet committet, tilstanden uændret)"
  /usr/bin/grep -qx "15min" "$3/out.txt" || fail "TIMEOUT_NOT_SET"
  /usr/bin/grep -q "^$4" "$3/out.txt" || fail "OK-markøren $4 mangler"
}
```

`SET statement_timeout` står i stdin-forspillet, ikke i `sql/07.sql`/`08.sql`, så filernes byte-hashes er uændrede. Det gælder kun denne forbindelse. `SHOW` bekræfter, at værdien nåede sessionen (`TIMEOUT_NOT_SET` ellers).

`actor_value` slår uuid'en op med `readonly_psql`, tjekker antal (1) og SHA-256 mod `DAA_ACTOR_SHA256` og printer den kun til kalderens kommandosubstitution. Den logges aldrig.

- [ ] **Step 3: `step_decide` og `step_bind`**

`step_decide <runmappe>`:
1. Mål tilstanden.
2. `DECIDED` + `count(*) FILTER (WHERE decision_evidence->>'pack_sha256' = DAA_PACK_SHA256)` = 676 ⇒ `ALREADY_APPLIED`. `DECIDED` med et andet tal ⇒ `DECIDED_OTHER_PACK`. Er tilstanden ikke `PROPOSED` ⇒ `TRANSFER_STATE_NOT_PROPOSED`.
3. `run_transfer_sql sql/07.sql $DAA_07_SQL_SHA256 <run> TRANSFER_07_OK`.
4. Mål igen: tilstanden skal være `DECIDED`, og 676 skal bære pakkens hash.

`step_bind <runmappe>`:
1. `COMPLETE` ⇒ `ALREADY_APPLIED`. Er tilstanden ikke `DECIDED` ⇒ `TRANSFER_STATE_NOT_DECIDED`.
2. `run_transfer_sql sql/08.sql $DAA_08_SQL_SHA256 <run> TRANSFER_08_OK`.
3. `items_notice` udtrækkes fra `err.txt` med `^.*NOTICE: +TRANSFER_08 items=([0-9]+) uden_for_pakken=([0-9]+)$` og skal være 622 / 0.
4. Tilstanden skal derefter være `COMPLETE`.

- [ ] **Step 4: `07-decide.sh` og `08-bind.sh`**

Kontrakten er som `04-apply.sh`. Desuden kræves `DAA_APPLY_REPORT` + SHA (status `APPLY_OK|ALREADY_APPLIED`), og for `08` også `DAA_DECIDE_REPORT` + SHA. Udskrift: `DAA_DECIDE_REPORT=…` / `DAA_BIND_REPORT=…` med SHA og status.

---

### Task 6: `step_verify` og `05-verify.sh`

**Files:**
- Modify: `lib.zsh` (+ `step_verify <runmappe> <04-report.json> <preflight.json>`)
- Create: `05-verify.sh`

**Interfaces:**
- Produces: `verify.json` `{status: VERIFY_OK, state: COMPLETE, digests, n_pack_sha_tagged, baseline_equal, untouched_equal, grants_equal, anon_private_select: 0, database_target_sha256}` og `verify-ok.json` (bundet til pausen; `00-freeze end` kræver den).

- [ ] **Step 1: `step_verify` (spec §5 og §9, læse-kun)**

Hvert krav har sin kode:
- tilstand `COMPLETE` med alle tre digests og antal = pakkens (`VERIFY_STATE`);
- 676 bærer `pack_sha256` (`VERIFY_PACK_TAG`);
- baselinens tre drift-felter = pakkens; kanonisk delta 0 er `canonical_sha256` (`VERIFY_BASELINE`);
- `untouched_hash` = `04-report.json`'s `untouched_before` (`VERIFY_UNTOUCHED`);
- `grants_sha256` = preflightens (`VERIFY_GRANTS`);
- `has_table_privilege('anon', t, 'SELECT')` er falsk for `private.interpretation`, `private.interpretation_observation`, `private.interpretation_promotion` og `private.interpretation_promotion_batch` (`VERIFY_ANON`).

- [ ] **Step 2: `05-verify.sh`**

Ingen argumenter. Kræver GO-miljøet + `DAA_BIND_REPORT` + SHA (status `BIND_OK|ALREADY_APPLIED`). Skriver `verify.json` og `write_marker verify-ok …`. Udskrift: `VERIFY_OK`.

---

### Task 7: `03-rehearsal.sh` (samme bytes, lokal base, øvet fortrydelse)

**Files:**
- Create: `03-rehearsal.sh`

**Interfaces:**
- Consumes: alle `step_*`, `undo_restore`, `undo_errors_sha256`, `go_hashes_lines`.
- Produces:
  - `rehearsal-<ts>-XXXXXX/rehearsal.json` med `{status: REHEARSAL_OK, dump_sha256, dump_receipt_sha256, repo_commit, go_hashes_sha256, preflight_report_sha256, rehearsal_database, digests, seconds: {restore, dryrun, apply, decide, bind, undo}, undo_errors_sha256, undo_n_errors, restore_hash_fresh_equal: true, after_undo: {state, restore_hash_equal, catalog_equal, baseline_equal}, database_target_sha256}`;
  - `go-hashes.txt`, 33 linjer;
  - udskrift: `DAA_GO_HASHES_FILE=…`, `DAA_REHEARSAL_REPORT=…` + SHA og `REHEARSAL_OK`.

- [ ] **Step 1: Kontrakt og rækkefølge**

1. Ingen argumenter. Kræv `DAA_DUMP_RECEIPT`+SHA, `DAA_PREFLIGHT_REPORT`+SHA (status `PREFLIGHT_OK`), `DAA_EXPECTED_TARGET` (prods eller stand-ins) og `DAA_EXPECTED_COMMIT`. Kør `assert_repo_clean` og `assert_expected_commit`. Skriv `go-hashes.txt` og verificér den.
2. Opret Supabase-rollerne lokalt, hvis de mangler (omseg 03 l. 33-39). `createdb daa44_rehearsal_transfer_<ts>_r`. `pg_restore --clean --if-exists --no-owner` af dumpet. Andre fejl end vault ⇒ `RESTORE_ERRORS`.
3. **Målet skiftes:** rehearsal-basen har sin egen mål-identitet. Lige efter restoren sættes `CTX_TARGET="$(raw_target_identity)"` (som omseg `03` l. 47), og den skal være ≠ `DAA_PROD_TARGET`. Fra her bruger `step_*` og `run_r` det **aktuelle** mål (`CTX_TARGET`), aldrig GO-konstanten `DAA_EXPECTED_TARGET`, der kun binder dumpets oprindelse. Ellers stopper R-filerne på `DAA_TARGET_MISMATCH`.

   Restoren skal være trofast mod kvitteringen: `restore_hash` og `untouched_hash` = kvitteringens. Baselinens drift-felter og `catalog_sha256` = preflightens, og 0 afvigende kodepunkter mellem rehearsal-basen og preflightens `chars` inden for datamængden (som G2) (`REHEARSAL_FIDELITY`). Tilstand `EMPTY`.
4. Med `DAA_RUN_MODE=local` mod rehearsal-basen: `step_apply` → `step_decide` → `step_bind` → `step_verify`. Varighederne gemmes.
5. **Fortrydelsesøvelse (spec §6.1 trin 4b):**
   - `undo_restore` af samme dump oven på den befolkede base, med hele fejllisten gemt;
   - `undo_errors_sha256` og antal;
   - tilstand `EMPTY`;
   - `restore_hash` = kvitteringens (prods måling fra `02`);
   - `catalog_sha256` = preflightens (prods eget katalog fra `01`);
   - baseline = pakkens.
6. **Varighed (spec §6.1 trin 4c, grænser fastsat her; strammet 4/10):** dry-run, apply, `07` og `08` ≤ 30 s hver lokalt (`DURATION_LIMIT`). Prod afbryder enkeltsætninger efter 2 min; et helt trin på ≤ 30 s giver mindst 4× luft for hver sætning i det. `07`/`08` sætter desuden selv 15 min (Task 5). R-trinnene (hash-låste) har kun luften. Overskrides 30 s: STOP og spørg.
7. `rehearsal.json`. Basen bevares som bevis.

- [ ] **Step 2: Syntakstjek og argumenttest**

```bash
/bin/zsh -n ~/.private/2018-20-overfoersel/03-rehearsal.sh && /bin/zsh -f ~/.private/2018-20-overfoersel/03-rehearsal.sh --x >/dev/null 2>&1; print exit=$?
```

Forventet: `exit=2`.

---

### Task 8: Stand-in-ceremoni, fejlinjektion og angrebstests (lokalt, 0 prod)

**Files:**
- Create: `~/.private/2018-20-overfoersel/standin/koer-standin.zsh` (driver; ikke i GO)

**Interfaces:**
- Consumes: alle scripts. Stand-in-basen fra Task 1, genskabt ren (fersk restore af 1/10-dumpet, intet manipuleret).

- [ ] **Step 1: Hele ceremonien mod stand-in**

`DAA_STANDIN_DB=<standin-base>`. Driveren kører de samme kommandoer, som runbooken giver projektejeren, i rækkefølge, og fører GO-miljøet videre fra hver udskrift:
1. `00 begin`.
2. `01`.
3. `02`.
4. `03` (restorer stand-in-dumpet i en ny `_r`-base).
5. `04`, `07` og `08` med `--jeg-mener-det`.
6. `05`.
7. `00 end`.

Forventet:
- `PREFLIGHT_OK`, `DUMP_OK`, `REHEARSAL_OK`, `APPLY_OK`, `DECIDE_OK`, `BIND_OK` og `VERIFY_OK`;
- digests = pakkens (`bb808efe…`, `33fc4b56…`, `5762ceaa…`), 676/622.

- [ ] **Step 2: Genkørsel efter commit (Review Focus 3)**

`04`, `07` og `08` køres igen. Forventet tre gange `ALREADY_APPLIED`, exit 0 og uændrede digests.

- [ ] **Step 3: Afbrud i `04` (Review Focus 2)**

1. Ny ren stand-in. `00 begin` → `01` → `02` → `03`.
2. `DAA_FAULT=apply:after_authorize 04-apply.sh --jeg-mener-det` ⇒ STOP (R exit 97).
3. Tilstanden er `EMPTY`. Genkørsel uden `DAA_FAULT` ⇒ `APPLY_OK` med `attempt: 2` (genforsøgsgaten `NO_WRITE_SINCE_FIRST_ATTEMPT` holder).
4. Ny ren stand-in. `DAA_FAULT=apply:after_execute` ⇒ STOP. Tilstanden er `PROPOSED`. Genkørsel ⇒ `ALREADY_APPLIED`, derefter `07` → `08` → `05` = `VERIFY_OK`.

Afviger noget af dette (fx at serveren afviser en ny autorisation, efter at en udstedt er efterladt ubrugt): STOP. Notér, og ret kontrakten i planen med en ruling, før der fortsættes.

- [ ] **Step 4: Forkert grundlag giver STOP uden skrivning (Review Focus 1 og 3)**

GO-vagterne er testet i Step 6. Her tester driveren trinfunktionerne direkte, som `03` gør (I1): den sourcer `lib.zsh` med `DAA_RUN_MODE=local` mod en kopi (`createdb -T`) af en stand-in-base og kalder `step_decide`/`step_bind`:
- **(a)** I `PROPOSED`: én værdi ændret i en baseline-tabel, som klassifikationen læser (`public.assertion`/`public.fact`) ⇒ `step_decide` = `MACHINE_PREMISE_DRIFT`.
- **(b)** I `PROPOSED`: redaktionsprofilens `rolle` ændret, så der er 0 `redaktion` ⇒ `ACTOR_GATE`.
- **(c)** `step_decide` i `EMPTY` ⇒ `TRANSFER_STATE_NOT_PROPOSED`.
- **(d)** `step_bind` i `PROPOSED` ⇒ `TRANSFER_STATE_NOT_DECIDED`.

Hver gang skal digests være uændrede bagefter.

- [ ] **Step 5: Fortrydelse i stand-in (Review Focus 4)**

På stand-in i `COMPLETE`: `09-undo.sh --jeg-mener-det` ⇒ `UNDO_OK`. Tilstanden er `EMPTY`. `undo_errors_sha256` = rehearsalens. `00 end --efter-fortrydelse` lykkes.

- [ ] **Step 6: Angrebstests (Review Focus 5)**

Køres med `HOME=$T`, hvor `$T/.Renviron` har `SUPABASE_HOST=127.0.0.1` og `SUPABASE_PORT=1`, og `$T/.private/2018-20-overfoersel/prod` er tom. Pooler-kravet stopper derfor ethvert forbindelsesforsøg, før en socket åbnes (`POOLER_REQUIRED`). Tests, hvis vagt ligger før forbindelsen, skal give deres egen kode og ikke `POOLER_REQUIRED`; det viser rækkefølgen. Scripts og pakke peges ind via faste stier i lib, ikke via `HOME`. Hver test skal give navngivet STOP eller exit 2 **uden** en forbindelse:

| # | Angreb | Forventet |
| --- | --- | --- |
| 1 | `04-apply.sh` uden flag / med ekstra argument | exit 2 |
| 2 | `zsh` uden `-f` | exit 2 (`koer med /bin/zsh -f`) |
| 3 | `DAA_FAULT=x 04-apply.sh --jeg-mener-det` | `FAULT_IN_PROD` |
| 4 | `DAA_REIMPORT_ACTOR_ID=x` | `ACTOR_ENV_INHERITED` |
| 5 | `DAA_LOCAL_PGHOST=x` | `LOCAL_ENV_IN_PROD` |
| 6 | GO-hashfil med én linje fjernet / én ekstra / én ændret | `fil-hashes afviger fra GO-pakken` |
| 7 | `DAA_EXPECTED_COMMIT` forkert | `repo-commit afviger` |
| 8 | `PGHOSTADDR=127.0.0.1 PGOPTIONS='-c default_transaction_read_only=off'` sat, `01-preflight.sh` | ryddes; derefter `POOLER_REQUIRED` (test-`.Renviron`) — ingen socket åbnes |
| 11 | test-`.Renviron` med `SUPABASE_HOST=db.example.supabase.co` (direkte forbindelse, ikke pooler) | `POOLER_REQUIRED` |
| 9 | `PYTHONOPTIMIZE=2` | uændret adfærd (PY rydder den) |
| 10 | `09-undo.sh` uden aktiv skrivepause | `skrivepausen er ikke aktiv` |

- [ ] **Step 7: Notér i ændringsloggen og commit**

Tal, koder og forkortede hashes: varigheder, `undo_n_errors`, udfald pr. test.

```bash
git add docs/superpowers/plans/2026-10-04-trin4-2018-20-overfoersel-b-ceremoni.md
git commit -m "docs(147): plan B — stand-in-ceremoni REHEARSAL_OK, fejlinjektion og angrebstests"
```

---

### Task 9: Runbook

**Files:**
- Create: `docs/runbooks/transfer-2018-20-prod.md`
- Modify: `docs/evidensbaseret-genimport/status.md` (én linje), `docs/changelog.md` (én linje)

- [ ] **Step 1: Skriv runbooken**

Afsnit, i rækkefølge:
1. **Formål og forudsætninger**: pakke, plan A/B, skrivepause, ingen andre skrivere. `DAA_REPO` er **hovedcheckouten** (`/Users/johanreventlow/TypeScript/danmarksadelsaarbog`) på `main` ved GO-commit'en, ikke en worktree. Den står i dag på `docs/147-overfoersel-spec`, så den skal flyttes før `01`. `assert_expected_commit` fanger det, men runbooken skal forhindre det.
2. **Proben** (Task 1) og dens gates.
3. **Ceremonien** som nummererede `! /bin/zsh -f …`-kommandoer. Før hver står én linje »hvad det betyder«, efter hver det forventede udfald. `go-env.txt` (kun stier og hashes) opbygges trin for trin.
4. **GO-pakken (spec §7)**: hvad projektejeren ser før GO (alle tal og hashes fra `rehearsal.json`, inventarets 33 linjer, commit), og hvad GO binder.
5. **Stopregler**: tabellen over tilstande × næste skridt (spec §5), `04`'s tre afbrudsudfald og hvad en `UNDO_ERRORS_DIFFER` kræver.

   Fejllisten ved en fortrydelse i prod vil **næsten sikkert afvige** fra den lokale, fordi realtime-/graphql-afhængigheder kun findes i prod. Beviset er efterkravene: tilstand `EMPTY`, restore-hash, katalog og baseline. En afvigende fejlliste med opfyldte efterkrav vurderes af projektejeren og er ikke i sig selv en fejl.
6. **Fortrydelse**: `09-undo.sh`, prisen (alt skrevet i `private`/`public` efter dumpets start går tabt), og at de RLS-afhængige funktioner hverken droppes eller genskabes.
7. **Efter `VERIFY_OK`**: modenhedsløft (spec §9), omsegmenteringens fortrydelsesvindue lukket (decisions 2026-10-01), og oprydning kun efter måling og ja.

- [ ] **Step 2: Statuslinjer og commit**

```bash
git add docs/runbooks/transfer-2018-20-prod.md docs/evidensbaseret-genimport/status.md docs/changelog.md
git commit -m "docs(147): runbook for prod-overførslen af 2018-20"
```

---

## Efter planen (ikke en del af den)

1. **Review af scripts og runbook.** Kræver projektejerens ja til, hvem der må læse de private scripts, for de ligger i `~/.private`, selv om de ikke rummer data. Muligheder: en Opus-agent eller Codex på en kopi af kun de 16 private kodefiler i en scratchmappe, greppet for persondata før kopiering, eller intet eksternt review.
2. **Ceremonien** i én session på projektejerens GO: `00 begin` → `01` → `02` → `03` → GO → `04` → `07` → `08` → `05` → `00 end`.
3. **Oprydning** (måling først, ja før sletning): stand-in-, probe- og rehearsal-baser samt forældede private mapper fra plan A.

## Ændringslog

- 2026-10-04: første udgave. Udgangspunktet er målt:
  - levende-gaten `471|471|471|471|471` i restoren;
  - aktørens hash = pakkens;
  - R-filernes kontrakt og R-filerne, der genbruges uændret (ingen hardkodede pilottal);
  - transitive inkluderinger (scoped → targets; R → `apply_reimport_helpers.R` + profil-JSON).
- 2026-10-04: Selvreview og rådgiver-review før overdragelse:
  - Trinrapporten hedder `04-report.json`, fordi R-filen selv skriver `apply.json` med O_EXCL.
  - `03` skifter til rehearsal-basens eget mål (`CTX_TARGET`).
  - Tegnproben gater kun på kodepunkter i datamængden; hele intervallet ville give falsk STOP mellem glibc og macOS-libc. Negativtesten kræver `-E UTF8`.
  - Pooler-kravet håndhæves i shell'en (`POOLER_REQUIRED`), og angrebstest 11 er tilføjet.
  - Proben bruger fundamentets funktioner (`classify_state`, levende, aktør, ledger).
  - Første forsøg i `04` bindes af `apply-first.json`.
  - Runbooken skal nævne `DAA_REPO` = hovedcheckouten på `main`, og at fortrydelsens fejlliste i prod forventeligt afviger.
- 2026-10-04: Prod-proben målt (Task 1 Step 5). G1 OK (prod 170006, lokal 170010); G2 OK (0 afvigende kodepunkter i data, 10 i alt uden for data, ctype en_US.UTF-8 begge); G3 OK (tre drift-felter = pakken, n_src 0); G4 OK (EMPTY); G5 OK (katalog ens, orphans 0/0, multi_fk 14/14); G6 OK (n=1); G8 OK (471×5). I1: restore- og uberørt-hash = lokal; 0 change_sets siden dumpet.
  - G7 afveg: prods `statement_timeout` er 2min (ikke i `rolconfig`), idle 0, lock 0. Projektejerens beslutning: prod-indstillingen røres ikke. G7 kræver nu ≥ 120 s; rehearsal-grænsen er strammet til ≤ 30 s pr. trin; `run_transfer_sql` sætter selv `statement_timeout = '15min'` i stdin-forspillet og bekræfter det med `SHOW`. Rammer et R-trin alligevel grænsen, rulles den aktuelle transaktion tilbage; en mellemtilstand håndteres af tilstandsklassifikationen og `09-undo`.
- 2026-10-05: Task 2-8 udført (private scripts; stand-in, 0 prod). Endelige bytes: `lib.zsh` `4b8ce9fa…`, GO-sæt (33 linjer) `0e936efd…` i den sidste stand-in-rehearsal.
  - **Stand-in-ceremoni (Step 1):** `PREFLIGHT_OK`, `DUMP_OK`, `REHEARSAL_OK`, `APPLY_OK`, `DECIDE_OK`, `BIND_OK`, `VERIFY_OK`, `FREEZE_END_OK`; digests = pakkens (`bb808efe…`, `33fc4b56…`, `5762ceaa…`), 3.739/676/622. Også kørt med runbookens egne `koer.zsh`-kommandoer (go-env 20 gyldige linjer). Varigheder lokalt: restore 2 s, dry-run 12-15 s, apply 10-12 s, `07` 16-17 s, `08` 3-4 s, fortrydelse 2-6 s; `undo_n_errors` 5 (`620b9304…`).
  - **Genkørsel (Step 2):** `04`, `07`, `08` igen ⇒ tre gange `ALREADY_APPLIED`, tilstand `COMPLETE` uændret.
  - **Afbrud (Step 3):** `apply:after_authorize` ⇒ STOP (R 97), `EMPTY`, genforsøg `APPLY_OK` med `attempt: 2`. `apply:after_execute` ⇒ STOP, `PROPOSED`, genkørsel `ALREADY_APPLIED`, `07`→`08`→`05` = `VERIFY_OK`.
  - **Forkert grundlag (Step 4):** (a) `MACHINE_PREMISE_DRIFT`, (b) `ACTOR_GATE`, (c) `TRANSFER_STATE_NOT_PROPOSED`, (d) `TRANSFER_STATE_NOT_DECIDED`; digests uændrede alle fire gange.
  - **Fortrydelse (Step 5):** `09` ⇒ `UNDO_OK` (`COMPLETE`→`EMPTY`, fejlliste = rehearsalens), `00 end --efter-fortrydelse` OK.
  - **Angrebstest (Step 6):** 11/11 navngivet STOP eller exit 2 uden forbindelse (1-2 exit 2; 3 `FAULT_IN_PROD`; 4 `ACTOR_ENV_INHERITED`; 5 `LOCAL_ENV_IN_PROD`; 6 `GO_HASHES` ×3; 7 `COMMIT_MISMATCH`; 8 og 11 `POOLER_REQUIRED`; 9 uændret; 10 `FREEZE_NOT_ACTIVE`).
  - **Rulings undervejs:** `04` melder `ALREADY_APPLIED` også i `DECIDED`/`COMPLETE`; `03` kører `ANALYZE` efter troskabstjekkene (uden statistik gav `07` 30 s mod 16 s); miljø- og pausefil-tjek før forbindelse (test 10 krævede det); `run_r` giver R den faste hovedcheckout som `DAA_REPO`; `02` binder kvitteringen i pausen; `koer.zsh` (uden for GO) bærer GO-miljøet, og mål/commit gemmes med `--saet`.
  - **Fund:** én af 14 kørsler hang 15 min i `07`'s klassifikation og blev afbrudt af trinnets egen tidsgrænse (rollback, tilstand uændret). Ikke genskabt: forældet statistik (`reltuples` 0/-1) og den præcise rækkefølge gav 14-15 s; en genkørsel med prøvetagning af `pg_stat_activity` var grøn. Ingen rettelse i prod-stien; `pg_error_code` giver nu `STATEMENT_TIMEOUT`, og runbooken har en stopregel for det.
- 2026-10-05: Endelig review (Opus, på en kopi af kun kodefilerne efter PII-grep): "With fixes". Rettet, hver med en test, der fejlede før og bestod efter:
  - **C1:** fortrydelsen efterlod anon/authenticated-adgang. Prods dump har `DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public`, og en restore som `postgres` genskaber objekterne med de rettigheder. Efterlignet lokalt: anon kunne læse 4 private kædetabeller, og 415 grants afveg. Preflighten gemmer nu den fulde grants-liste (`aclexplode`; anon, authenticated, PUBLIC). `09` og `03` afstemmer efter restoren og kræver `UNDO_GRANTS` og `UNDO_ANON`.
  - **I1:** `09` kan køres igen efter en afbrudt restore. Førmålingen giver `UNMEASURABLE` i stedet for at stoppe.
  - **I2:** `02` dumper kun i `EMPTY`. `09` kræver, at kvitteringen er den samme som i `04`'s første forsøg.
  - **I3:** `ANALYZE` af kædens fire tabeller før `07` og `08`, plus en `EXPLAIN` af klassifikationen til diagnose. ANALYZE ændrer ingen af gaternes hashes (målt).
  - **I4:** en fortrydelse noteres i pausen, og de skrivende trin giver derefter `UNDO_IN_THIS_FREEZE`. `00 begin` flytter den forrige forsøgsbinding til side.
  - **I5:** ikke rettet (ruling i ledgeren). Otte minor-fund er udskudt.
  - **Hele suiten kørt igen med de endelige bytes** (`lib.zsh` `983c00fa…`, GO-sæt `70c8f9ea…`): A, B, C, runbook-vejen, D 4/4 og angreb 11/11 er grønne. Afstemningen giver 0|0 i stand-in.
