from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

import pytest

import materialize_identity_decisions_1939_v50 as subject


def sha_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def fixture():
    review = {
        "schema_version": "1939-v50-identity-review-v1",
        "generator_version": "builder:v1",
        "input_hashes": {"x": "a" * 64},
        "review_only": True,
        "review_state": "pending",
        "canonical_mutations_authorized": False,
        "counts": {"subjects": 2, "profiles": 2, "candidate_links": 2},
        "profiles": [
            {"record_key": "old-a", "person_id": 101, "display_name": "Anna"},
            {"record_key": "old-b", "person_id": 102, "display_name": "Bent"},
        ],
        "subjects": [
            {"new_record_key": "new-a", "review_state": "pending",
             "person_creation": "forbidden", "source_span": {"char_from": 1, "char_to": 5},
             "verbatim_text": "Anna", "candidates": [{
                 "candidate_record_key": "old-a", "candidate_person_id": 101,
                 "candidate_display_name": "Anna", "classification": "review_candidate",
                 "proposed_action": "unresolved", "signals": [{"kind": "literal_name"}],
                 "competing_candidate_record_keys": [], "competing_subject_record_keys": [],
             }]},
            {"new_record_key": "new-b", "review_state": "pending",
             "person_creation": "forbidden", "source_span": {"char_from": 6, "char_to": 10},
             "verbatim_text": "Bent", "candidates": [{
                 "candidate_record_key": "old-b", "candidate_person_id": 102,
                 "candidate_display_name": "Bent", "classification": "review_candidate",
                 "proposed_action": "unresolved", "signals": [{"kind": "literal_name"}],
                 "competing_candidate_record_keys": [], "competing_subject_record_keys": [],
             }]},
        ],
        "review_gate": "GO", "identity_decision_gate": "NO-GO", "reimport_gate": "NO-GO",
    }
    review_sha = sha_bytes(json.dumps(review, sort_keys=True).encode())
    approvals = {
        "schema_version": "1939-v50-identity-approvals-v1",
        "review_sha256": review_sha,
        "reviewed_by": "codex-assisted:johan-reventlow",
        "decision_batch": "v50-identity-review-batch-1",
        "confirmation": "1-2 ja",
        "approvals": [
            {"source_record_key": "new-a", "candidate_record_key": "old-a", "action": "same"},
            {"source_record_key": "new-b", "candidate_record_key": "old-b", "action": "same"},
        ],
    }
    return review, approvals, review_sha


def test_materializes_exact_append_only_decisions_without_database_authority():
    review, approvals, review_sha = fixture()
    result = subject.materialize_decisions(review, approvals, review_sha, expected_decisions=2)
    assert result["schema_version"] == "1939-v50-identity-decisions-v1"
    assert result["input_review_sha256"] == review_sha
    assert result["canonical_mutations_authorized"] is False
    assert result["database_write_authorized"] is False
    assert result["decision_gate"] == "GO"
    assert result["database_gate"] == "NO-GO"
    assert [row["source_record_key"] for row in result["decisions"]] == ["new-a", "new-b"]
    assert result["decisions"][0]["record_provenance"] == {
        "record_key": "new-a", "external_person_number": None}
    assert result["decisions"][0]["canonical_person_id"] == 101
    assert result["decisions"][0]["source_persona_status"] == "pending_materialization"


@pytest.mark.parametrize("mutation", [
    "review_hash", "unknown_candidate", "duplicate_subject", "not_same",
    "candidate_already_decided", "competing_candidate", "competing_subject",
    "canonical_authority", "count",
])
def test_fails_closed_on_drift_or_ambiguity(mutation):
    review, approvals, review_sha = fixture()
    if mutation == "review_hash":
        approvals["review_sha256"] = "0" * 64
    elif mutation == "unknown_candidate":
        approvals["approvals"][0]["candidate_record_key"] = "old-x"
    elif mutation == "duplicate_subject":
        approvals["approvals"][1]["source_record_key"] = "new-a"
    elif mutation == "not_same":
        approvals["approvals"][0]["action"] = "different"
    elif mutation == "candidate_already_decided":
        review["subjects"][0]["candidates"][0]["proposed_action"] = "same"
    elif mutation == "competing_candidate":
        review["subjects"][0]["candidates"][0]["competing_candidate_record_keys"] = ["old-z"]
    elif mutation == "competing_subject":
        review["subjects"][0]["candidates"][0]["competing_subject_record_keys"] = ["new-z"]
    elif mutation == "canonical_authority":
        review["canonical_mutations_authorized"] = True
    elif mutation == "count":
        approvals["approvals"].pop()
    with pytest.raises(subject.IdentityDecisionError):
        subject.materialize_decisions(review, approvals, review_sha, expected_decisions=2)


def test_output_is_exclusive_and_deterministic(tmp_path: Path):
    review, approvals, review_sha = fixture()
    result = subject.materialize_decisions(review, approvals, review_sha, expected_decisions=2)
    output = tmp_path / "decisions.json"
    report = tmp_path / "decisions.md"
    subject.write_outputs(result, output, report)
    first = output.read_bytes(), report.read_bytes()
    with pytest.raises(FileExistsError):
        subject.write_outputs(result, output, report)
    output.unlink(); report.unlink()
    subject.write_outputs(result, output, report)
    assert (output.read_bytes(), report.read_bytes()) == first

