# Evidence-phase reconciliation completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make #156 fail closed on a data-free ledger of the retained 1939
artifacts, emit private contributions only for mechanically bound phases, and
refuse a production comparison while any historical phase remains unbound.

**Architecture:** A new local artifact auditor reads an explicit ignored bundle
and seals a versioned, data-free evidence ledger. It classifies every phase as
mechanically bound, afterdocumented but unbound, or unavailable. The existing
final-state reconciler accepts only ledger-v2 contributions whose artifact set,
adapter identity and output hash are locked. Real drift details go exclusively
to a mandatory private `0600` report; terminal output is data-free.

**Tech Stack:** Python 3 standard library, pytest, JSON, SHA-256, existing
DAA evidence scripts and read-only PostgreSQL snapshot SQL.

**Spec:** `docs/superpowers/specs/2026-08-29-evidence-phase-reconciliation-completion-design.md`

## Global Constraints

- This is a controlled historical integrity task for #156; it does not change
  roadmap priority or authorise production writes.
- Read private artifacts only from an explicit ignored bundle; never copy them,
  add them to Git, or print source text, names, record payloads, person IDs or
  record keys to the terminal.
- Use `/usr/bin/python3` and write all committed tests from synthetic,
  text-free fixtures only.
- The auditor, projector and reconciler never open a database connection.
- A real production snapshot requires separate explicit user authorisation.
- Preserve Task 25's missing contemporaneous GO and D1's missing manifest as
  visible evidence states; no match can retrospectively approve either.

---

### Task 1: Define and validate the versioned evidence ledger

**Files:**
- Create: `.claude/skills/daa-extract/scripts/evidence_phase_artifact_ledger.py`
- Create: `.claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py`
- Modify: `.claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py`
- Modify: `.claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py`

**Interfaces:**
- Consumes: a JSON object with `schema_version` equal to
  `daa-evidence-phase-artifact-ledger-v2`.
- Produces: `validate_ledger(document: object) -> list[PhaseEntry]`, where
  `PhaseEntry` has `phase_id`, `sequence`, `artifacts`, `adapter_id`,
  `adapter_sha256`, `projection_evidence`, `authorisation_evidence`, and an
  optional `contribution_sha256`.
- `seal_ledger(document: Mapping[str, object]) -> dict[str, object]` writes
  `ledger_content_sha256` over canonical JSON excluding that field. A ledger
  without contributions is valid as audit input; reconciliation requires one
  non-empty contribution hash for every phase.
- Define `LedgerError(ValueError)`, immutable `ArtifactEntry` and `PhaseEntry`
  dataclasses, `_is_hex_sha256(value: object) -> bool`,
  `canonical_sha256(document: Mapping[str, object], excluded_field: str) -> str`,
  and `validate_phase_rows(rows: object) -> list[PhaseEntry]`. Require unique
  phase IDs and positive, unique sequences; unique artifact roles and relative
  paths per phase; exactly `role`, `path`, `sha256`, `schema_version`, and
  `required` for each artifact; and a contribution hash only for a
  `mechanically_bound` phase.
- Rejects with stable tokens prefixed `EVIDENCE_RECONCILIATION_`.

- [ ] **Step 1: Write the failing ledger-contract tests**

```python
def test_audit_input_ledger_has_no_contribution_hash_until_projection_is_complete():
    ledger = seal_ledger({
        "schema_version": "daa-evidence-phase-artifact-ledger-v2",
        "phases": [{
            "phase_id": "task25",
            "sequence": 1,
            "artifacts": [{
                "role": "manifest", "path": "task25.json", "sha256": "a" * 64,
                "schema_version": "1939-v50-production-write-manifest-v1", "required": True,
            }],
            "adapter_id": "task25-v1", "adapter_sha256": "b" * 64,
            "projection_evidence": "mechanically_bound",
            "authorisation_evidence": "afterdocumented_authorisation_gap",
        }],
    })
    assert validate_ledger(ledger)[0].phase_id == "task25"


def test_reconciliation_ledger_rejects_an_unbound_phase_that_claims_a_contribution():
    ledger = sealed_unbound_phase_with(contribution_sha256="c" * 64)
    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_LEDGER_EVIDENCE_INVALID"):
        validate_ledger(ledger)
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py -q
```

