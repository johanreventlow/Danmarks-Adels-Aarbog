from __future__ import annotations

import copy
import hashlib
import json

import pytest

from materialize_provenance_decisions_1939_v50 import (
    ProvenanceDecisionError,
    _materialize_provenance_decisions,
    _build_conservative_proposal,
)


def digest(value):
    return hashlib.sha256(
        (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
    ).hexdigest()


def subject(category="fact", order=0):
    return {
        "review_subject_id": f"provenance-{order:032x}",
        "category": category,
        "baseline_record_key": f"baseline-{order}",
        "source_record_key": f"record-{order}",
        "source_order": order,
        "object_order": 0,
        "provenance_status": "missing_provenance",
        "legacy_payload": {"value": str(order)},
        "source_span": {"char_from": order * 10, "char_to": order * 10 + 5},
        "verbatim_text": "tekst",
        "page_evidence": {"page_from": 1, "page_to": 1},
        "canonical_target": {
            "baseline_record_key": f"baseline-{order}",
            "canonical_person_id": order + 1,
            "display_name": "Navn",
            "staged": False,
        },
        "database_context": [],
        "evidence_signals": [],
        "proposed_disposition": "unresolved",
    }


def review():
    subjects = [subject("fact", 0), subject("marriage", 1), subject("relationship", 2)]
    return {
        "schema_version": "1939-v50-provenance-review-v1",
        "generator_version": "test",
        "input_hashes": {"input_sha256": "a" * 64},
        "source": {"edition": "1939", "logical_source_id": "1939", "database_source_id": 3, "rendition_id": "r"},
        "counts": {"facts": 1, "marriages": 1, "relationships": 1, "subjects": 3, "mapped_profiles": 1, "new_person_candidates": 0},
        "new_person_candidate_keys": [],
        "review_only": True,
        "review_gate": "GO",
        "decision_gate": "NO-GO",
        "database_write_authorized": False,
        "canonical_mutations_authorized": False,
        "reimport_gate": "NO-GO",
        "subjects": subjects,
    }


def proposal(review_value):
    return {
        "schema_version": "1939-v50-provenance-proposals-v1",
        "review_sha256": digest(review_value),
        "review_only": True,
        "database_write_authorized": False,
        "decisions": [
            {
                "review_subject_id": row["review_subject_id"],
                "disposition": "retain_source_only",
                "resolution_basis": "conservative_no_atomic_positive_canonical_evidence",
                "canonical_operations": [],
            }
            for row in review_value["subjects"]
        ],
    }


def build():
    r = review()
    return _materialize_provenance_decisions(r, proposal(r), expected_counts={"facts": 1, "marriages": 1, "relationships": 1})


def test_retain_source_only_is_closed_and_no_go_for_writes():
    out = build()
    assert out["counts"] == {"facts": 1, "marriages": 1, "relationships": 1, "subjects": 3, "promote_canonical": 0, "retain_source_only": 3, "retire_1939_projection": 0, "unresolved": 0}
    assert out["decision_gate"] == "GO"
    assert out["production_authorized"] is False
    assert all(row["canonical_operations"] == [] for row in out["decisions"])
    assert all(len(row["evidence_sha256"]) == 64 for row in out["decisions"])


@pytest.mark.parametrize("mutation", [
    lambda p: p.update(review_sha256="b" * 64),
    lambda p: p["decisions"].append(copy.deepcopy(p["decisions"][0])),
    lambda p: p["decisions"][0].update(disposition="unknown"),
    lambda p: p["decisions"][0].update(canonical_operations=[{"operation": "write"}]),
    lambda p: p.update(database_write_authorized=True),
])
def test_proposal_mutations_fail_closed(mutation):
    r = review()
    p = proposal(r)
    mutation(p)
    with pytest.raises(ProvenanceDecisionError):
        _materialize_provenance_decisions(r, p, expected_counts={"facts": 1, "marriages": 1, "relationships": 1})


def test_unresolved_keeps_gate_closed():
    r = review()
    p = proposal(r)
    p["decisions"][0]["disposition"] = "unresolved"
    p["decisions"][0]["resolution_basis"] = "needs_review"
    out = _materialize_provenance_decisions(r, p, expected_counts={"facts": 1, "marriages": 1, "relationships": 1})
    assert out["decision_gate"] == "NO-GO"


def test_review_subject_or_counts_drift_fails_closed():
    r = review()
    p = proposal(r)
    r["subjects"][0]["verbatim_text"] = "drift"
    with pytest.raises(ProvenanceDecisionError):
        _materialize_provenance_decisions(r, p, expected_counts={"facts": 1, "marriages": 1, "relationships": 1})


def test_conservative_proposal_preserves_order_and_has_no_write_operations():
    r = review()
    out = _build_conservative_proposal(r, expected_counts={"facts": 1, "marriages": 1, "relationships": 1})
    assert [row["review_subject_id"] for row in out["decisions"]] == [row["review_subject_id"] for row in r["subjects"]]
    assert {row["disposition"] for row in out["decisions"]} == {"retain_source_only"}
    assert all(row["canonical_operations"] == [] for row in out["decisions"])
