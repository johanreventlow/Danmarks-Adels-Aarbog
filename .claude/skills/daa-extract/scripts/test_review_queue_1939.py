"""Tests for the fail-closed 1939 exception queue classifier."""

from __future__ import annotations

import copy

import pytest

from review_queue_1939 import classify_review_entries, sample_auto_resolved


def source(**overrides):
    value = {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }
    value.update(overrides)
    return value


def anchored_candidate(candidate_id="candidate-1", postklasse="nummereret"):
    return {
        "candidate_id": candidate_id,
        "postklasse": postklasse,
        "calamari_span": {"char_from": 10, "char_to": 20},
        "pdf_pages": [498],
        "raw_structure_bridge": {
            "kind": "record_start",
            "raw_char_from": 100,
            "raw_char_to": 110,
            "raw_excerpt_sha256": "e" * 64,
        },
    }


def automatic(key, rule_id="complete_anchor_v1", postklasse="nummereret"):
    return {
        "baseline_record_key": key,
        "queue_class": "auto_resolved",
        "reason_code": "complete_unique_anchored_candidate",
        "reason_da": "komplet",
        "candidate": anchored_candidate(key),
        "rule_id": rule_id,
        "postklasse": postklasse,
    }


def human(key):
    return {
        "baseline_record_key": key,
        "queue_class": "human_required",
        "reason_code": "no_candidate",
        "reason_da": "ingen kandidat",
    }


def queue_manifest(*entries, source_hash="a" * 64):
    return {
        "schema_version": 1,
        "source": source(baseline_sha256=source_hash),
        "entries": list(entries),
    }


def evidence(key, candidate=None, *, source_blockers=None, **overrides):
    candidates = [] if candidate is None else [candidate]
    value = {
        "baseline_record_key": key,
        "candidates": candidates,
        "positive_provenance": (
            {
                "kind": "record_key_v2_locator",
                "baseline_record_key": key,
                "candidate_id": candidate["candidate_id"],
            }
            if candidate
            else None
        ),
        "conflicts": [],
        "source_blockers": source_blockers or [],
        "rule_id": "complete_anchor_v1",
    }
    value.update(overrides)
    return value


def test_complete_unique_candidate_is_auto_resolved():
    result = classify_review_entries(
        source(), {"rk-1"}, [evidence("rk-1", candidate=anchored_candidate())]
    )
    assert result["entries"] == [
        {
            "baseline_record_key": "rk-1",
            "queue_class": "auto_resolved",
            "reason_code": "complete_unique_anchored_candidate",
            "reason_da": "Én komplet, entydig og konfliktfri kildebro.",
            "candidate": anchored_candidate(),
            "rule_id": "complete_anchor_v1",
            "postklasse": "nummereret",
        }
    ]


@pytest.mark.parametrize(
    "mutation,reason",
    [
        (lambda e: e.update(positive_provenance=None), "missing_positive_provenance"),
        (lambda e: e.update(conflicts=["locator_collision"]), "evidence_conflict"),
        (
            lambda e: e["candidates"].append(anchored_candidate("candidate-2")),
            "multiple_candidates",
        ),
    ],
)
def test_missing_gate_requires_human(mutation, reason):
    entry = evidence("rk-1", candidate=anchored_candidate())
    mutation(entry)
    result = classify_review_entries(source(), {"rk-1"}, [entry])
    assert result["entries"][0]["queue_class"] == "human_required"
    assert result["entries"][0]["reason_code"] == reason


def test_missing_source_material_is_source_blocked():
    result = classify_review_entries(
        source(), {"rk-1"}, [evidence("rk-1", source_blockers=["raw_ocr_missing"])]
    )
    assert result["entries"][0]["queue_class"] == "source_blocked"
    assert result["entries"][0]["reason_code"] == "raw_ocr_missing"


