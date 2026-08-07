import json
import hashlib

import pytest

from coverage_1939 import legacy_review_entry_errors, validate_coverage
from prepare_coverage_1939 import (
    assemble_coverage,
    build_candidates,
    main,
    materialize_coverage,
    review_summary,
    review_to_decisions,
    validate_review_template,
    write_review_template,
)

RAW_TEXT = "x" * 128


def post(**overrides):
    value = {
        "lokal_id": "Stamme.1",
        "postklasse": None,
        "sider": "496",
        "raw_text": "Alfa",
    }
    value.update(overrides)
    return value


def bridge(**overrides):
    value = {
        "candidate_id": "candidate-1",
        "post_index": 0,
        "calamari_span": {"char_from": 0, "char_to": 8},
        "calamari_verbatim_text": "1. Alfa\n",
        "pdf_pages": [496],
        "kind": "line_header",
        "raw_char_from": 100,
        "raw_char_to": 112,
        "raw_verbatim_text": RAW_TEXT[100:112],
        "raw_excerpt_sha256": hashlib.sha256(RAW_TEXT[100:112].encode("utf-8")).hexdigest(),
    }
    value.update(overrides)
    return value


def test_common_coverage_validator_rejects_presentation_candidate_only():
    candidate = {
        "candidate_id": "real-anchor",
        "postklasse": "nummereret",
        "calamari_span": {"char_from": 10, "char_to": 20},
        "pdf_pages": [498],
        "raw_structure_bridge": {
            "kind": "record_start",
            "raw_char_from": 100,
            "raw_char_to": 110,
            "raw_excerpt_sha256": "e" * 64,
        },
    }
    bundle = {
        "schema_version": 1,
        "source": {
            "edition": "1939",
            "calamari_sha256": "a" * 64,
            "raw_ocr_sha256": "b" * 64,
            "pdf_sha256": "c" * 64,
        },
        "entries": [{
            "baseline_record_key": "rk-1",
            "status": "accepteret",
            "candidate": candidate,
        }],
    }

    assert validate_coverage(bundle, expected_baseline_keys={"rk-1"})[
        "rk-1"
    ]["candidate"]["candidate_id"] == "real-anchor"

    bundle["entries"][0]["candidate"] = {
        **candidate,
        "candidate_id": "presentation:1939-v2:post:7",
    }
    with pytest.raises(ValueError, match="reserveret presentation"):
        validate_coverage(bundle, expected_baseline_keys={"rk-1"})


def test_build_candidates_preserves_explicit_exact_calamari_slice():
    result = build_candidates("1. Alfa\n2. Beta\n", RAW_TEXT, [post()], [bridge()])

    assert result == [{
        "candidate_id": "candidate-1",
        "postklasse": "nummereret",
        "calamari_span": {"char_from": 0, "char_to": 8},
        "pdf_pages": [496],
        "raw_structure_bridge": {
            "kind": "line_header",
            "raw_char_from": 100,
            "raw_char_to": 112,
            "raw_excerpt_sha256": hashlib.sha256(
                RAW_TEXT[100:112].encode("utf-8")
            ).hexdigest(),
        },
    }]


def test_build_candidates_preserves_verified_raw_excerpt():
    raw_text = "rå Alfa"
    raw_digest = hashlib.sha256("rå".encode("utf-8")).hexdigest()

    result = build_candidates(
        "1. Alfa\n",
        raw_text,
        [post()],
        [bridge(
            raw_char_from=0,
            raw_char_to=2,
            raw_verbatim_text="rå",
            raw_excerpt_sha256=raw_digest,
        )],
    )

    assert result[0]["raw_structure_bridge"] == {
        "kind": "line_header",
        "raw_char_from": 0,
        "raw_char_to": 2,
        "raw_excerpt_sha256": raw_digest,
    }


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        ({"raw_char_from": 0, "raw_char_to": 99}, "ikke eksakt rå-bro"),
        ({"raw_char_from": 0, "raw_char_to": 2, "raw_verbatim_text": "forkert"}, "ikke eksakt rå-bro"),
        ({"raw_char_from": 0, "raw_char_to": 2, "raw_excerpt_sha256": "0" * 64}, "rå-bro SHA-256"),
    ],
)
def test_build_candidates_rejects_unverified_raw_excerpt(overrides, message):
    raw_text = "rå Alfa"
    values = {
        "raw_char_from": 0,
        "raw_char_to": 2,
        "raw_verbatim_text": "rå",
        "raw_excerpt_sha256": hashlib.sha256("rå".encode("utf-8")).hexdigest(),
    }
    values.update(overrides)

    with pytest.raises(ValueError, match=message):
        build_candidates("1. Alfa\n", raw_text, [post()], [bridge(**values)])


