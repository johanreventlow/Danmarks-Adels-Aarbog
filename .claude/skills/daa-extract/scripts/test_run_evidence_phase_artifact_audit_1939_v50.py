from __future__ import annotations

import json
import hashlib
import os
import subprocess
from dataclasses import replace
from pathlib import Path

import pytest

from audit_evidence_phase_artifacts_1939_v50 import AuditError, audit_bundle
from evidence_phase_artifact_ledger import (
    CatalogArtifactEntry,
    CatalogPhaseEntry,
    HISTORICAL_PHASE_AUTHORISATIONS,
    seal_ledger,
    validate_catalog,
    validate_ledger,
)
from project_evidence_phase_artifacts_1939_v50 import adapter_sha256, project_phase
from reconcile_evidence_phase_gate import ReconciliationError, _reconcile_capability, seal
from run_evidence_phase_artifact_audit_1939_v50 import (
    CliError,
    _FdBundleRoot,
    _materialize_phase,
    _open_absolute_root,
    main,
)

SCRIPT = Path(__file__).with_name("run_evidence_phase_artifact_audit_1939_v50.py")
RECONCILE_SCRIPT = Path(__file__).with_name("reconcile_evidence_phase_gate.py")
TERMINAL_KEYS = {
    "status",
    "error",
    "phase_ids",
    "evidence_states",
    "artifact_hashes",
    "counts",
}
COMPLETE_TERMINAL_KEYS = TERMINAL_KEYS - {"error"}


def write_json(path: Path, document: object) -> str:
    raw = json.dumps(document, sort_keys=True, separators=(",", ":")).encode("utf-8")
    path.write_bytes(raw)
    return hashlib.sha256(raw).hexdigest()


def unbound_catalog() -> dict:
    return {
        "schema_version": "daa-evidence-phase-artifact-catalog-v1",
        "phases": [
            {
                "phase_id": "synthetic-unbound",
                "sequence": 1,
                "adapter_id": "synthetic-unbound-v1",
                "projection_evidence": "afterdocumented_unbound",
                "authorisation_evidence": "afterdocumented_authorisation_gap",
                "artifacts": [
                    {
                        "role": "manifest",
                        "path": "synthetic-manifest.json",
                        "schema_version": "synthetic-manifest-v1",
                        "required": True,
                    }
                ],
            }
        ],
    }


def test_cli_rejects_a_partial_phase_inventory_before_artifact_admission(tmp_path):
    """Removing historical phases must fail before the CLI reads any artifact."""
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    catalog = bundle / "catalog.json"
    write_json(catalog, unbound_catalog())

    completed = run_cli(bundle, catalog, output)

    assert completed.returncode == 2
    assert json.loads(completed.stderr)["error"] == "EVIDENCE_RECONCILIATION_HISTORICAL_INVENTORY_INVALID"
    assert list(output.iterdir()) == []


@pytest.mark.parametrize(
    "mutate",
    [
        lambda phases: phases.pop(),
        lambda phases: phases.append({**phases[-1], "phase_id": "extra", "sequence": 8}),
        lambda phases: phases.__setitem__(1, {**phases[1], "phase_id": "phase-a-renamed"}),
        lambda phases: phases.__setitem__(1, {**phases[1], "sequence": 3}),
        lambda phases: phases.__setitem__(1, {**phases[1], "adapter_id": "phase-b-v1"}),
        lambda phases: phases.__setitem__(0, {**phases[0], "authorisation_evidence": "contemporaneous_phase_package"}),
        lambda phases: phases.__setitem__(6, {**phases[6], "projection_evidence": "afterdocumented_unbound"}),
    ],
)
def test_cli_rejects_every_historical_inventory_or_authorisation_bypass(tmp_path, mutate):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    document = _write_historical_catalog(bundle, bound_phase_ids=frozenset())
    mutate(document["phases"])
    catalog = bundle / "catalog.json"
    write_json(catalog, document)

    completed = run_cli(bundle, catalog, output)

    assert completed.returncode == 2
    assert json.loads(completed.stderr)["status"] == "invalid"
    assert list(output.iterdir()) == []


@pytest.mark.parametrize(
    ("phase_id", "override"),
    [
        ("task25", "contemporaneous_phase_package"),
        ("phase-a", "afterdocumented_authorisation_gap"),
        ("phase-b", "afterdocumented_authorisation_gap"),
        ("narrative-publication", "afterdocumented_authorisation_gap"),
        ("name-completion", "afterdocumented_authorisation_gap"),
        ("c0", "afterdocumented_authorisation_gap"),
        ("d1", "afterdocumented_authorisation_gap"),
    ],
)
def test_public_audit_cli_rejects_every_canonical_authorisation_override_before_artifact_work(
    tmp_path, phase_id, override
):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    document = _write_historical_catalog(bundle, bound_phase_ids=frozenset())
    phase = next(phase for phase in document["phases"] if phase["phase_id"] == phase_id)
    phase["authorisation_evidence"] = override
    catalog = bundle / "catalog.json"
    write_json(catalog, document)

    completed = run_cli(bundle, catalog, output)

    assert completed.returncode == 2
    assert json.loads(completed.stderr)["error"] == "EVIDENCE_RECONCILIATION_HISTORICAL_AUTHORISATION_INVALID"
    assert list(output.iterdir()) == []


