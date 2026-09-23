# 4.4 prod-wrapper — første `interpretation_proposal`-kørsel i prod: plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (native) to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En øvet, hash-bundet og fail-closed prod-procedure (runbook + private scripts),
der lader projektejeren skrive 4.3b's 84 fortolkningsforslag som `proposed` i prod og
bevise resultatet med #196's projektion og komparator.

**Architecture:** Samme form som 4.1c (`docs/runbooks/clause-evidence-prod-apply.md` +
`~/.private/148c-prod/`): syv private scripts `00-freeze … 06-recover` med fælles
`lib.zsh`, tre hærdede R-scripts (rolleprobe, dry-run, apply/replay), restore-rehearsal af netop dagens dump med lokal
fortrydelsesøvelse, og en committed runbook. Forskellen er 4.4-kæden: dry-run →
profil-readback → før-projektion → apply → efter-projektion → fresh-komparator → replay med
ny autorisation → replay-projektion → replay-komparator, med operation og autorisation i
hver sin rolle-transaktion som i #196's CI-bevis.

**Tech Stack:** zsh, psql 17, R (DBI/RPostgres), Python 3 (`-I`), Supabase Session pooler.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md`
§7 (proposed-ingest), §7.4/§11.5 (fortrydelse), §11.1 (projektion). Beslutning:
`docs/decisions.md` »4.4's forslags-kørsel i prod fortrydes kun ved restore« (2026-09-23).
Forlæg: `docs/runbooks/clause-evidence-prod-apply.md`, `~/.private/148c-prod/`,
`tests/integration/test-reimport-interpretation-proposal.R`.

## Revisionslog

**v2 (2026-09-23) — efter Codex sol runde 1 (NO-GO, 6 blokerende + 3 major).** Alle ni
fund verificeret i koden før rettelse.

| Fund | Verificeret i | Rettelse | Sted |
|---|---|---|---|
| B1 profilversion | profil-JSON `"profile_version": "1.0.0"`; CI hardkoder `'interpretation-proposal-v1'` (`test-…-proposal.R:100`) | `DAA_PROFILE_FILE_VERSION="1.0.0"` er den eneste version, der indsættes og readback-valideres; writeren læser den aldrig (skriver literal `'interpretation-proposal-v1'` som `schema_version`, `schema.sql:3670-3676`) | Global Constraints, Task 1 Step 2, Task 2 Step 4 |
| B2 aktør via miljø | gatewayens `preflight` læser `DAA_REIMPORT_ACTOR_ID` (`apply_reimport_helpers.R:333-336`); 148c sætter den i linje 71, uden for den kopierede præambel 1-60 | nedarvet værdi → STOP før forbindelse; sæt efter entydighedstjek (lever kun i R-processen); skallerne `unset` den | Task 2 Step 2 |
| B3 ukendt commit-udfald | `apply.json` skrives først efter commit; 04's tomhedsporte kan ikke genkøres efter dry-run | `apply-intent.json` før apply-kaldet; nyt `06-recover.sh` med tre udfald og autorisationstabel | Task 4 Step 1, 3, 6; Autorisationstabel |
| B4 dry-run-vask | CI kræver byte-identisk projektion før/efter dry-run (`test-…-proposal.R:228-236`); komparatoren kræver præcis én ny autorisation (`compare_…py:729-733`) | `pre-dry.json` før dry-run + `assert_projection_delta`: lig `before.json` efter fjernelse af præcis den ene dry-run-autorisation | Task 4 Step 1 |
| B5 freeze er kun markører | `00-freeze.sh:34-61` tæller forbindelser, stopper intet | skrivepausen *bevises*: prod-tilstands-hash i dump-kvitteringen, genberegnet i 04 før første skrivning; ikke-berørte-tabeller-hash 04→05 | Task 1 Step 6, Task 4 Step 3-4, Task 6 |
| B6 én login, to roller | `red_authorize_reimport` kun til `service_role`, apply-RPC'er kun til `authenticated` (`schema.sql:4391-4392`); prod har kun bevist `service_role` (148c `04-clause-apply-prod.R:93`) | `01-role-probe-prod.R` i rollback-transaktioner: begge roller, claim-livscyklus, negative ACL'er; køres i 01 og igen i 04 før første skrivning | Task 2 Step 6, Task 3 |
| M7 05 ubundet | 148c `05-verify.sh:10-19` kræver rapport + hash | `apply-receipt.json` (O_EXCL, 0600) med alle filhashes; 05 kræver sti + hash | Task 4 Step 3-4 |
| M8 preflight < writerkrav | writeren kræver 1 anker, 1 parent, aktivt prædikat/kind/value-form, ny nøgle, `machine`-disposition med provenance (`schema.sql:3653-3775`) | pr. claim/pr. klausul anti-joins genereret fra manifestet | Task 3 Step 1.7 |
| M9 levende fail-open | spec §9.2 linje 608: »levende eller uafklaret« udelukkes | fem kardinaliteter, krav `8\|8\|8\|8\|8` | Task 3 Step 1.8 |

**v3 (2026-09-23) — efter Codex sol runde 2 (NO-GO; B1, B2, B6, M7, M9 LUKKET; B3, B4, B5,
M8 DELVIST; 2 blokerende + 4 major nye).** Alle seks verificeret i koden før rettelse.

| Fund | Verificeret i | Rettelse | Sted |
|---|---|---|---|
| R2-1 R-kald uden miljø | 148c giver hvert R-kald eksplicit miljø (`03-restore-rehearsal.sh:117-120`); v2's sekvens kaldte `Rscript` bart, så `DAA_PREVIEW_SHA256` (ikke-eksporteret) aldrig nåede R | `run_r`: `/usr/bin/env -i` + lukket, mode-specifik allowlist; intet nedarves | Task 4 Step 1 |
| R2-2 hash ≠ restore-troskab | `state-hash.sql` tager kun `relkind='r'`; sekvenser mangler; v2 tillod at udelukke volatile tabeller | to hashes: `restore_hash` (alle tabeller + sekvenser, ALDRIG eksklusioner; volatil = STOP) og `untouched_hash` (kun neutralitet) | Task 1 Step 6-7, Task 4 |
| R2-3 06 dækker ikke alle afbrydelser | komparatorens rapportsti er O_EXCL (`compare_…py:1135-1148`) | 06 = artefakt-tilstandsmaskine; genoptager ALTID i en child-runmappe med validerede artefakter kopieret og hash-bundet | Task 4 Step 6 |
| R2-4 profilrækken usynlig | projektionen har ingen `writer_profile`-rækker; `untouched_hash` udelukker tabellen | privat `writer-profiles.sql`-snapshot i hvert projektionspunkt; delta = præcis den forventede række | Task 4 Step 1 |
| R2-5 autorisations-baseline | `status` skifter ikke selv til `expired` (`schema.sql:2766-2783`); preflight tjekkede kun aktive | preflight kræver 0 autorisationer i ALLE statusser bundet til manifest `a328ede9…`; tabellen tæller kun manifest-bundne; øvrige er baseline i `pre-dry.json` | Task 3, Autorisationstabel |
| R2-6 writerkrav + manifest | writerens `extraction_run`-driftvagt (`schema.sql:3668-3677`) manglede; `validate_manifest` kaldte ikke komparatorens fulde validering (`compare_…py:340-385`) | preflight: 0 `extraction_run` med manifestets run-keys; `validate_manifest` kalder komparatorens `validate_manifest` | Task 1 Step 3, Task 3 |

Valg truffet i v2 (ingen blokerer): **B6 én login + rollebevis** frem for to nye prod-logins
(nye DB-roller i prod = ny overflade; `service_role` allerede bevist 18/9). **B5 detektion,
ikke forhindring:** Supabase free-tier har ingen vedligeholdelsesport, og en rolle-/database-
bred `read_only` ville også ramme kørslen selv; hashen beviser direkte »ingen skrivning
siden dump«, som er netop restore-risikoen.

## Roadmap-adgangskrav (roadmap.md, seks spørgsmål)

1. **Roadmapmål:** trin 4 — den fælles fortolkningskæde (#147), leverance 4 (proposed-ingest).
2. **Værdikædeled:** observation → *fortolkning*: forslag bundet til klausuler står i prod
   som `proposed`, klar til 4.5's menneskelige afgørelse.
3. **Leverancetype:** generel mekanisme (writer, projektion, komparator er editionsneutrale);
   manifestet og tallene er 2018-20-profilens.
4. **Værdi:** 4.5 kan køre sin pilot mod prod-data i stedet for en restore; redaktionen får
   rigtige forslag at afgøre.
5. **Færdigbevis:** denne plan er færdig ved `REHEARSAL_OK` mod en stand-in af prod (Task 5),
   Codex-GO på scripts og runbook (Task 7) og en committed runbook. Prod-kørslen selv er
   projektejerens GO-gate efter planen og løfter først da rækken »Proposed-ingest og
   promotion« (kun ingest-halvdelen; promotion forbliver dry-run).
6. **Erstatter:** `~/.private/44-rehearsal-scripts/44-*.R` som kørselsvej (de genautoriserer
   pr. kørsel og mangler `--jeg-mener-det`). Ingen permanent overflade erstattes.

## Global Constraints

- Ingen prod-forbindelse fra AI-sessionen. Projektejeren kører trin 1 og 3 i egen shell.
- AI'en læser aldrig manifestets payload, cache, runner-input eller rå komparatorrapporter —
  kun rensede rapporter med tal, koder og hashes. Probe-kørsler omdirigerer stdout+stderr
  til fil og greppes for navngivne markører.
- Manifest: `~/.private/43b-kørsel/proposal-manifest.json`, fil-SHA-256
  `c310ca6325b5a3a10c895a0f80161a51a0c24b61c902b807d34c7f8433c65aad`, indholdshash
  `a328ede946140a1223be3077d18579d94f763812875a55d67abed00645313cf8`. Genbygget
  2026-09-23 med `main`'s builder: byte-identisk. Må ikke genbygges i kørslen.
- Profil: `daa-2018-20-interpretation-proposal-v1`, writer-config-hash
  `4e39fff44db0cdab7ff35d59fe852f317dc608e818c4b2dd8ff060190fdc625c`, filversion
  `"1.0.0"` (`DAA_PROFILE_FILE_VERSION`). Det er den værdi, der indsættes i
  `reimport_writer_profile.profile_version` og readback-valideres. `interpretation-proposal-v1`
  er IKKE en profilversion: writeren skriver den som literal `schema_version` på
  `extraction_run`/`interpretation` og læser aldrig profilrækkens version.
- Aktør: den ene `redaktion`-profil. Sættes kun af R-scriptene selv
  (`DAA_REIMPORT_ACTOR_ID`); en nedarvet værdi i miljøet er en stopport.
- Én prod-login (Session pooler). Rollerne skiftes kun med `SET LOCAL ROLE` i hver sin
  transaktion: `authenticated` til operationen, `service_role` til autorisation. Begge
  bevises i rollback-transaktioner før første skrivning (Task 2 Step 6).
- Forventede tal (fra 4.4-rehearsal 2026-09-14, genmåles i Task 5): 8 elementer, 84 claims,
  88 links, 68 `principal` / 16 `other`, dispositioner 13 `fortolkning_foreslaaet` +
  6 `afventer_identitet`, nul kanonisk delta, `anon` uændret.
- `preview_sha256` := manifestfilens byte-SHA-256 (`c310ca63…`). IKKE 4.1c's
  `digest(manifest_path)` — det hasher stiens tekst, ikke filen.
- Hvert script: `set -euo pipefail`, `umask 077`, `PGTZ=UTC`; ryd alle nedarvede `PG*`
  inkl. `PGHOSTADDR`; indlejret Python kun som `/usr/bin/python3 -I` med eksplicitte
  `raise SystemExit` (aldrig `assert`).
- Læse-kun kald: `PGOPTIONS='-c default_transaction_read_only=on'` pr. kommando.
- `db-verify` kører kun mod disponerbare baser (#198). `COLLATE "C"` ved al ordnet hashning.
- Private filer 0600, mapper 0700, i `~/.private/147-44-prod/`. Scripts committes ikke.
- Indekset til `interpretation_predicate_fk` hører ikke til denne kørsel (84 rækker er ikke
  skala); runbookens §9 fastholder at det skal på før skala-kørsel.

## Review Focus

1. **Forbindelsen forsvinder omkring apply-commit** → `06-recover.sh` klassificerer læse-kun
   bundet til manifest-hash, mål, profil og `apply-intent.json`; præcis tre udfald, og kun
   »intet commit« må udstede en ny autorisation (Task 4 Step 6, Autorisationstabel).
2. **Dry-run eller en fremmed skrivning »vaskes« ind i før-projektionen** →
   `assert_projection_delta` (Task 4 Step 1) og prod-tilstands-hashen fra dumpet (Task 4
   Step 3).
3. **Replay-trinnet kører på et forkert grundlag** (efter-projektion taget efter replay, eller
   autorisation genbrugt) → replay-komparatoren skal fejle `REPLAY_DRIFT` (Task 4 negativ).
4. **Arvet miljø** (`PGHOSTADDR`, `PYTHONOPTIMIZE`, `PGOPTIONS`, `DAA_REIMPORT_ACTOR_ID`)
   slår en stopport fra → rehearsal med dem sat giver uændret resultat eller navngivet STOP
   (Task 5).
5. **Writerens forudsætninger holder ikke i prod** (citater, anker, parent, prædikat,
   nøgle, disposition) → preflight spejler hvert writerkrav før enhver skrivning (Task 3).
6. **En levende eller uafklaret person blandt de 8 records** → preflight kræver `8|8|8|8|8`
   (Task 3); ellers STOP.

---

## Filstruktur

Private (`~/.private/147-44-prod/`, ikke i git):

| Fil | Ansvar |
|---|---|
| `lib.zsh` | faste stier/hashes, forbindelse, målbinding, manifest-/profil-/GO-hash-validering, `run_proposal_sequence` + `continue_after_apply` (fælles for 03, 04 og 06), `assert_projection_delta`, `assert_report_chain`, `sanitize_report`, `write_apply_receipt` |
| `00-freeze.sh` | skrivepause begin/end: ansvarskode, forbindelsesantal, markører (148c-logik); `end` binder til apply-kvitteringen. Selve pausen *bevises* af tilstands-hashen (02 → 04 → 05) |
| `01-preflight.sh` | læse-kun: mål, rolleprobe, 4.1c-forudsætning, tomhed, writerkrav pr. claim/klausul, persona/identitet/levende, forældreløse, redaktion=1 |
| `02-dump.sh` | læse-kun dump + kvittering med prod-tilstands-hash før og efter dumpet (skal være ens) |
| `03-restore-rehearsal.sh` | lokal restore af dagens dump, fuld sekvens, fejlinjektion af begge recovery-udfald, verify-SQL, db-verify, fortrydelsesøvelse |
| `04-apply.sh` | `--jeg-mener-det`; bindinger; tilstands-hash = dumpets; rolleprobe; `run_proposal_sequence` mod prod; apply-kvittering |
| `05-verify.sh` | kræver apply-kvittering + hash; læse-kun slutprojektion, ikke-berørt-hash, genkørsel af begge komparatorer, `verify.sql` |
| `06-recover.sh` | kun efter en afbrudt 04: læse-kun klassifikation → genoptag eller NO-GO |
| `01-role-probe-prod.R` | rollebevis i rollback-transaktioner (ingen skrivning) |
| `03-proposal-dryrun-prod.R` | profilrække (varig) + dry-run-autorisation + dry-run; skriver `dryrun.json` |
| `04-proposal-apply-prod.R` | apply/replay med ekstern autorisation i egen rolle-transaktion; skriver `apply-intent.json` før kaldet |
| `verify.sql`, `rollback-preflight.sql` | læse-kun SQL (sidste kopieret fra 148c) |
| `restore-hash.sql` | alle tabeller + sekvenser i `private`+`public`, ingen eksklusioner: »ingen skrivning siden dump« og restore-troskab |
| `untouched-hash.sql` | samme minus den hardkodede 4.4-tabelliste: neutralitet 04 → 05 |
| `writer-profiles.sql` | kanonisk snapshot af alle `reimport_writer_profile`-rækker (projektionen har dem ikke) |

Repo (committes):

| Fil | Ansvar |
|---|---|
| `docs/runbooks/interpretation-proposal-prod-apply.md` | autoritativ procedure, GO-pakke, stopregler, fortrydelse |
| `docs/superpowers/plans/2026-09-23-4-4-prod-wrapper.md` | denne plan |

---

### Task 1: Fundament — `lib.zsh`, freeze, dump, manifest-binding

**Files:**
- Create: `~/.private/147-44-prod/lib.zsh`, `00-freeze.sh`, `02-dump.sh`,
  `restore-hash.sql`, `untouched-hash.sql`, `writer-profiles.sql`, `rollback-preflight.sql`

**Interfaces:**
- Produces: `validate_manifest` (udskriver fil-SHA), `validate_profile`, `target_identity`,
  `assert_expected_target`, `project_database <out> [psql-args]`, `verify_go_hashes`,
  `assert_repo_clean`, `assert_freeze_active`, `assert_freeze_report`, `read_dump_receipt`,
  konstanter `DAA_MANIFEST DAA_MANIFEST_FILE_SHA256 DAA_MANIFEST_CONTENT_SHA256
  DAA_PROFILE DAA_PROFILE_ID DAA_PROFILE_SHA256 DAA_PREVIEW_SHA256`.

- [ ] **Step 1: Kopiér forlæg.** `cp -p ~/.private/148c-prod/{lib.zsh,00-freeze.sh,02-dump.sh,rollback-preflight.sql} ~/.private/147-44-prod/`;
  `cp -p ~/.private/148c-prod/state-hash.sql ~/.private/147-44-prod/restore-hash.sql` (udvides i Step 6).
- [ ] **Step 2: Skift konstanter i `lib.zsh`:**

```zsh
DAA_PRIVATE_DIR="${DAA_PRIVATE_DIR:-$HOME/.private/147-44-prod}"
DAA_MANIFEST="$HOME/.private/43b-kørsel/proposal-manifest.json"   # ikke overstyrbar
DAA_PROFILE="$DAA_REPO/.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json"
DAA_COMPARATOR="$DAA_SQL_DIR/compare_interpretation_proposal_projection.py"
DAA_PROFILE_ID="daa-2018-20-interpretation-proposal-v1"
DAA_PROFILE_FILE_VERSION="1.0.0"   # profil-JSON'ens top-niveau; det eneste der indsættes/readback'es
DAA_MANIFEST_FILE_SHA256="c310ca6325b5a3a10c895a0f80161a51a0c24b61c902b807d34c7f8433c65aad"
DAA_MANIFEST_CONTENT_SHA256="a328ede946140a1223be3077d18579d94f763812875a55d67abed00645313cf8"
DAA_PROFILE_SHA256="4e39fff44db0cdab7ff35d59fe852f317dc608e818c4b2dd8ff060190fdc625c"
DAA_PREVIEW_SHA256="$DAA_MANIFEST_FILE_SHA256"
```
Fjern `DAA_RENDITION_SHA256`, `DAA_LEDGER_FILE_SHA256`, `parent_hash_match`. Omdøb
`DAA_PROFILE_VERSION` → `DAA_PROFILE_FILE_VERSION` overalt (`validate_profile`, rehearsal-
og apply-kvitteringer), så navnet ikke kan forveksles med writerens `schema_version`. `target_identity`
bruger `interpretation_proposal_target_identity.sql`; `project_database` bruger
`interpretation_proposal_projection.psql`.

- [ ] **Step 3: Erstat `validate_manifest`** (fil-hash + lukkede metadata, ingen payload ud):

```zsh
validate_manifest() {
  require_file "$DAA_MANIFEST"
  expect_eq "manifestets fil-hash afviger" "$(sha256_file "$DAA_MANIFEST")" "$DAA_MANIFEST_FILE_SHA256"
  /usr/bin/python3 -I - "$DAA_MANIFEST" "$DAA_MANIFEST_CONTENT_SHA256" "$DAA_PROFILE_ID" "$DAA_PROFILE_SHA256" <<'PY' || fail "manifestet afviger"
import json, sys
p, content, pid, psha = sys.argv[1:]
m = json.load(open(p, encoding="utf-8"))
ops = m.get("operations")
if not (isinstance(ops, list) and len(ops) == 8): raise SystemExit("MANIFEST_OPS")
if sum(len(o.get("claims", [])) for o in ops) != 84: raise SystemExit("MANIFEST_CLAIMS")
if sum(len(c["cited_clauses"]) for o in ops for c in o["claims"]) != 88: raise SystemExit("MANIFEST_LINKS")
roles = [c["persona_role"] for o in ops for c in o["claims"]]
if (roles.count("principal"), roles.count("other")) != (68, 16): raise SystemExit("MANIFEST_ROLES")
if m.get("manifest_content_sha256") != content: raise SystemExit("MANIFEST_CONTENT")
if m.get("source") != {"id": 1, "profile_id": pid, "profile_sha256": psha}: raise SystemExit("MANIFEST_SOURCE")
if m.get("expected_counts") != {"person_creates": 0, "source_evidence": 0, "canonical_delta": 0,
                                "interpretation_proposals": 8}: raise SystemExit("MANIFEST_COUNTS")
if {o.get("dependency_class") for o in ops} != {"interpretation_proposal"}: raise SystemExit("MANIFEST_CLASS")
PY
  # Komparatorens egen manifest-hash skal give samme indholdshash.
  expect_eq "komparatorens manifest-hash afviger" \
    "$(/usr/bin/python3 -I "$DAA_COMPARATOR" --print-manifest-sha256 "$DAA_MANIFEST")" "$DAA_MANIFEST_CONTENT_SHA256"
  # Den fulde lukkede validering (claim-nøgler, claim_id-form/unikhed, persona_role,
  # confidence i [0,1], værdiform, citat-form/unikhed, provenance, indholdshash) er
  # komparatorens validate_manifest — genbrugt, ikke kopieret. -I ignorerer PYTHONPATH;
  # modulets mappe indsættes eksplicit, og filen er i GO-hash-mængden.
  /usr/bin/python3 -I - "$DAA_SQL_DIR" "$DAA_MANIFEST" <<'PY' || fail "manifestet består ikke komparatorens validering"
import sys
sys.path.insert(0, sys.argv[1])
import compare_interpretation_proposal_projection as c
c.validate_manifest(c.strict_json_loads(open(sys.argv[2], "rb").read().decode("utf-8")))
PY
}
```
Målt i manifestfilen 2026-09-23 (kun tal): 8 ops, 84 claims, 88 citater over 19 distinkte
klausuler, 68/16, alle 8 elementer har mindst ét `principal`-claim.

- [ ] **Step 4: Opdatér `verify_go_hashes`' og `assert_repo_clean`'s filmængde** til 4.4:
  private `00-freeze.sh 01-preflight.sh 02-dump.sh 03-restore-rehearsal.sh 04-apply.sh
  05-verify.sh 06-recover.sh lib.zsh 01-role-probe-prod.R 03-proposal-dryrun-prod.R
  04-proposal-apply-prod.R verify.sql restore-hash.sql untouched-hash.sql writer-profiles.sql
  rollback-preflight.sql` (16) + repo
  `apply_reimport_helpers.R`, `interpretation_proposal_projection.psql`,
  `interpretation_proposal_projection.sql`, `interpretation_proposal_anon_projection.sql`,
  `interpretation_proposal_target_identity.sql`, `compare_interpretation_proposal_projection.py`,
  profil-JSON (7) + manifestfilen (1) = **eksakt 24**. `assert_repo_clean` dækker de 7
  repo-stier.
- [ ] **Step 5: Test.** `zsh -c 'source ~/.private/147-44-prod/lib.zsh; validate_manifest && echo MANIFEST_OK'`
  → `MANIFEST_OK`. Mutant: kopiér manifestet til `$DAA_PRIVATE_DIR/mutant.json`, ændr én
  `confidence` med python, peg en midlertidig `DAA_MANIFEST` dertil i en subshell → STOPPORT
  (fil-hash). Slet mutanten bagefter.
- [ ] **Step 6: To hash-scripts, to formål** (R2-2):
  - `restore-hash.sql` = 148c's `state-hash.sql` udvidet til alle tabeller (`relkind IN
    ('r','p')`) OG alle sekvenser (`last_value`, `is_called`) i `private`+`public` — præcis
    det, `pg_restore --schema=private --schema=public` overskriver. **Ingen eksklusionsvariabel
    findes i filen.** Den er beviset for »ingen skrivning siden dump« og for restore-troskab.
  - `untouched-hash.sql` = samme konstruktion, men med en fast, i filen hardkodet liste over
    de 4.4-tabeller, der udelades (Task 4), inkl. sekvenser ejet af dem; resultatet bærer
    listen, så eksklusionen er synlig. Den bruges kun til neutralitet 04 → 05.
  `00-freeze.sh`/`02-dump.sh`: sti-/navneændringer (148c → 147-44), plus i `02-dump.sh`: kør
  `restore-hash.sql` læse-kun mod prod umiddelbart FØR og EFTER `pg_dump`; de skal være ens
  (ellers `DUMP_STATE_UNSTABLE` → STOP). Kvitteringen får `restore_sha256` og
  `restore_hash_seconds`. Kør `zsh -n` på begge.
- [ ] **Step 7: Stabilitet og køretid.** På stand-in (Task 5 Step 1): kør `restore-hash.sql`
  to gange med en `anon`-læsning af web-fladens forespørgsler imellem → samme hash; notér
  køretiden. **En volatil tabel eller sekvens er en STOP, ikke en eksklusion:** dens writer
  skal navngives i runbookens kanalliste og standses i pausen. En afbrudt/rullet-tilbage
  transaktion i prod kan flytte en sekvens og give en falsk STOP; det er fail-closed og
  løses med nyt dump.

### Task 2: Hærdede R-kopier (dry-run, apply, replay)

**Files:**
- Create: `~/.private/147-44-prod/01-role-probe-prod.R`, `03-proposal-dryrun-prod.R`,
  `04-proposal-apply-prod.R`

**Interfaces:**
- Consumes: `apply_reimport_helpers.R` (`execute_reimport(..., authorization_policy="external")`,
  `new_reimport_dbi_gateway(connect, transaction_setup=)`, `reimport_writer_expected_counts`,
  `reimport_authorized_payloads_json`).
- Produces:
  - `01-role-probe-prod.R` → stdout `ROLE_PROBE_OK`; skriver intet (alle transaktioner
    ROLLBACK).
  - `03-proposal-dryrun-prod.R <manifest> <dryrun.json>` → skriver `dryrun-intent.json`
    (samme mappe; `{"phase":"dry-run","authorization_id","principal_id","preview_sha256"}`,
    O_EXCL 0600) straks efter autorisationens commit og før `execute_reimport`; derefter 0600
    `{"authorization_id","principal_id","status":"finalized","committed":false,
    "profile_version":"1.0.0"}`; stdout `DRY_RUN_OK`; profilrække varig.
  - `04-proposal-apply-prod.R <manifest> apply|replay <intent.json> <out.json>` → skriver
    0600 `<intent.json>` = `{"phase","authorization_id","principal_id","preview_sha256"}`
    via `O_EXCL` STRAKS efter autorisationens commit og FØR `execute_reimport`; derefter
    `<out.json>` = intent-felterne + `{"status","committed"}`. Ingen af filerne må findes
    i forvejen. stdout kun status og `APPLY_OK`/`REPLAY_OK`.

- [ ] **Step 1: Forbindelses-præambel** kopieres ordret fra
  `~/.private/148c-prod/04-clause-apply-prod.R` linje 1-60 (argument-tjek tilpasset,
  `PG*`-rydning, prod/local-mode, `assert_target`).
- [ ] **Step 2: Rolle-adskilt gateway og autorisation** (fra #196-integrationen, én login):

```r
# B2: gatewayens preflight læser aktøren fra miljøet (apply_reimport_helpers.R:335) og
# sætter claimet igen derfra — en nedarvet UUID ville erstatte den valgte aktør.
# Tjekket (og DAA_FAULT-tjekket) står ØVERST i præamblen, før første dbConnect.
if (nzchar(Sys.getenv("DAA_REIMPORT_ACTOR_ID"))) stop("ACTOR_ENV_INHERITED", call. = FALSE)
# ... præamblen forbinder og asserterer målet ...
actors <- q("SELECT id::text i FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 2")$i
if (length(actors) != 1L || !nzchar(actors[[1L]])) stop("REDAKTION_ACTOR_NOT_UNIQUE", call. = FALSE)
actor <- actors[[1L]]
Sys.setenv(DAA_REIMPORT_ACTOR_ID = actor)   # lever kun i denne R-proces; on.exit virker
                                            # ikke på topniveau, og det behøves ikke
