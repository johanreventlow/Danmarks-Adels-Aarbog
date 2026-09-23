# 4.4 prod-wrapper — første `interpretation_proposal`-kørsel i prod: plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (native) to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En øvet, hash-bundet og fail-closed prod-procedure (runbook + private scripts),
der lader projektejeren skrive 4.3b's 84 fortolkningsforslag som `proposed` i prod og
bevise resultatet med #196's projektion og komparator.

**Architecture:** Samme form som 4.1c (`docs/runbooks/clause-evidence-prod-apply.md` +
`~/.private/148c-prod/`): seks private scripts `00-freeze … 05-verify` med fælles
`lib.zsh`, to hærdede R-kopier, restore-rehearsal af netop dagens dump med lokal
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
  `4e39fff44db0cdab7ff35d59fe852f317dc608e818c4b2dd8ff060190fdc625c`.
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

1. **Forbindelsen forsvinder omkring apply-commit** → udfaldet afgøres med én læse-kun
   forespørgsel bundet til manifest-hash, mål og profil; ingen ny autorisation (Task 3, 6).
2. **Replay-trinnet kører på et forkert grundlag** (efter-projektion taget efter replay, eller
   autorisation genbrugt) → replay-komparatoren skal fejle `REPLAY_DRIFT` (Task 4 negativ).
3. **Arvet miljø** (`PGHOSTADDR`, `PYTHONOPTIMIZE`, `PGOPTIONS`) slår en stopport fra →
   rehearsal med begge sat giver uændret resultat (Task 5).
