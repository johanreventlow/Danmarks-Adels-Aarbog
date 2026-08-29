from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from audit_evidence_phase_artifacts_1939_v50 import AuditError, audit_bundle, receipt_binds_manifest_and_identities
from evidence_phase_artifact_ledger import ArtifactEntry, PhaseEntry, seal_ledger, validate_ledger


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def write_json(path: Path, document: object) -> str:
    raw = json.dumps(document, sort_keys=True, separators=(",", ":")).encode("utf-8")
    path.write_bytes(raw)
    return sha256_bytes(raw)


def sealed_phase_b_ledger(manifest_sha256: str) -> list:
    return validate_ledger(
        seal_ledger(
            {
                "schema_version": "daa-evidence-phase-artifact-ledger-v2",
                "phases": [
                    {
                        "phase_id": "phase-b",
                        "sequence": 1,
                        "artifacts": [
                            {
                                "role": "manifest",
                                "path": "phase-b.json",
                                "sha256": manifest_sha256,
                                "schema_version": "1939-v50-narrative-replacement-manifest-v2",
                                "required": True,
                            }
                        ],
                        "adapter_id": "phase-b-v1",
                        "adapter_sha256": "a" * 64,
                        "projection_evidence": "afterdocumented_unbound",
                        "authorisation_evidence": "afterdocumented_authorisation_gap",
                    }
                ],
            }
        )
    )


def phase_b_ledger_with_receipt(manifest_sha256: str, receipt_sha256: str) -> list:
    ledger = sealed_phase_b_ledger(manifest_sha256)
    phase = ledger[0]
    return [
        PhaseEntry(
            phase_id=phase.phase_id,
            sequence=phase.sequence,
            artifacts=phase.artifacts
            + (
                ArtifactEntry(
                    role="receipt",
                    path="phase-b-receipt.json",
                    sha256=receipt_sha256,
                    schema_version="daa-evidence-phase-receipt-phase-b-v1",
                    required=True,
                ),
            ),
            adapter_id=phase.adapter_id,
            adapter_sha256=phase.adapter_sha256,
            projection_evidence=phase.projection_evidence,
            authorisation_evidence=phase.authorisation_evidence,
        )
    ]


def phase_b_manifest_phase(path: str, sha256: str) -> PhaseEntry:
    phase = sealed_phase_b_ledger("a" * 64)[0]
    return PhaseEntry(
        phase_id=phase.phase_id,
        sequence=phase.sequence,
        artifacts=(
            ArtifactEntry(
                role="manifest",
                path=path,
                sha256=sha256,
                schema_version="1939-v50-narrative-replacement-manifest-v2",
                required=True,
            ),
        ),
        adapter_id=phase.adapter_id,
        adapter_sha256=phase.adapter_sha256,
        projection_evidence=phase.projection_evidence,
        authorisation_evidence=phase.authorisation_evidence,
    )


def phase_b_identity_map() -> list[dict]:
    return [
        {
            "person_id": person_id,
            "record_key": f"record-{person_id}",
            "narrative_id": 10000 + person_id,
            "before_sha256": f"{person_id:064x}",
            "after_sha256": f"{person_id + 551:064x}",
            "publication_status": "published",
        }
        for person_id in range(1, 552)
    ]


def phase_b_operations(identity_map: list[dict]) -> list[dict]:
    return [
        {
            "person_id": row["person_id"],
            "source_record_key": row["record_key"],
            "expected_old_narrative_sha256": row["before_sha256"],
            "normalized_sha256": row["after_sha256"],
        }
        for row in identity_map
    ]


def sealed_d1_ledger() -> list:
    return validate_ledger(
        seal_ledger(
            {
                "schema_version": "daa-evidence-phase-artifact-ledger-v2",
                "phases": [
                    {
                        "phase_id": "d1",
                        "sequence": 1,
                        "artifacts": [
                            {
                                "role": "legacy-apply",
                                "path": "d1.apply",
                                "sha256": "b" * 64,
                                "schema_version": "1939-v50-d1-legacy-apply-v1",
                                "required": False,
                            }
                        ],
                        "adapter_id": "d1-historical-exception-v1",
                        "adapter_sha256": "c" * 64,
                        "projection_evidence": "unavailable",
                        "authorisation_evidence": "unavailable",
                    }
                ],
            }
        )
    )