operation_setup <- function(db) {
  db$execute("SET LOCAL ROLE authenticated")
  db$query("SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
  who <- db$query("SELECT current_user AS u, current_setting('request.jwt.claim.sub',true) AS sub")
  if (!identical(who$u[[1L]], "authenticated") || !identical(who$sub[[1L]], actor))
    stop("OPERATION_ROLE_INVALID", call. = FALSE)
}
gateway <- function() new_reimport_dbi_gateway(connect, transaction_setup = operation_setup)
preview_sha <- digest::digest(file = manifest_path, algo = "sha256")
if (!identical(preview_sha, Sys.getenv("DAA_PREVIEW_SHA256"))) stop("PREVIEW_SHA_MISMATCH", call. = FALSE)
authorize <- function() {
  a <- connect(); on.exit(dbDisconnect(a), add = TRUE)
  dbBegin(a)
  ok <- FALSE; on.exit(if (!ok) try(dbRollback(a), silent = TRUE), add = TRUE, after = FALSE)
  assert_target_on(a)
  dbExecute(a, "SET LOCAL ROLE service_role")
  dbGetQuery(a, "SELECT set_config('request.jwt.claim.sub',$1,true)", params = list(actor))
  who <- dbGetQuery(a, "SELECT current_user AS u")
  if (!identical(who$u[[1L]], "service_role")) stop("SERVICE_ROLE_NOT_ACTIVE", call. = FALSE)
  identity <- dbGetQuery(a, "SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text AS i")$i[[1L]]
  id <- dbGetQuery(a, paste("SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,",
      "gen_random_uuid(),clock_timestamp()+interval '30 minutes') AS id"),
    params = list(manifest$manifest_content_sha256, preview_sha, identity, manifest$source$id,
      manifest$source$profile_id, manifest$source$profile_sha256,
      jsonlite::toJSON(reimport_writer_expected_counts(manifest), auto_unbox = TRUE),
      reimport_authorized_payloads_json(manifest)))$id[[1L]]
  dbCommit(a); ok <- TRUE
  id
}
```
`assert_target_on(con)` er `assert_target` parametriseret på forbindelse. Aktør-ID skrives
kun til 0600-filer, aldrig til stdout. `operation_setup`'s assert fanger, hvis claimet fra
`SET LOCAL` og gatewayens miljø-claim nogensinde divergerer.

- [ ] **Step 3: Fase-logik i `04`:**

```r
phase <- args[[2L]]; intent <- args[[3L]]; out <- args[[4L]]
if (!(phase %in% c("apply", "replay"))) stop("PHASE_INVALID", call. = FALSE)
if (file.exists(intent) || file.exists(out)) stop("OUT_EXISTS", call. = FALSE)
assert_target()
auth_id <- authorize()
# B3: intent skrives før execute, så 06-recover ved præcis hvilken autorisation et afbrudt
# forsøg brugte. write_exclusive = open(O_WRONLY|O_CREAT|O_EXCL, 0600) via python3 -I.
write_exclusive(intent, list(phase = phase, authorization_id = auth_id,
  principal_id = actor, preview_sha256 = preview_sha))
fault_point("after_authorize")   # kun lokal fejlinjektion, se nedenfor
res <- execute_reimport(manifest, preview_sha, "apply", gateway(), list(id = auth_id),
                        authorization_policy = "external")
want <- if (identical(phase, "apply")) "finalized" else "already_applied"
if (!identical(res$status, want) || !isTRUE(res$committed))
  stop("PHASE_RESULT_UNEXPECTED:", res$status, call. = FALSE)
fault_point("after_execute")
write_exclusive(out, list(phase = phase, authorization_id = auth_id, principal_id = actor,
  preview_sha256 = preview_sha, status = res$status, committed = res$committed))
cat(if (identical(phase, "apply")) "APPLY_OK\n" else "REPLAY_OK\n")
```
`apply`-fasen afviser altså `already_applied` (så en genkørsel efter ukendt udfald ikke
tavst »lykkes«), og `replay` afviser `finalized`.

**Fejlinjektion (til rehearsal af 06-recover):** `fault_point(name)` afslutter processen med
`quit(status = 97)`, hvis `DAA_FAULT == name`. Den er kun aktiv, når
`DAA_CONNECTION_MODE == "local"`; i prod-mode er en ikke-tom `DAA_FAULT` en stopport
(`FAULT_IN_PROD`) i præamblen, FØR forbindelsen åbnes. `04-apply.sh` og `06-recover.sh`
kører `unset DAA_FAULT` og asserterer det; `run_r` sender den kun videre i local-mode.
`after_authorize` giver »intet commit«, `after_execute` giver »commit uden kvittering« — de
to udfald 06 skal skelne. `03-proposal-dryrun-prod.R` har samme `after_authorize`-punkt
(efter `dryrun-intent.json`). Zsh-siden har `after_step:<trin>` i `run_from` (`exit 97`
efter trinnet), kun når `DAA_RUN_MODE == local`.

- [ ] **Step 4: `03-proposal-dryrun-prod.R`:** præambel (Step 1) + aktør (Step 2) + krav
  `profile$profile_version == "1.0.0"` (B1; 148c-forlægget tjekker sin egen version i
  `03-clause-dryrun-prod.R:68`) + profil-hash fil=base
  (`private.reimport_canonical_json_sha256`) + `INSERT … ON CONFLICT DO NOTHING` med filens
  `profile_version` + readback af `(source_id, profile_id, profile_version, profile_sha256,
  canonical writer_config-hash)` = `(1, DAA_PROFILE_ID, "1.0.0", 4e39fff…, 4e39fff…)` +
  `execute_reimport(..., "dry-run", gateway(), list(id = authorize()), authorization_policy="external")`
  (samme `authorize()` som Step 2 — dry-run-scriptet får derfor samme præambel-kode);
  kræv `finalized`, `committed=FALSE`, uændret antal `interpretation`-rækker; skriv
  `<dryrun.json>` (O_EXCL, 0600) med dry-run-autorisationens id; `DRY_RUN_OK`. Selve
  neutralitetsbeviset er projektionsbaseret og ligger i `run_proposal_sequence` (B4).
  **Hvorfor ikke `auto_dry_run`:** gatewayens `authorize`
  (`apply_reimport_helpers.R:344-352`) kalder `red_authorize_reimport` i operations-
  transaktionen, som efter `SET LOCAL ROLE authenticated` ikke må autorisere (#196:
  »operationslogin kan ikke autorisere«). Konsekvens: dry-run efterlader én committed,
  ikke-forbrugt `issued`-autorisation (udløber efter 30 min). Den er forventet, tælles
  (præcis 1) og er ikke en stopport; tomheds-porten »0 aktive autorisationer« gælder
  FØR dry-run.
- [ ] **Step 5: Test mod stand-in** (bygges i Task 5 Step 1; indtil da mod en
  `createdb -T` kopi af den) med `DAA_CONNECTION_MODE=local`: dry-run → `DRY_RUN_OK`;
  apply → `APPLY_OK`; apply igen → `PHASE_RESULT_UNEXPECTED:already_applied`;
  replay → `REPLAY_OK`; forkert `DAA_EXPECTED_TARGET` → `DAA_TARGET_MISMATCH` og 0 nye
  autorisationer (tæl før/efter); `DAA_REIMPORT_ACTOR_ID=<anden uuid>` i miljøet →
  `ACTOR_ENV_INHERITED` før forbindelse; `DAA_CONNECTION_MODE=prod DAA_FAULT=x` →
  `FAULT_IN_PROD` før forbindelse (kun præambel-porten; prod nås aldrig i en test).
- [ ] **Step 6: `01-role-probe-prod.R`** (B6; forlæg `test-…-proposal.R:137-162`). Præambel
  som Step 1, men ingen aktør-miljø og ingen skrivning. Hver probe på en frisk forbindelse
  i `dbBegin` … `dbRollback`:
  1. `SET LOCAL ROLE authenticated` + lokal claim → `current_user='authenticated'`, claim = aktør;
  2. samme + `SELECT public.red_authorize_reimport(NULL×10)` → fejlbesked indeholder
     `permission denied` (operationsrollen kan ikke autorisere);
  3. `SET LOCAL ROLE service_role` → `current_user='service_role'`;
  4. samme + `SELECT public.red_apply_reimport_interpretation_proposal(NULL×3)` →
     `permission denied` (autorisatoren kan ikke skrive forslag);
  5. livscyklus for både COMMIT-løs ROLLBACK og en tom `dbCommit` af en transaktion med kun
     `SET LOCAL ROLE`+claim: bagefter `current_user = session_user` og claim tom.
  Alle fejl andre end `permission denied` → `ROLE_PROBE_UNEXPECTED` (ikke »bestået«).
  Bevis for at proben intet skriver: tilstands-hashen før/efter er ens (Task 5 mod
  stand-in). `ROLE_PROBE_OK`.

### Task 3: `01-preflight.sh` og `verify.sql`

**Files:**
- Create: `~/.private/147-44-prod/01-preflight.sh`, `verify.sql`

- [ ] **Step 1: Preflight-assertions** (alle i kode; rapport kun tal/koder/hashes;
  `PREFLIGHT_OK`):
  1. ingen argumenter; `validate_manifest`; `validate_profile`;
  2. målidentitet + rolletest `anon` (ordret fra 148c `01-preflight.sh`) +
     `01-role-probe-prod.R` → `ROLE_PROBE_OK` (B6; skriver intet);
  3. 4.1c-forudsætning: præcis én `finalized` batch med 591 `clause_evidence`-events for
     `daa-2018-20-clause-evidence-v1`, og 868 klausul-observationer;
  4. tomhed: 0 `interpretation_proposal`-events, 0 `interpretation` med
     `method='model'` for source 1, ingen profilrække for `DAA_PROFILE_ID`, 0 aktive
     (`issued`, ikke udløbne) autorisationer globalt, **0 autorisationer i ALLE statusser med
     `manifest_sha256 = DAA_MANIFEST_CONTENT_SHA256`** (R2-5: `status` skifter ikke selv til
     `expired`, `schema.sql:2766-2783`; en gammel `issued`-række ville ellers passere), og
     **0 `extraction_run` for kilde 1 med `run_key IN ('interpretation-proposal:' ||
     <hver distinkt runner_manifest_sha256 i manifestet>)`** (R2-6: writerens
     `ON CONFLICT DO NOTHING` + driftvagt, `schema.sql:3668-3677`, kan så aldrig ramme en
     fremmed række);
  5. 0 forældreløse `interpretation_observation` (SQL fra 4.1c-runbook §2.1); redaktion = 1;
  6. citater: genereres af Python fra manifestet som `VALUES`-liste
     `(record_key, ordinal, verbatim_sha256)` og køres læse-kun:

```sql
WITH expected(record_key, ordinal, sha) AS (VALUES /* genereret */),
parent AS (
  SELECT r.record_key, ob.id AS parent_id
    FROM private.source_record r
    JOIN private.source_record_anchor_current a ON a.source_record_id=r.id AND a.decision_status='accepted'
    JOIN private.source_record_occurrence o ON o.id=a.occurrence_id
    JOIN private.source_observation ob ON ob.occurrence_id=o.id AND ob.parent_observation_id IS NULL
   WHERE r.source_id=1)
SELECT count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM private.source_observation c
          WHERE c.parent_observation_id=p.parent_id AND c.clause_ordinal=e.ordinal
            AND encode(pg_catalog.sha256(convert_to(c.verbatim_text,'UTF8')),'hex')=e.sha))::text
       || '|' || count(*)::text
  FROM expected e LEFT JOIN parent p USING (record_key);
