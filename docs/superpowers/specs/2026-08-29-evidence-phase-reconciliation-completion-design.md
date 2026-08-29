# Historical evidence-phase reconciliation completion — design

**Date:** 2026-08-29
**Status:** Revised after independent review; implementation not started
**Scope:** Controlled historical integrity task for #156. It does not change
the active genimport roadmap or authorise a production mutation.

## Purpose

#156 needs a read-only answer to a narrow question: do the present production
projections for DAA 1939 agree with the effects documented by the historical
apply artifacts? The existing phase gate can compare a snapshot with
hash-locked contributions, but a manually authored contribution cannot itself
prove that it was derived from the historical manifest.

This design replaces manual contribution authoring with a local evidence
auditor and projector. The auditor classifies each historical phase before it
can become a contribution. Only a manifest with a contemporaneously bound
apply/audit receipt may produce a reconcilable contribution. Other retained
material is useful afterdocumentation, but stays visibly unresolved. The
public repository keeps only data-free code, tests, instructions, phase
identifiers and hashes.

## Authority and value-chain placement

- **Roadmap relation:** controlled interruption for historical data integrity;
  it does not start a new import phase or reprioritise #152.
- **Value-chain relation:** post-apply integrity control for the existing
  promotion/publication legacy path.
- **Delivery type:** temporary legacy-audit adapter, not a new permanent
  edition-specific database surface.
- **Editorial/user value:** a reader-facing source record and narrative can be
  traced to a documented applied artifact, while uncertainty remains visible.
- **Completion evidence:** the auditor produces a complete phase-evidence
  ledger; only if every applicable phase is mechanically bound may an
  explicitly authorised fresh read-only snapshot report a match or drift.
- **Replaced workflow:** handwritten reconciliation contributions with only a
  declared reference to an original manifest.

## Covered projections

The reconciliation remains intentionally bounded to the five projections
specified in #156:

1. `source_records`: `(source_id, record_key)`;
2. accepted `source_anchors`: `(source_id, record_key, occurrence_key)`;
3. published `narrative_bindings`: `(source_id, record_key, narrative_id)`;
4. `narrative_sha256`: `(narrative_id, sha256)`; and
5. `persons`: `(person_id)`.

It does not claim equality for DDL, facts, audit/change-set history, staged
state, `same_som`, record kinds, renditions or occurrence bytes. Those effects
stay outside the report's scope and must not be inferred from `status: match`.

## Evidence classification

Every phase has two independent states:

1. **Projection evidence:** `mechanically_bound`,
   `afterdocumented_unbound`, or `unavailable`.
2. **Authorisation evidence:** `contemporaneous_phase_package`,
   `afterdocumented_authorisation_gap`, or `unavailable`.

`mechanically_bound` requires original manifest bytes plus a retained receipt
that identifies those manifest bytes, the production target and the exact
affected identities. A count-only result, an unbound post-apply export, or a
current-database lookup is not sufficient. `afterdocumented_unbound` never
enters a contribution and always yields `EVIDENCE_RECONCILIATION_INCOMPLETE`.

## Artifact contract

The local bundle contains original bytes only; it is ignored by Git and never
copied by the tools.

| Phase family | Required original input | Required paired receipt/input | Role |
| --- | --- | --- | --- |
| Task 25 production writer | `1939-v50-production-write-manifest-v1` | post-apply audit, if it names the manifest bytes and exact affected IDs | Records, manifest element IDs as occurrence keys, and created-person identities. Its known missing GO remains a separate authorisation gap. |
| Phase A | `1939-v50-phase-a-anchor-manifest-v1` | receipt naming the manifest bytes, production target and all affected record/occurrence pairs | Additional source records and accepted anchors. A count-only apply result is afterdocumentation only. |
| Phase B | `1939-v50-narrative-replacement-manifest-v2` | a retained 551-row, manifest-bound `person_id`, `record_key`, `narrative_id`, before/after SHA and publication-status map | Final narrative hashes and record-bound narrative identities. The known unbound baseline export is afterdocumentation only. |
| Narrative publication | `1939-v50-narrative-publication-manifest-v1` | receipt naming the manifest bytes, production target and all eight binding identities | Published bindings for the Task 25 narratives. |
| Name completion | `1939-v50-name-completion-manifest-v1` | receipt naming source manifest and completion results | Dependency validation only; it adds no row to the five projections. |
| C0 follow-up | `1939-v50-c0-followup-manifest-v1` | receipt bound to manifest SHA, production identity, `change_set 965`, nine narrative IDs, after-SHAs and binding identities | Record-to-narrative binding corrections and final text hashes. The retained manifest alone is afterdocumentation only. |