@pytest.mark.parametrize(
    ("bridges", "posts", "message"),
    [
        ([bridge(calamari_verbatim_text="forkert")], [post()], "ikke eksakt Calamari-span"),
        ([bridge(post_index=1)], [post()], "ukendt post_index"),
        ([bridge(), bridge(candidate_id="candidate-2")], [post()], "post_index forekommer flere gange"),
        ([bridge(), bridge(post_index=1, candidate_id="candidate-2",
                           calamari_span={"char_from": 4, "char_to": 16},
                           calamari_verbatim_text="lfa\n2. Beta\n")],
         [post(), post(lokal_id="Stamme.2", raw_text="Beta")], "overlapper"),
        ([bridge(pdf_pages=[497])], [post()], "PDF-sider stemmer ikke"),
        ([bridge(raw_char_from=12, raw_char_to=12)], [post()], "rå-bro"),
    ],
)
def test_build_candidates_rejects_unanchored_or_ambiguous_bridge(bridges, posts, message):
    with pytest.raises(ValueError, match=message):
        build_candidates("1. Alfa\n2. Beta\n", RAW_TEXT, posts, bridges)


def test_assemble_coverage_resolves_only_known_candidate_ids():
    candidates = build_candidates("1. Alfa\n2. Beta\n", RAW_TEXT, [post()], [bridge()])

    result = assemble_coverage(
        source(),
        {"rk-1", "rk-2"},
        [
            {"baseline_record_key": "rk-1", "status": "accepteret", "candidate_id": "candidate-1"},
            {"baseline_record_key": "rk-2", "status": "menneskeark", "reason": "ingen-entydig-bro"},
        ],
        candidates,
    )

    assert result["entries"][0]["candidate"] == candidates[0]
    assert result["entries"][1]["status"] == "menneskeark"


def test_assemble_coverage_rejects_unknown_candidate_id():
    with pytest.raises(ValueError, match="ukendt candidate_id"):
        assemble_coverage(
            source(),
            {"rk-1"},
            [{"baseline_record_key": "rk-1", "status": "accepteret", "candidate_id": "ukendt"}],
            [],
        )


def source():
    return {
        "edition": "1939",
        "calamari_sha256": "a" * 64,
        "raw_ocr_sha256": "b" * 64,
        "pdf_sha256": "c" * 64,
    }


def test_materialize_coverage_writes_complete_bundle_once(tmp_path):
    calamari = tmp_path / "calamari.txt"
    raw = tmp_path / "raw.txt"
    pdf = tmp_path / "book.pdf"
    baseline = tmp_path / "baseline.json"
    decisions = tmp_path / "decisions.json"
    out = tmp_path / "coverage.json"
    text = "### PAGE 496 ###\n   1. Alfa † 1900.\n"
    calamari.write_text(text, encoding="utf-8")
    raw.write_text("raw structure", encoding="utf-8")
    pdf.write_bytes(b"pdf")
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    start = text.index("   1.")
    decisions.write_text(
        json.dumps({"entries": [{
            "baseline_record_key": "rk-1",
            "status": "accepteret",
            "candidate_id": "candidate-1",
            "post_index": 0,
            "calamari_span": {"char_from": start, "char_to": len(text)},
            "calamari_verbatim_text": text[start:],
            "pdf_pages": [496],
                "kind": "line_header",
                "raw_char_from": 0,
                "raw_char_to": 3,
                "raw_verbatim_text": "raw",
                "raw_excerpt_sha256": hashlib.sha256(b"raw").hexdigest(),
        }]}),
        encoding="utf-8",
    )

    result = materialize_coverage(calamari, raw, pdf, baseline, decisions, out)

    assert result["entries"][0]["candidate"]["candidate_id"] == "candidate-1"
    assert json.loads(out.read_text(encoding="utf-8")) == result
    with pytest.raises(FileExistsError):
        materialize_coverage(calamari, raw, pdf, baseline, decisions, out)


def test_cli_requires_all_private_input_paths():
    with pytest.raises(SystemExit):
        main([])


def test_cli_can_write_review_template_with_only_baseline_and_output(tmp_path):
    baseline = tmp_path / "baseline.json"
    out = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")

    assert main(["--make-review-template", "--baseline", str(baseline), "--out", str(out)]) == 0

    assert json.loads(out.read_text(encoding="utf-8"))["entries"] == [
        {"baseline_record_key": "rk-1", "review_status": "unreviewed",
         "baseline_locator": {"pages": None, "local_id": None}}
    ]


def test_cli_can_check_review_without_writing(tmp_path, capsys):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    write_review_template(baseline, review)

    assert main(["--check-review", str(review), "--baseline", str(baseline)]) == 0

    assert json.loads(capsys.readouterr().out) == {
        "review": str(review),
        "entries": 1,
    }


