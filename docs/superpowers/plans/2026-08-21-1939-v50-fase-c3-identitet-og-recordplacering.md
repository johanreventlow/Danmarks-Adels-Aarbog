# Fase C3 — identitet og recordplacering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Byg en read-only, hashbundet menneskereviewkæde for C0's syv `[C3]`-records plus R40-ledsageren, med uafhængige beslutninger om personidentitet og kilderecordplacering.

**Architecture:** Fire kontrakter kobles i én envejs-kæde: C0-artefakter → deterministisk C3-selektion → strukturel read-only DB-eksport → lokalt byte-låst reviewark → tekstfri beslutnings-JSON. Hvert led binder de eksakte bytes fra forrige led og afviser count-, identitets- eller tilstandsdrift; ingen fil i denne plan kan skrive til databasen eller fungere som apply-manifest.

**Tech Stack:** Python 3.9 stdlib, pytest, R 4.x, DBI/RPostgres/jsonlite, testthat, PostgreSQL 17/Supabase.

**Spec:** `docs/superpowers/specs/2026-08-21-1939-v50-fase-c3-identitet-og-recordplacering-design.md`

**Godkendt tillæg 2026-08-21:** Specialens identitetsdefault er
`UAFKLARET`, så baseline er fail-closed ved en eksisterende, konfliktende
alias-kant. Det giver 13 uafklarede og 2 afklarede defaults. R40/A og R15/B
forbliver `TIL 1017` og `TIL 1021`.

## Global Constraints

- **Scope er præcis 7 + 1:** syv C0-beslutninger med token `[C3]`, plus R40 som låst ledsager til R15. R15 skal være blandt de syv.
- **1017/1021-kontrakten er låst:** identitetsdefault `UAFKLARET`, R40/A `TIL 1017`, R15/B `TIL 1021`; `SAMME 1021 1017` kræver et eksplicit, grafvalideret redaktørvalg.
- **To akser er uafhængige:** identitet må aldrig udlede recordplacering, og recordplacering må aldrig udlede identitet.
- **Ingen DB-mutation:** ingen apply-fil, RPC, `INSERT`, `UPDATE`, `DELETE`, DDL eller apply-manifest tilføjes i denne plan.
- **`work/` er model-blind og gitignoreret:** narrativ prosa må kun behandles lokalt i processen og må aldrig committes, udskrives på CLI eller kopieres til tests, dokumentation eller beslutnings-JSON.
- **Python er `/usr/bin/python3` 3.9.6:** brug `Dict`/`List`/`Optional` fra `typing`; ingen `dict[str, ...]`, `list[...]`, `match` eller andre nyere sprogfeatures.
- **PG-miljø er alt eller intet:** sæt alle fem `PGDATABASE`, `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, eller ingen. `env_or` falder tilbage per variabel.
- **Databaseidentitet er obligatorisk:** dokumenteret eksport bruger `--expect-database-name`; navn og `(pg_control_system()).system_identifier` bæres videre.
- **Fejlkoder er stabile:** `SCREAMING_SNAKE_CASE` med præfikset `C3_`, og de må ikke indeholde narrativ prosa.
- **Ingen delvise outputs:** alle CLI'er afviser eksisterende output og skriver først efter fuld validering.
- **Determinisme:** sortering sker på låst C0-RID/sagsrækkefølge, aldrig inputordbogens iteration eller et ID læst fra reviewarket.

## Filstruktur

| Fil | Ansvar |
|---|---|
| `build_c3_selection_1939_v50.py` | Verificerer C0-inputtene, genbruger C0's `assign_rids`, udleder 7 + 1-scope og binder begge inputhashes. |
| `export_c3_current_state_1939_v50_helpers.R` | Ren, DB-fri transformation og fail-closed validering af person-, narrativ-, bindings-, identitets- og partnerkonfliktrækker. |
| `export_c3_current_state_1939_v50.R` | Read-only CLI, der læser selection, validerer DB-identitet og kører kun `SELECT`. |
| `build_c3_review_1939_v50.py` | Validerer selection/state, definerer én fælles `review_sequence()` og renderer det lokale reviewark. |
| `convert_c3_decisions_1939_v50.py` | Importerer samme sekvens, parser positionsstrengt, validerer tokens/grafkonflikter og skriver tekstfri hashbundet JSON. |
| Fokuserede tests og én `tests/testthat`-wrapper | Beviser hvert led uden adgang til prod eller `work/`-data. |

---

### Task 1: Deterministisk C3-selektion fra C0

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_c3_selection_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_c3_selection_1939_v50.py`

