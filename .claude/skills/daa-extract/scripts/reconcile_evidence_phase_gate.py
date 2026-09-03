#!/usr/bin/env python3
"""Compare a read-only production snapshot with hash-locked phase manifests.

The program never opens a database connection. A separate, explicitly approved
read-only SQL capture produces the production snapshot; this program verifies a
bounded, five-projection final state from an ordered set of listed phase
contributions. Reconciliation reports are written only to an explicitly named,
private output file. It is deliberately not a proof of the entire database
state or of historical manifest completeness.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Tuple

from evidence_phase_artifact_ledger import (
    LedgerError,
    PhaseEntry,
    validate_historical_reconciliation_ledger,
    validate_ledger,
)


MANIFEST_SCHEMA = "daa-evidence-phase-reconciliation-manifest-v1"
SNAPSHOT_SCHEMA = "daa-evidence-production-snapshot-v1"
SECTIONS = (
    "source_records",
    "source_anchors",
    "narrative_bindings",
    "narrative_sha256",
    "persons",
)
ROW_KEYS = {
    "source_records": ("source_id", "record_key"),
    "source_anchors": ("source_id", "record_key", "occurrence_key"),
    "narrative_bindings": ("source_id", "record_key", "narrative_id"),
    "narrative_sha256": ("narrative_id", "sha256"),
    "persons": ("person_id",),
}
STATE_KEYS = {
    "source_records": ("source_id", "record_key"),
    "source_anchors": ("source_id", "record_key", "occurrence_key"),
    "narrative_bindings": ("source_id", "record_key"),
    "narrative_sha256": ("narrative_id",),
    "persons": ("person_id",),
}


class ReconciliationError(ValueError):
    """A stable, fail-closed reconciliation error."""

    def __init__(self, token: str, report: Dict[str, Any] | None = None):
        super().__init__(token)
        self.report = report or {"status": "invalid", "error": token}


def _canonical_sha256(value: Mapping[str, Any], hash_field: str) -> str:
    payload = {key: item for key, item in value.items() if key != hash_field}
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _is_hex_sha256(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(char in "0123456789abcdef" for char in value)


def _require(condition: bool, token: str) -> None:
    if not condition:
        raise ReconciliationError(token)


def _validate_row(section: str, row: object) -> Dict[str, Any]:
    _require(isinstance(row, dict), "EVIDENCE_RECONCILIATION_ROW_INVALID")
    required = ROW_KEYS[section]
    _require(set(row) == set(required), "EVIDENCE_RECONCILIATION_ROW_KEYS_INVALID")
    result = dict(row)
    if "source_id" in result:
        _require(type(result["source_id"]) is int and result["source_id"] > 0, "EVIDENCE_RECONCILIATION_SOURCE_ID_INVALID")
    if "person_id" in result:
        _require(type(result["person_id"]) is int and result["person_id"] > 0, "EVIDENCE_RECONCILIATION_PERSON_ID_INVALID")
    if "narrative_id" in result:
        _require(type(result["narrative_id"]) is int and result["narrative_id"] > 0, "EVIDENCE_RECONCILIATION_NARRATIVE_ID_INVALID")
    for key in ("record_key", "occurrence_key"):
        if key in result:
            _require(isinstance(result[key], str) and result[key].strip() == result[key] and bool(result[key]), "EVIDENCE_RECONCILIATION_KEY_INVALID")
    if "sha256" in result:
        _require(_is_hex_sha256(result["sha256"]), "EVIDENCE_RECONCILIATION_SHA256_INVALID")
    return result


def _validate_sections(document: Mapping[str, Any]) -> Dict[str, List[Dict[str, Any]]]:
    result: Dict[str, List[Dict[str, Any]]] = {}
    for section in SECTIONS:
        rows = document.get(section)
        _require(isinstance(rows, list), "EVIDENCE_RECONCILIATION_SECTION_INVALID")
        result[section] = [_validate_row(section, row) for row in rows]
    return result


def _validate_withdrawal(section: str, row: object) -> Dict[str, Any]:
    _require(isinstance(row, dict), "EVIDENCE_RECONCILIATION_WITHDRAWAL_INVALID")
    required = STATE_KEYS[section]
    _require(set(row) == set(required), "EVIDENCE_RECONCILIATION_WITHDRAWAL_KEYS_INVALID")
    result = dict(row)
    if "source_id" in result:
        _require(type(result["source_id"]) is int and result["source_id"] > 0, "EVIDENCE_RECONCILIATION_SOURCE_ID_INVALID")
    if "person_id" in result:
        _require(type(result["person_id"]) is int and result["person_id"] > 0, "EVIDENCE_RECONCILIATION_PERSON_ID_INVALID")
    if "narrative_id" in result:
        _require(type(result["narrative_id"]) is int and result["narrative_id"] > 0, "EVIDENCE_RECONCILIATION_NARRATIVE_ID_INVALID")
    for key in ("record_key", "occurrence_key"):
        if key in result:
            _require(isinstance(result[key], str) and result[key].strip() == result[key] and bool(result[key]), "EVIDENCE_RECONCILIATION_KEY_INVALID")
    return result


def _validate_withdrawals(document: Mapping[str, Any]) -> Dict[str, List[Dict[str, Any]]]:
    raw = document.get("withdrawals")
    _require(isinstance(raw, dict) and set(raw) == set(SECTIONS), "EVIDENCE_RECONCILIATION_WITHDRAWALS_INVALID")
    result: Dict[str, List[Dict[str, Any]]] = {}
    for section in SECTIONS:
        rows = raw[section]
        _require(isinstance(rows, list), "EVIDENCE_RECONCILIATION_WITHDRAWALS_INVALID")
        result[section] = [_validate_withdrawal(section, row) for row in rows]
    return result


def _validate_manifest(document: object) -> Tuple[str, Dict[str, List[Dict[str, Any]]], Dict[str, List[Dict[str, Any]]]]:
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_MANIFEST_INVALID")
    _require(document.get("schema_version") == MANIFEST_SCHEMA, "EVIDENCE_RECONCILIATION_MANIFEST_SCHEMA_INVALID")
    _require(_is_hex_sha256(document.get("reconciliation_content_sha256")), "EVIDENCE_RECONCILIATION_MANIFEST_HASH_INVALID")
    _require(_canonical_sha256(document, "reconciliation_content_sha256") == document["reconciliation_content_sha256"], "EVIDENCE_RECONCILIATION_MANIFEST_HASH_INVALID")
    phase_id = document.get("phase_id")
    _require(isinstance(phase_id, str) and phase_id.strip() == phase_id and bool(phase_id), "EVIDENCE_RECONCILIATION_PHASE_ID_INVALID")
    _require(_is_hex_sha256(document.get("source_manifest_sha256")), "EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_HASH_INVALID")
    source_path = document.get("source_manifest_path")
    _require(isinstance(source_path, str) and bool(source_path), "EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_PATH_INVALID")
    path = Path(source_path)
    _require(not path.is_absolute() and ".." not in path.parts, "EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_PATH_INVALID")
    return phase_id, _validate_sections(document), _validate_withdrawals(document)


def _validate_database_target_identity(value: object) -> Dict[str, str]:
    _require(
        isinstance(value, dict)
        and set(value) == {"schema_version", "environment", "database_name", "system_identifier_sha256"}
        and value.get("schema_version") == "daa-evidence-production-target-identity-v1"
        and value.get("environment") == "production"
        and isinstance(value.get("database_name"), str)
        and bool(value["database_name"])
        and value["database_name"].strip() == value["database_name"]
        and _is_hex_sha256(value.get("system_identifier_sha256")),
        "EVIDENCE_RECONCILIATION_SNAPSHOT_TARGET_INVALID",
    )
    return dict(value)


def _validate_snapshot(
    document: object, *, expected_target_identity_sha256: str | None = None, require_target_identity: bool = True
) -> Dict[str, List[Dict[str, Any]]]:
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_SNAPSHOT_INVALID")
    _require(document.get("schema_version") == SNAPSHOT_SCHEMA, "EVIDENCE_RECONCILIATION_SNAPSHOT_SCHEMA_INVALID")
    _require(_is_hex_sha256(document.get("snapshot_content_sha256")), "EVIDENCE_RECONCILIATION_SNAPSHOT_HASH_INVALID")
    _require(_canonical_sha256(document, "snapshot_content_sha256") == document["snapshot_content_sha256"], "EVIDENCE_RECONCILIATION_SNAPSHOT_HASH_INVALID")
    target_identity = document.get("database_target_identity")
    if require_target_identity or target_identity is not None:
        target_identity = _validate_database_target_identity(target_identity)
    if expected_target_identity_sha256 is not None:
        _require(isinstance(target_identity, dict), "EVIDENCE_RECONCILIATION_SNAPSHOT_TARGET_INVALID")
        _require(
            _is_hex_sha256(expected_target_identity_sha256)
            and _canonical_sha256(target_identity, "") == expected_target_identity_sha256,
            "EVIDENCE_RECONCILIATION_SNAPSHOT_TARGET_MISMATCH",
        )
    return _validate_sections(document)


def seal(document: object) -> Dict[str, Any]:
    """Return a hash-locked copy of an unsealed phase manifest or snapshot."""
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_INPUT_INVALID")
    result = dict(document)
    schema = result.get("schema_version")
    if schema == SNAPSHOT_SCHEMA:
        hash_field = "snapshot_content_sha256"
    elif schema == MANIFEST_SCHEMA:
        hash_field = "reconciliation_content_sha256"
    else:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_SCHEMA_INVALID")
    _require(hash_field not in result, "EVIDENCE_RECONCILIATION_ALREADY_SEALED")
    result[hash_field] = _canonical_sha256(result, hash_field)
    if schema == SNAPSHOT_SCHEMA:
        _validate_snapshot(result, require_target_identity=False)
    else:
        _validate_manifest(result)
    return result


def _identity(section: str, row: Mapping[str, Any]) -> Tuple[Any, ...]:
    return tuple(row[key] for key in STATE_KEYS[section])


def _index(section: str, rows: Iterable[Dict[str, Any]], token: str) -> Dict[Tuple[Any, ...], Dict[str, Any]]:
    indexed: Dict[Tuple[Any, ...], Dict[str, Any]] = {}
    for row in rows:
        identity = _identity(section, row)
        if identity in indexed:
            raise ReconciliationError(token)
        indexed[identity] = row
    return indexed


def _validate_ledger_admission(ledger: object) -> list[PhaseEntry]:
    try:
        return validate_historical_reconciliation_ledger(ledger)
    except LedgerError as error:
        raise ReconciliationError(str(error)) from error


def _validate_capability_ledger_admission(ledger: object) -> list[PhaseEntry]:
    """Validate synthetic adapter mechanics without exposing a public bypass."""
    try:
        return validate_ledger(ledger, require_contribution_hashes=True)
    except LedgerError as error:
        raise ReconciliationError(str(error)) from error


def _validate_contribution_admission(
    manifests: Iterable[object], ledger: object, *, capability_only: bool = False
) -> Tuple[
    list[PhaseEntry],
    Dict[str, Tuple[Dict[str, List[Dict[str, Any]]], Dict[str, List[Dict[str, Any]]]]],
]:
    approved = (
        _validate_capability_ledger_admission(ledger)
        if capability_only
        else _validate_ledger_admission(ledger)
    )
    if not capability_only:
        _require(
            all(
                entry.projection_evidence == "mechanically_bound"
                and entry.contribution_sha256 is not None
                for entry in approved
            ),
            "EVIDENCE_RECONCILIATION_INCOMPLETE",
        )
    documents = list(manifests)
    phase_ids: List[str] = []
    manifest_hashes: Dict[str, str] = {}
    contributions: Dict[str, Tuple[Dict[str, List[Dict[str, Any]]], Dict[str, List[Dict[str, Any]]]]] = {}
    for manifest in documents:
        phase_id, sections, withdrawals = _validate_manifest(manifest)
        if phase_id in phase_ids:
            raise ReconciliationError("EVIDENCE_RECONCILIATION_DUPLICATE_PHASE")
        phase_ids.append(phase_id)
        assert isinstance(manifest, dict)  # narrowed by _validate_manifest
        manifest_hashes[phase_id] = manifest["reconciliation_content_sha256"]
        contributions[phase_id] = (sections, withdrawals)
    _require(bool(phase_ids), "EVIDENCE_RECONCILIATION_MANIFESTS_REQUIRED")
    approved_hashes = {entry.phase_id: entry.contribution_sha256 for entry in approved}
    if manifest_hashes != approved_hashes:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_LEDGER_MISMATCH")
    approved_by_phase = {entry.phase_id: entry for entry in approved}
    for phase_id, manifest in zip(phase_ids, documents):
        assert isinstance(manifest, dict)  # narrowed by _validate_manifest
        source_manifests = [
            artifact for artifact in approved_by_phase[phase_id].artifacts if artifact.role == "manifest"
        ]
        if len(source_manifests) != 1:
            raise ReconciliationError("EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_MISMATCH")
        source_manifest = source_manifests[0]
        if (
            manifest["source_manifest_path"] != source_manifest.path
            or manifest["source_manifest_sha256"] != source_manifest.sha256
        ):
            raise ReconciliationError("EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_MISMATCH")
    return approved, contributions


def _common_database_target_identity_sha256(approved: Iterable[PhaseEntry]) -> str | None:
    """Return the one sealed target for a target-bound admission set."""
    bound = [entry for entry in approved if entry.projection_evidence == "mechanically_bound"]
    hashes = {entry.database_target_identity_sha256 for entry in bound}
    if hashes == {None}:
        return None
    _require(
        len(hashes) == 1 and all(_is_hex_sha256(value) for value in hashes),
        "EVIDENCE_RECONCILIATION_DATABASE_TARGET_MISMATCH",
    )
    value = next(iter(hashes))
    assert isinstance(value, str)
    return value


def _reconcile_admitted(
    snapshot: object,
    approved: list[PhaseEntry],
    contributions: Dict[str, Tuple[Dict[str, List[Dict[str, Any]]], Dict[str, List[Dict[str, Any]]]]],
    ledger: object,
    *,
    require_target_identity: bool = True,
) -> Dict[str, Any]:
    actual = _validate_snapshot(
        snapshot,
        expected_target_identity_sha256=(
            _common_database_target_identity_sha256(approved)
            if require_target_identity
            else None
        ),
        require_target_identity=require_target_identity,
    )

    expected_rows: Dict[str, Dict[Tuple[Any, ...], Dict[str, Any]]] = {section: {} for section in SECTIONS}
    overrides: Dict[str, int] = {section: 0 for section in SECTIONS}
    withdrawal_counts: Dict[str, int] = {section: 0 for section in SECTIONS}
    for entry in sorted(approved, key=lambda item: item.sequence):
        phase_id = entry.phase_id
        for section in SECTIONS:
            phase_sections, phase_withdrawals = contributions[phase_id]
            contribution_rows = _index(
                section,
                phase_sections[section],
                "EVIDENCE_RECONCILIATION_CONTRIBUTION_DUPLICATE",
            )
            withdrawal_rows = _index(
                section,
                phase_withdrawals[section],
                "EVIDENCE_RECONCILIATION_WITHDRAWAL_DUPLICATE",
            )
            if set(contribution_rows) & set(withdrawal_rows):
                raise ReconciliationError("EVIDENCE_RECONCILIATION_WITHDRAWAL_CONFLICT")
            for identity in withdrawal_rows:
                if identity not in expected_rows[section]:
                    raise ReconciliationError("EVIDENCE_RECONCILIATION_WITHDRAWAL_MISSING")
                del expected_rows[section][identity]
                withdrawal_counts[section] += 1
            for identity, row in contribution_rows.items():
                if identity in expected_rows[section] and expected_rows[section][identity] != row:
                    overrides[section] += 1
                expected_rows[section][identity] = row

    differences: Dict[str, Dict[str, List[Dict[str, Any]]]] = {}
    counts: Dict[str, int] = {}
    for section in SECTIONS:
        expected = expected_rows[section]
        observed = _index(section, actual[section], "EVIDENCE_RECONCILIATION_SNAPSHOT_DUPLICATE")
        counts[section] = len(expected)
        missing = [
            expected[key]
            for key in sorted(expected)
            if key not in observed or expected[key] != observed[key]
        ]
        unexpected = [
            observed[key]
            for key in sorted(observed)
            if key not in expected or observed[key] != expected[key]
        ]
        if missing or unexpected:
            differences[section] = {"missing": missing, "unexpected": unexpected}

    report = {
        "status": "match" if not differences else "drift",
        "scope": "five-projection-final-state-v1",
        "phase_ids": [entry.phase_id for entry in sorted(approved, key=lambda item: item.sequence)],
        "ledger_content_sha256": ledger["ledger_content_sha256"],
        "artifact_hashes": {
            "ledger_content_sha256": ledger["ledger_content_sha256"],
            "contribution_sha256": {
                entry.phase_id: entry.contribution_sha256
                for entry in sorted(approved, key=lambda item: item.sequence)
            },
        },
        "counts": counts,
        "overrides": overrides,
        "withdrawals": withdrawal_counts,
        "differences": differences,
    }
    if differences:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_DRIFT", report)
    return report


def reconcile(snapshot: object, manifests: Iterable[object], ledger: object) -> Dict[str, Any]:
    """Return a public historical reconciliation report or fail closed."""
    approved, contributions = _validate_contribution_admission(manifests, ledger)
    return _reconcile_admitted(snapshot, approved, contributions, ledger)


def _reconcile_capability(snapshot: object, manifests: Iterable[object], ledger: object) -> Dict[str, Any]:
    """Exercise adapter projection mechanics below the public historical gate."""
    approved, contributions = _validate_contribution_admission(manifests, ledger, capability_only=True)
    return _reconcile_admitted(
        snapshot, approved, contributions, ledger, require_target_identity=False
    )


def _load_json(path: Path) -> object:
    def reject_duplicate_keys(pairs: List[Tuple[str, object]]) -> Dict[str, object]:
        result: Dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result

    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys)
    except (OSError, UnicodeDecodeError, ValueError, json.JSONDecodeError) as error:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_INPUT_UNREADABLE") from error


def load_phase_manifest(path: Path) -> Dict[str, Any]:
    """Load one sealed contribution without reopening its original manifest."""
    document = _load_json(path)
    _validate_manifest(document)
    assert isinstance(document, dict)  # narrowed by _validate_manifest
    return document


def _terminal_summary(report: Mapping[str, Any], error: str | None = None) -> Dict[str, Any]:
    """Return the deliberately non-identifying CLI result."""
    result: Dict[str, Any] = {
        "status": report.get("status", "invalid"),
        "phase_ids": report.get("phase_ids", []),
        "counts": report.get("counts", {}),
        "artifact_hashes": report.get("artifact_hashes", {}),
    }
    if error is not None:
        result["error"] = error
    return result


def _print_terminal_summary(report: Mapping[str, Any], error: str | None = None) -> None:
    print(json.dumps(_terminal_summary(report, error), ensure_ascii=False, sort_keys=True), file=sys.stderr if error else sys.stdout)


def _create_private_report(path: Path) -> int:
    descriptor: int | None = None
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.fchmod(descriptor, 0o600)
        return descriptor
    except FileExistsError as error:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_PRIVATE_REPORT_EXISTS") from error
    except OSError as error:
        if descriptor is not None:
            os.close(descriptor)
        raise ReconciliationError("EVIDENCE_RECONCILIATION_PRIVATE_REPORT_UNWRITABLE") from error


def _write_private_report(descriptor: int, report: Mapping[str, Any]) -> None:
    raw = json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
    except OSError as error:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_PRIVATE_REPORT_UNWRITABLE") from error


def _error_private_report(error: ReconciliationError) -> Dict[str, Any]:
    report = dict(error.report)
    report["error"] = str(error)
    return report


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only comparison of prod evidence state with phase manifests.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--snapshot", type=Path)
    mode.add_argument("--seal", type=Path, help="Print a hash-locked copy of an unsealed JSON input.")
    parser.add_argument("--phase-manifest", action="append", type=Path)
    parser.add_argument("--ledger", type=Path)
    parser.add_argument("--private-report", type=Path)
    args = parser.parse_args(argv)
    if args.seal is not None:
        try:
            if args.phase_manifest or args.ledger or args.private_report:
                raise ReconciliationError("EVIDENCE_RECONCILIATION_SEAL_ARGUMENTS_INVALID")
            print(json.dumps(seal(_load_json(args.seal)), ensure_ascii=False, sort_keys=True))
            return 0
        except ReconciliationError as error:
            print(json.dumps(error.report, ensure_ascii=False, sort_keys=True), file=sys.stderr)
            return 2

    if args.private_report is None:
        _print_terminal_summary({}, "EVIDENCE_RECONCILIATION_PRIVATE_REPORT_REQUIRED")
        return 2
    try:
        private_descriptor = _create_private_report(args.private_report)
    except ReconciliationError as error:
        _print_terminal_summary({}, str(error))
        return 2

    try:
        if not args.phase_manifest or args.ledger is None:
            raise ReconciliationError("EVIDENCE_RECONCILIATION_MANIFESTS_REQUIRED")
        ledger = _load_json(args.ledger)
        manifests = [load_phase_manifest(path) for path in args.phase_manifest]
        approved, contributions = _validate_contribution_admission(manifests, ledger)
        snapshot = _load_json(args.snapshot)
        report = _reconcile_admitted(snapshot, approved, contributions, ledger)
    except ReconciliationError as error:
        try:
            _write_private_report(private_descriptor, _error_private_report(error))
        except ReconciliationError as private_error:
            _print_terminal_summary({}, str(private_error))
            return 2
        _print_terminal_summary(error.report, str(error))
        return 2
    try:
        _write_private_report(private_descriptor, report)
    except ReconciliationError as error:
        _print_terminal_summary({}, str(error))
        return 2
    _print_terminal_summary(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
