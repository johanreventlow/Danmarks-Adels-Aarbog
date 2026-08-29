"""Fail-closed, data-free auditor for retained 1939 phase artifacts."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from typing import Mapping

from evidence_phase_artifact_ledger import ArtifactEntry, PhaseEntry, RECEIPT_ADAPTERS, ReceiptAdapter


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


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE") from error
    return digest.hexdigest()


def resolve_artifact(bundle_root: Path, artifact: ArtifactEntry) -> Path:
    root = bundle_root.resolve()
    candidate = (root / artifact.path).resolve()
    if root not in candidate.parents:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID")
    if not candidate.exists():
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_MISSING")
    if not candidate.is_file():
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE")
    if sha256_file(candidate) != artifact.sha256:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_HASH_INVALID")
    return candidate


def _load_required_json(path: Path, artifact: ArtifactEntry) -> object:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID") from error
    if not isinstance(document, dict) or document.get("schema_version") != artifact.schema_version:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    return document


def _artifact_for_role(phase: PhaseEntry, role: str) -> ArtifactEntry | None:
    return next((artifact for artifact in phase.artifacts if artifact.role == role), None)


def _valid_sha256(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(
        character in "0123456789abcdef" for character in value
    )


def _valid_text(value: object) -> bool:
    return isinstance(value, str) and bool(value) and value.strip() == value


def _validate_phase_b_identity_map(value: object, adapter: ReceiptAdapter) -> None:
    if not isinstance(value, list) or not value:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    identities: set[tuple[object, ...]] = set()
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
        if not _valid_text(row["publication_status"]):
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        identity = tuple(row[field] for field in adapter.identity_fields)
        if identity in identities:
            raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
        identities.add(identity)


def _load_adapter_receipt(
    resolved: Mapping[str, Path], phase: PhaseEntry, adapter: ReceiptAdapter
) -> tuple[ArtifactEntry, dict[str, object]] | None:
    manifest = _artifact_for_role(phase, adapter.manifest_role)
    receipt = _artifact_for_role(phase, adapter.receipt_role)
    if manifest is None or receipt is None or receipt.role not in resolved:
        return None
    if (
        manifest.schema_version != adapter.manifest_schema_version
        or receipt.schema_version != adapter.receipt_schema_version
    ):
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    document = _load_required_json(resolved[adapter.receipt_role], receipt)
    if not isinstance(document, dict) or set(document) != {
        "schema_version",
        adapter.manifest_sha256_field,
        adapter.identity_map_field,
    }:
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    manifest_sha256 = document[adapter.manifest_sha256_field]
    if not _valid_sha256(manifest_sha256):
        raise AuditError("EVIDENCE_RECONCILIATION_ARTIFACT_SCHEMA_INVALID")
    _validate_phase_b_identity_map(document[adapter.identity_map_field], adapter)
    return manifest, document


def receipt_binds_manifest_and_identities(
    resolved: Mapping[str, Path], phase: PhaseEntry
) -> bool:
    adapter = RECEIPT_ADAPTERS.get(phase.adapter_id)
    if adapter is None:
        return False
    receipt = _load_adapter_receipt(resolved, phase, adapter)
    if receipt is None:
        return False
    manifest, document = receipt
    return document[adapter.manifest_sha256_field] == manifest.sha256


def audit_bundle(bundle_root: Path, ledger: list[PhaseEntry]) -> AuditResult:
    summaries: list[PhaseSummary] = []
    for phase in ledger:
        resolved = {
            artifact.role: resolve_artifact(bundle_root, artifact)
            for artifact in phase.artifacts
            if artifact.required
        }
        for artifact in phase.artifacts:
            if artifact.required:
                _load_required_json(resolved[artifact.role], artifact)
        if phase.phase_id == "d1":
            summaries.append(
                PhaseSummary(
                    phase.phase_id,
                    "unavailable",
                    "unavailable",
                    "EVIDENCE_RECONCILIATION_HISTORICAL_EXCEPTION_NO_MANIFEST",
                )
            )
        elif not receipt_binds_manifest_and_identities(resolved, phase):
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
