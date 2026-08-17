from __future__ import annotations

import copy
import hashlib
import json

import pytest

import apply_reconciliation_decisions_1939 as subject


DecisionError = subject.DecisionError
apply_decisions = subject.apply_decisions


def classification_history_sha256(history):
    return hashlib.sha256(json.dumps(
        history, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")).hexdigest()


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


def genuinely_new_reconciliation():
    """One ownerless new source record, with no baseline match to accept."""
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "baseline_entries": [],
        "new_entries": [{
            "new_record_key": "new-genuine",
            "record_kind": "unclassified",
            "source_span": {"char_from": 10, "char_to": 20},
            "baseline_record_keys": [],
            "disposition": "unmatched_new_review",
        }],
        "report": {"reconciliation_gate": "NO-GO"},
    }


def nonperson_classification_reconciliation():
    """Two ownerless unmatched records for human non-person classification."""
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "baseline_entries": [],
        "new_entries": [{
            "new_record_key": "new-structural",
            "record_kind": "unclassified",
            "source_span": {"char_from": 10, "char_to": 20},
            "baseline_record_keys": [],
            "disposition": "unmatched_new_review",
        }, {
            "new_record_key": "new-crossref",
            "record_kind": "unclassified",
            "source_span": {"char_from": 30, "char_to": 40},
            "baseline_record_keys": [],
            "disposition": "unmatched_new_review",
            "human_annotation": {
                "new_record_key": "new-crossref",
                "record_kind": "cross_reference",
                "person_creation": "forbidden_without_separate_evidence",
            },
            "reviewed_by": "old-crossref-reviewer",
            "decision_batch": "old-crossref-batch",
        }],
        "report": {"reconciliation_gate": "NO-GO"},
    }


def nonperson_classification_decision_document(reconciliation_sha256, decisions):
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "reconciliation_sha256": reconciliation_sha256,
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "reviewed_by": "new-nonperson-reviewer",
        "decision_batch": "nonperson-classification-batch-1",
        "decisions": decisions,
    }


STRUCTURAL_CONTEXT_DECISION = {
    "decision_kind": "accept_structural_context",
    "new_record_key": "new-structural",
    "new_source_span": {"char_from": 10, "char_to": 20},
    "reason": "human_verified_structural_narrative",
}

CROSS_REFERENCE_DECISION = {
    "decision_kind": "resolve_annotated_cross_reference",
    "new_record_key": "new-crossref",
    "new_source_span": {"char_from": 30, "char_to": 40},
    "reason": "human_verified_cross_reference",
}


def test_nonperson_classification_accepts_structural_context_without_owner():
    source = nonperson_classification_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        nonperson_classification_decision_document(
            digest, [STRUCTURAL_CONTEXT_DECISION],
        ),
        reconciliation_sha256=digest,
    )

    assert result["baseline_entries"] == []
    structural, crossref = result["new_entries"]
    structural_history = {
        "source_reconciliation_sha256": digest,
        "classification_reviewed_by": "new-nonperson-reviewer",
        "classification_decision_batch": "nonperson-classification-batch-1",
    }
    assert structural == {
        "new_record_key": "new-structural",
        "record_kind": "structural_context",
        "source_span": {"char_from": 10, "char_to": 20},
        "baseline_record_keys": [],
        "disposition": "accepted_structural_context",
        "classification_basis": "human_verified_structural_context",
        "reviewed_by": "new-nonperson-reviewer",
        "decision_batch": "nonperson-classification-batch-1",
        "classification_history": structural_history,
        "classification_history_sha256": classification_history_sha256(structural_history),
    }
    assert crossref["baseline_record_keys"] == []
    assert crossref["disposition"] == "unmatched_new_review"
    assert result["report"]["new_dispositions"] == {
        "accepted_structural_context": 1,
        "unmatched_new_review": 1,
    }
    assert result["report"]["remaining_new_review"] == 1


def test_nonperson_classification_resolves_annotated_cross_reference_without_owner():
    source = nonperson_classification_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        nonperson_classification_decision_document(
            digest, [CROSS_REFERENCE_DECISION],
        ),
        reconciliation_sha256=digest,
    )

    assert result["baseline_entries"] == []
    structural, crossref = result["new_entries"]
    assert structural["baseline_record_keys"] == []
    assert structural["disposition"] == "unmatched_new_review"
    crossref_history = {
        "source_reconciliation_sha256": digest,
        "annotation_reviewed_by": "old-crossref-reviewer",
        "annotation_decision_batch": "old-crossref-batch",
        "resolution_reviewed_by": "new-nonperson-reviewer",
        "resolution_decision_batch": "nonperson-classification-batch-1",
    }
    assert crossref == {
        "new_record_key": "new-crossref",
        "record_kind": "cross_reference",
        "source_span": {"char_from": 30, "char_to": 40},
        "baseline_record_keys": [],
        "disposition": "accepted_cross_reference",
        "human_annotation": {
            "new_record_key": "new-crossref",
            "record_kind": "cross_reference",
            "person_creation": "forbidden_without_separate_evidence",
        },
        "reviewed_by": "old-crossref-reviewer",
        "decision_batch": "old-crossref-batch",
        "classification_basis": "human_confirmed_existing_cross_reference_annotation",
        "resolved_by": "new-nonperson-reviewer",
        "resolution_batch": "nonperson-classification-batch-1",
        "classification_history": crossref_history,
        "classification_history_sha256": classification_history_sha256(crossref_history),
    }
    assert result["report"]["new_dispositions"] == {
        "accepted_cross_reference": 1,
        "unmatched_new_review": 1,
    }
    assert result["report"]["remaining_new_review"] == 1


def test_nonperson_classification_accepts_mixed_closed_batch():
    source = nonperson_classification_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        nonperson_classification_decision_document(
            digest, [STRUCTURAL_CONTEXT_DECISION, CROSS_REFERENCE_DECISION],
        ),
        reconciliation_sha256=digest,
    )

    assert result["baseline_entries"] == []
    assert [entry["baseline_record_keys"] for entry in result["new_entries"]] == [[], []]
    assert result["report"] == {
        "baseline_total": 0,
        "new_total": 2,
        "applied_decisions": 2,
        "accepted_carryovers": 0,
        "retired_duplicates": 0,
        "retired_fragments": 0,
        "baseline_dispositions": {},
        "new_dispositions": {
            "accepted_cross_reference": 1,
            "accepted_structural_context": 1,
        },
        "remaining_baseline_review": 0,
        "remaining_new_review": 0,
        "reconciliation_gate": "GO",
    }


@pytest.mark.parametrize("mutation", [
    "unknown_target",
    "target_reused",
    "extra_field",
    "missing_field",
    "wrong_reason",
    "stale_span",
    "invalid_span",
    "stale_reconciliation_hash",
    "stale_baseline_hash",
    "stale_calamari_hash",
    "wrong_disposition",
    "wrong_kind",
    "declared_owner",
    "hidden_forward_owner",
    "existing_classification_metadata",
    "existing_resolution_metadata",
    "existing_classification_history",
    "existing_classification_history_sha256",
])
def test_nonperson_classification_rejects_closed_cross_reference_contract(mutation):
    source = nonperson_classification_reconciliation()
    decision = copy.deepcopy(CROSS_REFERENCE_DECISION)
    target = source["new_entries"][1]
    if mutation == "unknown_target":
        decision["new_record_key"] = "unknown"
    elif mutation == "target_reused":
        decisions = [decision, copy.deepcopy(decision)]
    elif mutation == "extra_field":
        decision["unexpected"] = True
    elif mutation == "missing_field":
        del decision["reason"]
    elif mutation == "wrong_reason":
        decision["reason"] = "human_verified_structural_narrative"
    elif mutation == "stale_span":
        decision["new_source_span"] = {"char_from": 31, "char_to": 40}
    elif mutation == "invalid_span":
        decision["new_source_span"] = {"char_from": 40, "char_to": 40}
    elif mutation == "wrong_disposition":
        target["disposition"] = "accepted_structural_context"
    elif mutation == "wrong_kind":
        target["record_kind"] = "structural_context"
    elif mutation == "declared_owner":
        target["baseline_record_keys"] = ["old-hidden"]
        source["baseline_entries"].append({
            "baseline_record_key": "old-hidden",
            "matches": [{"new_record_key": "new-crossref"}],
            "disposition": "unresolved",
            "unresolved_reason": "narrative_not_exact",
        })
    elif mutation == "hidden_forward_owner":
        source["baseline_entries"].append({
            "baseline_record_key": "old-hidden",
            "matches": [{"new_record_key": "new-crossref"}],
            "disposition": "unresolved",
            "unresolved_reason": "narrative_not_exact",
        })
        target["baseline_record_keys"] = ["old-hidden"]
    elif mutation == "existing_classification_metadata":
        target["classification_basis"] = "conflicting"
    elif mutation == "existing_resolution_metadata":
        target["resolved_by"] = "previous-reviewer"
    elif mutation == "existing_classification_history":
        target["classification_history"] = {}
    elif mutation == "existing_classification_history_sha256":
        target["classification_history_sha256"] = "c" * 64

    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = nonperson_classification_decision_document(
        digest, locals().get("decisions", [decision]),
    )
    if mutation == "stale_reconciliation_hash":
        document["source"]["reconciliation_sha256"] = "c" * 64
    elif mutation == "stale_baseline_hash":
        document["source"]["baseline_sha256"] = "c" * 64
    elif mutation == "stale_calamari_hash":
        document["source"]["calamari_sha256"] = "c" * 64

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


@pytest.mark.parametrize("mutation", [
    "unknown_target",
    "target_reused",
    "extra_field",
    "missing_field",
    "wrong_reason",
    "stale_span",
    "invalid_span",
    "wrong_disposition",
    "wrong_kind",
    "declared_owner",
    "hidden_forward_owner",
])
def test_nonperson_classification_rejects_closed_structural_contract(mutation):
    source = nonperson_classification_reconciliation()
    decision = copy.deepcopy(STRUCTURAL_CONTEXT_DECISION)
    target = source["new_entries"][0]
    if mutation == "unknown_target":
        decision["new_record_key"] = "unknown"
    elif mutation == "target_reused":
        decisions = [decision, copy.deepcopy(decision)]
    elif mutation == "extra_field":
        decision["unexpected"] = True
    elif mutation == "missing_field":
        del decision["reason"]
    elif mutation == "wrong_reason":
        decision["reason"] = "human_verified_cross_reference"
    elif mutation == "stale_span":
        decision["new_source_span"] = {"char_from": 11, "char_to": 20}
    elif mutation == "invalid_span":
        decision["new_source_span"] = {"char_from": 20, "char_to": 20}
    elif mutation == "wrong_disposition":
        target["disposition"] = "accepted_structural_context"
    elif mutation == "wrong_kind":
        target["record_kind"] = "structural_context"
    elif mutation == "declared_owner":
        target["baseline_record_keys"] = ["old-hidden"]
    elif mutation == "hidden_forward_owner":
        source["baseline_entries"].append({
            "baseline_record_key": "old-hidden",
            "matches": [{"new_record_key": "new-structural"}],
            "disposition": "unresolved",
            "unresolved_reason": "narrative_not_exact",
        })
        target["baseline_record_keys"] = ["old-hidden"]

    digest = hashlib.sha256(encoded(source)).hexdigest()
    with pytest.raises(DecisionError):
        apply_decisions(
            source,
            nonperson_classification_decision_document(
                digest, locals().get("decisions", [decision]),
            ),
            reconciliation_sha256=digest,
        )