4. **Klausul-citater løser ikke i prod** (4.1c-klausulerne afviger fra 4.3b's) → preflight
   tæller `84/84` citater løst før enhver skrivning (Task 3).
5. **En levende person blandt de 8 records** → preflight kræver 0 (Task 3); ellers STOP.

---

## Filstruktur

Private (`~/.private/147-44-prod/`, ikke i git):

| Fil | Ansvar |
|---|---|
| `lib.zsh` | faste stier/hashes, forbindelse, målbinding, manifest-/profil-/GO-hash-validering, `run_proposal_sequence` (fælles for 03 og 04) |
| `00-freeze.sh` | skrivepause begin/end (kopi af 148c, uændret logik) |
| `01-preflight.sh` | læse-kun: mål, 4.1c-forudsætning, tomhed, citater, persona, levende, forældreløse, redaktion=1 |
| `02-dump.sh` | læse-kun dump + kvittering (kopi af 148c) |
| `03-restore-rehearsal.sh` | lokal restore af dagens dump, fuld sekvens, verify-SQL, db-verify, fortrydelsesøvelse |
| `04-apply.sh` | `--jeg-mener-det`; bindinger; `run_proposal_sequence` mod prod |
| `05-verify.sh` | læse-kun slutprojektion + genkørsel af begge komparatorer + supplerende SQL |
| `03-proposal-dryrun-prod.R` | hærdet dry-run; indsætter profilrækken varigt |
| `04-proposal-apply-prod.R` | hærdet apply/replay med ekstern autorisation i egen rolle-transaktion |
| `verify.sql`, `state-hash.sql`, `rollback-preflight.sql` | læse-kun SQL (de to sidste kopieret fra 148c) |

Repo (committes):

| Fil | Ansvar |
|---|---|
| `docs/runbooks/interpretation-proposal-prod-apply.md` | autoritativ procedure, GO-pakke, stopregler, fortrydelse |
| `docs/superpowers/plans/2026-09-23-4-4-prod-wrapper.md` | denne plan |

---

### Task 1: Fundament — `lib.zsh`, freeze, dump, manifest-binding

**Files:**
- Create: `~/.private/147-44-prod/lib.zsh`, `00-freeze.sh`, `02-dump.sh`,
  `state-hash.sql`, `rollback-preflight.sql`

**Interfaces:**
- Produces: `validate_manifest` (udskriver fil-SHA), `validate_profile`, `target_identity`,
  `assert_expected_target`, `project_database <out> [psql-args]`, `verify_go_hashes`,
  `assert_repo_clean`, `assert_freeze_active`, `assert_freeze_report`, `read_dump_receipt`,
  konstanter `DAA_MANIFEST DAA_MANIFEST_FILE_SHA256 DAA_MANIFEST_CONTENT_SHA256
  DAA_PROFILE DAA_PROFILE_ID DAA_PROFILE_SHA256 DAA_PREVIEW_SHA256`.

- [ ] **Step 1: Kopiér forlæg.** `cp -p ~/.private/148c-prod/{lib.zsh,00-freeze.sh,02-dump.sh,state-hash.sql,rollback-preflight.sql} ~/.private/147-44-prod/`
- [ ] **Step 2: Skift konstanter i `lib.zsh`:**

```zsh
DAA_PRIVATE_DIR="${DAA_PRIVATE_DIR:-$HOME/.private/147-44-prod}"
DAA_MANIFEST="$HOME/.private/43b-kørsel/proposal-manifest.json"   # ikke overstyrbar
DAA_PROFILE="$DAA_REPO/.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json"
DAA_COMPARATOR="$DAA_SQL_DIR/compare_interpretation_proposal_projection.py"
DAA_PROFILE_ID="daa-2018-20-interpretation-proposal-v1"
DAA_PROFILE_VERSION="interpretation-proposal-v1"
DAA_MANIFEST_FILE_SHA256="c310ca6325b5a3a10c895a0f80161a51a0c24b61c902b807d34c7f8433c65aad"
DAA_MANIFEST_CONTENT_SHA256="a328ede946140a1223be3077d18579d94f763812875a55d67abed00645313cf8"
DAA_PROFILE_SHA256="4e39fff44db0cdab7ff35d59fe852f317dc608e818c4b2dd8ff060190fdc625c"
DAA_PREVIEW_SHA256="$DAA_MANIFEST_FILE_SHA256"
```
Fjern `DAA_RENDITION_SHA256`, `DAA_LEDGER_FILE_SHA256`, `parent_hash_match`. `target_identity`
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
}
```
Målt i manifestfilen 2026-09-23 (kun tal): 8 ops, 84 claims, 88 citater over 19 distinkte
klausuler, 68/16, alle 8 elementer har mindst ét `principal`-claim.

- [ ] **Step 4: Opdatér `verify_go_hashes`' og `assert_repo_clean`'s filmængde** til 4.4:
  private `00-freeze.sh 01-preflight.sh 02-dump.sh 03-restore-rehearsal.sh 04-apply.sh
  05-verify.sh lib.zsh 03-proposal-dryrun-prod.R 04-proposal-apply-prod.R verify.sql
  state-hash.sql rollback-preflight.sql` (12) + repo `apply_reimport_helpers.R`,
  `interpretation_proposal_projection.psql`, `interpretation_proposal_projection.sql`,
  `interpretation_proposal_anon_projection.sql`, `interpretation_proposal_target_identity.sql`,
  `compare_interpretation_proposal_projection.py`, profil-JSON (7) + manifestfilen (1) =
  **eksakt 20**. `assert_repo_clean` dækker de 7 repo-stier.
- [ ] **Step 5: Test.** `zsh -c 'source ~/.private/147-44-prod/lib.zsh; validate_manifest && echo MANIFEST_OK'`
  → `MANIFEST_OK`. Mutant: kopiér manifestet til `$DAA_PRIVATE_DIR/mutant.json`, ændr én
  `confidence` med python, peg en midlertidig `DAA_MANIFEST` dertil i en subshell → STOPPORT
  (fil-hash). Slet mutanten bagefter.
- [ ] **Step 6: `00-freeze.sh`/`02-dump.sh`:** kun sti-/navneændringer (148c → 147-44).
  Kør `zsh -n` på begge.

### Task 2: Hærdede R-kopier (dry-run, apply, replay)

**Files:**
- Create: `~/.private/147-44-prod/03-proposal-dryrun-prod.R`, `04-proposal-apply-prod.R`

**Interfaces:**
- Consumes: `apply_reimport_helpers.R` (`execute_reimport(..., authorization_policy="external")`,
  `new_reimport_dbi_gateway(connect, transaction_setup=)`, `reimport_writer_expected_counts`,
  `reimport_authorized_payloads_json`).
- Produces:
  - `03-proposal-dryrun-prod.R <manifest>` → stdout `DRY_RUN_OK`; profilrække varig.
  - `04-proposal-apply-prod.R <manifest> apply|replay <out.json>` → skriver 0600
    `{"authorization_id","principal_id","status","committed","preview_sha256"}` til
    `<out.json>` (må ikke findes); stdout kun status og `APPLY_OK`/`REPLAY_OK`.

- [ ] **Step 1: Forbindelses-præambel** kopieres ordret fra
  `~/.private/148c-prod/04-clause-apply-prod.R` linje 1-60 (argument-tjek tilpasset,
  `PG*`-rydning, prod/local-mode, `assert_target`).
- [ ] **Step 2: Rolle-adskilt gateway og autorisation** (fra #196-integrationen, én login):

```r
actors <- q("SELECT id::text i FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 2")$i
if (length(actors) != 1L || !nzchar(actors[[1L]])) stop("REDAKTION_ACTOR_NOT_UNIQUE", call. = FALSE)
actor <- actors[[1L]]
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
kun til `<out.json>` (0600), aldrig til stdout.