def test_audit_marks_a_phase_b_baseline_without_a_manifest_bound_receipt_unbound(tmp_path):
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {"schema_version": "1939-v50-narrative-replacement-manifest-v2", "operations": []},
    )

    result = audit_bundle(tmp_path, sealed_phase_b_ledger(manifest_sha256))

    assert result.phase("phase-b").projection_evidence == "afterdocumented_unbound"
    assert result.phase("phase-b").error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


def test_audit_marks_d1_as_a_manifestless_historical_exception(tmp_path):
    result = audit_bundle(tmp_path, sealed_d1_ledger())

    assert result.phase("d1").projection_evidence == "unavailable"
    assert result.phase("d1").error == "EVIDENCE_RECONCILIATION_HISTORICAL_EXCEPTION_NO_MANIFEST"


def test_audit_marks_phase_b_mechanically_bound_only_for_an_exact_manifest_and_identity_map(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": identity_map,
        },
    )

    result = audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))

    assert result.phase("phase-b").projection_evidence == "mechanically_bound"
    assert result.phase("phase-b").error is None


def test_audit_marks_phase_b_unbound_when_receipt_names_another_manifest(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": "d" * 64,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": identity_map,
        },
    )

    result = audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))

    assert result.phase("phase-b").projection_evidence == "afterdocumented_unbound"
    assert result.phase("phase-b").error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


def test_audit_rejects_a_required_non_json_receipt_before_classification(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_bytes = b"not-json"
    (tmp_path / "phase-b-receipt.json").write_bytes(receipt_bytes)

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID"):
        audit_bundle(
            tmp_path,
            phase_b_ledger_with_receipt(manifest_sha256, sha256_bytes(receipt_bytes)),
        )


def test_audit_rejects_a_required_artifact_path_escaping_the_bundle(tmp_path):
    escaped = tmp_path.parent / "escaped.json"
    escaped.write_bytes(b"{}")
    phase = PhaseEntry(
        phase_id="phase-b",
        sequence=1,
        artifacts=(
            ArtifactEntry(
                role="manifest",
                path="../escaped.json",
                sha256=sha256_bytes(escaped.read_bytes()),
                schema_version="1939-v50-narrative-replacement-manifest-v2",
                required=True,
            ),
        ),
        adapter_id="phase-b-v1",
        adapter_sha256="a" * 64,
        projection_evidence="afterdocumented_unbound",
        authorisation_evidence="afterdocumented_authorisation_gap",
    )

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID"):
        audit_bundle(tmp_path, [phase])


def test_audit_rejects_a_missing_required_artifact_before_classification(tmp_path):
    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_MISSING"):
        audit_bundle(tmp_path, [phase_b_manifest_phase("missing.json", "a" * 64)])


def test_audit_rejects_an_unreadable_required_artifact_before_classification(tmp_path):
    (tmp_path / "directory.json").mkdir()

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE"):
        audit_bundle(tmp_path, [phase_b_manifest_phase("directory.json", "a" * 64)])


def test_audit_rejects_a_hash_drifting_required_artifact_before_classification(tmp_path):
    write_json(
        tmp_path / "phase-b.json",
        {"schema_version": "1939-v50-narrative-replacement-manifest-v2"},
    )

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_HASH_INVALID"):
        audit_bundle(tmp_path, [phase_b_manifest_phase("phase-b.json", "a" * 64)])


def test_audit_rejects_a_receipt_with_a_non_exact_phase_b_identity_map_schema(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    malformed_map = [{key: value for key, value in identity_map[0].items() if key != "after_sha256"}]
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": malformed_map,
        },
    )

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID"):
        audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))


def test_audit_rejects_a_nonrequired_phase_b_manifest_before_classification(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": identity_map,
        },
    )
    phase = phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256)[0]
    optional_manifest = ArtifactEntry(
        role="manifest",
        path="phase-b.json",
        sha256=manifest_sha256,
        schema_version="1939-v50-narrative-replacement-manifest-v2",
        required=False,
    )
    ledger = [
        PhaseEntry(
            phase_id=phase.phase_id,
            sequence=phase.sequence,
            artifacts=(optional_manifest, phase.artifacts[1]),
            adapter_id=phase.adapter_id,
            adapter_sha256=phase.adapter_sha256,
            projection_evidence=phase.projection_evidence,
            authorisation_evidence=phase.authorisation_evidence,
        )
    ]

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_MANIFEST_REQUIRED"):
        audit_bundle(tmp_path, ledger)


