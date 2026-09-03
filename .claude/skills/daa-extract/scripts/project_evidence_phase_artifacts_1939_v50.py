"""Project hash-admitted historical artifacts into sealed reconciliation rows.

This module is deliberately read-only.  It accepts only a phase which the
artifact auditor already classified as mechanically bound and never opens a
database connection.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from audit_evidence_phase_artifacts_1939_v50 import PhaseSummary
from evidence_phase_artifact_ledger import (
    ArtifactEntry,
    LedgerError,
    PhaseEntry,
    TASK25_RECEIPT_ADAPTER,
    adapter_sha256,
    canonical_sha256,
    validate_phase_contract,
)
from reconcile_evidence_phase_gate import seal


class ProjectError(ValueError):
    """A stable, fail-closed historical-projection error."""


SECTIONS = (
    "source_records",
    "source_anchors",
    "narrative_bindings",
    "narrative_sha256",
    "persons",
)

def _require(condition: bool, token: str = "EVIDENCE_RECONCILIATION_INCOMPLETE") -> None:
    if not condition:
        raise ProjectError(token)


def _valid_text(value: object) -> bool:
    return isinstance(value, str) and bool(value) and value.strip() == value


def _valid_sha256(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(
        character in "0123456789abcdef" for character in value
    )


def _phase_target_matches(value: object, phase: PhaseEntry) -> bool:
    return (
        _production_target(value)
        and _valid_sha256(phase.database_target_identity_sha256)
        and canonical_sha256(value, "") == phase.database_target_identity_sha256
    )


def _artifact_by_role(phase: PhaseEntry, role: str) -> ArtifactEntry:
    matches = [artifact for artifact in phase.artifacts if artifact.role == role]
    _require(len(matches) == 1 and matches[0].required)
    return matches[0]


def _source_manifest_binding(manifest: ArtifactEntry) -> dict[str, str]:
    """Carry the ledger's canonical manifest identity into its contribution."""
    _require(_valid_text(manifest.path) and _valid_sha256(manifest.sha256))
    return {
        "source_manifest_path": manifest.path,
        "source_manifest_sha256": manifest.sha256,
    }


def _read_artifact(bundle_root: Path, artifact: ArtifactEntry) -> tuple[bytes, dict[str, object]]:
    _require(_valid_text(artifact.path) and "\x00" not in artifact.path)
    relative = Path(artifact.path)
    _require(not relative.is_absolute() and ".." not in relative.parts)
    try:
        root = bundle_root.resolve()
        path = (root / relative).resolve()
    except (OSError, RuntimeError, ValueError) as error:
        raise ProjectError("EVIDENCE_RECONCILIATION_INCOMPLETE") from error
    _require(root in path.parents and path.is_file())
    try:
        raw = path.read_bytes()
        document = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise ProjectError("EVIDENCE_RECONCILIATION_INCOMPLETE") from error
    _require(isinstance(document, dict))
    _require(hashlib.sha256(raw).hexdigest() == artifact.sha256)
    _require(document.get("schema_version") == artifact.schema_version)
    return raw, document


def _production_target(value: object) -> bool:
    return (
        isinstance(value, dict)
        and set(value) == {"schema_version", "environment", "system_identifier_sha256"}
        and value["schema_version"] == "daa-evidence-production-target-identity-v1"
        and value["environment"] == "production"
        and _valid_sha256(value["system_identifier_sha256"])
    )


def _unique(rows: list[dict[str, object]], fields: tuple[str, ...]) -> None:
    values: set[tuple[object, ...]] = set()
    for row in rows:
        identity = tuple(row[field] for field in fields)
        _require(identity not in values)
        values.add(identity)