def test_cli_can_convert_only_a_complete_checked_review_to_decisions(tmp_path, capsys):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    decisions = tmp_path / "decisions.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    template = write_review_template(baseline, review)
    template["entries"][0].update({
        "review_status": "menneskeark",
        "reason": "ingen entydig bro",
    })
    review.write_text(json.dumps(template), encoding="utf-8")

    assert main([
        "--review-to-decisions", str(review),
        "--baseline", str(baseline),
        "--out", str(decisions),
    ]) == 0

    assert json.loads(capsys.readouterr().out) == {
        "out": str(decisions),
        "entries": 1,
    }
    assert json.loads(decisions.read_text(encoding="utf-8")) == {
        "entries": [{
            "baseline_record_key": "rk-1",
            "reason": "ingen entydig bro",
            "status": "menneskeark",
        }]
    }
    with pytest.raises(FileExistsError):
        main([
            "--review-to-decisions", str(review),
            "--baseline", str(baseline),
            "--out", str(decisions),
        ])


def test_write_review_template_lists_each_baseline_key_once(tmp_path):
    baseline = tmp_path / "baseline.json"
    out = tmp_path / "review.json"
    baseline.write_text(
        '[{"record_key":"rk-2","sider":"501-502","_v2_lokal_id":"II.Fjerde.9"},'
        '{"record_key":"rk-1","sider":"496","_v2_lokal_id":"Stamme.I.U1"}]',
        encoding="utf-8",
    )

    result = write_review_template(baseline, out)

    assert result["baseline_sha256"]
    assert result["entries"] == [
        {"baseline_record_key": "rk-1", "review_status": "unreviewed",
         "baseline_locator": {"pages": "496", "local_id": "Stamme.I.U1"}},
        {"baseline_record_key": "rk-2", "review_status": "unreviewed",
         "baseline_locator": {"pages": "501-502", "local_id": "II.Fjerde.9"}},
    ]
    with pytest.raises(FileExistsError):
        write_review_template(baseline, out)


def test_validate_review_template_requires_current_baseline(tmp_path):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1","sider":"496","_v2_lokal_id":"I.1"}]', encoding="utf-8")
    write_review_template(baseline, review)

    assert validate_review_template(review, baseline)["entries"][0]["review_status"] == "unreviewed"

    baseline.write_text('[{"record_key":"rk-1"},{"record_key":"rk-2"}]', encoding="utf-8")
    with pytest.raises(ValueError, match="baseline SHA-256"):
        validate_review_template(review, baseline)


def test_validate_review_template_refuses_unknown_entry_fields(tmp_path):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    template = write_review_template(baseline, review)
    template["entries"][0]["guessed_person_id"] = "never-infer"
    review.write_text(json.dumps(template), encoding="utf-8")

    with pytest.raises(ValueError, match="uautoriserede"):
        validate_review_template(review, baseline)


def test_validate_review_template_rejects_browser_draft_placeholder(tmp_path):
    """draft is a browser-export-only shape (review_choices_1939._is_draft_placeholder);
    a plain legacy review ledger (write_review_template's own format) must
    stay strict and never accept it as a valid entry.
    """
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    template = write_review_template(baseline, review)
    template["entries"][0] = {"baseline_record_key": "rk-1", "draft": True}
    review.write_text(json.dumps(template), encoding="utf-8")

    with pytest.raises(ValueError, match="uautoriserede"):
        validate_review_template(review, baseline)


@pytest.mark.parametrize(
    ("status", "fields", "message"),
    [
        ("menneskeark", {}, "reason"),
        ("eksplicit_dublet", {}, "duplicate_of_baseline_record_key"),
        ("accepteret", {
            "candidate_id": "candidate-1",
            "calamari_span": {"char_from": 0, "char_to": 1},
            "calamari_verbatim_text": "A",
            "pdf_pages": [496],
            "kind": "line_header",
            "raw_char_from": 0,
            "raw_char_to": 1,
        }, "post_index"),
    ],
)
def test_validate_review_template_rejects_incomplete_review_decisions(
    tmp_path, status, fields, message
):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    template = write_review_template(baseline, review)
    template["entries"][0].update({"review_status": status, **fields})
    review.write_text(json.dumps(template), encoding="utf-8")

    with pytest.raises(ValueError, match=message):
        validate_review_template(review, baseline)


def test_validate_review_template_rejects_ill_typed_accepted_anchor(tmp_path):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    template = write_review_template(baseline, review)
    template["entries"][0].update({
        "review_status": "accepteret",
        "candidate_id": "candidate-1",
        "post_index": "not-an-index",
        "calamari_span": {"char_from": 0, "char_to": 1},
        "calamari_verbatim_text": "A",
        "pdf_pages": [496],
        "kind": "line_header",
        "raw_char_from": 0,
        "raw_char_to": 1,
        "raw_verbatim_text": "x",
        "raw_excerpt_sha256": hashlib.sha256(b"x").hexdigest(),
    })
    review.write_text(json.dumps(template), encoding="utf-8")

    with pytest.raises(ValueError, match="post_index"):
        validate_review_template(review, baseline)


