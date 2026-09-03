from __future__ import annotations

import hashlib
import json

import pytest

from evidence_phase_artifact_ledger import adapter_sha256, seal_ledger
from reconcile_evidence_phase_gate import (
    ReconciliationError,
    _load_json,
    _reconcile_capability,
    _validate_snapshot,
    load_phase_manifest,
    main,
    reconcile,
    seal,
)


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


def _target_identity() -> dict:
    return {
        "schema_version": "daa-evidence-production-target-identity-v1",
        "environment": "production",
        "system_identifier_sha256": "d" * 64,
    }


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
        "database_target_identity": _target_identity(),
        **{section: list(final_rows[section].values()) for section in sections},
    }
    return _with_hash(payload, "snapshot_content_sha256")


def _ledger(*manifests: dict) -> dict:
    return seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": manifest["phase_id"],
                    "sequence": sequence,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": manifest["source_manifest_path"],
                            "sha256": manifest["source_manifest_sha256"],
                            "schema_version": "1939-v50-phase-a-anchor-manifest-v1",
                            "required": True,
                        }
                    ],
                    "adapter_id": f"{manifest['phase_id']}-adapter-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "mechanically_bound",
                    "authorisation_evidence": "contemporaneous_phase_package",
                    "contribution_sha256": manifest["reconciliation_content_sha256"],
                }
                for sequence, manifest in enumerate(manifests, start=1)
            ],
        }
    )


def _unbound_ledger() -> dict:
    return seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "phase-a",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "phase-a.json",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-phase-a-anchor-manifest-v1",
                            "required": True,
                        }
                    ],
                    "adapter_id": "phase-a-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "afterdocumented_unbound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )


def _unavailable_ledger() -> dict:
    return seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "d1",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "historical_apply_script",
                            "path": "d1-historical-exception.placeholder",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-d1-historical-apply-v1",
                            "required": True,
                        }
                    ],
                    "adapter_id": "d1-historical-exception-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "unavailable",
                    "authorisation_evidence": "unavailable",
                }
            ],
        }
    )


def _write_cli_reconciliation_inputs(tmp_path, snapshot: dict, *manifests: dict) -> list[str]:
    contributions = []
    bound_manifests = []
    for manifest in manifests:
        original = tmp_path / f"{manifest['phase_id']}-original.json"
        original.write_bytes(b'{"original":true}\n')
        bound = dict(manifest)
        bound["source_manifest_path"] = original.name
        bound["source_manifest_sha256"] = hashlib.sha256(original.read_bytes()).hexdigest()
        bound = _with_hash(
            {key: value for key, value in bound.items() if key != "reconciliation_content_sha256"},
            "reconciliation_content_sha256",
        )
        contribution = tmp_path / f"{bound['phase_id']}-contribution.json"
        contribution.write_text(json.dumps(bound), encoding="utf-8")
        contributions.extend(["--phase-manifest", str(contribution)])
        bound_manifests.append(bound)

    snapshot_path = tmp_path / "snapshot.json"
    snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")
    ledger_path = tmp_path / "ledger.json"
    ledger_path.write_text(json.dumps(_ledger(*bound_manifests)), encoding="utf-8")
    return ["--snapshot", str(snapshot_path), "--ledger", str(ledger_path), *contributions]


def _drifting_cli_args(tmp_path) -> list[str]:
    phase_a = _manifest("phase-a", record_key="record-1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    snapshot = _snapshot(phase_a)
    snapshot["source_records"] = [{"source_id": 3, "record_key": "record-2"}]
    snapshot = _with_hash(
        {key: value for key, value in snapshot.items() if key != "snapshot_content_sha256"},
        "snapshot_content_sha256",
    )
    return _write_cli_reconciliation_inputs(tmp_path, snapshot, phase_a)


def test_reconcile_matches_snapshot_against_ordered_phase_final_state():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=202)

    report = _reconcile_capability(_snapshot(phase_a, phase_b), [phase_a, phase_b], _ledger(phase_a, phase_b))

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


def test_reconcile_refuses_an_incomplete_ledger_with_an_afterdocumented_phase_before_snapshot_comparison():
    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_INCOMPLETE"):
        _reconcile_capability({}, [], _unbound_ledger())