def _task25_rows(
    manifest_raw: bytes, manifest: dict[str, object], receipt: dict[str, object], phase: PhaseEntry
) -> dict[str, list[dict[str, object]]]:
    _require(manifest.get("schema_version") == "1939-v50-production-write-manifest-v1")
    source = manifest.get("source")
    adapter = TASK25_RECEIPT_ADAPTER
    creates = manifest.get("person_creates")
    operations = manifest.get("operations")
    _require(isinstance(source, dict) and source.get("database_source_id") == 3)
    _require(isinstance(creates, list) and isinstance(operations, list))
    _require(
        set(receipt) == {
            "schema_version",
            "manifest_sha256",
            "database_target_identity",
            adapter.identity_map_field,
        }
        and receipt["schema_version"] == "daa-evidence-phase-receipt-task25-v1"
        and receipt["manifest_sha256"] == hashlib.sha256(manifest_raw).hexdigest()
        and _phase_target_matches(receipt["database_target_identity"], phase)
    )
    identities = receipt[adapter.identity_map_field]
    _require(isinstance(identities, list) and len(identities) == adapter.identity_count)
    expected: list[tuple[str, str, str]] = []
    expected_creates: list[tuple[str, str]] = []
    for create in creates:
        _require(isinstance(create, dict) and set(create) >= {"element_id", "source_record_key"})
        element_id = create["element_id"]
        record_key = create["source_record_key"]
        _require(_valid_text(element_id) and _valid_text(record_key))
        expected_creates.append((element_id, record_key))
    element_ids: set[str] = set()
    record_keys: set[str] = set()
    source_evidence_count = 0
    for operation in operations:
        _require(
            isinstance(operation, dict)
            and set(operation) >= {"element_id", "dependency_class", "source_record_key"}
        )
        element_id = operation["element_id"]
        dependency_class = operation["dependency_class"]
        record_key = operation["source_record_key"]
        _require(
            _valid_text(element_id)
            and _valid_text(record_key)
            and dependency_class in {"source_evidence", "person_create"}
            and element_id not in element_ids
            and record_key not in record_keys
        )
        element_ids.add(element_id)
        record_keys.add(record_key)
        expected.append((element_id, dependency_class, record_key))
        if dependency_class == "source_evidence":
            source_evidence_count += 1
    expected_create_operations = [
        (element_id, record_key)
        for element_id, dependency_class, record_key in expected
        if dependency_class == "person_create"
    ]
    _require(
        len(expected) == adapter.identity_count
        and source_evidence_count == 305
        and len(expected_create_operations) == 8
        and expected_creates == expected_create_operations
    )
    projected: list[dict[str, object]] = []
    people: set[int] = set()
    for identity, (element_id, dependency_class, record_key) in zip(identities, expected):
        _require(
            isinstance(identity, dict)
            and set(identity) == set(adapter.identity_fields)
            and _valid_text(identity["element_id"])
            and identity["source_id"] == 3
            and _valid_text(identity["record_key"])
            and identity["element_id"] == element_id
            and identity["record_key"] == record_key
        )
        if dependency_class == "source_evidence":
            _require(identity["person_id"] is None)
        else:
            _require(
                type(identity["person_id"]) is int
                and identity["person_id"] > 0
                and identity["person_id"] not in people
            )
            people.add(identity["person_id"])
        projected.append(identity)
    _require(len(people) == 8)
    return {
        "source_records": [
            {"source_id": 3, "record_key": row["record_key"]} for row in projected
        ],
        "source_anchors": [
            {
                "source_id": 3,
                "record_key": row["record_key"],
                "occurrence_key": row["element_id"],
            }
            for row in projected
        ],
        "narrative_bindings": [],
        "narrative_sha256": [],
        "persons": [{"person_id": row["person_id"]} for row in projected if row["person_id"] is not None],
    }


def _project_task25(bundle_root: Path, phase: PhaseEntry) -> dict[str, list[dict[str, object]]]:
    manifest_entry = _artifact_by_role(phase, "manifest")
    receipt_entry = _artifact_by_role(phase, "receipt")
    manifest_raw, manifest = _read_artifact(bundle_root, manifest_entry)
    _, receipt = _read_artifact(bundle_root, receipt_entry)
    return _task25_rows(manifest_raw, manifest, receipt, phase)