@pytest.mark.parametrize(
    "candidate_mutation",
    [
        lambda c: c.update(postklasse="ukendt"),
        lambda c: c.update(pdf_pages=[]),
        lambda c: c["raw_structure_bridge"].update(raw_char_to=100),
    ],
)
def test_invalid_candidate_never_becomes_automatic(candidate_mutation):
    candidate = anchored_candidate()
    candidate_mutation(candidate)
    with pytest.raises(ValueError):
        classify_review_entries(source(), {"rk-1"}, [evidence("rk-1", candidate)])


@pytest.mark.parametrize(
    "field,value",
    [
        ("baseline_sha256", "A" * 64),
        ("calamari_sha256", "not-a-hash"),
        ("raw_ocr_sha256", "c" * 63),
        ("pdf_sha256", None),
        ("profile_version", ""),
    ],
)
def test_malformed_source_manifest_is_rejected(field, value):
    with pytest.raises(ValueError):
        classify_review_entries(source(**{field: value}), {"rk-1"}, [evidence("rk-1")])


def test_duplicate_or_missing_baseline_evidence_is_rejected():
    with pytest.raises(ValueError, match="dublet baseline_record_key"):
        classify_review_entries(
            source(), {"rk-1"}, [evidence("rk-1"), evidence("rk-1")]
        )
    with pytest.raises(ValueError, match="baseline-dækning"):
        classify_review_entries(source(), {"rk-1", "rk-2"}, [evidence("rk-1")])


def test_boolean_positive_provenance_requires_human_review():
    result = classify_review_entries(
        source(),
        {"rk-1"},
        [evidence("rk-1", anchored_candidate(), positive_provenance=True)],
    )
    assert result["entries"][0]["queue_class"] == "human_required"
    assert result["entries"][0]["reason_code"] == "missing_positive_provenance"


def test_duplicate_candidate_ids_demote_all_automatic_entries():
    candidate_a = anchored_candidate("candidate-shared")
    candidate_b = anchored_candidate("candidate-shared")
    candidate_b["calamari_span"] = {"char_from": 30, "char_to": 40}
    result = classify_review_entries(
        source(),
        {"rk-a", "rk-b"},
        [evidence("rk-a", candidate_a), evidence("rk-b", candidate_b)],
    )
    assert [entry["queue_class"] for entry in result["entries"]] == [
        "human_required",
        "human_required",
    ]
    assert [entry["reason_code"] for entry in result["entries"]] == [
        "candidate_collision",
        "candidate_collision",
    ]


@pytest.mark.parametrize(
    "second_span",
    [{"char_from": 10, "char_to": 20}, {"char_from": 15, "char_to": 25}],
)
def test_equal_or_overlapping_calamari_spans_demote_all_automatic_entries(second_span):
    candidate_b = anchored_candidate("candidate-2")
    candidate_b["calamari_span"] = second_span
    result = classify_review_entries(
        source(),
        {"rk-a", "rk-b"},
        [evidence("rk-a", anchored_candidate("candidate-1")), evidence("rk-b", candidate_b)],
    )
    assert [entry["queue_class"] for entry in result["entries"]] == [
        "human_required",
        "human_required",
    ]
    assert [entry["reason_code"] for entry in result["entries"]] == [
        "calamari_span_overlap",
        "calamari_span_overlap",
    ]


@pytest.mark.parametrize(
    "second_raw_span",
    [
        {"raw_char_from": 100, "raw_char_to": 110},
        {"raw_char_from": 105, "raw_char_to": 115},
    ],
)
def test_equal_or_overlapping_raw_ocr_spans_demote_all_automatic_entries(
    second_raw_span,
):
    candidate_b = anchored_candidate("candidate-2")
    candidate_b["calamari_span"] = {"char_from": 30, "char_to": 40}
    candidate_b["raw_structure_bridge"].update(second_raw_span)
    result = classify_review_entries(
        source(),
        {"rk-a", "rk-b"},
        [evidence("rk-a", anchored_candidate("candidate-1")), evidence("rk-b", candidate_b)],
    )
    assert [entry["queue_class"] for entry in result["entries"]] == [
        "human_required",
        "human_required",
    ]
    assert [entry["reason_code"] for entry in result["entries"]] == [
        "raw_ocr_span_overlap",
        "raw_ocr_span_overlap",
    ]