@pytest.mark.parametrize("mutation", [
    "missing_annotation",
    "annotation_extra_field",
    "annotation_missing_key",
    "annotation_missing_kind",
    "annotation_missing_person_creation",
    "annotation_key_mismatch",
    "annotation_wrong_kind",
    "annotation_wrong_person_creation",
    "annotation_wrong_type",
    "missing_old_reviewer",
    "empty_old_reviewer",
    "wrong_type_old_reviewer",
    "missing_old_batch",
    "empty_old_batch",
    "wrong_type_old_batch",
])
def test_nonperson_classification_rejects_cross_reference_annotation_drift(mutation):
    source = nonperson_classification_reconciliation()
    target = source["new_entries"][1]
    annotation = target["human_annotation"]
    if mutation == "missing_annotation":
        del target["human_annotation"]
    elif mutation == "annotation_extra_field":
        annotation["unexpected"] = True
    elif mutation == "annotation_missing_key":
        del annotation["new_record_key"]
    elif mutation == "annotation_missing_kind":
        del annotation["record_kind"]
    elif mutation == "annotation_missing_person_creation":
        del annotation["person_creation"]
    elif mutation == "annotation_key_mismatch":
        annotation["new_record_key"] = "new-structural"
    elif mutation == "annotation_wrong_kind":
        annotation["record_kind"] = "structural_context"
    elif mutation == "annotation_wrong_person_creation":
        annotation["person_creation"] = "allowed"
    elif mutation == "annotation_wrong_type":
        target["human_annotation"] = []
    elif mutation.startswith("missing_old_reviewer"):
        del target["reviewed_by"]
    elif mutation.startswith("empty_old_reviewer"):
        target["reviewed_by"] = ""
    elif mutation.startswith("wrong_type_old_reviewer"):
        target["reviewed_by"] = 1
    elif mutation.startswith("missing_old_batch"):
        del target["decision_batch"]
    elif mutation.startswith("empty_old_batch"):
        target["decision_batch"] = ""
    elif mutation.startswith("wrong_type_old_batch"):
        target["decision_batch"] = 1

    digest = hashlib.sha256(encoded(source)).hexdigest()
    with pytest.raises(DecisionError):
        apply_decisions(
            source,
            nonperson_classification_decision_document(
                digest, [copy.deepcopy(CROSS_REFERENCE_DECISION)],
            ),
            reconciliation_sha256=digest,
        )


@pytest.mark.parametrize("field,value", [
    ("human_annotation", {"note": "not allowed"}),
    ("reviewed_by", "old-reviewer"),
    ("decision_batch", "old-batch"),
    ("classification_basis", "conflicting"),
    ("classification_history", {}),
    ("classification_history_sha256", "c" * 64),
])
def test_nonperson_classification_rejects_structural_conflicting_human_metadata(field, value):
    source = nonperson_classification_reconciliation()
    source["new_entries"][0][field] = value
    digest = hashlib.sha256(encoded(source)).hexdigest()

    with pytest.raises(DecisionError):
        apply_decisions(
            source,
            nonperson_classification_decision_document(
                digest, [copy.deepcopy(STRUCTURAL_CONTEXT_DECISION)],
            ),
            reconciliation_sha256=digest,
        )


def classified_nonperson_reconciliation():
    source = nonperson_classification_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    return apply_decisions(
        source,
        nonperson_classification_decision_document(
            digest,
            [copy.deepcopy(STRUCTURAL_CONTEXT_DECISION), copy.deepcopy(CROSS_REFERENCE_DECISION)],
        ),
        reconciliation_sha256=digest,
    )


def later_nonperson_reconciliation():
    source = classified_nonperson_reconciliation()
    source["new_entries"].append({
        "new_record_key": "new-later-genuine",
        "record_kind": "unclassified",
        "source_span": {"char_from": 50, "char_to": 60},
        "baseline_record_keys": [],
        "disposition": "unmatched_new_review",
    })
    return source


def later_nonperson_decision_document(reconciliation_sha256):
    return nonperson_classification_decision_document(reconciliation_sha256, [{
        "decision_kind": "accept_genuinely_new",
        "new_record_key": "new-later-genuine",
        "new_source_span": {"char_from": 50, "char_to": 60},
        "record_kind": "unclassified",
        "reason": "visually_verified_distinct_source_record",
    }])


def test_nonperson_classification_later_batch_deeply_preserves_human_history():
    source = later_nonperson_reconciliation()
    expected_history = copy.deepcopy(source["new_entries"][:2])
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        later_nonperson_decision_document(digest),
        reconciliation_sha256=digest,
    )

    assert result["new_entries"][:2] == expected_history
    assert result["new_entries"][2]["disposition"] == "accepted_genuinely_new_source_record"


def test_nonperson_classification_preserves_history_through_two_later_batches():
    source = later_nonperson_reconciliation()
    first_digest = hashlib.sha256(encoded(source)).hexdigest()
    first = apply_decisions(
        source,
        later_nonperson_decision_document(first_digest),
        reconciliation_sha256=first_digest,
    )
    first["new_entries"].append({
        "new_record_key": "new-later-second",
        "record_kind": "unclassified",
        "source_span": {"char_from": 70, "char_to": 80},
        "baseline_record_keys": [],
        "disposition": "unmatched_new_review",
    })
    second_digest = hashlib.sha256(encoded(first)).hexdigest()
    second_document = nonperson_classification_decision_document(second_digest, [{
        "decision_kind": "accept_genuinely_new",
        "new_record_key": "new-later-second",
        "new_source_span": {"char_from": 70, "char_to": 80},
        "record_kind": "unclassified",
        "reason": "visually_verified_distinct_source_record",
    }])

    result = apply_decisions(
        first, second_document, reconciliation_sha256=second_digest,
    )

    assert result["new_entries"][:2] == first["new_entries"][:2]
    assert result["new_entries"][3]["disposition"] == "accepted_genuinely_new_source_record"


@pytest.mark.parametrize("mutation", [
    "crossref_wrong_disposition",
    "crossref_wrong_kind",
    "crossref_owner",
    "crossref_wrong_basis",
    "crossref_annotation",
    "crossref_missing_old_reviewer",
    "crossref_wrong_old_reviewer",
    "crossref_different_old_reviewer",
    "crossref_missing_old_batch",
    "crossref_wrong_old_batch",
    "crossref_different_old_batch",
    "crossref_missing_resolved_by",
    "crossref_empty_resolved_by",
    "crossref_wrong_resolved_by",
    "crossref_different_resolved_by",
    "crossref_missing_resolution_batch",
    "crossref_empty_resolution_batch",
    "crossref_wrong_resolution_batch",
    "crossref_different_resolution_batch",
    "structural_wrong_disposition",
    "structural_wrong_kind",
    "structural_owner",
    "structural_wrong_basis",
    "structural_missing_reviewer",
    "structural_wrong_reviewer",
    "structural_different_reviewer",
    "structural_missing_batch",
    "structural_wrong_batch",
    "structural_different_batch",
    "structural_annotation",
])
def test_nonperson_classification_rejects_malformed_later_history(mutation):
    source = later_nonperson_reconciliation()
    structural, crossref = source["new_entries"][:2]
    if mutation == "crossref_wrong_disposition":
        crossref["disposition"] = "unmatched_new_review"
    elif mutation == "crossref_wrong_kind":
        crossref["record_kind"] = "unclassified"
    elif mutation == "crossref_owner":
        crossref["baseline_record_keys"] = ["old-owner"]
    elif mutation == "crossref_wrong_basis":
        crossref["classification_basis"] = "wrong"
    elif mutation == "crossref_annotation":
        crossref["human_annotation"]["person_creation"] = "allowed"
    elif mutation == "crossref_missing_old_reviewer":
        del crossref["reviewed_by"]
    elif mutation == "crossref_wrong_old_reviewer":
        crossref["reviewed_by"] = 1
    elif mutation == "crossref_different_old_reviewer":
        crossref["reviewed_by"] = "different-old-reviewer"
    elif mutation == "crossref_missing_old_batch":
        del crossref["decision_batch"]
    elif mutation == "crossref_wrong_old_batch":
        crossref["decision_batch"] = 1
    elif mutation == "crossref_different_old_batch":
        crossref["decision_batch"] = "different-old-batch"
    elif mutation == "crossref_missing_resolved_by":
        del crossref["resolved_by"]
    elif mutation == "crossref_empty_resolved_by":
        crossref["resolved_by"] = ""
    elif mutation == "crossref_wrong_resolved_by":
        crossref["resolved_by"] = 1
    elif mutation == "crossref_different_resolved_by":
        crossref["resolved_by"] = "different-resolution-reviewer"
    elif mutation == "crossref_missing_resolution_batch":
        del crossref["resolution_batch"]
    elif mutation == "crossref_empty_resolution_batch":
        crossref["resolution_batch"] = ""
    elif mutation == "crossref_wrong_resolution_batch":
        crossref["resolution_batch"] = 1
    elif mutation == "crossref_different_resolution_batch":
        crossref["resolution_batch"] = "different-resolution-batch"
    elif mutation == "structural_wrong_disposition":
        structural["disposition"] = "unmatched_new_review"
    elif mutation == "structural_wrong_kind":
        structural["record_kind"] = "unclassified"
    elif mutation == "structural_owner":
        structural["baseline_record_keys"] = ["old-owner"]
    elif mutation == "structural_wrong_basis":
        structural["classification_basis"] = "wrong"
    elif mutation == "structural_missing_reviewer":
        del structural["reviewed_by"]
    elif mutation == "structural_wrong_reviewer":
        structural["reviewed_by"] = 1
    elif mutation == "structural_different_reviewer":
        structural["reviewed_by"] = "different-structural-reviewer"
    elif mutation == "structural_missing_batch":
        del structural["decision_batch"]
    elif mutation == "structural_wrong_batch":
        structural["decision_batch"] = 1
    elif mutation == "structural_different_batch":
        structural["decision_batch"] = "different-structural-batch"
    elif mutation == "structural_annotation":
        structural["human_annotation"] = {"note": "not allowed"}

    digest = hashlib.sha256(encoded(source)).hexdigest()
    with pytest.raises(DecisionError):
        apply_decisions(
            source,
            later_nonperson_decision_document(digest),
            reconciliation_sha256=digest,
        )


