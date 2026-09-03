from __future__ import annotations

import json
import hashlib
import os
import subprocess
from pathlib import Path

import pytest

from evidence_phase_artifact_ledger import CatalogArtifactEntry, CatalogPhaseEntry
from run_evidence_phase_artifact_audit_1939_v50 import CliError, _materialize_phase

SCRIPT = Path(__file__).with_name("run_evidence_phase_artifact_audit_1939_v50.py")


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
        "system_identifier_sha256": "e" * 64,
    }


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


def test_cli_writes_a_sealed_private_incomplete_audit_without_a_reconciliation_ledger(tmp_path):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    write_json(bundle / "synthetic-manifest.json", {"schema_version": "synthetic-manifest-v1"})
    catalog = bundle / "catalog.json"
    write_json(catalog, unbound_catalog())

    completed = run_cli(bundle, catalog, output)

    assert completed.returncode == 2
    assert json.loads(completed.stderr)["status"] == "incomplete"
    audit_ledger = json.loads((output / "audit-ledger.json").read_text(encoding="utf-8"))
    assert audit_ledger["ledger_content_sha256"]
    assert (output / "audit-summary.json").is_file()
    assert not (output / "reconciliation-ledger.json").exists()


def test_cli_hash_seals_bound_artifacts_and_private_outputs_without_terminal_leaks(tmp_path):
    bundle = tmp_path / "synthetic-bundle"
    bundle.mkdir()
    output = bundle / "private-output"
    output.mkdir()
    manifest_sha256 = write_json(
        bundle / "bound-manifest.json",
        {
            "schema_version": "1939-v50-production-write-manifest-v1",
            "source": {"database_source_id": 3},
            "person_creates": [{"element_id": "synthetic-element", "source_record_key": "terminal-secret"}],
        },
    )
    receipt_sha256 = write_json(
        bundle / "bound-receipt.json",
        {
            "schema_version": "daa-evidence-phase-receipt-task25-v1",
            "manifest_sha256": manifest_sha256,
            "database_target_identity": target_identity(),
            "created_person_identities": [
                {
                    "element_id": "synthetic-element",
                    "source_id": 3,
                    "record_key": "terminal-secret",
                    "person_id": 1,
                }
            ],
        },
    )
    catalog = bundle / "catalog.json"
    write_json(catalog, bound_task25_catalog(manifest_sha256, receipt_sha256))

    environment = {**os.environ, "PGHOST": "/definitely/no/database", "PGPORT": "1"}
    completed = run_cli(bundle, catalog, output, env=environment)

    assert completed.returncode == 0
    terminal = json.loads(completed.stdout)
    assert terminal["status"] == "complete"
    assert "terminal-secret" not in completed.stdout + completed.stderr
    assert str(bundle) not in completed.stdout + completed.stderr
    audit_ledger = json.loads((output / "audit-ledger.json").read_text(encoding="utf-8"))
    assert audit_ledger["phases"][0]["artifacts"][0]["sha256"] == manifest_sha256
    adapter_source = SCRIPT.with_name("project_evidence_phase_artifacts_1939_v50.py")
    assert audit_ledger["phases"][0]["adapter_sha256"] == hashlib.sha256(adapter_source.read_bytes()).hexdigest()
    contribution = json.loads((output / "1-synthetic-bound.contribution.json").read_text(encoding="utf-8"))
    assert contribution["source_manifest_sha256"] == manifest_sha256
    assert (output / "reconciliation-ledger.json").is_file()
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
    write_json(catalog, unbound_catalog())
    linked_catalog = bundle / "catalog-link.json"
    linked_catalog.symlink_to(catalog)

    catalog_result = run_cli(bundle, linked_catalog, output)

    assert catalog_result.returncode == 2
    assert json.loads(catalog_result.stderr)["error"] == "EVIDENCE_RECONCILIATION_CATALOG_PATH_INVALID"
    (bundle / "synthetic-manifest.json").symlink_to(bundle / "catalog.json")
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
    original = Path.read_bytes

    def fail_only_for_artifact(path: Path) -> bytes:
        if path == artifact:
            raise OSError("synthetic read race")
        return original(path)

    monkeypatch.setattr(Path, "read_bytes", fail_only_for_artifact)

    with pytest.raises(CliError, match="EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE"):
        _materialize_phase(phase, tmp_path)