def test_human_candidate_id_claim_demotes_otherwise_automatic_claimant():
    automatic = anchored_candidate("candidate-shared")
    human = anchored_candidate("candidate-shared")
    human["calamari_span"] = {"char_from": 30, "char_to": 40}
    human["raw_structure_bridge"].update(raw_char_from=300, raw_char_to=310)
    result = classify_review_entries(
        source(),
        {"rk-auto", "rk-human"},
        [
            evidence("rk-auto", automatic),
            evidence("rk-human", human, conflicts=["semantic_conflict"]),
        ],
    )
    assert [entry["queue_class"] for entry in result["entries"]] == [
        "human_required",
        "human_required",
    ]
    assert [entry["reason_code"] for entry in result["entries"]] == [
        "candidate_collision",
        "candidate_collision",
    ]


def test_human_calamari_claim_demotes_otherwise_automatic_claimant():
    automatic = anchored_candidate("candidate-auto")
    human = anchored_candidate("candidate-human")
    human["calamari_span"] = {"char_from": 15, "char_to": 25}
    human["raw_structure_bridge"].update(raw_char_from=300, raw_char_to=310)
    result = classify_review_entries(
        source(),
        {"rk-auto", "rk-human"},
        [
            evidence("rk-auto", automatic),
            evidence("rk-human", human, conflicts=["semantic_conflict"]),
        ],
    )
    assert [entry["queue_class"] for entry in result["entries"]] == [
        "human_required",
        "human_required",
    ]
    assert [entry["reason_code"] for entry in result["entries"]] == [
        "calamari_span_overlap",
        "calamari_span_overlap",
    ]


def test_human_raw_ocr_claim_demotes_otherwise_automatic_claimant():
    automatic = anchored_candidate("candidate-auto")
    human = anchored_candidate("candidate-human")
    human["calamari_span"] = {"char_from": 30, "char_to": 40}
    human["raw_structure_bridge"].update(raw_char_from=105, raw_char_to=115)
    result = classify_review_entries(
        source(),
        {"rk-auto", "rk-human"},
        [
            evidence("rk-auto", automatic),
            evidence("rk-human", human, conflicts=["semantic_conflict"]),
        ],
    )
    assert [entry["queue_class"] for entry in result["entries"]] == [
        "human_required",
        "human_required",
    ]
    assert [entry["reason_code"] for entry in result["entries"]] == [
        "raw_ocr_span_overlap",
        "raw_ocr_span_overlap",
    ]


def test_input_objects_are_not_mutated():
    input_source = source()
    input_baseline = {"rk-1"}
    input_evidence = [evidence("rk-1", anchored_candidate())]
    snapshot = copy.deepcopy((input_source, input_baseline, input_evidence))
    classify_review_entries(input_source, input_baseline, input_evidence)
    assert (input_source, input_baseline, input_evidence) == snapshot


def test_every_key_is_accounted_for_once():
    result = classify_review_entries(
        source(),
        {"rk-a", "rk-h", "rk-b"},
        [
            evidence("rk-a", anchored_candidate()),
            evidence("rk-h"),
            evidence("rk-b", source_blockers=["pdf_missing"]),
        ],
    )
    assert len(result["entries"]) == 3
    assert {entry["baseline_record_key"] for entry in result["entries"]} == {
        "rk-a",
        "rk-h",
        "rk-b",
    }