Expected: import failure because the ledger module does not yet exist.

- [ ] **Step 3: Implement the minimal strict ledger validator**

```python
LEDGER_SCHEMA = "daa-evidence-phase-artifact-ledger-v2"
PROJECTION_STATES = {"mechanically_bound", "afterdocumented_unbound", "unavailable"}
AUTHORISATION_STATES = {
    "contemporaneous_phase_package",
    "afterdocumented_authorisation_gap",
    "unavailable",
}

def validate_ledger(
    document: object, *, require_contribution_hashes: bool = False,
) -> list[PhaseEntry]:
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_LEDGER_INVALID")
    _require(document.get("schema_version") == LEDGER_SCHEMA,
             "EVIDENCE_RECONCILIATION_LEDGER_SCHEMA_INVALID")
    _require(document.get("ledger_content_sha256") == canonical_sha256(
             document, "ledger_content_sha256"), "EVIDENCE_RECONCILIATION_LEDGER_HASH_INVALID")
    phases = document.get("phases")
    _require(isinstance(phases, list) and phases,
             "EVIDENCE_RECONCILIATION_LEDGER_INVALID")
    entries = validate_phase_rows(phases)
    if require_contribution_hashes:
        _require(all(entry.projection_evidence == "mechanically_bound" and
                     entry.contribution_sha256 for entry in entries),
                 "EVIDENCE_RECONCILIATION_INCOMPLETE")
    return entries
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Add reconciler admission tests before changing it**

```python
def test_reconcile_refuses_a_ledger_with_an_afterdocumented_phase_before_snapshot_comparison():
    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_INCOMPLETE"):
        reconcile(snapshot, contributions, sealed_unbound_ledger())
```

- [ ] **Step 6: Run the new admission test and verify RED**

Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py \
  -k incomplete -q
```

Expected: FAIL because the current reconciler accepts inventory v1 without
evidence-state admission.

- [ ] **Step 7: Upgrade the reconciler to ledger-v2 admission**

Make `reconcile()` accept a sealed v2 ledger, validate it with
`require_contribution_hashes=True`, and verify a one-to-one exact match between
each ledger `phase_id`/`contribution_sha256` and the submitted sealed
contribution. Perform this admission before `_validate_snapshot()` so an
incomplete historical phase never reads, indexes, or compares a snapshot.
Retain ordered overrides and withdrawals after admission succeeds.

- [ ] **Step 8: Run ledger and reconciler tests**

Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py -q
```

Expected: PASS.

- [ ] **Step 9: Commit the ledger-contract batch**

```bash
git add .claude/skills/daa-extract/scripts/evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py \
  .claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py
git commit -m "feat(evidens): require phase artifact ledger"
```

### Task 2: Build the private artifact auditor and phase classifiers

**Files:**
- Create: `.claude/skills/daa-extract/scripts/audit_evidence_phase_artifacts_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_audit_evidence_phase_artifacts_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/evidence_phase_artifact_ledger.py`

**Interfaces:**
- Consumes: `audit_bundle(bundle_root: Path, ledger: list[PhaseEntry])`.
- Produces: `AuditResult` with one data-free phase summary per ledger entry;
  never contribution rows or private identities on stdout.
- Uses: `sha256_file(path: Path) -> str` and strict relative-path resolution.
- Define `AuditError(ValueError)`; every missing, unreadable, escaped,
  hash-drifting or schema-invalid required artifact raises a stable
  `EVIDENCE_RECONCILIATION_*` token before phase classification.
- Define immutable `PhaseSummary(phase_id, projection_evidence,
  authorisation_evidence, error)` and `AuditResult(summaries)`, where
  `AuditResult.phase(phase_id)` returns exactly one summary or raises
  `EVIDENCE_RECONCILIATION_PHASE_UNKNOWN`. Define
  `receipt_binds_manifest_and_identities(resolved: Mapping[str, Path],
  phase: PhaseEntry) -> bool`: it returns true only when the phase adapter's
  required JSON receipt names the exact hashed manifest and contains its full
  adapter-specific identity map. It never returns source values.

- [ ] **Step 1: Write failing classification tests**

```python
def test_audit_marks_a_phase_b_baseline_without_a_manifest_bound_receipt_unbound(tmp_path):
    result = audit_bundle(tmp_path, sealed_phase_b_ledger())
    assert result.phase("phase-b").projection_evidence == "afterdocumented_unbound"
    assert result.phase("phase-b").error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


