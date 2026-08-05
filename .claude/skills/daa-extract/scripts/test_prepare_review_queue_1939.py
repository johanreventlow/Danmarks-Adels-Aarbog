"""Contract tests for the private, lossless 1939 review queue model."""

from __future__ import annotations

import copy
import hashlib
import json

import pytest

from prepare_review_queue_1939 import build_queue_report, build_review_view_model, main


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


def test_report_accounts_for_every_record_and_fails_closed():
    report = build_queue_report(
        report_manifest(
            queue_entry("rk-a", "auto_resolved", "complete_unique_anchored_candidate"),
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
    assert report["collision_overlap_counts"] == {
        "candidate_collision": 0,
        "calamari_span_overlap": 0,
        "raw_ocr_span_overlap": 0,
    }
    assert report["publication_gate"] == "NO-GO"


def test_report_is_go_only_for_546_completed_or_validated_and_confirmed_records():
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
    assert report["publication_gate"] == "GO"


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
        "entries": [{"baseline_record_key": "rk-1"}],
    }), encoding="utf-8")
    review_path.write_text(json.dumps({
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
