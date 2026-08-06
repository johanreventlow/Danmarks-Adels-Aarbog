"""Contract tests for the private, lossless 1939 review queue model."""

from __future__ import annotations

import copy
import dataclasses
import hashlib
import json
from pathlib import Path

import pytest

from dual_rendition_evidence_1939 import (
    RULE_ID,
    build_source_bound_evidence,
    deterministic_candidate_id,
)
import prepare_coverage_1939 as task5_subject
import prepare_review_queue_1939 as subject
from prepare_review_queue_1939 import (
    _review_state,
    _validate_effective_state,
    build_queue_report,
    build_review_view_model,
    main,
)
from review_queue_1939 import sample_auto_resolved


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


def queue_entry(key, queue_class, reason_code):
    return {"baseline_record_key": key, "queue_class": queue_class,
            "reason_code": reason_code, "reason_da": reason_code}


def report_manifest(*entries):
    return {"schema_version": 1, "source": source(), "entries": list(entries)}


def accepted_decision(key, candidate_id="manual-anchor"):
    raw_text = "accepteret manuel tekst"
    return {
        "baseline_record_key": key,
        "review_status": "accepteret",
        "candidate_id": candidate_id,
        "post_index": 7,
        "calamari_span": {"char_from": 10, "char_to": 20},
        "calamari_verbatim_text": "accepteret Calamari-tekst",
        "pdf_pages": [700],
        "kind": "manual_cross_page_anchor",
        "raw_char_from": 100,
        "raw_char_to": 123,
        "raw_verbatim_text": raw_text,
        "raw_excerpt_sha256": "9051de1629f5ba1edae9157f0d8c6ef9f2e1ced6eeb95bb08cc5c28d938425c7",
    }


def test_multpage_candidate_is_deduplicated_by_candidate_id():
    model = build_review_view_model(
        [baseline("rk-1", pages="498-499")],
        manifest(human("rk-1", "multiple_candidates")),
        {"rk-1": [nearby("c-1", [498, 499]), nearby("c-1", [498, 499])]},
        [], {},
    )
    assert [c["candidate_id"] for c in model["records"][0]["candidates"]] == ["c-1"]


def test_default_view_contains_only_real_exceptions():
    model = build_review_view_model(
        [baseline("rk-a"), baseline("rk-h")],
        manifest(automatic("rk-a"), human("rk-h")),
        {"rk-a": [], "rk-h": []}, [], {},
    )
    assert model["default_view"] == "required"
    assert model["views"]["required"] == ["rk-h"]
    assert model["views"]["audit"] == []
    assert "automatic" not in model["views"]


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


def test_authoritative_accepted_decision_is_attached_when_not_page_near():
    decision = accepted_decision("rk-1")
    model = build_review_view_model(
        [baseline("rk-1")], manifest(human("rk-1")),
        {"rk-1": [nearby("near-page", [498])]}, [], {"rk-1": decision},
    )

    record = model["records"][0]
    assert [candidate["candidate_id"] for candidate in record["candidates"]] == [
        "manual-anchor", "near-page",
    ]
    accepted = record["candidates"][0]
    assert accepted["rank_reason"] == "accepteret_review_evidens"
    assert accepted["raw_text"] == "accepteret manuel tekst"
    assert accepted["accepted_review_details"] == decision
    assert record["candidate_count"] == 2


def test_authoritative_accepted_candidate_is_in_initial_set_after_three_nearby_candidates():
    decision = accepted_decision("rk-1", "z-manual-anchor")
    model = build_review_view_model(
        [baseline("rk-1")], manifest(human("rk-1")),
        {"rk-1": [nearby(f"near-{number}", [498]) for number in range(3)]},
        [], {"rk-1": decision},
    )

    record = model["records"][0]
    assert [candidate["candidate_id"] for candidate in record["candidates"]] == [
        "near-0", "near-1", "near-2", "z-manual-anchor",
    ]
    assert record["initial_candidate_ids"] == [
        "near-0", "near-1", "near-2", "z-manual-anchor",
    ]
    assert record["candidates"][3]["accepted_review_details"] == decision