**Interfaces:**
- Consumes: C0-kandidatdokumentets `records[]`, C0-beslutningsdokumentets `decisions[]`, og `assign_rids(records)` fra `convert_c0_linkage_decisions_1939_v50.py`.
- Produces: `build_selection(candidates_doc: Dict[str, Any], decisions_doc: Dict[str, Any], candidates_sha256: str, decisions_sha256: str) -> Dict[str, Any]` med schema `1939-v50-c3-selection-v1`, `input_hashes`, `cases`, `record_count=8`, `case_count=7`, `decision_line_count=15` og `person_ids`.
- Produces CLI: `--candidates PATH --c0-decisions PATH --output PATH`; stdout er kun `sager=7 records=8 beslutningslinjer=15`.

- [ ] **Step 1: Write the failing happy-path and hash-binding tests**

Create a fixture with 41 minimal records so C0's RID algorithm deterministically assigns R15 and R40. Give seven records `classification="sammenlaegning"`; their decision rows use `[C3]`. R15 has candidates 1017 and 1021. R40 has classification `kobling`, candidate 1017 and decision `[KOBL]`/`person_id=1017`.

```python
def test_builds_exact_seven_plus_companion_and_binds_both_inputs():
    candidates, decisions = fixture_documents()
    result = mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)
    assert result["input_hashes"] == {
        "c0_candidates_sha256": "a" * 64,
        "c0_decisions_sha256": "b" * 64,
    }
    assert (result["case_count"], result["record_count"],
            result["decision_line_count"]) == (7, 8, 15)
    assert [r["rid"] for r in result["cases"][-1]["records"]] == ["R15", "R40"]
```

- [ ] **Step 2: Run the focused test to verify RED**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_c3_selection_1939_v50.py -q
```

Expected: import failure because the implementation does not exist.

- [ ] **Step 3: Implement the minimal selection contract**

Import C0's RID module with `importlib.util`; validate hashes with `^[0-9a-f]{64}$`; require C0 candidate schema `1.0`, C0 decision schema `1.0`, list shapes, unique keys and exact decision/candidate key membership. Implement this core shape:

```python
C3_SCHEMA = "1939-v50-c3-selection-v1"
EXPECTED_C3_COUNT = 7
SPECIAL_RID = "R15"
COMPANION_RID = "R40"
SPECIAL_PERSON_IDS = (1017, 1021)

def build_selection(candidates_doc, decisions_doc,
                    candidates_sha256, decisions_sha256):
    records = candidates_doc.get("records")
    decisions = decisions_doc.get("decisions")
    require_sha(candidates_sha256)
    require_sha(decisions_sha256)
    if not isinstance(records, list) or not isinstance(decisions, list):
        fail("C3_SELECTION_INPUT_INVALID")
    records_by_key = unique_by_key(records, "new_record_key")
    decisions_by_key = unique_by_key(decisions, "new_record_key")
    if set(records_by_key) != set(decisions_by_key):
        fail("C3_SELECTION_KEY_MISMATCH")
    rid_by_key = c0_decisions.assign_rids(records)
    key_by_rid = {rid: key for key, rid in rid_by_key.items()}
    c3_keys = [key for key, row in decisions_by_key.items()
               if row.get("token") == "[C3]"]
    if len(c3_keys) != EXPECTED_C3_COUNT:
        fail("C3_SELECTION_COUNT_INVALID")
    for key in c3_keys:
        if records_by_key[key].get("classification") != "sammenlaegning":
            fail("C3_SELECTION_CLASS_INVALID:" + key)
    if "R15" not in key_by_rid or key_by_rid["R15"] not in c3_keys:
        fail("C3_SELECTION_R15_INVALID")
    r15 = records_by_key[key_by_rid["R15"]]
    if sorted(candidate_ids(r15)) != [1017, 1021]:
        fail("C3_SELECTION_R15_INVALID")
    if "R40" not in key_by_rid:
        fail("C3_SELECTION_R40_INVALID")
    r40_key = key_by_rid["R40"]
    r40_decision = decisions_by_key[r40_key]
    if (r40_key in c3_keys or r40_decision.get("token") != "[KOBL]"
            or r40_decision.get("person_id") != 1017):
        fail("C3_SELECTION_R40_INVALID")
    ordinary = [make_case(key, records_by_key[key], rid_by_key[key])
                for key in sorted(c3_keys, key=lambda k: int(rid_by_key[k][1:]))
                if rid_by_key[key] != "R15"]
    special = make_special_case(r15, records_by_key[r40_key])
    cases = ordinary + [special]
    person_ids = sorted({pid for case in cases
                         for pid in case["candidate_person_ids"]})
    return {"schema_version": C3_SCHEMA,
            "input_hashes": {"c0_candidates_sha256": candidates_sha256,
                             "c0_decisions_sha256": decisions_sha256},
            "case_count": 7, "record_count": 8,
            "decision_line_count": 15, "person_ids": person_ids,
            "cases": cases}