```
     Krav: `88|88` (én række pr. citat).
  7. **writerens øvrige krav** (M8; spejler `schema.sql:3653-3775`). Python genererer
     fra manifestet `claims(record_key, claim_no, predicate, kind, cited jsonb, value jsonb)`
     og piper SQL'en direkte til `readonly_psql -f -` — den skrives aldrig til en fil, og
     kun tællinger kommer ud. Samme `parent`-CTE som 6.

```sql
WITH claims(record_key, claim_no, predicate, kind, cited, value) AS (VALUES /* genereret */),
rec AS (SELECT DISTINCT record_key FROM claims),
per_record AS (
  SELECT e.record_key,
         (SELECT count(*) FROM private.source_record_anchor_current a
           WHERE a.source_record_id=r.id AND a.decision_status='accepted') AS anchors,
         (SELECT count(*) FROM private.source_record_anchor_current a
            JOIN private.source_observation ob ON ob.occurrence_id=a.occurrence_id
           WHERE a.source_record_id=r.id AND a.decision_status='accepted'
             AND ob.parent_observation_id IS NULL) AS parents
    FROM rec e LEFT JOIN private.source_record r ON r.source_id=1 AND r.record_key=e.record_key),
per_claim AS (
  SELECT c.*, p.interpretation_kind AS p_kind, p.value_kind,
         private.normalize_interpretation_proposal_value(c.value) AS v
    FROM claims c LEFT JOIN private.interpretation_predicate p
      ON p.predicate=c.predicate AND p.status='active'),
