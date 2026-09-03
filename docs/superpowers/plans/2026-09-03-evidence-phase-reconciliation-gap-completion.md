# Evidence-phase reconciliation gap completion plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` to implement this plan task by task.

**Goal:** Complete the locally testable parts of #156 by covering every named
historical phase family, providing a data-free operator CLI, and preserving the
fail-closed boundary before private retained artifacts or production access.

**Architecture:** Extend the existing ledger, auditor, and projector with
explicit adapter contracts for Phase A, narrative publication, name completion,
and the D1 manifestless historical exception. Add one orchestration CLI that
seals an artifact ledger from an explicit data-free catalog, audits it, projects
only mechanically bound phases, and writes all identity-bearing outputs as
exclusive `0600` files inside a caller-selected ignored bundle. Terminal output
contains only phase IDs, states, counts, hashes, and stable error tokens.

**Tech Stack:** Python 3 standard library, pytest, JSON, SHA-256, existing DAA
evidence reconciliation modules.

**Spec:**
`docs/superpowers/specs/2026-08-29-evidence-phase-reconciliation-completion-design.md`

## Global Constraints

- Work only in the isolated `codex/finish-156-158` worktree.
- Never read, list, print, copy, or inspect the real retained-artifact bundle or
  any `work/` content while implementing or testing this plan.
- Use `/usr/bin/python3`; every fixture must be synthetic and contain no real
  names, person IDs, record keys, narrative text, or retained payloads.
- The ledger, auditor, projector, CLI, and reconciler must not connect to a
  database.
- Do not perform production changes, production reads, pushes, or issue
  closures.
- Phase A, narrative publication, and name completion stay
  `afterdocumented_unbound` unless an exact manifest-bound receipt is actually
  present. Do not synthesize or infer a historical receipt.
- Task 25 retains `afterdocumented_authorisation_gap` even when mechanically
  bound. D1 remains `unavailable` with
  `EVIDENCE_RECONCILIATION_HISTORICAL_EXCEPTION_NO_MANIFEST` and never emits a
  contribution.
- Production snapshot admission stays impossible while any applicable phase is
  unbound or unavailable.

---

### Task 1: Complete phase-family audit and projection contracts

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/evidence_phase_artifact_ledger.py`
- Modify: `.claude/skills/daa-extract/scripts/audit_evidence_phase_artifacts_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/project_evidence_phase_artifacts_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py`
- Modify: `.claude/skills/daa-extract/scripts/test_audit_evidence_phase_artifacts_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/test_project_evidence_phase_artifacts_1939_v50.py`

**Interfaces and exact contracts:**

- Add receipt adapter IDs `phase-a-v1`, `narrative-publication-v1`, and
  `name-completion-v1`; keep `d1-historical-exception-v1` as a classifier, not
  a receipt adapter.
- All bound receipts require schema-specific validation plus
  `manifest_sha256`, `database_target_identity`, and a canonical target hash
  matching `PhaseEntry.database_target_identity_sha256`.
- `database_target_identity` is exactly:
  `{"schema_version":"daa-evidence-production-target-identity-v1",`
  `"environment":"production","system_identifier_sha256":"<sha256>"}`.
- Phase A manifest schema is `1939-v50-phase-a-anchor-manifest-v1`; a bound
  receipt schema is `daa-evidence-phase-receipt-phase-a-v1`. Its exact
  `identity_map` contains 584 unique rows with exactly `record_key` and
  `occurrence_key`. Projection emits those rows into both `source_records`
  (`source_id: 3`, `record_key`) and `source_anchors` (`source_id: 3`,
  `record_key`, `occurrence_key`), and emits no other projection rows.
- Narrative-publication manifest schema is
  `1939-v50-narrative-publication-manifest-v1`; bound receipt schema is
  `daa-evidence-phase-receipt-narrative-publication-v1`. Its exact
  `identity_map` contains eight unique rows with exactly `source_id`,
  `record_key`, `narrative_id`, and `binding_id`; every `source_id` is `3`.
  Projection emits only eight `narrative_bindings` rows with `source_id`,
  `record_key`, and `narrative_id`.
- Name-completion manifest schema is
  `1939-v50-name-completion-manifest-v1`; bound receipt schema is
  `daa-evidence-phase-receipt-name-completion-v1`. It binds exactly eight
  completion results with exactly `person_id`, `fact_id`, `assertion_id`,
  `citation_id`, and `conclusion_id`. It is dependency evidence only and emits
  a sealed contribution whose five projection lists and `withdrawals` are all
  empty.
- D1 may retain a hash-locked non-JSON `historical_apply_script` artifact. Hash
  and path validation must happen, but D1 classification must occur before any
  JSON parse so the script cannot be rejected as malformed JSON. D1 never
  projects.
- Receipt identity maps must equal the manifest identities, not merely match a
  count. Reject duplicates, missing rows, extra rows, wrong field sets, wrong
  source IDs, and target/hash drift with stable
  `EVIDENCE_RECONCILIATION_*` tokens.

- [ ] Write RED tests for each new adapter: valid exact binding, manifest-hash
  drift, target drift, duplicate/missing/extra identity, and unbound receipt.
- [ ] Write RED projection tests for the exact Phase A and narrative output and
  the empty name-completion contribution.
- [ ] Write a RED D1 test using a non-JSON synthetic script artifact.
- [ ] Implement the minimal adapter, audit, and projection changes.
- [ ] Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/test_audit_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_project_evidence_phase_artifacts_1939_v50.py -q
```

