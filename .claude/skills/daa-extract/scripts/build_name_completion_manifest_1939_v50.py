#!/usr/bin/env python3
"""Compile the closed DAA 1939 v50 staged name-completion manifest."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "1939-v50-name-completion-manifest-v1"
SOURCE_BATCH_ID = "560c39f8-5c87-4c0d-a768-025d97fa2974"
SOURCE_MANIFEST_BYTES_SHA256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"
SOURCE_MANIFEST_CONTENT_SHA256 = "8c6a9f56af7f1e75e1b961f561cc2118478ac4d9e08f838c9e5279938c545f03"
PRODUCTION_BINDINGS = {
    "record-3766faae-ae21-412a-8cfb-745a19ac77f0": (1846, "Ditlev", 503),
    "record-43d4974a-0532-421d-a3fb-8e7c575a67e7": (1847, "Gerhard (Gherardus de Reventlow)", 506),
    "record-80180a6e-2cc6-4968-81ca-004b6662d8ce": (1848, "Henning", 506),
    "record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422": (1849, "Henning Reventlow", 508),
    "record-8f346104-cf3c-465f-bfa3-efb78be436b2": (1850, "Iven (Ywanus de Reuentlo)", 506),
    "record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58": (1851, "Henning", 508),
    "record-b626f5ff-f2fb-4061-bfce-988dbddec846": (1852, "Henrik", 506),
    "record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d": (1853, "Margrethe", 517),
}


class ManifestError(ValueError):
    pass


def _fail(code: str) -> None:
    raise ManifestError(code)


def artifact_sha(value: object) -> str:
    return hashlib.sha256((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()).hexdigest()


def canonical_sha(value: object) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _validate_input_hashes(values: tuple[object, ...], supplied: list[str]) -> None:
    if len(supplied) != 3 or any(not isinstance(x, str) or not re.fullmatch(r"[0-9a-f]{64}", x) for x in supplied):
        _fail("NAME_COMPLETION_INPUT_HASH_INVALID")


def _rows_by_key(rows: Any, key: str) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list) or len(rows) != 8 or any(not isinstance(row, dict) for row in rows):
        _fail(key)
    result = {row.get("source_record_key"): row for row in rows}
    if set(result) != set(PRODUCTION_BINDINGS) or len(result) != 8:
        _fail(key)
    return result


def build_manifest(production_manifest: dict[str, Any], production_apply: dict[str, Any],
                   post_apply_audit: dict[str, Any], *, input_hashes: list[str]) -> dict[str, object]:
    values = (production_manifest, production_apply, post_apply_audit)
    _validate_input_hashes(values, input_hashes)
    if not isinstance(production_manifest, dict) or set(production_manifest) != {"schema_version", "batch_id", "manifest_content_sha256", "person_creates"} or production_manifest.get("schema_version") != "1939-v50-production-write-manifest-v1":
        _fail("NAME_COMPLETION_SOURCE_MANIFEST_INVALID")
    if not isinstance(production_apply, dict) or set(production_apply) != {"schema_version", "batch_id", "status", "committed", "person_id_map"} or production_apply.get("schema_version") != "1939-v50-production-apply-result-v1":
        _fail("NAME_COMPLETION_APPLY_INVALID")
    if not isinstance(post_apply_audit, dict) or set(post_apply_audit) != {"schema_version", "batch_id", "rows"} or post_apply_audit.get("schema_version") != "1939-v50-post-apply-audit-v1":
        _fail("NAME_COMPLETION_AUDIT_INVALID")
    if production_manifest.get("manifest_content_sha256") != SOURCE_MANIFEST_CONTENT_SHA256:
        _fail("NAME_COMPLETION_SOURCE_MANIFEST_INVALID")
    for value in values:
        if "batch_id" in value and value.get("batch_id") != SOURCE_BATCH_ID:
            _fail("NAME_COMPLETION_BATCH_INVALID")
    if production_apply.get("status") != "finalized" or production_apply.get("committed") is not True:
        _fail("NAME_COMPLETION_APPLY_INVALID")

    creates = _rows_by_key(production_manifest.get("person_creates"), "NAME_COMPLETION_SOURCE_ROWS_INVALID")
    if list(production_manifest["person_creates"][i].get("source_record_key") for i in range(8)) != list(PRODUCTION_BINDINGS):
        _fail("NAME_COMPLETION_SOURCE_ROWS_INVALID")
    mappings = production_apply.get("person_id_map")
    if not isinstance(mappings, dict) or list(mappings) != list(PRODUCTION_BINDINGS):
        _fail("NAME_COMPLETION_APPLY_MAP_INVALID")
    audits = _rows_by_key(post_apply_audit.get("rows"), "NAME_COMPLETION_AUDIT_ROWS_INVALID")
    if [row.get("source_record_key") for row in post_apply_audit["rows"]] != list(PRODUCTION_BINDINGS):
        _fail("NAME_COMPLETION_AUDIT_ROWS_INVALID")
    if set(mappings) != set(PRODUCTION_BINDINGS) or len(set(mappings.values())) != 8:
        _fail("NAME_COMPLETION_APPLY_MAP_INVALID")

    operations = []
    for key, (expected_person, expected_name, expected_page) in PRODUCTION_BINDINGS.items():
        row, audit = creates[key], audits[key]
        if mappings[key] != expected_person:
            _fail("NAME_COMPLETION_PERSON_BINDING_INVALID")
        allowed = {"element_id", "source_record_key", "source_id", "edition", "source_persona_id", "name",
                   "source_span", "page_evidence", "verbatim_text", "verbatim_sha256", "staged", "facts",
                   "relations", "families", "sex", "narrative", "source_mentions", "persona_mention_links",
                   "identity_decision_sha256", "review_sha256", "decision_basis", "uncertainties"}
        if not set(row) <= allowed or row.get("element_id") != f"person-create:{key}":
            _fail("NAME_COMPLETION_SOURCE_ROW_INVALID")
        if (row.get("source_record_key") != key or row.get("source_id") != 3 or row.get("edition") != "1939" or
                row.get("name") != expected_name or row.get("staged") is not True or row.get("facts") != [] or
                row.get("relations") != [] or row.get("families") != []):
            _fail("NAME_COMPLETION_SOURCE_ROW_INVALID")
        persona = row.get("source_persona_id")
        span = row.get("source_span")
        if not isinstance(persona, str) or not persona or not isinstance(span, dict) or set(span) != {"char_from", "char_to"} or not isinstance(span["char_from"], int) or not isinstance(span["char_to"], int) or span["char_from"] < 0 or span["char_to"] <= span["char_from"]:
            _fail("NAME_COMPLETION_SOURCE_EVIDENCE_INVALID")
        text, page = row.get("verbatim_text"), row.get("page_evidence")
        if (not isinstance(text, str) or hashlib.sha256(text.encode()).hexdigest() != row.get("verbatim_sha256") or
                not isinstance(page, dict) or page.get("page_from") != expected_page or page.get("page_to") != expected_page):
            _fail("NAME_COMPLETION_SOURCE_EVIDENCE_INVALID")
        if (audit.get("person_id") != expected_person or audit.get("source_record_key") != key or
                audit.get("source_persona_id") != row.get("source_persona_id") or audit.get("name") != expected_name or
                audit.get("page") != expected_page or audit.get("verbatim_text") != text or
                audit.get("staged") is not True or audit.get("name_fact_count") != 0):
            _fail("NAME_COMPLETION_AUDIT_INVALID")
        operations.append({
            "element_id": f"name-completion:{key}", "source_batch_id": SOURCE_BATCH_ID,
            "source_person_create_element_id": row["element_id"], "person_id": expected_person,
            "source_id": 3, "edition": "1939", "source_record_key": key,
            "source_persona_id": row.get("source_persona_id"), "name": expected_name,
            "source_span": row.get("source_span"), "page_evidence": page,
            "verbatim_text": text, "verbatim_sha256": row["verbatim_sha256"],
            "source_payload_sha256": canonical_sha(row),
            "expected_before": {"staged": True, "name_cache_empty": True, "name_facts": 0},
            "expected_after": {"name_fact": 1, "selected_assertion": 1, "daa_1939_citation": 1, "conclusion": 1},
        })
    result = {
        "schema_version": SCHEMA_VERSION, "generator_version": "build_name_completion_manifest_1939_v50.py:v1",
        "input_hashes": {"production_manifest_sha256": input_hashes[0], "production_apply_sha256": input_hashes[1], "post_apply_audit_sha256": input_hashes[2]},
        "source": {"edition": "1939", "source_id": 3}, "source_batch_id": SOURCE_BATCH_ID,
        "source_manifest_bytes_sha256": SOURCE_MANIFEST_BYTES_SHA256,
        "source_manifest_content_sha256": SOURCE_MANIFEST_CONTENT_SHA256,
        "operations": operations, "counts": {"name_completions": 8, "operations": 8},
        "expected_changes": {"facts_created": 8, "assertions_created": 8, "citations_created": 8, "conclusions_created": 8,
                             "persons_created": 0, "persons_activated": 0, "relations_changed": 0, "families_changed": 0},
        "production_authorized": False, "cutover_authorized": False,
    }
    result["manifest_content_sha256"] = canonical_sha(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    for label in ("production-manifest", "production-apply", "post-apply-audit"):
        parser.add_argument(f"--{label}", required=True)
        parser.add_argument(f"--{label}-sha256", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output)
    if output.exists():
        _fail("NAME_COMPLETION_OUTPUT_EXISTS")
    paths = [Path(args.production_manifest), Path(args.production_apply), Path(args.post_apply_audit)]
    hashes = [args.production_manifest_sha256, args.production_apply_sha256, args.post_apply_audit_sha256]
    raw = [path.read_bytes() for path in paths]
    if [hashlib.sha256(data).hexdigest() for data in raw] != hashes:
        _fail("NAME_COMPLETION_INPUT_HASH_INVALID")
    result = build_manifest(*(json.loads(data) for data in raw), input_hashes=hashes)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except ManifestError as error:
        raise SystemExit(str(error))
