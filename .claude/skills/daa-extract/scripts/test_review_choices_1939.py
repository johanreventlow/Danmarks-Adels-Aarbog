"""Tests for versioned, fail-closed 1939 browser choice imports."""

from __future__ import annotations

import copy

import pytest

from review_choices_1939 import convert_review_choices, validate_choice_export


def choice(key, outcome, **fields):
    return {"baseline_record_key": key, "outcome": outcome, **fields}


def expected_source():
    return {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }


def choice_export(*entries):
    return {
        "schema_version": 1,
        "source": expected_source(),
        "exported_at": "2026-08-05T12:00:00+02:00",
        "entries": list(entries),
    }


def human(key):
    return {
        "baseline_record_key": key,
        "queue_class": "human_required",
        "reason_code": "multiple_candidates",
        "reason_da": "flere kandidater",
    }


def automatic(key, candidate_id):
    return {
        "baseline_record_key": key,
        "queue_class": "auto_resolved",
        "reason_code": "complete_unique_anchored_candidate",
        "reason_da": "komplet",
        "candidate": anchored_candidate(candidate_id),
        "rule_id": "complete_anchor_v1",
        "postklasse": "nummereret",
    }


def anchored_candidate(candidate_id, *, offset=0):
    return {
        "candidate_id": candidate_id,
        "postklasse": "nummereret",
        "calamari_span": {"char_from": 10 + offset, "char_to": 20 + offset},
        "pdf_pages": [498],
        "raw_structure_bridge": {
            "kind": "record_start",
            "raw_char_from": 100 + offset,
            "raw_char_to": 110 + offset,
            "raw_excerpt_sha256": "e" * 64,
        },
    }


def test_selected_candidate_promotes_only_when_exact_candidate_exists():
    converted = convert_review_choices(
        {"rk-1": choice("rk-1", "human_selected_candidate", candidate_id="c-1")},
        {"c-1": {"baseline_record_key": "rk-1", "candidate": anchored_candidate("c-1")}},
        {"rk-1": human("rk-1")},
        set(),
    )

    assert converted["decisions"] == [{
        "baseline_record_key": "rk-1", "status": "accepteret", "candidate_id": "c-1",
    }]
    assert converted["audit_results"] == []


def test_selected_candidate_without_exact_anchor_remains_parked():
    converted = convert_review_choices(
        {"rk-1": choice("rk-1", "human_selected_candidate", candidate_id="c-1")},
        {},
        {"rk-1": human("rk-1")},
        set(),
    )

    assert converted["decisions"] == [{
        "baseline_record_key": "rk-1",
        "status": "menneskeark",
        "reason": "human_selected_candidate_requires_exact_anchor:c-1",
    }]


def test_selected_candidate_with_wrong_record_owner_remains_parked():
    converted = convert_review_choices(
        {"rk-1": choice("rk-1", "human_selected_candidate", candidate_id="c-1")},
        {"c-1": {"baseline_record_key": "rk-2", "candidate": anchored_candidate("c-1")}},
        {"rk-1": human("rk-1"), "rk-2": human("rk-2")},
        set(),
    )

    assert converted["decisions"][0]["status"] == "menneskeark"
    assert converted["decisions"][0]["reason"].endswith(":c-1")


def test_malformed_selected_candidate_parks_only_that_choice():
    malformed = anchored_candidate("c-bad")
    malformed["postklasse"] = "ukendt"

    converted = convert_review_choices(
        {"rk-1": choice("rk-1", "human_selected_candidate", candidate_id="c-bad")},
        {"c-bad": {"baseline_record_key": "rk-1", "candidate": malformed}},
        {"rk-1": human("rk-1")},
        set(),
    )

    assert converted["decisions"] == [{
        "baseline_record_key": "rk-1",
        "status": "menneskeark",
        "reason": "human_selected_candidate_requires_exact_anchor:c-bad",
    }]


def test_malformed_unused_candidate_does_not_abort_unrelated_valid_choice():
    converted = convert_review_choices(
        {"rk-1": choice("rk-1", "human_selected_candidate", candidate_id="c-1")},
        {
            "c-1": {
                "baseline_record_key": "rk-1",
                "candidate": anchored_candidate("c-1"),
            },
            "unused-bad": {"candidate": "ikke en kandidat"},
        },
        {"rk-1": human("rk-1")},
        set(),
    )

    assert converted["decisions"] == [{
        "baseline_record_key": "rk-1", "status": "accepteret", "candidate_id": "c-1",
    }]