keyed AS (
  SELECT *, private.interpretation_proposal_key(1, record_key, predicate, cited, v) AS k FROM per_claim),
cited_obs AS (
  SELECT DISTINCT c.id AS observation_id
    FROM claims cl CROSS JOIN LATERAL jsonb_array_elements(cl.cited) x
    JOIN parent pa ON pa.record_key=cl.record_key
    JOIN private.source_observation c ON c.parent_observation_id=pa.parent_id
                                     AND c.clause_ordinal=(x->>'ordinal')::int),
disp AS (
  SELECT o.observation_id, d.*
    FROM cited_obs o LEFT JOIN LATERAL (SELECT * FROM private.clause_disposition cd
      WHERE cd.observation_id=o.observation_id ORDER BY cd.version DESC LIMIT 1) d ON true)
SELECT concat_ws('|',
  (SELECT count(*) FILTER (WHERE anchors=1) FROM per_record),
  (SELECT count(*) FILTER (WHERE parents=1) FROM per_record),
  (SELECT count(*) FILTER (WHERE p_kind IS NOT NULL AND kind=p_kind) FROM per_claim),
  (SELECT count(*) FILTER (WHERE CASE WHEN value_kind IN ('text','date_raw')
        THEN jsonb_typeof(v)='string' AND btrim(v#>>'{}')<>''
        ELSE jsonb_typeof(v)='object' AND btrim(coalesce(v->>'raw',''))<>'' END) FROM per_claim),
  (SELECT count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM private.interpretation i
        WHERE i.interpretation_key=keyed.k)) FROM keyed),
  (SELECT count(DISTINCT k) FROM keyed),
  (SELECT count(*) FILTER (WHERE decided_by_kind='machine'
        AND coalesce(evidence->>'manifest_sha256','') ~ '^[0-9a-f]{64}$'
        AND (evidence->>'batch_id' IS NOT NULL OR evidence->>'extraction_run_id' IS NOT NULL)
        AND coalesce(evidence->>'batch_id', '00000000-0000-0000-0000-000000000000')
            ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND coalesce(evidence->>'extraction_run_id', '00000000-0000-0000-0000-000000000000')
            ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') FROM disp),
  (SELECT count(*) FROM cited_obs));
```
     Krav: `8|8|84|84|84|84|19|19`. Nøgle-tjekket er et bælte oven på tomheds-porten (0
     `method='model'`-forslag for kilde 1): nøglen beregnes af de samme funktioner, som
     writeren kalder, men af en Python-genereret jsonb, der kan afvige fra R's serialisering;
     derfor er tomheds-porten den primære. Confidence i `[0,1]` og claim-nøglernes form
     tjekkes i `validate_manifest` (ren Python, ingen base). Funktionerne er
     `IMMUTABLE SECURITY DEFINER` og kaldes som ejer; rehearsal beviser, at de kører i en
     læse-kun transaktion.
  8. **persona, identitet, levende** (M9; spec §9.2: »levende eller uafklaret« udelukkes).
     Ingen LEFT JOIN må kunne gøre et manglende led til »ikke levende«:

```sql
WITH expected_records(record_key) AS (VALUES /* manifestets 8 source_record_key */),
pm AS (
  SELECT e.record_key, count(spm.persona_id) AS n, min(spm.persona_id::text)::uuid AS persona_id
    FROM expected_records e JOIN parent p USING (record_key)
    LEFT JOIN private.source_mention sm ON sm.observation_id=p.parent_id
    LEFT JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
   GROUP BY e.record_key)
SELECT concat_ws('|',
  count(*) FILTER (WHERE pm.n=1),
  count(*) FILTER (WHERE pm.n=1 AND spi.decision_status='accepted'),
  count(*) FILTER (WHERE pm.n=1 AND spi.decision_status='accepted' AND pe.id IS NOT NULL),
  count(*) FILTER (WHERE pm.n=1 AND spi.decision_status='accepted' AND pe.levende IS FALSE),
  count(*))
  FROM pm
  LEFT JOIN private.source_persona_identity spi ON spi.source_persona_id=pm.persona_id
  LEFT JOIN public.person pe ON pe.id=spi.canonical_person_id;
```
     Krav: `8|8|8|8|8` — én primær persona, accepteret identitet (PK pr. persona,
     `schema.sql:1411-1425`), eksisterende person, `levende IS FALSE` (ikke `NOT levende`:
     `NULL` tæller ikke), og alle 8 records fundet. Kardinaliteterne rapporteres hver for sig,
     så et STOP siger hvilket led der mangler.
- [ ] **Step 2: Kør preflight-SQL'en** (psql direkte, `DAA_CONNECTION_MODE=local`-ækvivalent:
  `PGHOST=localhost`) mod stand-in → notér tallene; ret kun forventninger, der er forklaret.
- [ ] **Step 3: `verify.sql`** (læse-kun, `COLLATE "C"`, kun tal): events/batches for
  profilen (8 events, 1 `finalized` batch), forslag 84, uden link 0, `principal` uden
  persona 0, dispositionsfordeling for kørslens klausuler (13/6), forældreløse 0,
  autorisationer med `manifest_sha256 = a328ede9…` pr. status (forventning i
  Autorisationstabellen; døde autorisationer fra en genoptagelse gives som parameter fra
  kvitteringen), 1 profilrække for `DAA_PROFILE_ID` med filversion `1.0.0`, præcis én
  `extraction_run` pr. distinkt `runner_manifest_sha256` i manifestet (antallet beregnes af
  `validate_manifest` og står i rehearsal-rapporten).
  Køres i rehearsal (Task 4) før den må bruges i 05.

### Task 4: sekvens, `03-restore-rehearsal.sh`, `04-apply.sh`, `05-verify.sh`, `06-recover.sh`

**Files:**
- Create: `~/.private/147-44-prod/03-restore-rehearsal.sh`, `04-apply.sh`, `05-verify.sh`,
  `06-recover.sh`
- Modify: `~/.private/147-44-prod/lib.zsh` (tilføj `run_proposal_sequence`,
  `run_apply_phase`, `continue_after_apply`, `run_replay_phase`, `assert_projection_delta`,
  `assert_report_chain`, `sanitize_report`, `untouched_hash`, `write_apply_receipt`, `json_field`)

#### Autorisationstabel (kilde 1, bundet til manifest `a328ede9…`)

Hver række er et krav, som `verify.sql` og `06-recover.sh` tæller, og kolonnen
»Autorisationer« tæller KUN autorisationer med `manifest_sha256 = a328ede9…` (alle
statusser). Øvrige autorisationer for kilde 1 er baseline: de står i `pre-dry.json` og skal
være uændrede i hver senere projektion (komparatorens `_require_preserved`,
`assert_projection_delta`). Preflight kræver 0 manifest-bundne før 03 (Task 3 punkt 4).
`D` = dry-run, `A` = apply, `R` = replay. »Uforbrugt« = `status='issued'` og
`consumed_at IS NULL`.

| Tidspunkt | Autorisationer | Batches for profilen | `interpretation_proposal`-events |
|---|---|---|---|
| før 03 (04's tomhedsport) | 0 | 0 | 0 |
| efter dry-run | D uforbrugt | 0 | 0 |
| efter apply | D uforbrugt, A `consumed` | 1 `finalized` (A) | 8 |
| efter replay | D uforbrugt, A `consumed`, R `consumed` | 1 `finalized` (A) | 8 |
| afbrudt apply, intet commit | D uforbrugt, A uforbrugt | 0 | 0 |
| afbrudt apply, commit | D uforbrugt, A `consumed` | 1 `finalized` (A) | 8 |
| afbrudt replay, intet commit | … + R uforbrugt | 1 | 8 |
| afbrudt replay, commit | … + R `consumed` | 1 | 8 |

Hvert genoptagelsesforsøg lægger højst én ny død autorisation til. `06` tillader højst to
genoptagelser pr. kørsel; derefter NO-GO → restore.

- [ ] **Step 1: Fælles sekvens i `lib.zsh`** — de SAMME bytes kører i rehearsal (03), prod
  (04) og genoptagelse (06):

```zsh
# R2-1: hvert R-kald får et lukket miljø; intet nedarves. DAA_RUN_MODE/DAA_RUN_TARGET sættes
# readonly af kalderen (03: local; 04/06: prod) efter målbindingen. DAA_RSCRIPT er en absolut
# sti, opløst ved lib-load og skrevet i rehearsal-rapport og apply-kvittering.
run_r() {
  local script="$1"; shift
  local -a envv=(PATH=/usr/bin:/bin HOME="$HOME" LANG=en_US.UTF-8 PGTZ=UTC
    DAA_CONNECTION_MODE="$DAA_RUN_MODE" DAA_EXPECTED_TARGET="$DAA_RUN_TARGET"
    DAA_PREVIEW_SHA256="$DAA_PREVIEW_SHA256" DAA_REPO="$DAA_REPO")
  case "$DAA_RUN_MODE" in
    prod)  [[ -z "${DAA_FAULT:-}" ]] || fail "DAA_FAULT er sat i prod" ;;
    local) envv+=(DAA_LOCAL_PGHOST="$DAA_LOCAL_PGHOST" DAA_LOCAL_PGPORT="$DAA_LOCAL_PGPORT"
             DAA_LOCAL_PGUSER="$DAA_LOCAL_PGUSER" DAA_LOCAL_PGPASSWORD="${DAA_LOCAL_PGPASSWORD:-}"
             PGDATABASE="$DAA_LOCAL_PGDATABASE" DAA_FAULT="${DAA_FAULT:-}") ;;
    *)     fail "ukendt DAA_RUN_MODE" ;;
  esac
  require_sha "$DAA_PREVIEW_SHA256" "DAA_PREVIEW_SHA256 mangler"
  require_sha "$DAA_RUN_TARGET" "DAA_RUN_TARGET mangler"
  /usr/bin/env -i "${envv[@]}" "$DAA_RSCRIPT" "$script" "$@"
}

