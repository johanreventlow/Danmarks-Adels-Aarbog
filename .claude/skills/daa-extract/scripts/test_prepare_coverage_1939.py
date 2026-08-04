import json
import hashlib

import pytest

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