def test_classifier_and_accepted_review_evidence_remain_separate_for_same_candidate():
    entry = automatic("rk-1")
    decision = accepted_decision("rk-1", "rk-1")
    classifier_bytes = json.dumps(
        entry["candidate"], ensure_ascii=False, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")
    model = build_review_view_model(
        [baseline("rk-1")], manifest(entry),
        {"rk-1": [nearby("rk-1", [498])]}, ["rk-1"], {"rk-1": decision},
    )

    candidate = model["records"][0]["candidates"][0]
    assert json.dumps(
        candidate["details"], ensure_ascii=False, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8") == classifier_bytes
    assert candidate["accepted_review_details"] == decision
    candidate["accepted_review_details"]["kind"] = "ændret review-visning"
    assert json.dumps(
        candidate["details"], ensure_ascii=False, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8") == classifier_bytes


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


def test_audit_records_are_automatic_but_are_exposed_only_as_deterministic_samples():
    model = build_review_view_model(
        [baseline("rk-1")], manifest(automatic("rk-1")), {}, ["rk-1"], {},
    )
    assert model["views"]["audit"] == ["rk-1"]
    assert model["records"][0]["is_audit"] is True


def test_diagnostic_reason_is_danish_specific_and_compares_boundaries():
    entry = human("rk-1", "boundary_disagreement")
    entry["reason_da"] = "OCR-kilderne er uenige om postens grænse."
    record = build_review_view_model(
        [baseline("rk-1")], manifest(entry), {}, [], {},
    )["records"][0]

    assert record["reason_code"] == "boundary_disagreement"
    assert "grænse" in record["reason_da"].lower()
    assert "Calamari" in record["boundary_context"]
    assert "rå OCR" in record["boundary_context"]


def test_unknown_diagnostic_is_fail_closed_and_never_automatic():
    entry = human("rk-1", "fremtidig_ukendt_kode")
    record = build_review_view_model(
        [baseline("rk-1")], manifest(entry), {}, [], {},
    )["records"][0]

    assert record["queue_class"] == "human_required"
    assert record["boundary_context"] == "Calamari: ukendt · rå OCR: ukendt. Kræver menneskelig vurdering."


def test_source_bound_successor_disagreement_carries_emeke_to_the_view_model_once():
    source_baseline = json.dumps([
        {"record_key": "rk-volrad", "_v2_lokal_id": "I.1",
         "_narrativ_kilde": "calamari", "narrative": "Volrad"},
        {"record_key": "rk-emeke", "_v2_lokal_id": "I.2",
         "_narrativ_kilde": "calamari", "narrative": "Emeke"},
    ]).encode("utf-8")
    evidence, _, _ = build_source_bound_evidence(
        source_baseline,
        b"### PAGE 1 ###\n1. Volrad\n### PAGE 1 ###\n2. Emeke\n",
        b"### PAGE 496 ###\n1. Volrad\nII.\n### PAGE 496 ###\n2. Emeke\n",
        b"%PDF-synthetic", profile_version="1939-v2",
    )
    queue = subject.classify_review_entries(
        evidence["source"], {"rk-volrad", "rk-emeke"}, evidence["entries"],
    )
    model = build_review_view_model(
        [baseline("rk-volrad"), baseline("rk-emeke")], queue, {}, [], {},
    )
    record = next(item for item in model["records"] if item["record_key"] == "rk-volrad")

    assert next(item for item in queue["entries"] if item["baseline_record_key"] == "rk-volrad")[
        "reason_code"
    ] == "successor_disagreement"
    assert record["boundary_context"] == "Calamari og rå OCR: følgende post “2. Emeke”."
    assert record["boundary_context"].count("Emeke") == 1


def test_exact_raw_anchor_failure_reaches_queue_and_view_with_specific_source_diagnosis():
    source_baseline = json.dumps([{
        "record_key": "rk-volrad", "_v2_lokal_id": "I.1",
        "_narrativ_kilde": "raw", "narrative": "Volrad",
    }]).encode("utf-8")
    evidence, _, _ = build_source_bound_evidence(
        source_baseline,
        b"### PAGE 1 ###\n1. Volrad\n",
        b"### PAGE 496 ###\n1. V o l r a d\n",
        b"%PDF-synthetic", profile_version="1939-v2",
    )
    queue = subject.classify_review_entries(
        evidence["source"], {"rk-volrad"}, evidence["entries"],
    )
    record = build_review_view_model(
        [baseline("rk-volrad")], queue, {}, [], {},
    )["records"][0]

    assert evidence["entries"][0]["conflicts"] == ["missing_exact_baseline_narrative"]
    assert evidence["entries"][0]["anchor_rendition"] == "raw_ocr"
    assert record["reason_code"] == "missing_exact_baseline_narrative"
    assert record["reason_da"] == (
        "Det lagrede narrativ findes ikke præcist én gang i rå OCR; "
        "derfor findes ingen positiv kildebro."
    )
    assert record["boundary_context"] == "Rå OCR: intet præcist, entydigt narrativanker."


def test_source_bound_successor_shows_different_excerpts_per_source():
    source_baseline = json.dumps([
        {"record_key": "rk-volrad", "_v2_lokal_id": "I.1",
         "_narrativ_kilde": "calamari", "narrative": "Volrad"},
        {"record_key": "rk-emeke", "_v2_lokal_id": "I.2",
         "_narrativ_kilde": "calamari", "narrative": "Emeke"},
    ]).encode("utf-8")
    evidence, _, _ = build_source_bound_evidence(
        source_baseline,
        b"### PAGE 1 ###\n1. Volrad\n### PAGE 1 ###\n2. Emeke\n",
        b"### PAGE 496 ###\n1. Volrad\n### PAGE 496 ###\n3. Emeke\n",
        b"%PDF-synthetic", profile_version="1939-v2",
    )
    queue = subject.classify_review_entries(
        evidence["source"], {"rk-volrad", "rk-emeke"}, evidence["entries"],
    )
    record = next(item for item in build_review_view_model(
        [baseline("rk-volrad"), baseline("rk-emeke")], queue, {}, [], {},
    )["records"] if item["record_key"] == "rk-volrad")

    assert record["boundary_context"] == (
        "Calamari: følgende post “2. Emeke” · rå OCR: følgende post “3. Emeke”."
    )


def test_source_bound_successor_keeps_raw_excerpt_when_calamari_lacks_neighbor():
    source_baseline = json.dumps([
        {"record_key": "rk-volrad", "_v2_lokal_id": "I.1",
         "_narrativ_kilde": "calamari", "narrative": "Volrad"},
        {"record_key": "rk-emeke", "_v2_lokal_id": "I.2",
         "_narrativ_kilde": "calamari", "narrative": "Emeke"},
    ]).encode("utf-8")
    evidence, _, _ = build_source_bound_evidence(
        source_baseline,
        b"### PAGE 1 ###\n1. Volrad\n",
        b"### PAGE 496 ###\n1. Volrad\n### PAGE 496 ###\n2. Emeke\n",
        b"%PDF-synthetic", profile_version="1939-v2",
    )
    queue = subject.classify_review_entries(
        evidence["source"], {"rk-volrad", "rk-emeke"}, evidence["entries"],
    )
    model = build_review_view_model(
        [baseline("rk-volrad"), baseline("rk-emeke")], queue, {}, [], {},
    )
    record = next(item for item in model["records"] if item["record_key"] == "rk-volrad")

    assert record["boundary_context"] == (
        "Calamari: følgende post mangler · rå OCR: følgende post “"
        "2. Emeke”."
    )
    assert record["boundary_context"].count("Emeke") == 1


def test_source_bound_successor_keeps_calamari_excerpt_when_raw_ocr_lacks_neighbor():
    source_baseline = json.dumps([
        {"record_key": "rk-volrad", "_v2_lokal_id": "I.1",
         "_narrativ_kilde": "calamari", "narrative": "Volrad"},
        {"record_key": "rk-emeke", "_v2_lokal_id": "I.2",
         "_narrativ_kilde": "calamari", "narrative": "Emeke"},
    ]).encode("utf-8")
    evidence, _, _ = build_source_bound_evidence(
        source_baseline,
        b"### PAGE 1 ###\n1. Volrad\n### PAGE 1 ###\n2. Emeke\n",
        b"### PAGE 496 ###\n1. Volrad\n",
        b"%PDF-synthetic", profile_version="1939-v2",
    )
    queue = subject.classify_review_entries(
        evidence["source"], {"rk-volrad", "rk-emeke"}, evidence["entries"],
    )
    record = next(item for item in build_review_view_model(
        [baseline("rk-volrad"), baseline("rk-emeke")], queue, {}, [], {},
    )["records"] if item["record_key"] == "rk-volrad")

    assert record["boundary_context"] == (
        "Calamari: følgende post “2. Emeke” · rå OCR: følgende post mangler."
    )


def test_source_blocked_raw_ocr_missing_has_specific_source_bound_diagnostic():
    queue = subject.classify_review_entries(
        source(), {"rk-blocked"}, [{
            "baseline_record_key": "rk-blocked", "candidates": [],
            "positive_provenance": None, "conflicts": [],
            "source_blockers": ["raw_ocr_missing"], "rule_id": None,
        }],
    )
    record = build_review_view_model(
        [baseline("rk-blocked")], queue, {}, [], {},
    )["records"][0]

    assert record["reason_da"] == "Rå OCR-kilden mangler; posten kan ikke sammenholdes sikkert."
    assert record["boundary_context"] == "Calamari: tilgængelig · rå OCR: mangler."


def test_source_bound_boundary_excerpt_must_match_the_pinned_raw_ocr_bytes():
    source_baseline = json.dumps([
        {"record_key": "rk-volrad", "_v2_lokal_id": "I.1",
         "_narrativ_kilde": "calamari", "narrative": "Volrad"},
        {"record_key": "rk-emeke", "_v2_lokal_id": "I.2",
         "_narrativ_kilde": "calamari", "narrative": "Emeke"},
    ]).encode("utf-8")
    calamari = "### PAGE 1 ###\n1. Volrad\n### PAGE 1 ###\n2. Emeke\n"
    raw_ocr = "### PAGE 496 ###\n1. Volrad\n### PAGE 496 ###\n3. Emeke\n"
    evidence, _, _ = build_source_bound_evidence(
        source_baseline, calamari.encode("utf-8"), raw_ocr.encode("utf-8"),
        b"%PDF-synthetic", profile_version="1939-v2",
    )
    tampered = copy.deepcopy(evidence)
    tampered["entries"][0]["boundary_evidence"]["raw_ocr"]["text"] = "opfundet"

    with pytest.raises(ValueError, match="boundary_evidence matcher"):
        subject._source_bound_evidence_entries(
            tampered, evidence["source"], {"rk-volrad", "rk-emeke"}, calamari, raw_ocr,
        )


def test_unknown_source_blocker_stays_generic_and_fail_closed():
    queue = subject.classify_review_entries(
        source(), {"rk-blocked"}, [{
            "baseline_record_key": "rk-blocked", "candidates": [],
            "positive_provenance": None, "conflicts": [],
            "source_blockers": ["future_source_blocker"], "rule_id": None,
        }],
    )
    record = build_review_view_model(
        [baseline("rk-blocked")], queue, {}, [], {},
    )["records"][0]

    assert record["queue_class"] == "source_blocked"
    assert record["reason_da"] == "Kildemateriale er blokeret: future_source_blocker."
    assert record["boundary_context"] == "Calamari: ukendt · rå OCR: ukendt. Kræver menneskelig vurdering."


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


def test_report_accounts_for_every_record_and_fails_closed():
    auto = queue_entry("rk-a", "auto_resolved", "complete_unique_anchored_candidate")
    auto.update(rule_id="complete_anchor_v1", postklasse="nummereret")
    report = build_queue_report(
        report_manifest(
            auto,
            queue_entry("rk-h", "human_required", "multiple_candidates"),
            queue_entry("rk-b", "source_blocked", "raw_ocr_missing"),
        ),
        audit_keys=["rk-a"], completed_keys={"rk-h"}, audit_results=[],
    )
    assert report["baseline_total"] == 3
    assert report["auto_resolved"] == 1
    assert report["human_required"] == 1
    assert report["source_blocked"] == 1
    assert report["audit"] == 1
    assert report["completed"] == 1
    assert report["reason_code_counts"] == {
        "complete_unique_anchored_candidate": 1,
        "multiple_candidates": 1,
        "raw_ocr_missing": 1,
    }
    assert report["classification_matrix"] == [
        {"queue_class": "auto_resolved", "reason_code": "complete_unique_anchored_candidate",
         "rule_id": "complete_anchor_v1", "postklasse": "nummereret", "count": 1},
        {"queue_class": "human_required", "reason_code": "multiple_candidates",
         "rule_id": "ikke_fastlagt", "postklasse": "ikke_fastlagt", "count": 1},
        {"queue_class": "source_blocked", "reason_code": "raw_ocr_missing",
         "rule_id": "ikke_fastlagt", "postklasse": "ikke_fastlagt", "count": 1},
    ]
    assert sum(row["count"] for row in report["classification_matrix"]) == 3
    assert report["collision_overlap_counts"] == {
        "candidate_collision": 0,
        "calamari_span_overlap": 0,
        "raw_ocr_span_overlap": 0,
    }
    assert report["publication_gate"] == "NO-GO"


def test_loose_report_inputs_cannot_publish_even_with_546_fabricated_green_counts():
    auto = automatic("rk-auto")
    humans = [human(f"rk-human-{number}") for number in range(545)]
    completed = {entry["baseline_record_key"] for entry in humans}
    report = build_queue_report(
        manifest(auto, *humans),
        audit_keys=["rk-auto"],
        completed_keys=completed,
        audit_results=[{
            "baseline_record_key": "rk-auto",
            "audit_status": "audit_confirmed",
            "rule_id": "complete_anchor_v1",
        }],
    )

    assert report["baseline_total"] == 546
    assert report["stratum_counts"] == {"complete_anchor_v1|nummereret": 1}
    assert report["audit_blocked_rule_groups"] == []
    assert report["publication_gate"] == "NO-GO"


def test_plain_mapping_cannot_fabricate_validated_review_state():
    auto = automatic("rk-auto")
    humans = [human(f"rk-human-{number}") for number in range(545)]
    queue = manifest(auto, *humans)

    with pytest.raises(ValueError, match="review_state.*state-type"):
        build_queue_report(queue, review_state={
            "manifest": queue,
            "audit_keys": ["rk-auto"],
            "completed_keys": {
                entry["baseline_record_key"] for entry in humans
            },
            "audit_results": [_audit_confirmed("rk-auto")],
        })


def test_public_report_builder_is_no_go_even_for_actual_validated_review_state():
    auto = automatic("rk-auto")
    humans = [human(f"rk-human-{number}") for number in range(545)]
    queue = manifest(auto, *humans)
    human_keys = {entry["baseline_record_key"] for entry in humans}
    review_state = _review_state(
        {
            "decisions": [
                {
                    "baseline_record_key": key,
                    "status": "menneskeark",
                    "reason": "manuelt afsluttet",
                }
                for key in sorted(human_keys)
            ],
            "audit_results": [_audit_confirmed("rk-auto")],
        },
        source(),
        {"rk-auto", *human_keys},
        manifest=queue,
    )

    report = build_queue_report(queue, review_state=review_state)

    assert report["baseline_total"] == 546
    assert report["audit_confirmed"] == 1
    assert report["completed"] == 545
    assert report["publication_gate"] == "NO-GO"

    with pytest.raises(ValueError, match="må ikke blandes"):
        build_queue_report(
            queue,
            completed_keys=human_keys,
            review_state=review_state,
        )


@pytest.mark.parametrize("attack", ["direct", "replace", "setattr", "clone"])
def test_forgeable_review_state_never_grants_publication(attack):
    auto = automatic("rk-auto")
    humans = [human(f"rk-human-{number}") for number in range(545)]
    queue = manifest(auto, *humans)
    human_keys = {entry["baseline_record_key"] for entry in humans}
    review_state = _review_state(
        {
            "decisions": [],
            "audit_results": [_audit_confirmed("rk-auto")],
        },
        source(),
        {"rk-auto", *human_keys},
        manifest=queue,
    )
    if attack == "direct":
        forged = subject._ValidatedReviewState(
            source=copy.deepcopy(source()),
            manifest=copy.deepcopy(queue),
            audit_keys=("rk-auto",),
            completed_keys=frozenset(human_keys),
            audit_results=(_audit_confirmed("rk-auto"),),
        )
    elif attack == "replace":
        forged = dataclasses.replace(
            review_state, completed_keys=frozenset(human_keys)
        )
    elif attack == "setattr":
        forged = review_state
        object.__setattr__(forged, "completed_keys", frozenset(human_keys))
    else:
        reviewed = _review_state(
            {
                "decisions": [
                    {
                        "baseline_record_key": key,
                        "status": "menneskeark",
                        "reason": "manuelt afsluttet",
                    }
                    for key in sorted(human_keys)
                ],
                "audit_results": [_audit_confirmed("rk-auto")],
            },
            source(),
            {"rk-auto", *human_keys},
            manifest=queue,
        )
        forged = copy.copy(reviewed)

    report = build_queue_report(queue, review_state=forged)

    assert report["baseline_total"] == 546
    assert report["completed"] == 545
    assert report["publication_gate"] == "NO-GO"


def test_546_presentation_automatics_cannot_pass_validation_or_publication():
    normal_entries = [automatic(f"rk-{number}") for number in range(546)]
    normal_manifest = manifest(*normal_entries)
    audit_keys = sample_auto_resolved(normal_manifest)
    presentation_entries = copy.deepcopy(normal_entries)
    for number, entry in enumerate(presentation_entries):
        entry["candidate"]["candidate_id"] = f"presentation:1939-v2:post:{number}"

    report = build_queue_report(
        manifest(*presentation_entries),
        audit_keys=audit_keys,
        completed_keys=set(),
        audit_results=[{
            "baseline_record_key": key,
            "audit_status": "audit_confirmed",
            "rule_id": "complete_anchor_v1",
        } for key in audit_keys],
    )

    assert report["baseline_total"] == 546
    assert report["audit_confirmed"] == len(audit_keys)
    assert report["automatic_candidates_valid"] is False
    assert report["audit_sample_matches"] is False
    assert report["publication_gate"] == "NO-GO"


def test_failed_audit_blocks_its_rule_group_and_publication():
    auto = automatic("rk-auto")
    humans = [human(f"rk-human-{number}") for number in range(545)]
    report = build_queue_report(
        manifest(auto, *humans),
        audit_keys=["rk-auto"],
        completed_keys={entry["baseline_record_key"] for entry in humans},
        audit_results=[{
            "baseline_record_key": "rk-auto",
            "audit_status": "audit_failed",
            "rule_id": "complete_anchor_v1",
            "reason": "selected_different_candidate:c-other",
        }],
    )

    assert report["audit_blocked_rule_groups"] == ["complete_anchor_v1|nummereret"]
    assert report["publication_gate"] == "NO-GO"


def _pilot_cli_args(tmp_path):
    baseline_path = tmp_path / "baseline.json"
    evidence_path = tmp_path / "evidence.json"
    review_path = tmp_path / "review.json"
    calamari_path = tmp_path / "calamari.txt"
    raw_path = tmp_path / "raw.txt"
    pdf_path = tmp_path / "book.pdf"
    queue_path = tmp_path / "queue.json"
    report_path = tmp_path / "report.json"
    baseline_path.write_text(json.dumps([baseline("rk-1")]), encoding="utf-8")
    evidence_path.write_text(json.dumps({
        "schema_version": 1,
        "baseline_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        "entries": [{"baseline_record_key": "rk-1", "review_status": "unreviewed"}],
    }), encoding="utf-8")
    review_path.write_text(json.dumps({
        "schema_version": 1,
        "baseline_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        "entries": [{"baseline_record_key": "rk-1", "review_status": "unreviewed"}],
    }), encoding="utf-8")
    calamari_path.write_text("Calamari", encoding="utf-8")
    raw_path.write_text("Rå OCR", encoding="utf-8")
    pdf_path.write_bytes(b"PDF")
    return [
        "--baseline", str(baseline_path),
        "--evidence", str(evidence_path),
        "--review", str(review_path),
        "--calamari", str(calamari_path),
        "--raw", str(raw_path),
        "--pdf", str(pdf_path),
        "--profile-version", "1939-v2",
        "--queue-out", str(queue_path),
        "--report-out", str(report_path),
    ], queue_path, report_path, {
        "baseline_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        "calamari_sha256": hashlib.sha256(calamari_path.read_bytes()).hexdigest(),
        "raw_ocr_sha256": hashlib.sha256(raw_path.read_bytes()).hexdigest(),
        "pdf_sha256": hashlib.sha256(pdf_path.read_bytes()).hexdigest(),
    }


def _cli_path(args, option):
    return Path(args[args.index(option) + 1])


def _exact_cli_source(args):
    return {
        "edition": "1939",
        "baseline_sha256": hashlib.sha256(
            _cli_path(args, "--baseline").read_bytes()
        ).hexdigest(),
        "calamari_sha256": hashlib.sha256(
            _cli_path(args, "--calamari").read_bytes()
        ).hexdigest(),
        "raw_ocr_sha256": hashlib.sha256(
            _cli_path(args, "--raw").read_bytes()
        ).hexdigest(),
        "pdf_sha256": hashlib.sha256(
            _cli_path(args, "--pdf").read_bytes()
        ).hexdigest(),
        "profile_version": "1939-v2",
    }


def _source_bound_evidence(args, key="rk-1"):
    raw_excerpt = "Rå OCR"
    candidate = {
        "candidate_id": "candidate-1",
        "postklasse": "nummereret",
        "calamari_span": {"char_from": 0, "char_to": 8},
        "pdf_pages": [1],
        "raw_structure_bridge": {
            "kind": "record_start",
            "raw_char_from": 0,
            "raw_char_to": 6,
            "raw_excerpt_sha256": hashlib.sha256(
                raw_excerpt.encode("utf-8")
            ).hexdigest(),
        },
    }
    return {
        "schema_version": 1,
        "source": _exact_cli_source(args),
        "entries": [{
            "baseline_record_key": key,
            "candidates": [candidate],
            "positive_provenance": {
                "kind": "record_key_v2_locator",
                "baseline_record_key": key,
                "candidate_id": candidate["candidate_id"],
            },
            "conflicts": [],
            "source_blockers": [],
            "rule_id": "complete_anchor_v1",
        }],
    }


def _dual_source_bound_evidence(args, key="rk-1"):
    evidence = _source_bound_evidence(args, key)
    entry = evidence["entries"][0]
    candidate = entry["candidates"][0]
    bridge = candidate["raw_structure_bridge"]
    candidate["raw_structure_bridge"]["kind"] = RULE_ID
    candidate["candidate_id"] = deterministic_candidate_id(
        key, candidate["calamari_span"], {
            "char_from": bridge["raw_char_from"],
            "char_to": bridge["raw_char_to"],
        }, evidence["source"],
    )
    entry["positive_provenance"] = {
        "kind": RULE_ID,
        "baseline_record_key": key,
        "candidate_id": candidate["candidate_id"],
    }
    entry["rule_id"] = RULE_ID
    return evidence


def _task5_output(*decisions, audit_results=()):
    return {
        "decisions": list(decisions),
        "audit_results": list(audit_results),
    }


def _minimal_accepted(key, candidate_id):
    return {
        "baseline_record_key": key,
        "status": "accepteret",
        "candidate_id": candidate_id,
    }


def _audit_confirmed(key, rule_id="complete_anchor_v1"):
    return {
        "baseline_record_key": key,
        "audit_status": "audit_confirmed",
        "rule_id": rule_id,
    }


def _publication_human_go_inputs(*, payloads=None):
    keys = [f"rk-{number}" for number in range(546)]
    baseline_text = json.dumps([baseline(key) for key in keys])
    baseline_bytes = baseline_text.encode("utf-8")
    calamari_bytes = b"Calamari"
    raw_bytes = "R\u00e5 OCR".encode("utf-8")
    pdf_bytes = b"PDF"
    if payloads is not None:
        baseline_bytes = payloads["baseline_bytes"]
        calamari_bytes = payloads["calamari_bytes"]
        raw_bytes = payloads["raw_bytes"]
        pdf_bytes = payloads["pdf_bytes"]
    source_value = {
        "edition": "1939",
        "baseline_sha256": hashlib.sha256(baseline_bytes).hexdigest(),
        "calamari_sha256": hashlib.sha256(calamari_bytes).hexdigest(),
        "raw_ocr_sha256": hashlib.sha256(raw_bytes).hexdigest(),
        "pdf_sha256": hashlib.sha256(pdf_bytes).hexdigest(),
        "profile_version": "1939-v2",
    }
    evidence_text = json.dumps({
        "schema_version": 1,
        "baseline_sha256": source_value["baseline_sha256"],
        "entries": [
            {"baseline_record_key": key, "review_status": "unreviewed"}
            for key in keys
        ],
    })
    review_text = json.dumps({
        "decisions": [
            {
                "baseline_record_key": key,
                "status": "menneskeark",
                "reason": "manuelt afsluttet",
            }
            for key in keys
        ],
        "audit_results": [],
    })
    evidence_bytes = evidence_text.encode("utf-8")
    review_bytes = review_text.encode("utf-8")
    if payloads is not None:
        evidence_bytes = payloads["evidence_bytes"]
        review_bytes = payloads["review_bytes"]
    evidence_entries = [
        {
            "baseline_record_key": key,
            "candidates": [],
            "positive_provenance": None,
            "conflicts": [],
            "source_blockers": [],
            "rule_id": None,
        }
        for key in keys
    ]
    return subject.classify_review_entries(
        source_value, set(keys), evidence_entries
    ), {
        "baseline_bytes": baseline_bytes,
        "evidence_bytes": evidence_bytes,
        "review_bytes": review_bytes,
        "calamari_bytes": calamari_bytes,
        "raw_bytes": raw_bytes,
        "pdf_bytes": pdf_bytes,
        "profile_version": "1939-v2",
    }, {
        "baseline_text": baseline_text,
        "evidence_text": evidence_text,
        "review_text": review_text,
    }


def _decoding_bytes(payload, decoded_text):
    class HostileBytes(bytes):
        def decode(self, *args, **kwargs):
            return decoded_text

    return HostileBytes(payload)


def test_publication_boundary_rejects_one_byte_decode_override_go_attack():
    one_byte_payloads = {
        field: b"x"
        for field in (
            "baseline_bytes", "evidence_bytes", "review_bytes", "calamari_bytes",
            "raw_bytes", "pdf_bytes",
        )
    }
    manifest_value, _, decoded = _publication_human_go_inputs(
        payloads=one_byte_payloads
    )
    hostile = {
        "baseline_bytes": _decoding_bytes(b"x", decoded["baseline_text"]),
        "evidence_bytes": _decoding_bytes(b"x", decoded["evidence_text"]),
        "review_bytes": _decoding_bytes(b"x", decoded["review_text"]),
        "calamari_bytes": _decoding_bytes(b"x", "Calamari"),
        "raw_bytes": _decoding_bytes(b"x", "R\u00e5 OCR"),
        "pdf_bytes": _decoding_bytes(b"x", "PDF"),
        "profile_version": "1939-v2",
    }

    with pytest.raises(ValueError, match="eksakt bytes"):
        subject._build_publication_queue_report(manifest_value, **hostile)


@pytest.mark.parametrize(
    "byte_field",
    [
        "baseline_bytes", "evidence_bytes", "review_bytes", "calamari_bytes",
        "raw_bytes", "pdf_bytes",
    ],
)
def test_publication_boundary_rejects_each_bytes_subclass(byte_field):
    manifest_value, inputs, _ = _publication_human_go_inputs()
    hostile = dict(inputs)
    original = hostile[byte_field]
    hostile[byte_field] = _decoding_bytes(original, original.decode("utf-8"))

    with pytest.raises(ValueError, match="eksakt bytes"):
        subject._build_publication_queue_report(manifest_value, **hostile)


@pytest.mark.parametrize("location", ["root", "source", "entry"])
def test_publication_boundary_rejects_mapping_subclasses(location):
    class HostileDict(dict):
        pass

    manifest_value, inputs, _ = _publication_human_go_inputs()
    hostile_manifest = copy.deepcopy(manifest_value)
    if location == "root":
        hostile_manifest = HostileDict(hostile_manifest)
    elif location == "source":
        hostile_manifest["source"] = HostileDict(hostile_manifest["source"])
    else:
        hostile_manifest["entries"][0] = HostileDict(hostile_manifest["entries"][0])

    with pytest.raises(ValueError, match="eksakte JSON-typer"):
        subject._build_publication_queue_report(hostile_manifest, **inputs)


@pytest.mark.parametrize("location", ["profile_argument", "manifest_profile"])
def test_publication_boundary_rejects_str_subclasses(location):
    class HostileStr(str):
        pass

    manifest_value, inputs, _ = _publication_human_go_inputs()
    if location == "profile_argument":
        inputs["profile_version"] = HostileStr("1939-v2")
    else:
        manifest_value["source"]["profile_version"] = HostileStr("1939-v2")

    with pytest.raises(ValueError, match="eksakt str|eksakte JSON-typer"):
        subject._build_publication_queue_report(manifest_value, **inputs)


def test_publication_boundary_rejects_boolean_manifest_schema_version():
    manifest_value, inputs, _ = _publication_human_go_inputs()
    manifest_value["schema_version"] = True

    with pytest.raises(ValueError, match="schema_version"):
        subject._build_publication_queue_report(manifest_value, **inputs)


def test_publication_boundary_allows_exact_builtin_inputs_to_reach_go():
    manifest_value, inputs, _ = _publication_human_go_inputs()

    report = subject._build_publication_queue_report(manifest_value, **inputs)

    assert report["baseline_total"] == 546
    assert report["completed"] == 546
    assert report["publication_gate"] == "GO"


def _legacy_accepted_from_evidence(evidence, *, locator=None):
    candidate = evidence["entries"][0]["candidates"][0]
    bridge = candidate["raw_structure_bridge"]
    result = {
        "baseline_record_key": evidence["entries"][0]["baseline_record_key"],
        "review_status": "accepteret",
        "candidate_id": candidate["candidate_id"],
        "post_index": 0,
        "calamari_span": copy.deepcopy(candidate["calamari_span"]),
        "calamari_verbatim_text": "Calamari",
        "pdf_pages": copy.deepcopy(candidate["pdf_pages"]),
        "kind": bridge["kind"],
        "raw_char_from": bridge["raw_char_from"],
        "raw_char_to": bridge["raw_char_to"],
        "raw_verbatim_text": "Rå OCR",
        "raw_excerpt_sha256": bridge["raw_excerpt_sha256"],
    }
    if locator is not None:
        result["baseline_locator"] = locator
    return result


def _write_task5_output(args, *decisions, audit_results=()):
    _cli_path(args, "--review").write_text(
        json.dumps(_task5_output(*decisions, audit_results=audit_results)),
        encoding="utf-8",
    )


def test_cli_rederives_exact_546_review_inputs_for_go(tmp_path):
    args, _, report_path, _ = _pilot_cli_args(tmp_path)
    human_keys = [f"rk-human-{number}" for number in range(545)]
    _cli_path(args, "--baseline").write_text(
        json.dumps([baseline("rk-auto"), *[baseline(key) for key in human_keys]]),
        encoding="utf-8",
    )
    evidence = _source_bound_evidence(args, key="rk-auto")
    evidence["entries"].extend({
        "baseline_record_key": key,
        "candidates": [],
        "positive_provenance": None,
        "conflicts": [],
        "source_blockers": [],
        "rule_id": None,
    } for key in human_keys)
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(
        args,
        *[
            {
                "baseline_record_key": key,
                "status": "menneskeark",
                "reason": "manuelt afsluttet",
            }
            for key in human_keys
        ],
        audit_results=[_audit_confirmed("rk-auto")],
    )

    assert main(args) == 0

    report = json.loads(report_path.read_text(encoding="utf-8"))
    assert report["baseline_total"] == 546
    assert report["completed"] == 545
    assert report["audit_confirmed"] == 1
    assert report["publication_gate"] == "GO"


def test_task5_minimal_accepted_decision_joins_exact_source_evidence(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(args, _minimal_accepted("rk-1", "candidate-1"))

    assert main(args) == 0

    assert json.loads(queue_path.read_text(encoding="utf-8"))["entries"][0][
        "queue_class"
    ] == "human_required"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    assert report["completed"] == 1
    assert report["publication_gate"] == "NO-GO"


def test_auto_decision_with_confirmed_audit_is_rejected_before_outputs(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(
        args,
        {
            "baseline_record_key": "rk-1",
            "status": "menneskeark",
            "reason": "må ikke overskrive automatisk klassifikation",
        },
        audit_results=[_audit_confirmed("rk-1")],
    )

    with pytest.raises(ValueError, match="auto_resolved.*audit"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_auto_decision_without_audit_is_rejected_before_outputs(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(args, {
        "baseline_record_key": "rk-1",
        "status": "menneskeark",
        "reason": "automatisk nøgle må ikke være en menneskebeslutning",
    })

    with pytest.raises(ValueError, match="auto_resolved.*audit"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_human_required_key_cannot_have_audit_result(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(args, audit_results=[_audit_confirmed("rk-1")])

    with pytest.raises(ValueError, match="audit.*human_required"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_decision_and_audit_key_sets_must_be_disjoint_before_outputs(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(
        args,
        {
            "baseline_record_key": "rk-1",
            "status": "menneskeark",
            "reason": "parkeret",
        },
        audit_results=[_audit_confirmed("rk-1")],
    )

    with pytest.raises(ValueError, match="disjunkte"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_source_blocked_key_cannot_have_audit_result(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["source_blockers"] = ["rå OCR mangler"]
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(args, audit_results=[_audit_confirmed("rk-1")])

    with pytest.raises(ValueError, match="audit.*source_blocked"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize(
    "extra",
    [
        {"reason": "uautoriseret"},
        {"duplicate_of_baseline_record_key": "rk-ukendt"},
        {"review_note": "uautoriseret Task 5-metadata"},
        {"baseline_locator": {"pages": "forkert", "local_id": None}},
    ],
    ids=["reason", "duplicate-target", "review-note", "locator"],
)
def test_task5_minimal_accepted_rejects_every_extra_field_without_outputs(
    tmp_path, extra
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(
        args, {**_minimal_accepted("rk-1", "candidate-1"), **extra}
    )

    with pytest.raises(ValueError, match="Task 5.*felter"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize(
    "decision",
    [
        {
            "baseline_record_key": "rk-1",
            "status": "menneskeark",
            "reason": "uklar",
            "review_note": "ikke del af Task 5-output",
        },
        {
            "baseline_record_key": "rk-1",
            "status": "eksplicit_dublet",
            "duplicate_of_baseline_record_key": "rk-2",
            "review_note": "ikke del af Task 5-output",
        },
    ],
    ids=["menneskeark", "duplicate"],
)
def test_task5_nonaccepted_statuses_have_exact_grammar(decision):
    with pytest.raises(ValueError, match="Task 5.*felter"):
        subject._normalize_review_decision(decision, "status")


def test_legacy_enriched_acceptance_joins_current_source_and_exact_locator(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    review = {
        "schema_version": 1,
        "source": evidence["source"],
        "entries": [_legacy_accepted_from_evidence(
            evidence, locator={"pages": "498", "local_id": None}
        )],
    }
    _cli_path(args, "--review").write_text(json.dumps(review), encoding="utf-8")

    assert main(args) == 0

    assert json.loads(report_path.read_text(encoding="utf-8"))["completed"] == 1
    assert queue_path.exists()


def test_legacy_false_baseline_locator_rejects_before_outputs(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    review = {
        "schema_version": 1,
        "source": evidence["source"],
        "entries": [_legacy_accepted_from_evidence(
            evidence, locator={"pages": "forkert", "local_id": None}
        )],
    }
    _cli_path(args, "--review").write_text(json.dumps(review), encoding="utf-8")

    with pytest.raises(ValueError, match="baseline_locator matcher ikke"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize(
    "change",
    [
        {"post_index": 1},
        {"reason": "accepteret må ikke have reason"},
        {"duplicate_of_baseline_record_key": "rk-ukendt"},
    ],
    ids=["post-index", "reason", "duplicate-target"],
)
def test_legacy_acceptance_rejects_false_or_status_foreign_fields_before_outputs(
    tmp_path, change
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    accepted = _legacy_accepted_from_evidence(evidence)
    accepted.update(change)
    _cli_path(args, "--review").write_text(json.dumps({
        "schema_version": 1,
        "source": evidence["source"],
        "entries": [accepted],
    }), encoding="utf-8")

    expected = "evidence-derived" if "post_index" in change else "ugyldige felter"
    with pytest.raises(ValueError, match=expected):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_real_task5_cli_output_is_consumed_directly_by_task6_cli(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    evidence_path = _cli_path(args, "--evidence")
    evidence_path.write_text(json.dumps(evidence), encoding="utf-8")
    candidate = evidence["entries"][0]["candidates"][0]
    choices_path = tmp_path / "task5-choices.json"
    task5_queue_path = tmp_path / "task5-queue.json"
    anchored_path = tmp_path / "task5-anchored.json"
    task5_out = tmp_path / "task5-decisions.json"
    choices_path.write_text(json.dumps({
        "schema_version": 1,
        "source": evidence["source"],
        "exported_at": "2026-08-05T12:00:00+02:00",
        "entries": [{
            "baseline_record_key": "rk-1",
            "outcome": "human_selected_candidate",
            "candidate_id": "candidate-1",
        }],
    }), encoding="utf-8")
    task5_queue_path.write_text(json.dumps({
        "schema_version": 1,
        "source": evidence["source"],
        "entries": [human("rk-1", "missing_rule_id")],
    }), encoding="utf-8")
    anchored_path.write_text(json.dumps({
        "candidate-1": {
            "baseline_record_key": "rk-1",
            "candidate": candidate,
        },
    }), encoding="utf-8")

    assert task5_subject.main([
        "--choices-to-decisions", str(choices_path),
        "--queue-manifest", str(task5_queue_path),
        "--anchored-candidates", str(anchored_path),
        "--out", str(task5_out),
    ]) == 0
    assert json.loads(task5_out.read_text(encoding="utf-8")) == _task5_output(
        _minimal_accepted("rk-1", "candidate-1")
    )
    args[args.index("--review") + 1] = str(task5_out)

    assert main(args) == 0

    assert json.loads(report_path.read_text(encoding="utf-8"))["completed"] == 1
    assert json.loads(queue_path.read_text(encoding="utf-8"))["entries"][0][
        "queue_class"
    ] == "human_required"


@pytest.mark.parametrize(
    "candidate_id,error",
    [
        ("unknown-candidate", "evidence candidate"),
        ("presentation:1939-v2:post:7", "presentation"),
    ],
)
def test_task5_accepted_unknown_or_presentation_candidate_rejects_without_outputs(
    tmp_path, candidate_id, error
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(args, _minimal_accepted("rk-1", candidate_id))

    with pytest.raises(ValueError, match=error):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_task5_accepted_candidate_must_be_owned_by_decision_key(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    baseline_path = _cli_path(args, "--baseline")
    baseline_path.write_text(
        json.dumps([baseline("rk-1"), baseline("rk-2")]), encoding="utf-8"
    )
    calamari_path = _cli_path(args, "--calamari")
    raw_path = _cli_path(args, "--raw")
    calamari_path.write_text("abcdefghij", encoding="utf-8")
    raw_path.write_text("abcdefghij", encoding="utf-8")
    entries = []
    for key, candidate_id, start in (("rk-1", "c-1", 0), ("rk-2", "c-2", 5)):
        excerpt = "abcdefghij"[start:start + 2]
        entries.append({
            "baseline_record_key": key,
            "candidates": [{
                "candidate_id": candidate_id,
                "postklasse": "nummereret",
                "calamari_span": {"char_from": start, "char_to": start + 2},
                "pdf_pages": [1],
                "raw_structure_bridge": {
                    "kind": "record_start",
                    "raw_char_from": start,
                    "raw_char_to": start + 2,
                    "raw_excerpt_sha256": hashlib.sha256(
                        excerpt.encode("utf-8")
                    ).hexdigest(),
                },
            }],
            "positive_provenance": {
                "kind": "record_key_v2_locator",
                "baseline_record_key": key,
                "candidate_id": candidate_id,
            },
            "conflicts": [],
            "source_blockers": [],
            "rule_id": None,
        })
    evidence = {
        "schema_version": 1,
        "source": _exact_cli_source(args),
        "entries": entries,
    }
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(args, _minimal_accepted("rk-1", "c-2"))

    with pytest.raises(ValueError, match="evidence candidate"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_enriched_accepted_spans_cannot_substitute_for_joined_evidence(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence["entries"][0]["rule_id"] = None
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    enriched = {
        "baseline_record_key": "rk-1",
        "status": "accepteret",
        "candidate_id": "candidate-1",
        "post_index": 0,
        "calamari_span": {"char_from": 1, "char_to": 8},
        "calamari_verbatim_text": "alamari",
        "pdf_pages": [1],
        "kind": "record_start",
        "raw_char_from": 0,
        "raw_char_to": 6,
        "raw_verbatim_text": "Rå OCR",
        "raw_excerpt_sha256": hashlib.sha256("Rå OCR".encode("utf-8")).hexdigest(),
    }
    _write_task5_output(args, enriched)

    with pytest.raises(ValueError, match="Task 5.*felter"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_two_final_acceptances_with_colliding_evidence_reject_without_outputs(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    baseline_path = _cli_path(args, "--baseline")
    baseline_path.write_text(
        json.dumps([baseline("rk-1"), baseline("rk-2")]), encoding="utf-8"
    )
    evidence = _source_bound_evidence(args)
    first = evidence["entries"][0]
    first["rule_id"] = None
    second = copy.deepcopy(first)
    second["baseline_record_key"] = "rk-2"
    second["candidates"][0]["candidate_id"] = "candidate-2"
    second["positive_provenance"].update(
        baseline_record_key="rk-2", candidate_id="candidate-2"
    )
    evidence["source"] = _exact_cli_source(args)
    evidence["entries"] = [first, second]
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")
    _write_task5_output(
        args,
        _minimal_accepted("rk-1", "candidate-1"),
        _minimal_accepted("rk-2", "candidate-2"),
    )

    with pytest.raises(ValueError, match="injektiv"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize(
    "final_candidate",
    [
        {
            **anchored_candidate("rk-auto"),
            "calamari_span": {"char_from": 30, "char_to": 40},
            "raw_structure_bridge": {
                **anchored_candidate("rk-auto")["raw_structure_bridge"],
                "raw_char_from": 130,
                "raw_char_to": 140,
            },
        },
        {
            **anchored_candidate("c-final"),
            "calamari_span": {"char_from": 15, "char_to": 25},
            "raw_structure_bridge": {
                **anchored_candidate("c-final")["raw_structure_bridge"],
                "raw_char_from": 130,
                "raw_char_to": 140,
            },
        },
        {
            **anchored_candidate("c-final"),
            "calamari_span": {"char_from": 30, "char_to": 40},
            "raw_structure_bridge": {
                **anchored_candidate("c-final")["raw_structure_bridge"],
                "raw_char_from": 105,
                "raw_char_to": 115,
            },
        },
    ],
    ids=["candidate-id-only", "calamari-only", "raw-only"],
)
def test_automatic_and_final_accepted_claims_are_globally_injective(final_candidate):
    queue = manifest(automatic("rk-auto"), human("rk-final"))
    decisions = {
        "rk-final": {
            "baseline_record_key": "rk-final",
            "review_status": "accepteret",
            "candidate_id": final_candidate["candidate_id"],
        }
    }

    with pytest.raises(ValueError, match="injektiv"):
        _validate_effective_state(
            decisions, {"rk-final": final_candidate}, queue, source()
        )


def test_source_less_no_candidate_evidence_cannot_complete_task5_acceptance(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    _write_task5_output(args, _minimal_accepted("rk-1", "candidate-1"))

    with pytest.raises(ValueError, match="source-bound evidence"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_main_writes_exclusive_queue_and_report_with_hashes_from_bytes(tmp_path):
    args, queue_path, report_path, hashes = _pilot_cli_args(tmp_path)

    assert main(args) == 0

    queue = json.loads(queue_path.read_text(encoding="utf-8"))
    report = json.loads(report_path.read_text(encoding="utf-8"))
    assert queue["source"] == {"edition": "1939", **hashes,
                               "profile_version": "1939-v2"}
    assert queue["entries"] == [{
        "baseline_record_key": "rk-1",
        "queue_class": "human_required",
        "reason_code": "no_candidate",
        "reason_da": "Ingen kandidat med komplet kildebro.",
    }]
    assert report["source"] == queue["source"]
    assert report["baseline_total"] == 1
    assert report["human_required"] == 1
    assert report["publication_gate"] == "NO-GO"
    with pytest.raises(FileExistsError):
        main(args)


def test_source_less_positive_evidence_is_rejected_without_outputs(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    evidence.pop("source")
    evidence["baseline_sha256"] = _exact_cli_source(args)["baseline_sha256"]
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")

    with pytest.raises(ValueError, match="source"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_foreign_source_with_546_candidates_is_rejected_without_outputs(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    baseline_path = _cli_path(args, "--baseline")
    evidence_path = _cli_path(args, "--evidence")
    review_path = _cli_path(args, "--review")
    records = [baseline(f"rk-{number}") for number in range(546)]
    baseline_path.write_text(json.dumps(records), encoding="utf-8")
    baseline_digest = hashlib.sha256(baseline_path.read_bytes()).hexdigest()
    review_path.write_text(json.dumps({
        "baseline_sha256": baseline_digest,
        "entries": [
            {"baseline_record_key": record["record_key"], "review_status": "unreviewed"}
            for record in records
        ],
    }), encoding="utf-8")
    foreign = _source_bound_evidence(args)
    foreign["source"]["edition"] = "1940"
    foreign["entries"] = []
    for number, record in enumerate(records):
        candidate = copy.deepcopy(_source_bound_evidence(args)["entries"][0])
        candidate["baseline_record_key"] = record["record_key"]
        candidate["candidates"][0]["candidate_id"] = f"foreign-{number}"
        candidate["candidates"][0]["calamari_span"] = {
            "char_from": number * 2,
            "char_to": number * 2 + 1,
        }
        candidate["candidates"][0]["raw_structure_bridge"].update(
            raw_char_from=number * 2,
            raw_char_to=number * 2 + 1,
        )
        candidate["positive_provenance"].update(
            baseline_record_key=record["record_key"],
            candidate_id=f"foreign-{number}",
        )
        foreign["entries"].append(candidate)
    evidence_path.write_text(json.dumps(foreign), encoding="utf-8")

    with pytest.raises(ValueError, match="evidence source"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize(
    "mutation,error",
    [
        (
            lambda evidence: evidence["entries"][0]["candidates"][0][
                "raw_structure_bridge"
            ].update(raw_excerpt_sha256="0" * 64),
            "raw_excerpt_sha256 matcher ikke",
        ),
        (
            lambda evidence: evidence["entries"][0]["candidates"][0][
                "calamari_span"
            ].update(char_to=9),
            "Calamari-span",
        ),
        (
            lambda evidence: evidence["entries"][0]["candidates"][0][
                "raw_structure_bridge"
            ].update(raw_char_to=7),
            "rå-bro",
        ),
    ],
)
def test_exact_source_rejects_candidate_not_bound_to_current_text(
    tmp_path, mutation, error
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    mutation(evidence)
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")

    with pytest.raises(ValueError, match=error):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize(
    "mutation,error",
    [
        (lambda evidence: evidence.update(audit_results=[]), "evidence root"),
        (lambda evidence: evidence["source"].update(extra="x"), "evidence source"),
        (lambda evidence: evidence["source"].pop("pdf_sha256"), "evidence source"),
        (lambda evidence: evidence["entries"][0].update(extra="x"), "evidenspost"),
        (
            lambda evidence: evidence["entries"][0]["candidates"][0].update(extra="x"),
            "candidate",
        ),
        (
            lambda evidence: evidence["entries"][0]["positive_provenance"].update(
                extra="x"
            ),
            "positive_provenance",
        ),
        (
            lambda evidence: evidence["entries"][0]["positive_provenance"].update(
                candidate_id="foreign-candidate"
            ),
            "positive_provenance",
        ),
    ],
)
def test_source_bound_evidence_rejects_unknown_or_incomplete_grammar(
    tmp_path, mutation, error
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    mutation(evidence)
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")

    with pytest.raises(ValueError, match=error):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize("source_bound", [False, True])
@pytest.mark.parametrize("invalid_version", [True, 1.0, "1", None])
def test_evidence_schema_version_requires_exact_integer_one(
    tmp_path, source_bound, invalid_version
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    if source_bound:
        evidence = _source_bound_evidence(args)
    else:
        evidence = json.loads(
            _cli_path(args, "--evidence").read_text(encoding="utf-8")
        )
    if invalid_version is None:
        evidence.pop("schema_version", None)
    else:
        evidence["schema_version"] = invalid_version
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")

    with pytest.raises(ValueError, match="schema_version"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize("invalid_version", [True, 1.0, "1", None])
def test_review_schema_version_requires_exact_integer_one_without_outputs(
    tmp_path, invalid_version
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    review_path = _cli_path(args, "--review")
    review = json.loads(review_path.read_text(encoding="utf-8"))
    if invalid_version is None:
        review.pop("schema_version")
    else:
        review["schema_version"] = invalid_version
    review_path.write_text(json.dumps(review), encoding="utf-8")

    with pytest.raises(ValueError, match="schema_version"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize(
    "mutation,error",
    [
        (lambda entries: entries.clear(), "baseline-dækning"),
        (lambda entries: entries.append(copy.deepcopy(entries[0])), "dublet evidence"),
        (
            lambda entries: entries[0].update(baseline_record_key="rk-foreign"),
            "ukendt baseline_record_key",
        ),
    ],
)
def test_source_bound_evidence_requires_exact_unique_baseline_keys(
    tmp_path, mutation, error
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    mutation(evidence["entries"])
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")

    with pytest.raises(ValueError, match=error):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_exact_source_bound_candidate_can_be_classified_automatically(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _source_bound_evidence(args)
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")

    assert main(args) == 0

    queue = json.loads(queue_path.read_text(encoding="utf-8"))
    assert queue["entries"][0]["queue_class"] == "auto_resolved"
    assert queue["entries"][0]["candidate"] == evidence["entries"][0]["candidates"][0]
    assert json.loads(report_path.read_text(encoding="utf-8"))["publication_gate"] == "NO-GO"


def test_prepare_queue_accepts_the_dual_rendition_consensus_provenance_kind(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _dual_source_bound_evidence(args)
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")

    assert main(args) == 0

    queue = json.loads(queue_path.read_text(encoding="utf-8"))
    assert queue["entries"][0]["queue_class"] == "auto_resolved"
    assert queue["entries"][0]["rule_id"] == RULE_ID
    assert json.loads(report_path.read_text(encoding="utf-8"))["publication_gate"] == "NO-GO"


@pytest.mark.parametrize("mutate", [
    lambda entry: entry.update(rule_id="complete_anchor_v1"),
    lambda entry: entry["candidates"][0]["raw_structure_bridge"].update(kind="record_start"),
    lambda entry: entry["positive_provenance"].update(kind="record_key_v2_locator"),
    lambda entry: entry["candidates"][0].update(candidate_id="1939:dual-v1:stale"),
])
def test_prepare_queue_rejects_dual_consensus_cross_layer_mismatch(tmp_path, mutate):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    evidence = _dual_source_bound_evidence(args)
    entry = evidence["entries"][0]
    mutate(entry)
    if entry["positive_provenance"]["candidate_id"] != entry["candidates"][0]["candidate_id"]:
        entry["positive_provenance"]["candidate_id"] = entry["candidates"][0]["candidate_id"]
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")

    with pytest.raises(ValueError, match="dual consensus"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


@pytest.mark.parametrize("option,replacement", [
    ("--baseline", json.dumps([baseline("rk-1", pages="499")]).encode("utf-8")),
    ("--calamari", b"changed Calamari"),
    ("--raw", b"changed raw OCR"),
    ("--pdf", b"%PDF-changed"),
])
def test_prepare_queue_rejects_evidence_from_stale_or_mixed_source_bytes(
    tmp_path, option, replacement
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    _cli_path(args, "--evidence").write_text(
        json.dumps(_source_bound_evidence(args)), encoding="utf-8"
    )
    _cli_path(args, option).write_bytes(replacement)

    with pytest.raises(ValueError, match="evidence source matcher ikke"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_baseline_hash_and_keys_come_from_the_same_single_read(tmp_path, monkeypatch):
    args, queue_path, _, _ = _pilot_cli_args(tmp_path)
    baseline_path = _cli_path(args, "--baseline")
    captured_bytes = baseline_path.read_bytes()
    captured_digest = hashlib.sha256(captured_bytes).hexdigest()
    real_read_bytes = Path.read_bytes
    replaced = False

    def replace_after_captured_read(path):
        nonlocal replaced
        value = real_read_bytes(path)
        if path == baseline_path and not replaced:
            replaced = True
            path.write_text(json.dumps([baseline("rk-replaced")]), encoding="utf-8")
        return value

    monkeypatch.setattr(Path, "read_bytes", replace_after_captured_read)

    assert main(args) == 0

    queue = json.loads(queue_path.read_text(encoding="utf-8"))
    assert queue["source"]["baseline_sha256"] == captured_digest
    assert [entry["baseline_record_key"] for entry in queue["entries"]] == ["rk-1"]


def test_strict_json_bytes_rejects_nested_duplicate_fields():
    with pytest.raises(ValueError, match="dublet JSON-feltnavn"):
        subject._strict_json_bytes(
            b'{"entries":[{"baseline_record_key":"rk-1","nested":{"x":1,"x":2}}]}',
            "evidence",
        )


def test_main_preflights_both_outputs_and_rejects_unpinned_profile(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    report_path.write_text("bevar", encoding="utf-8")
    with pytest.raises(FileExistsError):
        main(args)
    assert not queue_path.exists()
    assert report_path.read_text(encoding="utf-8") == "bevar"

    report_path.unlink()
    args[args.index("1939-v2")] = "1939-v3"
    with pytest.raises(ValueError, match="profile_version"):
        main(args)
    assert not queue_path.exists()
    assert not report_path.exists()


def test_source_less_bare_accepted_546_review_is_rejected_without_outputs(tmp_path):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    baseline_path = tmp_path / "baseline.json"
    evidence_path = tmp_path / "evidence.json"
    review_path = tmp_path / "review.json"
    records = [baseline(f"rk-{number}") for number in range(546)]
    baseline_path.write_text(json.dumps(records), encoding="utf-8")
    evidence_path.write_text(json.dumps({
        "schema_version": 1,
        "baseline_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        "entries": [
            {"baseline_record_key": record["record_key"], "review_status": "unreviewed"}
            for record in records
        ],
    }), encoding="utf-8")
    review_path.write_text(json.dumps({
        "schema_version": 1,
        "baseline_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        "entries": [
            {"baseline_record_key": record["record_key"], "review_status": "accepteret"}
            for record in records
        ],
    }), encoding="utf-8")

    with pytest.raises(ValueError, match="source"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_546_fabricated_task5_acceptances_without_evidence_reject_without_outputs(
    tmp_path,
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    baseline_path = _cli_path(args, "--baseline")
    evidence_path = _cli_path(args, "--evidence")
    records = [baseline(f"rk-{number}") for number in range(546)]
    baseline_path.write_text(json.dumps(records), encoding="utf-8")
    evidence_path.write_text(json.dumps({
        "schema_version": 1,
        "baseline_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        "entries": [
            {"baseline_record_key": record["record_key"], "review_status": "unreviewed"}
            for record in records
        ],
    }), encoding="utf-8")
    _write_task5_output(args, *(
        _minimal_accepted(record["record_key"], f"fabricated-{number}")
        for number, record in enumerate(records)
    ))

    with pytest.raises(ValueError, match="source-bound evidence"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_exact_source_546_presentation_acceptances_never_complete_or_publish(tmp_path):
    args, queue_path, report_path, hashes = _pilot_cli_args(tmp_path)
    baseline_path = tmp_path / "baseline.json"
    evidence_path = tmp_path / "evidence.json"
    review_path = tmp_path / "review.json"
    records = [baseline(f"rk-{number}") for number in range(546)]
    baseline_path.write_text(json.dumps(records), encoding="utf-8")
    evidence_path.write_text(json.dumps({
        "schema_version": 1,
        "baseline_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        "entries": [
            {"baseline_record_key": record["record_key"], "review_status": "unreviewed"}
            for record in records
        ],
    }), encoding="utf-8")
    source_value = {
        "edition": "1939",
        **hashes,
        "baseline_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        "profile_version": "1939-v2",
    }
    review_path.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "entries": [
            {
                **accepted_decision(
                    record["record_key"],
                    f"presentation:1939-v2:post:{number}",
                ),
                "post_index": number,
                "calamari_span": {
                    "char_from": number * 2,
                    "char_to": number * 2 + 1,
                },
                "raw_char_from": number * 2,
                "raw_char_to": number * 2 + 1,
            }
            for number, record in enumerate(records)
        ],
    }), encoding="utf-8")

    with pytest.raises(ValueError, match="reserveret presentation"):
        main(args)

    assert not queue_path.exists()
    assert not report_path.exists()


def test_review_state_rejects_source_mismatch_and_malformed_accepted_evidence():
    mismatch = {"source": {**source(), "raw_ocr_sha256": "f" * 64}, "entries": []}
    with pytest.raises(ValueError, match="source hashes"):
        _review_state(mismatch, source(), {"rk-1"})

    malformed = accepted_decision("rk-1")
    malformed["raw_excerpt_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="matcher ikke raw_verbatim_text"):
        _review_state(
            {"schema_version": 1, "source": source(), "entries": [malformed]},
            source(),
            {"rk-1"},
        )


def test_enriched_final_decision_without_source_bound_evidence_cannot_complete():
    accepted = accepted_decision("rk-1")
    converted = {**accepted, "status": accepted["review_status"]}
    converted.pop("review_status")

    with pytest.raises(ValueError, match="Task 5.*felter"):
        _review_state(
            {"schema_version": 1, "source": source(), "decisions": [converted]},
            source(),
            {"rk-1"},
        )


def test_valid_provisional_choice_export_is_not_completed_before_conversion():
    completed, audit_results = _review_state(
        {
            "schema_version": 1,
            "source": source(),
            "exported_at": "2026-08-05T12:00:00+02:00",
            "entries": [{
                "baseline_record_key": "rk-1",
                "outcome": "undecidable",
                "reason": "kilden kan ikke afgøres",
            }],
        },
        source(),
        {"rk-1"},
    )

    assert completed == set()
    assert audit_results == []


def test_source_less_audit_and_invalid_audit_schema_are_rejected():
    with pytest.raises(ValueError, match="source"):
        _review_state(
            {
                "schema_version": 1,
                "baseline_sha256": "a" * 64,
                "entries": [{"baseline_record_key": "rk-1", "review_status": "unreviewed"}],
                "audit_results": [{
                    "baseline_record_key": "rk-1",
                    "audit_status": "audit_confirmed",
                    "rule_id": "complete_anchor_v1",
                }],
            },
            source(),
            {"rk-1"},
        )

    with pytest.raises(ValueError, match="audit result"):
        _review_state(
            {
                "schema_version": 1,
                "source": source(),
                "audit_results": [{
                    "baseline_record_key": "rk-1",
                    "audit_status": "audit_confirmed",
                    "rule_id": "complete_anchor_v1",
                    "reason": "bekræftet må ikke have reason",
                }],
            },
            source(),
            {"rk-1"},
        )


def test_valid_failed_or_undecidable_audit_blocks_rule_group():
    auto = automatic("rk-auto")
    humans = [human(f"rk-human-{number}") for number in range(545)]
    completed, audit_results = _review_state(
        {
            "schema_version": 1,
            "source": source(),
            "audit_results": [{
                "baseline_record_key": "rk-auto",
                "audit_status": "audit_undecidable",
                "rule_id": "complete_anchor_v1",
                "reason": "mennesket kunne ikke afgøre kontrollen",
            }],
        },
        source(),
        {"rk-auto", *{entry["baseline_record_key"] for entry in humans}},
        manifest=manifest(auto, *humans),
    )
    completed.update(entry["baseline_record_key"] for entry in humans)

    report = build_queue_report(
        manifest(auto, *humans),
        audit_keys=["rk-auto"],
        completed_keys=completed,
        audit_results=audit_results,
    )

    assert report["audit_confirmed"] == 0
    assert report["audit_blocked_rule_groups"] == ["complete_anchor_v1|nummereret"]
    assert report["publication_gate"] == "NO-GO"


def test_exclusive_writer_removes_partial_file_and_allows_immediate_retry(
    tmp_path, monkeypatch
):
    out = tmp_path / "report.json"
    real_dump = subject.json.dump

    def fail_mid_write(value, handle, **kwargs):
        handle.write("{partial")
        raise OSError("simuleret write-fejl")

    monkeypatch.setattr(subject.json, "dump", fail_mid_write)
    with pytest.raises(OSError, match="simuleret write-fejl"):
        subject._write_json_exclusive(out, {"publication_gate": "NO-GO"})
    assert not out.exists()

    monkeypatch.setattr(subject.json, "dump", real_dump)
    subject._write_json_exclusive(out, {"publication_gate": "NO-GO"})
    assert json.loads(out.read_text(encoding="utf-8")) == {
        "publication_gate": "NO-GO"
    }


@pytest.mark.parametrize("interrupt_type", [KeyboardInterrupt, SystemExit])
def test_aggregate_rollback_cleans_both_outputs_and_reraises_baseexception(
    tmp_path, monkeypatch, interrupt_type
):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    preexisting = tmp_path / "bevar.txt"
    preexisting.write_text("bevar", encoding="utf-8")
    real_dump = subject.json.dump
    calls = 0
    interruption = interrupt_type("simuleret afbrydelse")

    def interrupt_second_output(value, handle, **kwargs):
        nonlocal calls
        calls += 1
        if calls == 2:
            handle.write("{partial")
            raise interruption
        return real_dump(value, handle, **kwargs)

    monkeypatch.setattr(subject.json, "dump", interrupt_second_output)
    with pytest.raises(interrupt_type) as caught:
        main(args)

    assert caught.value is interruption
    assert not queue_path.exists()
    assert not report_path.exists()
    assert preexisting.read_text(encoding="utf-8") == "bevar"

    monkeypatch.setattr(subject.json, "dump", real_dump)
    assert main(args) == 0
    assert json.loads(queue_path.read_text(encoding="utf-8"))["schema_version"] == 1
    assert json.loads(report_path.read_text(encoding="utf-8"))["publication_gate"] == "NO-GO"
    assert preexisting.read_text(encoding="utf-8") == "bevar"
