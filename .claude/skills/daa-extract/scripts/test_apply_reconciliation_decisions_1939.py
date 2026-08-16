from __future__ import annotations

import copy
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
                "record_kind": "unclassified",
                "source_span": {"char_from": 0, "char_to": 10},
                "baseline_record_keys": ["old-a"],
                "disposition": "split_review",
            },
            {
                "new_record_key": "new-b",
                "record_kind": "unclassified",
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


def text_anchor_reconciliation():
    source = reconciliation()
    source["baseline_entries"] = [source["baseline_entries"][0]]
    old = source["baseline_entries"][0]
    old["matches"] = [old["matches"][0]]
    old["disposition"] = "text_anchor_review"
    old["evidence_method"] = "unique_exact_narrative"
    source["new_entries"] = [source["new_entries"][0]]
    source["new_entries"][0]["baseline_record_keys"] = ["old-a"]
    source["new_entries"][0]["disposition"] = "text_anchor_review"
    return source


def text_anchor_decision_document(reconciliation_sha256):
    document = decision_document(reconciliation_sha256)
    document["decisions"] = [{
        "baseline_record_key": "old-a",
        "decision_kind": "accept_text_anchor",
        "selected_new_record_key": "new-a",
    }]
    return document


def duplicate_reconciliation():
    source = reconciliation()
    source["baseline_entries"] = [
        {
            "baseline_record_key": "old-a",
            "name": "Ditlev Reventlow",
            "source_span": {"char_from": 0, "char_to": 10},
            "matches": [{
                "new_record_key": "new-a",
                "geometry_relation": "narrative_inside_new",
            }],
            "disposition": "merge_review",
        },
        {
            "baseline_record_key": "old-b",
            "name": "DitlevReventlow",
            "source_span": {"char_from": 0, "char_to": 10},
            "matches": [{
                "new_record_key": "new-a",
                "geometry_relation": "narrative_inside_new",
            }],
            "disposition": "merge_review",
        },
    ]
    source["new_entries"] = [{
        "new_record_key": "new-a",
        "source_span": {"char_from": 0, "char_to": 20},
        "baseline_record_keys": ["old-a", "old-b"],
        "disposition": "merge_review",
    }]
    return source


def duplicate_decision_document(reconciliation_sha256):
    document = decision_document(reconciliation_sha256)
    document["decisions"] = [{
        "baseline_record_key": "old-b",
        "decision_kind": "retire_duplicate_record",
        "canonical_baseline_record_key": "old-a",
        "new_record_key": "new-a",
        "reason": "duplicate_extraction_record",
    }]
    return document


def duplicate_case(mutation):
    source = duplicate_reconciliation()
    if mutation == "different_source_span":
        source["baseline_entries"][1]["source_span"] = {
            "char_from": 1,
            "char_to": 10,
        }
    elif mutation == "wrong_shared_target":
        source["baseline_entries"][1]["matches"][0]["new_record_key"] = "new-b"
        source["new_entries"].append({
            "new_record_key": "new-b",
            "source_span": {"char_from": 20, "char_to": 30},
            "baseline_record_keys": ["old-b"],
            "disposition": "merge_review",
        })
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = duplicate_decision_document(digest)
    decision = document["decisions"][0]
    if mutation == "unknown_canonical_key":
        decision["canonical_baseline_record_key"] = "missing"
    elif mutation == "same_canonical_and_retired_key":
        decision["canonical_baseline_record_key"] = "old-b"
    elif mutation == "reverse_retirement_conflict":
        document["decisions"].append({
            "baseline_record_key": "old-a",
            "decision_kind": "retire_duplicate_record",
            "canonical_baseline_record_key": "old-b",
            "new_record_key": "new-a",
            "reason": "duplicate_extraction_record",
        })
    elif mutation == "wrong_reason":
        decision["reason"] = "similar_name"
    elif mutation == "unexpected_field":
        decision["note"] = "looks duplicated"
    return source, document, digest


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


def test_nonselected_structural_context_is_resolved_without_person_creation():
    source = reconciliation()
    source["baseline_entries"] = source["baseline_entries"][:1]
    source["new_entries"][1]["baseline_record_keys"] = ["old-a"]
    source["new_entries"][1]["record_kind"] = "structural_context"

    result = apply(source=source)

    structural = result["new_entries"][1]
    assert structural["baseline_record_keys"] == []
    assert structural["disposition"] == "accepted_structural_context"
    assert result["report"]["remaining_new_review"] == 0


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


def test_accepts_exactly_one_human_reviewed_boundary_change():
    source = reconciliation()
    source["baseline_entries"] = source["baseline_entries"][:1]
    source["baseline_entries"][0]["matches"] = source["baseline_entries"][0]["matches"][:1]
    source["baseline_entries"][0]["disposition"] = "boundary_change_review"
    source["new_entries"] = source["new_entries"][:1]
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = decision_document(digest)
    document["decisions"] = [{
        "baseline_record_key": "old-a",
        "decision_kind": "accept_boundary_change",
        "selected_new_record_key": "new-a",
    }]

    result = apply_decisions(source, document, reconciliation_sha256=digest)

    old = result["baseline_entries"][0]
    assert old["disposition"] == "accepted_carryover"
    assert old["reconciliation_basis"] == "human_accepted_boundary_change"
    assert result["new_entries"][0]["disposition"] == "accepted_carryover"


def test_accepts_exactly_one_human_reviewed_text_anchor():
    source = text_anchor_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        text_anchor_decision_document(digest),
        reconciliation_sha256=digest,
    )

    old = result["baseline_entries"][0]
    assert old["matches"] == [{
        "new_record_key": "new-a",
        "geometry_relation": "new_inside_old",
    }]
    assert old["selected_new_record_key"] == "new-a"
    assert old["disposition"] == "accepted_carryover"
    assert old["reconciliation_basis"] == "human_accepted_text_anchor"
    assert old["reviewed_by"] == "johan-reventlow"
    assert old["decision_batch"] == "batch-1"
    assert result["new_entries"][0]["baseline_record_keys"] == ["old-a"]
    assert result["new_entries"][0]["disposition"] == "accepted_carryover"
    assert result["report"]["accepted_carryovers"] == 1
    assert result["report"]["baseline_dispositions"] == {
        "accepted_carryover": 1,
    }
    assert result["report"]["new_dispositions"] == {
        "accepted_carryover": 1,
    }
    assert result["report"]["remaining_baseline_review"] == 0
    assert result["report"]["remaining_new_review"] == 0
    assert result["report"]["reconciliation_gate"] == "GO"