def test_nonperson_classification_keeps_machine_structural_history_compatible():
    source = genuinely_new_reconciliation()
    source["new_entries"].append({
        "new_record_key": "machine-structural",
        "record_kind": "structural_context",
        "source_span": {"char_from": 30, "char_to": 40},
        "baseline_record_keys": [],
        "disposition": "accepted_structural_context",
    })
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        genuinely_new_decision_document(digest),
        reconciliation_sha256=digest,
    )

    machine = result["new_entries"][1]
    assert machine["disposition"] == "accepted_structural_context"
    assert "classification_basis" not in machine
    assert "classification_history" not in machine
    assert "classification_history_sha256" not in machine


@pytest.mark.parametrize("mutation", [
    "crossref_missing_history",
    "crossref_extra_history_field",
    "crossref_invalid_source_hash",
    "crossref_wrong_source_hash_type",
    "crossref_different_source_hash",
    "crossref_wrong_annotation_reviewer_mirror",
    "crossref_wrong_annotation_batch_mirror",
    "crossref_wrong_resolution_reviewer_mirror",
    "crossref_wrong_resolution_batch_mirror",
    "crossref_missing_history_digest",
    "crossref_invalid_history_digest",
    "crossref_wrong_history_digest",
    "structural_missing_history",
    "structural_extra_history_field",
    "structural_invalid_source_hash",
    "structural_wrong_source_hash_type",
    "structural_different_source_hash",
    "structural_wrong_reviewer_mirror",
    "structural_wrong_batch_mirror",
    "structural_missing_history_digest",
    "structural_invalid_history_digest",
    "structural_wrong_history_digest",
])
def test_nonperson_classification_rejects_malformed_or_mismatched_history(mutation):
    source = later_nonperson_reconciliation()
    structural, crossref = source["new_entries"][:2]
    target = crossref if mutation.startswith("crossref_") else structural
    if mutation.endswith("missing_history"):
        del target["classification_history"]
    elif mutation.endswith("missing_history_digest"):
        del target["classification_history_sha256"]
    elif mutation.endswith("invalid_history_digest"):
        target["classification_history_sha256"] = "not-a-hash"
    elif mutation.endswith("wrong_history_digest"):
        target["classification_history_sha256"] = "c" * 64
    elif mutation.endswith("extra_history_field"):
        target["classification_history"]["unexpected"] = True
    elif mutation.endswith("invalid_source_hash"):
        target["classification_history"]["source_reconciliation_sha256"] = "not-a-hash"
    elif mutation.endswith("wrong_source_hash_type"):
        target["classification_history"]["source_reconciliation_sha256"] = 1
    elif mutation.endswith("different_source_hash"):
        target["classification_history"]["source_reconciliation_sha256"] = "c" * 64
    elif mutation == "crossref_wrong_annotation_reviewer_mirror":
        target["classification_history"]["annotation_reviewed_by"] = "different"
    elif mutation == "crossref_wrong_annotation_batch_mirror":
        target["classification_history"]["annotation_decision_batch"] = "different"
    elif mutation == "crossref_wrong_resolution_reviewer_mirror":
        target["classification_history"]["resolution_reviewed_by"] = "different"
    elif mutation == "crossref_wrong_resolution_batch_mirror":
        target["classification_history"]["resolution_decision_batch"] = "different"
    elif mutation == "structural_wrong_reviewer_mirror":
        target["classification_history"]["classification_reviewed_by"] = "different"
    elif mutation == "structural_wrong_batch_mirror":
        target["classification_history"]["classification_decision_batch"] = "different"

    digest = hashlib.sha256(encoded(source)).hexdigest()
    with pytest.raises(DecisionError):
        apply_decisions(
            source,
            later_nonperson_decision_document(digest),
            reconciliation_sha256=digest,
        )


def spanless_adoption_reconciliation():
    """One spanless unresolved baseline and one accepted, ownerless target."""
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "baseline_entries": [{
            "baseline_record_key": "old-spanless",
            "name": "Recovered Person",
            "matches": [],
            "unresolved_reason": "narrative_not_exact",
            "disposition": "unresolved",
        }],
        "new_entries": [{
            "new_record_key": "new-genuine",
            "record_kind": "unclassified",
            "source_span": {"char_from": 10, "char_to": 20},
            "baseline_record_keys": [],
            "disposition": "accepted_genuinely_new_source_record",
            "acceptance_basis": "human_verified_genuinely_new_source_record",
            "reviewed_by": "old-reviewer",
            "decision_batch": "old-batch",
        }],
        "report": {"reconciliation_gate": "NO-GO"},
    }


def spanless_adoption_decision_document(reconciliation_sha256, decisions=None):
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "reconciliation_sha256": reconciliation_sha256,
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "reviewed_by": "new-reviewer",
        "decision_batch": "spanless-adoption-batch-1",
        "decisions": decisions or [{
            "baseline_record_key": "old-spanless",
            "decision_kind": "adopt_genuinely_new_target",
            "selected_new_record_key": "new-genuine",
            "selected_new_source_span": {"char_from": 10, "char_to": 20},
            "reason": "spanless_baseline_exact_source_recovery",
        }],
    }


def test_spanless_adoption_recovers_baseline_and_preserves_genuine_new_provenance():
    source = spanless_adoption_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        spanless_adoption_decision_document(digest),
        reconciliation_sha256=digest,
    )

    baseline = result["baseline_entries"][0]
    assert "source_span" not in baseline
    assert baseline["matches"] == [{
        "new_record_key": "new-genuine",
        "geometry_relation": "human_recovered_spanless_baseline",
    }]
    assert baseline["selected_new_record_key"] == "new-genuine"
    assert baseline["disposition"] == "accepted_carryover"
    assert baseline["reconciliation_basis"] == "human_adopted_spanless_baseline"
    assert baseline["reviewed_by"] == "new-reviewer"
    assert baseline["decision_batch"] == "spanless-adoption-batch-1"
    assert baseline["spanless_baseline_recovery"] == {
        "selected_new_source_span": {"char_from": 10, "char_to": 20},
        "reason": "spanless_baseline_exact_source_recovery",
    }

    target = result["new_entries"][0]
    assert target["baseline_record_keys"] == ["old-spanless"]
    assert target["disposition"] == "accepted_carryover"
    assert target["reconciliation_basis"] == "human_adopted_spanless_baseline"
    assert target["reviewed_by"] == "new-reviewer"
    assert target["decision_batch"] == "spanless-adoption-batch-1"
    assert "acceptance_basis" not in target
    assert target["prior_genuinely_new_acceptance"] == {
        "acceptance_basis": "human_verified_genuinely_new_source_record",
        "reviewed_by": "old-reviewer",
        "decision_batch": "old-batch",
    }


def test_spanless_adoption_resolves_two_independent_pairs_and_report_counts():
    source = spanless_adoption_reconciliation()
    source["baseline_entries"].append({
        "baseline_record_key": "old-spanless-second",
        "name": "Second Recovered Person",
        "matches": [],
        "unresolved_reason": "narrative_not_exact",
        "disposition": "unresolved",
    })
    source["new_entries"].append({
        "new_record_key": "new-genuine-second",
        "record_kind": "unclassified",
        "source_span": {"char_from": 30, "char_to": 40},
        "baseline_record_keys": [],
        "disposition": "accepted_genuinely_new_source_record",
        "acceptance_basis": "human_verified_genuinely_new_source_record",
        "reviewed_by": "old-reviewer-second",
        "decision_batch": "old-batch-second",
    })
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = spanless_adoption_decision_document(digest, [{
        "baseline_record_key": "old-spanless",
        "decision_kind": "adopt_genuinely_new_target",
        "selected_new_record_key": "new-genuine",
        "selected_new_source_span": {"char_from": 10, "char_to": 20},
        "reason": "spanless_baseline_exact_source_recovery",
    }, {
        "baseline_record_key": "old-spanless-second",
        "decision_kind": "adopt_genuinely_new_target",
        "selected_new_record_key": "new-genuine-second",
        "selected_new_source_span": {"char_from": 30, "char_to": 40},
        "reason": "spanless_baseline_exact_source_recovery",
    }])

    result = apply_decisions(source, document, reconciliation_sha256=digest)

    assert [entry["selected_new_record_key"] for entry in result["baseline_entries"]] == [
        "new-genuine", "new-genuine-second",
    ]
    assert [entry["baseline_record_keys"] for entry in result["new_entries"]] == [
        ["old-spanless"], ["old-spanless-second"],
    ]
    assert result["report"] == {
        "baseline_total": 2,
        "new_total": 2,
        "applied_decisions": 2,
        "accepted_carryovers": 2,
        "retired_duplicates": 0,
        "retired_fragments": 0,
        "baseline_dispositions": {"accepted_carryover": 2},
        "new_dispositions": {"accepted_carryover": 2},
        "remaining_baseline_review": 0,
        "remaining_new_review": 0,
        "reconciliation_gate": "GO",
    }


