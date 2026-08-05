"""Tests for versioned, fail-closed 1939 browser choice imports."""

from __future__ import annotations

import copy
import hashlib

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


def final_accepted(key, candidate_id, *, offset=0):
    raw_text = f"råtekst-{candidate_id}"
    return {
        "baseline_record_key": key,
        "review_status": "accepteret",
        "candidate_id": candidate_id,
        "post_index": offset,
        "calamari_span": {"char_from": 10 + offset, "char_to": 20 + offset},
        "calamari_verbatim_text": f"kildetekst-{candidate_id}",
        "pdf_pages": [498],
        "kind": "manual_anchor",
        "raw_char_from": 100 + offset,
        "raw_char_to": 110 + offset,
        "raw_verbatim_text": raw_text,
        "raw_excerpt_sha256": hashlib.sha256(raw_text.encode("utf-8")).hexdigest(),
    }


def validated_context(*entries):
    keys = {entry["baseline_record_key"] for entry in entries}
    return validate_choice_export(
        choice_export(*entries), expected_source(), keys, include_context=True
    )


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


def test_new_duplicate_can_target_final_accepted_legacy_without_reemitting_it():
    context = validated_context(
        choice(
            "rk-new", "possible_duplicate",
            duplicate_of_baseline_record_key="rk-final",
        ),
        final_accepted("rk-final", "c-final"),
    )

    converted = convert_review_choices(
        context["choices"],
        {},
        {"rk-new": human("rk-new"), "rk-final": human("rk-final")},
        set(),
        final_legacy_entries=context["final_legacy_entries"],
    )

    assert converted == {
        "decisions": [{
            "baseline_record_key": "rk-new",
            "status": "eksplicit_dublet",
            "duplicate_of_baseline_record_key": "rk-final",
        }],
        "audit_results": [],
    }


def test_final_human_status_overrides_auto_queue_for_duplicate_targets():
    context = validated_context(
        choice(
            "rk-new", "possible_duplicate",
            duplicate_of_baseline_record_key="rk-final",
        ),
        {
            "baseline_record_key": "rk-final",
            "review_status": "menneskeark",
            "reason": "historisk menneskeark",
        },
    )
    target_classification = automatic("rk-final", "c-auto")
    target_classification["candidate"] = anchored_candidate("c-auto", offset=50)

    with pytest.raises(ValueError, match="dubletmål skal være accepteret"):
        convert_review_choices(
            context["choices"],
            {},
            {"rk-new": human("rk-new"), "rk-final": target_classification},
            set(),
            final_legacy_entries=context["final_legacy_entries"],
        )


def test_final_accepted_anchor_parks_every_overlapping_new_claim_without_reemission():
    context = validated_context(
        choice("rk-new-1", "human_selected_candidate", candidate_id="c-new-1"),
        choice("rk-new-2", "human_selected_candidate", candidate_id="c-new-2"),
        final_accepted("rk-final", "c-final"),
    )

    calamari_overlap_only = anchored_candidate("c-new-1")
    calamari_overlap_only["raw_structure_bridge"].update({
        "raw_char_from": 300,
        "raw_char_to": 310,
    })
    raw_overlap_only = anchored_candidate("c-new-2", offset=50)
    raw_overlap_only["raw_structure_bridge"].update({
        "raw_char_from": 105,
        "raw_char_to": 115,
    })

    converted = convert_review_choices(
        context["choices"],
        {
            "c-new-1": {
                "baseline_record_key": "rk-new-1",
                "candidate": calamari_overlap_only,
            },
            "c-new-2": {
                "baseline_record_key": "rk-new-2",
                "candidate": raw_overlap_only,
            },
        },
        {
            "rk-new-1": human("rk-new-1"),
            "rk-new-2": human("rk-new-2"),
            "rk-final": human("rk-final"),
        },
        set(),
        final_legacy_entries=context["final_legacy_entries"],
    )

    assert converted == {
        "decisions": [
            {
                "baseline_record_key": "rk-new-1",
                "status": "menneskeark",
                "reason": "human_selected_candidate_not_globally_injective:c-new-1",
            },
            {
                "baseline_record_key": "rk-new-2",
                "status": "menneskeark",
                "reason": "human_selected_candidate_not_globally_injective:c-new-2",
            },
        ],
        "audit_results": [],
    }


def test_final_accepted_candidate_id_is_owned_across_baseline_records():
    context = validated_context(
        choice("rk-new", "human_selected_candidate", candidate_id="c-final"),
        final_accepted("rk-final", "c-final"),
    )

    converted = convert_review_choices(
        context["choices"],
        {"c-final": {
            "baseline_record_key": "rk-new",
            "candidate": anchored_candidate("c-final", offset=50),
        }},
        {"rk-new": human("rk-new"), "rk-final": human("rk-final")},
        set(),
        final_legacy_entries=context["final_legacy_entries"],
    )

    assert converted["decisions"] == [{
        "baseline_record_key": "rk-new",
        "status": "menneskeark",
        "reason": "human_selected_candidate_not_globally_injective:c-final",
    }]