def _c0_rows(
    manifest_raw: bytes, manifest: dict[str, object], receipt: dict[str, object], phase: PhaseEntry
) -> dict[str, list[dict[str, object]]]:
    _require(manifest.get("schema_version") == "1939-v50-c0-followup-manifest-v1")
    source = manifest.get("source")
    operations = manifest.get("operations")
    database_identity = manifest.get("database_identity")
    _require(isinstance(source, dict) and source.get("database_source_id") == 3)
    _require(isinstance(database_identity, str) and bool(database_identity))
    _require(isinstance(operations, list) and len(operations) == 9)
    _require(
        set(receipt) == {
            "schema_version",
            "manifest_sha256",
            "database_target_identity",
            "change_set",
            "narrative_results",
        }
        and receipt["schema_version"] == "daa-evidence-phase-receipt-c0-v1"
        and receipt["manifest_sha256"] == hashlib.sha256(manifest_raw).hexdigest()
        and _phase_target_matches(receipt["database_target_identity"], phase)
        and receipt["database_target_identity"]["system_identifier_sha256"]
        == hashlib.sha256(database_identity.encode("utf-8")).hexdigest()
        and receipt["change_set"] == 965
    )
    expected: dict[tuple[int, int, str], str] = {}
    for operation in operations:
        _require(
            isinstance(operation, dict)
            and set(operation) >= {"person_id", "narrative_id", "source_record_key", "new_text_sha256"}
            and type(operation["person_id"]) is int
            and operation["person_id"] > 0
            and type(operation["narrative_id"]) is int
            and operation["narrative_id"] > 0
            and _valid_text(operation["source_record_key"])
            and _valid_sha256(operation["new_text_sha256"])
        )
        identity = (
            operation["person_id"],
            operation["narrative_id"],
            operation["source_record_key"],
        )
        _require(identity not in expected)
        expected[identity] = operation["new_text_sha256"]
    results = receipt["narrative_results"]
    _require(isinstance(results, list) and len(results) == 9 and len(results) == len(expected))
    projected: list[dict[str, object]] = []
    for result in results:
        _require(
            isinstance(result, dict)
            and set(result) == {"person_id", "narrative_id", "source_id", "record_key", "after_sha256"}
            and type(result["person_id"]) is int
            and result["person_id"] > 0
            and type(result["narrative_id"]) is int
            and result["narrative_id"] > 0
            and result["source_id"] == 3
            and _valid_text(result["record_key"])
            and _valid_sha256(result["after_sha256"])
        )
        identity = (result["person_id"], result["narrative_id"], result["record_key"])
        _require(identity in expected and expected[identity] == result["after_sha256"])
        projected.append(result)
    _require(
        {(row["person_id"], row["narrative_id"], row["record_key"]) for row in projected}
        == set(expected)
    )
    _unique(projected, ("person_id",))
    _unique(projected, ("narrative_id",))
    _unique(projected, ("record_key",))
    return {
        "source_records": [],
        "source_anchors": [],
        "narrative_bindings": [
            {
                "source_id": 3,
                "record_key": row["record_key"],
                "narrative_id": row["narrative_id"],
            }
            for row in projected
        ],
        "narrative_sha256": [
            {"narrative_id": row["narrative_id"], "sha256": row["after_sha256"]}
            for row in projected
        ],
        "persons": [],
    }


def _project_c0(bundle_root: Path, phase: PhaseEntry) -> dict[str, list[dict[str, object]]]:
    manifest_entry = _artifact_by_role(phase, "manifest")
    receipt_entry = _artifact_by_role(phase, "receipt")
    manifest_raw, manifest = _read_artifact(bundle_root, manifest_entry)
    _, receipt = _read_artifact(bundle_root, receipt_entry)
    return _c0_rows(manifest_raw, manifest, receipt, phase)


