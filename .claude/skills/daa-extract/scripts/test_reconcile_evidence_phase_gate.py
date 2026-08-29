from __future__ import annotations

import hashlib
import json

import pytest

from reconcile_evidence_phase_gate import ReconciliationError, load_phase_manifest, reconcile, seal


def _with_hash(payload: dict, field: str) -> dict:
    value = dict(payload)
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    value[field] = hashlib.sha256(raw).hexdigest()
    return value


def _manifest(phase_id: str, *, record_key: str, occurrence_key: str, person_id: int, narrative_id: int, narrative_sha256: str = "b" * 64) -> dict:
    return _with_hash(
        {
            "schema_version": "daa-evidence-phase-reconciliation-manifest-v1",
            "phase_id": phase_id,
            "source_manifest_sha256": "a" * 64,
            "source_manifest_path": "original-manifest.json",
            "source_records": [{"source_id": 3, "record_key": record_key}],
            "source_anchors": [{"source_id": 3, "record_key": record_key, "occurrence_key": occurrence_key}],
            "narrative_bindings": [{"source_id": 3, "record_key": record_key, "narrative_id": narrative_id}],
            "narrative_sha256": [{"narrative_id": narrative_id, "sha256": narrative_sha256}],
            "persons": [{"person_id": person_id}],
            "withdrawals": {
                "source_records": [],
                "source_anchors": [],
                "narrative_bindings": [],
                "narrative_sha256": [],
                "persons": [],
            },
        },
        "reconciliation_content_sha256",
    )


def _snapshot(*manifests: dict) -> dict:
    sections = ("source_records", "source_anchors", "narrative_bindings", "narrative_sha256", "persons")
    state_keys = {
        "source_records": ("source_id", "record_key"),
        "source_anchors": ("source_id", "record_key", "occurrence_key"),
        "narrative_bindings": ("source_id", "record_key"),
        "narrative_sha256": ("narrative_id",),
        "persons": ("person_id",),
    }
    final_rows = {}
    for section in sections:
        final_rows[section] = {}
        for manifest in manifests:
            for row in manifest[section]:
                final_rows[section][tuple(row[key] for key in state_keys[section])] = row
    payload = {
        "schema_version": "daa-evidence-production-snapshot-v1",
        **{section: list(final_rows[section].values()) for section in sections},
    }
    return _with_hash(payload, "snapshot_content_sha256")


def _inventory(*manifests: dict) -> dict:
    return _with_hash(
        {
            "schema_version": "daa-evidence-phase-reconciliation-inventory-v1",
            "phase_manifests": [
                {
                    "phase_id": manifest["phase_id"],
                    "sequence": sequence,
                    "reconciliation_content_sha256": manifest["reconciliation_content_sha256"],
                    "source_manifest_sha256": manifest["source_manifest_sha256"],
                }
                for sequence, manifest in enumerate(manifests, start=1)
            ],
        },
        "inventory_content_sha256",
    )


def test_reconcile_matches_snapshot_against_ordered_phase_final_state():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=202)

    report = reconcile(_snapshot(phase_a, phase_b), [phase_a, phase_b], _inventory(phase_a, phase_b))

    assert report["status"] == "match"
    assert report["scope"] == "five-projection-final-state-v1"
    assert report["phase_ids"] == ["phase-a", "phase-b"]
    assert report["counts"] == {
        "source_records": 2,
        "source_anchors": 2,
        "narrative_bindings": 2,
        "narrative_sha256": 2,
        "persons": 2,
    }


def test_reconcile_fails_closed_when_production_has_an_unmanifested_binding():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    snapshot = _snapshot(phase_a)
    snapshot["narrative_bindings"].append({"source_id": 3, "record_key": "1939:unmanifested", "narrative_id": 999})
    snapshot = _with_hash({key: value for key, value in snapshot.items() if key != "snapshot_content_sha256"}, "snapshot_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_DRIFT") as caught:
        reconcile(snapshot, [phase_a], _inventory(phase_a))

    assert caught.value.report["differences"]["narrative_bindings"]["unexpected"] == [
        {"narrative_id": 999, "record_key": "1939:unmanifested", "source_id": 3}
    ]


def test_reconcile_fails_closed_when_production_has_a_different_value_for_the_same_identity():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    snapshot = _snapshot(phase_a)
    snapshot["narrative_sha256"] = [{"narrative_id": 201, "sha256": "c" * 64}]
    snapshot = _with_hash({key: value for key, value in snapshot.items() if key != "snapshot_content_sha256"}, "snapshot_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_DRIFT") as caught:
        reconcile(snapshot, [phase_a], _inventory(phase_a))

    difference = caught.value.report["differences"]["narrative_sha256"]
    assert difference["missing"] == [{"narrative_id": 201, "sha256": "b" * 64}]
    assert difference["unexpected"] == [{"narrative_id": 201, "sha256": "c" * 64}]