```

Define `require_sha`, `fail`, `unique_by_key`, `candidate_ids`, `make_case` and `make_special_case` immediately above `build_selection`. `make_case` copies the complete selected candidate record and adds its trusted RID; `make_special_case` sets `case_kind="1017_1021"`, `candidate_person_ids=[1017,1021]`, and stores records in `[R15,R40]` order. These helpers never read identity from review text.

Stable errors: `C3_SELECTION_HASH_INVALID`, `..._CANDIDATES_INVALID`, `..._DECISIONS_INVALID`, `..._KEY_DUPLICATE`, `..._KEY_MISMATCH`, `..._COUNT_INVALID`, `..._CLASS_INVALID:<key>`, `..._R15_INVALID`, `..._R40_INVALID`.

- [ ] **Step 4: Add adversarial tests**

Mutate one condition at a time: remove/add `[C3]`, duplicate a key, change a selected classification, remove 1021 from R15, change R40's decision/person and pass malformed hashes. Add a determinism test with reversed input arrays.

```python
def test_missing_c3_is_terminal():
    candidates, decisions = fixture_documents()
    next(row for row in decisions["decisions"]
         if row["token"] == "[C3]")["token"] = "[NY]"
    with pytest.raises(SystemExit, match="C3_SELECTION_COUNT_INVALID"):
        mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)

def test_r40_decision_drift_is_terminal():
    candidates, decisions = fixture_documents()
    rids = c0.assign_rids(candidates["records"])
    r40_key = next(key for key, rid in rids.items() if rid == "R40")
    next(row for row in decisions["decisions"]
         if row["new_record_key"] == r40_key)["person_id"] = 1021
    with pytest.raises(SystemExit, match="C3_SELECTION_R40_INVALID"):
        mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)
```

- [ ] **Step 5: Add CLI and verify GREEN**

Read each input as bytes before JSON decode, compute both hashes, reject existing output, write canonical JSON only after success, and test that stdout contains counts but no synthetic prose sentinel.

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_c3_selection_1939_v50.py -q
```

- [ ] **Step 6: Commit Task 1**

```bash
git add .claude/skills/daa-extract/scripts/build_c3_selection_1939_v50.py .claude/skills/daa-extract/scripts/test_build_c3_selection_1939_v50.py
git commit -m "feat(1939): derive locked C3 review scope"
```

---

### Task 2: Read-only eksport af aktuel strukturel tilstand

**Files:**
- Create: `.claude/skills/daa-extract/scripts/export_c3_current_state_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/export_c3_current_state_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/test_export_c3_current_state_1939_v50.R`
- Create: `tests/testthat/test-export-c3-current-state-1939-v50.R`

**Interfaces:**
- Consumes: Task 1 selection JSON; kun `person_ids`, counts og inputhashes bruges i R.
- Produces: `build_c3_current_state_1939_v50(person_ids, person_rows, narrative_rows, identity_rows, partner_conflict_rows, database_name, database_identity, generator, selection_sha256) -> list`.
- Output schema `1939-v50-c3-current-state-v1` med sorterede `persons`, `narratives`, `identity_edges`, `partner_conflicts`, databaseidentitet og `selection_sha256`.

- [ ] **Step 1: Write DB-free R contract tests**

Fixtures include 1017/1021 and ordinary candidates, one source-3 narrative each, optional binding, directed `samme_som`, normalized `ikke_samme_som` and numeric partner conflicts.