def test_validate_review_template_requires_raw_excerpt_proof(tmp_path):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    template = write_review_template(baseline, review)
    template["entries"][0].update({
        "review_status": "accepteret",
        "candidate_id": "candidate-1",
        "post_index": 0,
        "calamari_span": {"char_from": 0, "char_to": 1},
        "calamari_verbatim_text": "A",
        "pdf_pages": [496],
        "kind": "line_header",
        "raw_char_from": 0,
        "raw_char_to": 1,
        "raw_excerpt_sha256": hashlib.sha256(b"x").hexdigest(),
    })
    review.write_text(json.dumps(template), encoding="utf-8")

    with pytest.raises(ValueError, match="raw_verbatim_text"):
        validate_review_template(review, baseline)


def test_validate_review_template_rejects_wrong_raw_excerpt_hash(tmp_path):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    template = write_review_template(baseline, review)
    template["entries"][0].update({
        "review_status": "accepteret",
        "candidate_id": "candidate-1",
        "post_index": 0,
        "calamari_span": {"char_from": 0, "char_to": 1},
        "calamari_verbatim_text": "A",
        "pdf_pages": [496],
        "kind": "line_header",
        "raw_char_from": 0,
        "raw_char_to": 1,
        "raw_verbatim_text": "x",
        "raw_excerpt_sha256": "0" * 64,
    })
    review.write_text(json.dumps(template), encoding="utf-8")

    with pytest.raises(ValueError, match="raw_excerpt_sha256"):
        validate_review_template(review, baseline)


def test_authoritative_legacy_validator_reserves_presentation_candidate_ids():
    accepted = {
        "baseline_record_key": "rk-1",
        "review_status": "accepteret",
        **bridge(candidate_id="real-anchor", raw_verbatim_text=RAW_TEXT[100:112]),
    }
    assert legacy_review_entry_errors(accepted) == []

    presentation_only = {
        **accepted,
        "candidate_id": "presentation:1939-v2:post:7",
    }
    assert legacy_review_entry_errors(presentation_only) == [
        "accepteret candidate_id bruger reserveret presentation:-namespace"
    ]


def test_legacy_review_template_rejects_presentation_candidate_id(tmp_path):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-1"}]', encoding="utf-8")
    template = write_review_template(baseline, review)
    template["entries"][0].update({
        "review_status": "accepteret",
        **bridge(
            candidate_id="presentation:1939-v2:post:7",
            raw_verbatim_text=RAW_TEXT[100:112],
        ),
    })
    review.write_text(json.dumps(template), encoding="utf-8")

    with pytest.raises(ValueError, match="reserveret presentation"):
        validate_review_template(review, baseline)


def test_cli_review_summary_lists_each_unreviewed_record(tmp_path, capsys):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text('[{"record_key":"rk-2"},{"record_key":"rk-1"}]', encoding="utf-8")
    write_review_template(baseline, review)

    assert main(["--review-summary", str(review), "--baseline", str(baseline)]) == 0

    assert json.loads(capsys.readouterr().out) == {
        "review": str(review),
        "entries": 2,
        "status_counts": {"unreviewed": 2},
        "ready_for_decisions": False,
        "blockers": [
            {"baseline_record_key": "rk-1", "issue": "unreviewed"},
            {"baseline_record_key": "rk-2", "issue": "unreviewed"},
        ],
    }


def test_review_summary_lists_invalid_duplicate_target(tmp_path):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    baseline.write_text(
        '[{"record_key":"rk-1"},{"record_key":"rk-2"}]',
        encoding="utf-8",
    )
    template = write_review_template(baseline, review)
    entries = {entry["baseline_record_key"]: entry for entry in template["entries"]}
    entries["rk-1"].update({
        "review_status": "eksplicit_dublet",
        "duplicate_of_baseline_record_key": "missing-target",
    })
    entries["rk-2"].update({
        "review_status": "menneskeark",
        "reason": "ingen entydig bro",
    })
    review.write_text(json.dumps(template), encoding="utf-8")

    summary = review_summary(review, baseline)

    assert summary["ready_for_decisions"] is False
    assert summary["blockers"] == [{
        "baseline_record_key": "rk-1",
        "issue": "ukendt dubletmål",
    }]