# Sekvensen er en ordnet liste af trin; hvert trin producerer præcis én artefakt (O_EXCL)
# og kan køres fra et vilkårligt trin (06 genoptager med run_from).
PROPOSAL_STEPS=(untouched0 predry profiles_predry dryrun before profiles_before delta_dryrun
  apply after profiles_after fresh replay replayed profiles_replayed replay_match sanitize)
run_proposal_sequence() { run_from "$1" untouched0; }   # $1 = runmappe (0700)
run_from() {
  local run="$1" first="$2" go=0 step
  for step in "${PROPOSAL_STEPS[@]}"; do
    [[ "$step" == "$first" ]] && go=1
    (( go )) && "step_$step" "$run"
  done
  (( go )) || fail "ukendt trin: $first"
}
step_untouched0()        { untouched_hash > "$1/untouched-0.txt"; }
step_predry()            { project_database "$1/pre-dry.json" -v source_id=1; }
step_profiles_predry()   { writer_profiles > "$1/profiles-pre-dry.json"; }
step_dryrun() {
  run_r "$DAA_PRIVATE_DIR/03-proposal-dryrun-prod.R" "$DAA_MANIFEST" "$1/dryrun.json" \
    > "$1/dryrun.log" 2>&1 || fail "dry-run afbrudt — kør 06-recover.sh $1"
  /usr/bin/grep -qx DRY_RUN_OK "$1/dryrun.log" || fail "DRY_RUN_OK mangler"
}
step_before()            { project_database "$1/before.json" -v source_id=1; }
step_profiles_before()   { writer_profiles > "$1/profiles-before.json"; }
step_delta_dryrun() {    # B4 + R2-4: kun dry-run'ens egen autorisation og den ene profilrække
  assert_projection_delta "$1/pre-dry.json" "$1/before.json" "$1/dryrun.json" issued \
    > "$1/delta-dryrun.json"
  assert_profile_delta "$1/profiles-pre-dry.json" "$1/profiles-before.json" \
    >> "$1/delta-dryrun.json"
}
step_apply() {
  run_r "$DAA_PRIVATE_DIR/04-proposal-apply-prod.R" "$DAA_MANIFEST" apply \
    "$1/apply-intent.json" "$1/apply.json" > "$1/apply.log" 2>&1 \
    || fail "apply afbrudt — kør IKKE 04 igen; kør 06-recover.sh $1"
}
step_after()             { project_database "$1/after.json" -v source_id=1; }
step_profiles_after()    { expect_file_eq "$1/profiles-before.json" <(writer_profiles) \
                             && writer_profiles > "$1/profiles-after.json"; }
