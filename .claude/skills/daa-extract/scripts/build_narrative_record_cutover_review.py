#!/usr/bin/env python3
"""Validate cutover candidates, render offline review, and publish artifacts safely."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import secrets
import stat
import sys
import uuid
from pathlib import Path
from typing import Any, Mapping


RECORD_SCHEMA = "narrative-record-baseline-candidates-v1"
LEGACY_SCHEMA = "narrative-legacy-baseline-candidates-v1"
INVENTORY_SCHEMA = "narrative-record-cutover-inventory-v1"
DECISIONS_SCHEMA = "narrative-record-cutover-decisions-v1"
REVIEW_NAME = "narrative-record-cutover-review-v1.html"
HEX64 = frozenset("0123456789abcdef")
REPO_ROOT = Path(__file__).resolve().parents[4]
EXPECTED_CLASSIFIED_READERS = [
    {"path": "mobile/src/data/about.ts", "classification": "non_person_control"},
    {"path": "mobile/src/data/haendelser.ts", "classification": "rls_gated_metadata"},
    {"path": "mobile/src/data/load.ts", "classification": "v2_public_rpc"},
    {"path": "mobile/src/data/presensLinjer.ts", "classification": "non_person_control"},
    {"path": "mobile/src/data/redaktionRead.ts", "classification": "v2_editor_rpc"},
    {"path": "web/src/data/feedAux.ts", "classification": "v2_public_rpc"},
    {"path": "web/src/data/haendelser.ts", "classification": "rls_gated_metadata"},
    {"path": "web/src/data/presensLinjer.ts", "classification": "non_person_control"},
    {"path": "web/src/data/public.ts", "classification": "v2_public_rpc"},
    {"path": "web/src/data/redaktionRead.ts", "classification": "v2_editor_rpc"},
]


class ContractError(ValueError):
    pass


class PublicationError(RuntimeError):
    pass


def _reject_duplicate(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractError(f"DUPLICATE_JSON_KEY: {key}")
        result[key] = value
    return result


def strict_load_json(raw: bytes) -> Any:
    if not isinstance(raw, bytes):
        raise ContractError("RAW_BYTES_REQUIRED")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ContractError("INVALID_UTF8") from error
    try:
        return json.loads(text, object_pairs_hook=_reject_duplicate)
    except ContractError:
        raise
    except (json.JSONDecodeError, ValueError) as error:
        raise ContractError("INVALID_JSON") from error


def canonical_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def raw_sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def require_keys(value: Any, expected: set[str], token: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise ContractError(f"{token}: expected={sorted(expected)}")
    return value


def require_string(value: Any, token: str, *, nonblank: bool = True) -> str:
    if not isinstance(value, str) or (nonblank and not value.strip()):
        raise ContractError(token)
    return value


def require_int(value: Any, token: str) -> int:
    if type(value) is not int:
        raise ContractError(token)
    return value


def require_sha256(value: Any, token: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(c not in HEX64 for c in value):
        raise ContractError(f"INVALID_SHA256: {token}")
    return value


def require_uuid(value: Any, token: str) -> str:
    if not isinstance(value, str):
        raise ContractError(f"INVALID_UUID: {token}")
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError) as error:
        raise ContractError(f"INVALID_UUID: {token}") from error
    if str(parsed) != value.lower():
        raise ContractError(f"INVALID_UUID: {token}")
    return value.lower()


def new_legacy_publication_ref() -> str:
    return str(uuid.uuid4())


def _require_canonical(raw: bytes) -> dict[str, Any]:
    value = strict_load_json(raw)
    if canonical_bytes(value) != raw:
        raise ContractError("NON_CANONICAL_JSON")
    if not isinstance(value, dict):
        raise ContractError("JSON_OBJECT_REQUIRED")
    return value


def _database(value: Any) -> dict[str, str]:
    database = require_keys(value, {"database_name", "system_identifier"}, "DATABASE_SHAPE")
    return {
        "database_name": require_string(database["database_name"], "DATABASE_NAME_REQUIRED"),
        "system_identifier": require_string(
            database["system_identifier"], "SYSTEM_IDENTIFIER_REQUIRED"
        ),
    }


RECORD_ROW_KEYS = {
    "binding_id",
    "narrative_id",
    "person_id",
    "source_id",
    "source_kind",
    "source_record_id",
    "record_key",
    "status",
    "record_label",
    "citation_label",
    "publication_state_sha256",
    "narrative_text_sha256",
    "binding_match_count",
    "row_sha256",
}
LEGACY_ROW_KEYS = {
    "legacy_publication_ref",
    "narrative_id",
    "person_id",
    "source_id",
    "source_kind",
    "narrative_text_sha256",
    "baseline_sha256",
    "binding_match_count",
    "row_sha256",
}


def _row_hash(row: dict[str, Any]) -> str:
    unhashed = dict(row)
    stated = unhashed.pop("row_sha256", None)
    require_sha256(stated, "row_sha256")
    calculated = raw_sha256(canonical_bytes(unhashed))
    if stated != calculated:
        raise ContractError("ROW_SHA256_MISMATCH")
    return stated


def _record_rows(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise ContractError("RECORD_ROWS_REQUIRED")
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in value:
        row = require_keys(item, RECORD_ROW_KEYS, "RECORD_ROW_SHAPE")
        binding_id = require_uuid(row["binding_id"], "binding_id")
        if binding_id in seen:
            raise ContractError("DUPLICATE_RECORD_CANDIDATE")
        seen.add(binding_id)
        require_uuid(row["source_record_id"], "source_record_id")
        for key in ("narrative_id", "person_id", "source_id"):
            require_int(row[key], key)
        if row["source_kind"] != "DAA-udgave":
            raise ContractError("NON_DAA_CANDIDATE")
        if row["binding_match_count"] != 1:
            raise ContractError("AMBIGUOUS_RECORD_BINDING")
        require_string(row["record_key"], "RECORD_KEY_REQUIRED")
        if row["status"] not in {"draft", "published", "withdrawn"}:
            raise ContractError("RECORD_STATUS_INVALID")
        require_string(row["record_label"], "RECORD_LABEL_REQUIRED")
        require_string(row["citation_label"], "CITATION_LABEL_REQUIRED")
        require_sha256(row["publication_state_sha256"], "publication_state_sha256")
        require_sha256(row["narrative_text_sha256"], "narrative_text_sha256")
        _row_hash(row)
        rows.append(row)
    if [row["binding_id"] for row in rows] != sorted(row["binding_id"] for row in rows):
        raise ContractError("RECORD_CANDIDATE_ORDER")
    return rows


def _legacy_rows(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise ContractError("LEGACY_ROWS_REQUIRED")
    rows: list[dict[str, Any]] = []
    seen_ids: set[int] = set()
    seen_refs: set[str] = set()
    for item in value:
        row = require_keys(item, LEGACY_ROW_KEYS, "LEGACY_ROW_SHAPE")
        narrative_id = require_int(row["narrative_id"], "narrative_id")
        if narrative_id in seen_ids:
            raise ContractError("DUPLICATE_LEGACY_CANDIDATE")
        seen_ids.add(narrative_id)
        ref = require_uuid(row["legacy_publication_ref"], "legacy_publication_ref")
        if ref in seen_refs:
            raise ContractError("DUPLICATE_LEGACY_PUBLICATION_REF")
        seen_refs.add(ref)
        for key in ("person_id", "source_id"):
            require_int(row[key], key)
        if row["source_kind"] != "DAA-udgave":
            raise ContractError("NON_DAA_CANDIDATE")
        if row["binding_match_count"] != 0:
            raise ContractError("AMBIGUOUS_LEGACY_BINDING")
        require_sha256(row["narrative_text_sha256"], "narrative_text_sha256")
        require_sha256(row["baseline_sha256"], "baseline_sha256")
        _row_hash(row)
        rows.append(row)
    if [row["narrative_id"] for row in rows] != sorted(row["narrative_id"] for row in rows):
        raise ContractError("LEGACY_CANDIDATE_ORDER")
    return rows


def validate_candidate_bundle(
    record_raw: bytes, legacy_raw: bytes, inventory_raw: bytes
) -> dict[str, Any]:
    record = require_keys(
        _require_canonical(record_raw), {"schema_version", "database", "rows"},
        "RECORD_DOCUMENT_SHAPE",
    )
    legacy = require_keys(
        _require_canonical(legacy_raw), {"schema_version", "database", "rows"},
        "LEGACY_DOCUMENT_SHAPE",
    )
    inventory = require_keys(
        _require_canonical(inventory_raw),
        {
            "schema_version", "database", "record_candidate_ids",
            "legacy_candidate_ids", "counts_by_source", "accepted_identity_count",
            "identity_blocked_record_count", "classified_direct_readers",
        },
        "INVENTORY_DOCUMENT_SHAPE",
    )
    if record["schema_version"] != RECORD_SCHEMA:
        raise ContractError("RECORD_SCHEMA_VERSION")
    if legacy["schema_version"] != LEGACY_SCHEMA:
        raise ContractError("LEGACY_SCHEMA_VERSION")
    if inventory["schema_version"] != INVENTORY_SCHEMA:
        raise ContractError("INVENTORY_SCHEMA_VERSION")
    database = _database(record["database"])
    if _database(legacy["database"]) != database or _database(inventory["database"]) != database:
        raise ContractError("DATABASE_IDENTITY_MISMATCH")
    record_rows = _record_rows(record["rows"])
    legacy_rows = _legacy_rows(legacy["rows"])
    record_ids = [row["binding_id"] for row in record_rows]
    legacy_ids = [row["narrative_id"] for row in legacy_rows]
    if inventory["record_candidate_ids"] != record_ids:
        raise ContractError("INVENTORY_RECORD_ID_SET_MISMATCH")
    if inventory["legacy_candidate_ids"] != legacy_ids:
        raise ContractError("INVENTORY_LEGACY_ID_SET_MISMATCH")
    accepted_identity_count = require_int(
        inventory["accepted_identity_count"], "INVENTORY_ACCEPTED_IDENTITY_COUNT"
    )
    blocked_record_count = require_int(
        inventory["identity_blocked_record_count"], "INVENTORY_BLOCKED_RECORD_COUNT"
    )
    if accepted_identity_count < 0 or blocked_record_count < 0:
        raise ContractError("INVENTORY_IDENTITY_COUNT_NEGATIVE")
    if not isinstance(inventory["counts_by_source"], list):
        raise ContractError("COUNTS_BY_SOURCE_REQUIRED")
    observed_counts: list[dict[str, int]] = []
    for row in inventory["counts_by_source"]:
        row = require_keys(
            row, {"source_id", "record_candidates", "legacy_candidates"},
            "INVENTORY_COUNTS_BY_SOURCE_SHAPE",
        )
        source_id = require_int(row["source_id"], "INVENTORY_SOURCE_ID")
        record_count = require_int(
            row["record_candidates"], "INVENTORY_RECORD_CANDIDATE_COUNT"
        )
        legacy_count = require_int(
            row["legacy_candidates"], "INVENTORY_LEGACY_CANDIDATE_COUNT"
        )
        if record_count < 0 or legacy_count < 0:
            raise ContractError("INVENTORY_CANDIDATE_COUNT_NEGATIVE")
        observed_counts.append({
            "source_id": source_id,
            "record_candidates": record_count,
            "legacy_candidates": legacy_count,
        })
    count_map: dict[int, dict[str, int]] = {}
    for row in record_rows:
        value = count_map.setdefault(
            row["source_id"],
            {"source_id": row["source_id"], "record_candidates": 0, "legacy_candidates": 0},
        )
        value["record_candidates"] += 1
    for row in legacy_rows:
        value = count_map.setdefault(
            row["source_id"],
            {"source_id": row["source_id"], "record_candidates": 0, "legacy_candidates": 0},
        )
        value["legacy_candidates"] += 1
    expected_counts = [count_map[source_id] for source_id in sorted(count_map)]
    if observed_counts != expected_counts:
        raise ContractError("INVENTORY_COUNTS_BY_SOURCE_MISMATCH")
    if not isinstance(inventory["classified_direct_readers"], list):
        raise ContractError("CLASSIFIED_DIRECT_READERS_REQUIRED")
    readers: list[str] = []
    reader_classes = {
        "non_person_control", "rls_gated_metadata", "v2_public_rpc", "v2_editor_rpc",
    }
    for reader in inventory["classified_direct_readers"]:
        reader = require_keys(
            reader, {"path", "classification"}, "INVENTORY_READER_SHAPE"
        )
        path = require_string(reader["path"], "INVENTORY_READER_PATH")
        classification = require_string(
            reader["classification"], "INVENTORY_READER_CLASSIFICATION"
        )
        if classification not in reader_classes:
            raise ContractError("INVENTORY_READER_CLASSIFICATION")
        readers.append(path)
    if readers != sorted(readers) or len(readers) != len(set(readers)):
        raise ContractError("INVENTORY_READER_ORDER_OR_DUPLICATE")
    if inventory["classified_direct_readers"] != EXPECTED_CLASSIFIED_READERS:
        raise ContractError("INVENTORY_READER_SET_MISMATCH")
    return {
        "record": record,
        "legacy": legacy,
        "inventory": inventory,
        "database": database,
        "record_rows": record_rows,
        "legacy_rows": legacy_rows,
        "hashes": {
            "record_candidates_sha256": raw_sha256(record_raw),
            "legacy_candidates_sha256": raw_sha256(legacy_raw),
            "inventory_sha256": raw_sha256(inventory_raw),
        },
    }


def _b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def build_review_html(record_raw: bytes, legacy_raw: bytes, inventory_raw: bytes) -> bytes:
    bundle = validate_candidate_bundle(record_raw, legacy_raw, inventory_raw)
    hashes = bundle["hashes"]
    # Browser data contains strings only. In particular, BIGINT identifiers are
    # decimal strings until the canonical serializer emits their JSON number token.
    review_data = {
        "database": bundle["database"],
        "record_rows": [
            {
                "binding_id": row["binding_id"],
                "record_label": row["record_label"],
                "citation_label": row["citation_label"],
                "row_sha256": row["row_sha256"],
            }
            for row in bundle["record_rows"]
        ],
        "legacy_rows": [
            {
                "narrative_id_decimal": str(row["narrative_id"]),
                "row_sha256": row["row_sha256"],
            }
            for row in bundle["legacy_rows"]
        ],
    }
    script = r"""