@pytest.mark.parametrize("mutation", [
    "wrong_disposition",
    "wrong_evidence_method",
    "zero_matches",
    "extra_match",
    "wrong_target",
    "unknown_target",
    "extra_field",
])
def test_text_anchor_acceptance_fails_closed_on_drift(mutation):
    source = text_anchor_reconciliation()
    decision = {
        "baseline_record_key": "old-a",
        "decision_kind": "accept_text_anchor",
        "selected_new_record_key": "new-a",
    }
    if mutation == "wrong_disposition":
        source["baseline_entries"][0]["disposition"] = "boundary_change_review"
    elif mutation == "wrong_evidence_method":
        source["baseline_entries"][0]["evidence_method"] = "geometry_only"
    elif mutation == "zero_matches":
        source["baseline_entries"][0]["matches"] = []
    elif mutation == "extra_match":
        source["baseline_entries"][0]["matches"].append({
            "new_record_key": "new-b", "geometry_relation": "partial_overlap",
        })
    elif mutation == "wrong_target":
        source["new_entries"].append({
            "new_record_key": "new-b",
            "record_kind": "unclassified",
            "source_span": {"char_from": 10, "char_to": 20},
            "baseline_record_keys": [],
            "disposition": "unmatched_new_review",
        })
        decision["selected_new_record_key"] = "new-b"
    elif mutation == "unknown_target":
        decision["selected_new_record_key"] = "missing"
    elif mutation == "extra_field":
        decision["note"] = "looks exact"
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = text_anchor_decision_document(digest)
    document["decisions"] = [decision]

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_text_anchor_acceptance_rejects_same_batch_target_reuse():
    source = text_anchor_reconciliation()
    source["baseline_entries"].append({
        "baseline_record_key": "old-b",
        "name": "Bent",
        "matches": [{
            "new_record_key": "new-b", "geometry_relation": "new_inside_old",
        }],
        "disposition": "text_anchor_review",
        "evidence_method": "unique_exact_narrative",
    })
    source["new_entries"].append({
        "new_record_key": "new-b",
        "record_kind": "unclassified",
        "source_span": {"char_from": 10, "char_to": 20},
        "baseline_record_keys": ["old-b"],
        "disposition": "text_anchor_review",
    })
    source["baseline_entries"][1]["matches"][0]["new_record_key"] = "new-a"
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = text_anchor_decision_document(digest)
    document["decisions"].append({
        "baseline_record_key": "old-b",
        "decision_kind": "accept_text_anchor",
        "selected_new_record_key": "new-a",
    })

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_text_anchor_acceptance_rejects_unresolved_competing_owner():
    source = text_anchor_reconciliation()
    source["baseline_entries"].append({
        "baseline_record_key": "old-b",
        "name": "Bent",
        "matches": [{
            "new_record_key": "new-a", "geometry_relation": "partial_overlap",
        }],
        "disposition": "merge_review",
    })
    source["new_entries"][0]["baseline_record_keys"] = ["old-a", "old-b"]
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = text_anchor_decision_document(digest)

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_text_anchor_acceptance_rejects_hash_drift_after_document_creation():
    source = text_anchor_reconciliation()
    original_digest = hashlib.sha256(encoded(source)).hexdigest()
    document = text_anchor_decision_document(original_digest)
    source["report"]["reconciliation_gate"] = "GO"
    mutated_digest = hashlib.sha256(encoded(source)).hexdigest()

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=mutated_digest)


