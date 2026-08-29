#!/usr/bin/env python3
"""Compare a read-only production snapshot with hash-locked phase manifests.

The program never opens a database connection and never writes an artifact.  A
separate, explicitly approved read-only SQL capture produces the production
snapshot; this program verifies a bounded, five-projection final state from an
ordered set of listed phase contributions.  It is deliberately not a proof of
the entire database state or of historical manifest completeness.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Tuple


MANIFEST_SCHEMA = "daa-evidence-phase-reconciliation-manifest-v1"
SNAPSHOT_SCHEMA = "daa-evidence-production-snapshot-v1"
INVENTORY_SCHEMA = "daa-evidence-phase-reconciliation-inventory-v1"
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


def _validate_snapshot(document: object) -> Dict[str, List[Dict[str, Any]]]:
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_SNAPSHOT_INVALID")
    _require(document.get("schema_version") == SNAPSHOT_SCHEMA, "EVIDENCE_RECONCILIATION_SNAPSHOT_SCHEMA_INVALID")
    _require(_is_hex_sha256(document.get("snapshot_content_sha256")), "EVIDENCE_RECONCILIATION_SNAPSHOT_HASH_INVALID")
    _require(_canonical_sha256(document, "snapshot_content_sha256") == document["snapshot_content_sha256"], "EVIDENCE_RECONCILIATION_SNAPSHOT_HASH_INVALID")
    return _validate_sections(document)


def _validate_inventory(document: object) -> Dict[str, Dict[str, Any]]:
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_INVENTORY_INVALID")
    _require(document.get("schema_version") == INVENTORY_SCHEMA, "EVIDENCE_RECONCILIATION_INVENTORY_SCHEMA_INVALID")
    _require(_is_hex_sha256(document.get("inventory_content_sha256")), "EVIDENCE_RECONCILIATION_INVENTORY_HASH_INVALID")
    _require(_canonical_sha256(document, "inventory_content_sha256") == document["inventory_content_sha256"], "EVIDENCE_RECONCILIATION_INVENTORY_HASH_INVALID")
    rows = document.get("phase_manifests")
    _require(isinstance(rows, list) and bool(rows), "EVIDENCE_RECONCILIATION_INVENTORY_INVALID")
    indexed: Dict[str, Dict[str, Any]] = {}
    sequences = set()
    for row in rows:
        _require(isinstance(row, dict) and set(row) == {"phase_id", "sequence", "reconciliation_content_sha256", "source_manifest_sha256"}, "EVIDENCE_RECONCILIATION_INVENTORY_ROW_INVALID")
        phase_id = row["phase_id"]
        _require(isinstance(phase_id, str) and phase_id.strip() == phase_id and bool(phase_id), "EVIDENCE_RECONCILIATION_PHASE_ID_INVALID")
        _require(type(row["sequence"]) is int and row["sequence"] > 0, "EVIDENCE_RECONCILIATION_INVENTORY_SEQUENCE_INVALID")
        _require(_is_hex_sha256(row["reconciliation_content_sha256"]) and _is_hex_sha256(row["source_manifest_sha256"]), "EVIDENCE_RECONCILIATION_INVENTORY_HASH_INVALID")
        if phase_id in indexed:
            raise ReconciliationError("EVIDENCE_RECONCILIATION_INVENTORY_DUPLICATE")
        if row["sequence"] in sequences:
            raise ReconciliationError("EVIDENCE_RECONCILIATION_INVENTORY_SEQUENCE_DUPLICATE")
        sequences.add(row["sequence"])
        indexed[phase_id] = dict(row)
    return indexed


def seal(document: object) -> Dict[str, Any]:
    """Return a hash-locked copy of an unsealed phase manifest or snapshot."""
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_INPUT_INVALID")
    result = dict(document)
    schema = result.get("schema_version")
    if schema == SNAPSHOT_SCHEMA:
        hash_field = "snapshot_content_sha256"
    elif schema == MANIFEST_SCHEMA:
        hash_field = "reconciliation_content_sha256"
    elif schema == INVENTORY_SCHEMA:
        hash_field = "inventory_content_sha256"
    else:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_SCHEMA_INVALID")
    _require(hash_field not in result, "EVIDENCE_RECONCILIATION_ALREADY_SEALED")
    result[hash_field] = _canonical_sha256(result, hash_field)
    if schema == SNAPSHOT_SCHEMA:
        _validate_snapshot(result)
    elif schema == MANIFEST_SCHEMA:
        _validate_manifest(result)
    else:
        _validate_inventory(result)
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


def reconcile(snapshot: object, manifests: Iterable[object], inventory: object) -> Dict[str, Any]:
    """Return a match report or raise a fail-closed ReconciliationError."""
    actual = _validate_snapshot(snapshot)
    approved = _validate_inventory(inventory)
    phase_ids: List[str] = []
    manifest_index: Dict[str, Dict[str, str]] = {}
    contributions: Dict[str, Tuple[Dict[str, List[Dict[str, Any]]], Dict[str, List[Dict[str, Any]]]]] = {}
    for manifest in manifests:
        phase_id, sections, withdrawals = _validate_manifest(manifest)
        if phase_id in phase_ids:
            raise ReconciliationError("EVIDENCE_RECONCILIATION_DUPLICATE_PHASE")
        phase_ids.append(phase_id)
        assert isinstance(manifest, dict)  # narrowed by _validate_manifest
        manifest_index[phase_id] = {
            "reconciliation_content_sha256": manifest["reconciliation_content_sha256"],
            "source_manifest_sha256": manifest["source_manifest_sha256"],
        }
        contributions[phase_id] = (sections, withdrawals)
    _require(bool(phase_ids), "EVIDENCE_RECONCILIATION_MANIFESTS_REQUIRED")
    approved_hashes = {
        phase_id: {
            "reconciliation_content_sha256": row["reconciliation_content_sha256"],
            "source_manifest_sha256": row["source_manifest_sha256"],
        }
        for phase_id, row in approved.items()
    }
    if manifest_index != approved_hashes:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_INVENTORY_MISMATCH")

    expected_rows: Dict[str, Dict[Tuple[Any, ...], Dict[str, Any]]] = {section: {} for section in SECTIONS}
    overrides: Dict[str, int] = {section: 0 for section in SECTIONS}
    withdrawal_counts: Dict[str, int] = {section: 0 for section in SECTIONS}
    for phase_id, _ in sorted(approved.items(), key=lambda item: item[1]["sequence"]):
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
        "phase_ids": [phase_id for phase_id, _ in sorted(approved.items(), key=lambda item: item[1]["sequence"])],
        "inventory_content_sha256": inventory["inventory_content_sha256"],
        "counts": counts,
        "overrides": overrides,
        "withdrawals": withdrawal_counts,
        "differences": differences,
    }
    if differences:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_DRIFT", report)
    return report


def _load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_INPUT_UNREADABLE") from error


def load_phase_manifest(path: Path) -> Dict[str, Any]:
    """Load a contribution and prove its declared original manifest is unchanged."""
    document = _load_json(path)
    _validate_manifest(document)
    assert isinstance(document, dict)  # narrowed by _validate_manifest
    original = path.parent / document["source_manifest_path"]
    try:
        raw = original.read_bytes()
    except OSError as error:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_UNREADABLE") from error
    if hashlib.sha256(raw).hexdigest() != document["source_manifest_sha256"]:
        raise ReconciliationError("EVIDENCE_RECONCILIATION_SOURCE_MANIFEST_HASH_INVALID")
    return document


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only comparison of prod evidence state with phase manifests.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--snapshot", type=Path)
    mode.add_argument("--seal", type=Path, help="Print a hash-locked copy of an unsealed JSON input.")
    parser.add_argument("--phase-manifest", action="append", type=Path)
    parser.add_argument("--inventory", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.seal is not None:
            if args.phase_manifest or args.inventory:
                raise ReconciliationError("EVIDENCE_RECONCILIATION_SEAL_ARGUMENTS_INVALID")
            print(json.dumps(seal(_load_json(args.seal)), ensure_ascii=False, sort_keys=True))
            return 0
        if not args.phase_manifest or args.inventory is None:
            raise ReconciliationError("EVIDENCE_RECONCILIATION_MANIFESTS_REQUIRED")
        report = reconcile(_load_json(args.snapshot), [load_phase_manifest(path) for path in args.phase_manifest], _load_json(args.inventory))
    except ReconciliationError as error:
        print(json.dumps(error.report, ensure_ascii=False, sort_keys=True), file=sys.stderr)
        return 2
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
