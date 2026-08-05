"""Contract tests for the private, lossless 1939 review queue model."""

from __future__ import annotations

import copy

import pytest

from prepare_review_queue_1939 import build_review_view_model


def source():
    return {"edition": "1939", "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64, "raw_ocr_sha256": "c" * 64,
            "pdf_sha256": "d" * 64, "profile_version": "1939-v2"}


def baseline(key, pages="498"):
    return {"record_key": key, "navn": key, "sider": pages,
            "narrative": f"gammel tekst {key}"}


def nearby(candidate_id, pages):
    return {"candidate_id": candidate_id, "lokal_id": candidate_id,
            "pdf_pages": pages, "calamari_pages": [page - 495 for page in pages],
            "raw_text": f"ny tekst {candidate_id}", "rank_reason": "samme_pdf_side"}


def human(key, reason="multiple_candidates"):
    return {"baseline_record_key": key, "queue_class": "human_required",
            "reason_code": reason, "reason_da": "kræver vurdering"}


def blocked(key, reason="raw_ocr_missing"):
    return {"baseline_record_key": key, "queue_class": "source_blocked",
            "reason_code": reason, "reason_da": "kildemateriale mangler"}


def anchored_candidate(candidate_id):
    return {"candidate_id": candidate_id, "postklasse": "nummereret",
            "calamari_span": {"char_from": 10, "char_to": 20},
            "pdf_pages": [498], "raw_structure_bridge": {
                "kind": "record_start", "raw_char_from": 100, "raw_char_to": 110,
                "raw_excerpt_sha256": "e" * 64,
            }}


def automatic(key):
    return {"baseline_record_key": key, "queue_class": "auto_resolved",
            "reason_code": "complete_unique_anchored_candidate", "reason_da": "komplet",
            "candidate": anchored_candidate(key), "rule_id": "complete_anchor_v1",
            "postklasse": "nummereret"}


def manifest(*entries):
    return {"schema_version": 1, "source": source(), "entries": list(entries)}


def test_multpage_candidate_is_deduplicated_by_candidate_id():
    model = build_review_view_model(
        [baseline("rk-1", pages="498-499")],
        manifest(human("rk-1", "multiple_candidates")),
        {"rk-1": [nearby("c-1", [498, 499]), nearby("c-1", [498, 499])]},
        [], {},
    )
    assert [c["candidate_id"] for c in model["records"][0]["candidates"]] == ["c-1"]


def test_required_is_default_and_automatic_remains_inspectable():
    model = build_review_view_model(
        [baseline("rk-a"), baseline("rk-h")],
        manifest(automatic("rk-a"), human("rk-h")),
        {"rk-a": [], "rk-h": []}, [], {},
    )
    assert model["summary"] == {
        "required": 1, "automatic": 1, "audit": 0, "completed": 0, "source_blocked": 0,
    }
    assert model["default_view"] == "required"
    assert model["views"]["required"] == ["rk-h"]
    assert model["views"]["automatic"] == ["rk-a"]


def test_top_three_is_presentation_only_and_all_candidates_survive():
    candidates = [nearby(f"c-{i}", [498]) for i in range(5)]
    model = build_review_view_model(
        [baseline("rk-1")], manifest(human("rk-1")),
        {"rk-1": candidates}, [], {},
    )
    record = model["records"][0]
    assert record["initial_candidate_ids"] == ["c-0", "c-1", "c-2"]
    assert [candidate["candidate_id"] for candidate in record["candidates"]] == [
        "c-0", "c-1", "c-2", "c-3", "c-4",
    ]


def test_anchored_candidate_keeps_complete_private_evidence_under_details():
    model = build_review_view_model(
        [baseline("rk-1")], manifest(automatic("rk-1")),
        {"rk-1": [nearby("rk-1", [498])]}, [], {},
    )
    candidate = model["records"][0]["candidates"][0]
    assert set(candidate) == {
        "candidate_id", "lokal_id", "pdf_pages", "calamari_pages", "raw_text",
        "rank_reason", "details",
    }
    assert candidate["details"] == anchored_candidate("rk-1")


