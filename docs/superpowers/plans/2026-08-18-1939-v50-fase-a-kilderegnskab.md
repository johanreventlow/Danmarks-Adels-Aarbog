# 1939 v50 Fase A: Kilderegnskab for de eksisterende poster — taskplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skriv de 584 endnu ikke materialiserede source records (592 fra
kilderegnskabet minus de 8 allerede skrevne person-creates) til prod som
source-only evidens med byte-ankre i Calamari-renditionen — nul kanonisk
delta, ingen DDL.

**Architecture:** Genbrug task 25's SQL-writer uændret
(`red_authorize_1939_v50_reimport` → `red_begin` →
`red_apply_1939_v50_source_evidence` × 584 → `red_finalize`). Nyt arbejde er
kun: (1) en deterministisk Python-manifest-bygger, (2) en hard-låst R-wrapper
efter `apply_reimport_1939_v50.R`-mønstret, (3) rehearsal + GO-pakke.
Persona/identitet for eksisterende personer er BEVIDST udeladt — det hører
til fase C, hvor `red_decide_source_persona_identity`-maskineriet bor.

**Tech Stack:** Python 3 + pytest (`.claude/skills/daa-extract/scripts/`),
R + testthat (DB-fri gateway-tests), PostgreSQL 17 lokalt, psql mod prod.

**Spec:** `docs/superpowers/plans/2026-08-18-1939-v50-resten-af-genimporten.md`
(fase A) + kilderegnskabet i `work/task21-1939-v50-import-preview/import-preview-v1.json`.

## Global Constraints

- Prod-apply er IKKE en del af denne plan: Task 5 slutter i en GO-pakke;
  selve apply kræver særskilt brugergodkendelse med eksakte hashes + ny
  umiddelbar backup.
- Verbatim/spans/rendition er byte-eksakte; INGEN normalisering her.
- `load_daa.R` røres ikke. Ingen DDL. Supabase MCP `execute_sql` er
  read-only — bruges kun til efterkontrol.
- Deterministisk output: ingen tidsstempler/tilfældighed i manifestindhold;
  dobbeltkørsel skal være byte-identisk.
- Låste input-hashes (verificeres i kode, fail-closed):
  - `import-preview-v1.json` (task 21) — beregn og lås SHA i Task 1 Step 1.
  - `production-write-manifest-v1.json` byte-SHA
    `8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f`.
  - Calamari-rendition indhold: SHA
    `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`
    (samme fil/konvention som `prepare_reimport_1939_v50.py` bruger).
- work/-artefakter committes aldrig.

## Faktagrundlag (verificeret 2026-08-18 — implementer må ikke gen-udlede)

- `import-preview-v1.json['source_records']`: 592 entries med
  `new_record_key`, `record_kind` (584 `unclassified`, 6
  `structural_context`, 2 `cross_reference`), `source_span`
  (`char_from`/`char_to`), `verbatim_text`, `disposition`,
  `person_creation` (543 `requires_existing_anchor`, 49 `forbidden`).
  Ingen `page_evidence` — den slås op i boundary-materialiseringen.
