from __future__ import annotations

import hashlib
import json

import pytest

from audit_evidence_phase_artifacts_1939_v50 import PhaseSummary, audit_bundle
from evidence_phase_artifact_ledger import ArtifactEntry, PhaseEntry, canonical_sha256, seal_ledger, validate_ledger
from project_evidence_phase_artifacts_1939_v50 import ProjectError, project_phase
from reconcile_evidence_phase_gate import ReconciliationError, reconcile, seal


def write_json(path, document: object) -> str:
    raw = json.dumps(document, sort_keys=True, separators=(",", ":")).encode("utf-8")
    path.write_bytes(raw)
    return hashlib.sha256(raw).hexdigest()


def mechanically_bound_task25_phase(manifest_sha256: str, receipt_sha256: str) -> PhaseEntry:
    return PhaseEntry(
        phase_id="task25",
        sequence=1,
        artifacts=(
            ArtifactEntry(
                role="manifest",
                path="task25.json",
                sha256=manifest_sha256,
                schema_version="1939-v50-production-write-manifest-v1",
                required=True,
            ),
            ArtifactEntry(
                role="receipt",
                path="task25-receipt.json",
                sha256=receipt_sha256,
                schema_version="daa-evidence-phase-receipt-task25-v1",
                required=True,
            ),
        ),
        adapter_id="task25-v1",
        adapter_sha256="b" * 64,
        projection_evidence="mechanically_bound",
        authorisation_evidence="afterdocumented_authorisation_gap",
    )


def bound_summary(phase: PhaseEntry) -> PhaseSummary:
    return PhaseSummary(
        phase_id=phase.phase_id,
        projection_evidence="mechanically_bound",
        authorisation_evidence=phase.authorisation_evidence,
        error=None,
    )


def unbound_summary(phase: PhaseEntry) -> PhaseSummary:
    return PhaseSummary(
        phase_id=phase.phase_id,
        projection_evidence="afterdocumented_unbound",
        authorisation_evidence=phase.authorisation_evidence,
        error="EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND",
    )


def mechanically_bound_c0_phase(manifest_sha256: str, receipt_sha256: str) -> PhaseEntry:
    return PhaseEntry(
        phase_id="c0",
        sequence=3,
        artifacts=(
            ArtifactEntry(
                role="manifest",
                path="c0.json",
                sha256=manifest_sha256,
                schema_version="1939-v50-c0-followup-manifest-v1",
                required=True,
            ),
            ArtifactEntry(
                role="receipt",
                path="c0-receipt.json",
                sha256=receipt_sha256,
                schema_version="daa-evidence-phase-receipt-c0-v1",
                required=True,
            ),
        ),
        adapter_id="c0-followup-v1",
        adapter_sha256="c" * 64,
        projection_evidence="mechanically_bound",
        authorisation_evidence="contemporaneous_phase_package",
    )


def mechanically_bound_phase_b_phase(manifest_sha256: str, receipt_sha256: str) -> PhaseEntry:
    return PhaseEntry(
        phase_id="phase-b",
        sequence=2,
        artifacts=(
            ArtifactEntry(
                role="manifest",
                path="phase-b.json",
                sha256=manifest_sha256,
                schema_version="1939-v50-narrative-replacement-manifest-v2",
                required=True,
            ),
            ArtifactEntry(
                role="receipt",
                path="phase-b-receipt.json",
                sha256=receipt_sha256,
                schema_version="daa-evidence-phase-receipt-phase-b-v1",
                required=True,
            ),
        ),
        adapter_id="phase-b-v1",
        adapter_sha256="b" * 64,
        projection_evidence="mechanically_bound",
        authorisation_evidence="afterdocumented_authorisation_gap",
        database_target_identity_sha256=canonical_sha256(production_target_identity(), ""),
    )


def production_target_identity() -> dict:
    return {
        "schema_version": "daa-evidence-production-target-identity-v1",
        "environment": "production",
        "system_identifier_sha256": "e" * 64,
    }