def test_sample_is_deterministic_stratified_and_automatic_only():
    manifest = queue_manifest(
        *[automatic(f"n-{i}", "complete_anchor_v1", "nummereret") for i in range(40)],
        *[
            automatic(f"o-{i}", "complete_anchor_v1", "oversigtspost")
            for i in range(10)
        ],
        human("human-1"),
    )
    first = sample_auto_resolved(manifest)
    second = sample_auto_resolved(copy.deepcopy(manifest))
    assert first == second
    assert len([key for key in first if key.startswith("n-")]) == 2
    assert len([key for key in first if key.startswith("o-")]) == 2
    assert "human-1" not in first


def test_changed_source_hash_changes_seed_not_membership_rules():
    entries = [automatic(f"rk-{i}") for i in range(100)]
    first = sample_auto_resolved(queue_manifest(*entries, source_hash="a" * 64))
    second = sample_auto_resolved(queue_manifest(*entries, source_hash="b" * 64))
    assert first != second
    assert len(first) == len(second)


def test_sample_empty_or_single_member_strata():
    assert sample_auto_resolved(queue_manifest(human("human-1"))) == []
    assert sample_auto_resolved(queue_manifest(automatic("only"))) == ["only"]


def test_sample_rate_zero_uses_minimum_and_rate_one_selects_everything():
    manifest = queue_manifest(*[automatic(f"rk-{i}") for i in range(5)])
    assert len(sample_auto_resolved(manifest, rate=0)) == 2
    assert sample_auto_resolved(manifest, rate=1) == [
        "rk-0",
        "rk-1",
        "rk-2",
        "rk-3",
        "rk-4",
    ]


@pytest.mark.parametrize("rate", [-0.01, 1.01])
def test_sample_rejects_rates_outside_closed_unit_interval(rate):
    with pytest.raises(ValueError):
        sample_auto_resolved(queue_manifest(automatic("rk-1")), rate=rate)


@pytest.mark.parametrize("minimum_per_stratum", [0, -1])
def test_sample_rejects_non_positive_minimum_per_stratum(minimum_per_stratum):
    with pytest.raises(ValueError):
        sample_auto_resolved(
            queue_manifest(automatic("rk-1")),
            minimum_per_stratum=minimum_per_stratum,
        )


def test_sample_is_independent_of_manifest_order_and_does_not_mutate_it():
    manifest = queue_manifest(
        *[automatic(f"n-{i}", postklasse="nummereret") for i in range(40)],
        *[automatic(f"o-{i}", postklasse="oversigtspost") for i in range(10)],
        human("human-1"),
    )
    snapshot = copy.deepcopy(manifest)
    reordered = copy.deepcopy(manifest)
    reordered["entries"].reverse()
    assert sample_auto_resolved(manifest) == sample_auto_resolved(reordered)
    assert manifest == snapshot


@pytest.mark.parametrize(
    "mutation",
    [
        lambda entry: entry.pop("candidate"),
        lambda entry: entry.update(queue_class="auto_resolved "),
        lambda entry: entry.update(reason_code="no_candidate"),
        lambda entry: entry.update(reason_da=""),
        lambda entry: entry.update(rule_id=""),
        lambda entry: entry.update(postklasse=""),
    ],
)
def test_sample_rejects_malformed_auto_resolved_entry(mutation):
    entry = automatic("rk-1")
    mutation(entry)
    with pytest.raises(ValueError):
        sample_auto_resolved(queue_manifest(entry))


def test_sample_rejects_candidate_with_invalid_identity():
    entry = automatic("rk-1")
    entry["candidate"]["candidate_id"] = ""
    with pytest.raises(ValueError):
        sample_auto_resolved(queue_manifest(entry))


@pytest.mark.parametrize(
    "entries",
    [
        (automatic("rk-1"), automatic("rk-1", rule_id="other_rule_v1")),
        (automatic("rk-1"), human("rk-1")),
    ],
)
def test_sample_rejects_duplicate_baseline_record_keys_across_manifest(entries):
    with pytest.raises(ValueError, match="dublet baseline_record_key"):
        sample_auto_resolved(queue_manifest(*entries))