def test_audit_duplicate_can_target_final_accepted_legacy():
    context = validated_context(
        choice(
            "rk-a", "possible_duplicate",
            duplicate_of_baseline_record_key="rk-final",
        ),
        final_accepted("rk-final", "c-final"),
    )
    audit_classification = automatic("rk-a", "c-a")
    audit_classification["candidate"] = anchored_candidate("c-a", offset=50)

    converted = convert_review_choices(
        context["choices"],
        {},
        {"rk-a": audit_classification, "rk-final": human("rk-final")},
        {"rk-a"},
        final_legacy_entries=context["final_legacy_entries"],
    )

    assert converted == {
        "decisions": [],
        "audit_results": [{
            "baseline_record_key": "rk-a",
            "audit_status": "audit_failed",
            "rule_id": "complete_anchor_v1",
            "reason": "possible_duplicate:rk-final",
        }],
    }


def test_audit_duplicate_rejects_final_nonaccepted_legacy_even_if_queue_is_auto():
    context = validated_context(
        choice(
            "rk-a", "possible_duplicate",
            duplicate_of_baseline_record_key="rk-final",
        ),
        {
            "baseline_record_key": "rk-final",
            "review_status": "menneskeark",
            "reason": "historisk menneskeark",
        },
    )
    audit_classification = automatic("rk-a", "c-a")
    target_classification = automatic("rk-final", "c-target")
    target_classification["candidate"] = anchored_candidate("c-target", offset=50)

    with pytest.raises(ValueError, match="dubletmål skal være accepteret"):
        convert_review_choices(
            context["choices"],
            {},
            {"rk-a": audit_classification, "rk-final": target_classification},
            {"rk-a"},
            final_legacy_entries=context["final_legacy_entries"],
        )


def test_final_accepted_and_provisional_selected_candidate_for_same_key_are_rejected():
    choices = {
        "rk-1": choice(
            "rk-1", "human_selected_candidate", candidate_id="c-provisional"
        )
    }
    final_entries = {"rk-1": final_accepted("rk-1", "c-final")}
    snapshot = copy.deepcopy((choices, final_entries))

    with pytest.raises(
        ValueError,
        match="^modstridende final/provisional baseline_record_key-overlap$",
    ):
        convert_review_choices(
            choices,
            {"c-provisional": {
                "baseline_record_key": "rk-1",
                "candidate": anchored_candidate("c-provisional", offset=50),
            }},
            {"rk-1": human("rk-1")},
            set(),
            final_legacy_entries=final_entries,
        )

    assert (choices, final_entries) == snapshot


@pytest.mark.parametrize(
    "final_entry",
    [
        final_accepted("rk-1", "c-final"),
        {
            "baseline_record_key": "rk-1",
            "review_status": "eksplicit_dublet",
            "duplicate_of_baseline_record_key": "rk-target",
        },
        {
            "baseline_record_key": "rk-1",
            "review_status": "menneskeark",
            "reason": "endelig historisk afgørelse",
        },
    ],
    ids=["accepteret", "eksplicit_dublet", "menneskeark"],
)
@pytest.mark.parametrize(
    "provisional_choice",
    [
        choice("rk-1", "human_selected_candidate", candidate_id="c-provisional"),
        choice(
            "rk-1",
            "possible_duplicate",
            duplicate_of_baseline_record_key="rk-target",
        ),
        choice("rk-1", "no_candidate_fits", reason="privat begrundelse"),
        choice("rk-1", "undecidable", reason="privat begrundelse"),
    ],
    ids=["selected", "duplicate", "no-candidate", "undecidable"],
)
def test_final_legacy_status_rejects_every_provisional_outcome_for_same_key(
    final_entry, provisional_choice
):
    with pytest.raises(
        ValueError,
        match="^modstridende final/provisional baseline_record_key-overlap$",
    ):
        convert_review_choices(
            {"rk-1": provisional_choice},
            {},
            {"rk-1": human("rk-1"), "rk-target": human("rk-target")},
            set(),
            final_legacy_entries={"rk-1": final_entry},
        )


def test_final_legacy_and_audit_choice_for_same_key_are_rejected_without_audit_result():
    with pytest.raises(
        ValueError,
        match="^modstridende final/provisional baseline_record_key-overlap$",
    ):
        convert_review_choices(
            {"rk-a": choice(
                "rk-a", "no_candidate_fits", reason="privat auditbegrundelse"
            )},
            {},
            {"rk-a": automatic("rk-a", "c-auto")},
            {"rk-a"},
            final_legacy_entries={
                "rk-a": {
                    "baseline_record_key": "rk-a",
                    "review_status": "menneskeark",
                    "reason": "endelig historisk afgørelse",
                }
            },
        )