@pytest.mark.parametrize("mutation", ["wrong_disposition", "extra_match", "wrong_target", "extra_field"])
def test_boundary_change_acceptance_fails_closed_on_drift(mutation):
    source = reconciliation()
    source["baseline_entries"] = source["baseline_entries"][:1]
    source["baseline_entries"][0]["matches"] = source["baseline_entries"][0]["matches"][:1]
    source["baseline_entries"][0]["disposition"] = "boundary_change_review"
    source["new_entries"] = source["new_entries"][:1]
    decision = {
        "baseline_record_key": "old-a",
        "decision_kind": "accept_boundary_change",
        "selected_new_record_key": "new-a",
    }
    if mutation == "wrong_disposition":
        source["baseline_entries"][0]["disposition"] = "text_anchor_review"
    elif mutation == "extra_match":
        source["baseline_entries"][0]["matches"].append({
            "new_record_key": "new-b", "geometry_relation": "partial_overlap",
        })
    elif mutation == "wrong_target":
        decision["selected_new_record_key"] = "new-b"
    elif mutation == "extra_field":
        decision["note"] = "looks right"
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = decision_document(digest)
    document["decisions"] = [decision]

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


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


def test_retires_duplicate_but_preserves_audit_and_single_owner():
    source = duplicate_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = duplicate_decision_document(digest)

    result = apply_decisions(source, document, reconciliation_sha256=digest)

    canonical, retired = result["baseline_entries"]
    assert canonical["disposition"] == "accepted_carryover"
    assert canonical["reconciliation_basis"] == "human_retained_duplicate_target"
    assert retired["disposition"] == "retired_duplicate"
    assert retired["matches"] == []
    assert retired["canonical_baseline_record_key"] == "old-a"
    assert retired["retirement_reason"] == "duplicate_extraction_record"
    assert retired["reviewed_by"] == "johan-reventlow"
    assert result["new_entries"][0]["baseline_record_keys"] == ["old-a"]
    assert result["new_entries"][0]["disposition"] == "accepted_carryover"
    assert result["report"]["retired_duplicates"] == 1
    assert result["report"]["remaining_baseline_review"] == 0
    assert result["report"]["remaining_new_review"] == 0
    assert result["report"]["reconciliation_gate"] == "GO"


