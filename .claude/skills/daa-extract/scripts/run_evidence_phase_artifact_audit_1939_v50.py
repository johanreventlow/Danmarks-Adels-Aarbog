#!/usr/bin/env python3
"""Create private, hash-sealed audit artifacts from a retained phase catalog.

This command is deliberately data-free at its terminal boundary: exact
artifact contents and projected rows stay in the ignored private output
directory.  It opens no database and performs no network access.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Mapping, Sequence

from audit_evidence_phase_artifacts_1939_v50 import AuditError, audit_bundle
from evidence_phase_artifact_ledger import (
    ArtifactEntry,
    CatalogPhaseEntry,
    LedgerError,
    PhaseEntry,
    seal_ledger,
    validate_catalog,
    validate_ledger,
)
from project_evidence_phase_artifacts_1939_v50 import ProjectError, adapter_sha256, project_phase


SUMMARY_SCHEMA = "daa-evidence-phase-artifact-audit-summary-v1"


class CliError(ValueError):
    """A stable, non-identifying CLI failure."""


class _Parser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise CliError("EVIDENCE_RECONCILIATION_ARGUMENTS_INVALID")


def _require(condition: bool, token: str) -> None:
    if not condition:
        raise CliError(token)


def _no_duplicate_object(pairs: list[tuple[object, object]]) -> dict[object, object]:
    result: dict[object, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _json_load(path: Path) -> object:
    try:
        return json.loads(path.read_bytes().decode("utf-8"), object_pairs_hook=_no_duplicate_object)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise CliError("EVIDENCE_RECONCILIATION_CATALOG_UNREADABLE") from error


def _path_inside_root(root: Path, value: Path, *, token: str) -> Path:
    try:
        _require(not root.is_symlink() and root.is_dir(), "EVIDENCE_RECONCILIATION_BUNDLE_ROOT_INVALID")
        raw = value.expanduser()
        candidate = raw if raw.is_absolute() else root / raw
        _require(".." not in raw.parts, token)
        relative = candidate.relative_to(root)
        _require(bool(relative.parts), token)
        current = root
        for part in relative.parts:
            current = current / part
            _require(not current.is_symlink(), token)
        return candidate
    except (OSError, RuntimeError, ValueError) as error:
        raise CliError(token) from error


def _require_existing_file(root: Path, value: Path, *, token: str) -> Path:
    candidate = _path_inside_root(root, value, token=token)
    _require(candidate.is_file(), token)
    return candidate


def _require_output_directory(root: Path, value: Path) -> Path:
    candidate = _path_inside_root(root, value, token="EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_INVALID")
    _require(candidate.is_dir(), "EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_INVALID")
    try:
        _require(not any(candidate.iterdir()), "EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_NOT_EMPTY")
    except OSError as error:
        raise CliError("EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_INVALID") from error
    return candidate


def _artifact_path(root: Path, relative_path: str) -> Path:
    return _require_existing_file(root, Path(relative_path), token="EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID")


def _artifact_sha256(root: Path, relative_path: str) -> str:
    try:
        return hashlib.sha256(_artifact_path(root, relative_path).read_bytes()).hexdigest()
    except CliError:
        raise
    except OSError as error:
        raise CliError("EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE") from error


def _materialize_phase(catalog_phase: CatalogPhaseEntry, root: Path) -> PhaseEntry:
    artifacts = tuple(
        ArtifactEntry(
            role=artifact.role,
            path=artifact.path,
            sha256=_artifact_sha256(root, artifact.path),
            schema_version=artifact.schema_version,
            required=artifact.required,
        )
        for artifact in catalog_phase.artifacts
    )
    return PhaseEntry(
        phase_id=catalog_phase.phase_id,
        sequence=catalog_phase.sequence,
        artifacts=artifacts,
        adapter_id=catalog_phase.adapter_id,
        adapter_sha256=adapter_sha256(),
        projection_evidence=catalog_phase.projection_evidence,
        authorisation_evidence=catalog_phase.authorisation_evidence,
        database_target_identity_sha256=catalog_phase.database_target_identity_sha256,
    )


def _phase_row(phase: PhaseEntry, *, projection_evidence: str, contribution_sha256: str | None = None) -> dict[str, object]:
    row: dict[str, object] = {
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
        "projection_evidence": projection_evidence,
        "authorisation_evidence": phase.authorisation_evidence,
    }
    if phase.database_target_identity_sha256 is not None:
        row["database_target_identity_sha256"] = phase.database_target_identity_sha256
    if contribution_sha256 is not None:
        row["contribution_sha256"] = contribution_sha256
    return row


def _private_write(path: Path, document: Mapping[str, object]) -> None:
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError as error:
        raise CliError("EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_EXISTS") from error
    except OSError as error:
        raise CliError("EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_UNWRITABLE") from error
    try:
        with os.fdopen(descriptor, "wb") as handle:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))
            handle.flush()
            os.fsync(handle.fileno())
    except OSError as error:
        raise CliError("EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_UNWRITABLE") from error


def _terminal(
    *, status: str, error: str | None, phase_ids: list[str] | None = None,
    evidence_states: list[dict[str, str | None]] | None = None,
    artifact_hashes: Mapping[str, object] | None = None, counts: Mapping[str, int] | None = None,
) -> dict[str, object]:
    result: dict[str, object] = {
        "status": status,
        "phase_ids": phase_ids or [],
        "evidence_states": evidence_states or [],
        "artifact_hashes": dict(artifact_hashes or {}),
        "counts": dict(counts or {}),
    }
    if error is not None:
        result["error"] = error
    return result


def _emit(result: Mapping[str, object], *, error: bool) -> None:
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")), file=sys.stderr if error else sys.stdout)


def _audit(bundle_root: Path, catalog_path: Path, output_dir: Path) -> tuple[dict[str, object], bool]:
    catalog = validate_catalog(_json_load(catalog_path))
    source_phases = [_materialize_phase(phase, bundle_root) for phase in catalog]
    summaries = audit_bundle(bundle_root, source_phases)
    observed = {summary.phase_id: summary for summary in summaries.summaries}
    audit_document = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                _phase_row(phase, projection_evidence=observed[phase.phase_id].projection_evidence)
                for phase in source_phases
            ],
        }
    )
    audited_phases = validate_ledger(
        audit_document, allow_missing_target_for_incomplete=True
    )
    _private_write(output_dir / "audit-ledger.json", audit_document)

    contributions: dict[str, dict[str, object]] = {}
    for phase in audited_phases:
        summary = observed[phase.phase_id]
        if summary.projection_evidence == "mechanically_bound" and summary.error is None:
            contribution = project_phase(bundle_root, phase, summary)
            contributions[phase.phase_id] = contribution
            _private_write(output_dir / f"{phase.sequence}-{phase.phase_id}.contribution.json", contribution)

    complete = len(contributions) == len(audited_phases)
    reconciliation_document: dict[str, object] | None = None
    if complete:
        reconciliation_document = seal_ledger(
            {
                "schema_version": "daa-evidence-phase-artifact-ledger-v2",
                "phases": [
                    _phase_row(
                        phase,
                        projection_evidence="mechanically_bound",
                        contribution_sha256=contributions[phase.phase_id]["reconciliation_content_sha256"],
                    )
                    for phase in audited_phases
                ],
            }
        )
        validate_ledger(reconciliation_document, require_contribution_hashes=True)
        _private_write(output_dir / "reconciliation-ledger.json", reconciliation_document)

    ordered_summaries = [observed[phase.phase_id] for phase in sorted(audited_phases, key=lambda item: item.sequence)]
    evidence_states = [
        {
            "phase_id": summary.phase_id,
            "projection_evidence": summary.projection_evidence,
            "authorisation_evidence": summary.authorisation_evidence,
            "error": summary.error,
        }
        for summary in ordered_summaries
    ]
    counts = {
        "phases": len(audited_phases),
        "mechanically_bound": len(contributions),
        "incomplete": len(audited_phases) - len(contributions),
    }
    hashes: dict[str, object] = {
        "audit_ledger_content_sha256": audit_document["ledger_content_sha256"],
        "contribution_sha256": {
            phase_id: contribution["reconciliation_content_sha256"]
            for phase_id, contribution in contributions.items()
        },
    }
    if reconciliation_document is not None:
        hashes["reconciliation_ledger_content_sha256"] = reconciliation_document["ledger_content_sha256"]
    status = "complete" if complete else "incomplete"
    summary_document = {
        "schema_version": SUMMARY_SCHEMA,
        **_terminal(
            status=status,
            error=None if complete else "EVIDENCE_RECONCILIATION_INCOMPLETE",
            phase_ids=[summary.phase_id for summary in ordered_summaries],
            evidence_states=evidence_states,
            artifact_hashes=hashes,
            counts=counts,
        ),
    }
    _private_write(output_dir / "audit-summary.json", summary_document)
    return summary_document, complete


def main(argv: Sequence[str] | None = None) -> int:
    parser = _Parser(add_help=False)
    parser.add_argument("--bundle-root", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--private-output-dir", type=Path, required=True)
    try:
        args = parser.parse_args(argv)
        root = args.bundle_root.expanduser()
        _require(not root.is_symlink() and root.is_dir(), "EVIDENCE_RECONCILIATION_BUNDLE_ROOT_INVALID")
        catalog_path = _require_existing_file(root, args.catalog, token="EVIDENCE_RECONCILIATION_CATALOG_PATH_INVALID")
        output_dir = _require_output_directory(root, args.private_output_dir)
        result, complete = _audit(root, catalog_path, output_dir)
        _emit(result, error=not complete)
        return 0 if complete else 2
    except (CliError, LedgerError, AuditError, ProjectError) as error:
        _emit(_terminal(status="invalid", error=str(error)), error=True)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