def test_audit_marks_d1_as_a_manifestless_historical_exception(tmp_path):
    result = audit_bundle(tmp_path, sealed_d1_ledger())
    assert result.phase("d1").projection_evidence == "unavailable"
    assert result.phase("d1").error == "EVIDENCE_RECONCILIATION_HISTORICAL_EXCEPTION_NO_MANIFEST"
```

- [ ] **Step 2: Run the auditor tests and verify RED**

Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_audit_evidence_phase_artifacts_1939_v50.py -q
```

Expected: import failure because the auditor module does not yet exist.

- [ ] **Step 3: Implement path, byte-hash and schema admission**

```python
def resolve_artifact(bundle_root: Path, artifact: ArtifactEntry) -> Path:
    candidate = (bundle_root / artifact.path).resolve()
    if bundle_root.resolve() not in candidate.parents:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID")
    if sha256_file(candidate) != artifact.sha256:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_HASH_INVALID")
    return candidate

def audit_bundle(bundle_root: Path, ledger: list[PhaseEntry]) -> AuditResult:
    summaries = []
    for phase in ledger:
        resolved = {artifact.role: resolve_artifact(bundle_root, artifact)
                    for artifact in phase.artifacts if artifact.required}
        if phase.phase_id == "d1":
            summaries.append(PhaseSummary(phase.phase_id, "unavailable",
                "unavailable", "EVIDENCE_RECONCILIATION_HISTORICAL_EXCEPTION_NO_MANIFEST"))
        elif not receipt_binds_manifest_and_identities(resolved, phase):
            summaries.append(PhaseSummary(phase.phase_id, "afterdocumented_unbound",
                phase.authorisation_evidence, "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"))
        else:
            summaries.append(PhaseSummary(phase.phase_id, "mechanically_bound",
                phase.authorisation_evidence, None))
    return AuditResult(tuple(summaries))
```

- [ ] **Step 4: Add synthetic positive/negative receipt-binding tests**

Cover a receipt with matching manifest hash and exact identity-map schema, a
receipt with another manifest hash, a non-JSON receipt where JSON is required,
and an artifact path escaping the bundle.

- [ ] **Step 5: Run the auditor test suite and verify GREEN**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 6: Commit the artifact-auditor batch**

```bash
git add .claude/skills/daa-extract/scripts/audit_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_audit_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/evidence_phase_artifact_ledger.py
git commit -m "feat(evidens): audit historical phase artifacts"
```

### Task 3: Project only mechanically bound artifact families

**Files:**
- Create: `.claude/skills/daa-extract/scripts/project_evidence_phase_artifacts_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_project_evidence_phase_artifacts_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/audit_evidence_phase_artifacts_1939_v50.py`

**Interfaces:**
- Consumes: `project_phase(bundle_root: Path, phase: PhaseEntry,
  summary: PhaseSummary) -> dict` after the auditor has returned
  `mechanically_bound`.
- Produces: the existing sealed contribution shape, including five lists and
  empty or explicit `withdrawals`.
- Rejects: any phase not classified `mechanically_bound` with
  `EVIDENCE_RECONCILIATION_INCOMPLETE`.
- Define `ProjectError(ValueError)` and
  `project_phase(bundle_root: Path, phase: PhaseEntry, summary: PhaseSummary)
  -> dict[str, object]`; it calls no database API and rejects when
  `phase.phase_id != summary.phase_id` as well as when the summary is not
  mechanically bound. `seal()` from the existing reconciler locks each emitted
  contribution before its hash is inserted into the final reconciliation
  ledger.