def run_cli(
    bundle_root: Path, catalog: Path, output: Path, *, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "/usr/bin/python3",
            str(SCRIPT),
            "--bundle-root",
            str(bundle_root),
            "--catalog",
            str(catalog),
            "--private-output-dir",
            str(output),
        ],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )


def target_identity() -> dict:
    return {
        "schema_version": "daa-evidence-production-target-identity-v1",
        "environment": "production",
        "database_name": "synthetic_production",
        "system_identifier_sha256": hashlib.sha256(
            b"synthetic-capability-only-target"
        ).hexdigest(),
    }


def test_adapter_hash_changes_when_any_admission_component_changes(monkeypatch):
    """A sealed phase cannot silently substitute its ledger, audit, or projector code."""
    baseline = adapter_sha256()
    original_read_bytes = Path.read_bytes

    for filename in (
        "evidence_phase_artifact_ledger.py",
        "audit_evidence_phase_artifacts_1939_v50.py",
        "project_evidence_phase_artifacts_1939_v50.py",
    ):
        with monkeypatch.context() as patch:
            patch.setattr(
                Path,
                "read_bytes",
                lambda path, *, expected=filename: (
                    original_read_bytes(path) + b"\nsynthetic mutation\n"
                    if path.name == expected
                    else original_read_bytes(path)
                ),
            )
            assert adapter_sha256() != baseline