@pytest.mark.parametrize("adapter_id", ["phase-a-adapter-v1", "unknown-adapter-v1"])
def test_public_cli_rejects_a_one_phase_or_unknown_adapter_ledger_before_snapshot_validation(tmp_path, capsys, adapter_id):
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    ledger = _ledger(phase_a)
    ledger["phases"][0]["adapter_id"] = adapter_id
    ledger = seal_ledger({key: value for key, value in ledger.items() if key != "ledger_content_sha256"})

    contribution = tmp_path / "phase-a.contribution.json"
    ledger_path = tmp_path / "ledger.json"
    contribution.write_text(json.dumps(phase_a), encoding="utf-8")
    ledger_path.write_text(json.dumps(ledger), encoding="utf-8")

    assert main([
        "--snapshot", str(tmp_path / "must-not-read.json"),
        "--phase-manifest", str(contribution),
        "--ledger", str(ledger_path),
        "--private-report", str(tmp_path / "private-report.json"),
    ]) == 2
    assert json.loads(capsys.readouterr().err)["error"] == "EVIDENCE_RECONCILIATION_HISTORICAL_INVENTORY_INVALID"


def test_reconcile_refuses_an_unavailable_historical_phase_before_snapshot_validation():
    """An invalid snapshot must remain unread when D1 is still unavailable."""
    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_INCOMPLETE"):
        _reconcile_capability({"not": "a snapshot"}, [], _unavailable_ledger())


def test_reconcile_rejects_a_direct_ledger_with_an_undeclared_task25_role():
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "task25",
                    "sequence": 1,
                    "artifacts": [
                        {"role": "manifest", "path": "manifest.json", "sha256": "a" * 64, "schema_version": "1939-v50-production-write-manifest-v1", "required": True},
                        {"role": "undeclared", "path": "undeclared.json", "sha256": "b" * 64, "schema_version": "synthetic-v1", "required": True},
                    ],
                    "adapter_id": "task25-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "afterdocumented_unbound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_CONTRACT_INVALID"):
        _reconcile_capability({}, [], ledger)


def test_reconcile_rejects_a_missing_ledger_contribution_before_snapshot_validation():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=202)

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_LEDGER_MISMATCH"):
        _reconcile_capability({}, [phase_b], _ledger(phase_a))


def test_reconcile_fails_closed_when_production_has_an_unmanifested_binding():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    snapshot = _snapshot(phase_a)
    snapshot["narrative_bindings"].append({"source_id": 3, "record_key": "1939:unmanifested", "narrative_id": 999})
    snapshot = _with_hash({key: value for key, value in snapshot.items() if key != "snapshot_content_sha256"}, "snapshot_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_DRIFT") as caught:
        _reconcile_capability(snapshot, [phase_a], _ledger(phase_a))

    assert caught.value.report["differences"]["narrative_bindings"]["unexpected"] == [
        {"narrative_id": 999, "record_key": "1939:unmanifested", "source_id": 3}
    ]


def test_reconcile_fails_closed_when_production_has_a_different_value_for_the_same_identity():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    snapshot = _snapshot(phase_a)
    snapshot["narrative_sha256"] = [{"narrative_id": 201, "sha256": "c" * 64}]
    snapshot = _with_hash({key: value for key, value in snapshot.items() if key != "snapshot_content_sha256"}, "snapshot_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_DRIFT") as caught:
        _reconcile_capability(snapshot, [phase_a], _ledger(phase_a))

    difference = caught.value.report["differences"]["narrative_sha256"]
    assert difference["missing"] == [{"narrative_id": 201, "sha256": "b" * 64}]
    assert difference["unexpected"] == [{"narrative_id": 201, "sha256": "c" * 64}]


def test_reconcile_accepts_later_phase_override_for_an_already_touched_narrative():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=201, narrative_sha256="c" * 64)

    report = _reconcile_capability(_snapshot(phase_a, phase_b), [phase_b, phase_a], _ledger(phase_a, phase_b))

    assert report["phase_ids"] == ["phase-a", "phase-b"]
    assert report["counts"]["narrative_sha256"] == 1
    assert report["overrides"]["narrative_sha256"] == 1