@pytest.mark.parametrize("mutation", [
    "baseline_source_span",
    "baseline_missing_unresolved_reason",
    "baseline_wrong_unresolved_reason",
    "baseline_existing_match",
    "baseline_selected_target",
    "baseline_reconciliation_basis",
    "baseline_reviewer",
    "baseline_batch",
    "baseline_annotation",
    "baseline_prior_adoption",
    "baseline_target_only_prior_acceptance",
    "target_wrong_disposition",
    "target_wrong_kind",
    "target_wrong_span",
    "target_declared_owner",
    "target_hidden_forward_owner",
    "target_annotation",
    "target_reconciliation_basis",
    "target_prior_adoption",
    "target_missing_acceptance_basis",
    "target_empty_acceptance_basis",
    "target_wrong_type_acceptance_basis",
    "target_wrong_value_acceptance_basis",
    "target_missing_reviewer",
    "target_empty_reviewer",
    "target_wrong_type_reviewer",
    "target_missing_batch",
    "target_empty_batch",
    "target_wrong_type_batch",
])
def test_spanless_adoption_rejects_any_unproven_input(mutation):
    source = spanless_adoption_reconciliation()
    baseline = source["baseline_entries"][0]
    target = source["new_entries"][0]
    if mutation == "baseline_source_span":
        baseline["source_span"] = {"char_from": 0, "char_to": 10}
    elif mutation == "baseline_missing_unresolved_reason":
        del baseline["unresolved_reason"]
    elif mutation == "baseline_wrong_unresolved_reason":
        baseline["unresolved_reason"] = "unique_exact_narrative_outside_new_record"
    elif mutation == "baseline_existing_match":
        baseline["matches"] = [{"new_record_key": "new-genuine"}]
    elif mutation == "baseline_selected_target":
        baseline["selected_new_record_key"] = "new-genuine"
    elif mutation == "baseline_reconciliation_basis":
        baseline["reconciliation_basis"] = "human_selected_split_target"
    elif mutation == "baseline_reviewer":
        baseline["reviewed_by"] = "prior-reviewer"
    elif mutation == "baseline_batch":
        baseline["decision_batch"] = "prior-batch"
    elif mutation == "baseline_annotation":
        baseline["human_annotation"] = {"note": "not allowed"}
    elif mutation == "baseline_prior_adoption":
        baseline["spanless_baseline_recovery"] = {"reason": "not allowed"}
    elif mutation == "baseline_target_only_prior_acceptance":
        baseline["prior_genuinely_new_acceptance"] = {
            "acceptance_basis": "human_verified_genuinely_new_source_record",
            "reviewed_by": "old-reviewer",
            "decision_batch": "old-batch",
        }
    elif mutation == "target_wrong_disposition":
        target["disposition"] = "unmatched_new_review"
    elif mutation == "target_wrong_kind":
        target["record_kind"] = "cross_reference"
    elif mutation == "target_wrong_span":
        target["source_span"] = {"char_from": 10, "char_to": 21}
    elif mutation == "target_declared_owner":
        target["baseline_record_keys"] = ["old-spanless"]
    elif mutation == "target_hidden_forward_owner":
        source["baseline_entries"].append({
            "baseline_record_key": "old-hidden",
            "matches": [{"new_record_key": "new-genuine"}],
            "disposition": "unresolved",
            "unresolved_reason": "narrative_not_exact",
        })
        target["baseline_record_keys"] = ["old-hidden"]
    elif mutation == "target_annotation":
        target["human_annotation"] = {"note": "not allowed"}
    elif mutation == "target_reconciliation_basis":
        target["reconciliation_basis"] = "human_selected_split_target"
    elif mutation == "target_prior_adoption":
        target["prior_genuinely_new_acceptance"] = {}
    elif mutation in {"target_missing_reviewer", "target_empty_reviewer", "target_wrong_type_reviewer"}:
        field = "reviewed_by"
        if mutation.startswith("target_missing_"):
            del target[field]
        elif mutation.startswith("target_empty_"):
            target[field] = ""
        else:
            target[field] = []
    elif mutation in {"target_missing_batch", "target_empty_batch", "target_wrong_type_batch"}:
        field = "decision_batch"
        if mutation.startswith("target_missing_"):
            del target[field]
        elif mutation.startswith("target_empty_"):
            target[field] = ""
        else:
            target[field] = []
    elif mutation.startswith("target_missing_"):
        del target[mutation.removeprefix("target_missing_")]
    elif mutation.startswith("target_empty_"):
        target[mutation.removeprefix("target_empty_")] = ""
    elif mutation.startswith("target_wrong_type_"):
        target[mutation.removeprefix("target_wrong_type_")] = []
    elif mutation == "target_wrong_value_acceptance_basis":
        target["acceptance_basis"] = "not-human-verified"
    else:
        raise AssertionError(mutation)
    digest = hashlib.sha256(encoded(source)).hexdigest()

    with pytest.raises(DecisionError):
        apply_decisions(
            source,
            spanless_adoption_decision_document(digest),
            reconciliation_sha256=digest,
        )


@pytest.mark.parametrize("mutation", [
    "missing_baseline_key",
    "missing_decision_kind",
    "missing_selected_target",
    "missing_selected_span",
    "missing_reason",
    "extra_field",
    "unknown_baseline",
    "unknown_target",
    "duplicate_baseline",
    "two_baselines_one_target",
    "wrong_reason",
    "stale_reconciliation_hash",
    "stale_baseline_hash",
    "stale_calamari_hash",
])
def test_spanless_adoption_rejects_malformed_or_stale_decisions(mutation):
    source = spanless_adoption_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = spanless_adoption_decision_document(digest)
    decision = document["decisions"][0]
    if mutation.startswith("missing_"):
        field = {
            "missing_baseline_key": "baseline_record_key",
            "missing_decision_kind": "decision_kind",
            "missing_selected_target": "selected_new_record_key",
            "missing_selected_span": "selected_new_source_span",
            "missing_reason": "reason",
        }[mutation]
        del decision[field]
    elif mutation == "extra_field":
        decision["note"] = "not allowed"
    elif mutation == "unknown_baseline":
        decision["baseline_record_key"] = "missing"
    elif mutation == "unknown_target":
        decision["selected_new_record_key"] = "missing"
    elif mutation == "duplicate_baseline":
        document["decisions"].append(copy.deepcopy(decision))
    elif mutation == "two_baselines_one_target":
        source["baseline_entries"].append({
            "baseline_record_key": "old-spanless-second",
            "matches": [],
            "unresolved_reason": "narrative_not_exact",
            "disposition": "unresolved",
        })
        digest = hashlib.sha256(encoded(source)).hexdigest()
        document = spanless_adoption_decision_document(digest, [decision, {
            "baseline_record_key": "old-spanless-second",
            "decision_kind": "adopt_genuinely_new_target",
            "selected_new_record_key": "new-genuine",
            "selected_new_source_span": {"char_from": 10, "char_to": 20},
            "reason": "spanless_baseline_exact_source_recovery",
        }])
    elif mutation == "wrong_reason":
        decision["reason"] = "similarity"
    elif mutation == "stale_reconciliation_hash":
        document["source"]["reconciliation_sha256"] = "c" * 64
    elif mutation == "stale_baseline_hash":
        document["source"]["baseline_sha256"] = "c" * 64
    elif mutation == "stale_calamari_hash":
        document["source"]["calamari_sha256"] = "c" * 64
    else:
        raise AssertionError(mutation)

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def historical_spanless_adoption_reconciliation():
    source = spanless_adoption_reconciliation()
    source["baseline_entries"][0].update({
        "matches": [{
            "new_record_key": "new-genuine",
            "geometry_relation": "human_recovered_spanless_baseline",
        }],
        "selected_new_record_key": "new-genuine",
        "disposition": "accepted_carryover",
        "reconciliation_basis": "human_adopted_spanless_baseline",
        "reviewed_by": "new-reviewer",
        "decision_batch": "spanless-adoption-batch-1",
        "spanless_baseline_recovery": {
            "selected_new_source_span": {"char_from": 10, "char_to": 20},
            "reason": "spanless_baseline_exact_source_recovery",
        },
    })
    source["new_entries"][0].pop("acceptance_basis")
    source["new_entries"][0].update({
        "baseline_record_keys": ["old-spanless"],
        "disposition": "accepted_carryover",
        "reconciliation_basis": "human_adopted_spanless_baseline",
        "reviewed_by": "new-reviewer",
        "decision_batch": "spanless-adoption-batch-1",
        "prior_genuinely_new_acceptance": {
            "acceptance_basis": "human_verified_genuinely_new_source_record",
            "reviewed_by": "old-reviewer",
            "decision_batch": "old-batch",
        },
    })
    return source


def later_batch_with_historical_spanless_adoption():
    source = historical_spanless_adoption_reconciliation()
    source["baseline_entries"].append({
        "baseline_record_key": "old-fresh-boundary",
        "matches": [{"new_record_key": "new-fresh-boundary"}],
        "disposition": "boundary_change_review",
    })
    source["new_entries"].append({
        "new_record_key": "new-fresh-boundary",
        "source_span": {"char_from": 30, "char_to": 40},
        "baseline_record_keys": ["old-fresh-boundary"],
        "disposition": "boundary_change_review",
    })
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = decision_document(digest)
    document["decisions"] = [{
        "baseline_record_key": "old-fresh-boundary",
        "decision_kind": "accept_boundary_change",
        "selected_new_record_key": "new-fresh-boundary",
    }]
    return source, document, digest


def test_later_batch_preserves_spanless_adoption_graph_and_prior_provenance():
    source, document, digest = later_batch_with_historical_spanless_adoption()
    prior_baseline = copy.deepcopy(source["baseline_entries"][0])
    prior_target = copy.deepcopy(source["new_entries"][0])

    result = apply_decisions(source, document, reconciliation_sha256=digest)

    assert result["baseline_entries"][0] == prior_baseline
    assert result["new_entries"][0] == prior_target
    assert result["baseline_entries"][0]["matches"] == [{
        "new_record_key": "new-genuine",
        "geometry_relation": "human_recovered_spanless_baseline",
    }]
    assert result["new_entries"][0]["baseline_record_keys"] == ["old-spanless"]
    assert result["new_entries"][0]["prior_genuinely_new_acceptance"] == {
        "acceptance_basis": "human_verified_genuinely_new_source_record",
        "reviewed_by": "old-reviewer",
        "decision_batch": "old-batch",
    }


def test_later_batch_rejects_target_only_prior_acceptance_on_adopted_spanless_adoption_baseline():
    source = spanless_adoption_reconciliation()
    first_digest = hashlib.sha256(encoded(source)).hexdigest()
    adopted = apply_decisions(
        source,
        spanless_adoption_decision_document(first_digest),
        reconciliation_sha256=first_digest,
    )
    adopted["baseline_entries"][0]["prior_genuinely_new_acceptance"] = {
        "acceptance_basis": "human_verified_genuinely_new_source_record",
        "reviewed_by": "old-reviewer",
        "decision_batch": "old-batch",
    }
    adopted["baseline_entries"].append({
        "baseline_record_key": "old-fresh-boundary",
        "matches": [{"new_record_key": "new-fresh-boundary"}],
        "disposition": "boundary_change_review",
    })
    adopted["new_entries"].append({
        "new_record_key": "new-fresh-boundary",
        "source_span": {"char_from": 30, "char_to": 40},
        "baseline_record_keys": ["old-fresh-boundary"],
        "disposition": "boundary_change_review",
    })
    later_digest = hashlib.sha256(encoded(adopted)).hexdigest()
    later_document = decision_document(later_digest)
    later_document["decisions"] = [{
        "baseline_record_key": "old-fresh-boundary",
        "decision_kind": "accept_boundary_change",
        "selected_new_record_key": "new-fresh-boundary",
    }]

    with pytest.raises(DecisionError):
        apply_decisions(adopted, later_document, reconciliation_sha256=later_digest)