def canonical_hash(document: object) -> str:
    return hashlib.sha256(
        json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def bound_task25_catalog(manifest_sha256: str, receipt_sha256: str) -> dict:
    return {
        "schema_version": "daa-evidence-phase-artifact-catalog-v1",
        "phases": [
            {
                "phase_id": "synthetic-bound",
                "sequence": 1,
                "adapter_id": "task25-v1",
                "projection_evidence": "afterdocumented_unbound",
                "authorisation_evidence": "afterdocumented_authorisation_gap",
                "database_target_identity_sha256": canonical_hash(target_identity()),
                "artifacts": [
                    {
                        "role": "manifest",
                        "path": "bound-manifest.json",
                        "schema_version": "1939-v50-production-write-manifest-v1",
                        "required": True,
                    },
                    {
                        "role": "receipt",
                        "path": "bound-receipt.json",
                        "schema_version": "daa-evidence-phase-receipt-task25-v1",
                        "required": True,
                    },
                ],
            }
        ],
    }


def _catalog_phase(
    phase_id: str,
    sequence: int,
    adapter_id: str,
    manifest_path: str,
    manifest_schema: str,
    receipt_path: str | None = None,
    receipt_schema: str | None = None,
) -> dict:
    artifacts = [
        {
            "role": "manifest",
            "path": manifest_path,
            "schema_version": manifest_schema,
            "required": True,
        }
    ]
    if receipt_path is not None:
        assert receipt_schema is not None
        artifacts.append(
            {
                "role": "receipt",
                "path": receipt_path,
                "schema_version": receipt_schema,
                "required": True,
            }
        )
    return {
        "phase_id": phase_id,
        "sequence": sequence,
        "adapter_id": adapter_id,
        "projection_evidence": "afterdocumented_unbound",
        "authorisation_evidence": HISTORICAL_PHASE_AUTHORISATIONS.get(
            phase_id, "afterdocumented_authorisation_gap"
        ),
        "database_target_identity_sha256": canonical_hash(target_identity()),
        "artifacts": artifacts,
    }


def _write_historical_catalog(bundle: Path, *, bound_phase_ids: frozenset[str]) -> dict:
    del bound_phase_ids
    retained = [
        ("task25", 1, "task25-v1", "task25-manifest.json", "1939-v50-production-write-manifest-v1", "task25-apply.json", "afterdocumented_authorisation_gap"),
        ("phase-a", 2, "phase-a-v1", "phase-a-manifest.json", "1939-v50-phase-a-anchor-manifest-v1", "phase-a-apply.json", "contemporaneous_phase_package"),
        ("phase-b", 3, "phase-b-v1", "phase-b-manifest.json", "1939-v50-narrative-replacement-manifest-v1", "phase-b-apply.json", "contemporaneous_phase_package"),
        ("narrative-publication", 4, "narrative-publication-v1", "narrative-publication-manifest.json", "1939-v50-narrative-publication-manifest-v1", "narrative-publication-apply.json", "contemporaneous_phase_package"),
        ("name-completion", 5, "name-completion-v1", "name-completion-manifest.json", "1939-v50-name-completion-manifest-v1", "name-completion-apply.json", "contemporaneous_phase_package"),
    ]
    phases = []
    for phase_id, sequence, adapter_id, manifest_path, manifest_schema, apply_path, authorisation in retained:
        write_json(bundle / manifest_path, {"schema_version": manifest_schema})
        write_json(bundle / apply_path, {"retained": True})
        phases.append(
            {
                "phase_id": phase_id,
                "sequence": sequence,
                "adapter_id": adapter_id,
                "projection_evidence": "afterdocumented_unbound",
                "authorisation_evidence": authorisation,
                "artifacts": [
                    {"role": "manifest", "path": manifest_path, "schema_version": manifest_schema, "required": True},
                    {"role": "apply_record", "path": apply_path, "schema_version": None, "required": True},
                ],
            }
        )
    write_json(bundle / "c0-manifest.json", {"schema_version": "1939-v50-c0-followup-manifest-v1"})
    phases.append(
        {
            "phase_id": "c0",
            "sequence": 6,
            "adapter_id": "c0-followup-v1",
            "projection_evidence": "afterdocumented_unbound",
            "authorisation_evidence": "contemporaneous_phase_package",
            "artifacts": [
                {"role": "manifest", "path": "c0-manifest.json", "schema_version": "1939-v50-c0-followup-manifest-v1", "required": True}
            ],
        }
    )
    phases.append(
        {
            "phase_id": "d1",
            "sequence": 7,
            "adapter_id": "d1-historical-exception-v1",
            "projection_evidence": "unavailable",
            "authorisation_evidence": "unavailable",
            "artifacts": [],
        }
    )
    write_json(bundle / "c3-manifest.json", {"schema_version": "1939-v50-c3-apply-manifest-v1"})
    write_json(bundle / "c3-apply.json", {"retained": True})
    phases.append(
        {
            "phase_id": "c3",
            "sequence": 8,
            "adapter_id": "c3-apply-v1",
            "projection_evidence": "afterdocumented_unbound",
            "authorisation_evidence": "contemporaneous_phase_package",
            "artifacts": [
                {"role": "manifest", "path": "c3-manifest.json", "schema_version": "1939-v50-c3-apply-manifest-v1", "required": True},
                {"role": "apply_record", "path": "c3-apply.json", "schema_version": None, "required": True},
            ],
        }
    )
    return _synthetic_catalog(phases)


def _phase_a_identity_map() -> list[dict]:
    return [
        {"record_key": f"synthetic-a-record-{number}", "occurrence_key": f"synthetic-a-occurrence-{number}"}
        for number in range(1, 585)
    ]


def _phase_b_identity_map() -> list[dict]:
    return [
        {
            "person_id": 1000 + number,
            "record_key": f"synthetic-b-record-{number}",
            "narrative_id": 2000 + number,
            "before_sha256": f"{number:064x}",
            "after_sha256": f"{number + 551:064x}",
            "publication_status": "published",
        }
        for number in range(1, 552)
    ]


def _task25_operations() -> list[dict]:
    return [
        {
            "element_id": f"synthetic-source-evidence:{number}",
            "dependency_class": "source_evidence",
            "source_record_key": f"synthetic-source-record-{number if number <= 235 else number - 235}",
        }
        for number in range(1, 306)
    ] + [
        {
            "element_id": f"synthetic-person-create:{number}",
            "dependency_class": "person_create",
            "source_record_key": f"synthetic-person-record-{number}",
        }
        for number in range(1, 9)
    ]


def _task25_operation_identities(operations: list[dict]) -> list[dict]:
    return [
        {
            "element_id": operation["element_id"],
            "source_id": 3,
            "record_key": operation["source_record_key"],
            "person_id": None,
        }
        for operation in operations[:305]
    ] + [
        {
            "element_id": operation["element_id"],
            "source_id": 3,
            "record_key": operation["source_record_key"],
            "person_id": 9000 + number,
        }
        for number, operation in enumerate(operations[305:], start=1)
    ]


def _write_synthetic_supported_phase_artifacts(
    bundle: Path, *, bound_phase_ids: frozenset[str]
) -> list[dict]:
    """Return the six non-D1 phases of a wholly synthetic capability fixture."""
    target = target_identity()
    phases: list[dict] = []

    task25_operations = _task25_operations()
    task25_manifest = {
        "schema_version": "1939-v50-production-write-manifest-v1",
        "source": {"database_source_id": 3},
        "person_creates": [
            operation for operation in task25_operations if operation["dependency_class"] == "person_create"
        ],
        "operations": task25_operations,
    }
    task25_hash = write_json(bundle / "task25-manifest.json", task25_manifest)
    write_json(
            bundle / "task25-receipt.json",
            {
                "schema_version": "daa-evidence-phase-receipt-task25-v1",
                "manifest_sha256": task25_hash,
                "database_target_identity": target,
                "operation_identities": _task25_operation_identities(task25_operations),
            },
        )
    phases.append(_catalog_phase("task25", 1, "task25-v1", "task25-manifest.json", task25_manifest["schema_version"], "task25-receipt.json", "daa-evidence-phase-receipt-task25-v1"))

    phase_a_identities = _phase_a_identity_map()
    phase_a_manifest = {
        "schema_version": "1939-v50-phase-a-anchor-manifest-v1",
        "source": {"database_source_id": 3},
        "operations": [
            {"source_record_key": row["record_key"], "element_id": row["occurrence_key"]}
            for row in phase_a_identities
        ],
    }
    phase_a_hash = write_json(bundle / "phase-a-manifest.json", phase_a_manifest)
    write_json(bundle / "phase-a-receipt.json", {"schema_version": "daa-evidence-phase-receipt-phase-a-v1", **({"manifest_sha256": phase_a_hash, "database_target_identity": target, "identity_map": phase_a_identities} if "phase-a" in bound_phase_ids else {})})
    phases.append(_catalog_phase("phase-a", 2, "phase-a-v1", "phase-a-manifest.json", phase_a_manifest["schema_version"], *(("phase-a-receipt.json", "daa-evidence-phase-receipt-phase-a-v1") if "phase-a" in bound_phase_ids else ())))

    phase_b_identities = _phase_b_identity_map()
    phase_b_manifest = {
        "schema_version": "1939-v50-narrative-replacement-manifest-v2",
        "operations": [
            {"person_id": row["person_id"], "source_record_key": row["record_key"], "expected_old_narrative_sha256": row["before_sha256"], "normalized_sha256": row["after_sha256"]}
            for row in phase_b_identities
        ],
    }
    phase_b_hash = write_json(bundle / "phase-b-manifest.json", phase_b_manifest)
    write_json(bundle / "phase-b-receipt.json", {"schema_version": "daa-evidence-phase-receipt-phase-b-v1", **({"manifest_sha256": phase_b_hash, "database_target_identity": target, "identity_map": phase_b_identities} if "phase-b" in bound_phase_ids else {})})
    phases.append(_catalog_phase("phase-b", 3, "phase-b-v1", "phase-b-manifest.json", phase_b_manifest["schema_version"], *(("phase-b-receipt.json", "daa-evidence-phase-receipt-phase-b-v1") if "phase-b" in bound_phase_ids else ())))

    publication_identities = [
        {"source_id": 3, "record_key": f"synthetic-publication-record-{number}", "narrative_id": 3000 + number, "binding_id": f"synthetic-binding-{number}"}
        for number in range(1, 9)
    ]
    publication_manifest = {
        "schema_version": "1939-v50-narrative-publication-manifest-v1",
        "bindings": [{key: row[key] for key in ("record_key", "narrative_id", "binding_id")} for row in publication_identities],
    }
    publication_hash = write_json(bundle / "narrative-publication-manifest.json", publication_manifest)
    write_json(bundle / "narrative-publication-receipt.json", {"schema_version": "daa-evidence-phase-receipt-narrative-publication-v1", **({"manifest_sha256": publication_hash, "database_target_identity": target, "identity_map": publication_identities} if "narrative-publication" in bound_phase_ids else {})})
    phases.append(_catalog_phase("narrative-publication", 4, "narrative-publication-v1", "narrative-publication-manifest.json", publication_manifest["schema_version"], *(("narrative-publication-receipt.json", "daa-evidence-phase-receipt-narrative-publication-v1") if "narrative-publication" in bound_phase_ids else ())))

    completion_results = [
        {"person_id": 4000 + number, "fact_id": 5000 + number, "assertion_id": 6000 + number, "citation_id": 7000 + number, "conclusion_id": 8000 + number}
        for number in range(1, 9)
    ]
    completion_manifest = {
        "schema_version": "1939-v50-name-completion-manifest-v1",
        "operations": [{"person_id": row["person_id"]} for row in completion_results],
    }
    completion_hash = write_json(bundle / "name-completion-manifest.json", completion_manifest)
    write_json(bundle / "name-completion-receipt.json", {"schema_version": "daa-evidence-phase-receipt-name-completion-v1", **({"manifest_sha256": completion_hash, "database_target_identity": target, "completion_results": completion_results} if "name-completion" in bound_phase_ids else {})})
    phases.append(_catalog_phase("name-completion", 5, "name-completion-v1", "name-completion-manifest.json", completion_manifest["schema_version"], *(("name-completion-receipt.json", "daa-evidence-phase-receipt-name-completion-v1") if "name-completion" in bound_phase_ids else ())))

    c0_operations = [
        {"person_id": 10000 + number, "narrative_id": 11000 + number, "source_record_key": f"synthetic-c0-record-{number}", "new_text_sha256": f"{12000 + number:064x}"}
        for number in range(1, 10)
    ]
    c0_manifest = {
        "schema_version": "1939-v50-c0-followup-manifest-v1",
        "source": {"database_source_id": 3},
        "database_identity": "synthetic-capability-only-target",
        "operations": c0_operations,
    }
    c0_hash = write_json(bundle / "c0-manifest.json", c0_manifest)
    write_json(bundle / "c0-receipt.json", {"schema_version": "daa-evidence-phase-receipt-c0-v1", **({"manifest_sha256": c0_hash, "database_target_identity": target, "change_set": 965, "narrative_results": [{"person_id": row["person_id"], "narrative_id": row["narrative_id"], "source_id": 3, "record_key": row["source_record_key"], "after_sha256": row["new_text_sha256"]} for row in c0_operations]} if "c0" in bound_phase_ids else {})})
    phases.append(_catalog_phase("c0", 6, "c0-followup-v1", "c0-manifest.json", c0_manifest["schema_version"], *(("c0-receipt.json", "daa-evidence-phase-receipt-c0-v1") if "c0" in bound_phase_ids else ())))
    return phases


def _synthetic_catalog(phases: list[dict]) -> dict:
    return {"schema_version": "daa-evidence-phase-artifact-catalog-v1", "phases": phases}


def _synthetic_capability_only_catalog(phases: list[dict]) -> dict:
    """This fixture proves adapter capability only; it is not historical evidence."""
    return _synthetic_catalog(phases)


def _run_synthetic_capability_only_audit(bundle: Path, output: Path, monkeypatch) -> list[str]:
    """Use the real private audit path; only its fixed historical-inventory guard is synthetic here."""
    phases = _write_synthetic_supported_phase_artifacts(
        bundle,
        bound_phase_ids=frozenset(
            {"task25", "phase-a", "phase-b", "narrative-publication", "name-completion", "c0"}
        ),
    )
    write_json(bundle / "catalog.json", _synthetic_capability_only_catalog(phases))
    monkeypatch.setattr(
        "run_evidence_phase_artifact_audit_1939_v50.validate_historical_catalog", validate_catalog
    )
    assert main(
        ["--bundle-root", str(bundle), "--catalog", str(bundle / "catalog.json"), "--private-output-dir", str(output)]
    ) == 0
    return [
        f"{sequence}-{phase_id}.contribution.json"
        for sequence, phase_id in enumerate(
            ("task25", "phase-a", "phase-b", "narrative-publication", "name-completion", "c0"), start=1
        )
    ]


def _snapshot_from_contributions(contributions: list[dict]) -> dict:
    sections = ("source_records", "source_anchors", "narrative_bindings", "narrative_sha256", "persons")
    state_keys = {
        "source_records": ("source_id", "record_key"),
        "source_anchors": ("source_id", "record_key", "occurrence_key"),
        "narrative_bindings": ("source_id", "record_key"),
        "narrative_sha256": ("narrative_id",),
        "persons": ("person_id",),
    }
    snapshot = {
        "schema_version": "daa-evidence-production-snapshot-v1",
        "database_target_identity": target_identity(),
    }
    for section in sections:
        rows = {}
        for contribution in contributions:
            for row in contribution[section]:
                rows[tuple(row[field] for field in state_keys[section])] = row
        snapshot[section] = list(rows.values())
    return seal(snapshot)


def test_generated_capability_outputs_match_only_through_internal_reconciliation(tmp_path, monkeypatch, capsys):
    """The public audit CLI is historical and necessarily incomplete because D1 is unavailable."""
    bundle = tmp_path / "synthetic-capability-only"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    contribution_names = _run_synthetic_capability_only_audit(bundle, output, monkeypatch)
    audit_terminal = json.loads(capsys.readouterr().out)
    assert audit_terminal["status"] == "complete"
    assert set(audit_terminal) == COMPLETE_TERMINAL_KEYS
    contribution_paths = [output / name for name in contribution_names]
    contributions = [json.loads(path.read_text(encoding="utf-8")) for path in contribution_paths]
    snapshot = _snapshot_from_contributions(contributions)
    assert len(contributions[0]["source_records"]) == 243
    assert len(contributions[0]["source_anchors"]) == 313
    assert {row["person_id"] for row in contributions[-1]["persons"]} == set(range(10001, 10010))
    assert {row["person_id"] for row in contributions[-1]["persons"]}.isdisjoint(
        {row["person_id"] for row in contributions[2]["persons"]}
    )
    ledger = json.loads((output / "reconciliation-ledger.json").read_text(encoding="utf-8"))
    for phase in ledger["phases"]:
        manifest = next(artifact for artifact in phase["artifacts"] if artifact["role"] == "manifest")
        (bundle / manifest["path"]).unlink()

    assert _reconcile_capability(snapshot, contributions, ledger)["status"] == "match"


def test_public_cli_rejects_the_identical_six_phase_capability_catalog_before_output_processing(tmp_path, capsys):
    bundle = tmp_path / "synthetic-capability-only"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    phases = _write_synthetic_supported_phase_artifacts(
        bundle,
        bound_phase_ids=frozenset(
            {"task25", "phase-a", "phase-b", "narrative-publication", "name-completion", "c0"}
        ),
    )
    catalog = bundle / "catalog.json"
    write_json(catalog, _synthetic_capability_only_catalog(phases))

    assert main(["--bundle-root", str(bundle), "--catalog", str(catalog), "--private-output-dir", str(output)]) == 2

    assert json.loads(capsys.readouterr().err)["error"] == "EVIDENCE_RECONCILIATION_HISTORICAL_INVENTORY_INVALID"
    assert list(output.iterdir()) == []


def test_generated_capability_contribution_source_binding_mismatch_skips_snapshot_loading(tmp_path, monkeypatch):
    bundle = tmp_path / "synthetic-capability-only"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    contribution_names = _run_synthetic_capability_only_audit(bundle, output, monkeypatch)
    contribution = output / contribution_names[0]
    document = json.loads(contribution.read_text(encoding="utf-8"))
    document["source_manifest_path"] = "wrong-manifest.json"
    document = seal({key: value for key, value in document.items() if key != "reconciliation_content_sha256"})
    write_json(contribution, document)
    ledger_path = output / "reconciliation-ledger.json"
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    ledger["phases"][0]["contribution_sha256"] = document["reconciliation_content_sha256"]
    write_json(ledger_path, seal_ledger({key: value for key, value in ledger.items() if key != "ledger_content_sha256"}))
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    documents = [
        json.loads((output / name).read_text(encoding="utf-8"))
        for name in contribution_names
    ]
    with pytest.raises(ReconciliationError, match="EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_MISMATCH"):
        _reconcile_capability({"not": "a snapshot"}, documents, ledger)


def test_cli_writes_a_sealed_private_incomplete_audit_without_a_reconciliation_ledger(tmp_path):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    catalog = bundle / "catalog.json"
    write_json(catalog, _write_historical_catalog(bundle, bound_phase_ids=frozenset()))

    completed = run_cli(bundle, catalog, output)

    assert completed.returncode == 2
    terminal = json.loads(completed.stderr)
    assert terminal["status"] == "incomplete"
    assert set(terminal) == TERMINAL_KEYS
    audit_ledger = json.loads((output / "audit-ledger.json").read_text(encoding="utf-8"))
    assert audit_ledger["ledger_content_sha256"]
    assert (output / "audit-summary.json").is_file()
    assert not (output / "reconciliation-ledger.json").exists()


def test_cli_hash_seals_afterdocumented_artifacts_without_terminal_leaks(tmp_path):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    catalog = bundle / "catalog.json"
    write_json(catalog, _write_historical_catalog(
        bundle,
        bound_phase_ids=frozenset({"task25", "phase-a", "phase-b", "narrative-publication", "name-completion", "c0"}),
    ))

    environment = {**os.environ, "PGHOST": "/definitely/no/database", "PGPORT": "1"}
    completed = run_cli(bundle, catalog, output, env=environment)

    assert completed.returncode == 2
    terminal = json.loads(completed.stderr)
    assert terminal["status"] == "incomplete"
    assert set(terminal) == TERMINAL_KEYS
    assert "terminal-secret" not in completed.stdout + completed.stderr
    assert str(bundle) not in completed.stdout + completed.stderr
    audit_ledger = json.loads((output / "audit-ledger.json").read_text(encoding="utf-8"))
    assert audit_ledger["phases"][0]["artifacts"][0]["sha256"]
    assert audit_ledger["phases"][0]["adapter_sha256"] == adapter_sha256()
    assert not list(output.glob("*.contribution.json"))
    assert not (output / "reconciliation-ledger.json").exists()
    for private_file in output.iterdir():
        assert private_file.stat().st_mode & 0o777 == 0o600


def test_cli_rejects_a_catalog_artifact_path_escape_before_writing_outputs(tmp_path):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    catalog = bundle / "catalog.json"
    document = unbound_catalog()
    document["phases"][0]["artifacts"][0]["path"] = "../outside.json"
    write_json(catalog, document)

    completed = run_cli(bundle, catalog, output)

    assert completed.returncode == 2
    assert json.loads(completed.stderr)["error"] == "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID"
    assert list(output.iterdir()) == []


def test_cli_rejects_a_symlinked_catalog_and_artifact(tmp_path):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    catalog = bundle / "catalog.json"
    write_json(catalog, _write_historical_catalog(bundle, bound_phase_ids=frozenset()))
    linked_catalog = bundle / "catalog-link.json"
    linked_catalog.symlink_to(catalog)

    catalog_result = run_cli(bundle, linked_catalog, output)

    assert catalog_result.returncode == 2
    assert json.loads(catalog_result.stderr)["error"] == "EVIDENCE_RECONCILIATION_CATALOG_PATH_INVALID"
    (bundle / "task25-manifest.json").unlink()
    (bundle / "task25-manifest.json").symlink_to(bundle / "catalog.json")
    artifact_result = run_cli(bundle, catalog, output)

    assert artifact_result.returncode == 2
    assert json.loads(artifact_result.stderr)["error"] == "EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID"
    assert list(output.iterdir()) == []


def test_cli_preflight_preserves_an_existing_private_output_without_reading_catalog(tmp_path):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    sentinel = output / "audit-ledger.json"
    sentinel.write_text("do not overwrite", encoding="utf-8")
    catalog = bundle / "catalog.json"
    catalog.write_text("not-json", encoding="utf-8")

    completed = run_cli(bundle, catalog, output)

    assert completed.returncode == 2
    assert json.loads(completed.stderr)["error"] == "EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_NOT_EMPTY"
    assert sentinel.read_text(encoding="utf-8") == "do not overwrite"


def test_cli_reports_invalid_arguments_as_redacted_json():
    completed = subprocess.run(
        ["/usr/bin/python3", str(SCRIPT)], check=False, capture_output=True, text=True
    )

    assert completed.returncode == 2
    assert completed.stderr.startswith("{")
    assert str(SCRIPT) not in completed.stderr


def test_cli_error_terminal_uses_only_the_allowlisted_keys(capsys):
    assert main([]) == 2

    assert set(json.loads(capsys.readouterr().err)) == TERMINAL_KEYS


def test_cli_rejects_duplicate_catalog_keys_before_artifact_admission(tmp_path):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    write_json(bundle / "synthetic-manifest.json", {"schema_version": "synthetic-manifest-v1"})
    catalog = bundle / "catalog.json"
    catalog.write_text(
        '{"schema_version":"daa-evidence-phase-artifact-catalog-v1",'
        '"schema_version":"daa-evidence-phase-artifact-catalog-v1",'
        '"phases":[{"phase_id":"synthetic-unbound","sequence":1,'
        '"adapter_id":"synthetic-unbound-v1",'
        '"projection_evidence":"afterdocumented_unbound",'
        '"authorisation_evidence":"afterdocumented_authorisation_gap",'
        '"artifacts":[{"role":"manifest","path":"synthetic-manifest.json",'
        '"schema_version":"synthetic-manifest-v1","required":true}]}]}',
        encoding="utf-8",
    )

    completed = run_cli(bundle, catalog, output)

    assert completed.returncode == 2
    assert json.loads(completed.stderr)["error"] == "EVIDENCE_RECONCILIATION_CATALOG_UNREADABLE"
    assert list(output.iterdir()) == []


def test_cli_converts_an_artifact_read_race_to_a_stable_error(tmp_path, monkeypatch):
    artifact = tmp_path / "artifact.json"
    artifact.write_text("{}", encoding="utf-8")
    phase = CatalogPhaseEntry(
        phase_id="synthetic",
        sequence=1,
        artifacts=(CatalogArtifactEntry("manifest", artifact.name, "synthetic-v1", True),),
        adapter_id="synthetic-v1",
        projection_evidence="afterdocumented_unbound",
        authorisation_evidence="afterdocumented_authorisation_gap",
    )
    root = _FdBundleRoot(_open_absolute_root(tmp_path))
    original_open = os.open

    def fail_only_for_artifact(path, flags, mode=0o777, *, dir_fd=None):
        if path == artifact.name and dir_fd is not None:
            raise OSError("synthetic read race")
        return original_open(path, flags, mode, dir_fd=dir_fd)

    monkeypatch.setattr(os, "open", fail_only_for_artifact)
    try:
        with pytest.raises(CliError, match="EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE"):
            _materialize_phase(phase, root)
    finally:
        root.close()


def test_cli_reads_the_checked_artifact_ancestor_without_following_a_swap(tmp_path, monkeypatch, capsys):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    safe = bundle / "safe"
    safe.mkdir()
    external = tmp_path / "external"
    external.mkdir()
    document = _write_historical_catalog(bundle, bound_phase_ids=frozenset())
    (bundle / "task25-manifest.json").rename(safe / "task25-manifest.json")
    original_hash = hashlib.sha256((safe / "task25-manifest.json").read_bytes()).hexdigest()
    write_json(external / "synthetic-manifest.json", {"schema_version": "terminal-secret"})
    catalog = bundle / "catalog.json"
    document["phases"][0]["artifacts"][0]["path"] = "safe/task25-manifest.json"
    write_json(catalog, document)
    output = bundle / "private-output"
    output.mkdir()
    original_open = os.open
    original_read_bytes = Path.read_bytes

    def swap_after_open(path, flags, mode=0o777, *, dir_fd=None):
        descriptor = original_open(path, flags, mode, dir_fd=dir_fd)
        if path == "safe" and flags & os.O_DIRECTORY and dir_fd is not None:
            safe.rename(bundle / "safe-held")
            safe.symlink_to(external, target_is_directory=True)
        return descriptor

    monkeypatch.setattr(os, "open", swap_after_open)

    def reject_external_read(path: Path) -> bytes:
        if path == external / "task25-manifest.json":
            raise AssertionError("external artifact was read")
        return original_read_bytes(path)

    monkeypatch.setattr(Path, "read_bytes", reject_external_read)

    assert main(["--bundle-root", str(bundle), "--catalog", str(catalog), "--private-output-dir", str(output)]) == 2

    terminal = capsys.readouterr().err
    assert "terminal-secret" not in terminal
    assert json.loads(terminal)["error"] == "EVIDENCE_RECONCILIATION_ARTIFACT_MISSING"
    assert not (output / "audit-ledger.json").exists()
    assert hashlib.sha256((bundle / "safe-held" / "task25-manifest.json").read_bytes()).hexdigest() == original_hash


def test_cli_writes_through_the_checked_output_directory_fd_after_a_swap(tmp_path, monkeypatch, capsys):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    catalog = bundle / "catalog.json"
    write_json(catalog, _write_historical_catalog(
        bundle,
        bound_phase_ids=frozenset({"task25", "phase-a", "phase-b", "narrative-publication", "name-completion", "c0"}),
    ))
    output = bundle / "private-output"
    output.mkdir()
    external = tmp_path / "external-output"
    external.mkdir()
    original_open = os.open

    def swap_after_output_open(path, flags, mode=0o777, *, dir_fd=None):
        descriptor = original_open(path, flags, mode, dir_fd=dir_fd)
        if path == "private-output" and flags & os.O_DIRECTORY and dir_fd is not None:
            output.rename(bundle / "private-output-held")
            output.symlink_to(external, target_is_directory=True)
        return descriptor

    monkeypatch.setattr(os, "open", swap_after_output_open)

    assert main(["--bundle-root", str(bundle), "--catalog", str(catalog), "--private-output-dir", str(output)]) == 2

    capsys.readouterr()
    assert not (external / "audit-ledger.json").exists()
    assert (bundle / "private-output-held" / "audit-ledger.json").is_file()


def test_historical_shape_stops_before_snapshot_and_never_seals_a_reconciliation_ledger(
    tmp_path, monkeypatch, capsys
):
    """A missing receipt must keep the actual historical sequence visibly incomplete."""
    bundle = tmp_path / "synthetic-historical-shape"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    catalog = bundle / "catalog.json"
    write_json(catalog, _write_historical_catalog(
        bundle, bound_phase_ids=frozenset({"task25", "phase-b", "c0"})
    ))
    snapshot = bundle / "synthetic-production-snapshot.json"
    snapshot.write_text("must never be read", encoding="utf-8")
    reads: list[tuple[str, ...]] = []
    original_read_bytes = _FdBundleRoot.read_bytes

    def record_reads(self, parts, *, token):
        reads.append(parts)
        return original_read_bytes(self, parts, token=token)

    monkeypatch.setattr(_FdBundleRoot, "read_bytes", record_reads)

    assert main(["--bundle-root", str(bundle), "--catalog", str(catalog), "--private-output-dir", str(output)]) == 2

    terminal = json.loads(capsys.readouterr().err)
    assert terminal["status"] == "incomplete"
    assert terminal["error"] == "EVIDENCE_RECONCILIATION_INCOMPLETE"
    assert snapshot.name not in {part for read in reads for part in read}
    audit = json.loads((output / "audit-ledger.json").read_text(encoding="utf-8"))
    assert [phase["phase_id"] for phase in audit["phases"]] == [
        "task25",
        "phase-a",
        "phase-b",
        "narrative-publication",
        "name-completion",
        "c0",
        "d1",
        "c3",
    ]
    expected_evidence_states = [
        ("task25", "afterdocumented_unbound"),
        ("phase-a", "afterdocumented_unbound"),
        ("phase-b", "afterdocumented_unbound"),
        ("narrative-publication", "afterdocumented_unbound"),
        ("name-completion", "afterdocumented_unbound"),
        ("c0", "afterdocumented_unbound"),
        ("d1", "unavailable"),
        ("c3", "afterdocumented_unbound"),
    ]
    assert [(phase["phase_id"], phase["projection_evidence"]) for phase in terminal["evidence_states"]] == expected_evidence_states
    assert [(phase["phase_id"], phase["projection_evidence"]) for phase in audit["phases"]] == expected_evidence_states
    assert not (output / "reconciliation-ledger.json").exists()
    assert not list(output.glob("*.contribution.json"))


def test_synthetic_capability_only_fixture_seals_all_supported_contributions_but_excludes_d1(tmp_path):
    """The all-bound fixture exercises adapter mechanics, never historical authorisation."""
    bundle = tmp_path / "synthetic-capability-only"
    bundle.mkdir()
    phases = _write_synthetic_supported_phase_artifacts(
        bundle,
        bound_phase_ids=frozenset(
            {"task25", "phase-a", "phase-b", "narrative-publication", "name-completion", "c0"}
        ),
    )
    catalog = validate_catalog(_synthetic_capability_only_catalog(phases))
    root = _FdBundleRoot(_open_absolute_root(bundle))
    try:
        materialized = [_materialize_phase(phase, root) for phase in catalog]
    finally:
        root.close()
    summaries = audit_bundle(bundle, materialized).summaries
    admitted = [
        replace(phase, projection_evidence=summary.projection_evidence)
        for phase, summary in zip(materialized, summaries)
    ]
    contributions = [project_phase(bundle, phase, summary) for phase, summary in zip(admitted, summaries)]

    assert [phase.phase_id for phase in admitted] == [
        "task25",
        "phase-a",
        "phase-b",
        "narrative-publication",
        "name-completion",
        "c0",
    ]
    assert all(phase.projection_evidence == "mechanically_bound" for phase in admitted)
    assert len(contributions) == 6


def test_tampering_an_artifact_after_capability_ledger_sealing_fails_before_projection(tmp_path):
    """The second audit must reject changed bytes before it can write a contribution."""
    bundle = tmp_path / "synthetic-capability-only"
    bundle.mkdir()
    catalog = validate_catalog(_synthetic_capability_only_catalog(
        _write_synthetic_supported_phase_artifacts(
            bundle,
            bound_phase_ids=frozenset({"task25", "phase-a", "phase-b", "narrative-publication", "name-completion", "c0"}),
        )
    ))
    root = _FdBundleRoot(_open_absolute_root(bundle))
    try:
        materialized = [_materialize_phase(phase, root) for phase in catalog]
    finally:
        root.close()
    task25 = bundle / "task25-manifest.json"
    task25.write_text('{"schema_version":"1939-v50-production-write-manifest-v1","tampered":true}', encoding="utf-8")
    with pytest.raises(AuditError, match="EVIDENCE_RECONCILIATION_ARTIFACT_HASH_INVALID"):
        audit_bundle(bundle, materialized)
