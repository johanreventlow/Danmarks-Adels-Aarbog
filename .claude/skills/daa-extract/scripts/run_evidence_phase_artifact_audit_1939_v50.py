#!/usr/bin/env python3
"""Create private, hash-sealed audit artifacts from a retained phase catalog.

This command is deliberately data-free at its terminal boundary: exact
artifact contents and projected rows stay in the ignored private output
directory.  It opens no database and performs no network access.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import errno
import hashlib
import json
import os
import stat
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
    validate_historical_catalog,
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


def _json_load(raw: bytes) -> object:
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=_no_duplicate_object)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise CliError("EVIDENCE_RECONCILIATION_CATALOG_UNREADABLE") from error


_OPEN_DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def _relative_parts(value: Path, root_path: Path, *, token: str) -> tuple[str, ...]:
    try:
        raw = value.expanduser()
        _require(".." not in raw.parts, token)
        relative = raw.relative_to(root_path) if raw.is_absolute() else raw
        _require(bool(relative.parts) and relative != Path("."), token)
        return tuple(relative.parts)
    except (OSError, RuntimeError, ValueError) as error:
        raise CliError(token) from error


def _open_directory_component(parent_fd: int, component: str, *, token: str) -> int:
    descriptor: int | None = None
    try:
        descriptor = os.open(component, _OPEN_DIRECTORY_FLAGS, dir_fd=parent_fd)
        _require(stat.S_ISDIR(os.fstat(descriptor).st_mode), token)
        return descriptor
    except CliError:
        if descriptor is not None:
            os.close(descriptor)
        raise
    except OSError as error:
        if descriptor is not None:
            os.close(descriptor)
        raise CliError(token) from error


def _open_absolute_root(path: Path) -> int:
    raw = path.expanduser()
    if not raw.is_absolute():
        raw = Path.cwd() / raw
    _require(".." not in raw.parts, "EVIDENCE_RECONCILIATION_BUNDLE_ROOT_INVALID")
    try:
        descriptor = os.open("/", _OPEN_DIRECTORY_FLAGS)
    except OSError as error:
        raise CliError("EVIDENCE_RECONCILIATION_BUNDLE_ROOT_INVALID") from error
    try:
        for component in raw.parts[1:]:
            next_descriptor = _open_directory_component(
                descriptor, component, token="EVIDENCE_RECONCILIATION_BUNDLE_ROOT_INVALID"
            )
            os.close(descriptor)
            descriptor = next_descriptor
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


@dataclass
class _FdBundleRoot:
    descriptor: int

    def close(self) -> None:
        os.close(self.descriptor)

    def resolve(self) -> "_FdBundleRoot":
        return self

    def __truediv__(self, value: Path) -> "_FdPath":
        return _FdPath(self, tuple(value.parts))

    def _open_parent(self, parts: tuple[str, ...], *, token: str) -> tuple[int, str]:
        _require(bool(parts) and all(part not in ("", ".", "..") for part in parts), token)
        parent_fd = os.dup(self.descriptor)
        try:
            for component in parts[:-1]:
                next_descriptor = _open_directory_component(parent_fd, component, token=token)
                os.close(parent_fd)
                parent_fd = next_descriptor
            return parent_fd, parts[-1]
        except BaseException:
            os.close(parent_fd)
            raise

    def open_file(self, parts: tuple[str, ...], *, token: str) -> int:
        parent_fd, leaf = self._open_parent(parts, token=token)
        descriptor: int | None = None
        try:
            descriptor = os.open(leaf, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent_fd)
            _require(stat.S_ISREG(os.fstat(descriptor).st_mode), token)
            return descriptor
        except CliError:
            if descriptor is not None:
                os.close(descriptor)
            raise
        except OSError as error:
            if descriptor is not None:
                os.close(descriptor)
            if error.errno == errno.ELOOP and token.startswith("EVIDENCE_RECONCILIATION_ARTIFACT"):
                raise CliError("EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID") from error
            raise CliError(token) from error
        finally:
            os.close(parent_fd)

    def open_directory(self, parts: tuple[str, ...], *, token: str) -> int:
        parent_fd, leaf = self._open_parent(parts, token=token)
        try:
            return _open_directory_component(parent_fd, leaf, token=token)
        finally:
            os.close(parent_fd)

    def read_bytes(self, parts: tuple[str, ...], *, token: str) -> bytes:
        descriptor = self.open_file(parts, token=token)
        try:
            with os.fdopen(descriptor, "rb") as handle:
                return handle.read()
        except OSError as error:
            raise CliError(token) from error


@dataclass(frozen=True)
class _FdPath:
    root: _FdBundleRoot
    parts: tuple[str, ...]

    def resolve(self) -> "_FdPath":
        return self

    @property
    def parents(self) -> tuple[_FdBundleRoot, ...]:
        return (self.root,)

    def exists(self) -> bool:
        try:
            descriptor = self.root.open_file(
                self.parts, token="EVIDENCE_RECONCILIATION_ARTIFACT_PATH_INVALID"
            )
        except CliError:
            return False
        os.close(descriptor)
        return True

    def is_file(self) -> bool:
        return self.exists()

    def read_bytes(self) -> bytes:
        return self.root.read_bytes(
            self.parts, token="EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE"
        )


def _require_empty_output_directory(root: _FdBundleRoot, parts: tuple[str, ...]) -> int:
    descriptor = root.open_directory(parts, token="EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_INVALID")
    try:
        _require(not os.listdir(descriptor), "EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_NOT_EMPTY")
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _require_catalog_file(root: _FdBundleRoot, parts: tuple[str, ...]) -> None:
    descriptor = root.open_file(parts, token="EVIDENCE_RECONCILIATION_CATALOG_PATH_INVALID")
    os.close(descriptor)


def _artifact_sha256(root: _FdBundleRoot, relative_path: str) -> str:
    return hashlib.sha256(
        root.read_bytes(
            tuple(Path(relative_path).parts),
            token="EVIDENCE_RECONCILIATION_ARTIFACT_UNREADABLE",
        )
    ).hexdigest()


def _materialize_phase(catalog_phase: CatalogPhaseEntry, root: _FdBundleRoot) -> PhaseEntry:
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


def _private_write(output_fd: int, filename: str, document: Mapping[str, object]) -> None:
    try:
        descriptor = os.open(
            filename,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=output_fd,
        )
        _require(stat.S_ISREG(os.fstat(descriptor).st_mode), "EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_UNWRITABLE")
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


def _audit(
    bundle_root: _FdBundleRoot, catalog_parts: tuple[str, ...], output_fd: int
) -> tuple[dict[str, object], bool]:
    catalog = validate_historical_catalog(
        _json_load(
            bundle_root.read_bytes(
                catalog_parts, token="EVIDENCE_RECONCILIATION_CATALOG_UNREADABLE"
            )
        )
    )
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
    _private_write(output_fd, "audit-ledger.json", audit_document)

    contributions: dict[str, dict[str, object]] = {}
    for phase in audited_phases:
        summary = observed[phase.phase_id]
        if summary.projection_evidence == "mechanically_bound" and summary.error is None:
            contribution = project_phase(bundle_root, phase, summary)
            contributions[phase.phase_id] = contribution
            _private_write(output_fd, f"{phase.sequence}-{phase.phase_id}.contribution.json", contribution)

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
        _private_write(output_fd, "reconciliation-ledger.json", reconciliation_document)

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
    _private_write(output_fd, "audit-summary.json", summary_document)
    return _terminal(
        status=status,
        error=None if complete else "EVIDENCE_RECONCILIATION_INCOMPLETE",
        phase_ids=[summary.phase_id for summary in ordered_summaries],
        evidence_states=evidence_states,
        artifact_hashes=hashes,
        counts=counts,
    ), complete


def main(argv: Sequence[str] | None = None) -> int:
    parser = _Parser(add_help=False)
    parser.add_argument("--bundle-root", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--private-output-dir", type=Path, required=True)
    try:
        args = parser.parse_args(argv)
        root_path = args.bundle_root.expanduser()
        if not root_path.is_absolute():
            root_path = Path.cwd() / root_path
        root = _FdBundleRoot(_open_absolute_root(root_path))
        try:
            catalog_parts = _relative_parts(
                args.catalog, root_path, token="EVIDENCE_RECONCILIATION_CATALOG_PATH_INVALID"
            )
            output_parts = _relative_parts(
                args.private_output_dir,
                root_path,
                token="EVIDENCE_RECONCILIATION_PRIVATE_OUTPUT_INVALID",
            )
            _require_catalog_file(root, catalog_parts)
            output_fd = _require_empty_output_directory(root, output_parts)
            try:
                result, complete = _audit(root, catalog_parts, output_fd)
            finally:
                os.close(output_fd)
        finally:
            root.close()
        _emit(result, error=not complete)
        return 0 if complete else 2
    except (CliError, LedgerError, AuditError, ProjectError) as error:
        _emit(_terminal(status="invalid", error=str(error)), error=True)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
