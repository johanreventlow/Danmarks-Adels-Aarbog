#!/usr/bin/env python3
"""Compile the closed, non-authorizing DAA 1939 v50 production manifest."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import uuid
from pathlib import Path
from typing import Any


PRODUCTION_NEW_NAMES = {
    "record-3766faae-ae21-412a-8cfb-745a19ac77f0": "Ditlev",
    "record-43d4974a-0532-421d-a3fb-8e7c575a67e7": "Gerhard (Gherardus de Reventlow)",
    "record-8f346104-cf3c-465f-bfa3-efb78be436b2": "Iven (Ywanus de Reuentlo)",
    "record-b626f5ff-f2fb-4061-bfce-988dbddec846": "Henrik",
    "record-80180a6e-2cc6-4968-81ca-004b6662d8ce": "Henning",
    "record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58": "Henning",
    "record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422": "Henning Reventlow",
    "record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d": "Margrethe",
}


class ManifestError(ValueError):
    pass


def _fail(code: str) -> None:
    raise ManifestError(code)


def artifact_sha(value: Any) -> str:
    return hashlib.sha256((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()).hexdigest()


def canonical_sha(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def persona_id(key: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"daa:source-persona:1939:{key}"))


def _validate_hashes(values: tuple[Any, ...], supplied: list[str]) -> None:
    if len(supplied) != len(values) or any(not re.fullmatch(r"[0-9a-f]{64}", x or "") for x in supplied):
        _fail("PRODUCTION_MANIFEST_HASH_INVALID")
    if [artifact_sha(value) for value in values] != supplied:
        _fail("PRODUCTION_MANIFEST_HASH_INVALID")


def _build_manifest(
    source_personas: dict[str, Any], identity_review: dict[str, Any],
    identity_decisions: dict[str, Any], provenance_decisions: dict[str, Any],
    database_preview: dict[str, Any], *, input_hashes: list[str],
    expected_existing: int, expected_new: int, expected_provenance: int,
    allowed_new_keys: set[str],
) -> dict[str, Any]:
    values = (source_personas, identity_review, identity_decisions, provenance_decisions, database_preview)
    _validate_hashes(values, input_hashes)
    if (source_personas.get("schema_version") != "1939-v50-source-persona-materialization-v2" or
            source_personas.get("database_write_authorized") is not False or
            identity_review.get("schema_version") != "1939-v50-remaining-identity-review-v1" or
            identity_review.get("database_write_authorized") is not False or
            identity_decisions.get("schema_version") != "1939-v50-remaining-identity-decisions-v1" or
            identity_decisions.get("database_write_authorized") is not False or
            provenance_decisions.get("schema_version") != "1939-v50-provenance-decisions-v1" or
            provenance_decisions.get("production_authorized") is not False or
            provenance_decisions.get("database_write_authorized") is not False or
            database_preview.get("schema_version") != "1939-v50-database-preview-v3" or
            database_preview.get("canonical_mutations_authorized") is not False or
            database_preview.get("expected_database_changes", {}).get("authorized") is not False):
        _fail("PRODUCTION_MANIFEST_INPUT_STATE_INVALID")
    anchors = database_preview.get("person_anchors", {})
    matched = anchors.get("matched")
    if (not isinstance(matched, list) or anchors.get("matched_count") != expected_existing or
            anchors.get("missing_count") != 0 or anchors.get("collision_count") != 0 or
            len(matched) != expected_existing):
        _fail("PRODUCTION_MANIFEST_ANCHORS_INVALID")
    anchor_keys, anchor_ids = set(), set()
    for row in matched:
        if set(row) != {"baseline_record_key", "person_id"} or row["baseline_record_key"] in anchor_keys or row["person_id"] in anchor_ids:
            _fail("PRODUCTION_MANIFEST_ANCHORS_INVALID")
        anchor_keys.add(row["baseline_record_key"]); anchor_ids.add(row["person_id"])
    candidates = source_personas.get("new_person_candidates")
    if not isinstance(candidates, list) or len(candidates) != expected_new or source_personas.get("counts", {}).get("new_person_candidate") != expected_new:
        _fail("PRODUCTION_MANIFEST_NEW_UNIVERSE_INVALID")
    candidate_by_key = {row.get("source_record_key"): row for row in candidates}
    if set(candidate_by_key) != allowed_new_keys or len(candidate_by_key) != len(candidates):
        _fail("PRODUCTION_MANIFEST_NEW_UNIVERSE_INVALID")
    review_rows = identity_review.get("subjects")
    if not isinstance(review_rows, list):
        _fail("PRODUCTION_MANIFEST_IDENTITY_EVIDENCE_INVALID")
    review_by_key = {row.get("new_record_key"): row for row in review_rows if row.get("new_record_key") in allowed_new_keys}
    decision_rows = identity_decisions.get("decisions")
    if (not isinstance(decision_rows, list) or identity_decisions.get("counts", {}).get("new_person_candidate") != expected_new or
            identity_decisions.get("counts", {}).get("unresolved") != 0):
        _fail("PRODUCTION_MANIFEST_IDENTITY_DECISIONS_INVALID")
    decision_by_key = {row.get("source_record_key"): row for row in decision_rows if row.get("decision") == "new_person_candidate"}
    if set(review_by_key) != allowed_new_keys or set(decision_by_key) != allowed_new_keys:
        _fail("PRODUCTION_MANIFEST_IDENTITY_EVIDENCE_INVALID")
    creates = []
    for key in sorted(allowed_new_keys):
        candidate, review, decision = candidate_by_key[key], review_by_key[key], decision_by_key[key]
        text, span = review.get("verbatim_text"), review.get("source_span")
        if (not isinstance(text, str) or not text or span != candidate.get("source_span") or span != decision.get("source_span") or
                hashlib.sha256(text.encode()).hexdigest() != candidate.get("verbatim_sha256") or
                candidate.get("verbatim_sha256") != decision.get("verbatim_sha256") or
                decision.get("review_status") != "codex_verified"):
            _fail("PRODUCTION_MANIFEST_IDENTITY_EVIDENCE_INVALID")
        name = PRODUCTION_NEW_NAMES.get(key)
        if name is None:
            # Fixture-only derivation; production uses the locked names above.
            name = re.sub(r"^\s*\d+\.\s*", "", text).split(",", 1)[0].strip()
        create = {
            "element_id": f"person-create:{key}", "dependency_class": "person_create",
            "source_record_key": key, "source_id": 3, "edition": "1939",
            "source_span": span, "verbatim_text": text,
            "verbatim_sha256": hashlib.sha256(text.encode()).hexdigest(),
            "source_persona_id": persona_id(key), "persona_key": f"1939:{key}",
            "identity_decision_sha256": input_hashes[2], "review_sha256": decision.get("review_sha256"),
            "decision_basis": decision.get("reason"), "name": name, "sex": None,
            "narrative": {"text": text, "source_record_key": key},
            "source_mentions": [{"kind": "person", "text": name, "source_record_key": key}],
            "persona_mention_links": [{"source_persona_id": persona_id(key), "source_record_key": key}],
            "facts": [], "relations": [], "families": [], "uncertainties": [],
            "staged": True,
        }
        if key == "record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d" and (create["sex"] is not None or create["facts"]):
            _fail("PRODUCTION_MANIFEST_FABRICATED_FIELD")
        creates.append(create)
    prov_rows = provenance_decisions.get("decisions")
    if (not isinstance(prov_rows, list) or len(prov_rows) != expected_provenance or
            provenance_decisions.get("counts", {}).get("subjects") != expected_provenance or
            provenance_decisions.get("counts", {}).get("unresolved") != 0):
        _fail("PRODUCTION_MANIFEST_PROVENANCE_INVALID")
    evidence_ops, canonical_delta = [], []
    seen_subjects = set()
    for row in prov_rows:
        sid = row.get("review_subject_id")
        if not isinstance(sid, str) or sid in seen_subjects:
            _fail("PRODUCTION_MANIFEST_PROVENANCE_INVALID")
        seen_subjects.add(sid)
        if row.get("disposition") == "retain_source_only" and row.get("canonical_operations") == []:
            evidence_ops.append({
                "element_id": f"source-evidence:{sid}", "dependency_class": "source_evidence",
                "review_subject_id": sid, "source_record_key": row.get("source_record_key"),
                "category": row.get("category"), "disposition": "retain_source_only",
                "evidence_sha256": row.get("evidence_sha256"),
            })
        elif row.get("disposition") in {"promote_canonical", "retire_1939_projection"}:
            canonical_delta.extend(row.get("canonical_operations", []))
        else:
            _fail("PRODUCTION_MANIFEST_PROVENANCE_INVALID")
    operations = sorted([*evidence_ops, *creates], key=lambda x: ({"source_evidence": 0, "person_create": 1, "canonical_delta": 2}[x["dependency_class"]], x["element_id"]))
    manifest = {
        "schema_version": "1939-v50-production-write-manifest-v1",
        "generator_version": "build_production_write_manifest_1939_v50.py:v1",
        "input_hashes": {
            "source_persona_v2_sha256": input_hashes[0], "remaining_identity_review_sha256": input_hashes[1],
            "remaining_identity_decisions_sha256": input_hashes[2], "provenance_decisions_sha256": input_hashes[3],
            "database_preview_v3_sha256": input_hashes[4],
        },
        "source": {"edition": "1939", "logical_source_id": "1939", "database_source_id": 3},
        "expected_database_contract": {"postgres_major": 17, "writer_contract": "1939-v50-production-writer-v1"},
        "existing_anchors": matched, "person_creates": creates,
        "provenance_dispositions": prov_rows, "canonical_delta": canonical_delta,
        "operations": operations,
        "counts": {"existing_anchors": expected_existing, "person_creates": expected_new, "provenance_dispositions": expected_provenance, "source_evidence_operations": len(evidence_ops), "canonical_delta": len(canonical_delta), "operations": len(operations)},
        "expected_changes": {"persons_created": expected_new, "source_evidence_written": len(evidence_ops), "canonical_rows_changed": len(canonical_delta), "persons_activated": 0},
        "production_authorized": False, "apply_gate": "NO-GO", "cutover_gate": "NO-GO",
    }
    manifest["manifest_content_sha256"] = canonical_sha(manifest)
    return manifest


def build_manifest(source_personas, identity_review, identity_decisions, provenance_decisions, database_preview, *, input_hashes):
    return _build_manifest(source_personas, identity_review, identity_decisions, provenance_decisions, database_preview,
        input_hashes=input_hashes, expected_existing=543, expected_new=8, expected_provenance=305,
        allowed_new_keys=set(PRODUCTION_NEW_NAMES))


def main() -> None:
    p = argparse.ArgumentParser()
    for name in ("source-personas", "identity-review", "identity-decisions", "provenance-decisions", "database-preview"):
        p.add_argument(f"--{name}", required=True); p.add_argument(f"--{name}-sha256", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args(); out = Path(a.output)
    if out.exists(): _fail("PRODUCTION_MANIFEST_OUTPUT_EXISTS")
    paths = [a.source_personas, a.identity_review, a.identity_decisions, a.provenance_decisions, a.database_preview]
    supplied = [a.source_personas_sha256, a.identity_review_sha256, a.identity_decisions_sha256, a.provenance_decisions_sha256, a.database_preview_sha256]
    raw = [Path(path).read_bytes() for path in paths]
    if [hashlib.sha256(x).hexdigest() for x in raw] != supplied: _fail("PRODUCTION_MANIFEST_HASH_INVALID")
    result = build_manifest(*(json.loads(x) for x in raw), input_hashes=supplied)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