def test_selected_candidate_colliding_with_automatic_anchor_remains_parked():
    converted = convert_review_choices(
        {"rk-h": choice("rk-h", "human_selected_candidate", candidate_id="c-h")},
        {"c-h": {"baseline_record_key": "rk-h", "candidate": anchored_candidate("c-h")}},
        {"rk-a": automatic("rk-a", "c-a"), "rk-h": human("rk-h")},
        set(),
    )

    assert converted["decisions"] == [{
        "baseline_record_key": "rk-h",
        "status": "menneskeark",
        "reason": "human_selected_candidate_not_globally_injective:c-h",
    }]


def test_audit_disagreement_blocks_rule_without_replacing_automatic_decision():
    converted = convert_review_choices(
        {"rk-a": choice("rk-a", "no_candidate_fits", reason="teksten tilhører naboen")},
        {},
        {"rk-a": automatic("rk-a", candidate_id="c-a")},
        {"rk-a"},
    )

    assert converted["decisions"] == []
    assert converted["audit_results"] == [{
        "baseline_record_key": "rk-a",
        "audit_status": "audit_failed",
        "rule_id": "complete_anchor_v1",
        "reason": "teksten tilhører naboen",
    }]


def test_audit_agreement_confirms_existing_automatic_candidate_only():
    converted = convert_review_choices(
        {"rk-a": choice("rk-a", "human_selected_candidate", candidate_id="c-a")},
        {},
        {"rk-a": automatic("rk-a", candidate_id="c-a")},
        {"rk-a"},
    )

    assert converted == {
        "decisions": [],
        "audit_results": [{
            "baseline_record_key": "rk-a",
            "audit_status": "audit_confirmed",
            "rule_id": "complete_anchor_v1",
        }],
    }


def test_audit_selected_different_candidate_fails_with_stable_reason():
    converted = convert_review_choices(
        {"rk-a": choice("rk-a", "human_selected_candidate", candidate_id="c-other")},
        {},
        {"rk-a": automatic("rk-a", candidate_id="c-a")},
        {"rk-a"},
    )

    assert converted["audit_results"][0]["audit_status"] == "audit_failed"
    assert converted["audit_results"][0]["reason"] == "selected_different_candidate:c-other"


@pytest.mark.parametrize(
    ("target", "target_classification", "message"),
    [
        ("rk-unknown", {}, "ukendt dubletmål"),
        ("rk-a", {}, "sig selv"),
        ("rk-human", {"rk-human": human("rk-human")}, "dubletmål skal være accepteret"),
    ],
)
def test_audit_duplicate_rejects_unknown_or_nonaccepted_target(
    target, target_classification, message
):
    classifications = {"rk-a": automatic("rk-a", candidate_id="c-a")}
    classifications.update(target_classification)

    with pytest.raises(ValueError, match=message):
        convert_review_choices(
            {"rk-a": choice(
                "rk-a", "possible_duplicate", duplicate_of_baseline_record_key=target
            )},
            {},
            classifications,
            {"rk-a"},
        )


def test_audit_duplicate_with_accepted_target_emits_failure_without_rewrite():
    target = automatic("rk-target", candidate_id="c-target")
    target["candidate"] = anchored_candidate("c-target", offset=50)

    converted = convert_review_choices(
        {"rk-a": choice(
            "rk-a", "possible_duplicate", duplicate_of_baseline_record_key="rk-target"
        )},
        {},
        {"rk-a": automatic("rk-a", candidate_id="c-a"), "rk-target": target},
        {"rk-a"},
    )

    assert converted == {
        "decisions": [],
        "audit_results": [{
            "baseline_record_key": "rk-a",
            "audit_status": "audit_failed",
            "rule_id": "complete_anchor_v1",
            "reason": "possible_duplicate:rk-target",
        }],
    }


def test_choice_for_non_audit_automatic_record_is_rejected():
    with pytest.raises(ValueError, match="automatisk.*audit"):
        convert_review_choices(
            {"rk-a": choice("rk-a", "human_selected_candidate", candidate_id="c-a")},
            {},
            {"rk-a": automatic("rk-a", candidate_id="c-a")},
            set(),
        )