def test_receipt_binding_rejects_a_ledger_manifest_hash_that_differs_from_verified_bytes(tmp_path):
    identity_map = phase_b_identity_map()
    actual_manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    declared_manifest_sha256 = "a" * 64
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": declared_manifest_sha256,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": identity_map,
        },
    )
    phase = phase_b_ledger_with_receipt(declared_manifest_sha256, receipt_sha256)[0]

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_HASH_INVALID"):
        receipt_binds_manifest_and_identities(
            {"manifest": tmp_path / "phase-b.json", "receipt": tmp_path / "phase-b-receipt.json"},
            phase,
        )

    assert actual_manifest_sha256 != declared_manifest_sha256


def test_audit_marks_a_phase_b_receipt_with_only_one_of_551_identities_unbound(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": identity_map[:1],
        },
    )

    result = audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))

    assert result.phase("phase-b").error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


def test_audit_rejects_a_phase_b_receipt_without_database_target_identity(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "identity_map": identity_map,
        },
    )

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID"):
        audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))


@pytest.mark.parametrize("field", ["person_id", "record_key", "narrative_id"])
def test_audit_marks_a_phase_b_receipt_with_a_duplicate_identity_field_unbound(tmp_path, field):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_map = phase_b_identity_map()
    receipt_map[-1] = {**receipt_map[-1], field: receipt_map[0][field]}
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": receipt_map,
        },
    )

    result = audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))

    assert result.phase("phase-b").error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


def test_audit_marks_a_phase_b_receipt_with_an_unallowed_publication_status_unbound(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_map = phase_b_identity_map()
    receipt_map[-1] = {**receipt_map[-1], "publication_status": "draft"}
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": receipt_map,
        },
    )

    result = audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))

    assert result.phase("phase-b").error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


def test_audit_rejects_a_phase_b_receipt_identity_not_matched_by_manifest_operation(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_map = phase_b_identity_map()
    receipt_map[-1] = {**receipt_map[-1], "after_sha256": "f" * 64}
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": receipt_map,
        },
    )

    result = audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))

    assert result.phase("phase-b").error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


def test_audit_rejects_duplicate_json_keys_before_classification(tmp_path):
    raw = b'{"schema_version":"1939-v50-narrative-replacement-manifest-v2","schema_version":"other"}'
    (tmp_path / "phase-b.json").write_bytes(raw)

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID"):
        audit_bundle(tmp_path, [phase_b_manifest_phase("phase-b.json", sha256_bytes(raw))])


@pytest.mark.parametrize("path", ["/tmp/not-an-artifact.json", "../not-an-artifact.json"])
def test_audit_rejects_absolute_and_traversal_artifact_paths(tmp_path, path):
    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID"):
        audit_bundle(tmp_path, [phase_b_manifest_phase(path, "a" * 64)])


def test_audit_rejects_a_symlink_loop_artifact_path(tmp_path):
    (tmp_path / "loop.json").symlink_to("loop.json")

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID"):
        audit_bundle(tmp_path, [phase_b_manifest_phase("loop.json", "a" * 64)])


def test_audit_reads_a_required_artifact_once_for_hash_and_json_admission(tmp_path, monkeypatch):
    identity_map = phase_b_identity_map()
    manifest_path = tmp_path / "phase-b.json"
    manifest_sha256 = write_json(
        manifest_path,
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": "synthetic-target-v1",
            "identity_map": identity_map,
        },
    )
    original_open = Path.open
    opens = 0

    def open_manifest_once(path, *args, **kwargs):
        nonlocal opens
        if path == manifest_path:
            opens += 1
            if opens > 1:
                raise AssertionError("manifest was reopened after byte-hash admission")
        return original_open(path, *args, **kwargs)

    monkeypatch.setattr(Path, "open", open_manifest_once)

    result = audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))

    assert result.phase("phase-b").projection_evidence == "mechanically_bound"
    assert opens == 1