def phase_b_identity_map() -> list[dict]:
    return [
        {
            "person_id": person_id,
            "record_key": f"record-{person_id}",
            "narrative_id": 1000 + person_id,
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


def sealed_ledger(phases: list[PhaseEntry], contributions: dict[str, dict] | None = None) -> dict:
    rows = []
    for phase in phases:
        row = {
            "phase_id": phase.phase_id,
            "sequence": phase.sequence,
            "artifacts": [
                {
                    "role": artifact.role,
                    "path": artifact.path,
                    "sha256": artifact.sha256,
                    "schema_version": artifact.schema_version,
                    "required": artifact.required,
                }
                for artifact in phase.artifacts
            ],
            "adapter_id": phase.adapter_id,
            "adapter_sha256": phase.adapter_sha256,
            "projection_evidence": phase.projection_evidence,
            "authorisation_evidence": phase.authorisation_evidence,
        }
        if phase.database_target_identity_sha256 is not None:
            row["database_target_identity_sha256"] = phase.database_target_identity_sha256
        if contributions is not None:
            row["contribution_sha256"] = contributions[phase.phase_id]["reconciliation_content_sha256"]
        rows.append(row)
    return seal_ledger({"schema_version": "daa-evidence-phase-artifact-ledger-v2", "phases": rows})


def final_snapshot(*contributions: dict) -> dict:
    state_keys = {
        "source_records": ("source_id", "record_key"),
        "source_anchors": ("source_id", "record_key", "occurrence_key"),
        "narrative_bindings": ("source_id", "record_key"),
        "narrative_sha256": ("narrative_id",),
        "persons": ("person_id",),
    }
    rows = {section: {} for section in state_keys}
    for contribution in contributions:
        for section, fields in state_keys.items():
            for withdrawal in contribution["withdrawals"][section]:
                rows[section].pop(tuple(withdrawal[field] for field in fields))
            for row in contribution[section]:
                rows[section][tuple(row[field] for field in fields)] = row
    return seal(
        {
            "schema_version": "daa-evidence-production-snapshot-v1",
            **{section: list(values.values()) for section, values in rows.items()},
        }
    )


def test_project_task25_uses_manifest_element_id_as_occurrence_key(tmp_path):
    manifest_sha256 = write_json(
        tmp_path / "task25.json",
        {
            "schema_version": "1939-v50-production-write-manifest-v1",
            "source": {"database_source_id": 3},
            "person_creates": [
                {"element_id": "element-1", "source_record_key": "record-1"}
            ],
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "task25-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-task25-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": production_target_identity(),
            "created_person_identities": [
                {
                    "element_id": "element-1",
                    "source_id": 3,
                    "record_key": "record-1",
                    "person_id": 1,
                }
            ],
        },
    )
    phase = mechanically_bound_task25_phase(manifest_sha256, receipt_sha256)
    contribution = project_phase(tmp_path, phase, bound_summary(phase))

    assert contribution["source_anchors"] == [
        {"source_id": 3, "record_key": "record-1", "occurrence_key": "element-1"}
    ]


def test_audit_marks_task25_mechanically_bound_only_with_the_receipt_identity_map(tmp_path):
    manifest_sha256 = write_json(
        tmp_path / "task25.json",
        {
            "schema_version": "1939-v50-production-write-manifest-v1",
            "source": {"database_source_id": 3},
            "person_creates": [{"element_id": "element-1", "source_record_key": "record-1"}],
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "task25-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-task25-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": production_target_identity(),
            "created_person_identities": [
                {"element_id": "element-1", "source_id": 3, "record_key": "record-1", "person_id": 1}
            ],
        },
    )
    phase = mechanically_bound_task25_phase(manifest_sha256, receipt_sha256)

    assert audit_bundle(tmp_path, [phase]).phase("task25").projection_evidence == "mechanically_bound"


def test_audit_marks_c0_mechanically_bound_only_with_the_receipt_after_values(tmp_path):
    manifest_sha256 = write_json(
        tmp_path / "c0.json",
        {
            "schema_version": "1939-v50-c0-followup-manifest-v1",
            "source": {"database_source_id": 3},
            "operations": [
                {"person_id": 1, "narrative_id": 7, "source_record_key": "record-1", "new_text_sha256": "d" * 64}
            ],
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "c0-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-c0-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": production_target_identity(),
            "change_set": 965,
            "narrative_results": [
                {"person_id": 1, "narrative_id": 7, "source_id": 3, "record_key": "record-1", "after_sha256": "d" * 64}
            ],
        },
    )
    phase = mechanically_bound_c0_phase(manifest_sha256, receipt_sha256)

    assert audit_bundle(tmp_path, [phase]).phase("c0").projection_evidence == "mechanically_bound"


def test_project_rejects_phase_b_without_the_required_551_row_bound_identity_map(tmp_path):
    phase = PhaseEntry(
        phase_id="phase-b",
        sequence=2,
        artifacts=(),
        adapter_id="phase-b-v1",
        adapter_sha256="b" * 64,
        projection_evidence="afterdocumented_unbound",
        authorisation_evidence="afterdocumented_authorisation_gap",
    )

    with pytest.raises(ProjectError, match="EVIDENCE_RECONCILIATION_INCOMPLETE"):
        project_phase(tmp_path, phase, unbound_summary(phase))


def test_project_phase_b_uses_the_bound_receipt_after_sha_and_binding_identity(tmp_path):
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
    phase = mechanically_bound_phase_b_phase(manifest_sha256, receipt_sha256)

    contribution = project_phase(tmp_path, phase, bound_summary(phase))

    assert contribution["narrative_sha256"][0] == {
        "narrative_id": 1001,
        "sha256": f"{552:064x}",
    }
    assert contribution["narrative_bindings"][0] == {
        "source_id": 3,
        "record_key": "record-1",
        "narrative_id": 1001,
    }


def test_project_c0_uses_the_receipt_after_sha_and_binding_identity(tmp_path):
    manifest_sha256 = write_json(
        tmp_path / "c0.json",
        {
            "schema_version": "1939-v50-c0-followup-manifest-v1",
            "source": {"database_source_id": 3},
            "operations": [
                {
                    "person_id": 1,
                    "narrative_id": 7,
                    "source_record_key": "record-1",
                    "new_text_sha256": "d" * 64,
                }
            ],
        },
    )
    receipt_sha256 = write_json(
        tmp_path / "c0-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-c0-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": {
                "schema_version": "daa-evidence-production-target-identity-v1",
                "environment": "production",
                "system_identifier_sha256": "e" * 64,
            },
            "change_set": 965,
            "narrative_results": [
                {
                    "person_id": 1,
                    "narrative_id": 7,
                    "source_id": 3,
                    "record_key": "record-1",
                    "after_sha256": "d" * 64,
                }
            ],
        },
    )
    phase = mechanically_bound_c0_phase(manifest_sha256, receipt_sha256)

    contribution = project_phase(tmp_path, phase, bound_summary(phase))

    assert contribution["narrative_sha256"] == [{"narrative_id": 7, "sha256": "d" * 64}]
    assert contribution["narrative_bindings"] == [
        {"source_id": 3, "record_key": "record-1", "narrative_id": 7}
    ]


def test_audited_projections_seal_into_a_second_ledger_and_reconcile_final_state(tmp_path):
    task25_manifest_sha256 = write_json(
        tmp_path / "task25.json",
        {
            "schema_version": "1939-v50-production-write-manifest-v1",
            "source": {"database_source_id": 3},
            "person_creates": [{"element_id": "element-1", "source_record_key": "record-1"}],
        },
    )
    task25_receipt_sha256 = write_json(
        tmp_path / "task25-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-task25-v1",
            "manifest_sha256": task25_manifest_sha256,
            "database_target_identity": production_target_identity(),
            "created_person_identities": [
                {"element_id": "element-1", "source_id": 3, "record_key": "record-1", "person_id": 1}
            ],
        },
    )
    phase_b_map = phase_b_identity_map()
    phase_b_manifest_sha256 = write_json(
        tmp_path / "phase-b.json",
        {"schema_version": "1939-v50-narrative-replacement-manifest-v2", "operations": phase_b_operations(phase_b_map)},
    )
    phase_b_receipt_sha256 = write_json(
        tmp_path / "phase-b-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-phase-b-v1",
            "manifest_sha256": phase_b_manifest_sha256,
            "database_target_identity": production_target_identity(),
            "identity_map": phase_b_map,
        },
    )
    c0_manifest_sha256 = write_json(
        tmp_path / "c0.json",
        {
            "schema_version": "1939-v50-c0-followup-manifest-v1",
            "source": {"database_source_id": 3},
            "operations": [
                {"person_id": 1, "narrative_id": 1001, "source_record_key": "record-1", "new_text_sha256": "d" * 64}
            ],
        },
    )
    c0_receipt_sha256 = write_json(
        tmp_path / "c0-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-c0-v1",
            "manifest_sha256": c0_manifest_sha256,
            "database_target_identity": production_target_identity(),
            "change_set": 965,
            "narrative_results": [
                {"person_id": 1, "narrative_id": 1001, "source_id": 3, "record_key": "record-1", "after_sha256": "d" * 64}
            ],
        },
    )
    phases = [
        mechanically_bound_task25_phase(task25_manifest_sha256, task25_receipt_sha256),
        mechanically_bound_phase_b_phase(phase_b_manifest_sha256, phase_b_receipt_sha256),
        mechanically_bound_c0_phase(c0_manifest_sha256, c0_receipt_sha256),
    ]
    audit_ledger = sealed_ledger(phases)
    audit_phases = validate_ledger(audit_ledger)
    summaries = audit_bundle(tmp_path, audit_phases)
    contributions = {
        phase.phase_id: project_phase(tmp_path, phase, summaries.phase(phase.phase_id))
        for phase in audit_phases
    }
    reconciliation_ledger = sealed_ledger(audit_phases, contributions)

    report = reconcile(final_snapshot(*contributions.values()), list(contributions.values()), reconciliation_ledger)

    assert report["status"] == "match"
    assert report["ledger_content_sha256"] == reconciliation_ledger["ledger_content_sha256"]
    assert contributions["c0"]["narrative_sha256"] == [{"narrative_id": 1001, "sha256": "d" * 64}]

    unbound = PhaseEntry(
        phase_id="unbound",
        sequence=4,
        artifacts=(
            ArtifactEntry("manifest", "unbound.json", "a" * 64, "synthetic-v1", True),
        ),
        adapter_id="unbound-v1",
        adapter_sha256="b" * 64,
        projection_evidence="afterdocumented_unbound",
        authorisation_evidence="afterdocumented_authorisation_gap",
    )
    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_INCOMPLETE") as caught:
        reconcile({}, [], sealed_ledger([unbound]))
    assert caught.value.report == {"status": "invalid", "error": "EVIDENCE_RECONCILIATION_INCOMPLETE"}