- [ ] **Step 3: Fase-logik i `04`:**

```r
phase <- args[[2L]]; out <- args[[3L]]
if (!(phase %in% c("apply", "replay"))) stop("PHASE_INVALID", call. = FALSE)
if (file.exists(out)) stop("OUT_EXISTS", call. = FALSE)
assert_target()
auth_id <- authorize()
res <- execute_reimport(manifest, preview_sha, "apply", gateway(), list(id = auth_id),
                        authorization_policy = "external")
want <- if (identical(phase, "apply")) "finalized" else "already_applied"
if (!identical(res$status, want) || !isTRUE(res$committed))
  stop("PHASE_RESULT_UNEXPECTED:", res$status, call. = FALSE)
writeLines(jsonlite::toJSON(list(authorization_id = auth_id, principal_id = actor,
  status = res$status, committed = res$committed, preview_sha256 = preview_sha),
  auto_unbox = TRUE), out); Sys.chmod(out, "0600")
cat(if (identical(phase, "apply")) "APPLY_OK\n" else "REPLAY_OK\n")
```
`apply`-fasen afviser altså `already_applied` (så en genkørsel efter ukendt udfald ikke
tavst »lykkes«), og `replay` afviser `finalized`.

- [ ] **Step 4: `03-proposal-dryrun-prod.R`:** præambel (Step 1) + profil-hash fil=base
  (`private.reimport_canonical_json_sha256`) + `INSERT … ON CONFLICT DO NOTHING` + readback
  af `(source_id, profile_id, profile_version, profile_sha256)` = konstanter +
  `execute_reimport(..., "dry-run", gateway(), list(id = authorize()), authorization_policy="external")`
  (samme `authorize()` som Step 2 — dry-run-scriptet får derfor samme præambel-kode);
  kræv `finalized`, `committed=FALSE`, uændret antal `interpretation`-rækker; `DRY_RUN_OK`.
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
  autorisationer (tæl før/efter).

### Task 3: `01-preflight.sh` og `verify.sql`

**Files:**
- Create: `~/.private/147-44-prod/01-preflight.sh`, `verify.sql`

- [ ] **Step 1: Preflight-assertions** (alle i kode; rapport kun tal/koder/hashes;
  `PREFLIGHT_OK`):
  1. ingen argumenter; `validate_manifest`; `validate_profile`;
  2. målidentitet + rolletest `anon` (ordret fra 148c `01-preflight.sh`);
  3. 4.1c-forudsætning: præcis én `finalized` batch med 591 `clause_evidence`-events for
     `daa-2018-20-clause-evidence-v1`, og 868 klausul-observationer;
  4. tomhed: 0 `interpretation_proposal`-events, 0 `interpretation` med
     `method='model'` for source 1, ingen profilrække for `DAA_PROFILE_ID`, 0 aktive
     (`issued`, ikke udløbne) autorisationer;
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
  7. persona og levende for de 8 records (samme `parent`-CTE; `expected_records(record_key)`
     er manifestets 8 `source_record_key` som genereret `VALUES`-liste):

```sql
SELECT count(*) FILTER (WHERE pm.n = 1)::text || '|' ||
       count(*) FILTER (WHERE pe.levende)::text || '|' || count(*)::text
  FROM expected_records e JOIN parent p USING (record_key)
  CROSS JOIN LATERAL (SELECT count(*) n, min(spm.persona_id::text)::uuid persona_id
      FROM private.source_mention sm JOIN private.source_persona_mention spm ON spm.mention_id=sm.id
     WHERE sm.observation_id=p.parent_id AND spm.mention_role='primary') pm
  LEFT JOIN private.source_persona_identity spi ON spi.source_persona_id=pm.persona_id AND spi.decision_status='accepted'
  LEFT JOIN public.person pe ON pe.id=spi.canonical_person_id;
```
     Krav: `8|0|8` — alle 8 elementer har `principal`-claims (målt), så alle 8 records skal
     have præcis én primær persona; `levende` skal være 0.
