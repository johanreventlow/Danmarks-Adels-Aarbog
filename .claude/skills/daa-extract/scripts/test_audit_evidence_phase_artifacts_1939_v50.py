from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from audit_evidence_phase_artifacts_1939_v50 import AuditError, audit_bundle, receipt_binds_manifest_and_identities
from evidence_phase_artifact_ledger import ArtifactEntry, PhaseEntry, canonical_sha256, seal_ledger, validate_ledger


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def write_json(path: Path, document: object) -> str:
    raw = json.dumps(document, sort_keys=True, separators=(",", ":")).encode("utf-8")
    path.write_bytes(raw)
    return sha256_bytes(raw)


def production_target_identity() -> dict:
    return {
        "schema_version": "daa-evidence-production-target-identity-v1",
        "environment": "production",
        "system_identifier_sha256": "e" * 64,
    }


def production_target_identity_sha256() -> str:
    return canonical_sha256(production_target_identity(), "")


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
                        "database_target_identity_sha256": production_target_identity_sha256(),
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
            database_target_identity_sha256=phase.database_target_identity_sha256,
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
        database_target_identity_sha256=phase.database_target_identity_sha256,
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


NEW_ADAPTERS = {
    "phase-a-v1": (
        "phase-a",
        "1939-v50-phase-a-anchor-manifest-v1",
        "daa-evidence-phase-receipt-phase-a-v1",
        "identity_map",
    ),
    "narrative-publication-v1": (
        "narrative-publication",
        "1939-v50-narrative-publication-manifest-v1",
        "daa-evidence-phase-receipt-narrative-publication-v1",
        "identity_map",
    ),
    "name-completion-v1": (
        "name-completion",
        "1939-v50-name-completion-manifest-v1",
        "daa-evidence-phase-receipt-name-completion-v1",
        "completion_results",
    ),
}


def phase_a_identities() -> list[dict]:
    return [
        {"record_key": f"record-{number}", "occurrence_key": f"occurrence-{number}"}
        for number in range(1, 585)
    ]


def narrative_publication_identities() -> list[dict]:
    return [
        {
            "source_id": 3,
            "record_key": f"record-{number}",
            "narrative_id": number,
            "binding_id": f"binding-{number}",
        }
        for number in range(1, 9)
    ]


def name_completion_results() -> list[dict]:
    return [
        {
            "person_id": number,
            "fact_id": 100 + number,
            "assertion_id": 200 + number,
            "citation_id": 300 + number,
            "conclusion_id": 400 + number,
        }
        for number in range(1, 9)
    ]


def new_adapter_manifest(adapter_id: str) -> dict:
    if adapter_id == "phase-a-v1":
        return {
            "schema_version": NEW_ADAPTERS[adapter_id][1],
            "source": {"database_source_id": 3},
            "operations": [
                {
                    "source_record_key": row["record_key"],
                    "element_id": row["occurrence_key"],
                }
                for row in phase_a_identities()
            ],
        }
    if adapter_id == "narrative-publication-v1":
        return {
            "schema_version": NEW_ADAPTERS[adapter_id][1],
            "bindings": [
                {
                    "record_key": row["record_key"],
                    "narrative_id": row["narrative_id"],
                    "binding_id": row["binding_id"],
                }
                for row in narrative_publication_identities()
            ],
        }
    assert adapter_id == "name-completion-v1"
    return {
        "schema_version": NEW_ADAPTERS[adapter_id][1],
        "operations": [{"person_id": row["person_id"]} for row in name_completion_results()],
    }


def new_adapter_receipt(adapter_id: str, manifest_sha256: str) -> dict:
    identity_field = NEW_ADAPTERS[adapter_id][3]
    identities = (
        phase_a_identities()
        if adapter_id == "phase-a-v1"
        else narrative_publication_identities()
        if adapter_id == "narrative-publication-v1"
        else name_completion_results()
    )
    return {
        "schema_version": NEW_ADAPTERS[adapter_id][2],
        "manifest_sha256": manifest_sha256,
        "database_target_identity": production_target_identity(),
        identity_field: identities,
    }