```r
doc <- build_c3_current_state_1939_v50(
  c(1017, 1021), person_rows(), narrative_rows(), identity_rows()[0, ],
  partner_rows()[0, ], "postgres", "42", "test:v1", paste(rep("a",64),collapse=""))
expect(identical(doc$schema_version, "1939-v50-c3-current-state-v1"))
expect(identical(vapply(doc$persons, function(x) x$person_id, numeric(1)), c(1017,1021)))
expect(!("tekst" %in% names(doc$narratives[[1L]])))
```

Test missing/extra/duplicate person, missing column, person/narrative `privat=TRUE` or `NA`, duplicate source-3 narrative, malformed SHA, invalid edge endpoint/role/direction, duplicate edge, binding status preservation, malformed database identity and selection hash.

- [ ] **Step 2: Run direct R test to verify RED**

```bash
cd .claude/skills/daa-extract/scripts && Rscript test_export_c3_current_state_1939_v50.R
```

Expected: missing helper failure.

- [ ] **Step 3: Implement the pure builder**

Require exact columns before `any()`. Sort numerically; normalize `ikke_samme_som` to `(least_id,greatest_id)`. Preserve only:

```text
persons: person_id, staged, privat
narratives: person_id, narrative_id, old_sha256, privat, side,
            source_record_id, binding_status
identity_edges: role, subject_id, object_id
partner_conflicts: left_person_id, right_person_id, family_id
```

Permit at most one DAA-1939 narrative per selected person and require one for every selected person. Use stable `C3_STATE_*` errors.

- [ ] **Step 4: Implement the read-only CLI**

Accept exactly `--selection`, `--output`, `--expect-database-name`. Validate selection schema/hash before connecting. Use the established `env_or` connection and only `SELECT` queries for:

```sql
SELECT current_database(), (pg_control_system()).system_identifier::text;
SELECT id AS person_id, staged, privat FROM person WHERE id = ANY($1) ORDER BY id;
SELECT n.subjekt_id AS person_id, n.id AS narrative_id,
       encode(extensions.digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex') AS old_sha256,
       n.privat, n.side, p.source_record_id, p.status AS binding_status
  FROM narrative n
  LEFT JOIN private.narrative_record_publication p ON p.narrative_id=n.id
 WHERE n.subjekt_type='person' AND n.source_id=3 AND n.subjekt_id=ANY($1);
SELECT rolle, subjekt_id AS subject_id, objekt_id AS object_id
  FROM relation
 WHERE subjekt_type='person' AND objekt_type='person'
   AND rolle IN ('samme_som','ikke_samme_som')
   AND (subjekt_id=ANY($1) OR objekt_id=ANY($1));
```

For G5, use this read-only component query and emit only IDs/family IDs:

```sql
WITH selected(person_id) AS (SELECT unnest($1::bigint[])),
components AS (
  SELECT s.person_id AS seed_id,g.pid AS member_id
    FROM selected s
    CROSS JOIN LATERAL public._samme_som_gruppe(s.person_id) g
)
SELECT DISTINCT least(a.seed_id,b.seed_id) AS left_person_id,
       greatest(a.seed_id,b.seed_id) AS right_person_id,fa.family_id
  FROM family_member fa
  JOIN components a ON a.member_id=fa.person_id
  JOIN family_member fb ON fb.family_id=fa.family_id
                       AND fb.rolle='partner' AND fb.person_id<>fa.person_id
  JOIN components b ON b.member_id=fb.person_id AND b.seed_id<>a.seed_id
 WHERE fa.rolle='partner'
 ORDER BY left_person_id,right_person_id,fa.family_id;
```

Never call `red_*`. Write after validation; stdout has counts only.

- [ ] **Step 5: Add testthat wrapper and verify GREEN**

```r
testthat::test_that("export-c3-current-state R contract passes direct assertions", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  old <- getwd(); on.exit(setwd(old), add = TRUE)
  setwd(file.path(root, ".claude", "skills", "daa-extract", "scripts"))
  testthat::expect_no_error(source("test_export_c3_current_state_1939_v50.R", local=TRUE))
})
```

```bash
Rscript .claude/skills/daa-extract/scripts/test_export_c3_current_state_1939_v50.R
Rscript run-tests.R
```

- [ ] **Step 6: Audit and commit Task 2**

