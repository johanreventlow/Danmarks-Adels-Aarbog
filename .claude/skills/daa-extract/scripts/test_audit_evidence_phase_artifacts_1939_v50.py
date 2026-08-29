from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from audit_evidence_phase_artifacts_1939_v50 import AuditError, audit_bundle
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
            "person_id": 7,
            "record_key": "record-1",
            "narrative_id": 9,
            "before_sha256": "b" * 64,
            "after_sha256": "c" * 64,
            "publication_status": "published",
        }
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
        {"schema_version": "1939-v50-narrative-replacement-manifest-v2", "identity_map": []},
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
            "identity_map": identity_map,
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

    result = audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))

    assert result.phase("phase-b").projection_evidence == "mechanically_bound"
    assert result.phase("phase-b").error is None


def test_audit_marks_phase_b_unbound_when_receipt_names_another_manifest(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "identity_map": identity_map,
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": "d" * 64,
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
            "identity_map": identity_map,
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
            "identity_map": identity_map,
        },
    )
    malformed_map = [{key: value for key, value in identity_map[0].items() if key != "after_sha256"}]
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "identity_map": malformed_map,
        },
    )

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID"):
        audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))
