"""Contract tests for the private, lossless 1939 review queue model."""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

import pytest

import prepare_review_queue_1939 as subject
from prepare_review_queue_1939 import (
    _review_state,
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
        "baseline_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        "entries": [{"baseline_record_key": "rk-1", "review_status": "unreviewed"}],
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
def test_evidence_schema_version_rejects_boolean_one(tmp_path, source_bound):
    args, queue_path, report_path, _ = _pilot_cli_args(tmp_path)
    if source_bound:
        evidence = _source_bound_evidence(args)
    else:
        evidence = json.loads(
            _cli_path(args, "--evidence").read_text(encoding="utf-8")
        )
    evidence["schema_version"] = True
    _cli_path(args, "--evidence").write_text(json.dumps(evidence), encoding="utf-8")

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


def test_exact_source_546_presentation_acceptances_never_complete_or_publish(tmp_path):
    args, queue_path, report_path, hashes = _pilot_cli_args(tmp_path)
    baseline_path = tmp_path / "baseline.json"
    evidence_path = tmp_path / "evidence.json"
    review_path = tmp_path / "review.json"
    records = [baseline(f"rk-{number}") for number in range(546)]
    baseline_path.write_text(json.dumps(records), encoding="utf-8")
    evidence_path.write_text(json.dumps({
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


def test_only_exact_source_semantically_complete_final_decisions_count_completed():
    accepted = accepted_decision("rk-1")
    converted = {**accepted, "status": accepted["review_status"]}
    converted.pop("review_status")

    completed, audit_results = _review_state(
        {"schema_version": 1, "source": source(), "decisions": [converted]},
        source(),
        {"rk-1"},
    )

    assert completed == {"rk-1"}
    assert audit_results == []


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
