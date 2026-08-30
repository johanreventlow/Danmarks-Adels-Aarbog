"""Fail-closed, data-free auditor for retained 1939 phase artifacts."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from typing import Mapping

from evidence_phase_artifact_ledger import (
    ArtifactEntry,
    PhaseEntry,
    RECEIPT_ADAPTERS,
    ReceiptAdapter,
    canonical_sha256,
)


class AuditError(ValueError):
    """A stable, fail-closed artifact-audit error."""


@dataclass(frozen=True)
class PhaseSummary:
    phase_id: str
    projection_evidence: str
    authorisation_evidence: str
    error: str | None


@dataclass(frozen=True)
class AuditResult:
    summaries: tuple[PhaseSummary, ...]

    def phase(self, phase_id: str) -> PhaseSummary:
        matches = [summary for summary in self.summaries if summary.phase_id == phase_id]
        if len(matches) != 1:
            raise AuditError("EVIDENCE_RECONCILIATION_PHASE_UNKNOWN")
        return matches[0]


@dataclass(frozen=True)
class _VerifiedArtifact:
    artifact: ArtifactEntry
    path: Path
    raw: bytes
    document: dict[str, object]


def _valid_sha256(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(
        character in "0123456789abcdef" for character in value
    )


def _valid_text(value: object) -> bool:
    return isinstance(value, str) and bool(value) and value.strip() == value


def _no_duplicate_object(pairs: list[tuple[object, object]]) -> dict[object, object]:
    document: dict[object, object] = {}
    for key, value in pairs:
        if key in document:
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        document[key] = value
    return document


def _parse_json(raw: bytes) -> dict[str, object]:
    try:
        document = json.loads(raw.decode("utf-8"), object_pairs_hook=_no_duplicate_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID") from error
    if not isinstance(document, dict):
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    return document


def _resolve_artifact_path(bundle_root: Path, artifact: ArtifactEntry) -> Path:
    if not isinstance(artifact.path, str) or "\x00" in artifact.path:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID")
    try:
        relative = Path(artifact.path)
        if not artifact.path or relative.is_absolute() or ".." in relative.parts:
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID")
        root = bundle_root.resolve()
        candidate = (root / relative).resolve()
    except AuditError:
        raise
    except (OSError, RuntimeError, ValueError) as error:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID") from error
    if root not in candidate.parents:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID")
    return candidate


def _read_artifact_bytes(bundle_root: Path, artifact: ArtifactEntry) -> tuple[Path, bytes]:
    candidate = _resolve_artifact_path(bundle_root, artifact)
    try:
        if not candidate.exists():
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_MISSING")
        if not candidate.is_file():
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE")
        raw = candidate.read_bytes()
    except AuditError:
        raise
    except FileNotFoundError as error:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_MISSING") from error
    except OSError as error:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE") from error
    if hashlib.sha256(raw).hexdigest() != artifact.sha256:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_HASH_INVALID")
    return candidate, raw


def sha256_file(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE") from error


def resolve_artifact(bundle_root: Path, artifact: ArtifactEntry) -> Path:
    return _read_artifact_bytes(bundle_root, artifact)[0]


def _verify_required_artifact(bundle_root: Path, artifact: ArtifactEntry) -> _VerifiedArtifact:
    path, raw = _read_artifact_bytes(bundle_root, artifact)
    document = _parse_json(raw)
    if document.get("schema_version") != artifact.schema_version:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    return _VerifiedArtifact(artifact, path, raw, document)


def _artifact_for_role(phase: PhaseEntry, role: str) -> ArtifactEntry | None:
    return next((artifact for artifact in phase.artifacts if artifact.role == role), None)


def _require_manifest(phase: PhaseEntry, adapter: ReceiptAdapter) -> ArtifactEntry:
    manifest = _artifact_for_role(phase, adapter.manifest_role)
    if manifest is None or not manifest.required:
        raise AuditError("EVIDENCE_RECONCILIATION_MANIFEST_REQUIRED")
    if manifest.schema_version != adapter.manifest_schema_version:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    return manifest


def _validate_phase_b_identity_map(value: object, adapter: ReceiptAdapter) -> list[dict[str, object]] | None:
    if not isinstance(value, list):
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    rows: list[dict[str, object]] = []
    unique_values: dict[str, set[object]] = {field: set() for field in adapter.identity_unique_fields}
    for row in value:
        if not isinstance(row, dict) or set(row) != set(adapter.identity_fields):
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        if type(row["person_id"]) is not int or row["person_id"] <= 0:
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        if type(row["narrative_id"]) is not int or row["narrative_id"] <= 0:
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        if not _valid_text(row["record_key"]):
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        if not _valid_sha256(row["before_sha256"]) or not _valid_sha256(row["after_sha256"]):
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        if not isinstance(row["publication_status"], str):
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        if row["publication_status"] not in adapter.publication_statuses:
            return None
        for field in adapter.identity_unique_fields:
            if row[field] in unique_values[field]:
                return None
            unique_values[field].add(row[field])
        rows.append(row)
    return rows if len(rows) == adapter.identity_count else None


def _phase_b_operations_match(manifest: dict[str, object], identity_map: list[dict[str, object]]) -> bool:
    operations = manifest.get("operations")
    if not isinstance(operations, list) or len(operations) != len(identity_map):
        return False
    expected: set[tuple[object, object, object, object]] = set()
    for operation in operations:
        if not isinstance(operation, dict):
            return False
        fields = (
            operation.get("person_id"),
            operation.get("source_record_key"),
            operation.get("expected_old_narrative_sha256"),
            operation.get("normalized_sha256"),
        )
        if (
            type(fields[0]) is not int
            or fields[0] <= 0
            or not _valid_text(fields[1])
            or not _valid_sha256(fields[2])
            or not _valid_sha256(fields[3])
            or fields in expected
        ):
            return False
        expected.add(fields)
    observed = {
        (row["person_id"], row["record_key"], row["before_sha256"], row["after_sha256"])
        for row in identity_map
    }
    return expected == observed


def _production_target_matches(value: object, phase: PhaseEntry) -> bool:
    if not isinstance(value, dict) or set(value) != {
        "schema_version",
        "environment",
        "system_identifier_sha256",
    }:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    if (
        value["schema_version"] != "daa-evidence-production-target-identity-v1"
        or not _valid_text(value["environment"])
        or not _valid_sha256(value["system_identifier_sha256"])
    ):
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    expected_hash = phase.database_target_identity_sha256
    if not _valid_sha256(expected_hash):
        raise AuditError("EVIDENCE_RECONCILIATION_DATABASE_TARGET_REQUIRED")
    return (
        value["environment"] == "production"
        and canonical_sha256(value, "") == expected_hash
    )


def _receipt_binds_verified_artifacts(
    verified: Mapping[str, _VerifiedArtifact], phase: PhaseEntry, adapter: ReceiptAdapter
) -> bool:
    manifest_entry = _require_manifest(phase, adapter)
    manifest = verified.get(adapter.manifest_role)
    receipt = verified.get(adapter.receipt_role)
    receipt_entry = _artifact_for_role(phase, adapter.receipt_role)
    if receipt_entry is None or not receipt_entry.required or receipt is None:
        return False
    if receipt_entry.schema_version != adapter.receipt_schema_version or manifest is None:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    if manifest.artifact != manifest_entry:
        raise AuditError("EVIDENCE_RECONCILIATION_MANIFEST_REQUIRED")
    expected_receipt_fields = {
        "schema_version",
        adapter.manifest_sha256_field,
        adapter.database_target_identity_field,
        adapter.identity_map_field,
    }
    if set(receipt.document) != expected_receipt_fields:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    if not _valid_sha256(receipt.document[adapter.manifest_sha256_field]):
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    target_matches = _production_target_matches(
        receipt.document[adapter.database_target_identity_field], phase
    )
    identity_map = _validate_phase_b_identity_map(receipt.document[adapter.identity_map_field], adapter)
    if identity_map is None:
        return False
    return (
        target_matches
        and receipt.document[adapter.manifest_sha256_field] == hashlib.sha256(manifest.raw).hexdigest()
        and _phase_b_operations_match(manifest.document, identity_map)
    )


def receipt_binds_manifest_and_identities(resolved: Mapping[str, Path], phase: PhaseEntry) -> bool:
    """Check one adapter receipt without returning private source values."""
    adapter = RECEIPT_ADAPTERS.get(phase.adapter_id)
    if adapter is None:
        return False
    manifest_entry = _require_manifest(phase, adapter)
    receipt_entry = _artifact_for_role(phase, adapter.receipt_role)
    if receipt_entry is None or not receipt_entry.required:
        return False
    if adapter.manifest_role not in resolved or adapter.receipt_role not in resolved:
        return False
    if receipt_entry.schema_version != adapter.receipt_schema_version:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    verified: dict[str, _VerifiedArtifact] = {}
    for artifact in (manifest_entry, receipt_entry):
        path = resolved[artifact.role]
        try:
            raw = path.read_bytes()
        except ValueError as error:
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID") from error
        except OSError as error:
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE") from error
        if hashlib.sha256(raw).hexdigest() != artifact.sha256:
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_HASH_INVALID")
        document = _parse_json(raw)
        if document.get("schema_version") != artifact.schema_version:
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        verified[artifact.role] = _VerifiedArtifact(artifact, path, raw, document)
    return _receipt_binds_verified_artifacts(verified, phase, adapter)


def audit_bundle(bundle_root: Path, ledger: list[PhaseEntry]) -> AuditResult:
    summaries: list[PhaseSummary] = []
    for phase in ledger:
        verified = {
            artifact.role: _verify_required_artifact(bundle_root, artifact)
            for artifact in phase.artifacts
            if artifact.required
        }
        if phase.phase_id == "d1":
            summaries.append(
                PhaseSummary(
                    phase.phase_id,
                    "unavailable",
                    "unavailable",
                    "EVIDENCE_RECONCILIATION_HISTORICAL_EXCEPTION_NO_MANIFEST",
                )
            )
            continue
        adapter = RECEIPT_ADAPTERS.get(phase.adapter_id)
        if adapter is None or not _receipt_binds_verified_artifacts(verified, phase, adapter):
            summaries.append(
                PhaseSummary(
                    phase.phase_id,
                    "afterdocumented_unbound",
                    phase.authorisation_evidence,
                    "EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND",
                )
            )
        else:
            summaries.append(
                PhaseSummary(
                    phase.phase_id,
                    "mechanically_bound",
                    phase.authorisation_evidence,
                    None,
                )
            )
    return AuditResult(tuple(summaries))