Expected: all tests pass with pristine output.

- [ ] Commit as `feat(evidens): complete historical phase adapters`.

---

### Task 2: Add the data-free artifact-audit CLI and operator runbook

**Files:**
- Create: `.claude/skills/daa-extract/scripts/run_evidence_phase_artifact_audit_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_run_evidence_phase_artifact_audit_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/evidence_phase_artifact_ledger.py`
- Modify: `docs/runbooks/evidence-import-phase-gate.md`

**CLI:**

```text
run_evidence_phase_artifact_audit_1939_v50.py
  --bundle-root PATH
  --catalog PATH
  --private-output-dir PATH
```

- The catalog schema is `daa-evidence-phase-artifact-catalog-v1`. It contains
  only `phase_id`, positive unique `sequence`, `adapter_id`,
  `projection_evidence`, `authorisation_evidence`, optional
  `database_target_identity_sha256`, and artifact metadata with exactly
  `role`, relative `path`, `schema_version`, and `required`. It contains no
  artifact SHA values or projection identities.
- `--catalog` and `--private-output-dir` must resolve inside `--bundle-root`.
  Reject symlinks, escapes, missing roots, and non-directories before reading
  an artifact. The output directory must already exist and be empty.
- Compute each artifact byte hash and the registered adapter source hash, seal
  the audit ledger, audit all phases, and project only mechanically bound
  phases. Never infer a receipt or promote an unbound phase.
- Write with `os.open(..., O_WRONLY | O_CREAT | O_EXCL, 0o600)`:
  `audit-ledger.json`, `audit-summary.json`, one
  `<sequence>-<phase_id>.contribution.json` per bound phase, and
  `reconciliation-ledger.json` only when every phase is mechanically bound.
  On any expected incomplete phase, omit the reconciliation ledger and return
  exit code `2` after writing the audit ledger and summary.
- Stdout/stderr JSON is limited to `status`, stable `error`, ordered phase IDs
  and evidence states, artifact/contribution hashes, and aggregate counts.
  It must never contain paths, artifact values, projection identities, or
  private report rows.
- If any output target already exists or any write fails, stop fail-closed and
  do not overwrite. Tests must verify `0600` mode, no-overwrite, path escape,
  symlink rejection, byte-hash sealing, redacted terminal output, and no DB
  access.
- The runbook must show the exact invocation, say that the catalog and outputs
  live only in the ignored retained bundle, state that current historical gaps
  produce `INCOMPLETE`, and stop before the separately authorised production
  snapshot step.

- [ ] Write failing CLI tests before implementation.
- [ ] Implement the catalog validator, orchestration CLI, exclusive private
  writers, and redacted summary.
- [ ] Run:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_run_evidence_phase_artifact_audit_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/test_audit_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_project_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py -q
```

Expected: all tests pass with pristine output.

- [ ] Commit as `feat(evidens): add private artifact audit cli`.

---

### Task 3: Prove the complete synthetic fail-closed workflow

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/test_run_evidence_phase_artifact_audit_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py`
- Modify: `docs/runbooks/evidence-import-phase-gate.md`

**Acceptance:**

- One synthetic integration test covers Task 25, Phase A, Phase B, narrative
  publication, name completion, C0 follow-up, and D1 in historical sequence.
- The first run contains the real historical evidence-state shape: Phase A,
  narrative publication, and name completion are unbound; D1 is unavailable;
  the CLI returns `2`, writes no reconciliation ledger, and reads no snapshot.
- A separate wholly synthetic all-bound variant may use synthetic receipts to
  exercise successful contribution sealing and reconciliation-ledger creation,
  but it must not reclassify D1 or imply historical authorisation. Exclude D1
  from that applicability set and label the fixture `synthetic_capability_only`.
- Tampering with an artifact after ledger sealing must fail before projection.
- Reconciler admission must still reject any ledger that contains an unbound or
  unavailable applicable phase before snapshot validation.

- [ ] Add the RED end-to-end tests.
- [ ] Make only the minimal fixes required for GREEN.
- [ ] Run the focused tests above, then:

```bash
PYTHONPATH=.claude/skills/daa-extract/scripts /usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/test_audit_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_project_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_run_evidence_phase_artifact_audit_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_reconcile_evidence_phase_gate.py \
  .claude/skills/daa-extract/scripts/test_audit_1939.py \
  .claude/skills/daa-extract/scripts/test_reconcile_source_records_1939.py \
  .claude/skills/daa-extract/scripts/test_evidence_contract.py -q
PYTHONPYCACHEPREFIX=/private/tmp/daa156-pycache /usr/bin/python3 -m py_compile \
  .claude/skills/daa-extract/scripts/evidence_phase_artifact_ledger.py \
  .claude/skills/daa-extract/scripts/audit_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/project_evidence_phase_artifacts_1939_v50.py \
  .claude/skills/daa-extract/scripts/run_evidence_phase_artifact_audit_1939_v50.py \
  .claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py
git diff --check
```

Expected: tests pass, compilation succeeds, and the diff is clean.

- [ ] Commit as `test(evidens): prove fail closed phase workflow`.
- [ ] Perform controller self-review, then one independent read-only
  GPT-5.6-Sol whole-branch review. Resolve only valid findings and rerun the
  complete verification once.

## Explicit stop gate

After Task 3, stop. Do not run the CLI against retained artifacts, do not read
a production snapshot, do not modify production, do not push, and do not close
#156 or #158 without a new explicit user authorisation.