- [ ] **Step 2: Kør preflight-SQL'en** (psql direkte, `DAA_CONNECTION_MODE=local`-ækvivalent:
  `PGHOST=localhost`) mod stand-in → notér tallene; ret kun forventninger, der er forklaret.
- [ ] **Step 3: `verify.sql`** (læse-kun, `COLLATE "C"`, kun tal): events/batches for
  profilen (8 events, 1 `finalized` batch), forslag 84, uden link 0, `principal` uden
  persona 0, dispositionsfordeling for kørslens klausuler (13/6), forældreløse 0.
  Køres i rehearsal (Task 4) før den må bruges i 05.

### Task 4: `run_proposal_sequence`, `03-restore-rehearsal.sh`, `04-apply.sh`, `05-verify.sh`

**Files:**
- Create: `~/.private/147-44-prod/03-restore-rehearsal.sh`, `04-apply.sh`, `05-verify.sh`
- Modify: `~/.private/147-44-prod/lib.zsh` (tilføj `run_proposal_sequence`, `sanitize_report`)

- [ ] **Step 1: Fælles sekvens i `lib.zsh`** — de SAMME bytes kører i rehearsal og prod:

```zsh
run_proposal_sequence() {   # $1 = runmappe (0700); forbindelse sat af kalderen
  local run="$1" target
  target="$(target_identity)"; assert_expected_target "$target"
  Rscript "$DAA_PRIVATE_DIR/03-proposal-dryrun-prod.R" "$DAA_MANIFEST" > "$run/dryrun.log" 2>&1 \
    || fail "dry-run fejlede"
  /usr/bin/grep -qx DRY_RUN_OK "$run/dryrun.log" || fail "DRY_RUN_OK mangler"
  project_database "$run/before.json" -v source_id=1
  Rscript "$DAA_PRIVATE_DIR/04-proposal-apply-prod.R" "$DAA_MANIFEST" apply "$run/apply.json" \
    > "$run/apply.log" 2>&1 || fail "apply fejlede — kør IKKE igen; se §5 ukendt udfald"
  project_database "$run/after.json" -v source_id=1
  local principal; principal="$(/usr/bin/python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["principal_id"])' "$run/apply.json")"
  /usr/bin/python3 -I "$DAA_COMPARATOR" --mode fresh --manifest "$DAA_MANIFEST" \
    --before "$run/before.json" --after "$run/after.json" --expect-target-sha256 "$target" \
    --expect-preview-sha256 "$DAA_PREVIEW_SHA256" --expect-principal-id "$principal" \
    --report "$run/fresh.json" > /dev/null || fail "fresh-komparator gav ikke match"
  Rscript "$DAA_PRIVATE_DIR/04-proposal-apply-prod.R" "$DAA_MANIFEST" replay "$run/replay.json" \
    > "$run/replay.log" 2>&1 || fail "replay fejlede"
  project_database "$run/replayed.json" -v source_id=1
  local rid; rid="$(/usr/bin/python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["authorization_id"])' "$run/replay.json")"
  /usr/bin/python3 -I "$DAA_COMPARATOR" --mode replay --after "$run/after.json" \
    --replayed "$run/replayed.json" --replay-authorization-id "$rid" \
    --expect-target-sha256 "$target" --report "$run/replay-match.json" > /dev/null \
    || fail "replay-komparator gav ikke match"
  assert_report_chain "$run"   # fresh.input_file_sha256.after == replay-match.input_file_sha256.after
                               # == sha256(after.json); counts = 8/84/88/{13,6}
  sanitize_report "$run/fresh.json" > "$run/fresh-renset.json"
  sanitize_report "$run/replay-match.json" > "$run/replay-renset.json"
}
```
`assert_report_chain` og `sanitize_report` skrives som `python3 -I`-heredocs med
`raise SystemExit` (renseren som 4.1c-runbook §5.2: kun status/code/scope/counts/target/
længder).