def _phase_b_rows(
    manifest_raw: bytes,
    manifest: dict[str, object],
    receipt: dict[str, object],
    phase: PhaseEntry,
) -> dict[str, list[dict[str, object]]]:
    _require(manifest.get("schema_version") == "1939-v50-narrative-replacement-manifest-v2")
    operations = manifest.get("operations")
    _require(isinstance(operations, list))
    _require(
        set(receipt) == {
            "schema_version",
            "manifest_sha256",
            "database_target_identity",
            "identity_map",
        }
        and receipt["schema_version"] == "daa-evidence-phase-receipt-phase-b-v1"
        and receipt["manifest_sha256"] == hashlib.sha256(manifest_raw).hexdigest()
        and _phase_target_matches(receipt["database_target_identity"], phase)
    )
    rows = receipt["identity_map"]
    _require(isinstance(rows, list) and len(rows) == 551 and len(operations) == 551)
    expected: set[tuple[object, object, object, object]] = set()
    for operation in operations:
        _require(isinstance(operation, dict))
        identity = (
            operation.get("person_id"),
            operation.get("source_record_key"),
            operation.get("expected_old_narrative_sha256"),
            operation.get("normalized_sha256"),
        )
        _require(
            type(identity[0]) is int
            and identity[0] > 0
            and _valid_text(identity[1])
            and _valid_sha256(identity[2])
            and _valid_sha256(identity[3])
            and identity not in expected
        )
        expected.add(identity)
    projected: list[dict[str, object]] = []
    for row in rows:
        _require(
            isinstance(row, dict)
            and set(row) == {
                "person_id",
                "record_key",
                "narrative_id",
                "before_sha256",
                "after_sha256",
                "publication_status",
            }
            and type(row["person_id"]) is int
            and row["person_id"] > 0
            and _valid_text(row["record_key"])
            and type(row["narrative_id"]) is int
            and row["narrative_id"] > 0
            and _valid_sha256(row["before_sha256"])
            and _valid_sha256(row["after_sha256"])
            and row["publication_status"] == "published"
            and (
                row["person_id"],
                row["record_key"],
                row["before_sha256"],
                row["after_sha256"],
            )
            in expected
        )
        projected.append(row)
    _unique(projected, ("person_id",))
    _unique(projected, ("record_key",))
    _unique(projected, ("narrative_id",))
    _require(len(projected) == len(expected))
    projected.sort(key=lambda row: row["person_id"])
    return {
        "source_records": [],
        "source_anchors": [],
        "narrative_bindings": [
            {
                "source_id": 3,
                "record_key": row["record_key"],
                "narrative_id": row["narrative_id"],
            }
            for row in projected
        ],
        "narrative_sha256": [
            {"narrative_id": row["narrative_id"], "sha256": row["after_sha256"]}
            for row in projected
        ],
        "persons": [{"person_id": row["person_id"]} for row in projected],
    }


def _project_phase_b(bundle_root: Path, phase: PhaseEntry) -> dict[str, list[dict[str, object]]]:
    manifest_entry = _artifact_by_role(phase, "manifest")
    receipt_entry = _artifact_by_role(phase, "receipt")
    manifest_raw, manifest = _read_artifact(bundle_root, manifest_entry)
    _, receipt = _read_artifact(bundle_root, receipt_entry)
    return _phase_b_rows(manifest_raw, manifest, receipt, phase)


def _phase_a_rows(
    manifest_raw: bytes, manifest: dict[str, object], receipt: dict[str, object], phase: PhaseEntry
) -> dict[str, list[dict[str, object]]]:
    _require(manifest.get("schema_version") == "1939-v50-phase-a-anchor-manifest-v1")
    source = manifest.get("source")
    operations = manifest.get("operations")
    _require(isinstance(source, dict) and source.get("database_source_id") == 3)
    _require(isinstance(operations, list) and len(operations) == 584)
    expected: set[tuple[str, str]] = set()
    for operation in operations:
        _require(isinstance(operation, dict))
        record_key = operation.get("source_record_key")
        occurrence_key = operation.get("element_id")
        _require(_valid_text(record_key) and _valid_text(occurrence_key))
        _require((record_key, occurrence_key) not in expected)
        expected.add((record_key, occurrence_key))
    _require(
        set(receipt) == {"schema_version", "manifest_sha256", "database_target_identity", "identity_map"}
        and receipt["schema_version"] == "daa-evidence-phase-receipt-phase-a-v1"
        and receipt["manifest_sha256"] == hashlib.sha256(manifest_raw).hexdigest()
        and _phase_target_matches(receipt["database_target_identity"], phase)
    )
    rows = receipt["identity_map"]
    _require(isinstance(rows, list) and len(rows) == 584)
    observed: set[tuple[str, str]] = set()
    projected: list[dict[str, object]] = []
    for row in rows:
        _require(
            isinstance(row, dict)
            and set(row) == {"record_key", "occurrence_key"}
            and _valid_text(row["record_key"])
            and _valid_text(row["occurrence_key"])
        )
        identity = (row["record_key"], row["occurrence_key"])
        _require(identity not in observed)
        observed.add(identity)
        projected.append(row)
    _require(observed == expected)
    return {
        "source_records": [{"source_id": 3, "record_key": row["record_key"]} for row in projected],
        "source_anchors": [
            {"source_id": 3, "record_key": row["record_key"], "occurrence_key": row["occurrence_key"]}
            for row in projected
        ],
        "narrative_bindings": [],
        "narrative_sha256": [],
        "persons": [],
    }