The auditor verifies every raw-file SHA-256 against the hash declared by its
dependent manifest or ledger entry. A missing, misnamed, malformed, unbound or
hash-drifting receipt is a stable fail-closed error. It must not replace a
receipt with an inferred current-database value.

## Historical exception

The D1 publication operation is represented by a retained apply script and a
documented `change_set 955`, but not by an original hash-locked manifest and
paired manifest receipt. The projector records it as
`historical_exception_no_manifest`.

This exception does not become an invented phase contribution. The final report
must show it as unresolved and state that the bounded five-projection result
does not prove D1's staged/publication effect. The existing afterdocumentation
requirement in #156 remains satisfied by making that limitation explicit.

Task 25 has a distinct status: it may retain projection evidence, but its
authorisation state is always `afterdocumented_authorisation_gap` until a
contemporaneous phase package is found. A projection match must never be
reported as retrospectively authorising that apply.

## Components and data flow

```text
private original artifacts (read-only)
        │ raw SHA-256 + schema + evidence-classification validation
        ▼
manifest-family auditor and projector adapters
        │ mechanically bound private contribution, or visible incomplete status
        ▼
phase inventory builder
        │ sealed v2 ledger: phase, order, artifact roles/hashes, adapter version,
        │ evidence state and contribution output hash
        ▼
existing final-state reconciler
        │
        ├── local synthetic tests
        └── explicitly authorised fresh read-only production snapshot
                 │
                 ▼
           match, drift, or historical-exception report
```

Only mechanically bound adapters emit the existing contribution schema with
mandatory `withdrawals`. The inventory is versioned to v2. For each phase it
contains an ordered array of artifacts with `role`, relative `path`, raw
`sha256`, declared schema, and required/optional status; an adapter identifier
and source-code SHA-256; projection and authorisation evidence states; and the
sealed contribution output SHA-256 when a contribution is permitted. The
inventory controls phase order. A later phase may replace an earlier value or
withdraw it, but a duplicate inside one phase, an invalid withdrawal, an
unknown artifact family, an unbound artifact, or a missing ledger phase fails
closed.

## CLI boundary

The new local CLI accepts an explicit artifact-bundle directory, an explicit
data-free phase ledger path and a mandatory caller-selected private-output path
under the ignored bundle. It creates that output with mode `0600`; standard
output contains only its data-free summary. It opens no database connection.

The existing reconciliation CLI accepts only sealed snapshot, v2 inventory and
contribution inputs. It first rejects any applicable phase without
`mechanically_bound` projection evidence. A runbook command invokes the
auditor/projector for every ledger phase, then invokes reconciliation with
those exact outputs. No runbook command permits production writes.

For real artifacts, the terminal may print only status, phase IDs, counts,
artifact hashes and stable error tokens. Exact missing/unexpected identity rows
are written only to a caller-supplied, ignored private report file created with
mode `0600`; no private-report path means no real reconciliation is run.

## Test strategy

All committed fixtures are synthetic and text-free. Tests cover:

- every mechanically bound schema family produces deterministic
  five-projection rows;
- each raw manifest/receipt hash mismatch fails before output;
- Task 25 element IDs become the expected occurrence keys;
- an unbound Phase B map and a C0 manifest without its apply receipt produce
  `EVIDENCE_RECONCILIATION_INCOMPLETE`, not a contribution;
- Phase B and C0 later values replace earlier narrative hashes/bindings only
  in a synthetic mechanically bound fixture;
- required withdrawals remove an obsolete final-state row;
- omitted ledger phase, duplicate sequence and unrecognised schema fail;
- D1 and Task 25's authorisation gap are emitted as documented evidence states
  and never become retrospective approval;
- a complete synthetic bundle projects, seals and reconciles to a matching
  synthetic snapshot; and
- tampering any artifact after sealing produces a stable failure token.

Real private artifacts are used only in a local, read-only validation command.
That command reports phase IDs, schema versions, byte hashes, counts and error
tokens; it never prints source text, names, record payloads, person data or
identity-level drift rows.

## Completion criteria

The implementation is ready for a separate read-only production check only
when all of the following hold:

1. the auditor classifies each retained applicable phase locally;
2. only mechanically bound phases produce a sealed contribution;
3. the v2 data-free ledger includes every applicable phase in explicit order;
4. Task 25, C0 and D1 retain their visible evidence/authorisation status rather
   than fabricated proof;
5. committed synthetic tests pass; and
6. the runbook states that a fresh production snapshot still requires separate
   user authorisation.

A production snapshot is not permitted while any applicable phase is
`afterdocumented_unbound` or `unavailable`. When permitted, `match` is evidence
only for the five named projections. It is not a general genimport completion,
historical authorisation or production-GO.