def test_later_decision_batch_preserves_prior_duplicate_retirement():
    source = duplicate_reconciliation()
    first_digest = hashlib.sha256(encoded(source)).hexdigest()
    first = apply_decisions(
        source,
        duplicate_decision_document(first_digest),
        reconciliation_sha256=first_digest,
    )
    first["baseline_entries"].append({
        "baseline_record_key": "old-c",
        "name": "Clara",
        "matches": [{
            "new_record_key": "new-c",
            "geometry_relation": "old_inside_new",
        }],
        "disposition": "boundary_change_review",
    })
    first["new_entries"].append({
        "new_record_key": "new-c",
        "record_kind": "unclassified",
        "source_span": {"char_from": 20, "char_to": 30},
        "baseline_record_keys": ["old-c"],
        "disposition": "boundary_change_review",
    })
    second_digest = hashlib.sha256(encoded(first)).hexdigest()
    second_document = decision_document(second_digest)
    second_document["decisions"] = [{
        "baseline_record_key": "old-c",
        "decision_kind": "accept_boundary_change",
        "selected_new_record_key": "new-c",
    }]

    result = apply_decisions(
        first, second_document, reconciliation_sha256=second_digest,
    )

    retired = next(
        entry for entry in result["baseline_entries"]
        if entry["baseline_record_key"] == "old-b"
    )
    assert retired["disposition"] == "retired_duplicate"
    assert retired["canonical_baseline_record_key"] == "old-a"
    assert result["report"]["retired_duplicates"] == 1
    assert result["report"]["remaining_baseline_review"] == 0