def test_reconcile_accepts_later_phase_override_for_an_already_touched_narrative():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=201, narrative_sha256="c" * 64)

    report = reconcile(_snapshot(phase_a, phase_b), [phase_b, phase_a], _inventory(phase_a, phase_b))

    assert report["phase_ids"] == ["phase-a", "phase-b"]
    assert report["counts"]["narrative_sha256"] == 1
    assert report["overrides"]["narrative_sha256"] == 1


def test_reconcile_applies_a_later_withdrawal_before_comparing_final_state():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=202, narrative_sha256="c" * 64)
    phase_b["withdrawals"]["narrative_sha256"] = [{"narrative_id": 201}]
    phase_b = _with_hash({key: value for key, value in phase_b.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    report = reconcile(_snapshot(phase_b), [phase_a, phase_b], _inventory(phase_a, phase_b))

    assert report["status"] == "match"
    assert report["counts"]["narrative_sha256"] == 1


def test_reconcile_rejects_duplicate_final_state_inside_one_contribution():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["source_records"].append({"source_id": 3, "record_key": "1939:1"})
    phase_a = _with_hash({key: value for key, value in phase_a.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_CONTRIBUTION_DUPLICATE"):
        reconcile(_snapshot(phase_a), [phase_a], _inventory(phase_a))


def test_reconcile_rejects_a_manifest_without_a_complete_withdrawals_shape():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    del phase_a["withdrawals"]
    phase_a = _with_hash({key: value for key, value in phase_a.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_WITHDRAWALS_INVALID"):
        reconcile(_snapshot(), [phase_a], _inventory(phase_a))


def test_reconcile_rejects_a_withdrawal_that_conflicts_with_its_new_row():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["withdrawals"]["source_records"] = [{"source_id": 3, "record_key": "1939:1"}]
    phase_a = _with_hash({key: value for key, value in phase_a.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_WITHDRAWAL_CONFLICT"):
        reconcile(_snapshot(), [phase_a], _inventory(phase_a))


def test_reconcile_rejects_a_withdrawal_without_a_previous_state():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=202)
    phase_b["withdrawals"]["narrative_sha256"] = [{"narrative_id": 999}]
    phase_b = _with_hash({key: value for key, value in phase_b.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_WITHDRAWAL_MISSING"):
        reconcile(_snapshot(phase_a, phase_b), [phase_a, phase_b], _inventory(phase_a, phase_b))


def test_reconcile_rejects_a_tampered_phase_manifest_before_comparing_any_state():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["persons"] = [{"person_id": 999}]

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_MANIFEST_HASH_INVALID"):
        reconcile(_snapshot(phase_a), [phase_a], _inventory(phase_a))


def test_seal_adds_a_canonical_hash_without_mutating_the_capture_document():
    raw_snapshot = {
        "schema_version": "daa-evidence-production-snapshot-v1",
        "source_records": [],
        "source_anchors": [],
        "narrative_bindings": [],
        "narrative_sha256": [],
        "persons": [],
    }

    sealed = seal(raw_snapshot)

    assert "snapshot_content_sha256" not in raw_snapshot
    assert sealed["snapshot_content_sha256"] == _with_hash(raw_snapshot, "snapshot_content_sha256")["snapshot_content_sha256"]


def test_loading_a_phase_contribution_verifies_its_original_manifest_bytes(tmp_path):
    original = tmp_path / "original-manifest.json"
    original.write_bytes(b'{"original":true}\n')
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["source_manifest_sha256"] = hashlib.sha256(original.read_bytes()).hexdigest()
    phase_a = _with_hash({key: value for key, value in phase_a.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")
    contribution = tmp_path / "phase-a.json"
    contribution.write_text(json.dumps(phase_a), encoding="utf-8")

    assert load_phase_manifest(contribution) == phase_a

    original.write_bytes(b'{"original":false}\n')
    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_HASH_INVALID"):
        load_phase_manifest(contribution)


def test_reconcile_rejects_an_inventory_that_names_a_phase_missing_from_the_command():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=202)

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_INVENTORY_MISMATCH"):
        reconcile(_snapshot(phase_a), [phase_a], _inventory(phase_a, phase_b))


def test_reconcile_rejects_an_inventory_with_a_duplicate_sequence():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=202)
    inventory = _inventory(phase_a, phase_b)
    inventory["phase_manifests"][1]["sequence"] = 1
    inventory = _with_hash({key: value for key, value in inventory.items() if key != "inventory_content_sha256"}, "inventory_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_INVENTORY_SEQUENCE_DUPLICATE"):
        reconcile(_snapshot(phase_a, phase_b), [phase_a, phase_b], inventory)