def test_required_non_candidate_outcomes_remain_explicit_and_parked():
    converted = convert_review_choices(
        {
            "rk-n": choice("rk-n", "no_candidate_fits", reason="ingen passer"),
            "rk-u": choice("rk-u", "undecidable", reason="uklar kilde"),
        },
        {},
        {"rk-n": human("rk-n"), "rk-u": human("rk-u")},
        set(),
    )

    assert converted["decisions"] == [
        {"baseline_record_key": "rk-n", "status": "menneskeark",
         "reason": "no_candidate_fits:ingen passer"},
        {"baseline_record_key": "rk-u", "status": "menneskeark",
         "reason": "undecidable:uklar kilde"},
    ]


def test_possible_duplicate_requires_an_accepted_distinct_target():
    choices = {
        "rk-1": choice(
            "rk-1", "possible_duplicate", duplicate_of_baseline_record_key="rk-2"
        )
    }
    with pytest.raises(ValueError, match="dubletmål skal være accepteret"):
        convert_review_choices(
            choices, {}, {"rk-1": human("rk-1"), "rk-2": human("rk-2")}, set()
        )

    converted = convert_review_choices(
        choices, {}, {"rk-1": human("rk-1"), "rk-2": automatic("rk-2", "c-2")}, set()
    )
    assert converted["decisions"] == [{
        "baseline_record_key": "rk-1",
        "status": "eksplicit_dublet",
        "duplicate_of_baseline_record_key": "rk-2",
    }]


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        (lambda root: root["source"].update(baseline_sha256="f" * 64), "source/version"),
        (lambda root: root["source"].update(profile_version="1939-v1"), "source/version"),
        (lambda root: root["entries"].append(copy.deepcopy(root["entries"][0])), "dublet"),
        (lambda root: root["entries"][0].update(baseline_record_key="rk-ukendt"), "ukendt"),
        (lambda root: root["entries"][0].update(outcome="ukendt"), "outcome"),
        (lambda root: root["entries"][0].update(extra="uautoriseret"), "uautoriserede"),
        (lambda root: root.update(exported_at="i går"), "eksporttidspunkt"),
        (
            lambda root: root.update(exported_at="2026-08-05 12:00:00+02:00"),
            "eksporttidspunkt",
        ),
    ],
)
def test_choice_export_rejects_stale_duplicate_unknown_or_malformed(mutation, message):
    value = choice_export(choice("rk-1", "undecidable", reason="uklar kilde"))
    mutation(value)

    with pytest.raises(ValueError, match=message):
        validate_choice_export(value, expected_source(), {"rk-1"})


@pytest.mark.parametrize("outcome", ["no_candidate_fits", "undecidable"])
def test_reason_outcomes_require_reason_and_forbid_candidate_fields(outcome):
    with pytest.raises(ValueError, match="reason"):
        validate_choice_export(choice_export(choice("rk-1", outcome)), expected_source(), {"rk-1"})
    with pytest.raises(ValueError, match="uautoriserede"):
        validate_choice_export(
            choice_export(choice("rk-1", outcome, reason="uklar", candidate_id="c-1")),
            expected_source(),
            {"rk-1"},
        )


def test_possible_duplicate_rejects_self_target():
    with pytest.raises(ValueError, match="sig selv"):
        validate_choice_export(
            choice_export(choice(
                "rk-1", "possible_duplicate", duplicate_of_baseline_record_key="rk-1"
            )),
            expected_source(),
            {"rk-1"},
        )


def test_choice_export_accepts_browser_timestamp_and_redundant_baseline_hash():
    value = choice_export(choice(
        "rk-1", "human_selected_candidate", candidate_id="c-1",
        decided_at="2026-08-05T12:01:00+02:00",
    ))
    value["baseline_sha256"] = "a" * 64

    result = validate_choice_export(value, expected_source(), {"rk-1"})

    assert result["rk-1"]["candidate_id"] == "c-1"


def test_validation_and_conversion_do_not_mutate_inputs():
    exported = choice_export(choice("rk-1", "human_selected_candidate", candidate_id="c-1"))
    candidates = {"c-1": {
        "baseline_record_key": "rk-1", "candidate": anchored_candidate("c-1")
    }}
    classifications = {"rk-1": human("rk-1")}
    snapshot = copy.deepcopy((exported, candidates, classifications))

    choices = validate_choice_export(exported, expected_source(), {"rk-1"})
    convert_review_choices(choices, candidates, classifications, set())

    assert (exported, candidates, classifications) == snapshot
