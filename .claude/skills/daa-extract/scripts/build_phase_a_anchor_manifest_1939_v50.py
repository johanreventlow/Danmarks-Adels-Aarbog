#!/usr/bin/env python3
"""Build the DAA 1939 v50 fase-A anchor manifest of source_evidence-only writes.

Consumes the closed task 21/25 artefacts (import-preview, database-preview,
production-write-manifest, boundary-materialization) plus the Calamari
rendition text, and emits ONE closed, non-authorizing manifest containing the
source_evidence elements for every source record that task 25's production
manifest did NOT already write as a person_create. Never authorizes writes;
never touches the database.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


HASH_RE = re.compile(r"^[0-9a-f]{64}$")
CALAMARI_RENDITION_ID = "daa-1939-calamari-r6-clean"
CALAMARI_SOURCE_ID = "1939"
SQL_PAYLOAD_KEYS = {
    "review_subject_id", "source_record_key", "category", "disposition",
    "evidence_sha256", "canonical_target", "source_span", "page_evidence",
    "verbatim_text", "legacy_payload", "rendition_content_sha256",
}

# Låst 2026-08-18 (task-1-context.md, Faktagrundlag) — production-universets
# input-hashes og aritmetik. Byggeren fail-closed'er hvis en fil er drivet,
# uafhængigt af hvad der overleveres på CLI'en.
LOCKED_IMPORT_PREVIEW_SHA256 = "04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5"
LOCKED_DATABASE_PREVIEW_SHA256 = "a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c"
LOCKED_PRODUCTION_MANIFEST_SHA256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"
LOCKED_BOUNDARY_SHA256 = "73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f"
LOCKED_CALAMARI_SHA256 = "020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37"
LOCKED_INPUT_HASHES = [
    LOCKED_IMPORT_PREVIEW_SHA256, LOCKED_DATABASE_PREVIEW_SHA256,
    LOCKED_PRODUCTION_MANIFEST_SHA256, LOCKED_BOUNDARY_SHA256, LOCKED_CALAMARI_SHA256,
]
EXPECTED_SOURCE_RECORDS = 592
EXPECTED_EXCLUDED_ALREADY_WRITTEN = 8
EXPECTED_ELEMENTS = 584
EXPECTED_CANONICAL_TARGETS = 543


class ManifestError(ValueError):
    pass


def _fail(code: str) -> None:
    raise ManifestError(code)


def artifact_sha(value: Any) -> str:
    return hashlib.sha256((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()).hexdigest()


def canonical_sha(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _validate_hashes(values: tuple[Any, ...], supplied: list[str]) -> None:
    if len(supplied) != len(values) or any(not re.fullmatch(r"[0-9a-f]{64}", x or "") for x in supplied):
        _fail("PHASE_A_MANIFEST_HASH_INVALID")
    if [artifact_sha(value) for value in values] != supplied:
        _fail("PHASE_A_MANIFEST_HASH_INVALID")


def _source_records(import_preview: dict[str, Any], calamari_sha256: str) -> dict[str, dict[str, Any]]:
    if (import_preview.get("schema_version") != "1939-v50-import-preview-v1" or
            import_preview.get("canonical_mutations_authorized") is not False or
            import_preview.get("source", {}).get("input_hashes", {}).get("calamari_sha256") != calamari_sha256):
        _fail("PHASE_A_MANIFEST_IMPORT_PREVIEW_INVALID")
    rows = import_preview.get("source_records")
    if not isinstance(rows, list):
        _fail("PHASE_A_MANIFEST_IMPORT_PREVIEW_INVALID")
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            _fail("PHASE_A_MANIFEST_IMPORT_PREVIEW_INVALID")
        key = row.get("new_record_key")
        span = row.get("source_span")
        text = row.get("verbatim_text")
        kind = row.get("record_kind")
        creation = row.get("person_creation")
        if (not isinstance(key, str) or not key or key in result or
                not isinstance(span, dict) or set(span) != {"char_from", "char_to"} or
                not isinstance(span.get("char_from"), int) or not isinstance(span.get("char_to"), int) or
                span["char_to"] <= span["char_from"] or
                not isinstance(text, str) or not text or
                kind not in {"unclassified", "structural_context", "cross_reference"} or
                creation not in {"requires_existing_anchor", "forbidden"}):
            _fail(f"PHASE_A_MANIFEST_SOURCE_RECORD_INVALID:{key}")
        result[key] = {
            "new_record_key": key, "record_kind": kind, "person_creation": creation,
            "source_span": {"char_from": span["char_from"], "char_to": span["char_to"]},
            "verbatim_text": text,
        }
    return result


def _excluded_keys(production_manifest: dict[str, Any], calamari_sha256: str) -> set[str]:
    if (production_manifest.get("schema_version") != "1939-v50-production-write-manifest-v1" or
            production_manifest.get("production_authorized") is not False or
            production_manifest.get("source", {}).get("rendition_content_sha256") != calamari_sha256):
        _fail("PHASE_A_MANIFEST_PRODUCTION_MANIFEST_INVALID")
    creates = production_manifest.get("person_creates")
    if not isinstance(creates, list):
        _fail("PHASE_A_MANIFEST_PRODUCTION_MANIFEST_INVALID")
    keys = []
    for row in creates:
        if not isinstance(row, dict) or not isinstance(row.get("source_record_key"), str):
            _fail("PHASE_A_MANIFEST_PRODUCTION_MANIFEST_INVALID")
        keys.append(row["source_record_key"])
    if len(set(keys)) != len(keys):
        _fail("PHASE_A_MANIFEST_PRODUCTION_MANIFEST_INVALID")
    return set(keys)


def _mapped_existing(import_preview: dict[str, Any]) -> dict[str, dict[str, str]]:
    rows = import_preview.get("mapped_existing")
    if not isinstance(rows, list):
        _fail("PHASE_A_MANIFEST_IMPORT_PREVIEW_INVALID")
    result: dict[str, dict[str, str]] = {}
    seen_baseline: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            _fail("PHASE_A_MANIFEST_IMPORT_PREVIEW_INVALID")
        key = row.get("new_record_key")
        baseline = row.get("baseline_record_key")
        legacy_name = row.get("legacy_name")
        # legacy_name er legitimt None for de navnløse baseline-poster (kendt,
        # ikke en datafejl) — men skal så være None, ikke en anden falsy type.
        if (not isinstance(key, str) or not key or key in result or
                not isinstance(baseline, str) or not baseline or baseline in seen_baseline or
                not (legacy_name is None or (isinstance(legacy_name, str) and legacy_name.strip()))):
            _fail("PHASE_A_MANIFEST_MAPPED_EXISTING_INVALID")
        seen_baseline.add(baseline)
        result[key] = {"baseline_record_key": baseline, "legacy_name": legacy_name}
    return result


def _person_anchors(database_preview: dict[str, Any], calamari_sha256: str) -> dict[str, int]:
    if (database_preview.get("schema_version") != "1939-v50-database-preview-v1" or
            database_preview.get("canonical_mutations_authorized") is not False or
            database_preview.get("input_preview", {}).get("input_hashes", {}).get("calamari_sha256") != calamari_sha256):
        _fail("PHASE_A_MANIFEST_DATABASE_PREVIEW_INVALID")
    anchors = database_preview.get("person_anchors", {})
    matched = anchors.get("matched")
    if (not isinstance(matched, list) or anchors.get("missing_count") != 0 or
            anchors.get("collision_count") != 0 or len(matched) != anchors.get("matched_count")):
        _fail("PHASE_A_MANIFEST_DATABASE_PREVIEW_INVALID")
    result: dict[str, int] = {}
    seen_person_ids: set[int] = set()
    for row in matched:
        if not isinstance(row, dict) or set(row) != {"baseline_record_key", "person_id"}:
            _fail("PHASE_A_MANIFEST_DATABASE_PREVIEW_INVALID")
        baseline, person_id = row["baseline_record_key"], row["person_id"]
        if (not isinstance(baseline, str) or not baseline or baseline in result or
                not isinstance(person_id, int) or person_id in seen_person_ids):
            _fail("PHASE_A_MANIFEST_DATABASE_PREVIEW_INVALID")
        seen_person_ids.add(person_id)
        result[baseline] = person_id
    return result


def _boundary_pages(boundary: dict[str, Any], source_records: dict[str, dict[str, Any]],
                     calamari_sha256: str) -> dict[str, dict[str, int]]:
    review = boundary.get("source_record_review") if isinstance(boundary, dict) else None
    if (not isinstance(review, dict) or boundary.get("schema_version") != "1.0" or
            review.get("schema_version") != "1.0" or review.get("source_id") != CALAMARI_SOURCE_ID or
            review.get("rendition_id") != CALAMARI_RENDITION_ID or
            review.get("rendition_sha256") != calamari_sha256 or
            not isinstance(review.get("records"), list)):
        _fail("PHASE_A_MANIFEST_BOUNDARY_INVALID")
    by_anchor: dict[tuple[int, int], dict[str, Any]] = {}
    for row in review["records"]:
        if not isinstance(row, dict):
            _fail("PHASE_A_MANIFEST_BOUNDARY_INVALID")
        anchor = row.get("source_anchor")
        span = row.get("span")
        if (not isinstance(anchor, dict) or set(anchor) != {"char_from", "char_to"} or
                not isinstance(span, dict) or not isinstance(span.get("page_from"), int) or
                not isinstance(span.get("page_to"), int) or span["page_from"] < 1 or
                span["page_to"] < span["page_from"] or
                not isinstance(row.get("verbatim_text"), str)):
            _fail("PHASE_A_MANIFEST_BOUNDARY_INVALID")
        anchor_key = (anchor["char_from"], anchor["char_to"])
        if anchor_key in by_anchor:
            _fail("PHASE_A_MANIFEST_BOUNDARY_INVALID")
        by_anchor[anchor_key] = row
    result: dict[str, dict[str, int]] = {}
    for key, source in source_records.items():
        span = source["source_span"]
        row = by_anchor.get((span["char_from"], span["char_to"]))
        if row is None or row.get("verbatim_text") != source["verbatim_text"]:
            _fail(f"PHASE_A_MANIFEST_BOUNDARY_LOOKUP_FAILED:{key}")
        result[key] = {"page_from": row["span"]["page_from"], "page_to": row["span"]["page_to"]}
    return result


def _build_phase_a_anchor_manifest(
    import_preview: dict[str, Any], database_preview: dict[str, Any],
    production_manifest: dict[str, Any], boundary: dict[str, Any], calamari_text: str,
    *, input_hashes: list[str],
    expected_source_records: int | None = None,
    expected_excluded: int | None = None,
    expected_elements: int | None = None,
    expected_canonical_targets: int | None = None,
) -> dict[str, Any]:
    if not isinstance(calamari_text, str) or not calamari_text:
        _fail("PHASE_A_MANIFEST_CALAMARI_INVALID")
    if len(input_hashes) != 5 or not HASH_RE.fullmatch(input_hashes[4] or ""):
        _fail("PHASE_A_MANIFEST_HASH_INVALID")
    calamari_sha256 = input_hashes[4]
    _validate_hashes((import_preview, database_preview, production_manifest, boundary), input_hashes[:4])

    source_records = _source_records(import_preview, calamari_sha256)
    if expected_source_records is not None and len(source_records) != expected_source_records:
        _fail("PHASE_A_MANIFEST_ARITHMETIC_MISMATCH")
    excluded_keys = _excluded_keys(production_manifest, calamari_sha256)
    if expected_excluded is not None and len(excluded_keys) != expected_excluded:
        _fail("PHASE_A_MANIFEST_ARITHMETIC_MISMATCH")
    missing_excluded = excluded_keys - set(source_records)
    if missing_excluded:
        _fail(f"PHASE_A_MANIFEST_EXCLUDED_KEY_MISSING:{sorted(missing_excluded)[0]}")

    mapped_existing = _mapped_existing(import_preview)
    person_anchors = _person_anchors(database_preview, calamari_sha256)

    kept_keys = {key: row for key, row in source_records.items() if key not in excluded_keys}
    expected_element_count = len(source_records) - len(excluded_keys)
    if len(kept_keys) != expected_element_count:
        _fail("PHASE_A_MANIFEST_ARITHMETIC_MISMATCH")
    if expected_elements is not None and len(kept_keys) != expected_elements:
        _fail("PHASE_A_MANIFEST_ARITHMETIC_MISMATCH")

    page_evidence_by_key = _boundary_pages(boundary, kept_keys, calamari_sha256)

    operations: list[dict[str, Any]] = []
    canonical_target_count = 0
    for key, row in kept_keys.items():
        span = row["source_span"]
        verbatim_text = row["verbatim_text"]
        if calamari_text[span["char_from"]:span["char_to"]] != verbatim_text:
            _fail(f"PHASE_A_MANIFEST_SPAN_MISMATCH:{key}")
        category = "person" if row["record_kind"] == "unclassified" else row["record_kind"]
        payload: dict[str, Any] = {
            "review_subject_id": key,
            "source_record_key": key,
            "category": category,
            "disposition": "retain_source_only",
        }
        if row["person_creation"] == "requires_existing_anchor":
            mapping = mapped_existing.get(key)
            if mapping is None:
                _fail(f"PHASE_A_MANIFEST_ANCHOR_LOOKUP_FAILED:{key}")
            baseline_record_key = mapping["baseline_record_key"]
            person_id = person_anchors.get(baseline_record_key)
            if person_id is None:
                _fail(f"PHASE_A_MANIFEST_ANCHOR_LOOKUP_FAILED:{key}")
            payload["canonical_target"] = {"person_id": person_id}
            payload["legacy_payload"] = {
                "baseline_record_key": baseline_record_key,
                "legacy_name": mapping["legacy_name"],
            }
            canonical_target_count += 1
        payload["source_span"] = dict(span)
        payload["page_evidence"] = dict(page_evidence_by_key[key])
        payload["verbatim_text"] = verbatim_text
        payload["rendition_content_sha256"] = calamari_sha256
        if set(payload) - SQL_PAYLOAD_KEYS:
            _fail(f"PHASE_A_MANIFEST_PAYLOAD_KEY_INVALID:{key}")
        payload["evidence_sha256"] = canonical_sha(payload)
        operations.append({
            "element_id": f"phase-a:{key}",
            "dependency_class": "source_evidence",
            **payload,
        })

    operations.sort(key=lambda op: op["element_id"])
    if len(set(op["element_id"] for op in operations)) != len(operations):
        _fail("PHASE_A_MANIFEST_ARITHMETIC_MISMATCH")
    if expected_canonical_targets is not None and canonical_target_count != expected_canonical_targets:
        _fail("PHASE_A_MANIFEST_ARITHMETIC_MISMATCH")

    counts = {
        "person_creates": 0,
        "source_evidence": len(operations),
        "canonical_delta": 0,
    }
    manifest = {
        "schema_version": "1939-v50-phase-a-anchor-manifest-v1",
        "generator_version": "build_phase_a_anchor_manifest_1939_v50.py:v1",
        "input_hashes": {
            "import_preview_sha256": input_hashes[0],
            "database_preview_sha256": input_hashes[1],
            "production_manifest_sha256": input_hashes[2],
            "boundary_sha256": input_hashes[3],
            "calamari_sha256": input_hashes[4],
        },
        "source": {
            "edition": "1939", "logical_source_id": "1939", "database_source_id": 3,
            "rendition_content_sha256": calamari_sha256,
        },
        "arithmetic": {
            "source_records": len(source_records),
            "excluded_already_written": len(excluded_keys),
            "elements": len(operations),
            "canonical_targets": canonical_target_count,
        },
        "operations": operations,
        "counts": counts,
        "expected_changes": {
            "persons_created": 0, "source_evidence_written": len(operations),
            "canonical_rows_changed": 0, "persons_activated": 0,
        },
        "production_authorized": False, "apply_gate": "NO-GO",
    }
    manifest["manifest_content_sha256"] = canonical_sha(manifest)
    return manifest


def build_phase_a_anchor_manifest(import_preview, database_preview, production_manifest,
                                   boundary, calamari_text, *, input_hashes):
    """Public entrypoint — pins the production universe (hashes + aritmetik).

    Denne funktion accepterer KUN de låste 2026-08-18-hashes og den låste
    592/8/584/543-aritmetik fra task-1-context.md. Fixtures/tests, der ønsker
    andre tal, skal kalde `_build_phase_a_anchor_manifest` direkte.
    """
    if list(input_hashes) != LOCKED_INPUT_HASHES:
        _fail("PHASE_A_MANIFEST_HASH_NOT_LOCKED")
    return _build_phase_a_anchor_manifest(
        import_preview, database_preview, production_manifest, boundary, calamari_text,
        input_hashes=input_hashes,
        expected_source_records=EXPECTED_SOURCE_RECORDS,
        expected_excluded=EXPECTED_EXCLUDED_ALREADY_WRITTEN,
        expected_elements=EXPECTED_ELEMENTS,
        expected_canonical_targets=EXPECTED_CANONICAL_TARGETS,
    )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    for name in ("import-preview", "database-preview", "production-manifest", "boundary", "calamari"):
        p.add_argument(f"--{name}", required=True)
        p.add_argument(f"--{name}-sha256", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args(argv)
    out = Path(a.output)
    if out.exists():
        _fail("PHASE_A_MANIFEST_OUTPUT_EXISTS")
    paths = [a.import_preview, a.database_preview, a.production_manifest, a.boundary, a.calamari]
    supplied = [
        a.import_preview_sha256, a.database_preview_sha256, a.production_manifest_sha256,
        a.boundary_sha256, a.calamari_sha256,
    ]
    raw = [Path(path).read_bytes() for path in paths]
    if [hashlib.sha256(x).hexdigest() for x in raw] != supplied:
        _fail("PHASE_A_MANIFEST_HASH_INVALID")
    import_preview, database_preview, production_manifest, boundary = (json.loads(x) for x in raw[:4])
    calamari_text = raw[4].decode("utf-8")
    result = build_phase_a_anchor_manifest(
        import_preview, database_preview, production_manifest, boundary, calamari_text,
        input_hashes=supplied,
    )
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(out), "counts": result["counts"],
                       "arithmetic": result["arithmetic"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    main()
