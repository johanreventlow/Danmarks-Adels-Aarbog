from __future__ import annotations

import hashlib
import json

import pytest

import apply_reconciliation_decisions_1939 as subject


DecisionError = subject.DecisionError
apply_decisions = subject.apply_decisions


def reconciliation():
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "baseline_entries": [
            {
                "baseline_record_key": "old-a",
                "name": "Anna",
                "matches": [
                    {"new_record_key": "new-a", "geometry_relation": "new_inside_old"},
                    {"new_record_key": "new-b", "geometry_relation": "new_inside_old"},
                ],
                "disposition": "split_review",
            },
            {
                "baseline_record_key": "old-b",
                "name": "Bent",
                "matches": [
                    {"new_record_key": "new-b", "geometry_relation": "old_inside_new"},
                ],
                "disposition": "merge_review",
            },
        ],
        "new_entries": [
            {
                "new_record_key": "new-a",
                "source_span": {"char_from": 0, "char_to": 10},
                "baseline_record_keys": ["old-a"],
                "disposition": "split_review",
            },
            {
                "new_record_key": "new-b",
                "source_span": {"char_from": 10, "char_to": 20},
                "baseline_record_keys": ["old-a", "old-b"],
                "disposition": "split_merge_review",
            },
        ],
        "report": {"reconciliation_gate": "NO-GO"},
    }


def decision_document(reconciliation_sha256, *, selected="new-a", annotations=None):
    decision = {
        "baseline_record_key": "old-a",
        "decision_kind": "select_carryover_target",
        "selected_new_record_key": selected,
        "nonselected_action": "retain_distinct_source_records",
    }
    if annotations is not None:
        decision["record_annotations"] = annotations
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "reconciliation_sha256": reconciliation_sha256,
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "reviewed_by": "johan-reventlow",
        "decision_batch": "batch-1",
        "decisions": [decision],
    }


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def apply(document=None, source=None):
    source = source or reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    return apply_decisions(source, document or decision_document(digest),
                           reconciliation_sha256=digest)


def test_selected_split_target_inherits_old_key_and_other_target_is_recomputed():
    result = apply()

    old = result["baseline_entries"][0]
    assert old["matches"] == [
        {"new_record_key": "new-a", "geometry_relation": "new_inside_old"}
    ]
    assert old["disposition"] == "accepted_carryover"
    assert old["reconciliation_basis"] == "human_selected_split_target"
    assert old["reviewed_by"] == "johan-reventlow"
    assert result["new_entries"][0]["disposition"] == "accepted_carryover"
    assert result["new_entries"][0]["baseline_record_keys"] == ["old-a"]

    # new-b keeps the independent old-b edge after old-a's rejected edge is removed.
    assert result["new_entries"][1]["baseline_record_keys"] == ["old-b"]
    assert result["new_entries"][1]["disposition"] == "boundary_change_review"


def test_nonselected_target_without_another_owner_becomes_unmatched():
    source = reconciliation()
    source["baseline_entries"] = source["baseline_entries"][:1]
    source["new_entries"][1]["baseline_record_keys"] = ["old-a"]

    result = apply(source=source)

    assert result["new_entries"][1]["baseline_record_keys"] == []
    assert result["new_entries"][1]["disposition"] == "unmatched_new_review"


def test_cross_reference_annotation_is_preserved_and_forbids_person_creation():
    annotations = [{
        "new_record_key": "new-b",
        "record_kind": "cross_reference",
        "person_creation": "forbidden_without_separate_evidence",
    }]

    result = apply(decision_document(
        hashlib.sha256(encoded(reconciliation())).hexdigest(), annotations=annotations
    ))

    assert result["new_entries"][1]["human_annotation"] == annotations[0]


@pytest.mark.parametrize("selected", ["missing", "new-b"])
def test_rejects_missing_or_multiply_owned_selected_target(selected):
    with pytest.raises(DecisionError):
        apply(decision_document(
            hashlib.sha256(encoded(reconciliation())).hexdigest(), selected=selected
        ))


def test_rejects_hash_drift_and_duplicate_old_decisions():
    digest = hashlib.sha256(encoded(reconciliation())).hexdigest()
    document = decision_document(digest)
    document["decisions"].append(dict(document["decisions"][0]))
    with pytest.raises(DecisionError):
        apply(document)

    document = decision_document("c" * 64)
    with pytest.raises(DecisionError):
        apply(document)


def test_report_recounts_resolved_and_remaining_reviews():
    result = apply()

    assert result["report"]["accepted_carryovers"] == 1
    assert result["report"]["baseline_dispositions"] == {
        "accepted_carryover": 1,
        "boundary_change_review": 1,
    }
    assert result["report"]["new_dispositions"] == {
        "accepted_carryover": 1,
        "boundary_change_review": 1,
    }
    assert result["report"]["remaining_baseline_review"] == 1
    assert result["report"]["remaining_new_review"] == 1
    assert result["report"]["reconciliation_gate"] == "NO-GO"