@pytest.mark.parametrize("mutation", [
    "baseline_missing_match",
    "baseline_wrong_match_key",
    "baseline_wrong_match_geometry",
    "baseline_missing_selected_key",
    "baseline_wrong_selected_key",
    "baseline_wrong_basis",
    "baseline_missing_recovery",
    "baseline_missing_recovery_span",
    "baseline_wrong_recovery_span",
    "baseline_missing_recovery_reason",
    "baseline_wrong_recovery_reason",
    "baseline_missing_reviewer",
    "baseline_wrong_reviewer",
    "baseline_missing_batch",
    "baseline_wrong_batch",
    "target_missing_owners",
    "target_extra_owner",
    "target_wrong_disposition",
    "target_missing_basis",
    "target_wrong_basis",
    "target_missing_reviewer",
    "target_wrong_reviewer",
    "target_missing_batch",
    "target_wrong_batch",
    "target_reintroduced_acceptance_basis",
    "target_missing_prior",
    "target_missing_prior_acceptance_basis",
    "target_wrong_prior_acceptance_basis",
    "target_missing_prior_reviewer",
    "target_wrong_prior_reviewer",
    "target_missing_prior_batch",
    "target_wrong_prior_batch",
])
def test_later_batch_rejects_each_corrupt_spanless_adoption_field(mutation):
    source, document, _ = later_batch_with_historical_spanless_adoption()
    baseline = source["baseline_entries"][0]
    target = source["new_entries"][0]
    if mutation == "baseline_missing_match":
        baseline["matches"] = []
    elif mutation == "baseline_wrong_match_key":
        baseline["matches"][0]["new_record_key"] = "new-fresh-boundary"
    elif mutation == "baseline_wrong_match_geometry":
        baseline["matches"][0]["geometry_relation"] = "old_inside_new"
    elif mutation == "baseline_missing_selected_key":
        del baseline["selected_new_record_key"]
    elif mutation == "baseline_wrong_selected_key":
        baseline["selected_new_record_key"] = "new-fresh-boundary"
    elif mutation == "baseline_wrong_basis":
        baseline["reconciliation_basis"] = "human_selected_split_target"
    elif mutation == "baseline_missing_recovery":
        del baseline["spanless_baseline_recovery"]
    elif mutation == "baseline_missing_recovery_span":
        del baseline["spanless_baseline_recovery"]["selected_new_source_span"]
    elif mutation == "baseline_wrong_recovery_span":
        baseline["spanless_baseline_recovery"]["selected_new_source_span"] = {
            "char_from": 10, "char_to": 21,
        }
    elif mutation == "baseline_missing_recovery_reason":
        del baseline["spanless_baseline_recovery"]["reason"]
    elif mutation == "baseline_wrong_recovery_reason":
        baseline["spanless_baseline_recovery"]["reason"] = "similarity"
    elif mutation == "baseline_missing_reviewer":
        del baseline["reviewed_by"]
    elif mutation == "baseline_wrong_reviewer":
        baseline["reviewed_by"] = "wrong-reviewer"
    elif mutation == "baseline_missing_batch":
        del baseline["decision_batch"]
    elif mutation == "baseline_wrong_batch":
        baseline["decision_batch"] = "wrong-batch"
    elif mutation == "target_missing_owners":
        target["baseline_record_keys"] = []
    elif mutation == "target_extra_owner":
        target["baseline_record_keys"].append("old-fresh-boundary")
    elif mutation == "target_wrong_disposition":
        target["disposition"] = "unmatched_new_review"
    elif mutation == "target_missing_basis":
        del target["reconciliation_basis"]
    elif mutation == "target_wrong_basis":
        target["reconciliation_basis"] = "human_selected_split_target"
    elif mutation == "target_missing_reviewer":
        del target["reviewed_by"]
    elif mutation == "target_wrong_reviewer":
        target["reviewed_by"] = "wrong-reviewer"
    elif mutation == "target_missing_batch":
        del target["decision_batch"]
    elif mutation == "target_wrong_batch":
        target["decision_batch"] = "wrong-batch"
    elif mutation == "target_reintroduced_acceptance_basis":
        target["acceptance_basis"] = "human_verified_genuinely_new_source_record"
    elif mutation == "target_missing_prior":
        del target["prior_genuinely_new_acceptance"]
    elif mutation.startswith("target_missing_prior_"):
        field = {
            "acceptance_basis": "acceptance_basis",
            "reviewer": "reviewed_by",
            "batch": "decision_batch",
        }[mutation.removeprefix("target_missing_prior_")]
        del target["prior_genuinely_new_acceptance"][field]
    elif mutation.startswith("target_wrong_prior_"):
        field = {
            "acceptance_basis": "acceptance_basis",
            "reviewer": "reviewed_by",
            "batch": "decision_batch",
        }[mutation.removeprefix("target_wrong_prior_")]
        target["prior_genuinely_new_acceptance"][field] = (
            "wrong-value" if field == "acceptance_basis" else []
        )
    else:
        raise AssertionError(mutation)
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document["source"]["reconciliation_sha256"] = digest

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def genuinely_new_decision_document(reconciliation_sha256, decisions=None):
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "reconciliation_sha256": reconciliation_sha256,
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "reviewed_by": "johan-reventlow",
        "decision_batch": "genuinely-new-batch-1",
        "decisions": decisions or [{
            "decision_kind": "accept_genuinely_new",
            "new_record_key": "new-genuine",
            "new_source_span": {"char_from": 10, "char_to": 20},
            "record_kind": "unclassified",
            "reason": "visually_verified_distinct_source_record",
        }],
    }


def apply_genuinely_new(source=None, document=None):
    source = source or genuinely_new_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    return apply_decisions(
        source,
        document or genuinely_new_decision_document(digest),
        reconciliation_sha256=digest,
    )


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


def continuation_fragment_reconciliation():
    source = reconciliation()
    source["baseline_entries"] = [
        {
            "baseline_record_key": "old-canonical",
            "name": "Hedevig Ida",
            "source_span": {"char_from": 0, "char_to": 10},
            "matches": [{
                "new_record_key": "new-a",
                "geometry_relation": "old_inside_new",
            }],
            "disposition": "merge_review",
        },
        {
            "baseline_record_key": "old-fragment",
            "source_span": {"char_from": 10, "char_to": 20},
            "matches": [{
                "new_record_key": "new-a",
                "geometry_relation": "old_inside_new",
            }],
            "disposition": "merge_review",
        },
    ]
    source["new_entries"] = [{
        "new_record_key": "new-a",
        "source_span": {"char_from": 0, "char_to": 20},
        "baseline_record_keys": ["old-canonical", "old-fragment"],
        "disposition": "merge_review",
    }]
    return source


def continuation_fragment_decision_document(reconciliation_sha256):
    document = decision_document(reconciliation_sha256)
    document["decisions"] = [{
        "baseline_record_key": "old-fragment",
        "decision_kind": "retire_continuation_fragment",
        "canonical_baseline_record_key": "old-canonical",
        "new_record_key": "new-a",
        "reason": "continuation_extraction_fragment",
    }]
    return document


def embedded_spanless_fragment_reconciliation():
    source = reconciliation()
    source["baseline_entries"] = [
        {
            "baseline_record_key": "old-canonical",
            "name": "Conrad Reventlow",
            "source_span": {"char_from": 0, "char_to": 100},
            "matches": [{
                "new_record_key": "new-a",
                "geometry_relation": "partial_overlap",
            }],
            "disposition": "unchanged",
            "reconciliation_basis": "unique_exact_narrative_inside_new",
        },
        {
            "baseline_record_key": "old-fragment",
            "name": "fyenske Rytterreg.)",
            "matches": [],
            "unresolved_reason": "narrative_not_exact",
            "disposition": "unresolved",
        },
    ]
    source["new_entries"] = [{
        "new_record_key": "new-a",
        "record_kind": "unclassified",
        "source_span": {"char_from": 0, "char_to": 90},
        "baseline_record_keys": ["old-canonical"],
        "disposition": "unchanged",
    }]
    return source


def embedded_spanless_fragment_decision_document(reconciliation_sha256):
    document = decision_document(reconciliation_sha256)
    document["decisions"] = [{
        "baseline_record_key": "old-fragment",
        "decision_kind": "retire_embedded_spanless_fragment",
        "canonical_baseline_record_key": "old-canonical",
        "new_record_key": "new-a",
        "embedded_source_span": {"char_from": 20, "char_to": 39},
        "embedded_fragment_text": "fyenske Rytterreg.)",
        "reason": "embedded_text_fragment_of_canonical_record",
    }]
    return document


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def apply(document=None, source=None):
    source = source or reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    return apply_decisions(source, document or decision_document(digest),
                           reconciliation_sha256=digest)


def test_accepts_one_visually_verified_genuinely_new_source_record():
    source = genuinely_new_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    decisions = genuinely_new_decision_document(digest)

    result = apply_decisions(source, decisions, reconciliation_sha256=digest)

    accepted = result["new_entries"][0]
    assert result["baseline_entries"] == source["baseline_entries"]
    assert accepted["baseline_record_keys"] == []
    assert accepted["disposition"] == "accepted_genuinely_new_source_record"
    assert accepted["acceptance_basis"] == "human_verified_genuinely_new_source_record"
    assert accepted["reviewed_by"] == decisions["reviewed_by"]
    assert accepted["decision_batch"] == decisions["decision_batch"]
    assert result["report"]["remaining_new_review"] == 0
    assert result["report"]["reconciliation_gate"] == "GO"


def test_accepts_multiple_distinct_ownerless_genuinely_new_source_records():
    source = genuinely_new_reconciliation()
    source["new_entries"].append({
        "new_record_key": "new-genuine-second",
        "record_kind": "unclassified",
        "source_span": {"char_from": 20, "char_to": 30},
        "baseline_record_keys": [],
        "disposition": "unmatched_new_review",
    })
    digest = hashlib.sha256(encoded(source)).hexdigest()
    decisions = genuinely_new_decision_document(digest, decisions=[
        {
            "decision_kind": "accept_genuinely_new",
            "new_record_key": "new-genuine",
            "new_source_span": {"char_from": 10, "char_to": 20},
            "record_kind": "unclassified",
            "reason": "visually_verified_distinct_source_record",
        },
        {
            "decision_kind": "accept_genuinely_new",
            "new_record_key": "new-genuine-second",
            "new_source_span": {"char_from": 20, "char_to": 30},
            "record_kind": "unclassified",
            "reason": "visually_verified_distinct_source_record",
        },
    ])

    result = apply_decisions(source, decisions, reconciliation_sha256=digest)

    assert [entry["disposition"] for entry in result["new_entries"]] == [
        "accepted_genuinely_new_source_record",
        "accepted_genuinely_new_source_record",
    ]
    assert all(entry["baseline_record_keys"] == [] for entry in result["new_entries"])
    assert result["report"]["reconciliation_gate"] == "GO"


@pytest.mark.parametrize("mutation", [
    {"new_record_key": "missing"},
    {"new_source_span": {"char_from": 10, "char_to": 21}},
    {"new_source_span": {"char_from": 20, "char_to": 20}},
    {"record_kind": "structural_context"},
    {"reason": "name_match"},
    {"extra": True},
])
def test_genuinely_new_acceptance_rejects_wrong_closed_decision(mutation):
    source = genuinely_new_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = genuinely_new_decision_document(digest)
    document["decisions"][0].update(mutation)

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