def _project_phase_a(bundle_root: Path, phase: PhaseEntry) -> dict[str, list[dict[str, object]]]:
    manifest_entry = _artifact_by_role(phase, "manifest")
    receipt_entry = _artifact_by_role(phase, "receipt")
    manifest_raw, manifest = _read_artifact(bundle_root, manifest_entry)
    _, receipt = _read_artifact(bundle_root, receipt_entry)
    return _phase_a_rows(manifest_raw, manifest, receipt, phase)


def _narrative_publication_rows(
    manifest_raw: bytes, manifest: dict[str, object], receipt: dict[str, object], phase: PhaseEntry
) -> dict[str, list[dict[str, object]]]:
    _require(manifest.get("schema_version") == "1939-v50-narrative-publication-manifest-v1")
    bindings = manifest.get("bindings")
    _require(isinstance(bindings, list) and len(bindings) == 8)
    expected: set[tuple[int, str, int, str]] = set()
    for binding in bindings:
        _require(isinstance(binding, dict))
        record_key = binding.get("record_key")
        narrative_id = binding.get("narrative_id")
        binding_id = binding.get("binding_id")
        _require(
            _valid_text(record_key)
            and type(narrative_id) is int
            and narrative_id > 0
            and _valid_text(binding_id)
        )
        identity = (3, record_key, narrative_id, binding_id)
        _require(identity not in expected)
        expected.add(identity)
    _require(
        set(receipt) == {"schema_version", "manifest_sha256", "database_target_identity", "identity_map"}
        and receipt["schema_version"] == "daa-evidence-phase-receipt-narrative-publication-v1"
        and receipt["manifest_sha256"] == hashlib.sha256(manifest_raw).hexdigest()
        and _phase_target_matches(receipt["database_target_identity"], phase)
    )
    rows = receipt["identity_map"]
    _require(isinstance(rows, list) and len(rows) == 8)
    observed: set[tuple[int, str, int, str]] = set()
    projected: list[dict[str, object]] = []
    for row in rows:
        _require(
            isinstance(row, dict)
            and set(row) == {"source_id", "record_key", "narrative_id", "binding_id"}
            and row["source_id"] == 3
            and _valid_text(row["record_key"])
            and type(row["narrative_id"]) is int
            and row["narrative_id"] > 0
            and _valid_text(row["binding_id"])
        )
        identity = (row["source_id"], row["record_key"], row["narrative_id"], row["binding_id"])
        _require(identity not in observed)
        observed.add(identity)
        projected.append(row)
    _require(observed == expected)
    return {
        "source_records": [],
        "source_anchors": [],
        "narrative_bindings": [
            {"source_id": row["source_id"], "record_key": row["record_key"], "narrative_id": row["narrative_id"]}
            for row in projected
        ],
        "narrative_sha256": [],
        "persons": [],
    }