- [ ] **Step 1: Write a failing Task 25 projection test**

```python
def test_project_task25_uses_manifest_element_id_as_occurrence_key(tmp_path):
    phase = mechanically_bound_task25_phase()
    contribution = project_phase(tmp_path, phase, bound_summary(phase))
    assert contribution["source_anchors"] == [
        {"source_id": 3, "record_key": "record-1", "occurrence_key": "element-1"}
    ]
```

- [ ] **Step 2: Run the Task 25 test and verify RED**

Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_project_evidence_phase_artifacts_1939_v50.py \
  -k task25 -q
```

Expected: import failure because the projector does not yet exist.

- [ ] **Step 3: Implement the Task 25 adapter**

Read only the manifest fields required for record keys and element IDs, then
verify every created person identity against the receipt's exact identity map.
Reject a duplicate record, occurrence, person or receipt identity before
serialising the contribution.

- [ ] **Step 4: Add failing Phase B and C0 tests**

```python
def test_project_rejects_phase_b_without_the_required_551_row_bound_identity_map(tmp_path):
    with pytest.raises(ProjectError, match="EVIDENCE_RECONCILIATION_INCOMPLETE"):
        phase = phase_b_without_bound_map()
        project_phase(tmp_path, phase, unbound_summary(phase))

def test_project_c0_uses_the_receipt_after_sha_and_binding_identity(tmp_path):
    phase = mechanically_bound_c0_phase()
    contribution = project_phase(tmp_path, phase, bound_summary(phase))
    assert contribution["narrative_sha256"] == [{"narrative_id": 7, "sha256": "d" * 64}]
```

- [ ] **Step 5: Run the new tests and verify RED**

Run the Step 2 command without the `-k` filter. Expected: the new tests fail.

- [ ] **Step 6: Implement Phase B and C0 adapters**

Require all Phase B identity-map columns and all C0 receipt fields described in
the design. Use receipt after-values, not a current-database lookup, for final
narrative hashes and bindings. Emit only a data-free incomplete phase summary
when the artifacts are absent or unbound.

- [ ] **Step 7: Add a final-state integration test**

Create synthetic Task 25, Phase B and C0 artifacts with matching byte hashes,
audit and project each phase, seal the three contributions, build a second
sealed ledger containing their exact contribution hashes, and reconcile those
artifacts against a synthetic final snapshot. Assert that an unbound phase
blocks this comparison before any snapshot validation or difference is
returned. Keep the original no-contribution audit ledger unchanged.

- [ ] **Step 8: Run the complete projector suite and verify GREEN**

Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_project_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_audit_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py -q
```

Expected: PASS.

- [ ] **Step 9: Commit the projector batch**

```bash
git add .claude/skills/daa-extract/scripts/project_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_project_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/audit_evidence_phase_artifacts_1939_v50.py
git commit -m "feat(evidens): project bound historical phase evidence"
```

### Task 4: Make real reconciliation reports private by construction

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py`
- Modify: `.claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py`
- Modify: `docs/runbooks/evidence-import-phase-gate.md`

**Interfaces:**
- Consumes: `--private-report PATH` for every CLI reconciliation.
- Produces: terminal JSON with `status`, phase IDs, counts, artifact hashes and
  stable error token only; private JSON report with exact drift rows.
- Rejects: a real reconciliation without `--private-report` using
  `EVIDENCE_RECONCILIATION_PRIVATE_REPORT_REQUIRED`.

- [ ] **Step 1: Write the failing privacy tests**

```python
def test_cli_requires_a_private_report_path_for_reconciliation(tmp_path, capsys):
    assert main(valid_args_without_private_report(tmp_path)) == 2
    assert "EVIDENCE_RECONCILIATION_PRIVATE_REPORT_REQUIRED" in capsys.readouterr().err

