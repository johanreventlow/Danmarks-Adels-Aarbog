#!/usr/bin/env python3
"""Materialize fail-closed DAA 1939 v50 provenance dispositions."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1939-v50-provenance-decisions-v1"
PRODUCTION_COUNTS = {"facts": 130, "marriages": 94, "relationships": 81}
DISPOSITIONS = (
    "promote_canonical",
    "retain_source_only",
    "retire_1939_projection",
    "unresolved",
)
HASH_RE = re.compile(r"^[0-9a-f]{64}$")


class ProvenanceDecisionError(ValueError):
    pass


def _fail(code: str) -> None:
    raise ProvenanceDecisionError(code)


def _artifact_digest(value: Any) -> str:
    return hashlib.sha256(
        (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    ).hexdigest()


def _canonical_digest(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def _validate_review(review: Any, expected_counts: dict[str, int]) -> list[dict[str, Any]]:
    keys = {
        "schema_version", "generator_version", "input_hashes", "source", "counts",
        "new_person_candidate_keys", "review_only", "review_gate", "decision_gate",
        "database_write_authorized", "canonical_mutations_authorized", "reimport_gate",
        "subjects",
    }
    if not isinstance(review, dict) or set(review) != keys:
        _fail("PROVENANCE_REVIEW_SCHEMA_INVALID")
    if (review["schema_version"] != "1939-v50-provenance-review-v1" or
            review["review_only"] is not True or review["review_gate"] != "GO" or
            review["decision_gate"] != "NO-GO" or review["reimport_gate"] != "NO-GO" or
            review["database_write_authorized"] is not False or
            review["canonical_mutations_authorized"] is not False):
        _fail("PROVENANCE_REVIEW_STATE_INVALID")
    counts = review["counts"]
    expected_count_keys = {"facts", "marriages", "relationships", "subjects", "mapped_profiles", "new_person_candidates"}
    if not isinstance(counts, dict) or set(counts) != expected_count_keys:
        _fail("PROVENANCE_REVIEW_COUNTS_INVALID")
    if any(isinstance(v, bool) or not isinstance(v, int) or v < 0 for v in counts.values()):
        _fail("PROVENANCE_REVIEW_COUNTS_INVALID")
    if any(counts[k] != expected_counts[k] for k in expected_counts) or counts["subjects"] != sum(expected_counts.values()):
        _fail("PROVENANCE_REVIEW_COUNTS_INVALID")
    if not isinstance(review["input_hashes"], dict) or not review["input_hashes"] or any(
            not isinstance(v, str) or not HASH_RE.fullmatch(v) for v in review["input_hashes"].values()):
        _fail("PROVENANCE_REVIEW_LINEAGE_INVALID")
    subjects = review["subjects"]
    if not isinstance(subjects, list) or len(subjects) != counts["subjects"]:
        _fail("PROVENANCE_REVIEW_SUBJECTS_INVALID")
    subject_keys = {
        "review_subject_id", "category", "baseline_record_key", "source_record_key",
        "source_order", "object_order", "provenance_status", "legacy_payload",
        "source_span", "verbatim_text", "page_evidence", "canonical_target",
        "database_context", "evidence_signals", "proposed_disposition",
    }
    seen: set[str] = set()
    category_counts = {"fact": 0, "marriage": 0, "relationship": 0}
    prior = None
    for row in subjects:
        if not isinstance(row, dict) or set(row) != subject_keys:
            _fail("PROVENANCE_REVIEW_SUBJECT_INVALID")
        sid = row["review_subject_id"]
        if not isinstance(sid, str) or not sid or sid in seen:
            _fail("PROVENANCE_REVIEW_SUBJECT_INVALID")
        seen.add(sid)
        category = row["category"]
        if category not in category_counts:
            _fail("PROVENANCE_REVIEW_CATEGORY_INVALID")
        category_counts[category] += 1
        order = ({"fact": 0, "marriage": 1, "relationship": 2}[category], row["source_order"], row["object_order"], row["source_record_key"])
        if prior is not None and order < prior:
            _fail("PROVENANCE_REVIEW_ORDER_INVALID")
        prior = order
        if row["proposed_disposition"] != "unresolved":
            _fail("PROVENANCE_REVIEW_AUTHORITY_INVALID")
        span = row["source_span"]
        if (not isinstance(span, dict) or set(span) != {"char_from", "char_to"} or
                not isinstance(span["char_from"], int) or not isinstance(span["char_to"], int) or
                span["char_from"] < 0 or span["char_to"] <= span["char_from"] or
                not isinstance(row["verbatim_text"], str) or not row["verbatim_text"]):
            _fail("PROVENANCE_REVIEW_EVIDENCE_INVALID")
    if category_counts != {"fact": expected_counts["facts"], "marriage": expected_counts["marriages"], "relationship": expected_counts["relationships"]}:
        _fail("PROVENANCE_REVIEW_COUNTS_INVALID")
    return subjects


def _validate_operation(disposition: str, operations: Any) -> list[dict[str, Any]]:
    if not isinstance(operations, list):
        _fail("PROVENANCE_DECISION_OPERATION_INVALID")
    if disposition in {"retain_source_only", "unresolved"} and operations:
        _fail("PROVENANCE_DECISION_OPERATION_FORBIDDEN")
    if disposition in {"promote_canonical", "retire_1939_projection"} and not operations:
        _fail("PROVENANCE_DECISION_OPERATION_REQUIRED")
    # Canonical operations are intentionally unsupported until individually reviewed.
    if operations:
        _fail("PROVENANCE_DECISION_CANONICAL_REVIEW_REQUIRED")
    return []


def _materialize_provenance_decisions(
    review: dict[str, Any], proposal: dict[str, Any], *, expected_counts: dict[str, int]
) -> dict[str, Any]:
    subjects = _validate_review(review, expected_counts)
    proposal_keys = {"schema_version", "review_sha256", "review_only", "database_write_authorized", "decisions"}
    if not isinstance(proposal, dict) or set(proposal) != proposal_keys:
        _fail("PROVENANCE_PROPOSAL_SCHEMA_INVALID")
    if (proposal["schema_version"] != "1939-v50-provenance-proposals-v1" or
            proposal["review_only"] is not True or proposal["database_write_authorized"] is not False or
            proposal["review_sha256"] != _artifact_digest(review)):
        _fail("PROVENANCE_PROPOSAL_LINEAGE_INVALID")
    rows = proposal["decisions"]
    if not isinstance(rows, list) or len(rows) != len(subjects):
        _fail("PROVENANCE_PROPOSAL_COVERAGE_INVALID")
    row_keys = {"review_subject_id", "disposition", "resolution_basis", "canonical_operations"}
    output_rows = []
    disposition_counts = {key: 0 for key in DISPOSITIONS}
    for subject, decision in zip(subjects, rows):
        if not isinstance(decision, dict) or set(decision) != row_keys:
            _fail("PROVENANCE_DECISION_SCHEMA_INVALID")
        if decision["review_subject_id"] != subject["review_subject_id"]:
            _fail("PROVENANCE_DECISION_ORDER_INVALID")
        disposition = decision["disposition"]
        if disposition not in DISPOSITIONS:
            _fail("PROVENANCE_DECISION_DISPOSITION_INVALID")
        basis = decision["resolution_basis"]
        if not isinstance(basis, str) or not basis:
            _fail("PROVENANCE_DECISION_BASIS_INVALID")
        operations = _validate_operation(disposition, decision["canonical_operations"])
        evidence_sha = _canonical_digest({
            "review_subject": subject,
            "disposition": disposition,
            "resolution_basis": basis,
        })
        output_rows.append({
            "review_subject_id": subject["review_subject_id"],
            "category": subject["category"],
            "source_record_key": subject["source_record_key"],
            "canonical_target": subject["canonical_target"],
            "source_span": subject["source_span"],
            "page_evidence": subject["page_evidence"],
            "verbatim_text": subject["verbatim_text"],
            "legacy_payload": subject["legacy_payload"],
            "disposition": disposition,
            "resolution_basis": basis,
            "canonical_operations": operations,
            "evidence_sha256": evidence_sha,
        })
        disposition_counts[disposition] += 1
    counts = {**expected_counts, "subjects": len(subjects), **disposition_counts}
    unresolved = disposition_counts["unresolved"]
    return {
        "schema_version": SCHEMA_VERSION,
        "generator_version": "materialize_provenance_decisions_1939_v50.py:v1",
        "input_hashes": {**review["input_hashes"], "review_sha256": _artifact_digest(review), "proposal_sha256": _artifact_digest(proposal)},
        "source": review["source"],
        "counts": counts,
        "decisions": output_rows,
        "decision_gate": "GO" if unresolved == 0 else "NO-GO",
        "production_authorized": False,
        "database_write_authorized": False,
        "reimport_gate": "NO-GO",
    }


def materialize_provenance_decisions(review: dict[str, Any], proposal: dict[str, Any]) -> dict[str, Any]:
    return _materialize_provenance_decisions(review, proposal, expected_counts=PRODUCTION_COUNTS)


def _build_conservative_proposal(review: dict[str, Any], *, expected_counts: dict[str, int]) -> dict[str, Any]:
    subjects = _validate_review(review, expected_counts)
    return {
        "schema_version": "1939-v50-provenance-proposals-v1",
        "review_sha256": _artifact_digest(review),
        "review_only": True,
        "database_write_authorized": False,
        "decisions": [
            {
                "review_subject_id": row["review_subject_id"],
                "disposition": "retain_source_only",
                "resolution_basis": "conservative_no_atomic_positive_canonical_evidence",
                "canonical_operations": [],
            }
            for row in subjects
        ],
    }


def build_conservative_proposal(review: dict[str, Any]) -> dict[str, Any]:
    return _build_conservative_proposal(review, expected_counts=PRODUCTION_COUNTS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--review", required=True)
    parser.add_argument("--review-sha256", required=True)
    parser.add_argument("--proposal")
    parser.add_argument("--proposal-sha256")
    parser.add_argument("--build-conservative-proposal", action="store_true")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output)
    if output.exists():
        _fail("PROVENANCE_DECISION_OUTPUT_EXISTS")
    review_bytes = Path(args.review).read_bytes()
    if hashlib.sha256(review_bytes).hexdigest() != args.review_sha256:
        _fail("PROVENANCE_DECISION_INPUT_HASH_INVALID")
    review = json.loads(review_bytes)
    if args.build_conservative_proposal:
        if args.proposal is not None or args.proposal_sha256 is not None:
            _fail("PROVENANCE_DECISION_CLI_INVALID")
        result = build_conservative_proposal(review)
    else:
        if args.proposal is None or args.proposal_sha256 is None:
            _fail("PROVENANCE_DECISION_CLI_INVALID")
        proposal_bytes = Path(args.proposal).read_bytes()
        if hashlib.sha256(proposal_bytes).hexdigest() != args.proposal_sha256:
            _fail("PROVENANCE_DECISION_INPUT_HASH_INVALID")
        result = materialize_provenance_decisions(review, json.loads(proposal_bytes))
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