@pytest.mark.parametrize("mutation", [
    "declared_owner",
    "hidden_forward_owner",
    "malformed_reverse_owners",
    "duplicate_reverse_owners",
    "accepted_structural_context",
    "human_annotation",
    "acceptance_basis",
    "reviewed_by",
    "decision_batch",
])
def test_genuinely_new_acceptance_rejects_non_ownerless_or_preannotated_target(mutation):
    source = genuinely_new_reconciliation()
    target = source["new_entries"][0]
    if mutation in {"declared_owner", "malformed_reverse_owners", "duplicate_reverse_owners"}:
        source["baseline_entries"].append({
            "baseline_record_key": "old-owner",
            "matches": [{"new_record_key": "new-genuine"}],
            "disposition": "boundary_change_review",
        })
    if mutation == "declared_owner":
        target["baseline_record_keys"] = ["old-owner"]
    elif mutation == "hidden_forward_owner":
        source["baseline_entries"].append({
            "baseline_record_key": "old-hidden-owner",
            "matches": [{"new_record_key": "new-genuine"}],
            "disposition": "boundary_change_review",
        })
    elif mutation == "malformed_reverse_owners":
        target["baseline_record_keys"] = "old-owner"
    elif mutation == "duplicate_reverse_owners":
        target["baseline_record_keys"] = ["old-owner", "old-owner"]
    elif mutation == "accepted_structural_context":
        target["disposition"] = "accepted_structural_context"
    elif mutation == "human_annotation":
        target["human_annotation"] = {"note": "prior"}
    else:
        target[mutation] = "prior"
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = genuinely_new_decision_document(digest)

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_genuinely_new_acceptance_rejects_structural_target_kind():
    source = genuinely_new_reconciliation()
    source["new_entries"][0]["record_kind"] = "structural_context"
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = genuinely_new_decision_document(digest)

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_genuinely_new_acceptance_rejects_second_ownerless_decision_for_same_target():
    source = genuinely_new_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    duplicate = genuinely_new_decision_document(digest)
    duplicate["decisions"].append(dict(duplicate["decisions"][0]))

    with pytest.raises(DecisionError, match="flere beslutninger bruger samme new_record_key"):
        apply_decisions(source, duplicate, reconciliation_sha256=digest)


def test_genuinely_new_acceptance_rejects_stale_source_hashes():
    source = genuinely_new_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    for field in ("reconciliation_sha256", "baseline_sha256", "calamari_sha256"):
        document = genuinely_new_decision_document(digest)
        document["source"][field] = "c" * 64
        with pytest.raises(DecisionError):
            apply_decisions(source, document, reconciliation_sha256=digest)


def later_batch_after_genuinely_new_acceptance():
    first_source = genuinely_new_reconciliation()
    first = apply_genuinely_new(source=first_source)
    second_source = copy.deepcopy(first)
    second_source["baseline_entries"].append({
        "baseline_record_key": "old-fresh-boundary",
        "matches": [{
            "new_record_key": "new-fresh-boundary",
            "geometry_relation": "new_inside_old",
        }],
        "disposition": "boundary_change_review",
    })
    second_source["new_entries"].append({
        "new_record_key": "new-fresh-boundary",
        "record_kind": "unclassified",
        "source_span": {"char_from": 30, "char_to": 40},
        "baseline_record_keys": ["old-fresh-boundary"],
        "disposition": "boundary_change_review",
    })
    second_digest = hashlib.sha256(encoded(second_source)).hexdigest()
    second_document = decision_document(second_digest)
    second_document["decisions"] = [{
        "baseline_record_key": "old-fresh-boundary",
        "decision_kind": "accept_boundary_change",
        "selected_new_record_key": "new-fresh-boundary",
    }]
    return second_source, second_document, second_digest


@pytest.mark.parametrize("mutation", [
    "consistent_nonempty_owner",
    "inconsistent_nonempty_owner",
    "wrong_kind",
    "missing_acceptance_basis",
    "wrong_acceptance_basis",
    "human_annotation",
    "missing_reviewed_by",
    "empty_reviewed_by",
    "wrong_type_reviewed_by",
    "missing_decision_batch",
    "empty_decision_batch",
    "wrong_type_decision_batch",
])
def test_later_batch_rejects_malformed_genuinely_new_acceptance(mutation):
    source, document, _ = later_batch_after_genuinely_new_acceptance()
    accepted = source["new_entries"][0]
    if mutation == "consistent_nonempty_owner":
        source["baseline_entries"].append({
            "baseline_record_key": "old-prior-owner",
            "matches": [{"new_record_key": "new-genuine"}],
            "disposition": "boundary_change_review",
        })
        accepted["baseline_record_keys"] = ["old-prior-owner"]
    elif mutation == "inconsistent_nonempty_owner":
        accepted["baseline_record_keys"] = ["old-ghost-owner"]
    elif mutation == "wrong_kind":
        accepted["record_kind"] = "structural_context"
    elif mutation == "missing_acceptance_basis":
        accepted.pop("acceptance_basis")
    elif mutation == "wrong_acceptance_basis":
        accepted["acceptance_basis"] = "unverified"
    elif mutation == "human_annotation":
        accepted["human_annotation"] = {"note": "contradictory-history"}
    elif mutation == "missing_reviewed_by":
        accepted.pop("reviewed_by")
    elif mutation == "empty_reviewed_by":
        accepted["reviewed_by"] = ""
    elif mutation == "wrong_type_reviewed_by":
        accepted["reviewed_by"] = []
    elif mutation == "missing_decision_batch":
        accepted.pop("decision_batch")
    elif mutation == "empty_decision_batch":
        accepted["decision_batch"] = ""
    elif mutation == "wrong_type_decision_batch":
        accepted["decision_batch"] = []
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document["source"]["reconciliation_sha256"] = digest

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_later_batch_preserves_genuinely_new_acceptance_provenance():
    second_source, second_document, second_digest = (
        later_batch_after_genuinely_new_acceptance()
    )
    prior = copy.deepcopy(second_source["new_entries"][0])

    result = apply_decisions(
        second_source, second_document, reconciliation_sha256=second_digest,
    )

    genuinely_new = next(
        entry for entry in result["new_entries"]
        if entry["new_record_key"] == "new-genuine"
    )
    assert genuinely_new == prior


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


def test_retires_contiguous_continuation_fragment_and_retains_only_canonical_owner():
    source = continuation_fragment_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        continuation_fragment_decision_document(digest),
        reconciliation_sha256=digest,
    )

    canonical, fragment = result["baseline_entries"]
    assert canonical["matches"] == [{
        "new_record_key": "new-a", "geometry_relation": "old_inside_new",
    }]
    assert canonical["selected_new_record_key"] == "new-a"
    assert canonical["disposition"] == "accepted_carryover"
    assert canonical["reconciliation_basis"] == "human_accepted_contiguous_merge"
    assert canonical["reviewed_by"] == "johan-reventlow"
    assert canonical["decision_batch"] == "batch-1"
    assert fragment["matches"] == []
    assert fragment["disposition"] == "retired_fragment"
    assert fragment["canonical_baseline_record_key"] == "old-canonical"
    assert fragment["retirement_reason"] == "continuation_extraction_fragment"
    assert fragment["reviewed_by"] == "johan-reventlow"
    assert fragment["decision_batch"] == "batch-1"
    assert result["new_entries"][0]["baseline_record_keys"] == ["old-canonical"]
    assert result["new_entries"][0]["disposition"] == "accepted_carryover"
    assert result["report"]["accepted_carryovers"] == 1
    assert result["report"]["retired_fragments"] == 1
    assert result["report"]["remaining_baseline_review"] == 0
    assert result["report"]["remaining_new_review"] == 0
    assert result["report"]["reconciliation_gate"] == "GO"


def test_retires_embedded_spanless_fragment_without_changing_canonical_graph():
    source = embedded_spanless_fragment_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        embedded_spanless_fragment_decision_document(digest),
        reconciliation_sha256=digest,
    )

    canonical, fragment = result["baseline_entries"]
    assert canonical == source["baseline_entries"][0]
    assert result["new_entries"] == source["new_entries"]
    assert fragment["matches"] == []
    assert fragment["disposition"] == "retired_fragment"
    assert fragment["canonical_baseline_record_key"] == "old-canonical"
    assert fragment["retirement_reason"] == "embedded_text_fragment_of_canonical_record"
    assert fragment["reviewed_by"] == "johan-reventlow"
    assert fragment["decision_batch"] == "batch-1"
    history = fragment["embedded_fragment_retirement"]
    assert history == {
        "source_reconciliation_sha256": digest,
        "canonical_baseline_record_key": "old-canonical",
        "new_record_key": "new-a",
        "embedded_source_span": {"char_from": 20, "char_to": 39},
        "embedded_fragment_text": "fyenske Rytterreg.)",
        "reason": "embedded_text_fragment_of_canonical_record",
        "reviewed_by": "johan-reventlow",
        "decision_batch": "batch-1",
    }
    assert fragment["embedded_fragment_retirement_sha256"] == (
        classification_history_sha256(history)
    )
    assert result["report"]["retired_fragments"] == 1
    assert result["report"]["remaining_baseline_review"] == 0
    assert result["report"]["remaining_new_review"] == 0
    assert result["report"]["reconciliation_gate"] == "GO"