def test_review_to_decisions_refuses_unreviewed_and_preserves_explicit_fields():
    review = {
        "entries": [{
            "baseline_record_key": "rk-1",
            "review_status": "accepteret",
            "candidate_id": "candidate-1",
            "post_index": 2,
            "calamari_span": {"char_from": 10, "char_to": 20},
            "calamari_verbatim_text": "kildetekst",
            "pdf_pages": [496],
            "kind": "line_header",
            "raw_char_from": 30,
            "raw_char_to": 40,
            "raw_verbatim_text": "råtekst",
            "raw_excerpt_sha256": hashlib.sha256("råtekst".encode("utf-8")).hexdigest(),
        }]
    }

    decisions = review_to_decisions(review)

    assert decisions == {"entries": [{
        "baseline_record_key": "rk-1",
        "candidate_id": "candidate-1",
        "post_index": 2,
        "calamari_span": {"char_from": 10, "char_to": 20},
        "calamari_verbatim_text": "kildetekst",
        "pdf_pages": [496],
        "kind": "line_header",
        "raw_char_from": 30,
        "raw_char_to": 40,
        "raw_verbatim_text": "råtekst",
        "raw_excerpt_sha256": hashlib.sha256("råtekst".encode("utf-8")).hexdigest(),
        "status": "accepteret",
    }]}
    with pytest.raises(ValueError, match="unreviewed"):
        review_to_decisions({"entries": [{"baseline_record_key": "rk-1", "review_status": "unreviewed"}]})
    with pytest.raises(ValueError, match="ukendt dubletmål"):
        review_to_decisions({"entries": [
            review["entries"][0],
            {
                "baseline_record_key": "rk-2",
                "review_status": "eksplicit_dublet",
                "duplicate_of_baseline_record_key": "missing",
            },
        ]})


def test_cli_converts_versioned_browser_choices_exclusively(tmp_path, capsys):
    choices = tmp_path / "choices.json"
    queue = tmp_path / "queue.json"
    candidates = tmp_path / "candidates.json"
    out = tmp_path / "new-decisions.json"
    manifest_source = {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }
    candidate = {
        "candidate_id": "c-1",
        "postklasse": "nummereret",
        "calamari_span": {"char_from": 10, "char_to": 20},
        "pdf_pages": [498],
        "raw_structure_bridge": {
            "kind": "record_start",
            "raw_char_from": 100,
            "raw_char_to": 110,
            "raw_excerpt_sha256": "e" * 64,
        },
    }
    choices.write_text(json.dumps({
        "schema_version": 1,
        "source": manifest_source,
        "baseline_sha256": "a" * 64,
        "exported_at": "2026-08-05T12:00:00+02:00",
        "entries": [{
            "baseline_record_key": "rk-1",
            "outcome": "human_selected_candidate",
            "candidate_id": "c-1",
            "decided_at": "2026-08-05T11:59:00+02:00",
        }],
    }), encoding="utf-8")
    queue.write_text(json.dumps({
        "schema_version": 1,
        "source": manifest_source,
        "entries": [{
            "baseline_record_key": "rk-1",
            "queue_class": "human_required",
            "reason_code": "multiple_candidates",
            "reason_da": "flere kandidater",
        }],
    }), encoding="utf-8")
    candidates.write_text(json.dumps({
        "c-1": {"baseline_record_key": "rk-1", "candidate": candidate}
    }), encoding="utf-8")

    assert main([
        "--choices-to-decisions", str(choices),
        "--queue-manifest", str(queue),
        "--anchored-candidates", str(candidates),
        "--out", str(out),
    ]) == 0

    assert json.loads(out.read_text(encoding="utf-8")) == {
        "decisions": [{
            "baseline_record_key": "rk-1",
            "status": "accepteret",
            "candidate_id": "c-1",
        }],
        "audit_results": [],
    }
    assert json.loads(capsys.readouterr().out) == {
        "out": str(out), "decisions": 1, "audit_results": 0,
    }
    with pytest.raises(FileExistsError):
        main([
            "--choices-to-decisions", str(choices),
            "--queue-manifest", str(queue),
            "--anchored-candidates", str(candidates),
            "--out", str(out),
        ])


def test_cli_choice_conversion_ignores_browser_draft_placeholders(tmp_path, capsys):
    """convert_choice_export is a third live consumer of validate_choice_export.

    It only reads the validated `choices` / `final_legacy_entries` dicts, never
    the raw export entries — so a browser export containing draft placeholders
    (the real shape of the user's 546-entry file, 446 of them untouched) must
    convert cleanly and simply produce no decision for the untouched records.
    """
    choices = tmp_path / "choices.json"
    queue = tmp_path / "queue.json"
    candidates = tmp_path / "candidates.json"
    out = tmp_path / "new-decisions.json"
    manifest_source = {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }
    choices.write_text(json.dumps({
        "schema_version": 1,
        "source": manifest_source,
        "baseline_sha256": "a" * 64,
        "exported_at": "2026-08-05T12:00:00+02:00",
        "entries": [
            {
                "baseline_record_key": "rk-1",
                "outcome": "undecidable",
                "decided_at": "2026-08-05T11:59:00+02:00",
                "reason": "uklar kilde",
            },
            {"baseline_record_key": "rk-2", "draft": True},
        ],
    }), encoding="utf-8")
    queue.write_text(json.dumps({
        "schema_version": 1,
        "source": manifest_source,
        "entries": [
            {"baseline_record_key": "rk-1", "queue_class": "human_required",
             "reason_code": "no_candidate", "reason_da": "ingen kandidat"},
            {"baseline_record_key": "rk-2", "queue_class": "human_required",
             "reason_code": "no_candidate", "reason_da": "ingen kandidat"},
        ],
    }), encoding="utf-8")
    candidates.write_text(json.dumps({}), encoding="utf-8")

    assert main([
        "--choices-to-decisions", str(choices),
        "--queue-manifest", str(queue),
        "--anchored-candidates", str(candidates),
        "--out", str(out),
    ]) == 0

    assert json.loads(out.read_text(encoding="utf-8")) == {
        "decisions": [{
            "baseline_record_key": "rk-1",
            "status": "menneskeark",
            "reason": "undecidable:uklar kilde",
        }],
        "audit_results": [],
    }
    assert json.loads(capsys.readouterr().out) == {
        "out": str(out), "decisions": 1, "audit_results": 0,
    }