```bash
rg -n '\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|red_[a-z_]+\s*\()' .claude/skills/daa-extract/scripts/export_c3_current_state_1939_v50.R
git add .claude/skills/daa-extract/scripts/export_c3_current_state_1939_v50_helpers.R .claude/skills/daa-extract/scripts/export_c3_current_state_1939_v50.R .claude/skills/daa-extract/scripts/test_export_c3_current_state_1939_v50.R tests/testthat/test-export-c3-current-state-1939-v50.R
git commit -m "feat(1939): export read-only C3 state"
```

Expected: `rg` has no matches (exit 1); tests pass.

---

### Task 3: Ét deterministisk, lokalt reviewark

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_c3_review_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_c3_review_1939_v50.py`

**Interfaces:**
- Consumes: Task 1 selection og Task 2 state plus deres SHA-256.
- Produces: `review_sequence(selection_doc: Dict[str, Any], state_doc: Dict[str, Any]) -> List[Dict[str, Any]]`; items har `type`, `decision_id`, `tail`, `allowed_person_ids`, `default_token`.
- Produces: `render_review(selection_doc, state_doc, selection_sha256, state_sha256) -> str` med 15 editable linjer.
- CLI: `--selection --state --output`; stdout er counts og outputhash, aldrig tekst.

- [ ] **Step 1: Write RED sequence and golden-byte tests**

Use synthetic prose only. Six ordinary cases emit `identity,record`; special case emits `identity,R40,R15`. Ordinary defaults and the special identity default are `UAFKLARET`; the two special record defaults are locked proposals.

```python
def test_sequence_has_fifteen_decisions_and_fail_closed_special_tail():
    editable = [x for x in mod.review_sequence(selection_doc(), state_doc())
                if x["type"] != "heading"]
    assert len(editable) == 15
    assert [(x["decision_id"], x["default_token"]) for x in editable[-3:]] == [
        ("identity:1017:1021", "UAFKLARET"),
        ("record:R40", "TIL 1017"),
        ("record:R15", "TIL 1021"),
    ]
```

Add a golden SHA-256 assertion over rendered synthetic fixture bytes. Inspect the initial intentional mismatch, then lock the literal hash.

- [ ] **Step 2: Run focused test to verify RED**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_c3_review_1939_v50.py -q
```

- [ ] **Step 3: Validate state and input hashes before rendering**

Require both schemas, 64-hex hashes, `state.selection_sha256`, exact person coverage, no private/NA-private person or narrative, at most one narrative per person, and known binding states. Error messages identify IDs only.

- [ ] **Step 4: Implement the single authoritative sequence**

For ordinary records, allowed IDs are sorted unique candidate person IDs:

```python
{"type":"identity", "decision_id":"identity:<rid>",
 "default_token":"UAFKLARET", "allowed_person_ids":ids, "tail":locked_tail}
{"type":"record", "decision_id":"record:<rid>",
 "default_token":"UAFKLARET", "allowed_person_ids":ids, "tail":locked_tail}
```

Special semantics come from validated R15/R40/1017/1021 IDs, not display text. Render bracketed token plus exact tail. Candidate `verbatim_text` may appear only in output review bytes.

- [ ] **Step 5: Add fail-closed/no-leak tests and verify GREEN**

Test wrong hashes/schemas, missing/extra state, private values, duplicate narrative, special-contract drift, existing output, and stdout/stderr lacking `MODEL_BLIND_SENTINEL`.

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_c3_review_1939_v50.py -q
/usr/bin/python3 -m py_compile .claude/skills/daa-extract/scripts/build_c3_review_1939_v50.py
```

- [ ] **Step 6: Commit Task 3**

```bash
git add .claude/skills/daa-extract/scripts/build_c3_review_1939_v50.py .claude/skills/daa-extract/scripts/test_build_c3_review_1939_v50.py
git commit -m "feat(1939): build locked C3 review sheet"
```

---

### Task 4: Positionsstreng, tekstfri beslutningskonverter

**Files:**
- Create: `.claude/skills/daa-extract/scripts/convert_c3_decisions_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_convert_c3_decisions_1939_v50.py`

**Interfaces:**
- Consumes: reviewtekst, selection/state bytes og `review_sequence()` importeret fra Task 3.
- Produces: `parse_review(text: str, selection_doc: Dict[str, Any], state_doc: Dict[str, Any], input_hashes: Dict[str, str]) -> Dict[str, Any]`.
- Output schema `1939-v50-c3-decisions-v1` har kun hashes, counts, strukturerede `cases`, databaseidentitet; ingen prosa/navne/tails.
- CLI: `--review --selection --state --output`; hashes beregnes internt.

- [ ] **Step 1: Write roundtrip and axis-independence RED tests**

```python
def test_unchanged_sheet_roundtrips_without_prose():
    selection, state = docs()
    text = build.render_review(selection, state, "a"*64, "b"*64)
    out = conv.parse_review(text, selection, state, {
        "c0_candidates_sha256": "c"*64,
        "c0_decisions_sha256": "d"*64,
        "selection_sha256": "a"*64,
        "state_sha256": "b"*64,
        "review_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
    })
    assert out["counts"] == {"cases":7, "records":8,
                             "decision_lines":15, "unresolved":13}
    assert out["cases"][-1]["identity"] == {"action":"unresolved"}
    assert [x["person_id"] for x in out["cases"][-1]["record_decisions"]] == [1017,1021]
    assert "MODEL_BLIND_SENTINEL" not in json.dumps(out, ensure_ascii=False)