@pytest.mark.parametrize("mutation", [
    "fragment_has_span",
    "fragment_not_unresolved",
    "fragment_has_match",
    "wrong_unresolved_reason",
    "text_not_exact_name",
    "canonical_not_resolved",
    "canonical_wrong_target",
    "target_wrong_owner",
    "span_outside_canonical",
    "span_outside_target",
    "wrong_reason",
    "extra_field",
    "duplicate_decision",
])
def test_embedded_spanless_fragment_retirement_fails_closed(mutation):
    source = embedded_spanless_fragment_reconciliation()
    if mutation == "fragment_has_span":
        source["baseline_entries"][1]["source_span"] = {"char_from": 20, "char_to": 39}
    elif mutation == "fragment_not_unresolved":
        source["baseline_entries"][1]["disposition"] = "unchanged"
    elif mutation == "fragment_has_match":
        source["baseline_entries"][1]["matches"] = [{"new_record_key": "new-a"}]
        source["new_entries"][0]["baseline_record_keys"].append("old-fragment")
    elif mutation == "wrong_unresolved_reason":
        source["baseline_entries"][1]["unresolved_reason"] = "not_found"
    elif mutation == "text_not_exact_name":
        source["baseline_entries"][1]["name"] = "different fragment"
    elif mutation == "canonical_not_resolved":
        source["baseline_entries"][0]["disposition"] = "merge_review"
        source["new_entries"][0]["disposition"] = "merge_review"
    elif mutation == "canonical_wrong_target":
        source["baseline_entries"][0]["matches"][0]["new_record_key"] = "new-b"
        source["new_entries"].append({
            "new_record_key": "new-b", "record_kind": "unclassified",
            "source_span": {"char_from": 0, "char_to": 100},
            "baseline_record_keys": ["old-canonical"], "disposition": "unchanged",
        })
        source["new_entries"][0]["baseline_record_keys"] = []
    elif mutation == "target_wrong_owner":
        source["new_entries"][0]["baseline_record_keys"] = []
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = embedded_spanless_fragment_decision_document(digest)
    decision = document["decisions"][0]
    if mutation == "span_outside_canonical":
        decision["embedded_source_span"] = {"char_from": 100, "char_to": 110}
    elif mutation == "span_outside_target":
        decision["embedded_source_span"] = {"char_from": 90, "char_to": 100}
    elif mutation == "wrong_reason":
        decision["reason"] = "continuation_extraction_fragment"
    elif mutation == "extra_field":
        decision["note"] = "looks embedded"
    elif mutation == "duplicate_decision":
        document["decisions"].append(copy.deepcopy(decision))

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_later_batch_preserves_and_validates_embedded_spanless_fragment_history():
    source = embedded_spanless_fragment_reconciliation()
    first_digest = hashlib.sha256(encoded(source)).hexdigest()
    first = apply_decisions(
        source,
        embedded_spanless_fragment_decision_document(first_digest),
        reconciliation_sha256=first_digest,
    )
    prior_fragment = copy.deepcopy(first["baseline_entries"][1])
    first["baseline_entries"].append({
        "baseline_record_key": "old-fresh",
        "matches": [{"new_record_key": "new-fresh"}],
        "disposition": "boundary_change_review",
    })
    first["new_entries"].append({
        "new_record_key": "new-fresh",
        "record_kind": "unclassified",
        "source_span": {"char_from": 110, "char_to": 120},
        "baseline_record_keys": ["old-fresh"],
        "disposition": "boundary_change_review",
    })
    second_digest = hashlib.sha256(encoded(first)).hexdigest()
    document = decision_document(second_digest)
    document["decisions"] = [{
        "baseline_record_key": "old-fresh",
        "decision_kind": "accept_boundary_change",
        "selected_new_record_key": "new-fresh",
    }]

    result = apply_decisions(first, document, reconciliation_sha256=second_digest)

    assert result["baseline_entries"][1] == prior_fragment
    assert result["report"]["retired_fragments"] == 1

    for mutation in ("reviewed_by", "embedded_source_span", "history_digest"):
        corrupt = copy.deepcopy(first)
        fragment = corrupt["baseline_entries"][1]
        if mutation == "reviewed_by":
            fragment["reviewed_by"] = "different-reviewer"
        elif mutation == "embedded_source_span":
            fragment["embedded_fragment_retirement"]["embedded_source_span"] = {
                "char_from": 21, "char_to": 39,
            }
        else:
            fragment["embedded_fragment_retirement_sha256"] = "a" * 64
        corrupt_digest = hashlib.sha256(encoded(corrupt)).hexdigest()
        corrupt_document = decision_document(corrupt_digest)
        corrupt_document["decisions"] = copy.deepcopy(document["decisions"])
        with pytest.raises(DecisionError):
            apply_decisions(
                corrupt, corrupt_document, reconciliation_sha256=corrupt_digest,
            )


@pytest.mark.parametrize("mutation", [
    "baseline_not_merge_review",
    "target_not_merge_review",
    "different_target",
    "non_contiguous_spans",
    "reversed_spans",
    "canonical_outside_target",
    "fragment_outside_target",
    "extra_owner",
    "target_ghost_owner",
    "target_missing_owner",
    "target_duplicate_owner",
    "target_invalid_owner_type",
    "unknown_canonical_key",
    "unknown_fragment_key",
    "unknown_target_key",
    "stale_reconciliation_hash",
    "unexpected_field",
])
def test_continuation_fragment_retirement_fails_closed_on_unproven_or_drifted_input(mutation):
    source = continuation_fragment_reconciliation()
    if mutation == "baseline_not_merge_review":
        source["baseline_entries"][0]["disposition"] = "unchanged"
    elif mutation == "target_not_merge_review":
        source["new_entries"][0]["disposition"] = "unchanged"
    elif mutation == "different_target":
        source["baseline_entries"][1]["matches"][0]["new_record_key"] = "new-b"
        source["new_entries"].append({
            "new_record_key": "new-b",
            "source_span": {"char_from": 10, "char_to": 20},
            "baseline_record_keys": ["old-fragment"],
            "disposition": "merge_review",
        })
    elif mutation == "non_contiguous_spans":
        source["baseline_entries"][1]["source_span"] = {"char_from": 12, "char_to": 20}
    elif mutation == "reversed_spans":
        source["baseline_entries"][0]["source_span"] = {"char_from": 10, "char_to": 20}
        source["baseline_entries"][1]["source_span"] = {"char_from": 0, "char_to": 10}
    elif mutation == "canonical_outside_target":
        source["new_entries"][0]["source_span"] = {"char_from": 1, "char_to": 20}
    elif mutation == "fragment_outside_target":
        source["new_entries"][0]["source_span"] = {"char_from": 0, "char_to": 19}
    elif mutation == "extra_owner":
        source["baseline_entries"].append({
            "baseline_record_key": "old-extra",
            "source_span": {"char_from": 20, "char_to": 30},
            "matches": [{
                "new_record_key": "new-a", "geometry_relation": "partial_overlap",
            }],
            "disposition": "merge_review",
        })
        source["new_entries"][0]["baseline_record_keys"].append("old-extra")
    elif mutation == "target_ghost_owner":
        source["new_entries"][0]["baseline_record_keys"].append("old-ghost")
    elif mutation == "target_missing_owner":
        source["new_entries"][0]["baseline_record_keys"] = ["old-canonical"]
    elif mutation == "target_duplicate_owner":
        source["new_entries"][0]["baseline_record_keys"].append("old-fragment")
    elif mutation == "target_invalid_owner_type":
        source["new_entries"][0]["baseline_record_keys"] = "old-canonical"
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = continuation_fragment_decision_document(digest)
    decision = document["decisions"][0]
    if mutation == "unknown_canonical_key":
        decision["canonical_baseline_record_key"] = "missing"
    elif mutation == "unknown_fragment_key":
        decision["baseline_record_key"] = "missing"
    elif mutation == "unknown_target_key":
        decision["new_record_key"] = "missing"
    elif mutation == "stale_reconciliation_hash":
        document["source"]["reconciliation_sha256"] = "c" * 64
    elif mutation == "unexpected_field":
        decision["note"] = "contiguous"

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_later_batch_preserves_continuation_fragment_history_and_report_counts():
    source = continuation_fragment_reconciliation()
    first_digest = hashlib.sha256(encoded(source)).hexdigest()
    first = apply_decisions(
        source,
        continuation_fragment_decision_document(first_digest),
        reconciliation_sha256=first_digest,
    )
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
        "baseline_record_key": "old-fresh-boundary",
        "name": "Fresh Boundary",
        "matches": [{
            "new_record_key": "new-fresh-boundary",
            "geometry_relation": "new_inside_old",
        }],
        "disposition": "boundary_change_review",
    })
    second_source["new_entries"].append({
        "new_record_key": "new-fresh-boundary",
        "record_kind": "unclassified",
        "source_span": {"char_from": 20, "char_to": 30},
        "baseline_record_keys": ["old-fresh-boundary"],
        "disposition": "boundary_change_review",
    })
    second_digest = hashlib.sha256(encoded(second_source)).hexdigest()
    second_document = decision_document(second_digest)
    second_document["decisions"] = [{
        "baseline_record_key": "old-fresh-boundary",
        "decision_kind": "accept_boundary_change",
        "selected_new_record_key": "new-fresh-boundary",
    }]

    result = apply_decisions(
        second_source, second_document, reconciliation_sha256=second_digest,
    )

    result_baseline = {
        entry["baseline_record_key"]: entry for entry in result["baseline_entries"]
    }
    result_new = {
        entry["new_record_key"]: entry for entry in result["new_entries"]
    }
    for key, entry in prior_baseline.items():
        assert result_baseline[key] == entry
    for key, entry in prior_new.items():
        assert result_new[key] == entry
    assert result["report"]["accepted_carryovers"] == 2
    assert result["report"]["retired_fragments"] == 1
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


def legacy_anchor_reconciliation():
    """Two repairs: one disjoint and one partially overlapping source span."""
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "baseline_entries": [
            {
                "baseline_record_key": "old-margrethe",
                "name": "Margrethe",
                "source_span": {"char_from": 50370, "char_to": 50568},
                "matches": [],
                "disposition": "unresolved",
                "unresolved_reason": "unique_exact_narrative_outside_new_record",
            },
            {
                "baseline_record_key": "old-iwen",
                "name": "Iwen",
                "source_span": {"char_from": 182918, "char_to": 183074},
                "matches": [],
                "disposition": "unresolved",
                "unresolved_reason": "unique_exact_narrative_outside_new_record",
            },
        ],
        "new_entries": [
            {
                "new_record_key": "new-margrethe",
                "source_span": {"char_from": 49214, "char_to": 49537},
                "baseline_record_keys": [],
                "disposition": "unmatched_new_review",
            },
            {
                "new_record_key": "new-iwen",
                "source_span": {"char_from": 182918, "char_to": 183021},
                "baseline_record_keys": [],
                "disposition": "unmatched_new_review",
            },
        ],
        "report": {"reconciliation_gate": "NO-GO"},
    }


def legacy_anchor_decision_document(reconciliation_sha256):
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "reconciliation_sha256": reconciliation_sha256,
            "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64,
        },
        "reviewed_by": "johan-reventlow",
        "decision_batch": "legacy-anchor-repair-v1",
        "decisions": [
            {
                "baseline_record_key": "old-margrethe",
                "decision_kind": "repair_legacy_anchor",
                "selected_new_record_key": "new-margrethe",
                "stale_source_span": {"char_from": 50370, "char_to": 50568},
                "selected_new_source_span": {"char_from": 49214, "char_to": 49537},
                "discarded_source_spans": [{"char_from": 50370, "char_to": 50568}],
                "reason": "neighbor_record_contamination",
            },
            {
                "baseline_record_key": "old-iwen",
                "decision_kind": "repair_legacy_anchor",
                "selected_new_record_key": "new-iwen",
                "stale_source_span": {"char_from": 182918, "char_to": 183074},
                "selected_new_source_span": {"char_from": 182918, "char_to": 183021},
                "discarded_source_spans": [{"char_from": 183021, "char_to": 183074}],
                "reason": "neighbor_record_contamination",
            },
        ],
    }