def test_cli_choice_conversion_rejects_stale_source_without_output(tmp_path):
    choices = tmp_path / "choices.json"
    queue = tmp_path / "queue.json"
    candidates = tmp_path / "candidates.json"
    out = tmp_path / "new-decisions.json"
    source_value = {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }
    stale = dict(source_value, raw_ocr_sha256="f" * 64)
    choices.write_text(json.dumps({
        "schema_version": 1, "source": stale,
        "exported_at": "2026-08-05T12:00:00+02:00",
        "entries": [{"baseline_record_key": "rk-1", "outcome": "undecidable",
                     "reason": "uklar kilde"}],
    }), encoding="utf-8")
    queue.write_text(json.dumps({
        "schema_version": 1, "source": source_value,
        "entries": [{"baseline_record_key": "rk-1", "queue_class": "human_required",
                     "reason_code": "multiple_candidates", "reason_da": "flere"}],
    }), encoding="utf-8")
    candidates.write_text("{}", encoding="utf-8")

    with pytest.raises(ValueError, match="source/version"):
        main([
            "--choices-to-decisions", str(choices),
            "--queue-manifest", str(queue),
            "--anchored-candidates", str(candidates),
            "--out", str(out),
        ])

    assert not out.exists()


@pytest.mark.parametrize("boundary", ["choice", "queue"])
@pytest.mark.parametrize("invalid_version", [True, 1.0, "1"])
def test_cli_choice_and_queue_schema_versions_require_exact_integer_one_without_output(
    tmp_path, boundary, invalid_version
):
    choices = tmp_path / "choices.json"
    queue = tmp_path / "queue.json"
    candidates = tmp_path / "candidates.json"
    out = tmp_path / "new-decisions.json"
    source_value = {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }
    choice_value = {
        "schema_version": invalid_version if boundary == "choice" else 1,
        "source": source_value,
        "exported_at": "2026-08-05T12:00:00+02:00",
        "entries": [{
            "baseline_record_key": "rk-1",
            "outcome": "undecidable",
            "reason": "uklar kilde",
        }],
    }
    queue_value = {
        "schema_version": invalid_version if boundary == "queue" else 1,
        "source": source_value,
        "entries": [{
            "baseline_record_key": "rk-1",
            "queue_class": "human_required",
            "reason_code": "multiple_candidates",
            "reason_da": "flere",
        }],
    }
    choices.write_text(json.dumps(choice_value), encoding="utf-8")
    queue.write_text(json.dumps(queue_value), encoding="utf-8")
    candidates.write_text("{}", encoding="utf-8")

    with pytest.raises(ValueError, match="schema_version|source/version"):
        main([
            "--choices-to-decisions", str(choices),
            "--queue-manifest", str(queue),
            "--anchored-candidates", str(candidates),
            "--out", str(out),
        ])

    assert not out.exists()


@pytest.mark.parametrize(
    "raw_choices",
    [
        (
            '{"schema_version":1,"schema_version":2,"source":{SOURCE},'
            '"exported_at":"2026-08-05T12:00:00+02:00","entries":[ENTRY]}'
        ),
        (
            '{"schema_version":1,"source":{"edition":"1939","edition":"1940",'
            '"baseline_sha256":"' + ("a" * 64) + '","calamari_sha256":"' +
            ("b" * 64) + '","raw_ocr_sha256":"' + ("c" * 64) +
            '","pdf_sha256":"' + ("d" * 64) + '","profile_version":"1939-v2"},'
            '"exported_at":"2026-08-05T12:00:00+02:00","entries":[ENTRY]}'
        ),
        (
            '{"schema_version":1,"source":{SOURCE},'
            '"exported_at":"2026-08-05T12:00:00+02:00","entries":['
            '{"baseline_record_key":"rk-1","outcome":"undecidable",'
            '"outcome":"human_selected_candidate","reason":"uklar kilde"}]}'
        ),
        (
            '{"schema_version":1,"source":{SOURCE},'
            '"exported_at":"2026-08-05T12:00:00+02:00","entries":['
            '{"baseline_record_key":"rk-1","review_status":"unreviewed",'
            '"baseline_locator":{"pages":"498","pages":"499","local_id":null}}]}'
        ),
    ],
    ids=["duplicate-root", "duplicate-source", "duplicate-outcome", "duplicate-nested"],
)
def test_cli_choice_json_rejects_every_recursive_duplicate_key_before_output(
    tmp_path, raw_choices
):
    choices = tmp_path / "choices.json"
    queue = tmp_path / "queue.json"
    candidates = tmp_path / "candidates.json"
    out = tmp_path / "new-decisions.json"
    source_value = {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }
    source_json = json.dumps(source_value, ensure_ascii=False)
    entry_json = json.dumps({
        "baseline_record_key": "rk-1",
        "outcome": "undecidable",
        "reason": "uklar kilde",
    }, ensure_ascii=False)
    choices.write_text(
        raw_choices.replace("{SOURCE}", source_json).replace("ENTRY", entry_json),
        encoding="utf-8",
    )
    queue.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "entries": [{
            "baseline_record_key": "rk-1",
            "queue_class": "human_required",
            "reason_code": "multiple_candidates",
            "reason_da": "flere",
        }],
    }), encoding="utf-8")
    candidates.write_text("{}", encoding="utf-8")

    with pytest.raises(ValueError, match="dublet JSON-nøgle"):
        main([
            "--choices-to-decisions", str(choices),
            "--queue-manifest", str(queue),
            "--anchored-candidates", str(candidates),
            "--out", str(out),
        ])

    assert not out.exists()