def test_classifier_entry_is_retained_separately_and_is_not_presentation_mutated():
    entry = automatic("rk-1")
    queue = manifest(entry)
    original = copy.deepcopy(entry)
    model = build_review_view_model(
        [baseline("rk-1")], queue, {"rk-1": [nearby("rk-1", [498])]}, [], {},
    )
    record = model["records"][0]
    assert record["classification"] == original
    assert record["classification"]["rule_id"] == "complete_anchor_v1"
    assert record["classification"]["postklasse"] == "nummereret"
    record["candidates"][0]["details"]["postklasse"] = "ændret i visning"
    assert record["classification"] == original
    assert queue["entries"][0] == original


def test_all_546_baseline_keys_are_accounted_for_exactly_once():
    records = [baseline(f"rk-{number}") for number in range(546)]
    entries = [human(record["record_key"]) for record in records]
    model = build_review_view_model(records, manifest(*entries), {}, [], {})
    assert len(model["records"]) == 546
    assert {record["record_key"] for record in model["records"]} == {
        f"rk-{number}" for number in range(546)
    }


def test_duplicate_baseline_key_fails_closed():
    with pytest.raises(ValueError, match="dublet baseline_record_key"):
        build_review_view_model(
            [baseline("rk-1"), baseline("rk-1")], manifest(human("rk-1")), {}, [], {},
        )


def test_missing_manifest_key_fails_closed():
    with pytest.raises(ValueError, match="baseline-dækning"):
        build_review_view_model(
            [baseline("rk-1"), baseline("rk-2")], manifest(human("rk-1")), {}, [], {},
        )


def test_conflicting_duplicate_candidate_fails_closed():
    conflicting = nearby("c-1", [499])
    with pytest.raises(ValueError, match="samme candidate_id har forskelligt indhold"):
        build_review_view_model(
            [baseline("rk-1")], manifest(human("rk-1")),
            {"rk-1": [nearby("c-1", [498]), conflicting]}, [], {},
        )


def test_audit_records_are_automatic_and_are_exposed_in_their_own_view():
    model = build_review_view_model(
        [baseline("rk-1")], manifest(automatic("rk-1")), {}, ["rk-1"], {},
    )
    assert model["views"]["automatic"] == ["rk-1"]
    assert model["views"]["audit"] == ["rk-1"]
    assert model["records"][0]["is_audit"] is True


def test_source_blocked_is_required_with_visible_reason_and_subcount():
    model = build_review_view_model(
        [baseline("rk-1")], manifest(blocked("rk-1", "raw_ocr_missing")), {}, [], {},
    )
    assert model["summary"]["required"] == 1
    assert model["summary"]["source_blocked"] == 1
    assert model["records"][0]["reason_code"] == "raw_ocr_missing"


def test_existing_human_decision_is_additionally_visible_in_completed():
    decision = {"baseline_record_key": "rk-1", "review_status": "menneskeark",
                "reason": "vurderet af redaktionen"}
    model = build_review_view_model(
        [baseline("rk-1")], manifest(human("rk-1")), {}, [], {"rk-1": decision},
    )
    assert model["views"]["required"] == ["rk-1"]
    assert model["views"]["completed"] == ["rk-1"]
    assert model["records"][0]["decision"] == decision


def test_inputs_are_not_mutated():
    records = [baseline("rk-1")]
    queue = manifest(automatic("rk-1"))
    candidates = {"rk-1": [nearby("rk-1", [498])]}
    decisions = {"rk-1": {"review_status": "menneskeark"}}
    snapshot = copy.deepcopy((records, queue, candidates, decisions))
    build_review_view_model(records, queue, candidates, ["rk-1"], decisions)
    assert (records, queue, candidates, decisions) == snapshot