def new_adapter_phase(adapter_id: str, manifest_sha256: str, receipt_sha256: str | None) -> PhaseEntry:
    phase_id, manifest_schema, receipt_schema, _ = NEW_ADAPTERS[adapter_id]
    artifacts = [
        ArtifactEntry("manifest", f"{phase_id}.json", manifest_sha256, manifest_schema, True),
    ]
    if receipt_sha256 is not None:
        artifacts.append(
            ArtifactEntry("receipt", f"{phase_id}-receipt.json", receipt_sha256, receipt_schema, True)
        )
    return PhaseEntry(
        phase_id=phase_id,
        sequence=1,
        artifacts=tuple(artifacts),
        adapter_id=adapter_id,
        adapter_sha256="a" * 64,
        projection_evidence="afterdocumented_unbound",
        authorisation_evidence="afterdocumented_authorisation_gap",
        database_target_identity_sha256=production_target_identity_sha256(),
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
            "database_target_identity": production_target_identity(),
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
            "database_target_identity": production_target_identity(),
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
            "database_target_identity": production_target_identity(),
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
            "database_target_identity": production_target_identity(),
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
            database_target_identity_sha256=phase.database_target_identity_sha256,
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
            "database_target_identity": production_target_identity(),
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
            "database_target_identity": production_target_identity(),
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
            "database_target_identity": production_target_identity(),
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
            "database_target_identity": production_target_identity(),
            "identity_map": receipt_map,
        },
    )

    result = audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))

    assert result.phase("phase-b").error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


def test_audit_rejects_a_phase_b_receipt_with_a_non_string_publication_status(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_map = phase_b_identity_map()
    receipt_map[-1] = {**receipt_map[-1], "publication_status": []}
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": production_target_identity(),
            "identity_map": receipt_map,
        },
    )

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID"):
        audit_bundle(tmp_path, phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256))


@pytest.mark.parametrize("environment", ["rehearsal", "synthetic"])
def test_audit_marks_a_nonproduction_receipt_target_unbound(tmp_path, environment):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    target = {**production_target_identity(), "environment": environment}
    receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": target,
            "identity_map": identity_map,
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
            "database_target_identity": production_target_identity(),
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


@pytest.mark.parametrize("path", ["/tmp/not-an-artifact.json", "../not-an-artifact.json", "nul\x00.json"])
def test_audit_rejects_absolute_and_traversal_artifact_paths(tmp_path, path):
    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID"):
        audit_bundle(tmp_path, [phase_b_manifest_phase(path, "a" * 64)])


def test_direct_receipt_helper_maps_a_nul_receipt_path_to_the_stable_path_error(tmp_path):
    identity_map = phase_b_identity_map()
    manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {
            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
            "operations": phase_b_operations(identity_map),
        },
    )
    receipt_sha256 = sha256_bytes(b"unused")
    phase = phase_b_ledger_with_receipt(manifest_sha256, receipt_sha256)[0]

    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID"):
        receipt_binds_manifest_and_identities(
            {"manifest": tmp_path / "phase-b.json", "receipt": Path("nul\x00receipt.json")},
            phase,
        )


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
            "database_target_identity": production_target_identity(),
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


@pytest.mark.parametrize("adapter_id", NEW_ADAPTERS)
def test_audit_binds_each_new_adapter_to_its_exact_manifest_identities(tmp_path, adapter_id: str):
    phase_id = NEW_ADAPTERS[adapter_id][0]
    manifest_sha256 = write_json(tmp_path / f"{phase_id}.json", new_adapter_manifest(adapter_id))
    receipt_sha256 = write_json(
        tmp_path / f"{phase_id}-receipt.json", new_adapter_receipt(adapter_id, manifest_sha256)
    )

    result = audit_bundle(tmp_path, [new_adapter_phase(adapter_id, manifest_sha256, receipt_sha256)])

    assert result.phase(phase_id).projection_evidence == "mechanically_bound"
    assert result.phase(phase_id).error is None


@pytest.mark.parametrize("adapter_id", NEW_ADAPTERS)
def test_audit_marks_each_new_adapter_unbound_when_its_receipt_names_another_manifest(tmp_path, adapter_id: str):
    phase_id = NEW_ADAPTERS[adapter_id][0]
    manifest_sha256 = write_json(tmp_path / f"{phase_id}.json", new_adapter_manifest(adapter_id))
    receipt = new_adapter_receipt(adapter_id, "d" * 64)
    receipt_sha256 = write_json(tmp_path / f"{phase_id}-receipt.json", receipt)

    result = audit_bundle(tmp_path, [new_adapter_phase(adapter_id, manifest_sha256, receipt_sha256)])

    assert result.phase(phase_id).error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