@pytest.mark.parametrize(
    "raw_queue",
    [
        (
            '{"schema_version":2,"schema_version":1,"source":{SOURCE},'
            '"entries":[ENTRY]}'
        ),
        (
            '{"schema_version":1,"source":{"edition":"1939",'
            '"baseline_sha256":"' + ("f" * 64) + '","baseline_sha256":"' +
            ("a" * 64) + '","calamari_sha256":"' + ("b" * 64) +
            '","raw_ocr_sha256":"' + ("c" * 64) + '","pdf_sha256":"' +
            ("d" * 64) + '","profile_version":"1939-v2"},"entries":[ENTRY]}'
        ),
        (
            '{"schema_version":1,"source":{SOURCE},"entries":['
            '{"baseline_record_key":"rk-1","queue_class":"auto_resolved",'
            '"queue_class":"human_required","reason_code":"multiple_candidates",'
            '"reason_da":"flere"}]}'
        ),
    ],
    ids=["duplicate-root", "duplicate-source", "duplicate-entry"],
)
def test_cli_queue_json_rejects_every_recursive_duplicate_key_before_sampling_or_output(
    tmp_path, raw_queue
):
    choices = tmp_path / "choices.json"
    queue = tmp_path / "queue.json"
    candidates = tmp_path / "candidates.json"
    out = tmp_path / "new-decisions.json"
    source_value = {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }
    choices.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "exported_at": "2026-08-05T12:00:00+02:00",
        "entries": [{
            "baseline_record_key": "rk-1",
            "outcome": "undecidable",
            "reason": "uklar kilde",
        }],
    }), encoding="utf-8")
    queue.write_text(
        raw_queue.replace("{SOURCE}", json.dumps(source_value)).replace(
            "ENTRY",
            json.dumps({
                "baseline_record_key": "rk-1",
                "queue_class": "human_required",
                "reason_code": "multiple_candidates",
                "reason_da": "flere",
            }),
        ),
        encoding="utf-8",
    )
    candidates.write_text("{}", encoding="utf-8")

    with pytest.raises(ValueError, match="dublet JSON-nøgle i queue manifest"):
        main([
            "--choices-to-decisions", str(choices),
            "--queue-manifest", str(queue),
            "--anchored-candidates", str(candidates),
            "--out", str(out),
        ])

    assert not out.exists()


def test_cli_choice_conversion_rejects_duplicate_candidate_ids_in_json(tmp_path):
    choices = tmp_path / "choices.json"
    queue = tmp_path / "queue.json"
    candidates = tmp_path / "candidates.json"
    out = tmp_path / "new-decisions.json"
    source_value = {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }
    choices.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "exported_at": "2026-08-05T12:00:00+02:00",
        "entries": [{
            "baseline_record_key": "rk-1",
            "outcome": "human_selected_candidate",
            "candidate_id": "c-1",
        }],
    }), encoding="utf-8")
    queue.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "entries": [{
            "baseline_record_key": "rk-1",
            "queue_class": "human_required",
            "reason_code": "multiple_candidates",
            "reason_da": "flere",
        }],
    }), encoding="utf-8")
    wrapper = json.dumps({
        "baseline_record_key": "rk-1",
        "candidate": {
            "candidate_id": "c-1",
            "postklasse": "nummereret",
            "calamari_span": {"char_from": 10, "char_to": 20},
            "pdf_pages": [498],
            "raw_structure_bridge": {
                "kind": "record_start",
                "raw_char_from": 100,
                "raw_char_to": 110,
                "raw_excerpt_sha256": "e" * 64,
            },
        },
    })
    candidates.write_text('{"c-1":' + wrapper + ',"c-1":' + wrapper + '}', encoding="utf-8")

    with pytest.raises(ValueError, match="dublet candidate_id"):
        main([
            "--choices-to-decisions", str(choices),
            "--queue-manifest", str(queue),
            "--anchored-candidates", str(candidates),
            "--out", str(out),
        ])

    assert not out.exists()