def test_reconcile_applies_a_later_withdrawal_before_comparing_final_state():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=202, narrative_sha256="c" * 64)
    phase_b["withdrawals"]["narrative_sha256"] = [{"narrative_id": 201}]
    phase_b = _with_hash({key: value for key, value in phase_b.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    report = _reconcile_capability(_snapshot(phase_b), [phase_a, phase_b], _ledger(phase_a, phase_b))

    assert report["status"] == "match"
    assert report["counts"]["narrative_sha256"] == 1


def test_reconcile_rejects_duplicate_final_state_inside_one_contribution():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["source_records"].append({"source_id": 3, "record_key": "1939:1"})
    phase_a = _with_hash({key: value for key, value in phase_a.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_CONTRIBUTION_DUPLICATE"):
        _reconcile_capability(_snapshot(phase_a), [phase_a], _ledger(phase_a))


def test_reconcile_rejects_a_manifest_without_a_complete_withdrawals_shape():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    del phase_a["withdrawals"]
    phase_a = _with_hash({key: value for key, value in phase_a.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_WITHDRAWALS_INVALID"):
        _reconcile_capability(_snapshot(), [phase_a], _ledger(phase_a))


def test_reconcile_rejects_a_withdrawal_that_conflicts_with_its_new_row():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["withdrawals"]["source_records"] = [{"source_id": 3, "record_key": "1939:1"}]
    phase_a = _with_hash({key: value for key, value in phase_a.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_WITHDRAWAL_CONFLICT"):
        _reconcile_capability(_snapshot(), [phase_a], _ledger(phase_a))


def test_reconcile_rejects_a_withdrawal_without_a_previous_state():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=202)
    phase_b["withdrawals"]["narrative_sha256"] = [{"narrative_id": 999}]
    phase_b = _with_hash({key: value for key, value in phase_b.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_WITHDRAWAL_MISSING"):
        _reconcile_capability(_snapshot(phase_a, phase_b), [phase_a, phase_b], _ledger(phase_a, phase_b))


def test_reconcile_rejects_a_tampered_phase_manifest_before_comparing_any_state():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["persons"] = [{"person_id": 999}]

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_MANIFEST_HASH_INVALID"):
        _reconcile_capability(_snapshot(phase_a), [phase_a], _ledger(phase_a))


def test_seal_adds_a_canonical_hash_without_mutating_the_capture_document():
    raw_snapshot = {
        "schema_version": "daa-evidence-production-snapshot-v1",
        "database_target_identity": _target_identity(),
        "source_records": [],
        "source_anchors": [],
        "narrative_bindings": [],
        "narrative_sha256": [],
        "persons": [],
    }

    sealed = seal(raw_snapshot)

    assert "snapshot_content_sha256" not in raw_snapshot
    assert sealed["snapshot_content_sha256"] == _with_hash(raw_snapshot, "snapshot_content_sha256")["snapshot_content_sha256"]


def test_snapshot_rejects_a_missing_production_target_identity():
    snapshot = _snapshot()
    del snapshot["database_target_identity"]
    snapshot = _with_hash(
        {key: value for key, value in snapshot.items() if key != "snapshot_content_sha256"},
        "snapshot_content_sha256",
    )

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_SNAPSHOT_TARGET_INVALID"):
        _validate_snapshot(snapshot)


def test_snapshot_rejects_a_target_identity_other_than_the_admitted_ledger_target():
    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_SNAPSHOT_TARGET_MISMATCH"):
        _validate_snapshot(_snapshot(), expected_target_identity_sha256="a" * 64)


@pytest.mark.parametrize("raw", [b'{"phase_id":"first","phase_id":"second"}', b'\xff'])
def test_json_loader_redacts_duplicate_keys_and_invalid_utf8(tmp_path, raw):
    path = tmp_path / "malformed.json"
    path.write_bytes(raw)

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_INPUT_UNREADABLE"):
        _load_json(path)


def test_loading_a_phase_contribution_does_not_reopen_its_original_manifest(tmp_path):
    original = tmp_path / "original-manifest.json"
    original.write_bytes(b'{"original":true}\n')
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["source_manifest_sha256"] = hashlib.sha256(original.read_bytes()).hexdigest()
    phase_a = _with_hash({key: value for key, value in phase_a.items() if key != "reconciliation_content_sha256"}, "reconciliation_content_sha256")
    contribution = tmp_path / "phase-a.json"
    contribution.write_text(json.dumps(phase_a), encoding="utf-8")

    original.unlink()
    assert load_phase_manifest(contribution) == phase_a


def test_reconcile_rejects_a_contribution_with_a_source_manifest_binding_mismatch_before_snapshot_validation():
    original = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    changed = dict(original)
    changed["source_manifest_path"] = "other-original-manifest.json"
    changed = _with_hash(
        {key: value for key, value in changed.items() if key != "reconciliation_content_sha256"},
        "reconciliation_content_sha256",
    )
    ledger = _ledger(original)
    ledger["phases"][0]["contribution_sha256"] = changed["reconciliation_content_sha256"]
    ledger = seal_ledger({key: value for key, value in ledger.items() if key != "ledger_content_sha256"})

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_MISMATCH"):
        _reconcile_capability({"not": "a snapshot"}, [changed], ledger)


def test_reconcile_checks_source_manifest_binding_when_contributions_are_an_iterator():
    original = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    changed = dict(original)
    changed["source_manifest_sha256"] = "b" * 64
    changed = _with_hash(
        {key: value for key, value in changed.items() if key != "reconciliation_content_sha256"},
        "reconciliation_content_sha256",
    )
    ledger = _ledger(original)
    ledger["phases"][0]["contribution_sha256"] = changed["reconciliation_content_sha256"]
    ledger = seal_ledger({key: value for key, value in ledger.items() if key != "ledger_content_sha256"})

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_MISMATCH"):
        _reconcile_capability({"not": "a snapshot"}, iter([changed]), ledger)


def test_cli_requires_a_private_report_path_for_reconciliation(tmp_path, capsys):
    assert main(_drifting_cli_args(tmp_path)) == 2

    terminal = json.loads(capsys.readouterr().err)
    assert terminal["error"] == "EVIDENCE_RECONCILIATION_PRIVATE_REPORT_REQUIRED"


def test_cli_rejects_a_capability_only_ledger_to_a_mode_0600_private_report(tmp_path, capsys):
    private_report = tmp_path / "private-drift.json"

    assert main([*_drifting_cli_args(tmp_path), "--private-report", str(private_report)]) == 2

    terminal = json.loads(capsys.readouterr().err)
    assert terminal["error"] == "EVIDENCE_RECONCILIATION_HISTORICAL_INVENTORY_INVALID"
    assert "record-1" not in json.dumps(terminal)
    assert oct(private_report.stat().st_mode & 0o777) == "0o600"
    assert json.loads(private_report.read_text(encoding="utf-8"))["error"] == "EVIDENCE_RECONCILIATION_HISTORICAL_INVENTORY_INVALID"


def test_cli_rejects_an_existing_private_report_before_reading_reconciliation_inputs(tmp_path, capsys):
    private_report = tmp_path / "private-drift.json"
    private_report.write_text("do not overwrite", encoding="utf-8")
    args = [
        "--snapshot",
        str(tmp_path / "unreadable-snapshot.json"),
        "--ledger",
        str(tmp_path / "unreadable-ledger.json"),
        "--phase-manifest",
        str(tmp_path / "unreadable-manifest.json"),
        "--private-report",
        str(private_report),
    ]

    assert main(args) == 2

    terminal = json.loads(capsys.readouterr().err)
    assert terminal["error"] == "EVIDENCE_RECONCILIATION_PRIVATE_REPORT_EXISTS"
    assert private_report.read_text(encoding="utf-8") == "do not overwrite"


def test_cli_rejects_an_unwritable_private_report_before_reading_reconciliation_inputs(tmp_path, capsys):
    private_report = tmp_path / "missing-parent" / "private-drift.json"
    args = [
        "--snapshot",
        str(tmp_path / "unreadable-snapshot.json"),
        "--ledger",
        str(tmp_path / "unreadable-ledger.json"),
        "--phase-manifest",
        str(tmp_path / "unreadable-manifest.json"),
        "--private-report",
        str(private_report),
    ]

    assert main(args) == 2

    terminal = json.loads(capsys.readouterr().err)
    assert terminal["error"] == "EVIDENCE_RECONCILIATION_PRIVATE_REPORT_UNWRITABLE"
    assert not private_report.exists()


def test_cli_loads_phase_contributions_before_reading_the_snapshot(tmp_path, capsys):
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["persons"] = [{"person_id": 999}]
    contribution = tmp_path / "phase-a.json"
    contribution.write_text(json.dumps(phase_a), encoding="utf-8")
    ledger = tmp_path / "ledger.json"
    ledger.write_text(json.dumps(_ledger(_manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201))), encoding="utf-8")

    status = main(
        [
            "--snapshot",
            str(tmp_path / "missing-snapshot.json"),
            "--phase-manifest",
            str(contribution),
            "--ledger",
            str(ledger),
            "--private-report",
            str(tmp_path / "private-report.json"),
        ]
    )

    assert status == 2
    assert json.loads(capsys.readouterr().err)["error"] == "EVIDENCE_RECONCILIATION_MANIFEST_HASH_INVALID"


def test_cli_rejects_a_capability_only_ledger_before_reading_the_snapshot(tmp_path, capsys):
    original = tmp_path / "original-manifest.json"
    original.write_bytes(b'{"original":true}\n')
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_a["source_manifest_sha256"] = hashlib.sha256(original.read_bytes()).hexdigest()
    phase_a = _with_hash(
        {key: value for key, value in phase_a.items() if key != "reconciliation_content_sha256"},
        "reconciliation_content_sha256",
    )
    contribution = tmp_path / "phase-a.json"
    contribution.write_text(json.dumps(phase_a), encoding="utf-8")
    ledger = _ledger(phase_a)
    ledger["phases"][0]["contribution_sha256"] = "c" * 64
    ledger = seal_ledger(
        {key: value for key, value in ledger.items() if key != "ledger_content_sha256"}
    )
    ledger_path = tmp_path / "ledger.json"
    ledger_path.write_text(json.dumps(ledger), encoding="utf-8")

    status = main(
        [
            "--snapshot",
            str(tmp_path / "missing-snapshot.json"),
            "--phase-manifest",
            str(contribution),
            "--ledger",
            str(ledger_path),
            "--private-report",
            str(tmp_path / "private-report.json"),
        ]
    )

    assert status == 2
    assert json.loads(capsys.readouterr().err)["error"] == "EVIDENCE_RECONCILIATION_HISTORICAL_INVENTORY_INVALID"


def test_reconcile_rejects_a_ledger_that_names_a_phase_missing_from_the_command():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=202)

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_LEDGER_MISMATCH"):
        _reconcile_capability(_snapshot(phase_a), [phase_a], _ledger(phase_a, phase_b))


def test_reconcile_rejects_a_contribution_whose_hash_does_not_match_the_ledger():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    ledger = _ledger(phase_a)
    ledger["phases"][0]["contribution_sha256"] = "c" * 64
    ledger = seal_ledger({key: value for key, value in ledger.items() if key != "ledger_content_sha256"})

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_LEDGER_MISMATCH"):
        _reconcile_capability(_snapshot(phase_a), [phase_a], ledger)


def test_reconcile_rejects_a_ledger_with_a_duplicate_sequence():
    phase_a = _manifest("phase-a", record_key="1939:1", occurrence_key="occ-1", person_id=101, narrative_id=201)
    phase_b = _manifest("phase-b", record_key="1939:2", occurrence_key="occ-2", person_id=102, narrative_id=202)
    ledger = _ledger(phase_a, phase_b)
    ledger["phases"][1]["sequence"] = 1
    ledger = seal_ledger({key: value for key, value in ledger.items() if key != "ledger_content_sha256"})

    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_LEDGER_SEQUENCE_DUPLICATE"):
        _reconcile_capability(_snapshot(phase_a, phase_b), [phase_a, phase_b], ledger)