def _project_narrative_publication(
    bundle_root: Path, phase: PhaseEntry
) -> dict[str, list[dict[str, object]]]:
    manifest_entry = _artifact_by_role(phase, "manifest")
    receipt_entry = _artifact_by_role(phase, "receipt")
    manifest_raw, manifest = _read_artifact(bundle_root, manifest_entry)
    _, receipt = _read_artifact(bundle_root, receipt_entry)
    return _narrative_publication_rows(manifest_raw, manifest, receipt, phase)


def _name_completion_rows(
    manifest_raw: bytes, manifest: dict[str, object], receipt: dict[str, object], phase: PhaseEntry
) -> dict[str, list[dict[str, object]]]:
    _require(manifest.get("schema_version") == "1939-v50-name-completion-manifest-v1")
    operations = manifest.get("operations")
    _require(isinstance(operations, list) and len(operations) == 8)
    expected_people: set[int] = set()
    for operation in operations:
        _require(isinstance(operation, dict) and type(operation.get("person_id")) is int)
        person_id = operation["person_id"]
        _require(person_id > 0 and person_id not in expected_people)
        expected_people.add(person_id)
    _require(
        set(receipt) == {
            "schema_version",
            "manifest_sha256",
            "database_target_identity",
            "completion_results",
        }
        and receipt["schema_version"] == "daa-evidence-phase-receipt-name-completion-v1"
        and receipt["manifest_sha256"] == hashlib.sha256(manifest_raw).hexdigest()
        and _phase_target_matches(receipt["database_target_identity"], phase)
    )
    results = receipt["completion_results"]
    _require(isinstance(results, list) and len(results) == 8)
    observed_people: set[int] = set()
    for result in results:
        _require(
            isinstance(result, dict)
            and set(result) == {"person_id", "fact_id", "assertion_id", "citation_id", "conclusion_id"}
            and all(type(result[field]) is int and result[field] > 0 for field in result)
        )
        _require(result["person_id"] not in observed_people)
        observed_people.add(result["person_id"])
    _require(observed_people == expected_people)
    return {section: [] for section in SECTIONS}


def _project_name_completion(
    bundle_root: Path, phase: PhaseEntry
) -> dict[str, list[dict[str, object]]]:
    manifest_entry = _artifact_by_role(phase, "manifest")
    receipt_entry = _artifact_by_role(phase, "receipt")
    manifest_raw, manifest = _read_artifact(bundle_root, manifest_entry)
    _, receipt = _read_artifact(bundle_root, receipt_entry)
    return _name_completion_rows(manifest_raw, manifest, receipt, phase)


def project_phase(bundle_root: Path, phase: PhaseEntry, summary: PhaseSummary) -> dict[str, object]:
    """Return one sealed five-projection contribution for an audited phase."""
    try:
        validate_phase_contract(phase)
    except LedgerError as error:
        raise ProjectError(str(error)) from error
    _require(phase.phase_id == summary.phase_id)
    _require(summary.projection_evidence == "mechanically_bound" and summary.error is None)
    _require(phase.projection_evidence == "mechanically_bound")
    _require(_valid_sha256(phase.adapter_sha256) and phase.adapter_sha256 == adapter_sha256())
    if phase.adapter_id == "task25-v1":
        sections = _project_task25(bundle_root, phase)
    elif phase.adapter_id == "c0-followup-v1":
        sections = _project_c0(bundle_root, phase)
    elif phase.adapter_id == "phase-b-v1":
        sections = _project_phase_b(bundle_root, phase)
    elif phase.adapter_id == "phase-a-v1":
        sections = _project_phase_a(bundle_root, phase)
    elif phase.adapter_id == "narrative-publication-v1":
        sections = _project_narrative_publication(bundle_root, phase)
    elif phase.adapter_id == "name-completion-v1":
        sections = _project_name_completion(bundle_root, phase)
    else:
        raise ProjectError("EVIDENCE_RECONCILIATION_INCOMPLETE")
    manifest = _artifact_by_role(phase, "manifest")
    contribution: dict[str, object] = {
        "schema_version": "daa-evidence-phase-reconciliation-manifest-v1",
        "phase_id": phase.phase_id,
        **_source_manifest_binding(manifest),
        **sections,
        "withdrawals": {section: [] for section in SECTIONS},
    }
    return seal(contribution)