def _write_nested_duplicate_candidate_case(tmp_path, selected_id, anchored_json):
    choices = tmp_path / "choices.json"
    queue = tmp_path / "queue.json"
    candidates = tmp_path / "candidates.json"
    out = tmp_path / "new-decisions.json"
    source_value = {
        "edition": "1939",
        "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }
    key = "rk-good" if selected_id == "c-good" else "rk-bad"
    choices.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "exported_at": "2026-08-05T12:00:00+02:00",
        "entries": [{
            "baseline_record_key": key,
            "outcome": "human_selected_candidate",
            "candidate_id": selected_id,
        }],
    }), encoding="utf-8")
    queue.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "entries": [{
            "baseline_record_key": key,
            "queue_class": "human_required",
            "reason_code": "multiple_candidates",
            "reason_da": "flere",
        }],
    }), encoding="utf-8")
    candidates.write_text(anchored_json, encoding="utf-8")
    return choices, queue, candidates, out


def _raw_wrapper(candidate_id, owner, *, duplicate_postklasse=False):
    repeated = ',"postklasse":"nummereret"' if duplicate_postklasse else ""
    return (
        '{"baseline_record_key":' + json.dumps(owner) + ',"candidate":{'
        '"candidate_id":' + json.dumps(candidate_id) + ','
        '"postklasse":"nummereret"' + repeated + ','
        '"calamari_span":{"char_from":10,"char_to":20},'
        '"pdf_pages":[498],'
        '"raw_structure_bridge":{"kind":"record_start","raw_char_from":100,'
        '"raw_char_to":110,"raw_excerpt_sha256":"' + ("e" * 64) + '"}}}'
    )


def test_cli_ignores_nested_duplicate_in_unused_candidate_wrapper(tmp_path):
    anchored_json = (
        '{"c-good":' + _raw_wrapper("c-good", "rk-good")
        + ',"c-bad":' + _raw_wrapper(
            "c-bad", "rk-bad", duplicate_postklasse=True
        ) + '}'
    )
    choices, queue, candidates, out = _write_nested_duplicate_candidate_case(
        tmp_path, "c-good", anchored_json
    )

    assert main([
        "--choices-to-decisions", str(choices),
        "--queue-manifest", str(queue),
        "--anchored-candidates", str(candidates),
        "--out", str(out),
    ]) == 0

    assert json.loads(out.read_text(encoding="utf-8"))["decisions"] == [{
        "baseline_record_key": "rk-good",
        "status": "accepteret",
        "candidate_id": "c-good",
    }]


def test_cli_parks_selected_wrapper_with_nested_duplicate(tmp_path):
    anchored_json = '{"c-bad":' + _raw_wrapper(
        "c-bad", "rk-bad", duplicate_postklasse=True
    ) + '}'
    choices, queue, candidates, out = _write_nested_duplicate_candidate_case(
        tmp_path, "c-bad", anchored_json
    )

    assert main([
        "--choices-to-decisions", str(choices),
        "--queue-manifest", str(queue),
        "--anchored-candidates", str(candidates),
        "--out", str(out),
    ]) == 0

    assert json.loads(out.read_text(encoding="utf-8"))["decisions"] == [{
        "baseline_record_key": "rk-bad",
        "status": "menneskeark",
        "reason": "human_selected_candidate_requires_exact_anchor:c-bad",
    }]


def test_cli_never_promotes_selected_presentation_candidate(tmp_path):
    candidate_id = "presentation:1939-v2:post:7"
    anchored_json = json.dumps({
        candidate_id: {
            "baseline_record_key": "rk-bad",
            "candidate": {
                "candidate_id": candidate_id,
                "postklasse": "nummereret",
                "calamari_span": {"char_from": 10, "char_to": 20},
                "pdf_pages": [498],
                "raw_structure_bridge": {
                    "kind": "record_start",
                    "raw_char_from": 100,
                    "raw_char_to": 110,
                    "raw_excerpt_sha256": "e" * 64,
                },
            },
        },
    })
    choices, queue, candidates, out = _write_nested_duplicate_candidate_case(
        tmp_path, candidate_id, anchored_json
    )

    assert main([
        "--choices-to-decisions", str(choices),
        "--queue-manifest", str(queue),
        "--anchored-candidates", str(candidates),
        "--out", str(out),
    ]) == 0

    assert json.loads(out.read_text(encoding="utf-8"))["decisions"] == [{
        "baseline_record_key": "rk-bad",
        "status": "menneskeark",
        "reason": (
            "human_selected_candidate_is_presentation_only:"
            "presentation:1939-v2:post:7"
        ),
    }]