```

Also change only one axis and assert the other remains byte-equivalent in structured output.

- [ ] **Step 2: Run focused test to verify RED**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_convert_c3_decisions_1939_v50.py -q
```

- [ ] **Step 3: Implement exact token grammar**

```python
IDENTITY_SIMPLE = {"FORSKELLIGE", "UAFKLARET"}
RECORD_SIMPLE = {"INGEN_PUBLIKATION", "UAFKLARET"}
REVISION_KINDS = {"split_into", "merged_from", "replaced_by"}
SAMME_RE = re.compile(r"^SAMME ([0-9]+) ([0-9]+)$")
TIL_RE = re.compile(r"^TIL ([0-9]+)$")
REVISION_RE = re.compile(r"^REVISION (split_into|merged_from|replaced_by)$")
```

IDs must belong to `allowed_person_ids`; reject self-link, G3/G4 occupied alias, normalized `ikke_samme_som` and partner conflict. An exact existing alias→canonical edge may roundtrip; a different occupied direction is terminal.

- [ ] **Step 4: Implement full-document positional validation**

Import Task 3's sequence. Parse choice from the expected position, never identity from an edited RID. Re-render with chosen tokens and require exact equality for all non-token bytes, including headings and whitespace. Stable errors: `C3_REVIEW_TOKEN_INVALID`, `..._LINE_TAMPERED`, `..._LINE_MISSING`, `..._LINE_UNEXPECTED`, `..._DECISION_DUPLICATE`, `..._HASH_MISMATCH`.

- [ ] **Step 5: Emit explicit semantic JSON atomically**

```text
SAMME a c       -> {action:same, alias_person_id:a, canonical_person_id:c}
FORSKELLIGE     -> {action:different}
UAFKLARET       -> {action:unresolved}
TIL p           -> {action:assign, person_id:p}
REVISION k      -> {action:revision, relation_kind:k}
INGEN_PUBLIKATION -> {action:no_publication}
```

Carry C0 hashes from selection plus exact `selection_sha256`, `state_sha256`, `review_sha256`. Write only after every semantic and hash gate passes.

- [ ] **Step 6: Add adversarial matrix and verify GREEN**

Cover missing/extra/duplicate/swapped lines; altered heading/tail/whitespace; unknown token/person; self-link; wrong direction; G3/G4, `ikke_samme_som`, partner conflict; invalid revision; stale hashes; every legal token and valid `UAFKLARET`. Assert errors never include prose sentinel.

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_c3_review_1939_v50.py .claude/skills/daa-extract/scripts/test_convert_c3_decisions_1939_v50.py -q
/usr/bin/python3 -m py_compile .claude/skills/daa-extract/scripts/convert_c3_decisions_1939_v50.py
```

- [ ] **Step 7: Commit Task 4**

```bash
git add .claude/skills/daa-extract/scripts/convert_c3_decisions_1939_v50.py .claude/skills/daa-extract/scripts/test_convert_c3_decisions_1939_v50.py
git commit -m "feat(1939): validate C3 review decisions"
```

---

### Task 5: Integrationsbevis og lokalt review-checkpoint

**Files:**
- Runtime-only, never commit: `work/task27-1939-v50-c3-review/selection-v1.json`, `current-state-v1.json`, `c3-afgoerelser.txt`, senere `c3-afgoerelser.json`.
- Modify only if a discovered assertion gap requires it: the Task 1–4 file responsible for that contract.

**Interfaces:**
- Consumes Tasks 1–4 og eksisterende `work/task26-1939-v50-c0-record-linkage/linkage-candidates-v1.json` samt `c0-afgoerelser.json`.
- Produces det lokale checkpoint `c3-afgoerelser.txt`; beslutnings-JSON produceres først efter brugerens reviewgodkendelse.

- [ ] **Step 1: Run focused suites**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_c3_selection_1939_v50.py .claude/skills/daa-extract/scripts/test_build_c3_review_1939_v50.py .claude/skills/daa-extract/scripts/test_convert_c3_decisions_1939_v50.py -q
Rscript .claude/skills/daa-extract/scripts/test_export_c3_current_state_1939_v50.R
```