def test_repairs_disjoint_and_overlapping_legacy_anchors_with_complete_provenance():
    source = legacy_anchor_reconciliation()
    original = copy.deepcopy(source)
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        legacy_anchor_decision_document(digest),
        reconciliation_sha256=digest,
    )

    baseline = {entry["baseline_record_key"]: entry for entry in result["baseline_entries"]}
    new = {entry["new_record_key"]: entry for entry in result["new_entries"]}
    assert baseline["old-margrethe"]["source_span"] == {"char_from": 50370, "char_to": 50568}
    assert baseline["old-iwen"]["source_span"] == {"char_from": 182918, "char_to": 183074}
    for old_key, new_key, stale, target, discarded in [
        ("old-margrethe", "new-margrethe", {"char_from": 50370, "char_to": 50568},
         {"char_from": 49214, "char_to": 49537}, [{"char_from": 50370, "char_to": 50568}]),
        ("old-iwen", "new-iwen", {"char_from": 182918, "char_to": 183074},
         {"char_from": 182918, "char_to": 183021}, [{"char_from": 183021, "char_to": 183074}]),
    ]:
        entry = baseline[old_key]
        assert entry["matches"] == [{
            "new_record_key": new_key,
            "geometry_relation": "human_repaired_legacy_anchor",
        }]
        assert entry["selected_new_record_key"] == new_key
        assert entry["disposition"] == "accepted_carryover"
        assert entry["reconciliation_basis"] == "human_repaired_legacy_anchor"
        assert entry["reviewed_by"] == "johan-reventlow"
        assert entry["decision_batch"] == "legacy-anchor-repair-v1"
        assert entry["legacy_anchor_repair"] == {
            "stale_source_span": stale,
            "selected_new_source_span": target,
            "discarded_source_spans": discarded,
            "reason": "neighbor_record_contamination",
        }
        assert new[new_key]["baseline_record_keys"] == [old_key]
        assert new[new_key]["disposition"] == "accepted_carryover"
    assert result["report"] == {
        "baseline_total": 2,
        "new_total": 2,
        "applied_decisions": 2,
        "accepted_carryovers": 2,
        "retired_duplicates": 0,
        "retired_fragments": 0,
        "baseline_dispositions": {"accepted_carryover": 2},
        "new_dispositions": {"accepted_carryover": 2},
        "remaining_baseline_review": 0,
        "remaining_new_review": 0,
        "reconciliation_gate": "GO",
    }
    assert {
        before["baseline_record_key"]
        for before, after in zip(original["baseline_entries"], result["baseline_entries"])
        if before != after
    } == {"old-margrethe", "old-iwen"}
    assert {
        before["new_record_key"]
        for before, after in zip(original["new_entries"], result["new_entries"])
        if before != after
    } == {"new-margrethe", "new-iwen"}


@pytest.mark.parametrize("mutation", [
    "wrong_baseline_disposition",
    "wrong_unresolved_reason",
    "baseline_has_match",
    "target_not_unmatched",
    "target_ghost_owner",
    "target_duplicate_owner",
    "target_malformed_owners",
    "target_previously_annotated",
    "target_hidden_forward_owner",
    "target_unknown_owner",
    "stale_baseline_span",
    "wrong_declared_stale_span",
    "mismatched_target_span",
    "wrong_declared_target_span",
    "empty_discarded",
    "unsorted_discarded",
    "overlapping_discarded",
    "incomplete_discarded",
    "wrong_reason",
    "unknown_field",
    "unknown_target",
    "stale_reconciliation_hash",
    "stale_baseline_hash",
    "stale_calamari_hash",
])
def test_legacy_anchor_repair_fails_closed_on_unproven_or_drifted_input(mutation):
    source = legacy_anchor_reconciliation()
    if mutation == "wrong_baseline_disposition":
        source["baseline_entries"][0]["disposition"] = "boundary_change_review"
    elif mutation == "wrong_unresolved_reason":
        source["baseline_entries"][0]["unresolved_reason"] = "other"
    elif mutation == "baseline_has_match":
        source["baseline_entries"][0]["matches"] = [{"new_record_key": "new-margrethe"}]
    elif mutation == "target_not_unmatched":
        source["new_entries"][0]["disposition"] = "accepted_carryover"
    elif mutation == "target_ghost_owner":
        source["new_entries"][0]["baseline_record_keys"] = ["ghost"]
    elif mutation == "target_duplicate_owner":
        source["new_entries"][0]["baseline_record_keys"] = ["old-margrethe", "old-margrethe"]
    elif mutation == "target_malformed_owners":
        source["new_entries"][0]["baseline_record_keys"] = "old-margrethe"
    elif mutation == "target_previously_annotated":
        source["new_entries"][0]["human_annotation"] = {
            "new_record_key": "new-margrethe",
            "record_kind": "cross_reference",
            "person_creation": "forbidden_without_separate_evidence",
        }
    elif mutation == "target_hidden_forward_owner":
        source["baseline_entries"].append({
            "baseline_record_key": "old-hidden-owner",
            "matches": [{"new_record_key": "new-margrethe"}],
            "disposition": "boundary_change_review",
        })
    elif mutation == "target_unknown_owner":
        source["new_entries"][0]["baseline_record_keys"] = ["old-missing"]
    elif mutation == "stale_baseline_span":
        source["baseline_entries"][0]["source_span"] = {"char_from": 50370, "char_to": 50567}
    elif mutation == "mismatched_target_span":
        source["new_entries"][0]["source_span"] = {"char_from": 49214, "char_to": 49536}
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = legacy_anchor_decision_document(digest)
    decision = document["decisions"][0]
    if mutation == "empty_discarded":
        decision["discarded_source_spans"] = []
    elif mutation == "unsorted_discarded":
        decision["discarded_source_spans"] = [
            {"char_from": 50400, "char_to": 50568},
            {"char_from": 50370, "char_to": 50400},
        ]
    elif mutation == "overlapping_discarded":
        decision["discarded_source_spans"] = [
            {"char_from": 50370, "char_to": 50400},
            {"char_from": 50399, "char_to": 50568},
        ]
    elif mutation == "incomplete_discarded":
        decision["discarded_source_spans"] = [{"char_from": 50370, "char_to": 50567}]
    elif mutation == "wrong_declared_stale_span":
        decision["stale_source_span"] = {"char_from": 50370, "char_to": 50567}
    elif mutation == "wrong_declared_target_span":
        decision["selected_new_source_span"] = {"char_from": 49214, "char_to": 49536}
    elif mutation == "wrong_reason":
        decision["reason"] = "similarity"
    elif mutation == "unknown_field":
        decision["note"] = "not allowed"
    elif mutation == "unknown_target":
        decision["selected_new_record_key"] = "missing"
    elif mutation == "stale_reconciliation_hash":
        document["source"]["reconciliation_sha256"] = "c" * 64
    elif mutation == "stale_baseline_hash":
        document["source"]["baseline_sha256"] = "c" * 64
    elif mutation == "stale_calamari_hash":
        document["source"]["calamari_sha256"] = "c" * 64

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_legacy_anchor_repair_rejects_same_batch_target_reuse():
    source = legacy_anchor_reconciliation()
    source["baseline_entries"].append({
        "baseline_record_key": "old-extra",
        "source_span": {"char_from": 60000, "char_to": 60010},
        "matches": [],
        "disposition": "unresolved",
        "unresolved_reason": "unique_exact_narrative_outside_new_record",
    })
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = legacy_anchor_decision_document(digest)
    document["decisions"].append({
        "baseline_record_key": "old-extra",
        "decision_kind": "repair_legacy_anchor",
        "selected_new_record_key": "new-margrethe",
        "stale_source_span": {"char_from": 60000, "char_to": 60010},
        "selected_new_source_span": {"char_from": 49214, "char_to": 49537},
        "discarded_source_spans": [{"char_from": 60000, "char_to": 60010}],
        "reason": "neighbor_record_contamination",
    })

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)


def test_later_batch_preserves_legacy_anchor_repair_metadata_and_report_counts():
    source = legacy_anchor_reconciliation()
    first_digest = hashlib.sha256(encoded(source)).hexdigest()
    first = apply_decisions(
        source,
        legacy_anchor_decision_document(first_digest),
        reconciliation_sha256=first_digest,
    )
    prior_baseline = copy.deepcopy(first["baseline_entries"])
    prior_new = copy.deepcopy(first["new_entries"])
    second_source = copy.deepcopy(first)
    second_source["baseline_entries"].append({
        "baseline_record_key": "old-fresh-boundary",
        "matches": [{"new_record_key": "new-fresh-boundary"}],
        "disposition": "boundary_change_review",
    })
    second_source["new_entries"].append({
        "new_record_key": "new-fresh-boundary",
        "source_span": {"char_from": 70000, "char_to": 70010},
        "baseline_record_keys": ["old-fresh-boundary"],
        "disposition": "boundary_change_review",
    })
    second_digest = hashlib.sha256(encoded(second_source)).hexdigest()
    second_document = decision_document(second_digest)
    second_document["decisions"] = [{
        "baseline_record_key": "old-fresh-boundary",
        "decision_kind": "accept_boundary_change",
        "selected_new_record_key": "new-fresh-boundary",
    }]

    result = apply_decisions(
        second_source, second_document, reconciliation_sha256=second_digest,
    )

    assert result["baseline_entries"][:2] == prior_baseline
    assert result["new_entries"][:2] == prior_new
    assert result["report"]["accepted_carryovers"] == 3
    assert result["report"]["remaining_baseline_review"] == 0
    assert result["report"]["remaining_new_review"] == 0


def test_later_batch_cannot_annotate_a_previously_repaired_legacy_anchor_target():
    source = legacy_anchor_reconciliation()
    first_digest = hashlib.sha256(encoded(source)).hexdigest()
    first = apply_decisions(
        source,
        legacy_anchor_decision_document(first_digest),
        reconciliation_sha256=first_digest,
    )
    second_source = copy.deepcopy(first)
    second_source["baseline_entries"].append({
        "baseline_record_key": "old-fresh-split",
        "matches": [
            {"new_record_key": "new-fresh-split"},
            {"new_record_key": "new-iwen"},
        ],
        "disposition": "split_review",
    })
    second_source["new_entries"].append({
        "new_record_key": "new-fresh-split",
        "source_span": {"char_from": 70000, "char_to": 70010},
        "baseline_record_keys": ["old-fresh-split"],
        "disposition": "split_review",
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
        "reviewed_by": "later-reviewer",
        "decision_batch": "later-batch",
        "decisions": [{
            "baseline_record_key": "old-fresh-split",
            "decision_kind": "select_carryover_target",
            "selected_new_record_key": "new-fresh-split",
            "nonselected_action": "retain_distinct_source_records",
            "record_annotations": [{
                "new_record_key": "new-iwen",
                "record_kind": "cross_reference",
                "person_creation": "forbidden_without_separate_evidence",
            }],
        }],
    }

    with pytest.raises(DecisionError):
        apply_decisions(
            second_source, second_document, reconciliation_sha256=second_digest,
        )


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