- [ ] **Step 2: `03-restore-rehearsal.sh`** = 148c-udgaven med disse ændringer: kalder
  `run_proposal_sequence` mellem før-/efter-tilstands-hash; kører `verify.sql` mod
  restoren; kører `db-rls.sql` → `tests/sql/run-db-verify-disposable.sql` (kun lokalt);
  fortrydelsesøvelse: `pg_restore --clean --if-exists --no-owner --schema=private
  --schema=public` oven på den befolkede base, krav 0 `interpretation_proposal`-events,
  0 model-forslag, ingen profilrække, tilstands-hash = før; fejl-tilladelsesliste som 148c
  (vault-klassen + de tre RLS-afhængige funktioner i begge beskedformer). Kør
  `DAA_CONNECTION_MODE=local`. Slut: `REHEARSAL_OK` + rapport-hashes.
- [ ] **Step 3: `04-apply.sh`** = 148c-udgaven med: `--jeg-mener-det` påkrævet (exit 2
  ellers); bindinger (commit, 20 fil-hashes, mål, dump-kvittering, rehearsal-rapport,
  freeze-rapport); 0 `change_set` siden dump-start; preflightens tomheds- og
  citat-assertions gentaget læse-kun; derefter `run_proposal_sequence` mod prod;
  `APPLY_DONE`.
- [ ] **Step 4: `05-verify.sh`**: tag `final.json`-projektion; kræv at den parset er lig
  `replayed.json` parset (ingen skrivning siden replay); genkør begge komparatorer mod
  apply-rundens filer med NYE rapportstier; `verify.sql`; skriv `verify-ok.json`;
  `VERIFY_OK`.
- [ ] **Step 5: `zsh -n` på alle seks scripts.** Forventet: ingen output.

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
  tilstands-hash identisk før/efter fortrydelse.
- [ ] **Step 3: Angrebstests** (hver skal STOPPE med navngiven kode, ingen skrivning):
  `PYTHONOPTIMIZE=1` + `PGHOSTADDR=192.0.2.1` i miljøet → uændret `REHEARSAL_OK`;
  kommentarlinje tilføjet `verify.sql` → `fil-hashes afviger fra GO-pakken`; `04-apply.sh`
  uden argument → exit 2; forkert `DAA_EXPECTED_TARGET` → STOPPORT før dry-run; replay-
  komparator med dry-run-/apply-autorisations-id → `INTERPRETATION_PROJECTION_REPLAY_DRIFT`;
  `after.json` byttet med `replayed.json` i fresh → ikke-`match`. `04-apply.sh` testes
  KUN for de porte, der ligger før enhver forbindelse (argument, fil-hashes, freeze,
  dump-kvittering) — den forbinder altid til `~/.Renviron`s prod og må derfor aldrig nå
  forbindelsesstadiet i en test. Selve sekvensen er bevist gennem 03, som kører de samme
  bytes (`run_proposal_sequence`).
- [ ] **Step 4:** Bevar stand-in-dump, rehearsal-base og rapporter til Task 7.

### Task 6: Runbook

**Files:**
- Create: `docs/runbooks/interpretation-proposal-prod-apply.md`

- [ ] **Step 1:** Skriv runbooken med 4.1c-runbookens afsnit 1-9 som skelet, og 4.4's
  deltaer: manifest-/preview-/profil-hashes; 20-fil-listen; rolle-adskilt
  operation/autorisation; sekvensen fra Task 4 Step 1; ukendt-udfald-forespørgsel bundet
  til `manifest_sha256=a328ede9…`, mål og profil, med tabellen (0 rækker → må køres én gang
  mere mod SAMME GO; 1 `finalized` med 8 events → gå til 05; alt andet NO-GO → restore);
  GO-pakkens liste inkl. kvitteringen fra 2026-09-23 og at 4.1c's fortrydelsesvindue lukkes;
  stopregler; fælder (dry-run-profilrække varig, `already_applied` i apply-fasen er STOP,
  aktør-ID kun i 0600-filer); §9: status/changelog/database-current-state/4.4-rapport,
  Advisors, `interpretation_predicate_fk`-indeks før skala.
- [ ] **Step 2: Commit.**

```bash
git add docs/runbooks/interpretation-proposal-prod-apply.md
git commit -m "docs(runbook): prod-procedure for 4.4's forslags-kørsel (#147)"
```

### Task 7: Codex-review (gpt-5.6-sol) og rettelser

- [ ] **Step 1:** Kopiér de 12 private scripts + runbook til en review-mappe i scratchpad
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
mod dagens dump → GO-pakke → projektejerens GO → `04 --jeg-mener-det` → `05` →
`00-freeze end`.