def test_cli_writes_exact_drift_only_to_mode_0600_private_report(tmp_path, capsys):
    assert main(valid_drifting_args_with_private_report(tmp_path)) == 2
    assert "record-1" not in capsys.readouterr().err
    assert oct(private_report.stat().st_mode & 0o777) == "0o600"
```

- [ ] **Step 2: Run privacy tests and verify RED**

Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py \
  -k "private_report or requires_a_private" -q
```

Expected: FAIL because current CLI writes detailed drift JSON to stderr.

- [ ] **Step 3: Implement the private-report writer**

Use `os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)` and write a
canonical JSON private report before printing a redacted terminal summary. Do
not overwrite an existing report. Validate `--private-report` before loading
the snapshot or contributions; on a reconciliation error, write the detailed
report only when the path was created successfully, then print exactly
`status`, error token, phase IDs, section counts and artifact hashes. Ensure
malformed paths, write failures and existing paths fail before any
reconciliation output is emitted.

- [ ] **Step 4: Run privacy tests and verify GREEN**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Update the runbook**

Replace the direct terminal drift instruction with a command requiring an
ignored `--private-report` path, state the `0600` behavior, and state that a
ledger with any unbound phase returns `INCOMPLETE` before production snapshot
comparison.

- [ ] **Step 6: Run the full relevant verification**

Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/test_audit_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_project_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py \
  .claude/skills/daa-extract/scripts/test_audit_1939.py \
  .claude/skills/daa-extract/scripts/test_build_phase_a_anchor_manifest_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_build_narrative_replacement_manifest_1939_v50.py -q
PYTHONPYCACHEPREFIX=/private/tmp/daa156157-pycache /usr/bin/python3 -m py_compile \
  .claude/skills/daa-extract/scripts/evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/audit_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/project_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py
git diff --check
```

Expected: all tests pass, bytecode compilation succeeds and the diff has no
whitespace errors.

- [ ] **Step 7: Request GPT-Sol review and resolve valid findings**

Ask a read-only reviewer to inspect the final diff against the design, focusing
on artifact-to-receipt binding, privacy of output, fail-closed admission and
the distinction between historical effect and historical authorisation. Fix
only verified findings and rerun Step 6.

- [ ] **Step 8: Commit the privacy and runbook batch**

```bash
git add .claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py \
  .claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py \
  docs/runbooks/evidence-import-phase-gate.md
git commit -m "feat(evidens): keep reconciliation drift private"
```

### Task 5: Validate retained artifacts locally without exposing data

**Files:**
- Modify: `docs/runbooks/evidence-import-phase-gate.md`
- Create locally only: ignored private ledger, contributions and `0600` audit
  report beneath the approved `work/` bundle.

**Interfaces:**
- Consumes: the explicitly approved read-only historical artifact bundle.
- Produces: only local data-free terminal summaries and a private report;
  nothing is added to Git.

- [ ] **Step 1: Create the local data-free ledger from artifact byte hashes**

Run the auditor's ledger-sealing command against explicit relative paths for
Task 25, Phase A, Phase B, narrative publication, name completion, C0 and D1.
Do not place artifact content, person identifiers or record keys in the ledger.

- [ ] **Step 2: Run the auditor in summary mode**

Expected: retained evidence is classified phase-by-phase. Any missing binding
returns `EVIDENCE_RECONCILIATION_INCOMPLETE`; retain that result rather than
editing the ledger or synthesising a receipt.

- [ ] **Step 3: Do not request production access if any phase is unbound**

Record the data-free summary in the local handoff. Task 25's authorisation gap
and D1's manifestless exception remain visible even if another phase validates.

- [ ] **Step 4: If and only if every applicable phase becomes mechanically bound, request separate production-read approval**

Use the runbook's repeatable-read snapshot query and a mandatory `0600`
private report path. Do not perform this step without a new user message that
explicitly authorises production read access.

- [ ] **Step 5: Commit only the data-free runbook/documentation changes**

```bash
git add docs/runbooks/evidence-import-phase-gate.md
git commit -m "docs(evidens): document artifact reconciliation validation"
```
