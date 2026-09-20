"""Compile a closed, database-free source-scoped replace manifest."""

from __future__ import annotations

import hashlib
from collections.abc import Mapping, Sequence
from typing import Any


class ManifestError(ValueError):
    """Fail-closed manifest input error."""


_HEX64 = set("0123456789abcdef")
_DRY_RUN_KEYS = {"schema", "source_id", "dry_run_sha256", "records", "expected_counts", "policy_decisions"}
_OWNERSHIP_KEYS = {"schema", "source_id", "ownership_sha256", "records"}
_RECORD_KEYS = {"record_key", "outcome", "person_id", "element_id", "narrative_transition", "text", "text_sha256", "expected_state_sha256", "source_operation"}
_OWNERSHIP_RECORD_KEYS = {"record_key", "owned"}
_POLICY_KEYS = {"new_records", "discontinued_records"}
_POLICY_DECISION_KEYS = {"record_key", "mode"}
_SOURCE_OPERATION_KEYS = {"action", "record_key"}


def _fail(code: str) -> None:
    raise ManifestError(f"SOURCE_SCOPED_REPLACE_{code}")


def _exact_mapping(value: Any, keys: set[str], code: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != keys:
        _fail(code)
    return value


def _string(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value:
        _fail(code)
    return value


def _sha256(value: Any, code: str) -> str:
    value = _string(value, code)
    if len(value) != 64 or any(character not in _HEX64 for character in value):
        _fail(code)
    return value


def _positive_int(value: Any, code: str) -> int:
    if type(value) is not int or value <= 0:
        _fail(code)
    return value


def _closed_list(value: Any, code: str) -> list[Any]:
    if not isinstance(value, list):
        _fail(code)
    return value


def _record_key_list(records: Sequence[Mapping[str, Any]], code: str) -> list[str]:
    keys = [_string(record.get("record_key"), code) for record in records]
    if keys != sorted(keys) or len(set(keys)) != len(keys):
        _fail(code)
    return keys


def _policy_allowlist(value: Any, expected_mode: str, code: str) -> set[str]:
    decisions = _closed_list(value, code)
    keys: list[str] = []
    for decision in decisions:
        decision = _exact_mapping(decision, _POLICY_DECISION_KEYS, code)
        key = _string(decision["record_key"], code)
        if decision["mode"] != expected_mode:
            _fail(code)
        keys.append(key)
    if keys != sorted(keys) or len(keys) != len(set(keys)):
        _fail(code)
    return set(keys)


def _validate_counts(value: Any) -> Mapping[str, int]:
    value = _exact_mapping(value, {"narrative_operations", "source_operations"}, "EXPECTED_COUNTS")
    for name in value:
        if type(value[name]) is not int or value[name] < 0:
            _fail("EXPECTED_COUNTS")
    return value


def build_source_scoped_replace_manifest(dry_run: Mapping[str, Any], ownership: Mapping[str, Any], input_sha256: str) -> dict[str, Any]:
    """Compile previously read reports; this function performs no I/O."""
    dry_run = _exact_mapping(dry_run, _DRY_RUN_KEYS, "DRY_RUN_SCHEMA")
    ownership = _exact_mapping(ownership, _OWNERSHIP_KEYS, "OWNERSHIP_SCHEMA")
    if dry_run["schema"] != "source-scoped-replace-dry-run-v1" or ownership["schema"] != "source-scoped-replace-ownership-v1":
        _fail("REPORT_SCHEMA")
    source_id = _positive_int(dry_run["source_id"], "SOURCE_ID")
    if ownership["source_id"] != source_id:
        _fail("SOURCE_ID")
    input_sha256 = _sha256(input_sha256, "INPUT_SHA256")
    dry_run_sha256 = _sha256(dry_run["dry_run_sha256"], "DRY_RUN_SHA256")
    ownership_sha256 = _sha256(ownership["ownership_sha256"], "OWNERSHIP_SHA256")
    records = _closed_list(dry_run["records"], "RECORDS")
    ownership_records = _closed_list(ownership["records"], "OWNERSHIP_RECORDS")
    records = [_exact_mapping(record, _RECORD_KEYS, "RECORD_SCHEMA") for record in records]
    ownership_records = [_exact_mapping(record, _OWNERSHIP_RECORD_KEYS, "OWNERSHIP_RECORD_SCHEMA") for record in ownership_records]
    record_keys = _record_key_list(records, "RECORD_KEYS")
    ownership_keys = _record_key_list(ownership_records, "OWNERSHIP_RECORD_KEYS")
    if ownership_keys != record_keys:
        _fail("OWNERSHIP_SCOPE")
    if any(record["owned"] is not True for record in ownership_records):
        _fail("OWNERSHIP")
    expected_counts = _validate_counts(dry_run["expected_counts"])
    policy = _exact_mapping(dry_run["policy_decisions"], _POLICY_KEYS, "POLICY_SCHEMA")
    new_allowlist = _policy_allowlist(policy["new_records"], "create_staged", "NEW_POLICY")
    discontinued_allowlist = _policy_allowlist(policy["discontinued_records"], "retain_report_only", "DISCONTINUED_POLICY")
    if (new_allowlist | discontinued_allowlist) - set(record_keys):
        _fail("POLICY_SCOPE")

    narrative_operations: list[dict[str, Any]] = []
    source_operations: list[dict[str, Any]] = []
    for record in records:
        record_key = _string(record["record_key"], "RECORD_KEYS")
        outcome = record["outcome"]
        if outcome not in {"entydig", "new", "bortfalden"}:
            _fail("OUTCOME")
        if outcome == "new" and record_key not in new_allowlist:
            _fail("NEW_POLICY")
        if outcome == "bortfalden":
            if record_key not in discontinued_allowlist:
                _fail("DISCONTINUED_POLICY")
            continue
        if outcome == "entydig" and record_key in (new_allowlist | discontinued_allowlist):
            _fail("POLICY_SCOPE")
        transition = record["narrative_transition"]
        if transition not in {"draft_created", "draft_updated"}:
            _fail("NARRATIVE_TRANSITION")
        text = _string(record["text"], "NARRATIVE_TEXT")
        text_sha256 = _sha256(record["text_sha256"], "NARRATIVE_TEXT_SHA256")
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != text_sha256:
            _fail("NARRATIVE_TEXT_SHA256")
        operation = _exact_mapping(record["source_operation"], _SOURCE_OPERATION_KEYS, "SOURCE_OPERATION_SCHEMA")
        if operation["action"] != "replace_owned_facts" or operation["record_key"] != record_key:
            _fail("SOURCE_OPERATION")
        narrative_operations.append({
            "element_id": _positive_int(record["element_id"], "ELEMENT_ID"),
            "person_id": _positive_int(record["person_id"], "PERSON_ID"),
            "source_id": source_id,
            "record_key": record_key,
            "text": text,
            "text_sha256": text_sha256,
            "expected_state_sha256": _sha256(record["expected_state_sha256"], "EXPECTED_STATE_SHA256"),
        })
        source_operations.append({"action": "replace_owned_facts", "record_key": record_key})
    if (new_allowlist | discontinued_allowlist) != {record["record_key"] for record in records if record["outcome"] in {"new", "bortfalden"}}:
        _fail("POLICY_SCOPE")
    if expected_counts != {"narrative_operations": len(narrative_operations), "source_operations": len(source_operations)}:
        _fail("EXPECTED_COUNTS")
    return {
        "schema": "source-scoped-replace-v1",
        "source_id": source_id,
        "record_keys": record_keys,
        "input_sha256": input_sha256,
        "dry_run_sha256": dry_run_sha256,
        "ownership_sha256": ownership_sha256,
        "expected_counts": dict(expected_counts),
        "policy_decisions": {
            "new_records": [dict(item) for item in policy["new_records"]],
            "discontinued_records": [dict(item) for item in policy["discontinued_records"]],
        },
        "narrative_operations": narrative_operations,
        "source_operations": source_operations,
    }