step_fresh() {
  /usr/bin/python3 -I "$DAA_COMPARATOR" --mode fresh --manifest "$DAA_MANIFEST" \
    --before "$1/before.json" --after "$1/after.json" --expect-target-sha256 "$DAA_RUN_TARGET" \
    --expect-preview-sha256 "$DAA_PREVIEW_SHA256" \
    --expect-principal-id "$(json_field "$1/apply.json" principal_id)" \
    --report "$1/fresh.json" > /dev/null || fail "fresh-komparator gav ikke match"
}
step_replay() {
  run_r "$DAA_PRIVATE_DIR/04-proposal-apply-prod.R" "$DAA_MANIFEST" replay \
    "$1/replay-intent.json" "$1/replay.json" > "$1/replay.log" 2>&1 \
    || fail "replay afbrudt — kør 06-recover.sh $1"
}
step_replayed()          { project_database "$1/replayed.json" -v source_id=1; }
step_profiles_replayed() { expect_file_eq "$1/profiles-after.json" <(writer_profiles) \
                             && writer_profiles > "$1/profiles-replayed.json"; }
step_replay_match() {    # baseline = replay-base.json hvis 06 har lagt en, ellers after.json
  local base="$1/after.json"; [[ -e "$1/replay-base.json" ]] && base="$1/replay-base.json"
  /usr/bin/python3 -I "$DAA_COMPARATOR" --mode replay --after "$base" \
    --replayed "$1/replayed.json" \
    --replay-authorization-id "$(json_field "$1/replay.json" authorization_id)" \
    --expect-target-sha256 "$DAA_RUN_TARGET" --report "$1/replay-match.json" > /dev/null \
    || fail "replay-komparator gav ikke match"
  assert_report_chain "$1" "$base"
}
step_sanitize() {
  sanitize_report "$1/fresh.json" > "$1/fresh-renset.json"
  sanitize_report "$1/replay-match.json" > "$1/replay-renset.json"
}
```

`writer_profiles` = `readonly_psql -f writer-profiles.sql`: alle `reimport_writer_profile`-
rækker som kanonisk JSON-liste `(source_id, profile_id, profile_version, profile_sha256,
private.reimport_canonical_json_sha256(writer_config))`, sorteret `COLLATE "C"`.
`assert_profile_delta <gammel> <ny>`: præcis én ny række, lig `(1, DAA_PROFILE_ID, "1.0.0",
4e39fff…, 4e39fff…)`; alle øvrige rækker identiske (R2-4). Efter `before` må profilrækkerne
ikke ændre sig (`expect_file_eq` i `profiles_after`/`profiles_replayed`).

**`assert_projection_delta <gammel> <ny> <intent-fil> issued|consumed`** (`python3 -I`,
`raise SystemExit`): parse begge projektioner; `ny.authorizations` minus `gammel`'s id'er
skal være præcis én række, hvis `authorization_id` = intent-filens; rækken skal have
`operation='reimport'`, den krævede status (`issued` + `consumed=false`, eller `consumed` +
`consumed=true`), `manifest_sha256` = `DAA_MANIFEST_CONTENT_SHA256`, `preview_sha256` =
`DAA_PREVIEW_SHA256`, `profile_id`/`profile_sha256` = konstanterne, `principal_id` =
intent-filens. Fjern rækken; resten af `ny` skal være kanonisk JSON-lig `gammel` — hver
nøgle, også alle eksisterende autorisationer, batches, events, fortolkninger, links,
dispositioner, runs og neutrale flader. Projektionen har ingen `now()`-afhængige felter
(`status` er lagret), så lighed er et eksakt krav. Udskriver en renset rapport med de to
fil-hashes og autorisations-id'et.

**`assert_report_chain <run> <base>`**: `fresh.input_file_sha256.after` =
sha256(`after.json`); `replay-match.input_file_sha256.after` = sha256(`<base>`); er
`<base>` ≠ `after.json`, skal en `delta-replay-*.json` binde de to (Step 6); counts = 8/84/88/{13,6}.

**`untouched_hash`** = `untouched-hash.sql`, hvis hardkodede eksklusionsliste er de tabeller
4.4 skriver i (inkl. deres sekvenser):
`private.reimport_writer_profile, private.reimport_authorization, private.reimport_batch,
private.reimport_event, private.extraction_run, private.interpretation,
private.interpretation_observation, private.clause_disposition`. Listen er en påstand, der
bevises i rehearsal (Task 5 Step 2: `untouched_hash` før = efter sekvensen). Skriver writeren
et sted mere, fejler rehearsal, og listen rettes — aldrig omvendt. Hullet i
`reimport_writer_profile` dækkes af `writer_profiles`; resten af de ekskluderede tabeller af
projektionen + komparatorerne (autorisationer, batches, events, runs, fortolkninger, links,
dispositioner for kilde 1) — tabeller for andre kilder dækker projektionen med hashes
(`reimport_authorization_other_sources` m.fl.).

- [ ] **Step 2: `03-restore-rehearsal.sh`** = 148c-udgaven med disse ændringer: restore-hash
  af den gendannede base = dump-kvitteringens `restore_sha256` (bevis for at restoren er
  trofast på data, og at rehearsal kører på det dump 04 senere sammenligner med); rolleprobe;
  preflight-SQL (Task 3) mod restoren; `untouched_hash` før; `run_proposal_sequence`;
  `untouched_hash` efter = før; `verify.sql`; **fejlinjektion** på en `createdb -T`-kopi pr.
  udfald: `DAA_FAULT=after_authorize` i dry-run-, apply- og replay-fasen, `after_execute` i
  apply- og replay-fasen, og `DAA_FAULT=after_step:<trin>` (i `run_from`, kun local) efter
  `before`, `after`, `fresh` og `replay_match` samt før kvitteringen — hver efterfulgt af
  `06-recover.sh` → `RECOVER_OK` med det forventede udfald fra tabellen og samme endelige
  tal; én gang to afbrydelser i træk (child af child) og én tredje → NO-GO; derefter `db-rls.sql` → `tests/sql/run-db-verify-disposable.sql` (kun lokalt);
  fortrydelsesøvelse: `pg_restore --clean --if-exists --no-owner --schema=private
  --schema=public` oven på den befolkede base, krav 0 `interpretation_proposal`-events,
  0 model-forslag, ingen profilrække, restore-hash = før; fejl-tilladelsesliste som 148c
  (vault-klassen + de tre RLS-afhængige funktioner i begge beskedformer). Kør
  `DAA_CONNECTION_MODE=local`. Slut: `REHEARSAL_OK` + rapport med `dump_sha256`,
  `restore_sha256`, `manifest_file_sha256`, `profile_file_version`, tal, recovery-udfald.
- [ ] **Step 3: `04-apply.sh`** i denne rækkefølge; alt før punkt 7 er læse-kun:
  1. `--jeg-mener-det` påkrævet (exit 2 ellers); `unset DAA_FAULT DAA_REIMPORT_ACTOR_ID`
     og assert;
  2. bindinger: commit, 22 fil-hashes, mål, dump-kvittering, rehearsal-rapport (status,
     dump, manifest, `profile_file_version`, tal, hvert recovery-udfald i 06-tabellen bestået),
     freeze-rapport;
  3. **skrivepause-bevis (B5):** live `restore-hash.sql` = dump-kvitteringens `restore_sha256`
     = rehearsal-rapportens. Afviger den: STOP — noget er skrevet siden dumpet; tag nyt dump;
  4. rolleprobe (B6) → `ROLE_PROBE_OK`;
  5. tomheds-, citat-, writerkrav- og persona-assertions fra Task 3 gentaget læse-kun;
  6. `readonly DAA_RUN_MODE=prod DAA_RUN_TARGET="$TARGET"`;
  7. `run_proposal_sequence "$RUN"` (første trin gemmer `untouched_hash` som `U0`);
  8. `untouched_hash` = `U0` (intet uden for 4.4's tabeller ændret under kørslen);
  9. `write_apply_receipt`: `apply-receipt.json` via `O_EXCL` 0600 med runmappe, sha256 af
     hver artefakt i `PROPOSAL_STEPS`-rækkefølge (inkl. intents, profilsnapshots, logs og
     rensede rapporter), `DAA_RSCRIPT`-sti + `R --version`-linje, mål, dump-sha, `restore_sha256`, `U0`, freeze-rapport-sha,
     rehearsal-rapport-sha, commit, `profile_file_version`, `recovered: false`,
     `status: APPLY_DONE`. Udskriver `DAA_APPLY_RECEIPT=` og `DAA_APPLY_RECEIPT_SHA256=`.
- [ ] **Step 4: `05-verify.sh`** (M7; præambel ordret fra 148c `05-verify.sh:10-19`):
  kræver `DAA_APPLY_RECEIPT` + `DAA_APPLY_RECEIPT_SHA256` + rehearsal-rapport + hash;
  genberegner hver fil-hash i kvitteringen; tag `final.json`: parset lig den sidste
  `replayed.json` i kvitteringen; `untouched_hash` = kvitteringens `U0`; genkør begge
  komparatorer mod kvitteringens filer med NYE rapportstier; `verify.sql` med
  Autorisationstabellens slutrække (inkl. døde autorisationer fra en genoptagelse, som
  kvitteringen navngiver); skriv `verify-ok.json` med `apply_report_sha256` =
  kvitteringens hash; `VERIFY_OK`. `00-freeze end` binder til samme hash (148c-logik).
- [ ] **Step 5: `zsh -n` på alle syv scripts.** Forventet: ingen output.
- [ ] **Step 6: `06-recover.sh --jeg-mener-det <runmappe>`** (B3 + R2-3) — kun efter en
  afbrudt 04 eller 06. En artefakt-tilstandsmaskine over `PROPOSAL_STEPS`:
  1. præambel og bindinger som 04 punkt 1-2; rolleprobe; `readonly DAA_RUN_MODE=prod
     DAA_RUN_TARGET=<mål>`; runmappen er en 04-/06-runmappe uden `apply-receipt.json`
     (ellers STOP: kørslen er afsluttet, gå til 05); rodkørslens `untouched-0.txt` findes,
     og live `untouched_hash` = den (ALTID første port);
  2. **valider artefakterne i trinrækkefølge** (0600, parser, bindinger: intents' manifest/
     preview/principal, komparatorrapporters `status=match` og `input_file_sha256` mod de
     tidligere artefakter, delta-rapporter mod deres input). Stop ved første manglende ELLER
     ugyldige artefakt = `næste trin`; alt efter det behandles som ikke-eksisterende og
     bruges aldrig;
  3. **klassificér live-tilstanden læse-kun** med Autorisationstabellens tre kolonner og
     intent-id'erne; kombinationen (næste trin × live) skal stå i tabellen nedenfor, ellers
     NO-GO;
  4. **opret en child-runmappe** `<rod>/recover-<n>` (0700; `n` ≤ 2, ellers NO-GO), kopiér de
     validerede artefakter (`cp -p`) og skriv `resume.json` (O_EXCL) med forælderens sti,
     hver kopieret artefakts hash, `næste trin`, udfald og evt. død autorisation. Forælderen
     røres aldrig igen; ingen O_EXCL-fil genskrives;
  5. udfør udfaldets forberedelse og derefter `run_from <child> <trin>`; slut med
     `untouched_hash` = `U0`, `write_apply_receipt` (`recovered: true`, kæden af mapper,
     `resume.json`-hashes, døde autorisationer) og `RECOVER_OK udfald=<navn>`.

  | Næste trin | Live (manifest-bundne) | Udfald og forberedelse i child |
  |---|---|---|
  | `untouched0` … `profiles_predry` | 0 autorisationer, 0 profilrækker for profilen | **intet skrevet** → `run_from <child> predry` |
  | `dryrun` (ingen/ugyldig `dryrun.json`) | ≤1 uforbrugt autorisation (id = `dryrun-intent.json`, eller — mangler intent — præcis én ny uforbrugt med vores principal); profilrække 0 eller den forventede; 0 batches | **dry-run afbrudt** → forælderens `pre-dry.json`/`profiles-pre-dry.json` kopieres som `*-parent.json`; ny `pre-dry.json`/`profiles-pre-dry.json` i child; bevis delta mod `*-parent` (højst den ene døde autorisation; højst den ene forventede profilrække) `> delta-resume.json`; `run_from <child> dryrun` |
  | `before` … `delta_dryrun` | D uforbrugt; 0 batches | **dry-run færdig, bevis mangler** → `run_from <child> before` (dry-run er `committed=false`; delta mod forælderens `pre-dry`) |
  | `apply`; A uforbrugt (id fra `apply-intent.json`, eller præcis én ny uforbrugt med vores principal) | D + A uforbrugt; 0 batches; 0 events | **apply, intet commit** → forælderens `before.json` kopieres som `before-parent.json`, og child får en ny projektion som `before.json`; `assert_projection_delta before-parent → before <A> issued > delta-resume.json`; profilsnapshot live = forælderens; `run_from <child> apply` (fresh mod den nye `before.json`) |
  | `apply`; A `consumed` | D uforbrugt, A `consumed`; 1 `finalized` batch med `authorization_id=A`; 8 events | **apply, commit** → rekonstruér `apply.json` (intent + batchrække, `reconstructed: true`); `run_from <child> after` (fresh mod den kopierede `before.json`) |
  | `after` … `fresh` | som »efter apply« | **efter commit, før fresh** → `run_from <child> after` |
  | `replay`; R uforbrugt / ukendt ny uforbrugt | som »efter apply« + R uforbrugt | **replay, intet commit** → projektion `replay-base.json` i child; `assert_projection_delta after → replay-base <R> issued > delta-replay.json`; `run_from <child> replay` |
  | `replay`; R `consumed` | som »efter replay« | **replay, commit** → rekonstruér `replay.json`; `run_from <child> replayed` |
  | `replayed` … `sanitize` | som »efter replay« | **efter replay** → `run_from <child> <næste trin>` |
  | (alle trin gyldige, ingen kvittering) | som »efter replay« | **kun kvittering mangler** → kvittering i child |
  | alt andet: 2+ batches, events ∉ {0, 8}, 2+ ukendte autorisationer, fremmed principal, `untouched_hash` ≠ `U0`, tredje genoptagelse | — | **NO-GO** → bevar alt, restore efter runbook §8 |

  Kun tre trin udsteder autorisationer (`dryrun`, `apply`, `replay`), og de køres kun i en
  child, hvis klassifikationen har bevist, at det forrige forsøg på SAMME trin ikke
  committede. Ingen genoptagelse kører 04's tomhedsporte (de er bevidst uopfyldelige efter
  første skrivning); delta-beviset mod den sidst betroede artefakt er porten.
  `assert_report_chain` følger kæden af `delta-resume`/`delta-replay`-rapporter.

### Task 5: Stand-in og fuld rehearsal (lokal, 0 Actions-min)

- [ ] **Step 1: Stand-in af prod efter 4.1c.** Restore `~/.private/daa-prod-20260918101922.dump`
  (sidste prod-backup, taget før 4.1c-apply) til en ny lokal base `daa44_standin_<ts>`
  med 148c's rolle-/restore-mønster; kør 4.1c's klausul-apply lokalt via
  `DAA_CONNECTION_MODE=local` og `~/.private/148c-prod/0{3,4}-clause-*-prod.R` med
  148c-manifestet; kræv 591/868/617/251. `pg_dump -Fc --no-owner` → `~/.private/147-44-prod/standin-<ts>.dump`.
  NB: stand-in mangler 20/9's medie-DDL; uden betydning for 4.4, men derfor er det den
  rigtige dagsdump i runbookens trin 2, der er beviset.
- [ ] **Step 2: Rehearsal.** `zsh 03-restore-rehearsal.sh <standin.dump>` → `REHEARSAL_OK`;
  rensede tal: 8 elementer, 84 claims, 88 links, 13/6, fresh `match`, replay `match`,
  restore-hash identisk før/efter fortrydelse.
- [ ] **Step 3: Angrebstests** (hver skal STOPPE med navngiven kode, ingen skrivning):
  `PYTHONOPTIMIZE=1` + `PGHOSTADDR=192.0.2.1` i miljøet → uændret `REHEARSAL_OK`;
  kommentarlinje tilføjet `verify.sql` → `fil-hashes afviger fra GO-pakken`; `04-apply.sh`
  uden argument → exit 2; forkert `DAA_EXPECTED_TARGET` → STOPPORT før dry-run; replay-
  komparator med dry-run-/apply-autorisations-id → `INTERPRETATION_PROJECTION_REPLAY_DRIFT`;
  `after.json` byttet med `replayed.json` i fresh → ikke-`match`;
  `DAA_REIMPORT_ACTOR_ID=<fremmed uuid>` og en forkert, eksporteret `DAA_PREVIEW_SHA256` i
  operatørens shell → uændret `REHEARSAL_OK` (`run_r`'s `env -i` lader intet igennem);
  en ekstra `reimport_writer_profile`-række indsat mellem `pre-dry` og `before` (kopi) →
  `assert_profile_delta` STOP; en gammel `issued`-autorisation for manifestet indsat før
  preflight (kopi) → tomheds-porten STOP; en `extraction_run` med en af manifestets
  run-keys (kopi) → preflight STOP; en sekvens flyttet med `nextval` efter dump (kopi) →
  restore-hash-porten STOP; en ekstra fremmed
  autorisation indsat mellem `pre-dry` og `before` (via service_role på en kopi) →
  `assert_projection_delta` STOP; en `public`-række ændret mellem dump og sekvens (kopi) →
  restore-hash-porten STOP; en række i en ikke-4.4-tabel ændret under sekvensen (kopi,
  fejlinjektion) → `untouched_hash`-porten STOP; `06-recover.sh` på en runmappe med
  `apply-receipt.json` → STOP; tredje genoptagelse → NO-GO. `04-apply.sh` testes
  KUN for de porte, der ligger før enhver forbindelse (argument, fil-hashes, freeze,
  dump-kvittering) — den forbinder altid til `~/.Renviron`s prod og må derfor aldrig nå
  forbindelsesstadiet i en test. Selve sekvensen er bevist gennem 03, som kører de samme
  bytes (`run_proposal_sequence`).
- [ ] **Step 4: Restore-troskab for restore-hashen.** Stand-in-basens `restore-hash.sql` =
  hashen efter `pg_dump -Fc` → `pg_restore` til en ny base. Afviger de, er 04's
  skrivepause-bevis (Step 3 punkt 3) ubrugeligt som formuleret: find tabellen og ret
  hashen (fx en kolonne hvis tekstform afhænger af restore), dokumentér det — slæk aldrig
  kravet til »ingen skrivning siden dump«.
- [ ] **Step 5:** Bevar stand-in-dump, rehearsal-base og rapporter til Task 7.

### Task 6: Runbook

**Files:**
- Create: `docs/runbooks/interpretation-proposal-prod-apply.md`

- [ ] **Step 1:** Skriv runbooken med 4.1c-runbookens afsnit 1-9 som skelet, og 4.4's
  deltaer: manifest-/preview-/profil-hashes (filversion `1.0.0`); 24-fil-listen; én login
  med rolle-adskilt operation/autorisation og rolleproben; sekvensen fra Task 4 Step 1;
  Autorisationstabellen; `06-recover.sh` med udfaldstabellen (afbrudt 04 → ALDRIG 04 igen,
  altid 06); GO-pakkens liste inkl. kvitteringen fra 2026-09-23 og at 4.1c's
  fortrydelsesvindue lukkes; **skrivekanaler, der skal stå stille fra `00-freeze begin` til
  `00-freeze end`**: web-redaktørfladen (redaktion = 1 = projektejeren), mobil-dev mod prod,
  andre Claude-/Codex-sessioner og R-/Python-scripts med `~/.Renviron`, Supabase-dashboardets
  SQL-editor, andre reimports/prod-scripts; hvad der *beviser* pausen (restore-hash
  02 → 04, `untouched_hash` 04 → 05) og hvad det ikke dækker (skrivninger i 4.4's egne
  tabeller under kørslen fanges af komparatorerne, ikke af hashen); stopregler; fælder
  (dry-run-profilrække varig, `already_applied` i apply-fasen er STOP, aktør-ID kun i
  0600-filer, `DAA_FAULT`/`DAA_REIMPORT_ACTOR_ID` i miljøet er STOP); §9:
  status/changelog/database-current-state/4.4-rapport, Advisors,
  `interpretation_predicate_fk`-indeks før skala.
- [ ] **Step 2: Commit.**

```bash
git add docs/runbooks/interpretation-proposal-prod-apply.md
git commit -m "docs(runbook): prod-procedure for 4.4's forslags-kørsel (#147)"
```

### Task 7: Codex-review (gpt-5.6-sol) og rettelser

- [ ] **Step 1:** Kopiér de 16 private filer + runbook til en review-mappe i scratchpad
  (INGEN manifest, cache, rapporter eller dumps). Kør Codex sol read-only
  (`sandbox-exec`-profilen, `--skip-git-repo-check`, `< /dev/null`) med opgaven: find
  måder, hvorpå en stopport kan omgås, en skrivning kan ske før bindingerne, eller
  rehearsal og prod kan køre forskellige bytes.
- [ ] **Step 2:** Verificér hvert fund empirisk før rettelse; ret; gentag Task 5 Step 2-3.
  Runder til GO.
- [ ] **Step 3: Commit** runbook-rettelser (scripts er private).

---

## Efter planen (ikke en del af den)

Push + draft-PR (kræver projektejerens ja; indeholder også d778a82). Derefter kører
projektejeren trin 1 (`00-freeze begin`, `01`, `02`) → AI eller projektejer kører `03`
mod dagens dump → GO-pakke → projektejerens GO → `04 --jeg-mener-det` (ved afbrydelse:
`06-recover.sh --jeg-mener-det <runmappe>`) → `05` → `00-freeze end`.