@pytest.mark.parametrize("adapter_id", NEW_ADAPTERS)
def test_audit_marks_each_new_adapter_unbound_on_target_hash_drift(tmp_path, adapter_id: str):
    phase_id = NEW_ADAPTERS[adapter_id][0]
    manifest_sha256 = write_json(tmp_path / f"{phase_id}.json", new_adapter_manifest(adapter_id))
    receipt_sha256 = write_json(
        tmp_path / f"{phase_id}-receipt.json", new_adapter_receipt(adapter_id, manifest_sha256)
    )
    phase = new_adapter_phase(adapter_id, manifest_sha256, receipt_sha256)
    phase = PhaseEntry(
        **{**phase.__dict__, "database_target_identity_sha256": "f" * 64}
    )

    result = audit_bundle(tmp_path, [phase])

    assert result.phase(phase_id).error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


@pytest.mark.parametrize("adapter_id", NEW_ADAPTERS)
@pytest.mark.parametrize("mutation", ["duplicate", "missing", "extra", "replacement"])
def test_audit_marks_each_new_adapter_unbound_for_non_exact_identity_maps(
    tmp_path, adapter_id: str, mutation: str
):
    phase_id, _, _, identity_field = NEW_ADAPTERS[adapter_id]
    manifest_sha256 = write_json(tmp_path / f"{phase_id}.json", new_adapter_manifest(adapter_id))
    receipt = new_adapter_receipt(adapter_id, manifest_sha256)
    rows = receipt[identity_field]
    assert isinstance(rows, list)
    if mutation == "duplicate":
        rows[-1] = dict(rows[0])
    elif mutation == "missing":
        del rows[-1]
    elif mutation == "extra":
        rows.append(dict(rows[0]))
    elif adapter_id == "phase-a-v1":
        rows[-1] = {"record_key": "unexpected-record", "occurrence_key": "unexpected-occurrence"}
    elif adapter_id == "narrative-publication-v1":
        rows[-1] = {
            "source_id": 3,
            "record_key": "unexpected-record",
            "narrative_id": rows[-1]["narrative_id"],
            "binding_id": rows[-1]["binding_id"],
        }
    else:
        rows[-1] = {**rows[-1], "person_id": 999}
    receipt_sha256 = write_json(tmp_path / f"{phase_id}-receipt.json", receipt)

    result = audit_bundle(tmp_path, [new_adapter_phase(adapter_id, manifest_sha256, receipt_sha256)])

    assert result.phase(phase_id).error == "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND"


def test_audit_binds_name_completion_when_completion_result_ids_are_shared(tmp_path):
    manifest_sha256 = write_json(tmp_path / "name-completion.json", new_adapter_manifest("name-completion-v1"))
    receipt = new_adapter_receipt("name-completion-v1", manifest_sha256)
    results = receipt["completion_results"]
    assert isinstance(results, list)
    results[-1]["fact_id"] = results[0]["fact_id"]
    receipt_sha256 = write_json(tmp_path / "name-completion-receipt.json", receipt)

    result = audit_bundle(
        tmp_path, [new_adapter_phase("name-completion-v1", manifest_sha256, receipt_sha256)]
    )

    assert result.phase("name-completion").projection_evidence == "mechanically_bound"


def test_audit_classifies_d1_before_parsing_a_hash_locked_non_json_historical_script(tmp_path):
    raw = b"#!/bin/sh\nprintf '%s\\n' synthetic-historical-apply\n"
    (tmp_path / "d1.apply").write_bytes(raw)
    phase = PhaseEntry(
        phase_id="d1",
        sequence=1,
        artifacts=(
            ArtifactEntry(
                "historical_apply_script",
                "d1.apply",
                sha256_bytes(raw),
                "1939-v50-d1-legacy-apply-v1",
                True,
            ),
        ),
        adapter_id="d1-historical-exception-v1",
        adapter_sha256="c" * 64,
        projection_evidence="unavailable",
        authorisation_evidence="unavailable",
    )

    result = audit_bundle(tmp_path, [phase])

    assert result.phase("d1").error == "EVIDENCE_RECONCILIATION_HISTORICAL_EXCEPTION_NO_MANIFEST"