- Sider:
  `work/task20-1939-full/boundary-materialization-v3-ditlev.json`
  (SHA-256 `73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f`
  = import-preview'ets låste `materialization_sha256`) har
  `source_record_review.records` (592) med `source_anchor`
  (`char_from`/`char_to`), `span.page_from`/`span.page_to` og
  `verbatim_text`. Opslag = `_boundary_pages`-mønstret i
  `build_provenance_review_1939_v50.py`: match på (char_from,char_to) OG
  verbatim-lighed; manglende/tvetydigt opslag aborterer.
- Calamari-filen ligger i HOVED-repoet:
  `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle/full_ocr_calamari_r6_clean.txt`
  (verificeret SHA `020123a3…`).
- Låste input-SHA'er (beregnet 2026-08-18):
  `import-preview-v1.json` =
  `04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5`;
  `database-preview-v1.json` =
  `a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c`.
- `mapped_existing` (543 entries): `baseline_record_key` + `new_record_key`
  + `legacy_name` + kandidater. Indeholder IKKE person-id.
- Kanonisk person-id kommer fra
  `work/task21-1939-v50-import-preview/database-preview-v1.json`
  `['person_anchors']['matched']`: 543 entries på formen
  `{"baseline_record_key": …, "person_id": 1022}`. Person-id'er for
  eksisterende personer er uberørte af task 25/publikation/cutover, så
  mappingen er fortsat gyldig; byggeren SKAL alligevel assert'e 1:1-opløsning
  (hver af de 543 baseline-keys → præcis ét person_id).
- De 8 allerede skrevne record-keys står i `PRODUCTION_NEW_NAMES` i
  `build_production_write_manifest_1939_v50.py` og i task 25-manifestets
  `person_creates`.
- SQL-payload-kontrakten (`red_apply_1939_v50_source_evidence`,
  schema.sql:2477): `disposition` SKAL være `retain_source_only`; tilladte
  nøgler er PRÆCIS delmængder af {`review_subject_id`,`source_record_key`,
  `category`,`disposition`,`evidence_sha256`,`canonical_target`,
  `source_span`,`page_evidence`,`verbatim_text`,`legacy_payload`,
  `rendition_content_sha256`}; `ensure_reimport_1939_source_evidence`
  kræver span med `char_to>char_from`, `page_from>=1`,
  `page_to>=page_from`, ikke-tom verbatim og 64-hex rendition-sha, og
  autorisationens `authorized_elements[element_id]` skal være payloaden
  byte-lig (evt. minus `category`).
- R-writerens eksisterende validator (`apply_reimport_1939_v50_helpers.R`)
  er hard-låst til task 25-tællene — derfor NY wrapper, ikke genbrug.

---

### Task 1: Fase-A-manifest-bygger (Python)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_phase_a_anchor_manifest_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_phase_a_anchor_manifest_1939_v50.py`

**Interfaces:**
- Consumes: `import-preview-v1.json`, `production-write-manifest-v1.json`,
  Calamari-tekstfil (samme sti-konvention som `prepare_reimport_1939_v50.py`).
- Produces: `phase-a-anchor-manifest-v1.json` med
  `schema_version="1939-v50-phase-a-anchor-manifest-v1"`,
  `operations` (584 source_evidence-elementer),
  `counts={"person_creates":0,"source_evidence":584,"canonical_delta":0}`,
  `input_hashes`, `manifest_content_sha256` (kanonisk sortnøgle-JSON-SHA,
  genbrug `canonical_sha` fra task 25-byggeren).

- [ ] **Step 1: Lås input-hashes**

Kør fra worktree-roden
(`/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/evidensbaseret-genimport`):

```bash
shasum -a 256 work/task21-1939-v50-import-preview/import-preview-v1.json \
              work/task21-1939-v50-import-preview/database-preview-v1.json
```

og indsæt værdierne som konstanter i testfilen og byggeren (sammen med de to
allerede kendte: task25-manifest `8417b6de…`, Calamari `020123a3…`).

- [ ] **Step 2: Skriv fejlende tests**

Testfilen bygger små syntetiske fixtures (2-3 records) OG kører mod de
rigtige artefakter, når de findes på disk (skip ellers, som eksisterende
tests gør). Minimumssæt:

```python
def test_excludes_already_written_records():
    # fixture: 3 records hvoraf 1 key er i task25-person_creates → 2 elementer
def test_element_payload_has_exactly_allowed_keys():
    # nøglesæt ⊆ kontraktens 11 nøgler; disposition == "retain_source_only"
def test_verbatim_must_match_calamari_span():
    # fixture med forkert verbatim → SystemExit/ManifestError "SPAN_MISMATCH"
def test_page_evidence_from_boundary_lookup():
    # fixture-boundary med (char_from,char_to)+verbatim+span-sider;
    # match → page_evidence sat; manglende anchor ELLER verbatim-afvigelse
    # → abort med record_key i fejlbeskeden
def test_counts_and_determinism():
    # counts == {0,584-mønstret for fixture}, to kørsler → byte-identisk output
def test_real_artifacts_full_arithmetic():
    # (skip hvis work/ mangler) 592 - 8 = 584 elementer; kategorier:
    # 576 person + 6 structural_context + 2 cross_reference;
    # 543 elementer har canonical_target.person_id sat
```

- [ ] **Step 3: Kør tests — forvent FAIL (modul findes ikke)**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_build_phase_a_anchor_manifest_1939_v50.py -q`

- [ ] **Step 4: Implementér byggeren**

Krav ud over teststrukturen:
- CLI: `--import-preview PATH --import-preview-sha256 HEX
  --database-preview PATH --database-preview-sha256 HEX
  --production-manifest PATH --production-manifest-sha256 HEX
  --calamari PATH --calamari-sha256 HEX --output PATH`; alle hashes
  verificeres mod filbytes før parsing (mønster: `_validate_hashes` i
  task 25-byggeren); output-fil må ikke findes i forvejen.
- Element: `element_id = "phase-a:" + new_record_key`;
  `review_subject_id = new_record_key`; `category`: `person` når
  `record_kind=="unclassified"`, ellers `record_kind` uændret;
  `canonical_target = {"person_id": <id>}` kun for de 543
  (`person_creation=="requires_existing_anchor"`), hvor `<id>` slås op via
  `mapped_existing.new_record_key → baseline_record_key →
  database-preview person_anchors.matched → person_id`; manglende opslag
  aborterer. For øvrige elementer udelades nøglen; `legacy_payload = {"baseline_record_key": …,
  "legacy_name": …}` for de 543, ellers udelades;
  `evidence_sha256 = canonical_sha(payload uden evidence_sha256)`;
  `rendition_content_sha256` = den låste Calamari-SHA.
- Sider: `page_evidence = {"page_from": …, "page_to": …}` via
  boundary-opslaget (`_boundary_pages`-mønstret, se Faktagrundlag);
  CLI får `--boundary PATH --boundary-sha256 HEX`.
- Byte-kontrol: `verbatim_text == calamari[char_from:char_to]` for HVERT
  element (tegn-eksakt, ingen normalisering) — mismatch aborterer hele
  bygningen med record_key i fejlbeskeden.
- Aritmetik-assert: elementantal == len(source_records) − antal
  task25-person_create-keys fundet i sættet; begge tal printes i
  rapporten. Manglende/ekstra keys → abort.

- [ ] **Step 5: Kør tests — forvent PASS; kør mod de rigtige artefakter**

Run (rigtig kørsel fra worktree-roden, output til work/):
```bash
ROOT=/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/evidensbaseret-genimport
/usr/bin/python3 $ROOT/.claude/skills/daa-extract/scripts/build_phase_a_anchor_manifest_1939_v50.py \
  --import-preview $ROOT/work/task21-1939-v50-import-preview/import-preview-v1.json \
  --import-preview-sha256 <låst i Step 1> \
  --database-preview $ROOT/work/task21-1939-v50-import-preview/database-preview-v1.json \
  --database-preview-sha256 <låst i Step 1> \
  --production-manifest $ROOT/work/task25-1939-v50-production-writer/production-write-manifest-v1.json \
  --production-manifest-sha256 8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f \
  --boundary $ROOT/work/task20-1939-full/boundary-materialization-v3-ditlev.json \
  --boundary-sha256 73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f \
  --calamari /Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
  --calamari-sha256 020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37 \
  --output $ROOT/work/task25-1939-v50-production-writer/phase-a-anchor-manifest-v1.json
```
Forventet: 584 elementer; notér manifest-byte-SHA og content-SHA i en
`phase-a-anchor-manifest-v1-report.md` ved siden af.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/build_phase_a_anchor_manifest_1939_v50.py \
        .claude/skills/daa-extract/scripts/test_build_phase_a_anchor_manifest_1939_v50.py
git commit -m "feat(1939): fase A-manifest-bygger for de 584 kilderecords"
```

### Task 2: Hard-låst R-writer-wrapper

**Files:**
- Create: `.claude/skills/daa-extract/scripts/apply_phase_a_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/apply_phase_a_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/test_apply_phase_a_1939_v50.R`
- Create: `tests/testthat/test-apply-phase-a-1939-v50.R` (wrapper-mønster =
  kopi af `tests/testthat/test-apply-name-completion-1939-v50.R` med nyt
  filnavn i `source(...)`)

**Interfaces:**
- Consumes: fase-A-manifestet fra Task 1; DBI-gateway-mønstret og
  CLI-konventionerne fra `apply_reimport_1939_v50{_helpers}.R` (læs dem
  som forlæg — kopiér mønstret, del ikke koden, da validatorerne er
  batch-specifikke pr. designbeslutning i dette program).
- Produces: CLI `Rscript apply_phase_a_1939_v50.R --manifest … 
  --manifest-sha256 … --preview-sha256 … --output … [--dry-run]` der kører
  authorize→begin→source_evidence×584→finalize; `--dry-run` = samme
  transaktion afsluttet med rollback (aldrig commit).

- [ ] **Step 1: Skriv fejlende DB-fri tests** (`test_apply_phase_a_1939_v50.R`,
  fake-gateway-mønster som `test_preview_narrative_publication_1939_v50.R`):
  - validator afviser: forkerte counts (person_creates≠0, andet end 584
    source_evidence, canonical_delta≠0), dublet-element-ids, element med
    `disposition!='retain_source_only'`, manglende content-sha-match;
  - succesvej: gateway-kaldsorden `connect, begin, authorize, begin_batch,
    584×source_evidence, finalize, (commit|rollback)`; `--dry-run` ender i
    rollback og `committed=false`;
  - alle fejlveje ender i præcis én rollback;
  - CLI afviser forkert manifest-hash (system2-testen, exit 1).
- [ ] **Step 2: Kør — forvent FAIL** (`Rscript test_apply_phase_a_1939_v50.R`)
- [ ] **Step 3: Implementér helpers + CLI** (genbrug env_or/sslmode- og
  `DAA_REIMPORT_ACTOR_ID`-konventionen fra `apply_reimport_1939_v50.R`;
  expected_counts til authorize:
  `{"person_creates":0,"source_evidence":584,"canonical_delta":0}`)
- [ ] **Step 4: Kør — forvent `PASS n assertions`**
- [ ] **Step 5: Kør fulde suiter**: `Rscript run-tests.R` (ny wrapper tælles
  med, FAIL 0) og `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest -q`
- [ ] **Step 6: Commit** (`feat(1939): fase A-writer-wrapper (source-only, dry-run-first)`)

### Task 3: Rehearsal mod frisk produktionsækvivalent restore

**Files:**
- Create: `work/task25-1939-v50-production-writer/phase-a-rehearsal-report.md`
  (work/ er gitignoreret — rapporten committes ikke; dens hashes gengives i
  Task 4's readiness-doc)

- [ ] **Step 1: Frisk restore**: `createdb -T daa1939_narrative_publish_rehearsal3
  daa1939_phase_a_rehearsal1` er IKKE nok — rehearsal3 er fra før
  publikation+cutover. Tag i stedet ny dump af prod (backup-scriptet i
  work/, omdøbt DEST til `daa-local-phase-a-rehearsal-<stamp>`) og
  `pg_restore` til `daa1939_phase_a_rehearsal1` (vault-posterne udelades som
  ved tidligere restores).
- [ ] **Step 2: Før-baseline**: genbrug
  `scratchpad/publication_baseline.sql`-mønstret udvidet med
  `source_record`-fulddump + tællinger for occurrence/anchor/observation/
  mention/persona/rendition; gem + SHA-256.
- [ ] **Step 3: Dry-run** (`--dry-run` mod rehearsal-basen med
  `DAA_REIMPORT_ACTOR_ID=<redaktions-uuid fra restoren>`): forvent
  `status=finalized, committed=false`; efter-baseline SKAL være
  byte-identisk med før (cmp).
- [ ] **Step 4: Committed rehearsal** (uden `--dry-run`, stadig lokal base):
  efterkontrol med read-only SQL: source_records 243+584=827,
  anchors 313+584=897, occurrences/observations/mentions +584,
  personas fortsat 8, extraction_run +1, OG kanoniske tællinger
  (person/fact/assertion/citation/conclusion/relation/family/narrative)
  byte-identiske med før-baselinens. Batch `finalized`, 584 write-events
  med operation `source_evidence`.
- [ ] **Step 5: Replay-kontrol**: kør samme apply igen mod rehearsal-basen —
  forvent idempotent retur (already-applied-vejen) med 0 nye rækker.
- [ ] **Step 6: Skriv rehearsal-rapporten** (kommandoer, hashes, tal).

### Task 4: GO-pakke + readiness-dokument

**Files:**
- Create: `docs/superpowers/reviews/1939-v50-phase-a-readiness.md`

- [ ] **Step 1: Skriv readiness-dokumentet** efter mønstret i
  `1939-v50-narrative-publication-readiness.md`: konklusion (GO for at
  forberede, prod = NO-GO), låste artefakt-hashes (manifest byte+content,
  import-preview, calamari, task25-manifest), rehearsal-evidens (tallene fra
  Task 3), fulde suite-resultater, credentialscan (0 hits), og "krævet
  fremtidig godkendelse"-listen: prod-identitet `7642734024280108049`, ny
  umiddelbar backup (sti/0600/bytes/SHA), manifest-byte-SHA, præcis én
  apply uden retry.
- [ ] **Step 2: Kør `git diff --check`** — grøn.
- [ ] **Step 3: Commit** (`docs(1939): fase A readiness — kilderegnskab klar til godkendelse`)
- [ ] **Step 4: STOP.** Fremlæg GO-pakken for brugeren. Ingen prod-apply i
  denne plan.

## Efter godkendelse (uden for planen)

Apply-mønstret er identisk med narrativ-publikationen: nyt backup-script-run
→ hash-låst wrapper-script → én apply → read-only efterkontrol mod prod
(samme tal som Task 3 Step 4) → changelog/database-current-state +
memory-opdatering.
