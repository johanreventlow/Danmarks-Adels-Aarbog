# Historical evidence-phase reconciliation completion — design

**Date:** 2026-08-29
**Status:** Approved design; implementation not started
**Scope:** Controlled historical integrity task for #156. It does not change
the active genimport roadmap or authorise a production mutation.

## Purpose

#156 needs a read-only answer to a narrow question: do the present production
projections for DAA 1939 agree with the effects documented by the historical
apply artifacts? The existing phase gate can compare a snapshot with
hash-locked contributions, but a manually authored contribution cannot itself
prove that it was derived from the historical manifest.

This design replaces manual contribution authoring with a local projector. The
projector reads each original manifest and its paired immutable apply/audit
receipt, derives the five covered projections, and produces only a private,
hash-locked contribution. The public repository keeps only data-free code,
tests, instructions, phase identifiers and hashes.

## Authority and value-chain placement

- **Roadmap relation:** controlled interruption for historical data integrity;
  it does not start a new import phase or reprioritise #152.
- **Value-chain relation:** post-apply integrity control for the existing
  promotion/publication legacy path.
- **Delivery type:** temporary legacy-audit adapter, not a new permanent
  edition-specific database surface.
- **Editorial/user value:** a reader-facing source record and narrative can be
  traced to a documented applied artifact, while uncertainty remains visible.
- **Completion evidence:** the projector accepts every retained applicable
  artifact, the data-free ledger locks their identity/order, and an explicitly
  authorised fresh read-only snapshot either matches or reports exact drift.
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

## Artifact contract

The local bundle contains original bytes only; it is ignored by Git and never
copied by the tools.

| Phase family | Required original input | Required paired receipt/input | Role |
| --- | --- | --- | --- |
| Task 25 production writer | `1939-v50-production-write-manifest-v1` | production post-apply audit | Records, manifest element IDs as occurrence keys, and created-person identities. |
| Phase A | `1939-v50-phase-a-anchor-manifest-v1` | production apply receipt plus pinned input artifacts | Additional source records and accepted anchors. |
| Phase B | `1939-v50-narrative-replacement-manifest-v2` | pinned old-narrative export and production apply receipt | Final narrative hashes and record-bound narrative identities. |
| Narrative publication | `1939-v50-narrative-publication-manifest-v1` | manifest binding rows | Published bindings for the Task 25 narratives. |
| Name completion | `1939-v50-name-completion-manifest-v1` | production post-apply audit | Hash-bound dependency validation; no new row unless its source person is represented elsewhere. |
| C0 follow-up | `1939-v50-c0-followup-manifest-v1` | exact production manifest bytes | Record-to-narrative binding corrections and final text hashes. |

The projector verifies every raw-file SHA-256 against the hash declared by its
dependent manifest or data-free ledger entry. A missing, misnamed, malformed,
or hash-drifting receipt is a stable fail-closed error. It must not replace a
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

## Components and data flow

```text
private original artifacts (read-only)
        │ raw SHA-256 + schema validation
        ▼
manifest-family projector adapters
        │ private contribution + receipt provenance
        ▼
phase inventory builder
        │ data-free sealed inventory: phase, order, artifact hashes, projector version
        ▼
existing final-state reconciler
        │
        ├── local synthetic tests
        └── explicitly authorised fresh read-only production snapshot
                 │
                 ▼
           match, drift, or historical-exception report
```

The adapters emit the existing contribution schema with mandatory `withdrawals`.
The inventory controls phase order. A later phase may replace an earlier value
or withdraw it, but a duplicate inside one phase, an invalid withdrawal, an
unknown artifact family, an unsigned input or a missing ledger phase fails
closed.

## CLI boundary

The new local CLI accepts an explicit artifact-bundle directory and an explicit
data-free phase ledger path. It writes its contribution output only to standard
output or to a caller-selected path under the ignored private bundle. It opens
no database connection.

The existing reconciliation CLI continues to accept only sealed snapshot,
inventory and contribution inputs. A runbook command first invokes the
projector for every ledger phase, then invokes reconciliation with those exact
outputs. No runbook command permits production writes.

## Test strategy

All committed fixtures are synthetic and text-free. Tests cover:

- every supported schema family produces deterministic five-projection rows;
- each raw manifest/receipt hash mismatch fails before output;
- Task 25 element IDs become the expected occurrence keys;
- Phase B and C0 later values replace earlier narrative hashes/bindings;
- required withdrawals remove an obsolete final-state row;
- omitted ledger phase, duplicate sequence and unrecognised schema fail;
- D1 is emitted only as the documented exception and never as a contribution;
- a complete synthetic bundle projects, seals and reconciles to a matching
  synthetic snapshot; and
- tampering any artifact after sealing produces a stable failure token.

Real private artifacts are used only in a local, read-only validation command.
That command reports phase IDs, schema versions, byte hashes, counts and error
tokens; it never prints source text, names, record payloads or person data.

## Completion criteria

The implementation is ready for a separate read-only production check only
when all of the following hold:

1. retained applicable manifests and their required receipts validate locally;
2. each projected contribution is mechanically derived and sealed;
3. the data-free ledger includes every applicable phase in explicit order;
4. D1 appears as a visible historical exception rather than fabricated proof;
5. committed synthetic tests pass; and
6. the runbook states that a fresh production snapshot still requires separate
   user authorisation.

A production snapshot `match` is evidence only for the five named projections.
It is not a general genimport completion or production-GO.