def test_later_text_anchor_batch_preserves_prior_history_and_recounts_reports():
    """Catch regression where recomputation overwrites earlier decision audits."""
    source = {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "baseline_entries": [
            {
                "baseline_record_key": "old-prior-boundary",
                "name": "Prior Boundary",
                "matches": [{
                    "new_record_key": "new-prior-boundary",
                    "geometry_relation": "new_inside_old",
                }],
                "disposition": "boundary_change_review",
            },
            {
                "baseline_record_key": "old-duplicate-canonical",
                "name": "Duplicate Canonical",
                "source_span": {"char_from": 10, "char_to": 20},
                "matches": [{
                    "new_record_key": "new-duplicate",
                    "geometry_relation": "narrative_inside_new",
                }],
                "disposition": "merge_review",
            },
            {
                "baseline_record_key": "old-duplicate-retired",
                "name": "Duplicate Retired",
                "source_span": {"char_from": 10, "char_to": 20},
                "matches": [{
                    "new_record_key": "new-duplicate",
                    "geometry_relation": "narrative_inside_new",
                }],
                "disposition": "merge_review",
            },
        ],
        "new_entries": [
            {
                "new_record_key": "new-prior-boundary",
                "record_kind": "unclassified",
                "source_span": {"char_from": 0, "char_to": 10},
                "baseline_record_keys": ["old-prior-boundary"],
                "disposition": "boundary_change_review",
            },
            {
                "new_record_key": "new-duplicate",
                "record_kind": "unclassified",
                "source_span": {"char_from": 10, "char_to": 30},
                "baseline_record_keys": [
                    "old-duplicate-canonical", "old-duplicate-retired",
                ],
                "disposition": "merge_review",
            },
            {
                "new_record_key": "new-structural",
                "record_kind": "structural_context",
                "source_span": {"char_from": 30, "char_to": 40},
                "baseline_record_keys": [],
                "disposition": "accepted_structural_context",
            },
        ],
        "report": {"reconciliation_gate": "NO-GO"},
    }
    first_digest = hashlib.sha256(encoded(source)).hexdigest()
    first_document = {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "reconciliation_sha256": first_digest,
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "reviewed_by": "prior-reviewer",
        "decision_batch": "prior-batch",
        "decisions": [
            {
                "baseline_record_key": "old-prior-boundary",
                "decision_kind": "accept_boundary_change",
                "selected_new_record_key": "new-prior-boundary",
            },
            {
                "baseline_record_key": "old-duplicate-retired",
                "decision_kind": "retire_duplicate_record",
                "canonical_baseline_record_key": "old-duplicate-canonical",
                "new_record_key": "new-duplicate",
                "reason": "duplicate_extraction_record",
            },
        ],
    }
    first = apply_decisions(source, first_document, reconciliation_sha256=first_digest)
    prior_baseline = {
        entry["baseline_record_key"]: entry
        for entry in copy.deepcopy(first["baseline_entries"])
    }
    prior_new = {
        entry["new_record_key"]: entry
        for entry in copy.deepcopy(first["new_entries"])
    }
    second_source = copy.deepcopy(first)
    second_source["baseline_entries"].append({
        "baseline_record_key": "old-fresh-text-anchor",
        "name": "Fresh Text Anchor",
        "matches": [{
            "new_record_key": "new-fresh-text-anchor",
            "geometry_relation": "new_inside_old",
        }],
        "disposition": "text_anchor_review",
        "evidence_method": "unique_exact_narrative",
    })
    second_source["new_entries"].append({
        "new_record_key": "new-fresh-text-anchor",
        "record_kind": "unclassified",
        "source_span": {"char_from": 40, "char_to": 50},
        "baseline_record_keys": ["old-fresh-text-anchor"],
        "disposition": "text_anchor_review",
    })
    second_digest = hashlib.sha256(encoded(second_source)).hexdigest()
    second_document = {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "reconciliation_sha256": second_digest,
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "reviewed_by": "text-anchor-reviewer",
        "decision_batch": "text-anchor-batch",
        "decisions": [{
            "baseline_record_key": "old-fresh-text-anchor",
            "decision_kind": "accept_text_anchor",
            "selected_new_record_key": "new-fresh-text-anchor",
        }],
    }

    result = apply_decisions(
        second_source, second_document, reconciliation_sha256=second_digest,
    )

    result_baseline = {
        entry["baseline_record_key"]: entry for entry in result["baseline_entries"]
    }
    for key, entry in prior_baseline.items():
        assert result_baseline[key] == entry
    result_new = {
        entry["new_record_key"]: entry for entry in result["new_entries"]
    }
    for key, entry in prior_new.items():
        assert result_new[key] == entry
    assert result_baseline["old-fresh-text-anchor"]["disposition"] == "accepted_carryover"
    assert result_baseline["old-fresh-text-anchor"]["reconciliation_basis"] == (
        "human_accepted_text_anchor"
    )
    assert result_baseline["old-fresh-text-anchor"]["reviewed_by"] == "text-anchor-reviewer"
    assert result_baseline["old-fresh-text-anchor"]["decision_batch"] == "text-anchor-batch"
    structural = next(
        entry for entry in result["new_entries"]
        if entry["new_record_key"] == "new-structural"
    )
    assert structural["baseline_record_keys"] == []
    assert structural["disposition"] == "accepted_structural_context"
    duplicate_target = next(
        entry for entry in result["new_entries"]
        if entry["new_record_key"] == "new-duplicate"
    )
    assert duplicate_target["baseline_record_keys"] == ["old-duplicate-canonical"]
    assert result["report"]["baseline_total"] == 4
    assert result["report"]["new_total"] == 4
    assert result["report"]["applied_decisions"] == 1
    assert result["report"]["accepted_carryovers"] == 3
    assert result["report"]["retired_duplicates"] == 1
    assert result["report"]["baseline_dispositions"] == {
        "accepted_carryover": 3,
        "retired_duplicate": 1,
    }
    assert result["report"]["new_dispositions"] == {
        "accepted_carryover": 3,
        "accepted_structural_context": 1,
    }
    assert result["report"]["remaining_baseline_review"] == 0
    assert result["report"]["remaining_new_review"] == 0
    assert result["report"]["reconciliation_gate"] == "GO"


@pytest.mark.parametrize("mutation", [
    "different_source_span",
    "wrong_shared_target",
    "unknown_canonical_key",
    "same_canonical_and_retired_key",
    "reverse_retirement_conflict",
    "wrong_reason",
    "unexpected_field",
])
def test_rejects_unproven_or_conflicting_duplicate_retirement(mutation):
    source, document, digest = duplicate_case(mutation)

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)