def test_overlap_is_checked_only_after_the_provisional_choice_is_validated():
    malformed_choice = choice("rk-other", "undecidable", reason="uklar")

    with pytest.raises(ValueError, match="forkert baseline_record_key"):
        convert_review_choices(
            {"rk-1": malformed_choice},
            {},
            {"rk-1": human("rk-1"), "rk-other": human("rk-other")},
            set(),
            final_legacy_entries={
                "rk-1": {
                    "baseline_record_key": "rk-1",
                    "review_status": "menneskeark",
                    "reason": "endelig historisk afgørelse",
                }
            },
        )


def test_disjoint_final_and_provisional_mappings_keep_approved_output():
    choices = {
        "rk-new": choice(
            "rk-new", "human_selected_candidate", candidate_id="c-new"
        )
    }
    candidates = {"c-new": {
        "baseline_record_key": "rk-new",
        "candidate": anchored_candidate("c-new", offset=50),
    }}
    classifications = {"rk-final": human("rk-final"), "rk-new": human("rk-new")}
    final_entries = {"rk-final": final_accepted("rk-final", "c-final")}
    snapshot = copy.deepcopy((choices, candidates, classifications, final_entries))

    converted = convert_review_choices(
        choices,
        candidates,
        classifications,
        set(),
        final_legacy_entries=final_entries,
    )

    assert converted == {
        "decisions": [{
            "baseline_record_key": "rk-new",
            "status": "accepteret",
            "candidate_id": "c-new",
        }],
        "audit_results": [],
    }
    assert (choices, candidates, classifications, final_entries) == snapshot


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


def test_choice_export_accepts_complete_task4_legacy_overlay_and_skips_untouched_entries():
    raw_text = "råtekst"
    value = choice_export(
        choice(
            "rk-choice",
            "human_selected_candidate",
            candidate_id="c-1",
            decided_at="2026-08-05T12:01:00+02:00",
            review_status="unreviewed",
            baseline_locator={"pages": "498", "local_id": "Stamme.I.1"},
            review_note="læst i originalen",
        ),
        {
            "baseline_record_key": "rk-unreviewed",
            "review_status": "unreviewed",
            "baseline_locator": {"pages": None, "local_id": None},
        },
        {
            "baseline_record_key": "rk-accepted",
            "review_status": "accepteret",
            "candidate_id": "c-final",
            "post_index": 7,
            "calamari_span": {"char_from": 10, "char_to": 20},
            "calamari_verbatim_text": "kildetekst",
            "pdf_pages": [498],
            "kind": "manual_anchor",
            "raw_char_from": 100,
            "raw_char_to": 107,
            "raw_verbatim_text": raw_text,
            "raw_excerpt_sha256": hashlib.sha256(raw_text.encode("utf-8")).hexdigest(),
        },
        {
            "baseline_record_key": "rk-human",
            "review_status": "menneskeark",
            "reason": "historisk afgørelse",
        },
    )

    result = validate_choice_export(
        value,
        expected_source(),
        {"rk-choice", "rk-unreviewed", "rk-accepted", "rk-human"},
    )

    assert result == {"rk-choice": {
        "baseline_record_key": "rk-choice",
        "outcome": "human_selected_candidate",
        "candidate_id": "c-1",
        "decided_at": "2026-08-05T12:01:00+02:00",
        "review_status": "unreviewed",
        "baseline_locator": {"pages": "498", "local_id": "Stamme.I.1"},
        "review_note": "læst i originalen",
    }}


def test_choice_export_rejects_outcome_over_final_legacy_status():
    value = choice_export(choice(
        "rk-1", "undecidable", reason="nyt udfald",
        review_status="menneskeark",
    ))

    with pytest.raises(ValueError, match="endelig legacy"):
        validate_choice_export(value, expected_source(), {"rk-1"})


@pytest.mark.parametrize(
    ("entry", "message"),
    [
        (
            {"baseline_record_key": "rk-1", "review_status": "unreviewed",
             "baseline_locator": "498"},
            "baseline_locator",
        ),
        (
            {"baseline_record_key": "rk-1", "review_status": "unreviewed",
             "review_note": 17},
            "review_note",
        ),
        (
            {"baseline_record_key": "rk-1", "review_status": "menneskeark"},
            "reason",
        ),
        (
            {"baseline_record_key": "rk-1", "review_status": "unreviewed",
             "guessed_person_id": "må ikke accepteres"},
            "uautoriserede",
        ),
    ],
)
def test_choice_export_rejects_malformed_or_unknown_legacy_metadata(entry, message):
    with pytest.raises(ValueError, match=message):
        validate_choice_export(
            choice_export(entry), expected_source(), {"rk-1"}
        )


def test_choice_export_requires_complete_task4_record_key_accounting():
    value = choice_export(
        choice("rk-1", "undecidable", reason="uklar kilde")
    )

    with pytest.raises(ValueError, match="baseline-dækning"):
        validate_choice_export(value, expected_source(), {"rk-1", "rk-missing"})


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