- [ ] **Step 2: Run full regressions separately**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
Rscript run-tests.R
git diff --check
```

- [ ] **Step 3: Prove no C3 writer exists**

```bash
rg -n '\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b|red_[a-z_]+\s*\(' .claude/skills/daa-extract/scripts/build_c3_selection_1939_v50.py .claude/skills/daa-extract/scripts/export_c3_current_state_1939_v50.R .claude/skills/daa-extract/scripts/export_c3_current_state_1939_v50_helpers.R .claude/skills/daa-extract/scripts/build_c3_review_1939_v50.py .claude/skills/daa-extract/scripts/convert_c3_decisions_1939_v50.py
```

Expected: no matches, exit 1.

- [ ] **Step 4: Build real selection without displaying contents**

```bash
mkdir -p work/task27-1939-v50-c3-review
/usr/bin/python3 .claude/skills/daa-extract/scripts/build_c3_selection_1939_v50.py --candidates work/task26-1939-v50-c0-record-linkage/linkage-candidates-v1.json --c0-decisions work/task26-1939-v50-c0-record-linkage/c0-afgoerelser.json --output work/task27-1939-v50-c3-review/selection-v1.json
shasum -a 256 work/task27-1939-v50-c3-review/selection-v1.json
```

Expected: only `sager=7 records=8 beslutningslinjer=15` and hash. Never print file contents.

- [ ] **Step 5: Export fresh structural state read-only**

Run with all five local `PG*` values or none:

```bash
Rscript .claude/skills/daa-extract/scripts/export_c3_current_state_1939_v50.R --selection work/task27-1939-v50-c3-review/selection-v1.json --output work/task27-1939-v50-c3-review/current-state-v1.json --expect-database-name postgres
shasum -a 256 work/task27-1939-v50-c3-review/current-state-v1.json
```

Stop on any DB-, scope-, privacy-, narrative-, binding- or graph-drift.

- [ ] **Step 6: Generate real review without printing prose**

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/build_c3_review_1939_v50.py --selection work/task27-1939-v50-c3-review/selection-v1.json --state work/task27-1939-v50-c3-review/current-state-v1.json --output work/task27-1939-v50-c3-review/c3-afgoerelser.txt
shasum -a 256 work/task27-1939-v50-c3-review/c3-afgoerelser.txt
git status --short
```

Expected: 15 decision lines reported; `work/` remains absent from Git status.

- [ ] **Step 7: Stop for human review**

Report path, three hashes, structural counts, focused/full results and commit. Do not open or quote reviewprosa. Ask for explicit approval before conversion.

- [ ] **Step 8: Convert only after explicit approval**

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/convert_c3_decisions_1939_v50.py --review work/task27-1939-v50-c3-review/c3-afgoerelser.txt --selection work/task27-1939-v50-c3-review/selection-v1.json --state work/task27-1939-v50-c3-review/current-state-v1.json --output work/task27-1939-v50-c3-review/c3-afgoerelser.json
shasum -a 256 work/task27-1939-v50-c3-review/c3-afgoerelser.json
```

Stop again. En apply-fase kræver ny brainstorm, spec, plan og GO.

## Definition of Done

- Tasks 1–4 er committed i små, selvstændigt grønne commits.
- Fokuserede og fulde Python/R-suiter rapporteres separat og passerer.
- Real selection er 7 + 1, reviewet har 15 beslutningslinjer, og alle artefakter er SHA-256-bundne.
- `work/` forbliver untracked/model-blind; ingen prosa forekommer i fixtures eller beslutnings-JSON.
- Mekanisk audit finder ingen DB-skrivevej.
- Arbejdet stopper ved det lokale reviewcheckpoint; conversion kræver eksplicit godkendelse, og apply er helt ude af scope.