const reviewData = __NRK_REVIEW_DATA__;
const hashes = __NRK_HASHES__;
const selections = new Map();
const root = document.getElementById('review');
const add = (tag, text, parent = root) => { const node = document.createElement(tag); node.textContent = text; parent.appendChild(node); return node; };
const choice = (kind, id, rowHash, label, value, parent) => {
  const wrap = document.createElement('label');
  const input = document.createElement('input'); input.type = 'radio'; input.name = kind + ':' + id; input.value = value;
  input.addEventListener('change', () => selections.set(kind + ':' + id, {id, row_sha256: rowHash, decision: value}));
  wrap.appendChild(input); wrap.appendChild(document.createTextNode(label)); parent.appendChild(wrap);
};
add('h1', 'Narrative record cutover review v1');
add('p', 'Record candidates SHA-256: ' + hashes.record_candidates_sha256);
add('p', 'Legacy candidates SHA-256: ' + hashes.legacy_candidates_sha256);
add('p', 'Inventory SHA-256: ' + hashes.inventory_sha256);
add('h2', 'Record-baselines');
reviewData.record_rows.forEach(row => { const card = add('section', ''); add('h3', row.binding_id + ' — ' + row.record_label, card); add('p', row.citation_label, card); choice('record', row.binding_id, row.row_sha256, 'godkend baseline', 'godkend baseline', card); choice('record', row.binding_id, row.row_sha256, 'uafklaret', 'uafklaret', card); });
add('h2', 'Legacy-publicationer');
reviewData.legacy_rows.forEach(row => { const card = add('section', ''); add('h3', row.narrative_id_decimal, card); choice('legacy', row.narrative_id_decimal, row.row_sha256, 'bevar offentligt som grandfathered', 'bevar offentligt som grandfathered', card); choice('legacy', row.narrative_id_decimal, row.row_sha256, 'skjul ved cutover', 'skjul ved cutover', card); choice('legacy', row.narrative_id_decimal, row.row_sha256, 'uafklaret', 'uafklaret', card); });
const RAW_INTEGER = Symbol('raw canonical integer');
const rawInteger = decimal => { if (typeof decimal !== 'string' || !/^-?(0|[1-9][0-9]*)$/.test(decimal)) throw new Error('INVALID_INTEGER_DECIMAL'); return {[RAW_INTEGER]: decimal}; };
const canonical = value => { if (value && typeof value === 'object' && Object.prototype.hasOwnProperty.call(value, RAW_INTEGER)) return value[RAW_INTEGER]; if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']'; if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'; return JSON.stringify(value); };
if (canonical({narrative_id: rawInteger('9007199254740993')}) !== '{"narrative_id":9007199254740993}') throw new Error('BIGINT_CANONICALIZATION_FAILED');
const exportButton = add('button', 'Eksportér beslutnings-JSON');
exportButton.addEventListener('click', () => {
  const record_decisions = reviewData.record_rows.map(row => selections.get('record:' + row.binding_id) || {id: row.binding_id, row_sha256: row.row_sha256, decision: 'uafklaret'}).map(item => ({binding_id: item.id, row_sha256: item.row_sha256, decision: item.decision}));
  const legacy_decisions = reviewData.legacy_rows.map(row => selections.get('legacy:' + row.narrative_id_decimal) || {id: row.narrative_id_decimal, row_sha256: row.row_sha256, decision: 'uafklaret'}).map(item => ({narrative_id: rawInteger(item.id), row_sha256: item.row_sha256, decision: item.decision}));
  const result = {schema_version: 'narrative-record-cutover-decisions-v1', database: reviewData.database, input_hashes: hashes, record_decisions, legacy_decisions};
  const raw = canonical(result) + '\n'; const blob = new Blob([raw], {type: 'application/json'}); const anchor = document.createElement('a'); anchor.href = URL.createObjectURL(blob); anchor.download = 'narrative-record-cutover-decisions-v1.json'; anchor.click(); URL.revokeObjectURL(anchor.href);
});
"""
    hashes_json = json.dumps(
        hashes, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    review_json = json.dumps(
        review_data, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    for character, escaped in (
        ("<", "\\u003c"), (">", "\\u003e"), ("&", "\\u0026"),
        ("\u2028", "\\u2028"), ("\u2029", "\\u2029"),
    ):
        review_json = review_json.replace(character, escaped)
    script = script.replace("__NRK_HASHES__", hashes_json, 1)
    script = script.replace("__NRK_REVIEW_DATA__", review_json, 1)
    document = (
        "<!doctype html><html lang=\"da\"><head><meta charset=\"utf-8\">"
        "<meta name=\"referrer\" content=\"no-referrer\">"
        "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; "
        "script-src 'unsafe-inline'; style-src 'unsafe-inline'\">"
        "<title>Narrative record cutover review</title>"
        "<style>body{font:16px system-ui;max-width:72rem;margin:2rem auto;padding:0 1rem}"
        "section{border:1px solid #999;padding:1rem;margin:1rem 0}label{display:block}</style>"
        "</head><body><main id=\"review\"></main><script>" + script + "</script></body></html>\n"
    )
    # A final assertion protects future edits from introducing unsafe rendering/network APIs.
    for forbidden in ("innerHTML", "document.write", "fetch(", "XMLHttpRequest"):
        if forbidden in document:
            raise ContractError("UNSAFE_REVIEW_HTML")
    return document.encode("utf-8")


def _validate_output_path(path: Path) -> tuple[Path, os.stat_result]:
    path = Path(path)
    if "work" in path.parts:
        raise PublicationError("OUTPUT_WORK_PATH")
    try:
        entry = path.lstat()
    except FileNotFoundError as error:
        raise PublicationError("OUTPUT_DIRECTORY_MISSING") from error
    if stat.S_ISLNK(entry.st_mode):
        raise PublicationError("OUTPUT_SYMLINK")
    if not stat.S_ISDIR(entry.st_mode):
        raise PublicationError("OUTPUT_NOT_DIRECTORY")
    resolved = path.resolve(strict=True)
    if "work" in resolved.parts:
        raise PublicationError("OUTPUT_WORK_PATH")
    try:
        resolved.relative_to(REPO_ROOT.resolve(strict=True))
    except ValueError:
        pass
    else:
        raise PublicationError("OUTPUT_INSIDE_REPOSITORY")
    if stat.S_IMODE(entry.st_mode) != 0o700:
        raise PublicationError("OUTPUT_DIRECTORY_MODE")
    return resolved, entry


def _open_dirfd(path: Path) -> tuple[Path, int]:
    resolved, expected = _validate_output_path(path)
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(resolved, flags)
    current = os.fstat(descriptor)
    if (current.st_dev, current.st_ino) != (expected.st_dev, expected.st_ino):
        os.close(descriptor)
        raise PublicationError("OUTPUT_DIRECTORY_RACE")
    return resolved, descriptor


def open_output_directory(path: Path) -> Path:
    resolved, descriptor = _open_dirfd(path)
    os.close(descriptor)
    return resolved


def _valid_name(name: str) -> str:
    if not isinstance(name, str) or not name or Path(name).name != name or name in {".", ".."}:
        raise PublicationError("OUTPUT_FILENAME_INVALID")
    if name.startswith(".nrk."):
        raise PublicationError("OUTPUT_FILENAME_RESERVED")
    return name


def _read_at(descriptor: int, name: str) -> tuple[bytes, os.stat_result]:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    handle = os.open(name, flags, dir_fd=descriptor)
    try:
        info = os.fstat(handle)
        if not stat.S_ISREG(info.st_mode):
            raise PublicationError("OUTPUT_TARGET_NOT_REGULAR")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(handle, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks), info
    finally:
        os.close(handle)


def _exact_target(descriptor: int, name: str, raw: bytes) -> bool:
    try:
        observed, info = _read_at(descriptor, name)
    except FileNotFoundError:
        return False
    return observed == raw and stat.S_IMODE(info.st_mode) == 0o600


def _write_all(handle: int, raw: bytes) -> None:
    offset = 0
    while offset < len(raw):
        written = os.write(handle, raw[offset:])
        if written <= 0:
            raise PublicationError("OUTPUT_WRITE_FAILED")
        offset += written


def _same_file(left: os.stat_result, right: os.stat_result) -> bool:
    return (left.st_dev, left.st_ino) == (right.st_dev, right.st_ino)


def _unlink_owned(
    descriptor: int, entries: list[tuple[str, int, os.stat_result | None]]
) -> bool:
    recovery_required = False
    for path, handle, expected in entries:
        if expected is None:
            recovery_required = True
            continue
        try:
            info = os.stat(path, dir_fd=descriptor, follow_symlinks=False)
            owned = os.fstat(handle)
            if not _same_file(info, expected) or not _same_file(owned, expected):
                recovery_required = True
            else:
                os.unlink(path, dir_fd=descriptor)
        except FileNotFoundError:
            pass
        except OSError:
            recovery_required = True
    return recovery_required


def _close_staged(entries: list[tuple[str, int, os.stat_result | None]]) -> bool:
    recovery_required = False
    for _path, handle, _expected in entries:
        try:
            os.close(handle)
        except OSError:
            recovery_required = True
    return recovery_required


def _cleanup_staged(
    descriptor: int, staged: Mapping[str, tuple[str, int, os.stat_result | None]]
) -> bool:
    entries = list(staged.values())
    recovery_required = _unlink_owned(descriptor, entries)
    try:
        os.fsync(descriptor)
    except OSError:
        recovery_required = True
    if _close_staged(entries):
        recovery_required = True
    return recovery_required


def _stage_files(
    descriptor: int, bundle: Mapping[str, bytes]
) -> dict[str, tuple[str, int, os.stat_result | None]]:
    staged: dict[str, tuple[str, int, os.stat_result | None]] = {}
    token = secrets.token_hex(16)
    try:
        for index, (name, raw) in enumerate(bundle.items()):
            temp = f".nrk.{token}.{index}.tmp"
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0)
            flags |= getattr(os, "O_NOFOLLOW", 0)
            handle = os.open(temp, flags, 0o600, dir_fd=descriptor)
            staged[name] = (temp, handle, None)
            staged[name] = (temp, handle, os.fstat(handle))
            os.fchmod(handle, 0o600)
            _write_all(handle, raw)
            os.fsync(handle)
        return staged
    except Exception as error:
        if _cleanup_staged(descriptor, staged):
            raise PublicationError("ARTIFACT_RECOVERY_REQUIRED") from error
        if isinstance(error, PublicationError):
            raise
        raise PublicationError("OUTPUT_PUBLICATION_FAILED") from error


def _publish_missing(
    descriptor: int, bundle: Mapping[str, bytes], missing: list[str]
) -> None:
    subset = {name: bundle[name] for name in missing}
    staged = _stage_files(descriptor, subset)
    linked: list[tuple[str, int, os.stat_result]] = []
    try:
        for name in missing:
            temp, handle, expected = staged[name]
            if expected is None:
                raise PublicationError("ARTIFACT_RECOVERY_REQUIRED")
            if not _same_file(
                os.stat(temp, dir_fd=descriptor, follow_symlinks=False), expected
            ) or not _same_file(os.fstat(handle), expected):
                raise PublicationError("ARTIFACT_RECOVERY_REQUIRED")
            os.link(
                temp, name, src_dir_fd=descriptor, dst_dir_fd=descriptor,
                follow_symlinks=False,
            )
            linked.append((name, handle, expected))
            if not _same_file(
                os.stat(name, dir_fd=descriptor, follow_symlinks=False), expected
            ):
                raise PublicationError("ARTIFACT_RECOVERY_REQUIRED")
        if _unlink_owned(descriptor, list(staged.values())):
            raise PublicationError("ARTIFACT_RECOVERY_REQUIRED")
        os.fsync(descriptor)
        for name in missing:
            observed, info = _read_at(descriptor, name)
            expected = staged[name][2]
            if (expected is None or observed != bundle[name]
                    or stat.S_IMODE(info.st_mode) != 0o600
                    or not _same_file(info, expected)):
                raise PublicationError("ARTIFACT_RECOVERY_REQUIRED")
        if _close_staged(list(staged.values())):
            raise PublicationError("ARTIFACT_RECOVERY_REQUIRED")
    except Exception as error:
        recovery_required = _unlink_owned(descriptor, list(reversed(linked)))
        if _unlink_owned(descriptor, list(staged.values())):
            recovery_required = True
        try:
            os.fsync(descriptor)
        except OSError:
            recovery_required = True
        if _close_staged(list(staged.values())):
            recovery_required = True
        if recovery_required:
            raise PublicationError("ARTIFACT_RECOVERY_REQUIRED") from error
        if isinstance(error, PublicationError):
            raise
        raise PublicationError("OUTPUT_PUBLICATION_FAILED") from error


def _normalize_bundle(bundle: Mapping[str, bytes]) -> dict[str, bytes]:
    if not isinstance(bundle, Mapping) or not bundle:
        raise PublicationError("OUTPUT_BUNDLE_REQUIRED")
    result: dict[str, bytes] = {}
    for name in sorted(bundle):
        _valid_name(name)
        raw = bundle[name]
        if not isinstance(raw, bytes):
            raise PublicationError("OUTPUT_BYTES_REQUIRED")
        result[name] = raw
    return result


def _require_clean_temp_inventory(descriptor: int) -> None:
    try:
        entries = os.listdir(descriptor)
    except OSError as error:
        raise PublicationError("ARTIFACT_RECOVERY_REQUIRED") from error
    if any(name.startswith(".nrk.") for name in entries):
        raise PublicationError("ARTIFACT_RECOVERY_REQUIRED")


def publish_bundle(path: Path, bundle: Mapping[str, bytes]) -> str:
    normalized = _normalize_bundle(bundle)
    _resolved, descriptor = _open_dirfd(path)
    try:
        _require_clean_temp_inventory(descriptor)
        for name in normalized:
            try:
                os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            except FileNotFoundError:
                continue
            raise PublicationError(f"OUTPUT_TARGET_EXISTS: {name}")
        _publish_missing(descriptor, normalized, list(normalized))
        return "published"
    finally:
        os.close(descriptor)


def recover_bundle(path: Path, bundle: Mapping[str, bytes]) -> str:
    normalized = _normalize_bundle(bundle)
    _resolved, descriptor = _open_dirfd(path)
    try:
        _require_clean_temp_inventory(descriptor)
        missing: list[str] = []
        # Validate every existing target before writing anything. A foreign target
        # makes ownership ambiguous and therefore requires manual recovery.
        for name, raw in normalized.items():
            try:
                os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            except FileNotFoundError:
                missing.append(name)
            else:
                if not _exact_target(descriptor, name, raw):
                    raise PublicationError("ARTIFACT_RECOVERY_REQUIRED")
        if not missing:
            return "already_complete"
        _publish_missing(descriptor, normalized, missing)
        return "recovered"
    finally:
        os.close(descriptor)


def _stdin_bundle() -> dict[str, bytes]:
    value = strict_load_json(sys.stdin.buffer.read())
    document = require_keys(value, {"files"}, "PUBLICATION_REQUEST_SHAPE")
    if not isinstance(document["files"], dict):
        raise ContractError("PUBLICATION_FILES_REQUIRED")
    result: dict[str, bytes] = {}
    for name, encoded in document["files"].items():
        require_string(encoded, "PUBLICATION_BASE64_REQUIRED", nonblank=False)
        try:
            result[name] = base64.b64decode(encoded, validate=True)
        except ValueError as error:
            raise ContractError("PUBLICATION_BASE64_INVALID") from error
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--record-candidates")
    parser.add_argument("--legacy-candidates")
    parser.add_argument("--inventory")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument(
        "--mode", choices=("review", "publish-bundle-stdin", "recover-bundle-stdin"),
        default="review",
    )
    args = parser.parse_args(argv)
    output = Path(args.output_dir)
    try:
        if args.mode == "review":
            if not all((args.record_candidates, args.legacy_candidates, args.inventory)):
                raise ContractError("REVIEW_INPUT_PATHS_REQUIRED")
            record_raw = Path(args.record_candidates).read_bytes()
            legacy_raw = Path(args.legacy_candidates).read_bytes()
            inventory_raw = Path(args.inventory).read_bytes()
            raw = build_review_html(record_raw, legacy_raw, inventory_raw)
            outcome = publish_bundle(output, {REVIEW_NAME: raw})
            print(f"{outcome} output={output / REVIEW_NAME} sha256={raw_sha256(raw)}")
        else:
            bundle = _stdin_bundle()
            outcome = (
                publish_bundle(output, bundle)
                if args.mode == "publish-bundle-stdin"
                else recover_bundle(output, bundle)
            )
            print(outcome)
        return 0
    except (ContractError, PublicationError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
